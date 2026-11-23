----------
--ESTRAL--
----------

require "CarClaimSystem_Core"
require "CarClaimSystem_Perms"
require "CarClaimSystem_Net"

-- what the server says back, and the one place a refusal is shown to the player.

CarClaimSystem_Client = CarClaimSystem_Client or {}

local DENY_MS = 1500
local lastDeny = 0

-- "Claimed by <owner>" over the character. isValid on a blocked action asks every frame, so
-- this is paced rather than left to stack up.
function CarClaimSystem_Client.deny(player, vehicle)
    if not player or not player:isLocalPlayer() then return end

    local now = getTimestampMs()
    if now - lastDeny < DENY_MS then return end
    lastDeny = now

    local claim = CarClaimSystem.claimOf(vehicle)
    local owner = claim and claim.owner or "?"

    HaloTextHelper.addBadText(player, CarClaimSystem.text("IGUI_CarClaimSystem_ClaimedBy", owner))
end

local function CarClaimSystem_onAnswer(_, button)
    CarClaimSystem_Net.toServer("answer", { accept = button.internal == "YES" })
end

local function CarClaimSystem_showOffer(player, args)
    local text = CarClaimSystem.text("IGUI_CarClaimSystem_OfferText", tostring(args.from))
    local modal = ISModalDialog:new(0, 0, 320, 120, text, true, nil, CarClaimSystem_onAnswer,
        player:getPlayerNum())

    modal:initialise()
    modal:addToUIManager()
end

-- put out of a seat the server says is not theirs. the vanilla exit, so doors are opened and
-- shut the way they always are.
local function CarClaimSystem_forceExit(player)
    local vehicle = player:getVehicle()
    if not vehicle then return end

    CarClaimSystem_Client.deny(player, vehicle)
    ISVehicleMenu.onExit(player)
end

function CarClaimSystem_Client.onCommand(module, command, args)
    if module ~= CarClaimSystem.MODULE then return end

    local player = getPlayer()
    if not player then return end

    args = type(args) == "table" and args or {}

    if command == "result" then
        local text = CarClaimSystem.text("IGUI_CarClaimSystem_Res_" .. tostring(args.code),
            tostring(args.a1 or ""))

        if args.ok then
            HaloTextHelper.addGoodText(player, text)
        else
            HaloTextHelper.addBadText(player, text)
        end
    elseif command == "offer" then
        CarClaimSystem_showOffer(player, args)
    elseif command == "forceExit" then
        CarClaimSystem_forceExit(player)
    elseif command == "claims" then
        -- looked up here: the list window's file requires this one.
        if CarClaimSystem_List then CarClaimSystem_List.receive(args) end
    end
end

Events.OnServerCommand.Add(CarClaimSystem_Client.onCommand)
