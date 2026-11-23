----------
--ESTRAL--
----------

require "CarClaimSystem_Core"

if not CarClaimSystem.isAuthority() then return end

-- an engine left running with nobody at the wheel is switched off after a while. every
-- vehicle, claimed or not. a car somebody is driving is never touched: the count only runs
-- while the driver's seat is empty, and starts again the moment it is not.

CarClaimSystem_IdleShutoff = CarClaimSystem_IdleShutoff or {}

local MINUTE_MS = 60000

-- vehicle id -> { since, seen }. since is when the engine was first found idling; seen is the
-- last sweep that looked at it, so a vehicle that unloads is dropped rather than left to match
-- a different vehicle that is handed the same id later. never saved: a restart starts again.
CarClaimSystem_IdleShutoff.idle = CarClaimSystem_IdleShutoff.idle or {}

-- called for every loaded vehicle by the minute sweep. 0 minutes is off.
function CarClaimSystem_IdleShutoff.check(vehicle, now)
    local id = vehicle:getId()
    local minutes = CarClaimSystem.option("IdleShutoffMinutes", 10)

    if minutes <= 0 or not vehicle:isEngineRunning() or vehicle:getDriver() then
        CarClaimSystem_IdleShutoff.idle[id] = nil
        return false
    end

    local entry = CarClaimSystem_IdleShutoff.idle[id]
    if not entry then
        CarClaimSystem_IdleShutoff.idle[id] = { since = now, seen = now }
        return false
    end

    entry.seen = now
    if now - entry.since < minutes * MINUTE_MS then return false end

    CarClaimSystem_IdleShutoff.idle[id] = nil
    vehicle:shutOff()

    return true
end

-- entries no sweep has looked at lately belong to vehicles that are not loaded any more.
function CarClaimSystem_IdleShutoff.prune(now)
    local gone = {}

    for id, entry in pairs(CarClaimSystem_IdleShutoff.idle) do
        if now - entry.seen > 2 * MINUTE_MS then gone[#gone + 1] = id end
    end

    for _, id in ipairs(gone) do
        CarClaimSystem_IdleShutoff.idle[id] = nil
    end
end
