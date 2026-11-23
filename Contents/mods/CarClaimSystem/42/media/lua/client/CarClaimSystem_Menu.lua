----------
--ESTRAL--
----------

require "CarClaimSystem_Core"
require "CarClaimSystem_Perms"
require "CarClaimSystem_Net"
require "CarClaimSystem_Client"
require "CarClaimSystem_Panel"
require "CarClaimSystem_List"

-- the "Vehicle Claim" entry on a vehicle's right-click menu.
--
-- everything here is drawn from the copy of the claim the server stamped on the vehicle, and
-- every click is a request: the server decides again from its own record.

CarClaimSystem_Menu = CarClaimSystem_Menu or {}

-- names in one submenu. a busy server has more people on than fit down a screen.
local NAME_CAP = 30

local function CarClaimSystem_sub(context, text)
    local option = context:addOption(text, nil, nil)
    local sub = ISContextMenu:getNew(context)

    context:addSubMenu(option, sub)
    return sub, option
end

local function CarClaimSystem_disabled(context, text)
    local option = context:addOption(text, nil, nil)
    option.notAvailable = true
    return option
end

-- usernames of everyone connected but the player, nearest first, and how far each is.
local function CarClaimSystem_others(playerObj)
    local out = {}
    local me = CarClaimSystem.nameOf(playerObj)
    local players = getOnlinePlayers()
    if not players then return out end

    for i = 0, players:size() - 1 do
        local other = players:get(i)
        local username = CarClaimSystem.nameOf(other)

        if username and username ~= me then
            out[#out + 1] = { name = username, dist = playerObj:DistTo(other) }
        end
    end

    table.sort(out, function(a, b)
        if a.dist ~= b.dist then return a.dist < b.dist end
        return a.name < b.name
    end)

    return out
end

local function CarClaimSystem_copy(flags)
    return CarClaimSystem_Perms.clean(flags)
end

local function CarClaimSystem_onToggle(_, vehicleId, kind, target, flag, current)
    local flags = CarClaimSystem_copy(current)
    flags[flag] = not flags[flag] or nil

    if kind == "player" then
        CarClaimSystem_Net.toServer("setPlayer", { vehicle = vehicleId, target = target, flags = flags })
    else
        CarClaimSystem_Net.toServer("setGroup", { vehicle = vehicleId, group = kind, flags = flags })
    end
end

local function CarClaimSystem_onRemove(_, vehicleId, target)
    CarClaimSystem_Net.toServer("removePlayer", { vehicle = vehicleId, target = target })
end

-- one tick-style line per flag. a context menu shuts when an entry is clicked, so each click
-- is one change; the panel is the place to set several at once.
local function CarClaimSystem_flagOptions(menu, vehicleId, kind, target, current)
    for _, flag in ipairs(CarClaimSystem.FLAGS) do
        local mark = current and current[flag] and "[x] " or "[  ] "
        local label = mark .. CarClaimSystem.text("IGUI_CarClaimSystem_Flag_" .. flag)

        menu:addOption(label, nil, CarClaimSystem_onToggle, vehicleId, kind, target, flag, current)
    end
end

local function CarClaimSystem_groupMenu(context, vehicleId, claim, kind, has)
    local text = CarClaimSystem.text("IGUI_CarClaimSystem_Group_" .. kind)

    if not has then
        local option = CarClaimSystem_disabled(context, text)
        local tip = ISToolTip:new()
        tip:initialise()
        tip:setVisible(false)
        tip.description = CarClaimSystem.text("IGUI_CarClaimSystem_NoGroup_" .. kind)
        option.toolTip = tip
        return
    end

    CarClaimSystem_flagOptions(CarClaimSystem_sub(context, text), vehicleId, kind, nil, claim[kind])
end

local function CarClaimSystem_playersMenu(context, text, vehicleId, claim, list)
    if #list == 0 then
        CarClaimSystem_disabled(context, text)
        return
    end

    local menu = CarClaimSystem_sub(context, text)

    for i = 1, math.min(#list, NAME_CAP) do
        local name = list[i].name
        local current = claim.players and claim.players[name]
        local sub = CarClaimSystem_sub(menu, name)

        CarClaimSystem_flagOptions(sub, vehicleId, "player", name, current)

        if current then
            sub:addOption(CarClaimSystem.text("IGUI_CarClaimSystem_RemoveEntry"), nil,
                CarClaimSystem_onRemove, vehicleId, name)
        end
    end
end

local function CarClaimSystem_onCommandFor(_, command, vehicleId, target)
    CarClaimSystem_Net.toServer(command, { vehicle = vehicleId, target = target })
end

local function CarClaimSystem_pickMenu(context, text, command, vehicleId, list)
    if #list == 0 then
        CarClaimSystem_disabled(context, text)
        return
    end

    local menu = CarClaimSystem_sub(context, text)

    for i = 1, math.min(#list, NAME_CAP) do
        menu:addOption(list[i].name, nil, CarClaimSystem_onCommandFor, command, vehicleId, list[i].name)
    end
end

local function CarClaimSystem_onPanel(_, playerObj, vehicle)
    CarClaimSystem_Panel.open(playerObj, vehicle)
end

local function CarClaimSystem_ownerMenu(menu, playerObj, vehicle, claim)
    local id = vehicle:getId()
    local others = CarClaimSystem_others(playerObj)

    local nearby = {}
    for _, other in ipairs(others) do
        if other.dist <= CarClaimSystem.NEARBY_RANGE then nearby[#nearby + 1] = other end
    end

    CarClaimSystem_groupMenu(menu, id, claim, "faction", Faction.getPlayerFaction(playerObj) ~= nil)
    CarClaimSystem_groupMenu(menu, id, claim, "safehouse", SafeHouse.hasSafehouse(playerObj) ~= nil)

    CarClaimSystem_playersMenu(menu, CarClaimSystem.text("IGUI_CarClaimSystem_Nearby"), id, claim, nearby)
    CarClaimSystem_playersMenu(menu, CarClaimSystem.text("IGUI_CarClaimSystem_Online"), id, claim, others)

    menu:addOption(CarClaimSystem.text("IGUI_CarClaimSystem_ViewPermissions"), nil,
        CarClaimSystem_onPanel, playerObj, vehicle)

    CarClaimSystem_pickMenu(menu, CarClaimSystem.text("IGUI_CarClaimSystem_Transfer"), "offer", id, others)

    menu:addOption(CarClaimSystem.text("IGUI_CarClaimSystem_Release"), nil,
        CarClaimSystem_onCommandFor, "release", id, nil)
end

local function CarClaimSystem_adminMenu(menu, playerObj, vehicle)
    local id = vehicle:getId()

    menu:addOption(CarClaimSystem.text("IGUI_CarClaimSystem_ViewPermissions"), nil,
        CarClaimSystem_onPanel, playerObj, vehicle)

    menu:addOption(CarClaimSystem.text("IGUI_CarClaimSystem_AdminRelease"), nil,
        CarClaimSystem_onCommandFor, "adminRelease", id, nil)

    local everyone = CarClaimSystem_others(playerObj)
    everyone[#everyone + 1] = { name = CarClaimSystem.nameOf(playerObj), dist = 0 }

    CarClaimSystem_pickMenu(menu, CarClaimSystem.text("IGUI_CarClaimSystem_AdminReassign"),
        "adminReassign", id, everyone)
end

function CarClaimSystem_Menu.fill(playerObj, context, vehicle)
    local title = CarClaimSystem.text("IGUI_CarClaimSystem_Menu")
    local claim = CarClaimSystem.claimOf(vehicle)

    if not claim then
        if CarClaimSystem.isWreck(vehicle) then return end

        local menu = CarClaimSystem_sub(context, title)
        menu:addOption(CarClaimSystem.text("IGUI_CarClaimSystem_Claim"), nil,
            CarClaimSystem_onCommandFor, "claim", vehicle:getId(), nil)
        return
    end

    local menu = CarClaimSystem_sub(context, title)
    CarClaimSystem_disabled(menu, CarClaimSystem.text("IGUI_CarClaimSystem_Owner", claim.owner))

    if claim.owner == CarClaimSystem.nameOf(playerObj) then
        CarClaimSystem_ownerMenu(menu, playerObj, vehicle, claim)
    elseif CarClaimSystem.isAdmin(playerObj) then
        CarClaimSystem_adminMenu(menu, playerObj, vehicle)
    end
end

-- the vehicle is found the way vanilla finds it for its own entries: the one the player is
-- in, or the one under the mouse.
local function CarClaimSystem_onList(_, playerObj)
    CarClaimSystem_List.open(playerObj)
end

-- the list is on every right-click, not only a vehicle's: it is how a player finds a car that
-- is nowhere near them.
local function CarClaimSystem_onFillWorldObjectContextMenu(player, context, worldobjects, test)
    if test then return end

    local playerObj = getSpecificPlayer(player)
    if not playerObj then return end

    context:addOption(CarClaimSystem.text("IGUI_CarClaimSystem_MyVehicles"), nil,
        CarClaimSystem_onList, playerObj)

    local vehicle = playerObj:getVehicle()
        or IsoObjectPicker.Instance:PickVehicle(getMouseXScaled(), getMouseYScaled())
    if not vehicle then return end

    CarClaimSystem_Menu.fill(playerObj, context, vehicle)
end

Events.OnFillWorldObjectContextMenu.Add(CarClaimSystem_onFillWorldObjectContextMenu)
