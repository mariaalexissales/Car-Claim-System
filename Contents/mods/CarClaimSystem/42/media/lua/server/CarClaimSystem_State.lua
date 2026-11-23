----------
--ESTRAL--
----------

require "CarClaimSystem_Core"
require "CarClaimSystem_Perms"

if not CarClaimSystem.isAuthority() then return end

CarClaimSystem_State = CarClaimSystem_State or {}

local TABLE_NAME = "CarClaimSystem_State"
local LOCAL_ID = "CarClaimSystemId"

CarClaimSystem_State.data = CarClaimSystem_State.data or nil

-- global mod data, and never transmitted. a vehicle's own mod data cannot hold the claim: any
-- client can overwrite it, and the server takes the packet as it comes. so the claim lives
-- here, and the vehicle only carries a copy for clients to draw their menus from.
--
--   claims   key -> { owner, rev, lastSeen, players, faction, safehouse }
--            owner      account name
--            rev        moves on every change; the stamped copy is compared against it
--            lastSeen   epoch ms the owner was last online, for the inactivity timer
--            players    username -> flags. an empty table is a player kept out on purpose
--            faction    flags for whoever is in the owner's faction right now
--            safehouse  flags for whoever shares a safehouse with the owner right now
--            script     the vehicle's script name, for the owner's list
--            x, y, z    the tile it was on when the server last had it loaded
--            seenAt     epoch ms of that sighting. claims made before these were kept have
--                       none of the four until the vehicle is next loaded
function CarClaimSystem_State.ensure()
    if not CarClaimSystem_State.data then
        CarClaimSystem_State.data = ModData.getOrCreate(TABLE_NAME)
    end

    local data = CarClaimSystem_State.data
    data.claims = data.claims or {}

    return data
end

-- what a vehicle's claim is filed under. the database id is the only one that is the same
-- after a restart and that a client cannot change, but singleplayer does not always have one,
-- and there nobody else can write the mod data either.
function CarClaimSystem_State.keyOf(vehicle)
    local sqlId = vehicle:getSqlId()
    if sqlId and sqlId >= 0 then return "s" .. tostring(sqlId) end

    if isServer() then return nil end

    local md = vehicle:getModData()
    if not md[LOCAL_ID] then
        md[LOCAL_ID] = "l" .. tostring(CarClaimSystem.now()) .. "_" .. tostring(ZombRand(1000000))
    end

    return md[LOCAL_ID]
end

function CarClaimSystem_State.claimOf(vehicle)
    local key = CarClaimSystem_State.keyOf(vehicle)
    if not key then return nil end

    return CarClaimSystem_State.ensure().claims[key]
end

function CarClaimSystem_State.countOf(owner)
    local count = 0

    for _, claim in pairs(CarClaimSystem_State.ensure().claims) do
        if claim.owner == owner then count = count + 1 end
    end

    return count
end

