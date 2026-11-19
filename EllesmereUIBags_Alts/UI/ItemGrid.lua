-------------------------------------------------------------------------------
--  UI/ItemGrid.lua
--  Offline item grid: a pool of plain ItemButton frames (the intrinsic, NOT
--  the secure ContainerFrameItemButtonTemplate), laid out in titled sections.
--
--  The buttons only display: tooltip on hover, shift/ctrl-click through
--  HandleModifiedItemClick (chat link / dressing room). They never use,
--  move or pick up items, so there is nothing protected to taint.
-------------------------------------------------------------------------------
local _, ns = ...
local W = ns.W
local Ext = _G.EllesmereUIBagsExt

local SLOT, GAP, HEADER_H = 34, 4, 20
local MISS_ALPHA = 0.25
ns.SEARCH_MISS_ALPHA = MISS_ALPHA
-- The stock quality border (IconBorder, 37 px) overhangs the 34 px slot by
-- 1.5 px per side; inset the grid so the scroll frame never clips it.
local INSET = 2

local Grid = {}
Grid.__index = Grid
ns.ItemGrid = Grid

local function ResolveLink(ref)
    if not ref then return nil end
    if ref:find("|H", 1, true) then return ref end
    local _, link = C_Item.GetItemInfo(ref)
    return link
end

-- The item tooltip is built through Blizzard's own TooltipDataHandler with a
-- per-call linePreCall/tooltipPostCall (scoped to this one tooltip, no global
-- hooks): a stored item that is bound shows "Soulbound"/"Warbound" instead of
-- the generic "Binds when equipped", equipment sets are listed and so is who
-- holds how many where (ns.AddOwnerLines).
local BINDING_LINE = Enum.TooltipDataLineType.ItemBinding

local function BindingPreCall(tooltip, lineData)
    local info = tooltip.processingInfo
    local bound = info and info.euiAltsBound
    -- An item warbound until equipped keeps its own binding line, which says so.
    if not bound or bound == "wue" or lineData.type ~= BINDING_LINE then return false end
    local text = bound == "account" and ITEM_ACCOUNTBOUND or ITEM_SOULBOUND
    local c = lineData.leftColor
    tooltip:AddLine(text, c and c.r or 1, c and c.g or 1, c and c.b or 1)
    return true   -- consumed: the generic binding line is not added
end
ns.BindingPreCall = BindingPreCall   -- the search's result rows show it too

local function SetsPostCall(tooltip)
    local info = tooltip.processingInfo
    local sets = info and info.euiAltsSets
    if sets then
        tooltip:AddLine(string.format(ns.L["Equipment sets: %s"], "|cffffffff" .. sets .. "|r"), 1, 0.82, 0, true)
    end
    if info and info.euiAltsExtra then info.euiAltsExtra(tooltip, info.euiAltsExtraArg) end
    ns.AddOwnerLines(tooltip)
end

-- Tooltip of a stored stack on one of the browser's frames. ref: link or
-- "item:<id>"; extra(tooltip, extraArg): more lines before the owners.
function ns.ShowStoredItemTooltip(owner, ref, bound, sets, itemID, extra, extraArg)
    if not ref then return end
    local tooltip = W.GetTooltip()
    tooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if ref:find("battlepet:", 1, true) and W.ShowPetTooltip(owner, ref) then
        tooltip:Hide()
        return
    end
    tooltip:ProcessInfo({
        getterName = "GetHyperlink",
        getterArgs = { ref },
        linePreCall = BindingPreCall,
        tooltipPostCall = SetsPostCall,
        euiAltsBound = bound,
        euiAltsSets = sets,
        euiAltsOwners = itemID,
        euiAltsExtra = extra,
        euiAltsExtraArg = extraArg,
    })
end

local function Button_OnEnter(self)
    ns.ShowStoredItemTooltip(self, self.ref, self.bound, self.sets, self.itemID)
end

local function Button_OnLeave()
    W.GetTooltip():Hide()
    W.HidePetTooltip()
end

local function Button_OnClick(self)
    if not IsModifiedClick() then return end
    local link = ResolveLink(self.ref)
    if link then HandleModifiedItemClick(link) end
end
ns.ResolveItemLink = ResolveLink

