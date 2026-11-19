-------------------------------------------------------------------------------
--  UI/ValueList.lua
--  The browser's "Value" tab: every stack the selected owner keeps that could
--  still be sold, one row per item, owner and location, priced by
--  ns.Prices and sortable by each column.
--
--  What counts: bags, bank, mail, the warband bank and guild banks. Worn gear
--  is in use and stays out; so do auctions, which are already for sale (the
--  Auctions tab sums them). Items of an equipment set are in use as well:
--  they are hidden unless the list is asked to show them, and then form a
--  group of their own below the rest. Bags and worn gear know their set
--  slots; in the bank a soulbound item counts as a set item when a set asks
--  for it and the character has just that one.
--
--  Which owners: a character, a guild bank or the warband bank alone; one
--  realm's characters; or all characters with the warband bank. Guild banks
--  belong to a guild, not to the player, and join only when selected.
--
--  The list draws only the rows in view (a pool as tall as the scroll frame),
--  so thousands of stacks cost a few frames. Built on the tab's first show.
-------------------------------------------------------------------------------
local _, ns = ...
local L = ns.L
local W = ns.W
local Ext = _G.EllesmereUIBagsExt

local ROW_H = 22
local TOOLBAR_H = 26
local HEAD_H = 20
local GAP = 6
local ICON = 18
local MAX_REQUESTS = 200   -- item data requests per render, like the search

local ValueList = { rows = {}, pending = {} }
ns.ValueList = ValueList

-- Columns left to right; the item name takes the width the others leave.
local COLUMNS = {
    { key = "name",   label = "Item" },
    { key = "char",   label = "Character", width = 96 },
    { key = "loc",    label = "Location",  width = 84 },
    { key = "source", label = "Source",    width = 82 },
    { key = "value",  label = "Value",     width = 58, right = true },
    { key = "gain",   label = "Over vendor", width = 62, right = true,
      tooltip = "What the auction house brings beyond selling to a vendor." },
    { key = "bound",  label = "Binding",   width = 64 },
}
ValueList.COLUMNS = COLUMNS

-- Columns that sort largest first on their first click.
local NUMERIC = { value = true, gain = true }

local LOC_ORDER = { bags = 1, bank = 2, mail = 3, warband = 4, guild = 5 }
local LOC_LABEL = { bags = "Bags", bank = "Bank", mail = "Mail", warband = "Warband Bank", guild = "Guild Bank" }
local BOUND_ORDER = { free = 1, wue = 2, account = 3, soul = 4 }

local SOURCE_LABEL = {
    oeRegion = "OE region", oeRealm = "OE realm", auctionator = "Auctionator", tsm = "TSM", vendor = "Vendor",
}
-- Full names for the menu and the options.
local SOURCE_NAME = {
    oeRegion = "Oribos Exchange (region)", oeRealm = "Oribos Exchange (realm)",
    auctionator = "Auctionator", tsm = "TradeSkillMaster", vendor = "Vendor",
}
ValueList.SOURCE_NAME = SOURCE_NAME

-- Source names that are addon names stay as they are in every language.
local function SourceText(map, source)
    local text = map[source]
    if source == "auctionator" or source == "tsm" then return text end
    return L[text]
end
ValueList.SourceText = SourceText

local function BoundText(bound)
    if bound == "soul" then return ITEM_SOULBOUND, 0.6, 0.6, 0.6 end
    if bound == "account" then return ITEM_ACCOUNTBOUND, 0.31, 0.76, 0.97 end
    if bound == "wue" then return ITEM_ACCOUNTBOUND_UNTIL_EQUIP or ITEM_ACCOUNTBOUND, 0.31, 0.76, 0.97 end
    return L["Tradable"], 0.35, 0.85, 0.35
end

-------------------------------------------------------------------------------
--  Data: the owner's sellable stacks merged per owner, location, item and
--  bound state (and set membership), then priced.
-------------------------------------------------------------------------------
local function OwnerLabel(owner)
    if owner == ns.WARBAND_OWNER then return L["Warband Bank"], 0.31, 0.76, 0.97 end
    if owner:sub(1, 1) == "@" then
        local g = ns.db.guilds[owner:sub(2)]
        return (g and g.name) or owner:sub(2), 0.25, 0.75, 0.25
    end
    local c = ns.db.chars[owner]
    local name = (c and c.name) or owner
    if c and c.realm and c.realm ~= ns.GetPlayerRealm() then name = name .. "-" .. c.realm end
    local r, g, b = W.ClassColor(c and c.class)
    return name, r, g, b
