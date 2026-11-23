----------
--ESTRAL--
----------

require "CarClaimSystem_Core"
require "CarClaimSystem_Perms"
require "CarClaimSystem_Net"
require "CarClaimSystem_State"

if not CarClaimSystem.isAuthority() then return end

-- what a client can ask for.
--
-- a handler is handed the player the engine says sent the packet, and takes every name from
-- that, never from the packet. args is whatever the client typed: each field is checked where
-- it is used.

CarClaimSystem_Commands = CarClaimSystem_Commands or {}

CarClaimSystem_Commands.handlers = {}

-- target username -> { key, from, vehicle, at }. one offer at a time per recipient, and never
-- saved: an offer does not outlive a restart.
CarClaimSystem_Commands.offers = CarClaimSystem_Commands.offers or {}

-- milliseconds between two of the same command from one player.
local FLOOR = 200
local lastAt = {}

local function CarClaimSystem_allowed(username, command, now)
    local times = lastAt[username]

    if not times then
        times = {}
        lastAt[username] = times
    end

    if now - (times[command] or 0) < FLOOR then return false end

    times[command] = now
    return true
end

local function CarClaimSystem_reply(player, ok, code, a1)
    CarClaimSystem_Net.toClient(player, "result", { ok = ok == true, code = code, a1 = a1 })
end

local function CarClaimSystem_vehicle(args)
    local id = tonumber(args.vehicle)
    if not id then return nil end

    return getVehicleById(id)
end

local function CarClaimSystem_username(value)
    if type(value) ~= "string" or value == "" or #value > 64 then return nil end
    return value
end

local function CarClaimSystem_adminLog(player, text)
    local line = tostring(CarClaimSystem.nameOf(player)) .. " " .. text

    CarClaimSystem.log("admin: " .. line)
    if writeLog then writeLog("admin", "[CarClaimSystem] " .. line) end
end

-- the vehicle the packet names and the claim on it, when the sender owns that claim. answers
-- for itself when they do not.
local function CarClaimSystem_owned(player, args)
    local vehicle = CarClaimSystem_vehicle(args)
    if not vehicle then
        CarClaimSystem_reply(player, false, "NoVehicle")
        return nil
    end

    local claim = CarClaimSystem_State.claimOf(vehicle)
    if not claim or claim.owner ~= CarClaimSystem.nameOf(player) then
        CarClaimSystem_reply(player, false, "NotOwner")
        return nil
    end

    return vehicle, claim
end

local function CarClaimSystem_holdsKey(player, vehicle)
    if vehicle:isHotwired() or vehicle:isKeysInIgnition() then return true end

    return player:getInventory():haveThisKeyId(vehicle:getKeyId()) ~= nil
end

function CarClaimSystem_Commands.handlers.claim(player, args)
    local username = CarClaimSystem.nameOf(player)
    local vehicle = CarClaimSystem_vehicle(args)

    if not vehicle then return CarClaimSystem_reply(player, false, "NoVehicle") end

    if player:DistToProper(vehicle) > CarClaimSystem.CLAIM_RANGE and player:getVehicle() ~= vehicle then
        return CarClaimSystem_reply(player, false, "TooFar")
    end

    if CarClaimSystem.isWreck(vehicle) then return CarClaimSystem_reply(player, false, "Wreck") end

    if not CarClaimSystem_State.keyOf(vehicle) then
        return CarClaimSystem_reply(player, false, "NotReady")
    end

    local existing = CarClaimSystem_State.claimOf(vehicle)
    if existing then return CarClaimSystem_reply(player, false, "AlreadyClaimed", existing.owner) end

    if CarClaimSystem_State.atCap(username) then return CarClaimSystem_reply(player, false, "AtCap") end

    if CarClaimSystem.isTrailer(vehicle) then
        local puller = vehicle:getVehicleTowedBy()
        local pullerClaim = puller and CarClaimSystem_State.claimOf(puller)

        if not pullerClaim or pullerClaim.owner ~= username then
            return CarClaimSystem_reply(player, false, "TrailerNeedsCar")
        end
    elseif not CarClaimSystem_holdsKey(player, vehicle) then
        return CarClaimSystem_reply(player, false, "NeedKey")
    end

    CarClaimSystem_State.create(vehicle, username)
    CarClaimSystem_reply(player, true, "Claimed")
end

function CarClaimSystem_Commands.handlers.release(player, args)
    local vehicle = CarClaimSystem_owned(player, args)
    if not vehicle then return end

    CarClaimSystem_State.release(vehicle)
    CarClaimSystem_reply(player, true, "Released")
end

