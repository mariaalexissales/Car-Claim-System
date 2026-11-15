----------
--ESTRAL--
----------

require "CarClaimSystem_Core"
require "CarClaimSystem_Perms"
require "CarClaimSystem_Actions"
require "CarClaimSystem_Client"

-- the things a claim stops that the server cannot refuse up front: climbing in, changing seat
-- and hitching. an honest client never sends them. the server still checks who is sitting
-- where and undoes a hitch it did not allow, for the client that is not honest.

local function CarClaimSystem_seatBlocked(player, vehicle, seat)
    if not player or not vehicle then return false end
    if CarClaimSystem.can(player, vehicle, CarClaimSystem.seatFlag(seat)) then return false end

    CarClaimSystem_Client.deny(player, vehicle)
    return true
end

-- every vanilla way into a seat ends in one of these, all (player, vehicle, seat).
local function CarClaimSystem_wrapEnter(name)
    local original = ISVehicleMenu[name]
    if not original then return end

    ISVehicleMenu[name] = function(playerObj, vehicle, seat)
        if CarClaimSystem_seatBlocked(playerObj, vehicle, seat) then return end
        return original(playerObj, vehicle, seat)
    end
end

local function CarClaimSystem_towBlocked(player, vehicle)
    if not player or not vehicle then return false end
    if CarClaimSystem.can(player, vehicle, "tow") then return false end
    return true
end

local function CarClaimSystem_install()
    if ISVehicleMenu.CarClaimSystem_wrapped then return end
    ISVehicleMenu.CarClaimSystem_wrapped = true

    CarClaimSystem_wrapEnter("onEnter")
    CarClaimSystem_wrapEnter("onEnter2")
    CarClaimSystem_wrapEnter("processEnter")
    CarClaimSystem_wrapEnter("processShiftEnter")

    local onSwitchSeat = ISVehicleMenu.onSwitchSeat
    ISVehicleMenu.onSwitchSeat = function(playerObj, seatTo)
        if CarClaimSystem_seatBlocked(playerObj, playerObj and playerObj:getVehicle(), seatTo) then return end
        return onSwitchSeat(playerObj, seatTo)
    end

    -- the towing menu is built from the vehicle the player is at and whichever one this finds
    -- behind or in front of it. a claimed one the player may not tow is simply not found.
    local getTowable = ISVehicleTrailerUtils.getTowableVehicleNear
    ISVehicleTrailerUtils.getTowableVehicleNear = function(square, ignoreVehicle, attachmentA, attachmentB)
        local found = getTowable(square, ignoreVehicle, attachmentA, attachmentB)
        if found and CarClaimSystem_towBlocked(getPlayer(), found) then return nil end
        return found
    end

    local doTowingMenu = ISVehicleMenu.doTowingMenu
    ISVehicleMenu.doTowingMenu = function(playerObj, vehicle, menu)
        if CarClaimSystem_towBlocked(playerObj, vehicle) then return end
        return doTowingMenu(playerObj, vehicle, menu)
    end

    local onAttach = ISVehicleMenu.onAttachTrailer
    ISVehicleMenu.onAttachTrailer = function(playerObj, vehicle, attachmentA, attachmentB)
        if CarClaimSystem_towBlocked(playerObj, vehicle) then
            CarClaimSystem_Client.deny(playerObj, vehicle)
            return
        end
        return onAttach(playerObj, vehicle, attachmentA, attachmentB)
    end

    local onDetach = ISVehicleMenu.onDetachTrailer
    ISVehicleMenu.onDetachTrailer = function(playerObj, vehicle, attachmentA)
        local other = vehicle and (vehicle:getVehicleTowing() or vehicle:getVehicleTowedBy())
        local blocked = CarClaimSystem_towBlocked(playerObj, vehicle) and vehicle
            or CarClaimSystem_towBlocked(playerObj, other) and other

        if blocked then
            CarClaimSystem_Client.deny(playerObj, blocked)
            return
        end
        return onDetach(playerObj, vehicle, attachmentA)
    end

    -- the two seat actions themselves, for anything that queues one without the menu.
    CarClaimSystem_Actions.gate(ISEnterVehicle, function(action)
        return CarClaimSystem.seatFlag(action.seat)
    end)
    CarClaimSystem_Actions.gate(ISSwitchVehicleSeat, function(action)
        return CarClaimSystem.seatFlag(action.seatTo)
    end)
end

CarClaimSystem_install()
