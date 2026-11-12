-------------------------------------------------------------------------------
--  Tooltip/Tooltip.lua   (opt-in, default OFF)
--  Adds "who has this item" lines to item tooltips.
--
--  TooltipDataProcessor post-calls cannot be removed, so the hook is installed
--  on the first enable only and starts with a single boolean test. It is
--  registered for Enum.TooltipDataType.Item only: unit, spell and world-object
--  tooltips never reach this file (no OnTooltipCleared hook either -- Blizzard
--  refreshes every visible tooltip each TOOLTIP_UPDATE_TIME, so a clear hook
--  would run constantly while you merely look at the world).
--
--  Counting is cached twice: the item index (itemID -> owner -> location) is
--  built once and then only updated for items that changed, and the finished
--  tooltip lines are cached per itemID until the index reports a change for
--  that item. A tooltip refresh therefore costs a few table lookups and
--  allocates nothing. Item tooltips of world loot objects are skipped.
-------------------------------------------------------------------------------
local _, ns = ...
local L = ns.L

local pairs, ipairs, type, sort, format, wipe = pairs, ipairs, type, table.sort, string.format, wipe
local DecodeItemIDCount = ns.DecodeItemIDCount
local issecretvalue = issecretvalue   -- direct: the refresh path stays within its call budget

local hooked = false
local active = false
-- tooltip -> processingInfo our lines were added for. Blizzard's ProcessInfo
-- creates a new info table for every (re)build, so this blocks a second post-call
-- within one build (embedded item tooltips) without hooking OnTooltipCleared.
local lastAdded = setmetatable({}, { __mode = "k" })

local LOCATION_ORDER = { "bags", "bank", "equipped", "mail", "auctions", "warband", "guild" }
local LOCATION_LABEL = {
    bags = "Bags", bank = "Bank", equipped = "Equipped", mail = "Mail", auctions = "Auctions",
    warband = "Warband Bank", guild = "Guild Bank",
}
-- Atlases both clients ship (retail and Forever atlas tables).
local LOCATION_ATLAS = {
    bags = "hud-backpack", bank = "banker", equipped = "bags-icon-equipment", mail = "mailbox",
    auctions = "auctioneer", warband = "warbands-icon", guild = "ui-hud-micromenu-guildcommunities-up",
}
local ICON_SIZE = 14
-- Thin rule below the current character: a stretched 8x8 white texture, tinted grey.
local SEPARATOR = "|TInterface\\Buttons\\WHITE8X8:1:110:0:0:8:8:0:8:0:8:110:110:110|t"

local ALLOWED_TOOLTIPS

local function Settings() return ns.db.settings.tooltip end

local MODIFIER_TEST = {
    shift = function() return IsShiftKeyDown() end,
    ctrl  = function() return IsControlKeyDown() end,
    alt   = function() return IsAltKeyDown() end,
}

-- Whether characters and guilds outside the realm scope are listed right now.
local function OtherRealmsShown(s)
    local mode = s.otherRealms
    if mode == "always" then return true end
    local test = MODIFIER_TEST[mode]
    return test ~= nil and test()
end

local function ClassColorHex(class)
    local color = class and C_ClassColor.GetClassColor(class)
    if color and color.GenerateHexColor then return color:GenerateHexColor() end
    return "ffffffff"
end

function ns.LocationIcon(loc, size)
    size = size or ICON_SIZE
    return format("|A:%s:%d:%d|a", LOCATION_ATLAS[loc], size, size)
end

-- Tab icons are item-style icons: the crop drops their baked-in border.
local function TabIcon(icon)
    return format("|T%s:%d:%d:0:0:64:64:5:59:5:59|t", tostring(icon), ICON_SIZE, ICON_SIZE)
end

-- The container map with tabs behind one owner's location, if it has tabs.
local function TabMap(owner, loc)
    local db = ns.db
    if loc == "bank" then
        local c = db.chars[owner]
        return c and c.bank
    elseif loc == "warband" then
        return db.warband and db.warband.bank
    elseif loc == "guild" then
        local g = db.guilds[owner:sub(2)]
        return g and g.tabs
    end
    return nil
end

local function CountIn(items, itemID)
    local n = 0
    if not items then return n end
    for enc in ns.Stacks(items) do
        if type(enc) == "string" then
            local id, count = DecodeItemIDCount(enc)
            if id == itemID then n = n + count end
        end
    end
    return n
