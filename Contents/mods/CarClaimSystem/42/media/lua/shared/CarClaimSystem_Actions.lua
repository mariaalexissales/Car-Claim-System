----------
--ESTRAL--
----------

require "CarClaimSystem_Core"
require "CarClaimSystem_Perms"

-- the gate on everything the game does to a vehicle through a timed action.
--
-- in multiplayer a shared timed action is built again on the server and its complete() runs
-- there; answering false throws the action out and tells the client to stop. vanilla checks
-- nothing in complete(), so this wrapper is the only thing on the server standing between a
-- claimed car and an edited client. isValid() only ever runs on the client, where it stops
-- the action before the progress bar starts and says why.

CarClaimSystem_Actions = CarClaimSystem_Actions or {}

local function CarClaimSystem_vehicleOf(action)
    if action.vehicle then return action.vehicle end

    local part = action.part or action.vehiclePart
    if part then return part:getVehicle() end

    return action.character and action.character:getVehicle()
end

-- somebody already sitting in the car may always work its doors, locks and windows: that is
-- how they get out, and a player the owner has just revoked has to be able to leave.
local function CarClaimSystem_inside(action)
    local vehicle = CarClaimSystem_vehicleOf(action)
    return vehicle ~= nil and action.character ~= nil and action.character:getVehicle() == vehicle
end

local function CarClaimSystem_passengerFlag(action)
    if CarClaimSystem_inside(action) then return nil end
    return "passenger"
end

-- the hood is how the engine is reached and the trunk door is how the trunk is, so each is
-- held to the flag for what is behind it. every other door is just a way in.
local function CarClaimSystem_doorFlag(action)
    local id = action.part and action.part:getId() or ""

    if id == "EngineDoor" then return "mechanics" end
    if id == "TrunkDoor" or id == "DoorRear" then return "storage" end

    return CarClaimSystem_passengerFlag(action)
end

-- ISSmashWindow is the house-window action too. only a vehicle's window is anyone's claim.
local function CarClaimSystem_smashFlag(action)
    if not action.vehiclePart then return nil end
    return "owner"
end

function CarClaimSystem_Actions.blocked(action, flag)
    if type(flag) == "function" then flag = flag(action) end
    if not flag then return false end

    local vehicle = CarClaimSystem_vehicleOf(action)
    if not vehicle or not action.character then return false end

    if CarClaimSystem.can(action.character, vehicle, flag) then return false end

    return true, vehicle
end

function CarClaimSystem_Actions.gate(class, flag)
    if not class or class.CarClaimSystem_gated then return end
    class.CarClaimSystem_gated = true

    local complete = class.complete
    local isValid = class.isValid

    -- only where the class already has one. an action with no complete() is one the game
    -- keeps on the client, and giving it one would start sending it to the server.
    if complete then
        class.complete = function(self)
            if CarClaimSystem_Actions.blocked(self, flag) then return false end
            return complete(self)
        end
    end

    class.isValid = function(self)
        local blocked, vehicle = CarClaimSystem_Actions.blocked(self, flag)

        if blocked then
            if CarClaimSystem_Client then CarClaimSystem_Client.deny(self.character, vehicle) end
            return false
        end

        if isValid then return isValid(self) end
        return true
    end
end

-- putting fuel in is deliberately not here: anyone may fill a claimed car up.
function CarClaimSystem_Actions.install()
    local gate = CarClaimSystem_Actions.gate

    gate(ISInstallVehiclePart, "mechanics")
    gate(ISUninstallVehiclePart, "mechanics")
    gate(ISFixVehiclePartAction, "mechanics")
    gate(ISRepairEngine, "mechanics")
    gate(ISRepairLightbar, "mechanics")
    gate(ISTakeEngineParts, "mechanics")
    gate(ISTakeGasolineFromVehicle, "mechanics")
    gate(ISInflateTire, "mechanics")
    gate(ISDeflateTire, "mechanics")
    gate(ISWashVehicle, "mechanics")

    gate(ISHotwireVehicle, "drive")
    gate(ISStartVehicleEngine, "drive")

    gate(ISLockVehicleDoor, CarClaimSystem_passengerFlag)
    gate(ISUnlockVehicleDoor, CarClaimSystem_passengerFlag)
    gate(ISLockDoors, CarClaimSystem_passengerFlag)
    gate(ISOpenCloseVehicleWindow, CarClaimSystem_passengerFlag)
    gate(ISOpenVehicleDoor, CarClaimSystem_doorFlag)
    gate(ISCloseVehicleDoor, CarClaimSystem_doorFlag)

    gate(ISAddAnimalInTrailer, "storage")
    gate(ISRemoveAnimalFromTrailer, "storage")

    gate(ISSmashWindow, CarClaimSystem_smashFlag)
end

-- vanilla's lua is all loaded before any mod's, so every class above exists by now.
CarClaimSystem_Actions.install()
