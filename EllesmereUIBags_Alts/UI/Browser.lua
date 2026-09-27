-------------------------------------------------------------------------------
--  UI/Browser.lua
--  The cross-character browser window. Built on first open, never before
--  (acceptance criterion 1). While hidden it listens to nothing; data changes
--  only mark it stale and it re-renders on the next show.
-------------------------------------------------------------------------------
local _, ns = ...
local L = ns.L
local W = ns.W
local Ext = _G.EllesmereUIBagsExt

local FRAME_NAME = "EllesmereUIBagsAltsBrowser"
local WIDTH, HEIGHT = 920, 580
local SIDEBAR_W = 220
local PAD = 10
local ROW_H = 22
local RESULT_H = 38

local Browser = { stale = true }
ns.Browser = Browser

-- Pseudo owners of the aggregated views: "All characters" and one per realm
-- (the realm headers of the sidebar).
local ALL_OWNER = "*all"
local REALM_PREFIX = "*realm:"
Browser.ALL_OWNER = ALL_OWNER
function Browser.RealmOwner(realm) return REALM_PREFIX .. realm end

-- nil for a single owner, else the scope of an aggregated view:
-- {} = everything, { realm = r } = characters and guilds of one realm.
local function AggregateScope(owner)
    if owner == ALL_OWNER then return {} end
    if owner and owner:sub(1, #REALM_PREFIX) == REALM_PREFIX then
        return { realm = owner:sub(#REALM_PREFIX + 1) }
    end
    return nil
end

local function InScope(scope, realm)
    return scope.realm == nil or scope.realm == realm
end

local frame
local state = { owner = nil, tab = "bags", query = nil, queryText = "" }
local pendingSearch = {}   -- itemID -> true while waiting for item data

local CHAR_TABS = {
    { key = "all",      label = "Everything", allOnly = true },
    { key = "bags",     label = "Bags" },
    { key = "bank",     label = "Bank" },
    { key = "equipped", label = "Equipped" },
    { key = "mail",     label = "Mail" },
    { key = "auctions", label = "Auctions" },
    { key = "currency", label = "Currency" },
}

local BAG_TITLES = {
    [0] = "Backpack", [1] = "Bag 1", [2] = "Bag 2", [3] = "Bag 3", [4] = "Bag 4", [5] = "Reagent Bag",
}

-------------------------------------------------------------------------------
--  Data -> sections
-------------------------------------------------------------------------------
local function SortedIDs(map)
    local ids = {}
    for id in pairs(map or {}) do ids[#ids + 1] = id end
    table.sort(ids)
    return ids
end

-- -> list of encoded stacks in slot order, parallel list of set names (or nil)
local function ItemsInSlotOrder(container)
    local out, sets = {}, {}
    if not container or not container.items then return out, sets end
    for _, slot in ipairs(SortedIDs(container.items)) do
        out[#out + 1] = container.items[slot]
        sets[#out] = container.sets and container.sets[slot] or nil
    end
    return out, sets
end

local function Section(title, container)
    local items, sets = ItemsInSlotOrder(container)
    return { title = title, items = items, sets = sets }
end

local function MailItems(list)
    local out = {}
    for i = 1, #(list or {}) do out[#out + 1] = list[i].e end
    return out
end

-- Regroups all stacks of the given sections by EUI category, if available.
local function ByEUICategory(sections)
    if not ns.db.settings.ui.useEUICategories or not Ext:IsBagsLoaded() then return sections end
    local groups, order = {}, {}
    for _, section in ipairs(sections) do
        for i, enc in ipairs(section.items) do
            local id, _, link = ns.DecodeItem(enc)
            local ref = link or select(2, C_Item.GetItemInfo(id))
            local idx, name = Ext:ClassifyItem(ref, id)
            if not idx then return sections end   -- categories unavailable: keep containers
            local g = groups[idx]
            if not g then
                g = { title = name or ("#" .. idx), items = {}, sets = {}, idx = idx }
                groups[idx] = g
                order[#order + 1] = g
            end
            g.items[#g.items + 1] = enc
            g.sets[#g.items] = section.sets and section.sets[i] or nil
        end
    end
    table.sort(order, function(a, b) return a.idx < b.idx end)
    return order
end

local function CharSections(c, tab)
    local sections = {}
    if tab == "bags" then
        for _, bagID in ipairs(SortedIDs(c.bags)) do
            sections[#sections + 1] = Section(L[BAG_TITLES[bagID] or ("Bag " .. bagID)], c.bags[bagID])
        end
        return ByEUICategory(sections)
    elseif tab == "bank" then
        local i = 0
        for _, tabID in ipairs(SortedIDs(c.bank)) do
            i = i + 1
            local cont = c.bank[tabID]
            sections[#sections + 1] = Section((cont.name and cont.name ~= "") and cont.name or string.format(L["Tab %d"], i), cont)
        end
        return ByEUICategory(sections)
    elseif tab == "equipped" then
        sections[1] = Section(L["Equipped"], c.equipped)
    elseif tab == "mail" then
        sections[1] = { title = L["Inbox"], items = MailItems(c.mail and c.mail.items) }
        sections[2] = { title = L["In transit"], items = MailItems(c.mailIncoming) }
    elseif tab == "auctions" then
        sections[1] = { title = L["Active auctions"], items = MailItems(c.auctions and c.auctions.items) }
    end
    return sections
end

local function TabSections(tabs)
    local sections = {}
    local i = 0
    for _, id in ipairs(SortedIDs(tabs)) do
        i = i + 1
        local cont = tabs[id]
        sections[#sections + 1] = Section((cont.name and cont.name ~= "") and cont.name or string.format(L["Tab %d"], i), cont)
    end
    return sections
end

-------------------------------------------------------------------------------
--  All characters / one realm: every stored stack of a kind merged per item
--  (the link for gear and other rich items, the itemID for plain stacks) and
--  grouped by item class, or by EUI category when that option is on. The
--  warband bank is account wide and therefore only part of "All characters".
-------------------------------------------------------------------------------
local function EachContainer(map, add)
    if type(map) ~= "table" then return end
    for _, cont in pairs(map) do
        if type(cont) == "table" then add(cont.items) end
    end
end

-- Calls add(items) for every item collection of the scope shown on the tab.
local function CollectAll(scope, tab, add)
    local all = tab == "all"
    for _, c in pairs(ns.db.chars) do
        if InScope(scope, c.realm) then
            if all or tab == "bags" then EachContainer(c.bags, add) end
            if all or tab == "bank" then EachContainer(c.bank, add) end
            if all or tab == "equipped" then add(c.equipped and c.equipped.items) end
            if all or tab == "mail" then
                add(c.mail and c.mail.items)
                add(c.mailIncoming)
            end
            if all or tab == "auctions" then add(c.auctions and c.auctions.items) end
        end
    end
    if (all or tab == "bank") and not scope.realm then EachContainer(ns.db.warband.bank, add) end
    if all then
        for key, g in pairs(ns.db.guilds) do
            if InScope(scope, select(2, ns.SplitKey(key))) then EachContainer(g.tabs, add) end
        end
    end
end

local function MergedStacks(scope, tab)
    local merged, list = {}, {}
    CollectAll(scope, tab, function(items)
        if type(items) ~= "table" then return end
        for _, v in pairs(items) do
            local enc = type(v) == "table" and v.e or v
            if type(enc) == "string" then
                local id, count, link, bound = ns.DecodeItem(enc)
                if id then
                    local key = link or id
                    local m = merged[key]
                    if not m then
                        m = { id = id, link = link, count = 0, bound = bound,
                              quality = C_Item.GetItemQualityByID(link or id) or -1 }
                        merged[key] = m
                        list[#list + 1] = m
                    elseif m.bound ~= bound then
                        m.bound = nil   -- bound on one character, free on another
                    end
                    m.count = m.count + (count or 1)
                end
            end
        end
    end)
    return list
end

local function StackOrder(a, b)
    if a.quality ~= b.quality then return a.quality > b.quality end
    if a.id ~= b.id then return a.id < b.id end
    return (a.link or "") < (b.link or "")
end

local function AllSections(scope, tab)
    local groups, order = {}, {}
    for _, m in ipairs(MergedStacks(scope, tab)) do
        local classID = select(6, C_Item.GetItemInfoInstant(m.id)) or Enum.ItemClass.Miscellaneous
        local g = groups[classID]
        if not g then
            g = { classID = classID, title = C_Item.GetItemClassInfo(classID), stacks = {} }
            groups[classID] = g
            order[#order + 1] = g
        end
        g.stacks[#g.stacks + 1] = m
    end
    table.sort(order, function(a, b) return a.classID < b.classID end)
    local sections = {}
    for _, g in ipairs(order) do
        table.sort(g.stacks, StackOrder)
        local items = {}
        for i, m in ipairs(g.stacks) do items[i] = ns.EncodeItem(m.id, m.count, m.link, m.bound) end
        sections[#sections + 1] = { title = g.title, items = items }
    end
    return ByEUICategory(sections)
end

-- id -> quantity summed over the characters of the scope; shared: id ->
-- quantity of the most recently seen one (warband-wide currencies hold the
-- same value on every character, so they are not summed).
local function AllCurrencyTotals(scope)
    local totals, shared, at = {}, {}, {}
    for _, c in pairs(ns.db.chars) do
        local seen = c.lastSeen or 0
        for id, qty in pairs(InScope(scope, c.realm) and c.currency or {}) do
            totals[id] = (totals[id] or 0) + qty
            if not at[id] or seen > at[id] then
                at[id] = seen
                shared[id] = qty
            end
        end
    end
    return totals, shared
end

-------------------------------------------------------------------------------
--  Frame construction (lazy)
-------------------------------------------------------------------------------
local function SavePosition(self)
    local point, _, relPoint, x, y = self:GetPoint(1)
    ns.db.settings.ui.browserPoint = { point, relPoint, x, y }
end

local function RestorePosition(f)
    local p = ns.db.settings.ui.browserPoint
    f:ClearAllPoints()
    if type(p) == "table" and p[1] then
        f:SetPoint(p[1], UIParent, p[2] or p[1], p[3] or 0, p[4] or 0)
    else
        f:SetPoint("CENTER")
    end
end

local function CreateSidebarRow(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(ROW_H)
    b.left = W.Text(b, 12)
    b.left:SetPoint("LEFT", 6, 0)
    b.left:SetPoint("RIGHT", -70, 0)
    b.right = W.Text(b, 11, nil, 0.8, 0.8, 0.8)
    b.right:SetPoint("RIGHT", -6, 0)
    b.right:SetJustifyH("RIGHT")
    b.sel = b:CreateTexture(nil, "BACKGROUND")
    b.sel:SetAllPoints()
    b.sel:SetColorTexture(1, 1, 1, 0.10)
    b.sel:Hide()
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints()
    b.hl:SetColorTexture(1, 1, 1, 0.05)
    b:SetScript("OnClick", function(self)
        if self.ownerKey then Browser:Select(self.ownerKey) end
    end)
    return b
end

local function CreateResultRow(parent)
    local r = CreateFrame("Button", nil, parent)
    r:SetHeight(RESULT_H)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(RESULT_H - 6, RESULT_H - 6)
    r.icon:SetPoint("LEFT", 2, 0)
    -- Corner anchors on both sides keep each line one text row high.
    r.name = W.Text(r, 13)
    r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 8, -2)
    r.name:SetPoint("TOPRIGHT", r, "TOPRIGHT", -80, -5)
    r.detail = W.Text(r, 11, nil, 0.75, 0.75, 0.75)
    r.detail:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 8, 2)
    r.detail:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", -8, 5)
    r.total = W.Text(r, 14)
    r.total:SetPoint("TOPRIGHT", -8, -4)
    r.total:SetJustifyH("RIGHT")
    r.hl = r:CreateTexture(nil, "HIGHLIGHT")
    r.hl:SetAllPoints()
    r.hl:SetColorTexture(1, 1, 1, 0.05)
    r:SetScript("OnEnter", function(self)
        if not self.itemID then return end
        local tooltip = W.GetTooltip()
        tooltip:SetOwner(self, "ANCHOR_RIGHT")
        tooltip:SetHyperlink("item:" .. self.itemID)
        tooltip:Show()
    end)
    r:SetScript("OnLeave", function() W.GetTooltip():Hide() end)
    r:SetScript("OnClick", function(self)
        if self.itemID and IsModifiedClick() then
            local _, link = C_Item.GetItemInfo(self.itemID)
            if link then HandleModifiedItemClick(link) end
        end
    end)
    return r
end

-- Currency groups, in display order. Warband-wide currencies are shared by all
-- characters (neither bound nor transferable); that group shows only if used.
local CURRENCY_GROUPS = {
    { key = "bound",       title = "Character-bound" },
    { key = "transferable", title = "Transferable" },
    { key = "warband",     title = "Warband-wide (shared)" },
}

local function CurrencyKind(id, info)
    local t, w
    if type(info) == "table" then t, w = info.isAccountTransferable, info.isAccountWide end
    if t == nil and w == nil then
        local meta = ns.db.currencyMeta and ns.db.currencyMeta[id]
        if meta then t, w = meta.t, meta.w end
    end
    if w then return "warband" end
    if t then return "transferable" end
    return "bound"
end

-- Character name in class colour, with the realm when it is not the player's.
local function CharLabel(key)
    local c = ns.db.chars[key]
    local name = (c and c.name) or key
    if c and c.realm and c.realm ~= ns.GetPlayerRealm() then name = name .. "-" .. c.realm end
    local r, g, b = W.ClassColor(c and c.class)
    return string.format("|cff%02x%02x%02x%s|r", r * 255, g * 255, b * 255, name)
end

local function FormatQty(n)
    return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n)
end

-- Currency tooltip: Blizzard's own currency tooltip plus who holds how many.
local function CurrencyRow_OnEnter(self)
    if not self.currencyID then return end
    local id = self.currencyID
    local tooltip = W.GetTooltip()
    tooltip:SetOwner(self, "ANCHOR_RIGHT")
    tooltip:SetCurrencyByID(id)
    local rows, total = {}, 0
    for key, c in pairs(ns.db.chars) do
        local qty = c.currency and c.currency[id]
        if qty then
            rows[#rows + 1] = { key = key, qty = qty }
            total = total + qty
        end
    end
    table.sort(rows, function(a, b)
        if a.qty ~= b.qty then return a.qty > b.qty end
        return a.key < b.key
    end)
    if self.kind == "warband" then
        tooltip:AddLine(" ")
        tooltip:AddLine(L["Warband-wide (shared)"], 0.31, 0.76, 0.97)
    elseif #rows > 0 then
        tooltip:AddLine(" ")
        for _, row in ipairs(rows) do
            tooltip:AddDoubleLine(CharLabel(row.key), FormatQty(row.qty), 1, 0.82, 0, 1, 1, 1)
        end
        if #rows > 1 then tooltip:AddDoubleLine(L["Total"], FormatQty(total), 1, 0.82, 0, 1, 1, 1) end
    end
    tooltip:Show()
end

local function CreateCurrencyRow(parent)
    local r = CreateFrame("Frame", nil, parent)
    r:SetHeight(ROW_H)
    r:EnableMouse(true)
    r:SetScript("OnEnter", CurrencyRow_OnEnter)
    r:SetScript("OnLeave", function() W.GetTooltip():Hide() end)
    r.hl = r:CreateTexture(nil, "HIGHLIGHT")
    r.hl:SetAllPoints()
    r.hl:SetColorTexture(1, 1, 1, 0.05)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(ROW_H - 4, ROW_H - 4)
    r.icon:SetPoint("LEFT", 2, 0)
    r.name = W.Text(r, 12)
    r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
    r.qty = W.Text(r, 12)
    r.qty:SetPoint("RIGHT", -8, 0)
    r.qty:SetJustifyH("RIGHT")
    return r
end

local function Pool(factory, parent)
    return { items = {}, used = 0, factory = factory, parent = parent }
end

local function PoolAcquire(pool)
    pool.used = pool.used + 1
    local obj = pool.items[pool.used]
    if not obj then
        obj = pool.factory(pool.parent)
        pool.items[pool.used] = obj
    end
    obj:Show()
    return obj
end

local function PoolReset(pool)
    for i = 1, pool.used do pool.items[i]:Hide() end
    pool.used = 0
end

function Browser:Build()
    if frame then return frame end
    local f = W.Window(FRAME_NAME, WIDTH, HEIGHT)
    f:SetScale(ns.db.settings.ui.browserScale or 1)
    f:Hide()
    f.OnMoved = SavePosition
    RestorePosition(f)
    frame = f

    f.title = W.Text(f, 15)
    f.title:SetPoint("TOPLEFT", PAD + 2, -PAD)
    f.title:SetText(L["Alts"] .. "  |cff888888" .. L["all characters"] .. "|r")

    f.close = W.CloseButton(f)
    f.close:SetPoint("TOPRIGHT", -4, -4)
    f.close:SetScript("OnClick", function() Browser:Close() end)

    f.search = W.EditBox(f, 240, 22)
    f.search:SetPoint("TOPRIGHT", -40, -PAD + 2)
    -- Hook (not replace) so SearchBoxTemplate keeps its clear button and
    -- instructions; the clear button changes text without user input too.
    f.search:HookScript("OnTextChanged", function(box)
        Browser:SetQuery(box:GetText())
    end)
    f.search:HookScript("OnEnterPressed", function(box) box:ClearFocus() end)

    -- Sidebar
    f.sidebar = W.Panel(f, true)
    f.sidebar:SetPoint("TOPLEFT", PAD, -40)
    f.sidebar:SetPoint("BOTTOMLEFT", PAD, 40)
    f.sidebar:SetWidth(SIDEBAR_W)
    f.sideScroll = W.Scroll(f.sidebar)
    f.sideScroll:SetPoint("TOPLEFT", 4, -4)
    f.sideScroll:SetPoint("BOTTOMRIGHT", -18, 4)
    f.sideRows = Pool(CreateSidebarRow, f.sideScroll.content)
    f.sideHeaders = Pool(function(parent) return W.Text(parent, 11, nil, 0.6, 0.6, 0.6) end, f.sideScroll.content)

    -- Tabs (anchored per render: the visible set depends on the owner)
    f.tabs = {}
    for _, def in ipairs(CHAR_TABS) do
        local tab = W.Tab(f, L[def.label], function() Browser:SelectTab(def.key) end)
        tab.key, tab.allOnly = def.key, def.allOnly
        f.tabs[#f.tabs + 1] = tab
    end

    -- Content
    f.content = W.Panel(f, true)
    f.content:SetPoint("TOPLEFT", f.sidebar, "TOPRIGHT", PAD, -26)
    f.content:SetPoint("BOTTOMRIGHT", -PAD, 40)
    f.scroll = W.Scroll(f.content)
    f.scroll:SetPoint("TOPLEFT", 6, -6)
    f.scroll:SetPoint("BOTTOMRIGHT", -22, 6)
    f.grid = ns.NewItemGrid(f.scroll.content)
    f.results = Pool(CreateResultRow, f.scroll.content)
    f.currencies = Pool(CreateCurrencyRow, f.scroll.content)
    f.empty = W.Text(f.scroll.content, 13, nil, 0.6, 0.6, 0.6)
    f.empty:SetPoint("TOPLEFT", 4, -8)

    -- Footer
    f.footer = W.Text(f, 11, nil, 0.75, 0.75, 0.75)
    f.footer:SetPoint("BOTTOMLEFT", PAD + 2, 14)
    f.footer:SetPoint("BOTTOMRIGHT", -180, 14)
    f.delete = W.Button(f, L["Delete data"], 150, 22)
    f.delete:SetPoint("BOTTOMRIGHT", -PAD, 9)
    f.delete:SetScript("OnClick", function() Browser:ConfirmDelete() end)

    f:SetScript("OnShow", function()
        ns.RegisterEvent(Browser, "ITEM_DATA_LOAD_RESULT", function(_, _, itemID, success)
            if not success then return end
            if frame.grid then frame.grid:OnItemLoaded(itemID) end
            if pendingSearch[itemID] then
                pendingSearch[itemID] = nil
                Browser:RequestRefresh()
            end
        end)
        if Browser.stale then Browser:Refresh() end
    end)
    f:SetScript("OnHide", function()
        f:SetFrameStrata("HIGH")
        ns.UnregisterEvent(Browser, "ITEM_DATA_LOAD_RESULT")
        f:SetScript("OnUpdate", nil)
        wipe(pendingSearch)
    end)

    local function MarkStale() Browser:RequestRefresh() end
    ns.On("CHAR_UPDATED", Browser, MarkStale)
    ns.On("WARBAND_UPDATED", Browser, MarkStale)
    ns.On("GUILD_UPDATED", Browser, MarkStale)
    ns.On("DATA_RESET", Browser, function()
        if state.owner and not Browser:OwnerExists(state.owner) then state.owner = nil end
        MarkStale()
    end)
    return f
end

-------------------------------------------------------------------------------
--  State
-------------------------------------------------------------------------------
function Browser:OwnerExists(owner)
    if owner == ns.WARBAND_OWNER or owner == ALL_OWNER then return true end
    local scope = AggregateScope(owner)
    if scope then
        for _, c in pairs(ns.db.chars) do
            if c.realm == scope.realm then return true end
        end
        return false
    end
    if owner:sub(1, 1) == "@" then return ns.db.guilds[owner:sub(2)] ~= nil end
    return ns.db.chars[owner] ~= nil
end

function Browser:Select(owner)
    state.owner = owner
    self:Refresh()
end

function Browser:SelectTab(tab)
    state.tab = tab
    self:Refresh()
end

function Browser:SetQuery(text)
    text = text or ""
    if text == state.queryText then return end
    state.queryText = text
    state.query = ns.Search.Parse(text)
    self:Refresh()
end

function Browser:GetState() return state end

-- Coalesces bursts of data events into one render on the next frame while
-- shown (self-removing one-shot OnUpdate, not polling); hidden -> stale flag.
function Browser:RequestRefresh()
    self.stale = true
    if not frame or not frame:IsShown() then return end
    frame:SetScript("OnUpdate", function(f)
        f:SetScript("OnUpdate", nil)
        Browser:Refresh()
    end)
end

-------------------------------------------------------------------------------
--  Rendering
-------------------------------------------------------------------------------
local function RenderSidebar(f)
    PoolReset(f.sideRows)
    PoolReset(f.sideHeaders)
    local content = f.sideScroll.content
    local width = SIDEBAR_W - 26
    content:SetWidth(width)
    local y = 0
    local playerKey = ns.GetPlayerKey()

    local function Header(text)
        local h = PoolAcquire(f.sideHeaders)
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", 4, -y - 4)
        h:SetText(text)
        y = y + 18
    end
    local function Row(ownerKey, left, right, r, g, b)
        local row = PoolAcquire(f.sideRows)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -y)
        row:SetWidth(width)
        row.ownerKey = ownerKey
        row.left:SetText(left)
        row.left:SetTextColor(r or 1, g or 1, b or 1)
        row.right:SetText(right or "")
        row.sel:SetShown(state.owner == ownerKey)
        y = y + ROW_H
    end

    local allGold = ns.db.warband.money or 0
    for _, c in pairs(ns.db.chars) do allGold = allGold + (c.money or 0) end
    Row(ALL_OWNER, L["All characters"], W.FormatGold(allGold), 1, 0.82, 0)

    local realmGold = {}
    for _, c in pairs(ns.db.chars) do
        if c.realm then realmGold[c.realm] = (realmGold[c.realm] or 0) + (c.money or 0) end
    end
    local lastRealm
    for _, key in ipairs(ns.GetSortedCharKeys()) do
        local c = ns.db.chars[key]
        local realmLabel = c.realmName or c.realm or "?"
        if realmLabel ~= lastRealm then
            -- realm header doubles as the entry of the realm-wide overview
            if c.realm then
                y = y + 4
                Row(REALM_PREFIX .. c.realm, realmLabel, W.FormatGold(realmGold[c.realm]), 0.6, 0.6, 0.6)
            else
                Header(realmLabel)
            end
            lastRealm = realmLabel
        end
        local r, g, b = W.ClassColor(c.class)
        local name = (c.name or key) .. (key == playerKey and " *" or "")
        Row(key, name .. (c.level and (" |cff888888" .. c.level .. "|r") or ""), W.FormatGold(c.money), r, g, b)
    end

    Header(L["Account"])
    Row(ns.WARBAND_OWNER, L["Warband Bank"], W.FormatGold(ns.db.warband.money), 0.31, 0.76, 0.97)

    local guildKeys = ns.GetSortedGuildKeys()
    if #guildKeys > 0 then
        Header(L["Guild Banks"])
        for _, gk in ipairs(guildKeys) do
            local g = ns.db.guilds[gk]
            Row("@" .. gk, g.name or gk, W.FormatGold(g.money), 0.25, 0.75, 0.25)
        end
    end
    content:SetHeight(math.max(1, y))
end

-- quantities: id -> qty; shared (all-characters view): id -> the single value
-- shown for warband-wide currencies instead of the sum.
local function RenderCurrencies(f, quantities, width, shared)
    local groups = { bound = {}, transferable = {}, warband = {} }
    local total = 0
    for id, qty in pairs(quantities or {}) do
        local info = C_CurrencyInfo.GetCurrencyInfo(id)
        local kind = CurrencyKind(id, info)
        if kind == "warband" and shared and shared[id] then qty = shared[id] end
        local list = groups[kind]
        list[#list + 1] = { id = id, kind = kind, name = (info and info.name) or ("#" .. id),
                            icon = info and info.iconFileID, qty = qty }
        total = total + 1
    end
    local y = 0
    local ar, ag, ab = Ext:GetAccentColor()
    for _, group in ipairs(CURRENCY_GROUPS) do
        local rows = groups[group.key]
        if #rows > 0 then
            table.sort(rows, function(a, b) return a.name < b.name end)
            local h = f.grid:AcquireHeader()
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", f.scroll.content, "TOPLEFT", 2, -y - 2)
            h:SetText(L[group.title])
            h:SetTextColor(ar, ag, ab)
            y = y + 20
            for _, data in ipairs(rows) do
                local r = PoolAcquire(f.currencies)
                r:ClearAllPoints()
                r:SetPoint("TOPLEFT", 0, -y)
                r:SetWidth(width)
                r.currencyID, r.kind = data.id, data.kind
                r.icon:SetTexture(data.icon or 134400)
                r.name:SetText(data.name)
                r.qty:SetText(FormatQty(data.qty))
                y = y + ROW_H
            end
            y = y + 6
        end
    end
    return y, total
end

-- "Alice 5 (Bags 3, Bank 2), Warband 10"
local function DescribeOwners(itemID)
    local byOwner = ns.Index:Get(itemID)
    if not byOwner then return "" end
    local parts = {}
    for owner, byLoc in pairs(byOwner) do
        local n = 0
        for _, v in pairs(byLoc) do n = n + v end
        local label
        if owner == ns.WARBAND_OWNER then
            label = "|cff4fc3f7" .. L["Warband Bank"] .. "|r"
        elseif owner:sub(1, 1) == "@" then
            local g = ns.db.guilds[owner:sub(2)]
            label = "|cff40c040" .. ((g and g.name) or owner:sub(2)) .. "|r"
        else
            label = CharLabel(owner)
        end
        parts[#parts + 1] = { text = label .. " " .. n, n = n }
    end
    table.sort(parts, function(a, b) return a.n > b.n end)
    local out = {}
    for i = 1, #parts do out[i] = parts[i].text end
    return table.concat(out, ", ")
end

local function RenderResults(f, width)
    local results, pending = ns.Search.Run(state.query, 300)
    wipe(pendingSearch)
    for i = 1, math.min(#pending, 200) do
        pendingSearch[pending[i]] = true
        C_Item.RequestLoadItemDataByID(pending[i])
    end
    local y = 0
    for _, res in ipairs(results) do
        local r = PoolAcquire(f.results)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 0, -y)
        r:SetWidth(width)
        r.itemID = res.itemID
        local _, _, _, _, icon = C_Item.GetItemInfoInstant(res.itemID)
        r.icon:SetTexture(icon or 134400)
        local quality = C_Item.GetItemQualityByID(res.itemID)
        local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
        r.name:SetText(res.name)
        if color then r.name:SetTextColor(color.r, color.g, color.b) else r.name:SetTextColor(1, 1, 1) end
        r.total:SetText(tostring(res.total))
        r.detail:SetText(DescribeOwners(res.itemID))
        y = y + RESULT_H
    end
    return y, #results, #pending
end

-- Sold auctions waiting as gold in the mailbox, newest first, as result rows.
local function RenderSold(f, c, width, y)
    local list = {}
    for _, m in ipairs(c.mailSold or {}) do list[#list + 1] = m end
    table.sort(list, function(a, b) return (a.at or 0) > (b.at or 0) end)
    if #list == 0 then return y, 0 end
    local h = f.grid:AcquireHeader()
    h:ClearAllPoints()
    h:SetPoint("TOPLEFT", f.scroll.content, "TOPLEFT", 2, -y - 2)
    h:SetText(L["Sold (gold waiting in the mailbox)"])
    local ar, ag, ab = Ext:GetAccentColor()
    h:SetTextColor(ar, ag, ab)
    y = y + 20
    for _, m in ipairs(list) do
        local id, count, link = ns.DecodeItem(m.e)
        local r = PoolAcquire(f.results)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 0, -y)
        r:SetWidth(width)
        r.itemID = id
        local _, _, _, _, icon = C_Item.GetItemInfoInstant(id)
        r.icon:SetTexture(icon or 134400)
        local name = (link and link:match("|h%[(.-)%]|h")) or C_Item.GetItemInfo(id) or ("item:" .. id)
        r.name:SetText((count and count > 1) and (count .. "x " .. name) or name)
        local quality = C_Item.GetItemQualityByID(link or id)
        local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
        if color then r.name:SetTextColor(color.r, color.g, color.b) else r.name:SetTextColor(1, 1, 1) end
        r.total:SetText(W.FormatMoney(m.money))
        r.detail:SetText(W.FormatAgo(m.at))
        y = y + RESULT_H
    end
    return y, #list
end

local function SoldTotal(c)
    local total = 0
    for _, m in ipairs(c.mailSold or {}) do total = total + (m.money or 0) end
    return total
end

local function FooterForScope(scope)
    local gold = scope.realm and 0 or (ns.db.warband.money or 0)
    local chars, value, auctions, mailGold = 0, 0, 0, 0
    for _, c in pairs(ns.db.chars) do
        if InScope(scope, c.realm) then
            chars = chars + 1
            gold = gold + (c.money or 0)
            if state.tab == "auctions" then
                local v, n = ns.AuctionValue(c)
                value, auctions = value + v, auctions + n
            elseif state.tab == "mail" then
                mailGold = mailGold + SoldTotal(c)
            end
        end
    end
    local text = string.format("%s: %s   %s", L["Gold"], W.FormatGold(gold), string.format(L["%d characters"], chars))
    if state.tab == "auctions" then
        text = text .. string.format("   %s: %s (%d)", L["On the auction house"], W.FormatMoney(value), auctions)
    elseif state.tab == "mail" then
        text = text .. string.format("   %s: %s", L["Gold in mail"], W.FormatMoney(mailGold))
    end
    return text
end

local function FooterFor(owner)
    local scope = AggregateScope(owner)
    if scope then return FooterForScope(scope) end
    if owner == ns.WARBAND_OWNER then
        local wb = ns.db.warband
        return string.format("%s: %s   %s: %s", L["Gold"], W.FormatGold(wb.money), L["Bank scanned"], W.FormatAgo(wb.bankAt))
    elseif owner:sub(1, 1) == "@" then
        local g = ns.db.guilds[owner:sub(2)]
        if not g then return "" end
        return string.format("%s: %s   %s: %s", L["Gold"], W.FormatGold(g.money), L["Scanned"], W.FormatAgo(g.scannedAt))
    end
    local c = ns.db.chars[owner]
    if not c then return "" end
    if state.tab == "auctions" then
        local value, count = ns.AuctionValue(c)
        return string.format("%s: %s   %s: %s (%d)   %s: %s", L["Gold"], W.FormatGold(c.money),
            L["On the auction house"], W.FormatMoney(value), count,
            L["Auctions scanned"], W.FormatAgo(c.auctions and c.auctions.scannedAt))
    elseif state.tab == "mail" then
        return string.format("%s: %s   %s: %s   %s: %s", L["Gold"], W.FormatGold(c.money),
            L["Gold in mail"], W.FormatMoney(SoldTotal(c)),
            L["Mail scanned"], W.FormatAgo(c.mail and c.mail.scannedAt))
    end
    return string.format("%s: %s   %s: %s   %s: %s   %s: %s",
        L["Gold"], W.FormatGold(c.money),
        L["Last seen"], W.FormatAgo(c.lastSeen),
        L["Bank scanned"], W.FormatAgo(c.bankAt),
        L["Mail scanned"], W.FormatAgo(c.mail and c.mail.scannedAt))
end

function Browser:Refresh()
    if not frame then return end
    self.stale = false
    local f = frame
    if not state.owner or not self:OwnerExists(state.owner) then
        state.owner = ns.GetPlayerKey()
        if not state.owner or not ns.db.chars[state.owner] then
            state.owner = ns.GetSortedCharKeys()[1] or ns.WARBAND_OWNER
        end
    end
    RenderSidebar(f)

    f.grid:Reset()
    PoolReset(f.results)
    PoolReset(f.currencies)
    f.empty:SetText("")

    local width = f.scroll:GetWidth()
    if not width or width < 100 then width = WIDTH - SIDEBAR_W - 3 * PAD - 30 end
    f.scroll.content:SetWidth(width)

    local owner = state.owner
    local scope = AggregateScope(owner)
    local isAll = scope ~= nil
    local isChar = not isAll and owner ~= ns.WARBAND_OWNER and owner:sub(1, 1) ~= "@"
    local searching = state.query ~= nil
    if state.tab == "all" and not isAll then state.tab = "bags" end
    local prev
    for _, tab in ipairs(f.tabs) do
        local shown = (isChar or isAll) and not searching and (isAll or not tab.allOnly)
        tab:SetShown(shown)
        tab:SetSelected(tab.key == state.tab)
        if shown then
            tab:ClearAllPoints()
            if prev then tab:SetPoint("LEFT", prev, "RIGHT", 2, 0)
            else tab:SetPoint("TOPLEFT", f.sidebar, "TOPRIGHT", PAD, 0) end
            prev = tab
        end
    end

    local height, count = 0, 0
    if searching then
        local n, pend
        height, n, pend = RenderResults(f, width)
        if n == 0 then
            f.empty:SetText(pend > 0 and L["Searching... (loading item data)"] or L["No items found."])
        end
        f.footer:SetText(string.format(L["%d results"], n))
    else
        local sections
        if isAll then
            if state.tab == "currency" then
                local totals, shared = AllCurrencyTotals(scope)
                height, count = RenderCurrencies(f, totals, width, shared)
            else
                sections = AllSections(scope, state.tab)
            end
        elseif isChar then
            local c = ns.db.chars[owner]
            if state.tab == "currency" then
                height, count = RenderCurrencies(f, c.currency, width)
            else
                sections = CharSections(c, state.tab)
            end
        elseif owner == ns.WARBAND_OWNER then
            sections = TabSections(ns.db.warband.bank)
        else
            local g = ns.db.guilds[owner:sub(2)]
            sections = g and TabSections(g.tabs) or {}
        end
        if sections then
            height = f.grid:Layout(sections, width, isAll)
            count = f.grid.used
        end
        if isChar and state.tab == "mail" then
            local sold
            height, sold = RenderSold(f, ns.db.chars[owner], width, height)
            count = count + sold
        end
        if count == 0 then
            local hint = L["Nothing stored here yet."]
            if isChar and state.tab == "bank" then
                hint = L["No bank data yet. Visit a banker with this character."]
            elseif isChar and state.tab == "auctions" then
                hint = L["No auctions stored. Open the Auctions tab of the auction house with this character."]
            end
            f.empty:SetText(hint)
        end
        f.footer:SetText(FooterFor(owner))
    end
    f.scroll.content:SetHeight(math.max(1, height))
    f.delete:SetShown(not searching and not isAll and owner ~= ns.WARBAND_OWNER and owner ~= ns.GetPlayerKey())
end

-------------------------------------------------------------------------------
--  Actions
-------------------------------------------------------------------------------
function Browser:ConfirmDelete()
    local owner = state.owner
    if not owner or owner == ns.GetPlayerKey() or owner == ns.WARBAND_OWNER or AggregateScope(owner) then return end
    local isGuild = owner:sub(1, 1) == "@"
    local label = isGuild and ((ns.db.guilds[owner:sub(2)] or {}).name or owner:sub(2)) or owner
    Ext:Confirm({
        title = L["Delete data"],
        message = string.format(L["Delete all stored data of %s?"], label),
        confirmText = L["Delete"],
        cancelText = CANCEL or "Cancel",
        onConfirm = function()
            if isGuild then ns.DeleteGuild(owner:sub(2)) else ns.DeleteChar(owner) end
            state.owner = nil
            Browser:Refresh()
        end,
    })
end

function Browser:Open(owner)
    self:Build()
    if owner then state.owner = owner end
    if frame:IsShown() then
        self:Refresh()
    else
        self.stale = true
        frame:Show()   -- OnShow renders because the view is stale
    end
end

function Browser:Close()
    if frame then frame:Hide() end
end

function Browser:Toggle()
    if frame and frame:IsShown() then self:Close() else self:Open() end
end

function Browser:IsShown()
    return frame ~= nil and frame:IsShown()
end

function Browser:OpenSearch(text)
    self:Open()
    frame.search:SetText(text or "")
    self:SetQuery(text or "")
end

function Browser:GetFrame() return frame end

-- Opened from the Settings panel: show above it until the next close.
function Browser:RaiseAboveSettings()
    if frame then frame:SetFrameStrata("DIALOG") end
end