end

-- The named tabs of a location that hold the item, in tab order; nil when
-- none (the index counts per location only, so this reads the containers).
-- Containers without name and icon (Forever's bank bags) are no tabs.
local function TabsHolding(owner, loc, itemID)
    local map = TabMap(owner, loc)
    if type(map) ~= "table" then return nil end
    local tabs
    for id, cont in pairs(map) do
        if type(cont) == "table" and (cont.name or cont.icon) then
            local n = CountIn(cont.items, itemID)
            if n > 0 then
                tabs = tabs or {}
                tabs[#tabs + 1] = { id = id, name = cont.name, icon = cont.icon, count = n }
            end
        end
    end
    if tabs then sort(tabs, function(a, b) return a.id < b.id end) end
    return tabs
end

-- " (Mats 30, Herbs 10)" or with icons " ([icon] 30 [icon] 10)"; a single
-- tab needs no count: " (Mats)".
local function TabsSuffix(tabs, icons)
    local parts = {}
    for i, tab in ipairs(tabs) do
        local label
        if icons and tab.icon then
            label = TabIcon(tab.icon)
        else
            label = tab.name or format("#%d", i)
        end
        parts[i] = #tabs > 1 and (label .. " " .. tab.count) or label
    end
    return " (" .. table.concat(parts, icons and " " or ", ") .. ")"
end

-- One location of one owner: "Bank: 40 (Mats)" or "[icon] 40 ([tab])".
local function DescribeLocation(owner, loc, n, itemID, s, icons)
    local text = icons and (ns.LocationIcon(loc) .. " " .. n) or format("%s: %d", L[LOCATION_LABEL[loc]], n)
    if s.showTabs then
        local tabs = TabsHolding(owner, loc, itemID)
        if tabs then text = text .. TabsSuffix(tabs, icons) end
    end
    return text
end

local function DescribeLocations(owner, byLoc, itemID, s, icons)
    local parts = {}
    for _, loc in ipairs(LOCATION_ORDER) do
        local n = byLoc[loc]
        if n then parts[#parts + 1] = DescribeLocation(owner, loc, n, itemID, s, icons) end
    end
    return table.concat(parts, icons and "  " or ", ")
end

local function SumLocations(byLoc)
    local total = 0
    for _, n in pairs(byLoc) do total = total + n end
    return total
end

local SORTERS = {
    count  = function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.sortName < b.sortName
    end,
    recent = function(a, b)
        if a.lastSeen ~= b.lastSeen then return a.lastSeen > b.lastSeen end
        return a.sortName < b.sortName
    end,
    name   = function(a, b) return a.sortName < b.sortName end,
}

-- Builds the flat left/right line list for one item. s: the tooltip settings
-- (or a table shaped like them); includeOther: list owners outside the realm
-- scope too (the "other realms" setting, resolved by the caller).
local function BuildLines(itemID, s, includeOther)
    local byOwner = ns.Index:Get(itemID)
    if not byOwner then return false end
    local db = ns.db
    local playerKey = ns.GetPlayerKey()
    local ownRealm = ns.GetPlayerRealm()
    local detail = s.detail
    local icons = detail == "icons" or detail == "compact"

    local current, charRows = nil, {}
    local total = 0
    local warband, guildRows = nil, {}

    for owner, byLoc in pairs(byOwner) do
        local count = SumLocations(byLoc)
        if owner == ns.WARBAND_OWNER then
            if s.showWarband then
                warband = { owner = owner, byLoc = byLoc, count = count }
                total = total + count
            end
        elseif owner:sub(1, 1) == "@" then
            local guildKey = owner:sub(2)
            local g = db.guilds[guildKey]
            local _, realm = ns.SplitKey(guildKey)
            if s.showGuild and g and (includeOther or ns.IsRealmInScope(realm, s.realmScope)) then
                guildRows[#guildRows + 1] = { owner = owner, byLoc = byLoc, name = g.name or guildKey, count = count }
                total = total + count
            end
        else
            local c = db.chars[owner]
            local isCurrent = owner == playerKey
            if c and (includeOther or ns.IsRealmInScope(c.realm, s.realmScope)) and not (s.hideCurrent and isCurrent) then
                local label = c.name or owner
                if c.realm and c.realm ~= ownRealm then label = label .. "-" .. c.realm end
                local row = {
                    owner = owner, byLoc = byLoc, count = count,
                    label = format("|c%s%s|r", ClassColorHex(c.class), label),
                    sortName = (c.name or ""):lower() .. "-" .. owner,
                    lastSeen = c.lastSeen or 0,
                }
                if isCurrent then current = row else charRows[#charRows + 1] = row end
                total = total + count
            end
        end
    end

    local others = #charRows + #guildRows + (warband and 1 or 0)
    if not current and others == 0 then return false end
    sort(charRows, SORTERS[s.sort] or SORTERS.count)
    sort(guildRows, function(a, b) return a.name < b.name end)

    local lines = {}
    local function add(left, right)
        lines[#lines + 1] = left
        lines[#lines + 1] = right
    end
    local function addChar(row)
        if detail == "total" then
            add(row.label, format("%d", row.count))
        elseif detail == "icons" then
            add(row.label, format("%d", row.count))
            add(" ", DescribeLocations(row.owner, row.byLoc, itemID, s, true))
        else
            add(row.label, DescribeLocations(row.owner, row.byLoc, itemID, s, icons))
        end
    end

    -- The current character leads whatever the sort; the rule sets it apart.
    local maxChars = s.maxChars or 10
    local listed = 0
    if current then
        addChar(current)
        listed = 1
        if others > 0 then add(SEPARATOR, "") end
    end
    for i, row in ipairs(charRows) do
        if listed >= maxChars then
            add(format("|cff999999" .. L["...and %d more"] .. "|r", #charRows - i + 1), "")
            break
        end
        addChar(row)
        listed = listed + 1
    end
    if warband then
        local right
        if detail == "total" then
            right = format("%d", warband.count)
        elseif icons then
            right = DescribeLocation(warband.owner, "warband", warband.count, itemID, s, true)
        else
            -- the left side already says "Warband Bank"
            local tabs = s.showTabs and TabsHolding(warband.owner, "warband", itemID)
            right = format("%d", warband.count) .. (tabs and TabsSuffix(tabs, false) or "")
        end
        add("|cff4fc3f7" .. L["Warband Bank"] .. "|r", right)
    end
    for _, row in ipairs(guildRows) do
        local right = detail == "total" and format("%d", row.count)
            or DescribeLocation(row.owner, "guild", row.count, itemID, s, icons)
        add("|cff40c040" .. row.name .. "|r", right)
    end
    if s.showTotal and (others + (current and 1 or 0)) > 1 then
        add(L["Total"], format("%d", total))
    end
    return lines
end
ns.BuildTooltipLines = BuildLines   -- exposed for tests and the self-test

-- Cached lines per itemID, one cache per "other realms listed" state.
local lineCache, lineCacheOther = {}, {}   -- itemID -> { left1, right1, ... } | false

local function GetLines(itemID, includeOther)
    local cache = includeOther and lineCacheOther or lineCache
    local lines = cache[itemID]
    if lines == nil then
        lines = BuildLines(itemID, Settings(), includeOther)
        cache[itemID] = lines
    end
    return lines
end

local function AddLines(tooltip, lines)
    tooltip:AddLine(" ")
    for i = 1, #lines, 2 do
        tooltip:AddDoubleLine(lines[i], lines[i + 1], 1, 0.82, 0, 1, 1, 1)
    end
end

-- The browser's item tooltips (tooltipPostCall of its ProcessInfo builds):
-- processingInfo.euiAltsOwners is the itemID. They follow the tooltip
-- settings except "Show counts" (enabled, modifier): the browser is opened to
-- see the counts. processingInfo.euiAltsDetail overrides the detail setting
-- (the options' preview). Built uncached: the line cache only follows count
-- changes while the tooltip feature is on.
function ns.AddOwnerLines(tooltip)
    local info = tooltip.processingInfo
    local itemID = info and info.euiAltsOwners
    if not itemID then return end
    local s = Settings()
    if info.euiAltsDetail then
        s = setmetatable({ detail = info.euiAltsDetail }, { __index = s })
    end
    local lines = BuildLines(itemID, s, OtherRealmsShown(s))
    if lines then AddLines(tooltip, lines) end
end

-- Item ID of the tooltip data, resolved like Blizzard's TooltipUtil.GetDisplayedItem:
-- data.id, else the hyperlink, else the item GUID.
local function ItemIDFromData(data)
    if not data then return nil end
    local id = data.id
    if issecretvalue(id) then return nil end
    if id then return id end
    local link = data.hyperlink
    if link and not ns.IsSecret(link) then
        id = C_Item.GetItemInfoInstant(link)
        if id then return id end
    end
    local guid = data.guid
    if guid and not ns.IsSecret(guid) then return C_Item.GetItemIDByGUID(guid) end
    return nil
end

-- World objects (loot lying in the world, game objects) are not inventory.
local function IsWorldObject(data)
    if data.worldLootObjectGUID ~= nil or data.worldLootObjectInventoryType ~= nil then return true end
    local guid = data.guid
    if guid == nil or ns.IsSecret(guid) then return false end
    return type(guid) == "string" and guid:sub(1, 5) ~= "Item-"
end

local function OnTooltipItem(tooltip, data)
    if not active or not data then return end
    if not ALLOWED_TOOLTIPS[tooltip] then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    local info = tooltip.processingInfo
    -- euiAltsOwners: the browser adds its own all-owner lines to this build
    if info ~= nil and (lastAdded[tooltip] == info or info.euiAltsOwners) then return end
    if IsWorldObject(data) then return end
    local itemID = ItemIDFromData(data)
    if not itemID or ns.IsSecret(itemID) then return end
    local s = Settings()
    local modTest = MODIFIER_TEST[s.modifier]
    if modTest and not modTest() then return end

    if not ns.activated then ns.Activate("tooltip") end   -- once: current character's data first
    -- OtherRealmsShown and AddLines inlined: a refresh stays within its call budget
    local other = s.otherRealms
    local includeOther = other == "always" or (other ~= "never" and MODIFIER_TEST[other]())
    local cache = includeOther and lineCacheOther or lineCache
    local lines = cache[itemID]
    if lines == nil then lines = GetLines(itemID, includeOther) end
    if not lines then return end
    lastAdded[tooltip] = info
    tooltip:AddLine(" ")
    for i = 1, #lines, 2 do
        tooltip:AddDoubleLine(lines[i], lines[i + 1], 1, 0.82, 0, 1, 1, 1)
    end
end
ns.OnTooltipItem = OnTooltipItem   -- exposed for tests

local function InvalidateAll()
    wipe(lineCache)
    wipe(lineCacheOther)
end

ns.RegisterFeature({
    key = "tooltip",
    eager = true,     -- hovering an item is using the addon: it activates it
    IsEnabled = function(s) return s.tooltip.enabled end,
    OnEnable = function()
        if not hooked then
            hooked = true
            ALLOWED_TOOLTIPS = {}
            -- Not the comparison (shopping) tooltips: counts there are noise.
            for _, name in ipairs({ "GameTooltip", "ItemRefTooltip", "EllesmereUIBagsAltsTooltip" }) do
                local tt = _G[name]
                if tt then ALLOWED_TOOLTIPS[tt] = true end
            end
            -- The browser's own tooltip may be created later.
            ns.On("BROWSER_TOOLTIP_CREATED", ALLOWED_TOOLTIPS, function(_, tt) ALLOWED_TOOLTIPS[tt] = true end)
            TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnTooltipItem)
        end
        InvalidateAll()
        active = true
        ns.On("ITEM_COUNTS_CHANGED", lineCache, function(_, touched)
            for id in pairs(touched) do
                lineCache[id] = nil
                lineCacheOther[id] = nil
            end
        end)
        ns.On("INDEX_REBUILT", lineCache, InvalidateAll)
        ns.On("SETTINGS_CHANGED", lineCache, InvalidateAll)
        ns.On("CHAR_UPDATED", lineCache, function(_, _, what)
            if what == nil then InvalidateAll() end   -- meta (class/name) only
        end)
    end,
    OnDisable = function()
        active = false
        InvalidateAll()
        ns.Off("ITEM_COUNTS_CHANGED", lineCache)
        ns.Off("INDEX_REBUILT", lineCache)
        ns.Off("SETTINGS_CHANGED", lineCache)
        ns.Off("CHAR_UPDATED", lineCache)
    end,
})