end

-- Calls add(owner, loc, items, sets) for every collection of the selection.
-- sets: the container's slot -> set names map (bags only), else nil.
local function EachCollection(selection, add)
    local function Containers(owner, loc, map)
        if type(map) ~= "table" then return end
        for _, cont in pairs(map) do
            if type(cont) == "table" then add(owner, loc, cont.items, cont.sets) end
        end
    end
    local function Mail(owner, list)
        for _, m in ipairs(list or {}) do add(owner, "mail", { m.e }) end
    end
    local function Char(key, c)
        Containers(key, "bags", c.bags)
        Containers(key, "bank", c.bank)
        Mail(key, c.mail and c.mail.items)
        Mail(key, c.mailIncoming)
    end
    if selection.char then
        local c = ns.db.chars[selection.char]
        if c then Char(selection.char, c) end
    elseif selection.guild then
        local g = ns.db.guilds[selection.guild]
        if g then Containers("@" .. selection.guild, "guild", g.tabs) end
    elseif selection.warband then
        Containers(ns.WARBAND_OWNER, "warband", ns.db.warband.bank)
    else
        for key, c in pairs(ns.db.chars) do
            if selection.realm == nil or c.realm == selection.realm then Char(key, c) end
        end
        if selection.realm == nil then Containers(ns.WARBAND_OWNER, "warband", ns.db.warband.bank) end
    end
end

-- Stacks of a collection with their slot: packed strings, mail lists of
-- encoded stacks.
local function EachStack(items, fn)
    if type(items) == "string" then
        for slot, enc in ns.EachItem(items) do fn(enc, slot) end
    elseif type(items) == "table" then
        for i, enc in ipairs(items) do fn(enc, i) end
    end
end

-- -> merged stacks { id, link, bound, count, owner, loc, sets }
local function Collect(selection)
    local merged, list = {}, {}
    EachCollection(selection, function(owner, loc, items, setMap)
        EachStack(items, function(enc, slot)
            local id, count, link, bound = ns.DecodeItem(enc)
            if not id then return end
            local sets = setMap and setMap[slot] or nil
            local key = owner .. "|" .. loc .. "|" .. (link or id) .. "|" .. (bound or "") .. "|" .. (sets or "")
            local m = merged[key]
            if not m then
                m = { id = id, link = link, bound = bound, count = 0, owner = owner, loc = loc, sets = sets }
                merged[key] = m
                list[#list + 1] = m
            end
            m.count = m.count + (count or 1)
        end)
    end)
    return list
end

-- Name, quality and icon from the item cache (battle pets: from their link).
local function ItemDisplay(m)
    local ref = m.link or m.id
    local name, _, quality = C_Item.GetItemInfo(ref)
    if m.link and m.link:find("battlepet:", 1, true) then
        name = m.link:match("|h%[(.-)%]|h") or name
    end
    -- The instant icon needs no item data and is what the item grid shows.
    local icon = select(5, C_Item.GetItemInfoInstant(m.id))
    return name, quality, icon
end

-- The bank has no set locations: a soulbound item there belongs to a set
-- that asks for it when it is the character's only one (worn and every
-- other place counted).
local function BankSetNames(m)
    if m.loc ~= "bank" or m.sets or m.bound ~= "soul" or m.count ~= 1 then return nil end
    local c = ns.db.chars[m.owner]
    local names = c and c.setItemIDs and c.setItemIDs[m.id]
    if not names then return nil end
    local byLoc = ns.Index:Get(m.id)
    local total = 0
    for _, n in pairs(byLoc and byLoc[m.owner] or {}) do total = total + n end
    return total == 1 and names or nil
end

