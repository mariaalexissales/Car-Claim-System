----------
--ESTRAL--
----------

require "CarClaimSystem_Core"
require "CarClaimSystem_Perms"

-- no authority guard: this one has to run on clients. the loot window asks the vehicle whether
-- a character may reach each container, and the vehicle asks these functions. the game gives
-- the server no say in an item moving out of a trunk, so this, the door gate and the seat
-- check are what keep a claimed car's storage shut.
--
-- it lives in server/ because Vehicles.lua does, and has to have loaded first.

local function CarClaimSystem_wrap(name, original)
    return function(vehicle, part, chr)
        if vehicle and chr and not CarClaimSystem.can(chr, vehicle, "storage") then return false end
        return original(vehicle, part, chr)
    end
end

local function CarClaimSystem_install()
    if not Vehicles or not Vehicles.ContainerAccess or Vehicles.CarClaimSystem_wrapped then return end
    Vehicles.CarClaimSystem_wrapped = true

    local names = {}
    for name, fn in pairs(Vehicles.ContainerAccess) do
        -- the tank is how a car is refuelled, which anyone may do. siphoning is gated as an action.
        if type(fn) == "function" and name ~= "GasTank" then names[#names + 1] = name end
    end

    for _, name in ipairs(names) do
        Vehicles.ContainerAccess[name] = CarClaimSystem_wrap(name, Vehicles.ContainerAccess[name])
    end
end

CarClaimSystem_install()
