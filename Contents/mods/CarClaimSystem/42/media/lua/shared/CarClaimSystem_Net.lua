----------
--ESTRAL--
----------

require "CarClaimSystem_Core"

CarClaimSystem_Net = CarClaimSystem_Net or {}

-- looked up at call time: shared/ loads before client/ and server/, so neither dispatcher
-- exists yet when this file runs.
local function CarClaimSystem_serverHandler(command)
    return CarClaimSystem_Commands and CarClaimSystem_Commands.handlers
        and CarClaimSystem_Commands.handlers[command]
end

local function CarClaimSystem_dispatchLocal(command, args)
    local handler = CarClaimSystem_Client and CarClaimSystem_Client.onCommand
    if not handler then return end

    local ok, err = pcall(handler, CarClaimSystem.MODULE, command, args)
    if not ok then
        CarClaimSystem.warn("client handler " .. tostring(command) .. " failed: " .. tostring(err))
    end
end

-- with no remote server the send is a direct call into the handler that would have received
-- it, so singleplayer runs the same code the server does.
function CarClaimSystem_Net.toServer(command, args)
    args = args or {}

    if CarClaimSystem.hasRemoteServer() then
        local player = getPlayer()
        if not player then
            CarClaimSystem.warn("no local player yet, dropped " .. tostring(command))
            return
        end

        sendClientCommand(player, CarClaimSystem.MODULE, command, args)
        return
    end

    local handler = CarClaimSystem_serverHandler(command)
    if not handler then
        CarClaimSystem.warn("no server handler for " .. tostring(command))
        return
    end

    local ok, err = pcall(handler, getPlayer(), args)
    if not ok then
        CarClaimSystem.warn("server handler " .. tostring(command) .. " failed: " .. tostring(err))
    end
end

function CarClaimSystem_Net.toClient(player, command, args)
    args = args or {}

    if isServer() then
        sendServerCommand(player, CarClaimSystem.MODULE, command, args)
        return
    end

    CarClaimSystem_dispatchLocal(command, args)
end