-- Prices every stack (only those the search query matches, if any).
-- -> rows, hidden set stacks, stacks without a price, item IDs still waiting
-- for their data.
local function Build(selection, query)
    ns.Prices.Reset()
    local mode = ns.db.settings.value.source
    local showSets = ns.db.settings.value.showSets
    local rows, setsHidden, unpriced, pending = {}, 0, 0, {}
    for _, m in ipairs(Collect(selection)) do
        local match, waiting = true, false
        if query then match, waiting = ns.Search.Matches(query, m.id) end
        if waiting then pending[#pending + 1] = m.id end
        m.sets = m.sets or BankSetNames(m)
        -- A stack the search filters out counts nowhere, not even as hidden.
        if match and m.sets and not showSets then
            setsHidden = setsHidden + 1
        elseif match then
            local name, quality, icon = ItemDisplay(m)
            if not name then pending[#pending + 1] = m.id end
            local unit, source, auction, prices = ns.Prices.Evaluate(m.id, m.link, m.bound, mode)
            if unit then
                m.name, m.quality, m.icon = name or ("item:" .. m.id), quality, icon
                m.unit, m.source, m.prices = unit, source, prices
                m.value = unit * m.count
                if auction then m.gain = (auction - (prices.vendor or 0)) * m.count end
                m.ownerText, m.ownerR, m.ownerG, m.ownerB = OwnerLabel(m.owner)
                rows[#rows + 1] = m
            elseif name then
                unpriced = unpriced + 1
            end
        end
    end
    return rows, setsHidden, unpriced, pending
end

-- Sort keys; nil sorts last in either direction.
local SORT_VALUE = {
    name   = function(m) return m.name and m.name:lower() end,
    char   = function(m) return m.ownerText:lower() end,
    loc    = function(m) return LOC_ORDER[m.loc] end,
    source = function(m) return SourceText(SOURCE_LABEL, m.source) end,
    value  = function(m) return m.value end,
    gain   = function(m) return m.gain end,
    bound  = function(m) return BOUND_ORDER[m.bound or "free"] end,
}

local function Sort(rows, key, desc)
    local get = SORT_VALUE[key] or SORT_VALUE.value
    table.sort(rows, function(a, b)
        if (a.sets ~= nil) ~= (b.sets ~= nil) then return b.sets ~= nil end   -- set group last
        local va, vb = get(a), get(b)
        if va ~= vb then
            if va == nil then return false end
            if vb == nil then return true end
            if desc then return va > vb end
            return va < vb
        end
        -- Ties: most valuable first, then a stable order.
        if a.value ~= b.value then return a.value > b.value end
        if a.ownerText ~= b.ownerText then return a.ownerText < b.ownerText end
        return (a.link or tostring(a.id)) < (b.link or tostring(b.id))
    end)
end
ValueList.Sort = Sort

-- Rows with a group title before the equipment set stacks.
local function WithGroups(rows)
    local out = {}
    for _, m in ipairs(rows) do
        if m.sets and (#out == 0 or not out[#out].sets) then
            out[#out + 1] = { header = L["Equipment sets"], sets = true }
        end
        out[#out + 1] = m
    end
    return out
end

-------------------------------------------------------------------------------
--  Tooltip: the item as the grid shows it, plus every source's price.
-------------------------------------------------------------------------------
local function PriceLines(tooltip, m)
    local s = ns.db.settings.value
    tooltip:AddLine(" ")
    local header = s.ahCut and string.format(L["Price per unit (auction prices after the %d%% cut)"], ns.Prices.AH_CUT * 100)
        or L["Price per unit"]
    tooltip:AddLine(header, 1, 0.82, 0)
    local auctionator = ns.Prices.AuctionatorState()
    for _, source in ipairs(ns.Prices.SOURCES) do
        -- Price addons that are not loaded have nothing to say.
        if ns.Prices.IsAvailable(source) then
            local price = m.prices[source]
            local text
            if not ns.Prices.Applies(source, m.bound) then
                text = "|cff808080" .. L["bound"] .. "|r"
            elseif source == "auctionator" and auctionator == "empty" then
                text = "|cff808080" .. L["no scan yet"] .. "|r"
            elseif source == "tsm" and not ns.Prices.TSMPriceString() then
                text = "|cff808080" .. L["no price string set"] .. "|r"
            elseif price then
                text = W.FormatMoney(ns.Prices.Net(source, price))
                if source == "auctionator" and m.prices.auctionatorAge then
                    text = string.format(L["%s (seen %d days ago)"], text, m.prices.auctionatorAge)
                end
            elseif source == "auctionator" then
                text = "|cff808080" .. L["not in the scans"] .. "|r"
            else
                text = "|cff808080-|r"
            end
            local label = SourceText(SOURCE_NAME, source)
            if source == m.source then label = "> " .. label end
            tooltip:AddDoubleLine(label, text, 1, 1, 1, 1, 1, 1)
        end
    end
    if m.count > 1 then
        tooltip:AddDoubleLine(string.format(L["Total (%d)"], m.count), W.FormatMoney(m.value), 1, 0.82, 0, 1, 1, 1)
    end
end

-------------------------------------------------------------------------------
--  Frames (built on the tab's first show)
-------------------------------------------------------------------------------
-- Columns are narrow: whole gold from 1g up, silver and copper below it.
-- The tooltip has the exact amounts.
local function ShortMoney(copper)
    if copper >= 10000 then return W.FormatMoney(copper - copper % 10000) end
    return W.FormatMoney(copper)
end

local function FormatGain(copper)
    if not copper then return "-" end
    if copper < 0 then return "|cffff6060-" .. ShortMoney(-copper) .. "|r" end
    return ShortMoney(copper)
end

local function Row_OnEnter(self)
    local m = self.data
    if not m or m.header then return end
    ns.ShowStoredItemTooltip(self, m.link or ("item:" .. m.id), m.bound, m.sets, m.id, PriceLines, m)
end

local function Row_OnLeave()
    W.GetTooltip():Hide()
    W.HidePetTooltip()
end

local function Row_OnClick(self)
    local m = self.data
    if not m or m.header or not IsModifiedClick() then return end
    local link = ns.ResolveItemLink(m.link or ("item:" .. m.id))
    if link then HandleModifiedItemClick(link) end
end

local function CreateRow(parent)
    local r = CreateFrame("Button", nil, parent)
    r:SetHeight(ROW_H)
    r.hl = r:CreateTexture(nil, "HIGHLIGHT")
    r.hl:SetAllPoints()
    r.hl:SetColorTexture(1, 1, 1, 0.05)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(ICON, ICON)
    r.icon:SetPoint("LEFT", 2, 0)
    r.count = W.Text(r, 9)
    r.count:SetPoint("BOTTOMRIGHT", r.icon, "BOTTOMRIGHT", 1, -1)
    r.count:SetJustifyH("RIGHT")
    r.cells = {}
    for i, col in ipairs(COLUMNS) do
        local fs = W.Text(r, i == 1 and 12 or 11)
        if col.right then fs:SetJustifyH("RIGHT") end
        r.cells[col.key] = fs
    end
    r.title = W.Text(r, 12)
    r.title:SetPoint("LEFT", 2, 0)
    r:SetScript("OnEnter", Row_OnEnter)
    r:SetScript("OnLeave", Row_OnLeave)
    r:SetScript("OnClick", Row_OnClick)
    return r
end

-- x offset and width of every column for a list width.
local function ColumnLayout(width)
    local fixed = ICON + 4
    for i = 2, #COLUMNS do fixed = fixed + COLUMNS[i].width + GAP end
    local layout = {}
    local x = ICON + 4 + 4
    for _, col in ipairs(COLUMNS) do
        local w = col.width or math.max(40, width - fixed - 4)
        layout[col.key] = { x = x, w = w }
        x = x + w + GAP
    end
    return layout
end

local function PlaceCells(r, layout)
    for _, col in ipairs(COLUMNS) do
        local fs, place = r.cells[col.key], layout[col.key]
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", r, "LEFT", place.x, 0)
        fs:SetWidth(place.w)
    end
end

local function Header_OnClick(self)
    local s = ns.db.settings.value
    if s.sort == self.key then
        s.sortDesc = not s.sortDesc
    else
        s.sort, s.sortDesc = self.key, NUMERIC[self.key] == true
    end
    ns.Browser:Refresh()
end

local function Header_OnEnter(self)
    if not self.tip then return end
    local tooltip = W.GetTooltip()
    tooltip:SetOwner(self, "ANCHOR_TOP")
    tooltip:AddLine(L[self.tip], 1, 1, 1, true)
    tooltip:Show()
end

function ValueList:SourceMenu()
    local entries = {}
    local s = ns.db.settings.value
    local function Entry(source, text)
        local available = source == "auto" or ns.Prices.IsAvailable(source)
        entries[#entries + 1] = {
            text = (s.source == source and "> " or "") .. text,
            disabled = not available,
            tooltip = not available and L["Needs the addon installed and loaded."] or nil,
            onClick = function()
                s.source = source
                ns.Browser:Refresh()
            end,
        }
    end
    Entry("auto", L["Automatic"])
    for _, source in ipairs(ns.Prices.SOURCES) do Entry(source, SourceText(SOURCE_NAME, source)) end
    W.ShowMenu(ns.Browser:GetFrame(), L["Price source"], entries)
end

function ValueList:Build(f)
    if self.frame then return end
    local v = CreateFrame("Frame", nil, f.content)
    v:SetPoint("TOPLEFT", 6, -6)
    v:SetPoint("TOPRIGHT", -6, -6)
    v:SetHeight(TOOLBAR_H + HEAD_H)
    v:Hide()
    self.frame = v

    v.source = W.Button(v, "", 220, 22)
    v.source:SetPoint("TOPLEFT", 0, 0)
    v.source:SetScript("OnClick", function() ValueList:SourceMenu() end)

    v.sets = W.Button(v, "", 180, 22)
    v.sets:SetPoint("LEFT", v.source, "RIGHT", 6, 0)
    v.sets:SetScript("OnClick", function()
        local s = ns.db.settings.value
        s.showSets = not s.showSets
        ns.Browser:Refresh()
    end)

    v.heads = {}
    for _, col in ipairs(COLUMNS) do
        local h = CreateFrame("Button", nil, v)
        h:SetHeight(HEAD_H)
        h.key, h.tip = col.key, col.tooltip
        h.label = W.Text(h, 11, nil, 0.8, 0.8, 0.8)
        h.label:SetAllPoints()
        if col.right then h.label:SetJustifyH("RIGHT") end
        h.hl = h:CreateTexture(nil, "HIGHLIGHT")
        h.hl:SetAllPoints()
        h.hl:SetColorTexture(1, 1, 1, 0.05)
        h:SetScript("OnClick", Header_OnClick)
        h:SetScript("OnEnter", Header_OnEnter)
        h:SetScript("OnLeave", function() W.GetTooltip():Hide() end)
        v.heads[col.key] = h
    end

    self.pool = {}
    -- Scrolling moves the drawn window over the data.
    f.scroll:HookScript("OnVerticalScroll", function()
        if v:IsShown() then ValueList:Draw() end
    end)
end

-------------------------------------------------------------------------------
--  Drawing
-------------------------------------------------------------------------------
-- Rows in view -> pool frames placed at their row's height in the content.
function ValueList:Draw()
    local f = self.browser
    if not f then return end
    local content = f.scroll.content
    local offset = f.scroll:GetVerticalScroll() or 0
    local view = f.scroll:GetHeight()
    if not view or view < ROW_H then view = 400 end
    local first = math.max(1, math.floor(offset / ROW_H) + 1)
    local count = math.ceil(view / ROW_H) + 1
    local layout = self.layout
    for i = 1, count do
        local r = self.pool[i]
        local m = self.list[first + i - 1]
        if m then
            if not r then
                r = CreateRow(content)
                self.pool[i] = r
            end
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(first + i - 2) * ROW_H)
            r:SetWidth(self.width)
            self:Paint(r, m, layout)
            r:Show()
        elseif r then
            r:Hide()
            r.data = nil
        end
    end
    for i = count + 1, #self.pool do
        self.pool[i]:Hide()
        self.pool[i].data = nil
    end
end

function ValueList:Paint(r, m, layout)
    r.data = m
    if r.layoutWidth ~= self.width then
        PlaceCells(r, layout)
        r.layoutWidth = self.width
    end
    local cells = r.cells
    if m.header then
        r.title:SetText(m.header)
        r.title:SetTextColor(Ext:GetAccentColor())
        r.title:Show()
        r.icon:Hide()
        r.count:SetText("")
        for _, fs in pairs(cells) do fs:SetText("") end
        return
    end
    r.title:Hide()
    r.icon:Show()
    r.icon:SetTexture(m.icon or 134400)
    r.count:SetText(m.count > 1 and BreakUpLargeNumbers(m.count) or "")
    local color = m.quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[m.quality]
    cells.name:SetText(m.name)
    if color then cells.name:SetTextColor(color.r, color.g, color.b) else cells.name:SetTextColor(1, 1, 1) end
    cells.char:SetText(m.ownerText)
    cells.char:SetTextColor(m.ownerR, m.ownerG, m.ownerB)
    cells.loc:SetText(ns.LocationIcon(m.loc, 12) .. " " .. L[LOC_LABEL[m.loc]])
    local sourceText = SourceText(SOURCE_LABEL, m.source)
    if m.source == "auctionator" and m.prices.auctionatorAge then
        sourceText = sourceText .. string.format(" |cff888888%dd|r", m.prices.auctionatorAge)
    end
    cells.source:SetText(sourceText)
    cells.value:SetText(ShortMoney(m.value))
    cells.gain:SetText(FormatGain(m.gain))
    local text, br, bg, bb = BoundText(m.bound)
    cells.bound:SetText(text)
    cells.bound:SetTextColor(br, bg, bb)
end

-- The browser's owner -> the selection the list collects.
local function Selection(owner)
    if owner == ns.Browser.ALL_OWNER then return {} end
    local realm = owner:match("^%*realm:(.*)$")
    if realm then return { realm = realm } end
    if owner == ns.WARBAND_OWNER then return { warband = true } end
    if owner:sub(1, 1) == "@" then return { guild = owner:sub(2) } end
    return { char = owner }
end
ValueList.Selection = Selection

-- Shows the list for an owner, filtered by a parsed search query (or nil).
-- -> content height, row count, footer text
function ValueList:Render(f, owner, width, query)
    self:Build(f)
    self.browser = f
    self.width = width
    self.layout = ColumnLayout(width)
    local v = self.frame
    v:Show()
    f.scroll:ClearAllPoints()
    f.scroll:SetPoint("TOPLEFT", 6, -(6 + TOOLBAR_H + HEAD_H))
    f.scroll:SetPoint("BOTTOMRIGHT", -22, 6)

    local s = ns.db.settings.value
    local sourceName = s.source == "auto" and L["Automatic"] or SourceText(SOURCE_NAME, s.source)
    v.source:SetText(string.format(L["Price: %s"], sourceName))
    v.sets:SetText(s.showSets and L["Hide equipment sets"] or L["Show equipment sets"])
    for _, col in ipairs(COLUMNS) do
        local h, place = v.heads[col.key], self.layout[col.key]
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", v, "TOPLEFT", place.x, -TOOLBAR_H)
        h:SetWidth(place.w)
        local arrow = ""
        if s.sort == col.key then arrow = s.sortDesc and " v" or " ^" end
        h.label:SetText(L[col.label] .. arrow)
    end

    local rows, setsHidden, unpriced, pending = Build(Selection(owner), query)
    wipe(self.pending)
    for i = 1, math.min(#pending, MAX_REQUESTS) do
        self.pending[pending[i]] = true
        C_Item.RequestLoadItemDataByID(pending[i])
    end
    Sort(rows, s.sort, s.sortDesc)
    self.rows = rows
    self.list = WithGroups(rows)
    self:Draw()

    local total, setTotal = 0, 0
    for _, m in ipairs(rows) do
        if m.sets then setTotal = setTotal + m.value else total = total + m.value end
    end
    local footer = string.format(L["Value: %s in %d stacks"], W.FormatMoney(total), #rows)
    if s.showSets and setTotal > 0 then
        footer = footer .. "   " .. string.format(L["Equipment sets: %s"], W.FormatMoney(setTotal))
    elseif setsHidden > 0 then
        footer = footer .. "   " .. string.format(L["Hidden equipment set stacks: %d"], setsHidden)
    end
    if unpriced > 0 then
        footer = footer .. "   " .. string.format(L["Without a price: %d"], unpriced)
    end
    return #self.list * ROW_H, #rows, footer
end

-- Leaves the tab: the scroll frame takes the full content area again.
function ValueList:Hide(f)
    if not self.frame or not self.frame:IsShown() then return end
    self.frame:Hide()
    for _, r in ipairs(self.pool) do
        r:Hide()
        r.data = nil
    end
    f.scroll:ClearAllPoints()
    f.scroll:SetPoint("TOPLEFT", 6, -6)
    f.scroll:SetPoint("BOTTOMRIGHT", -22, 6)
end

-- ITEM_DATA_LOAD_RESULT: true when the list waits for this item.
function ValueList:OnItemLoaded(itemID)
    if not self.pending[itemID] then return false end
    self.pending[itemID] = nil
    return true
end
