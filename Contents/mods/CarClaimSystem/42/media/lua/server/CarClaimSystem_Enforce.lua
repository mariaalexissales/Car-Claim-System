----------
--ESTRAL--
----------

require "CarClaimSystem_Core"
require "CarClaimSystem_Perms"
require "CarClaimSystem_Net"
require "CarClaimSystem_State"
require "CarClaimSystem_Commands"
require "CarClaimSystem_IdleShutoff"

if not CarClaimSystem.isAuthority() then return end

-- the parts of a claim the game gives the server no way to refuse up front.
--
-- getting into a seat, changing seat and hitching a trailer all happen on the server without
-- any lua being asked. so they are caught after the fact: once a second everyone sitting in a
-- vehicle is checked, and a hitch is undone the moment its command has run.

CarClaimSystem_Enforce = CarClaimSystem_Enforce or {}

local SEAT_MS = 1000
local SWEEP_MS = 60000
local EJECT_MS = 3000
local DAY_MS = 86400000

-- km/h under which somebody can be put out of a car without being hurt.
local STOPPED = 1

local lastSeat = 0
local lastSweep = 0
local lastEject = {}

-- vehicle id -> { a, b, attA, attB }, filed under both ends. a is the one pulling. kept so an
-- unhitch by someone who may not tow can be put back, which needs the two attachment names.
CarClaimSystem_Enforce.tows = CarClaimSystem_Enforce.tows or {}

-- the driver's seat is the Drive flag and every other seat is the Passenger flag, the same
-- rule the client uses before it lets anyone climb in.
local function CarClaimSystem_maySit(player, vehicle)
    return CarClaimSystem.can(player, vehicle, CarClaimSystem.seatFlag(vehicle:getSeat(player)))
end

-- somebody is sitting where they may not. the engine goes off at once; they are only put out
-- when the car has all but stopped, so a revoke never throws anyone onto the road at speed.
function CarClaimSystem_Enforce.checkSeat(player, now)
    local vehicle = player:getVehicle()
    if not vehicle or CarClaimSystem_maySit(player, vehicle) then return end

    if vehicle:isDriver(player) and vehicle:isEngineRunning() then vehicle:shutOff() end

    if math.abs(vehicle:getCurrentSpeedKmHour()) >= STOPPED then return end

    local username = CarClaimSystem.nameOf(player) or "?"
    if now - (lastEject[username] or 0) < EJECT_MS then return end
    lastEject[username] = now

    local claim = CarClaimSystem_State.claimOf(vehicle)
    CarClaimSystem_Net.toClient(player, "forceExit", { owner = claim and claim.owner })
end

local function CarClaimSystem_remember(a, b, attA, attB)
    local record = { a = a:getId(), b = b:getId(), attA = attA, attB = attB }

    CarClaimSystem_Enforce.tows[record.a] = record
    CarClaimSystem_Enforce.tows[record.b] = record
end

local function CarClaimSystem_forget(record)
    CarClaimSystem_Enforce.tows[record.a] = nil
    CarClaimSystem_Enforce.tows[record.b] = nil
end

local function CarClaimSystem_mayTow(player, a, b)
    return CarClaimSystem.can(player, a, "tow") and CarClaimSystem.can(player, b, "tow")
end

-- runs after vanilla's own handler for the same command, which has already hitched the two.
function CarClaimSystem_Enforce.onAttach(player, args)
    local a = getVehicleById(tonumber(args.vehicleA) or -1)
    local b = getVehicleById(tonumber(args.vehicleB) or -1)
    if not a or not b then return end

    if CarClaimSystem_mayTow(player, a, b) then
        CarClaimSystem_remember(a, b, args.attachmentA, args.attachmentB)
        return
    end

    a:breakConstraint(true, false)
    CarClaimSystem.log(tostring(CarClaimSystem.nameOf(player)) .. " hitched a claimed vehicle without leave; undone")
end

