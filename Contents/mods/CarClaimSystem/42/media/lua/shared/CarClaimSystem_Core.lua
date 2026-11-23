----------
--ESTRAL--
----------

CarClaimSystem = CarClaimSystem or {}

CarClaimSystem.MODULE = "CarClaimSystem"

-- the key the public copy of a claim sits under in a vehicle's mod data.
CarClaimSystem.CACHE = "CarClaimSystem"

-- what a grant can allow. the order is the order every menu and the panel show them in.
CarClaimSystem.FLAGS = { "passenger", "drive", "storage", "mechanics", "tow" }

-- tiles. how close a player has to stand to claim, and how far "Nearby Players" reaches.
CarClaimSystem.CLAIM_RANGE = 4
CarClaimSystem.NEARBY_RANGE = 10

-- milliseconds a transfer offer waits for its answer.
CarClaimSystem.OFFER_MS = 60000

-- server/ lua loads on multiplayer clients too, and isServer() is false in singleplayer.
function CarClaimSystem.isAuthority()
    return not (isClient() and not isServer())
end

function CarClaimSystem.hasRemoteServer()
    return isClient() and not isServer()
end

function CarClaimSystem.log(message)
    print("[CarClaimSystem] " .. tostring(message))
end

function CarClaimSystem.warn(message)
    print("[CarClaimSystem] WARN: " .. tostring(message))
end

-- the engine ships both spellings of every role, and vanilla compares the lowercase one.
function CarClaimSystem.accessLevel(player)
    if not player then return "none" end

    local level = player:getAccessLevel()
    if not level or level == "" then return "none" end

    return string.lower(level)
end

-- admins walk through every claim. singleplayer has nobody to keep out, so the one player
-- there is not treated as an admin: the claim would otherwise do nothing they can see.
function CarClaimSystem.isAdmin(player)
    if not player then return false end
    if not isClient() and not isServer() then return false end

    local level = CarClaimSystem.accessLevel(player)
    return level == "admin" or level == "gm" or level == "moderator"
end

-- claims are keyed by this: the account name, which survives a death.
function CarClaimSystem.nameOf(player)
    if not player then return nil end

    local username = player:getUsername()
    if username and username ~= "" then return username end

    return nil
end

-- a handler that throws is called again next event, so one on a timer can fill console.txt.
-- every repeating handler registers through here and takes itself off after three failures
-- in a row.
local GUARD_LIMIT = 3

function CarClaimSystem.guard(name, event, fn)
    local failures = 0
    local wrapped

    wrapped = function(a, b, c, d)
        local ok, err = pcall(fn, a, b, c, d)

        if ok then
            failures = 0
            return
        end

        failures = failures + 1
        CarClaimSystem.warn(name .. " failed: " .. tostring(err))

        if failures >= GUARD_LIMIT then
            CarClaimSystem.warn(name .. " has failed " .. GUARD_LIMIT
                .. " times in a row and is stopped for the rest of this session")
            event.Remove(wrapped)
        end
    end

    event.Add(wrapped)
    return wrapped
end

-- wall clock, in epoch milliseconds. a claim has to lapse after the same number of real days
-- whether the server was up or not.
function CarClaimSystem.now()
    local ok, ms = pcall(function() return Calendar.getInstance():getTimeInMillis() end)
    if ok and type(ms) == "number" and ms > 0 then return ms end

    return getTimestampMs()
end

-- a sandbox number, or the default when the option is missing or not a number.
function CarClaimSystem.option(name, default)
    local vars = SandboxVars and SandboxVars.CarClaimSystem
    local value = vars and tonumber(vars[name])

    if not value or value < 0 then return default end
    return value
end

-- getText on a missing key returns the key, which would print IGUI_CarClaimSystem_X in the ui.
function CarClaimSystem.text(key, a1, a2)
    local value

    if a2 ~= nil then
        value = getText(key, a1, a2)
    elseif a1 ~= nil then
        value = getText(key, a1)
    else
        value = getText(key)
    end

    return value or key
end

-- burnt and smashed wrecks are never claimable: a claimed wreck could not be cleared off a road.
function CarClaimSystem.isWreck(vehicle)
    local name = vehicle:getScriptName() or ""
    return string.contains(name, "Burnt") or string.contains(name, "Smashed")
end

-- a trailer has nowhere to sit and no key, so it is claimed through the car pulling it.
function CarClaimSystem.isTrailer(vehicle)
    return vehicle:getMaxPassengers() == 0
end

-- seat 0 is the driver's.
function CarClaimSystem.seatFlag(seat)
    if seat == 0 then return "drive" end
    return "passenger"
end

function CarClaimSystem.sameFaction(owner, username)
    if not Faction then return false end

    local faction = Faction.getPlayerFaction(owner)
    if not faction then return false end

    return faction:isOwner(username) or faction:isMember(username)
end

function CarClaimSystem.sameSafehouse(owner, username)
    if not SafeHouse then return false end

    return SafeHouse.isInSameSafehouse(owner, username) == true
end

-- the claim on a vehicle, or nil. wherever the authority runs this is its own saved record;
-- a multiplayer client only has the copy the server stamped into the vehicle's mod data, which
-- is good enough to draw a menu with and is never what the server decides on.
function CarClaimSystem.claimOf(vehicle)
    if not vehicle then return nil end

    if CarClaimSystem.isAuthority() and CarClaimSystem_State then
        return CarClaimSystem_State.claimOf(vehicle)
    end

    local cache = vehicle:getModData()[CarClaimSystem.CACHE]
    if type(cache) ~= "table" or not cache.owner then return nil end

    return cache
end

-- may this player do the thing this flag covers to this vehicle. flag "owner" asks whether
-- they own it. an unclaimed vehicle allows everything.
function CarClaimSystem.can(player, vehicle, flag)
    local claim = CarClaimSystem.claimOf(vehicle)
    if not claim then return true end

    if CarClaimSystem.isAdmin(player) then return true end

    local username = CarClaimSystem.nameOf(player)
    if not username then return false end

    local flags = CarClaimSystem_Perms.resolve(claim, username,
        CarClaimSystem.sameFaction, CarClaimSystem.sameSafehouse)

    if flag == "owner" then return flags.owner == true end
    return flags[flag] == true
end