-- every claim one account holds, as { key, claim } pairs.
function CarClaimSystem_State.claimsOf(owner)
    local out = {}

    for key, claim in pairs(CarClaimSystem_State.ensure().claims) do
        if claim.owner == owner then out[#out + 1] = { key = key, claim = claim } end
    end

    return out
end

function CarClaimSystem_State.cap()
    return CarClaimSystem.option("MaxClaimsPerPlayer", 3)
end

-- 0 is no limit.
function CarClaimSystem_State.atCap(owner)
    local cap = CarClaimSystem_State.cap()
    return cap > 0 and CarClaimSystem_State.countOf(owner) >= cap
end

-- what the vehicle is and where it stands, kept on the record so the owner's list can name a
-- vehicle that is not loaded. not part of the stamped copy, and no change to rev: nobody's
-- permissions moved.
function CarClaimSystem_State.note(vehicle, claim)
    claim = claim or CarClaimSystem_State.claimOf(vehicle)
    if not claim then return end

    claim.script = vehicle:getScriptName()
    claim.x = math.floor(vehicle:getX())
    claim.y = math.floor(vehicle:getY())
    claim.z = math.floor(vehicle:getZ())
    claim.seenAt = CarClaimSystem.now()
end

local function CarClaimSystem_copyPlayers(players)
    local out = {}

    for username, flags in pairs(players or {}) do
        out[username] = CarClaimSystem_Perms.clean(flags)
    end

    return out
end

-- writes the public copy of the vehicle's claim into its mod data and sends it to the clients
-- near it. a copy, not the record: the two are saved in different places.
function CarClaimSystem_State.stamp(vehicle)
    local md = vehicle:getModData()
    local claim = CarClaimSystem_State.claimOf(vehicle)

    if claim then
        md[CarClaimSystem.CACHE] = {
            owner = claim.owner,
            rev = claim.rev,
            players = CarClaimSystem_copyPlayers(claim.players),
            faction = CarClaimSystem_Perms.clean(claim.faction),
            safehouse = CarClaimSystem_Perms.clean(claim.safehouse),
        }
    else
        md[CarClaimSystem.CACHE] = nil
    end

    vehicle:transmitModData()
end

-- true when the copy on the vehicle is not the one the server would stamp today: a client
-- wrote over it, or the claim changed or lapsed while the vehicle was not loaded.
function CarClaimSystem_State.stale(vehicle)
    local cache = vehicle:getModData()[CarClaimSystem.CACHE]
    local claim = CarClaimSystem_State.claimOf(vehicle)

    if not claim then return cache ~= nil end
    if type(cache) ~= "table" then return true end

    return cache.owner ~= claim.owner or cache.rev ~= claim.rev
end

function CarClaimSystem_State.touch(claim)
    claim.rev = (claim.rev or 0) + 1
end

function CarClaimSystem_State.create(vehicle, owner)
    local key = CarClaimSystem_State.keyOf(vehicle)
    if not key then return nil end

    local claim = {
        owner = owner,
        rev = 1,
        lastSeen = CarClaimSystem.now(),
        players = {},
        faction = {},
        safehouse = {},
    }

    CarClaimSystem_State.ensure().claims[key] = claim
    CarClaimSystem_State.note(vehicle, claim)
    CarClaimSystem_State.stamp(vehicle)

    return claim
end

function CarClaimSystem_State.release(vehicle)
    local key = CarClaimSystem_State.keyOf(vehicle)
    if not key then return end

    CarClaimSystem_State.ensure().claims[key] = nil
    CarClaimSystem_State.stamp(vehicle)
end

-- hands the vehicle to a new owner with nobody else allowed on it.
function CarClaimSystem_State.reassign(vehicle, claim, owner)
    claim.owner = owner
    claim.players = {}
    claim.faction = {}
    claim.safehouse = {}
    claim.lastSeen = CarClaimSystem.now()

    CarClaimSystem_State.touch(claim)
    CarClaimSystem_State.note(vehicle, claim)
    CarClaimSystem_State.stamp(vehicle)
end

-- every vehicle loaded right now. the cell hands back a java collection, walked by iterator
-- because that is the one thing a list and a set both have.
function CarClaimSystem_State.eachVehicle(fn)
    local cell = getCell()
    local vehicles = cell and cell:getVehicles()
    if not vehicles then return end

    local it = vehicles:iterator()
    while it:hasNext() do
        fn(it:next())
    end
end

-- everyone connected. singleplayer has no list, only the one player.
function CarClaimSystem_State.eachPlayer(fn)
    if not isServer() then
        local player = getPlayer()
        if player then fn(player) end
        return
    end

    local players = getOnlinePlayers()
    if not players then return end

    for i = 0, players:size() - 1 do
        fn(players:get(i))
    end
end

function CarClaimSystem_State.playerNamed(username)
    local found = nil

    CarClaimSystem_State.eachPlayer(function(player)
        if CarClaimSystem.nameOf(player) == username then found = player end
    end)

    return found
end

local function CarClaimSystem_onInit()
    CarClaimSystem_State.ensure()
end

Events.OnInitGlobalModData.Add(CarClaimSystem_onInit)
