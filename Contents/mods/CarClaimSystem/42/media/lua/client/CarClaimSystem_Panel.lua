----------
--ESTRAL--
----------

require "ISUI/ISCollapsableWindow"
require "ISUI/ISScrollingListBox"
require "CarClaimSystem_Core"
require "CarClaimSystem_Perms"
require "CarClaimSystem_Net"

-- everyone who holds anything on one vehicle, in one table: the two groups, then each player
-- with an entry of their own, online or not. the owner ticks and unticks; anyone else the
-- window is shown to only reads it.

CarClaimSystem_Panel = ISCollapsableWindow:derive("CarClaimSystem_Panel")

CarClaimSystem_Panel.instance = nil

local FONT = UIFont.Small
local FONT_H = getTextManager():getFontHeight(FONT)

local PAD = 8
local NAME_W = 170
local COL_W = 84
local BOX = FONT_H
local ROW_H = FONT_H + 8
local REMOVE_W = 70

local function CarClaimSystem_colX(index)
    return PAD + NAME_W + (index - 1) * COL_W
end

local function CarClaimSystem_removeX()
    return CarClaimSystem_colX(#CarClaimSystem.FLAGS + 1)
end

local function CarClaimSystem_width()
    return CarClaimSystem_removeX() + REMOVE_W + PAD + 14
end

local function CarClaimSystem_drawRow(list, y, item, alt)
    local row = item.item
    local textY = y + (ROW_H - FONT_H) / 2

    if alt then list:drawRect(0, y, list:getWidth(), ROW_H, 0.25, 0.2, 0.2, 0.2) end

    list:drawText(row.label, PAD, textY, 1, 1, 1, 1, FONT)

    for index, flag in ipairs(CarClaimSystem.FLAGS) do
        local x = CarClaimSystem_colX(index) + (COL_W - BOX) / 2
        local boxY = y + (ROW_H - BOX) / 2

        list:drawRectBorder(x, boxY, BOX, BOX, 1, 0.6, 0.6, 0.6)
        if row.flags[flag] then
            list:drawRect(x + 3, boxY + 3, BOX - 6, BOX - 6, 1, 0.4, 0.85, 0.4)
        end
    end

    if row.kind == "player" and list.panel.editable then
        list:drawText(list.panel.removeText, CarClaimSystem_removeX(), textY, 0.9, 0.45, 0.45, 1, FONT)
    end

    return y + ROW_H
end

-- a click is worked out from where it landed: which row, then which column.
local function CarClaimSystem_onListMouseDown(list, x, y)
    local panel = list.panel
    if not panel.editable then return end

    local index = list:rowAt(x, y)
    local entry = index and list.items[index]
    if not entry then return end

    local row = entry.item

    if row.kind == "player" and x >= CarClaimSystem_removeX() and x < CarClaimSystem_removeX() + REMOVE_W then
        CarClaimSystem_Net.toServer("removePlayer", { vehicle = panel.vehicle:getId(), target = row.name })
        return
    end

    for column, flag in ipairs(CarClaimSystem.FLAGS) do
        local left = CarClaimSystem_colX(column)

        if x >= left and x < left + COL_W then
            local flags = CarClaimSystem_Perms.clean(row.flags)
            flags[flag] = not flags[flag] or nil

            if row.kind == "player" then
                CarClaimSystem_Net.toServer("setPlayer",
                    { vehicle = panel.vehicle:getId(), target = row.name, flags = flags })
            else
                CarClaimSystem_Net.toServer("setGroup",
                    { vehicle = panel.vehicle:getId(), group = row.kind, flags = flags })
            end
            return
        end
    end
end

function CarClaimSystem_Panel:createChildren()
    ISCollapsableWindow.createChildren(self)

    local top = self:titleBarHeight() + PAD + FONT_H + 6
    local list = ISScrollingListBox:new(PAD, top, self.width - PAD * 2,
        self.height - top - PAD - self:resizeWidgetHeight())

    list:initialise()
    list:instantiate()
    list.itemheight = ROW_H
    list.font = FONT
    list.drawBorder = true
    list.doDrawItem = CarClaimSystem_drawRow
    list.onMouseDown = CarClaimSystem_onListMouseDown
    list.panel = self

    self:addChild(list)
    self.list = list
end

-- the rows are rebuilt whenever the copy on the vehicle moves on, which is what a change made
-- from this window comes back as.
function CarClaimSystem_Panel:refresh(claim)
    self.rev = claim.rev
    self.editable = claim.owner == CarClaimSystem.nameOf(self.playerObj)
    self:setTitle(CarClaimSystem.text("IGUI_CarClaimSystem_PanelTitle", claim.owner))

    self.list:clear()

    for _, kind in ipairs({ "faction", "safehouse" }) do
        self.list:addItem(kind, {
            kind = kind,
            label = CarClaimSystem.text("IGUI_CarClaimSystem_Group_" .. kind),
            flags = CarClaimSystem_Perms.clean(claim[kind]),
        })
    end

    local names = {}
    for username in pairs(claim.players or {}) do names[#names + 1] = username end
    table.sort(names)

    for _, username in ipairs(names) do
        self.list:addItem(username, {
            kind = "player",
            name = username,
            label = username,
            flags = CarClaimSystem_Perms.clean(claim.players[username]),
        })
    end
end

function CarClaimSystem_Panel:prerender()
    ISCollapsableWindow.prerender(self)

    local claim = CarClaimSystem.claimOf(self.vehicle)
    if not claim then
        self:close()
        return
    end

    if claim.rev ~= self.rev or claim.owner ~= self.claimOwner then
        self.claimOwner = claim.owner
        self:refresh(claim)
    end

    local y = self:titleBarHeight() + PAD
    self:drawText(self.nameText, PAD * 2, y, 0.8, 0.8, 0.8, 1, FONT)

    for index, flag in ipairs(CarClaimSystem.FLAGS) do
        local text = self.flagText[flag]
        local x = PAD + CarClaimSystem_colX(index) + (COL_W - getTextManager():MeasureStringX(FONT, text)) / 2

        self:drawText(text, x, y, 0.8, 0.8, 0.8, 1, FONT)
    end
end

function CarClaimSystem_Panel:close()
    self:setVisible(false)
    self:removeFromUIManager()

    if CarClaimSystem_Panel.instance == self then CarClaimSystem_Panel.instance = nil end
end

function CarClaimSystem_Panel:new(x, y, playerObj, vehicle)
    local o = ISCollapsableWindow.new(self, x, y, CarClaimSystem_width(), 300)

    o.playerObj = playerObj
    o.vehicle = vehicle
    o.resizable = false
    o.rev = nil
    o.claimOwner = nil
    o.editable = false

    -- fetched once: these are drawn every frame, and every getText is a format call.
    o.nameText = CarClaimSystem.text("IGUI_CarClaimSystem_ColName")
    o.removeText = CarClaimSystem.text("IGUI_CarClaimSystem_RemoveEntry")
    o.flagText = {}
    for _, flag in ipairs(CarClaimSystem.FLAGS) do
        o.flagText[flag] = CarClaimSystem.text("IGUI_CarClaimSystem_Flag_" .. flag)
    end

    return o
end

function CarClaimSystem_Panel.open(playerObj, vehicle)
    if CarClaimSystem_Panel.instance then CarClaimSystem_Panel.instance:close() end

    local width = CarClaimSystem_width()
    local x = (getCore():getScreenWidth() - width) / 2
    local y = (getCore():getScreenHeight() - 300) / 2

    local panel = CarClaimSystem_Panel:new(x, y, playerObj, vehicle)
    panel:initialise()
    panel:addToUIManager()

    CarClaimSystem_Panel.instance = panel
    return panel
end