-- sets one player's flags. a first grant needs them online: that is the only proof the name
-- is somebody. an entry that already exists can be edited whether they are on or not.
function CarClaimSystem_Commands.handlers.setPlayer(player, args)
    local vehicle, claim = CarClaimSystem_owned(player, args)
    if not vehicle then return end

    local target = CarClaimSystem_username(args.target)
    if not target or target == claim.owner then
        return CarClaimSystem_reply(player, false, "NoSuchPlayer")
    end

    if not claim.players[target] and not CarClaimSystem_State.playerNamed(target) then
        return CarClaimSystem_reply(player, false, "NoSuchPlayer")
    end

    claim.players[target] = CarClaimSystem_Perms.clean(args.flags)

    CarClaimSystem_State.touch(claim)
    CarClaimSystem_State.stamp(vehicle)
    CarClaimSystem_reply(player, true, "Saved")
end

-- takes a player's own entry away, which puts them back on whatever their groups allow.
function CarClaimSystem_Commands.handlers.removePlayer(player, args)
    local vehicle, claim = CarClaimSystem_owned(player, args)
    if not vehicle then return end

    local target = CarClaimSystem_username(args.target)
    if not target or not claim.players[target] then
        return CarClaimSystem_reply(player, false, "NoSuchPlayer")
    end

    claim.players[target] = nil

    CarClaimSystem_State.touch(claim)
    CarClaimSystem_State.stamp(vehicle)
    CarClaimSystem_reply(player, true, "Saved")
end

function CarClaimSystem_Commands.handlers.setGroup(player, args)
    local vehicle, claim = CarClaimSystem_owned(player, args)
    if not vehicle then return end

    if args.group ~= "faction" and args.group ~= "safehouse" then
        return CarClaimSystem_reply(player, false, "Failed")
    end

    claim[args.group] = CarClaimSystem_Perms.clean(args.flags)

    CarClaimSystem_State.touch(claim)
    CarClaimSystem_State.stamp(vehicle)
    CarClaimSystem_reply(player, true, "Saved")
end

-- every vehicle the sender has claimed, loaded or not, for the list window. a loaded one is
-- noted first, so its place is where it is now rather than at the last sweep. a vehicle that
-- has not been loaded since the claim was made, under a build that did not keep the place,
-- goes without one.
function CarClaimSystem_Commands.handlers.list(player, args)
    local username = CarClaimSystem.nameOf(player)
    local owned = CarClaimSystem_State.claimsOf(username)

    local loaded = {}
    if #owned > 0 then
        CarClaimSystem_State.eachVehicle(function(vehicle)
            local claim = CarClaimSystem_State.claimOf(vehicle)
            if claim and claim.owner == username then
                CarClaimSystem_State.note(vehicle, claim)
                loaded[claim] = vehicle
            end
        end)
    end

    local now = CarClaimSystem.now()
    local vehicles = {}

    for _, entry in ipairs(owned) do
        local claim = entry.claim
        local vehicle = loaded[claim]

        vehicles[#vehicles + 1] = {
            key = entry.key,
            script = claim.script,
            x = claim.x,
            y = claim.y,
            z = claim.z,
            ago = claim.seenAt and math.max(0, now - claim.seenAt) or nil,
            loaded = vehicle ~= nil,
            id = vehicle and vehicle:getId() or nil,
        }
    end

    CarClaimSystem_Net.toClient(player, "claims", {
        vehicles = vehicles,
        count = #vehicles,
        cap = CarClaimSystem_State.cap(),
    })
end

-- asks an online player to take the vehicle. nothing changes until they say yes.
function CarClaimSystem_Commands.handlers.offer(player, args)
    local vehicle, claim = CarClaimSystem_owned(player, args)
    if not vehicle then return end

    local target = CarClaimSystem_username(args.target)
    local targetPlayer = target and target ~= claim.owner and CarClaimSystem_State.playerNamed(target)
    if not targetPlayer then return CarClaimSystem_reply(player, false, "NoSuchPlayer") end

    local now = CarClaimSystem.now()
    local pending = CarClaimSystem_Commands.offers[target]
    if pending and now - pending.at < CarClaimSystem.OFFER_MS then
        return CarClaimSystem_reply(player, false, "OfferBusy", target)
    end

    if CarClaimSystem_State.atCap(target) then
        return CarClaimSystem_reply(player, false, "TargetAtCap", target)
    end

    CarClaimSystem_Commands.offers[target] = {
        key = CarClaimSystem_State.keyOf(vehicle),
        from = claim.owner,
        vehicle = vehicle:getId(),
        at = now,
    }

    CarClaimSystem_Net.toClient(targetPlayer, "offer", { from = claim.owner, vehicle = vehicle:getId() })
    CarClaimSystem_reply(player, true, "Offered", target)
end