-- and this one after vanilla has already let go. the hitch is put back from what was
-- remembered when it was made, or when the sweep last saw it.
function CarClaimSystem_Enforce.onDetach(player, args)
    local record = CarClaimSystem_Enforce.tows[tonumber(args.vehicle) or -1]
    if not record then return end

    local a = getVehicleById(record.a)
    local b = getVehicleById(record.b)

    if not a or not b or CarClaimSystem_mayTow(player, a, b) then
        CarClaimSystem_forget(record)
        return
    end

    if not a:getVehicleTowing() then
        a:addPointConstraint(nil, b, record.attA, record.attB)
    end

    CarClaimSystem.log(tostring(CarClaimSystem.nameOf(player)) .. " unhitched a claimed vehicle without leave; put back")
end

local function CarClaimSystem_onClientCommand(module, command, player, args)
    if module ~= "vehicle" or not player or type(args) ~= "table" then return end

    if command == "attachTrailer" then
        CarClaimSystem_Enforce.onAttach(player, args)
    elseif command == "detachTrailer" then
        CarClaimSystem_Enforce.onDetach(player, args)
    end
end

-- claims whose owner has not been on for longer than the server allows. 0 is never.
function CarClaimSystem_Enforce.expire(now)
    local days = CarClaimSystem.option("InactivityDays", 30)
    if days <= 0 then return end

    local claims = CarClaimSystem_State.ensure().claims
    local dead = {}

    for key, claim in pairs(claims) do
        if now - (claim.lastSeen or now) > days * DAY_MS then dead[#dead + 1] = key end
    end

    for _, key in ipairs(dead) do
        CarClaimSystem.log("claim " .. key .. " held by " .. tostring(claims[key].owner) .. " lapsed")
        claims[key] = nil
    end
end

-- once a minute: owners who are on are marked as seen, old claims lapse, and every loaded
-- vehicle is looked over. a wreck loses its claim; a stamped copy that is not the server's is
-- stamped again, which is also how a lapsed claim leaves a vehicle that was not loaded then;
-- a hitch made before the last restart is learned again.
function CarClaimSystem_Enforce.sweep(now)
    local online = {}
    CarClaimSystem_State.eachPlayer(function(player)
        local username = CarClaimSystem.nameOf(player)
        if username then online[username] = true end
    end)

    for _, claim in pairs(CarClaimSystem_State.ensure().claims) do
        if online[claim.owner] then claim.lastSeen = now end
    end

    CarClaimSystem_Enforce.expire(now)
    CarClaimSystem_Commands.expireOffers(now)

    CarClaimSystem_State.eachVehicle(function(vehicle)
        if CarClaimSystem_State.claimOf(vehicle) and CarClaimSystem.isWreck(vehicle) then
            CarClaimSystem_State.release(vehicle)
        elseif CarClaimSystem_State.stale(vehicle) then
            CarClaimSystem_State.stamp(vehicle)
        end

        local towed = vehicle:getVehicleTowing()
        if towed and not CarClaimSystem_Enforce.tows[vehicle:getId()] then
            CarClaimSystem_remember(vehicle, towed, vehicle:getTowAttachmentSelf(), vehicle:getTowAttachmentOther())
        end

        CarClaimSystem_IdleShutoff.check(vehicle, now)
    end)

    CarClaimSystem_IdleShutoff.prune(now)
end

local function CarClaimSystem_tick()
    local now = CarClaimSystem.now()

    if now - lastSeat >= SEAT_MS then
        lastSeat = now
        CarClaimSystem_State.eachPlayer(function(player)
            CarClaimSystem_Enforce.checkSeat(player, now)
        end)
    end

    if now - lastSweep >= SWEEP_MS then
        lastSweep = now
        CarClaimSystem_Enforce.sweep(now)
    end
end

Events.OnClientCommand.Add(CarClaimSystem_onClientCommand)
CarClaimSystem.guard("claim clock", Events.OnTick, CarClaimSystem_tick)
