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

local pairs, ipairs, sort, format, wipe = pairs, ipairs, table.sort, string.format, wipe

local hooked = false
local active = false
local lineCache = {}              -- itemID -> { left1, right1, left2, right2, ... } | false
-- tooltip -> processingInfo our lines were added for. Blizzard's ProcessInfo
-- creates a new info table for every (re)build, so this blocks a second post-call
-- within one build (embedded item tooltips) without hooking OnTooltipCleared.
local lastAdded = setmetatable({}, { __mode = "k" })

local LOCATION_ORDER = { "bags", "bank", "equipped", "mail", "auctions", "warband", "guild" }
local LOCATION_LABEL = {
    bags = "Bags", bank = "Bank", equipped = "Equipped", mail = "Mail", auctions = "Auctions",
    warband = "Warband Bank", guild = "Guild Bank",
}

local ALLOWED_TOOLTIPS

local function Settings() return ns.db.settings.tooltip end

local function ClassColorHex(class)
    local color = class and C_ClassColor.GetClassColor(class)
    if color and color.GenerateHexColor then return color:GenerateHexColor() end
    return "ffffffff"
end

local function DescribeLocations(byLoc)
    local parts = {}
    for _, loc in ipairs(LOCATION_ORDER) do
        local n = byLoc[loc]
        if n then parts[#parts + 1] = format("%s: %d", L[LOCATION_LABEL[loc]], n) end
    end
    return table.concat(parts, ", ")
end

local function SumLocations(byLoc)
    local total = 0
    for _, n in pairs(byLoc) do total = total + n end
    return total
end

-- Builds the flat left/right line list for one item. opts: settings-shaped
-- table overriding the tooltip settings (the browser's all-characters view).
local function BuildLines(itemID, opts)
    local byOwner = ns.Index:Get(itemID)
    if not byOwner then return false end
    local s = opts or Settings()
    local db = ns.db
    local playerKey = ns.GetPlayerKey()
    local ownRealm = ns.GetPlayerRealm()

    local charRows = {}
    local total = 0
    local warbandCount, guildRows = nil, {}

    for owner, byLoc in pairs(byOwner) do
        local count = SumLocations(byLoc)
        if owner == ns.WARBAND_OWNER then
            if s.showWarband then
                warbandCount = count
                total = total + count
            end
        elseif owner:sub(1, 1) == "@" then
            local guildKey = owner:sub(2)
            local g = db.guilds[guildKey]
            local _, realm = ns.SplitKey(guildKey)
            if s.showGuild and g and ns.IsRealmInScope(realm, s.realmScope) then
                guildRows[#guildRows + 1] = { name = g.name or guildKey, count = count }
                total = total + count
            end
        else
            local c = db.chars[owner]
            if c and ns.IsRealmInScope(c.realm, s.realmScope) and not (s.hideCurrent and owner == playerKey) then
                local label = c.name or owner
                if c.realm and c.realm ~= ownRealm then label = label .. "-" .. c.realm end
                charRows[#charRows + 1] = {
                    label = format("|c%s%s|r", ClassColorHex(c.class), label),
                    detail = DescribeLocations(byLoc),
                    count = count,
                    sortKey = (owner == playerKey and "0" or "1") .. owner,
                }
                total = total + count
            end
        end
    end

    if #charRows == 0 and not warbandCount and #guildRows == 0 then return false end
    sort(charRows, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.sortKey < b.sortKey
    end)
    sort(guildRows, function(a, b) return a.name < b.name end)

    local lines = {}
    local function add(left, right)
        lines[#lines + 1] = left
        lines[#lines + 1] = right
    end
    local maxChars = s.maxChars or 10
    for i, row in ipairs(charRows) do
        if i > maxChars then
            add(format("|cff999999" .. L["...and %d more"] .. "|r", #charRows - maxChars), "")
            break
        end
        add(row.label, row.detail)
    end
    if warbandCount then
        add("|cff4fc3f7" .. L["Warband Bank"] .. "|r", format("%d", warbandCount))
    end
    for _, row in ipairs(guildRows) do
        add("|cff40c040" .. row.name .. "|r", format("%s: %d", L["Guild Bank"], row.count))
    end
    if s.showTotal and (#charRows + #guildRows + (warbandCount and 1 or 0)) > 1 then
        add(L["Total"], format("%d", total))
    end
    return lines
end
ns.BuildTooltipLines = BuildLines   -- exposed for tests and the self-test

-- Every owner, every realm: the browser's all-characters view (own UI, so it
-- does not depend on the opt-in tooltip setting).
local ALL_OWNERS = { realmScope = "all", showWarband = true, showGuild = true, showTotal = true,
                     hideCurrent = false, maxChars = 40 }
function ns.BuildAllOwnerLines(itemID) return BuildLines(itemID, ALL_OWNERS) end

local function GetLines(itemID)
    local lines = lineCache[itemID]
    if lines == nil then
        lines = BuildLines(itemID)
        lineCache[itemID] = lines
    end
    return lines
end

local MODIFIER_TEST = {
    shift = function() return IsShiftKeyDown() end,
    ctrl  = function() return IsControlKeyDown() end,
    alt   = function() return IsAltKeyDown() end,
}

-- Item ID of the tooltip data, resolved like Blizzard's TooltipUtil.GetDisplayedItem:
-- data.id, else the hyperlink, else the item GUID.
local function ItemIDFromData(data)
    if not data then return nil end
    local id = data.id
    if id ~= nil then return id end
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
    local modTest = MODIFIER_TEST[Settings().modifier]
    if modTest and not modTest() then return end

    if not ns.activated then ns.Activate("tooltip") end   -- once: current character's data first
    local lines = GetLines(itemID)
    if not lines then return end
    lastAdded[tooltip] = info
    tooltip:AddLine(" ")
    for i = 1, #lines, 2 do
        tooltip:AddDoubleLine(lines[i], lines[i + 1], 1, 0.82, 0, 1, 1, 1)
    end
end
ns.OnTooltipItem = OnTooltipItem   -- exposed for tests

local function InvalidateAll() wipe(lineCache) end

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
            for id in pairs(touched) do lineCache[id] = nil end
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