function ns.NewItemGrid(parent)
    local g = setmetatable({ parent = parent, buttons = {}, headers = {}, used = 0, usedHeaders = 0,
        byItem = {} }, Grid)
    return g
end

function Grid:AcquireButton()
    self.used = self.used + 1
    local b = self.buttons[self.used]
    if not b then
        b = CreateFrame("ItemButton", nil, self.parent)
        b:SetSize(SLOT, SLOT)
        b.euiSkinned = Ext:SkinItemButton(b)
        b:SetSize(SLOT, SLOT)
        b:SetScript("OnEnter", Button_OnEnter)
        b:SetScript("OnLeave", Button_OnLeave)
        b:SetScript("OnClick", Button_OnClick)
        self.buttons[self.used] = b
    end
    b:Show()
    return b
end

function Grid:AcquireHeader()
    self.usedHeaders = self.usedHeaders + 1
    local h = self.headers[self.usedHeaders]
    if not h then
        h = W.Text(self.parent, 12)
        self.headers[self.usedHeaders] = h
    end
    h:Show()
    return h
end

function Grid:Reset()
    for i = 1, self.used do
        local b = self.buttons[i]
        b:Hide()
        b.ref, b.itemID, b.bound, b.sets = nil, nil, nil, nil
        b:SetAlpha(1)
    end
    for i = 1, self.usedHeaders do self.headers[i]:Hide() end
    self.used, self.usedHeaders = 0, 0
    wipe(self.byItem)
end

-- Paints one button from an encoded stack (sets: equipment set names or nil).
function Grid:Paint(b, enc, sets)
    local id, count, link, bound = ns.DecodeItem(enc)
    b.itemID = id
    b.ref = link or ("item:" .. id)
    b.bound, b.sets = bound, sets
    local _, _, _, _, icon = C_Item.GetItemInfoInstant(id)
    SetItemButtonTexture(b, icon or 134400)
    SetItemButtonCount(b, count)
    local quality = C_Item.GetItemQualityByID(link or id)
    if b.euiSkinned then
        local r, g, bb = 0.25, 0.25, 0.25
        if quality and quality > 1 then
            local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
            if c then r, g, bb = c.r, c.g, c.b end
        end
        Ext:SetItemBorderColor(b, r, g, bb, 1)
    else
        SetItemButtonQuality(b, quality, link or id)
    end
    local list = self.byItem[id]
    if not list then
        list = {}
        self.byItem[id] = list
    end
    list[#list + 1] = b
    if not quality then C_Item.RequestLoadItemDataByID(id) end
end

-- Called when item data arrives: repaint only the affected buttons.
function Grid:OnItemLoaded(itemID)
    local list = self.byItem[itemID]
    if not list then return end
    for i = 1, #list do
        local b = list[i]
        local quality = C_Item.GetItemQualityByID(b.ref)
        if b.euiSkinned then
            local c = quality and quality > 1 and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
            if c then Ext:SetItemBorderColor(b, c.r, c.g, c.b, 1) end
        else
            SetItemButtonQuality(b, quality, b.ref)
        end
    end
end

-- sections = { { title = "...", items = { enc, enc, ... } }, ... }
-- Returns the total content height.
function Grid:Layout(sections, width)
    self:Reset()
    local columns = math.max(1, math.floor((width - 2 * INSET + GAP) / (SLOT + GAP)))
    local y = 0
    for _, section in ipairs(sections) do
        if #section.items > 0 then
            local h = self:AcquireHeader()
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", self.parent, "TOPLEFT", 2, -y - 2)
            h:SetText(section.title or "")
            local r, g, b = Ext:GetAccentColor()
            h:SetTextColor(r, g, b)
            y = y + HEADER_H
            for i, enc in ipairs(section.items) do
                local col = (i - 1) % columns
                local row = math.floor((i - 1) / columns)
                local btn = self:AcquireButton()
                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", self.parent, "TOPLEFT", INSET + col * (SLOT + GAP), -(y + INSET + row * (SLOT + GAP)))
                self:Paint(btn, enc, section.sets and section.sets[i])
                -- a stack the search does not match, shown dimmed
                if section.miss and section.miss[i] then btn:SetAlpha(MISS_ALPHA) end
            end
            local rows = math.ceil(#section.items / columns)
            y = y + INSET + rows * (SLOT + GAP) + 6
        end
    end
    return y
end
