----------
--ESTRAL--
----------

require "ISUI/ISCollapsableWindow"
require "ISUI/ISScrollingListBox"
require "ISUI/ISButton"
require "CarClaimSystem_Core"
require "CarClaimSystem_Net"

-- every vehicle the player has claimed, loaded or not, cars and trailers apart: what it is, the tile it was last seen
-- on, how far that is from them, and how long ago that was. the server holds the only full
-- record, so the window asks for it when it opens and when Refresh is pressed, and draws what
-- comes back.

CarClaimSystem_List = ISCollapsableWindow:derive("CarClaimSystem_List")

CarClaimSystem_List.instance = nil

local FONT = UIFont.Small
local FONT_H = getTextManager():getFontHeight(FONT)

local PAD = 8
local ROW_H = FONT_H + 8
local BTN_H = FONT_H + 6
local HEIGHT = 320

local COLUMNS = {
    { field = "name", width = 220 },
    { field = "location", width = 130 },
    { field = "distance", width = 100 },
    { field = "seen", width = 120 },
}

local function CarClaimSystem_colX(index)
    local x = PAD
    for i = 1, index - 1 do x = x + COLUMNS[i].width end
    return x
end

local function CarClaimSystem_width()
    return CarClaimSystem_colX(#COLUMNS + 1) + PAD * 2 + 14
end

-- the name the game shows for a vehicle script, which other mods' vehicles carry too. a
-- script with no name of its own is shown as the script.
local function CarClaimSystem_vehicleName(script, unknown)
    if type(script) ~= "string" or script == "" then return unknown end

    local short = string.match(script, "[^.]+$") or script
    return getTextOrNull("IGUI_VehicleName" .. short) or short
end

local function CarClaimSystem_seenText(entry, panel)
    if entry.loaded then return panel.nearbyText end

    local ago = tonumber(entry.ago)
    if not ago then return panel.unknownText end

    local minutes = math.max(1, math.floor(ago / 60000))
    if minutes < 60 then
        return CarClaimSystem.text("IGUI_CarClaimSystem_SeenMinutes", tostring(minutes))
    end

    local hours = math.floor(minutes / 60)
    if hours < 48 then
        return CarClaimSystem.text("IGUI_CarClaimSystem_SeenHours", tostring(hours))
    end

    local days = math.floor(hours / 24)
    return CarClaimSystem.text("IGUI_CarClaimSystem_SeenDays", tostring(days))
end

local function CarClaimSystem_drawRow(list, y, item, alt)
    local row = item.item
    local textY = y + (ROW_H - FONT_H) / 2

    if row.header then
        list:drawRect(0, y, list:getWidth(), ROW_H, 0.5, 0.15, 0.15, 0.15)
        list:drawText(row.label, PAD, textY, 0.95, 0.8, 0.45, 1, FONT)
        return y + ROW_H
    end

    if alt then list:drawRect(0, y, list:getWidth(), ROW_H, 0.25, 0.2, 0.2, 0.2) end

    for index, column in ipairs(COLUMNS) do
        list:drawText(row[column.field], CarClaimSystem_colX(index), textY, 1, 1, 1, 1, FONT)
    end

    return y + ROW_H
end

function CarClaimSystem_List:createChildren()
    ISCollapsableWindow.createChildren(self)

    local top = self:titleBarHeight() + PAD

    local refresh = ISButton:new(PAD, top, 100, BTN_H, self.refreshText, self, CarClaimSystem_List.request)
    refresh:initialise()
    refresh:instantiate()
    self:addChild(refresh)
    self.refreshButton = refresh

    self.headerY = top + BTN_H + PAD

    local listTop = self.headerY + FONT_H + 6
    local list = ISScrollingListBox:new(PAD, listTop, self.width - PAD * 2,
        self.height - listTop - PAD - self:resizeWidgetHeight())

    list:initialise()
    list:instantiate()
    list.itemheight = ROW_H
    list.font = FONT
    list.drawBorder = true
    list.doDrawItem = CarClaimSystem_drawRow
    list.panel = self

    self:addChild(list)
    self.list = list
end

function CarClaimSystem_List:request()
    self.waiting = true
    CarClaimSystem_Net.toServer("list", {})
end

local function CarClaimSystem_byDistance(a, b)
    if a.dist and b.dist and a.dist ~= b.dist then return a.dist < b.dist end
    if (a.dist == nil) ~= (b.dist == nil) then return a.dist ~= nil end
    return a.name < b.name
end

-- a section's heading, with how many it holds against its limit. 0 is no limit.
local function CarClaimSystem_heading(trailer, count, cap)
    if trailer then
        if cap > 0 then
            return CarClaimSystem.text("IGUI_CarClaimSystem_SectionTrailers", tostring(count), tostring(cap))
        end
        return CarClaimSystem.text("IGUI_CarClaimSystem_SectionTrailersNoCap", tostring(count))
    end

    if cap > 0 then
        return CarClaimSystem.text("IGUI_CarClaimSystem_SectionCars", tostring(count), tostring(cap))
    end
    return CarClaimSystem.text("IGUI_CarClaimSystem_SectionCarsNoCap", tostring(count))
end

-- cars, then trailers, each under its own heading and nearest first. a vehicle with no known
-- place goes to the bottom of its section. a section with nothing in it keeps its heading, so
-- the limit is on show either way.
function CarClaimSystem_List:fill(args)
    self.waiting = false
    self.list:clear()

    local px, py = self.playerObj:getX(), self.playerObj:getY()
    local cars, trailers = {}, {}

    for _, entry in ipairs(type(args.vehicles) == "table" and args.vehicles or {}) do
        local x, y = tonumber(entry.x), tonumber(entry.y)
        local row = {
            name = CarClaimSystem_vehicleName(entry.script, self.unknownText),
            location = self.unknownText,
            distance = self.unknownText,
            seen = CarClaimSystem_seenText(entry, self),
        }

        if x and y then
            local dist = math.floor(math.sqrt((px - x) * (px - x) + (py - y) * (py - y)))
            row.dist = dist
            row.location = tostring(x) .. ", " .. tostring(y)
            row.distance = CarClaimSystem.text("IGUI_CarClaimSystem_Tiles", tostring(dist))
        end

        local into = entry.trailer == true and trailers or cars
        into[#into + 1] = row
    end

    if #cars + #trailers == 0 then return end

    local sections = {
        { trailer = false, rows = cars, cap = tonumber(args.cap) or 0 },
        { trailer = true, rows = trailers, cap = tonumber(args.trailerCap) or 0 },
    }

    for _, section in ipairs(sections) do
        table.sort(section.rows, CarClaimSystem_byDistance)

        local label = CarClaimSystem_heading(section.trailer, #section.rows, section.cap)
        self.list:addItem(label, { header = true, label = label })

        for _, row in ipairs(section.rows) do
            self.list:addItem(row.name, row)
        end
    end
end

function CarClaimSystem_List:prerender()
    ISCollapsableWindow.prerender(self)

    for index = 1, #COLUMNS do
        self:drawText(self.columnText[index], PAD + CarClaimSystem_colX(index), self.headerY,
            0.8, 0.8, 0.8, 1, FONT)
    end
end

function CarClaimSystem_List:render()
    ISCollapsableWindow.render(self)

    if #self.list.items > 0 then return end

    local text = self.waiting and self.loadingText or self.emptyText
    self:drawText(text, PAD * 2, self.list:getY() + PAD, 0.7, 0.7, 0.7, 1, FONT)
end

function CarClaimSystem_List:close()
    self:setVisible(false)
    self:removeFromUIManager()

    if CarClaimSystem_List.instance == self then CarClaimSystem_List.instance = nil end
end

function CarClaimSystem_List:new(x, y, playerObj)
    local o = ISCollapsableWindow.new(self, x, y, CarClaimSystem_width(), HEIGHT)

    o.playerObj = playerObj
    o.resizable = false
    o.waiting = true

    -- fetched once: these are drawn every frame, and every getText is a format call.
    o.refreshText = CarClaimSystem.text("IGUI_CarClaimSystem_Refresh")
    o.loadingText = CarClaimSystem.text("IGUI_CarClaimSystem_ListLoading")
    o.emptyText = CarClaimSystem.text("IGUI_CarClaimSystem_ListEmpty")
    o.unknownText = CarClaimSystem.text("IGUI_CarClaimSystem_Unknown")
    o.nearbyText = CarClaimSystem.text("IGUI_CarClaimSystem_SeenNow")
    o.columnText = {
        CarClaimSystem.text("IGUI_CarClaimSystem_ColVehicle"),
        CarClaimSystem.text("IGUI_CarClaimSystem_ColLocation"),
        CarClaimSystem.text("IGUI_CarClaimSystem_ColDistance"),
        CarClaimSystem.text("IGUI_CarClaimSystem_ColSeen"),
    }

    o.title = CarClaimSystem.text("IGUI_CarClaimSystem_MyVehicles")

    return o
end

-- the server's answer to "list". dropped when the window was shut before it came.
function CarClaimSystem_List.receive(args)
    local panel = CarClaimSystem_List.instance
    if panel then panel:fill(args) end
end

-- one window at a time. opening it again asks the server again.
function CarClaimSystem_List.open(playerObj)
    local panel = CarClaimSystem_List.instance

    if not panel then
        local width = CarClaimSystem_width()
        local x = (getCore():getScreenWidth() - width) / 2
        local y = (getCore():getScreenHeight() - HEIGHT) / 2

        panel = CarClaimSystem_List:new(x, y, playerObj)
        panel:initialise()
        panel:addToUIManager()

        CarClaimSystem_List.instance = panel
    end

    panel:bringToTop()
    panel:request()

    return panel
end