local function CarClaimSystem_tell(username, ok, code, a1)
    local player = CarClaimSystem_State.playerNamed(username)
    if player then CarClaimSystem_reply(player, ok, code, a1) end
end

function CarClaimSystem_Commands.handlers.answer(player, args)
    local username = CarClaimSystem.nameOf(player)
    local offer = CarClaimSystem_Commands.offers[username]

    if not offer then return CarClaimSystem_reply(player, false, "OfferExpired") end
    CarClaimSystem_Commands.offers[username] = nil

    if CarClaimSystem.now() - offer.at >= CarClaimSystem.OFFER_MS then
        return CarClaimSystem_reply(player, false, "OfferExpired")
    end

    if args.accept ~= true then
        CarClaimSystem_tell(offer.from, false, "OfferDeclined", username)
        return
    end

    -- the offer is held against what is true now, not what was true when it was made.
    local claim = CarClaimSystem_State.ensure().claims[offer.key]
    local vehicle = getVehicleById(offer.vehicle)

    if not claim or claim.owner ~= offer.from or not vehicle
        or CarClaimSystem_State.keyOf(vehicle) ~= offer.key then
        return CarClaimSystem_reply(player, false, "OfferExpired")
    end

    if CarClaimSystem_State.atCap(username) then
        CarClaimSystem_tell(offer.from, false, "TargetAtCap", username)
        return CarClaimSystem_reply(player, false, "AtCap")
    end

    CarClaimSystem_State.reassign(vehicle, claim, username)

    CarClaimSystem_reply(player, true, "TransferIn", offer.from)
    CarClaimSystem_tell(offer.from, true, "TransferOut", username)
end

-- offers nobody answered. called from the server clock.
function CarClaimSystem_Commands.expireOffers(now)
    for target, offer in pairs(CarClaimSystem_Commands.offers) do
        if now - offer.at >= CarClaimSystem.OFFER_MS then
            CarClaimSystem_Commands.offers[target] = nil
            CarClaimSystem_tell(offer.from, false, "OfferUnanswered", target)
        end
    end
end

function CarClaimSystem_Commands.handlers.adminRelease(player, args)
    if not CarClaimSystem.isAdmin(player) then return CarClaimSystem_reply(player, false, "NotOwner") end

    local vehicle = CarClaimSystem_vehicle(args)
    local claim = vehicle and CarClaimSystem_State.claimOf(vehicle)
    if not claim then return CarClaimSystem_reply(player, false, "NoVehicle") end

    CarClaimSystem_adminLog(player, "released the claim " .. tostring(claim.owner) .. " held on "
        .. tostring(CarClaimSystem_State.keyOf(vehicle)))

    CarClaimSystem_State.release(vehicle)
    CarClaimSystem_reply(player, true, "Released")
end

function CarClaimSystem_Commands.handlers.adminReassign(player, args)
    if not CarClaimSystem.isAdmin(player) then return CarClaimSystem_reply(player, false, "NotOwner") end

    local vehicle = CarClaimSystem_vehicle(args)
    local claim = vehicle and CarClaimSystem_State.claimOf(vehicle)
    if not claim then return CarClaimSystem_reply(player, false, "NoVehicle") end

    local target = CarClaimSystem_username(args.target)
    if not target or not CarClaimSystem_State.playerNamed(target) then
        return CarClaimSystem_reply(player, false, "NoSuchPlayer")
    end

    CarClaimSystem_adminLog(player, "moved " .. tostring(CarClaimSystem_State.keyOf(vehicle))
        .. " from " .. tostring(claim.owner) .. " to " .. target)

    CarClaimSystem_State.reassign(vehicle, claim, target)
    CarClaimSystem_reply(player, true, "Saved")
    CarClaimSystem_tell(target, true, "TransferIn", CarClaimSystem.nameOf(player))
end

-- a command inside its floor is dropped without a word: it is a double-click. args is whatever
-- the client typed, so it is made a table here, once. in singleplayer CarClaimSystem_Net calls
-- the handlers itself, with a table.
local function CarClaimSystem_onClientCommand(module, command, player, args)
    if module ~= CarClaimSystem.MODULE then return end

    local handler = CarClaimSystem_Commands.handlers[command]
    if not handler or not player then return end

    local username = CarClaimSystem.nameOf(player)
    if not username then return end

    if not CarClaimSystem_allowed(username, command, getTimestampMs()) then return end

    local ok, err = pcall(handler, player, type(args) == "table" and args or {})
    if not ok then
        CarClaimSystem.warn("command " .. tostring(command) .. " failed: " .. tostring(err))
        CarClaimSystem_reply(player, false, "Failed")
    end
end

Events.OnClientCommand.Add(CarClaimSystem_onClientCommand)
