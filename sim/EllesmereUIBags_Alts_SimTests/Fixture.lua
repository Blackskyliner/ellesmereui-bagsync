-- Deterministic multi-character data for layout tests and screenshots.
-- EUIAltsSimFixture.Install() adds three characters on two realms and a guild
-- bank next to whatever the simulator's own character holds, on retail also a
-- warband bank and currencies; Uninstall() restores the previous data.
-- Timestamps are relative to time() and sit mid-bucket (e.g. 2.5 h), so
-- "x h ago" texts render the same in every run, however long the simulator
-- takes to start.
-- On WoW Forever the data has that client's shape: characters keyed by GUID
-- under a realm group (Normal, PvP), full names with surnames (two share a
-- first name), balances below one gold, a keyring and an ammo stack, Classic
-- items. EUIAltsSimFixture.MAIN, SECOND, REALM and GUILD name the owners
-- tests and scenarios open, on either client.
EUIAltsSimFixture = {}

local ns = EllesmereUIBagsAlts._ns
local saved
local FOREVER = ns.Compat.IS_FOREVER

local LINEN, WOOL, HEARTH, THUNDERFURY = 2589, 2592, 6948, 19019
-- Retail: Draconium Ore, a Dragonflight potion. Forever: Copper Ore, Minor
-- Healing Potion, plus The Scarlet Key and Rough Arrow.
local ORE, POTION = 190396, 212345
local KEY, ARROW = 7146, 2512
if FOREVER then ORE, POTION = 2770, 118 end

-- The simulator's item table lacks most of these items: it answers with the
-- question-mark icon, and on Forever without a name. Their own icons (file
-- data IDs), names and qualities let screenshots show them the way the
-- client does; items the simulator knows keep its answer.
local ITEMS = FOREVER and {
    [LINEN] = { 132889, "Linen Cloth", 1 },
    [WOOL] = { 132911, "Wool Cloth", 1 },
    [THUNDERFURY] = { 135349, "Thunderfury, Blessed Blade of the Windseeker", 5 },
    [ORE] = { 134566, "Copper Ore", 1 },             -- inv_ore_copper_01
    [POTION] = { 134829, "Minor Healing Potion", 1 }, -- inv_potion_49
    [KEY] = { 134235, "The Scarlet Key", 1 },         -- inv_misc_key_01
    [ARROW] = { 132381, "Rough Arrow", 1 },           -- inv_ammo_arrow_01
} or {
    [LINEN] = { 132889 },       -- inv_fabric_linen_01
    [WOOL] = { 132911 },        -- inv_fabric_wool_01
    [THUNDERFURY] = { 135349 }, -- inv_sword_39
    [ORE] = { 4581144 },        -- inv_ore_draconium
    [POTION] = { 1385333 },     -- inv_alchemy_70_red
}
local QUESTION_MARK = 134400

local function ItemOf(item)
    return ITEMS[tonumber(item) or tonumber(type(item) == "string" and item:match("item:(%d+)") or nil)]
end

local function WithFixtureIcon(id, ...)
    local itemID, itemType, itemSubType, equipLoc, icon = ...
    local own = ItemOf(itemID or id)
    if own and icon == QUESTION_MARK then
        return itemID, itemType, itemSubType, equipLoc, own[1], select(6, ...)
    end
    return ...
end

local function UnknownName(name) return name == nil or name == "" or name == UNKNOWN or name == "Unknown" end

-- GetItemInfo's name, link, quality and icon (returns 1, 2, 3 and 10) for a
-- fixture item the simulator has no name for.
local function WithFixtureInfo(item, ...)
    local own = ItemOf(item)
    if not own or not own[2] or not UnknownName((...)) then return ... end
    local r, n = { ... }, math.max(select("#", ...), 10)
    local id = tonumber(item) or tonumber(item:match("item:(%d+)"))
    local color = ITEM_QUALITY_COLORS[own[3]]
    r[1] = own[2]
    r[2] = ("%s|Hitem:%d::::::::::::|h[%s]|h|r"):format(color and color.hex or "|cffffffff", id, own[2])
    r[3] = own[3]
    r[10] = own[1]
    return unpack(r, 1, n)
end

-- The simulator's currency tooltip data has no lines, so Blizzard's
-- SetCurrencyByID shows an empty tooltip, which hides itself and drops its
-- owner, and the lines added after it are lost. The client's tooltip starts
-- with the currency's name in its quality colour; while the fixture is
-- installed that line stands in when the simulator gives none (a post call
-- runs before Blizzard shows the tooltip and cannot be removed again). The
-- simulator's data carries no id either; the getter's argument names it.
local currencyNameHooked
local function HookCurrencyName()
    if currencyNameHooked then return end
    currencyNameHooked = true
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Currency, function(tooltip, data)
        if not saved or tooltip:NumLines() > 0 then return end
        local args = tooltip.processingInfo and tooltip.processingInfo.getterArgs
        local info = C_CurrencyInfo.GetCurrencyInfo(data and data.id or args and args[1])
        if not info then return end
        local quality = ITEM_QUALITY_COLORS[info.quality or 1]
        GameTooltip_AddColoredLine(tooltip, info.name, quality and quality.color or HIGHLIGHT_FONT_COLOR)
    end)
end

-- The simulator's item tooltip data has no lines for items it does not know,
-- which empties the tooltip the same way; the item's name stands in.
local itemNameHooked
local function HookItemName()
    if itemNameHooked then return end
    itemNameHooked = true
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
        if not saved or tooltip:NumLines() > 0 then return end
        local args = tooltip.processingInfo and tooltip.processingInfo.getterArgs
        local own = ItemOf(data and data.id or args and args[1])
        if not own or not own[2] then return end
        local quality = ITEM_QUALITY_COLORS[own[3]]
        GameTooltip_AddColoredLine(tooltip, own[2], quality and quality.color or HIGHLIGHT_FONT_COLOR)
    end)
end

local function enc(id, count) return id .. "," .. (count or 1) end

local function container(size, items, name)
    return { size = size, items = ns.PackItems(items), name = name }
end

local function chars(now)
    return {
        ["Aldrianna-Blackhand"] = {
            name = "Aldrianna", realm = "Blackhand", realmName = "Blackhand", class = "PALADIN", level = 90,
            money = 123456789, lastSeen = now - 5400, bankAt = now - 9000,
            bags = {
                [0] = container(20, { [1] = enc(HEARTH), [2] = enc(LINEN, 200), [3] = enc(POTION, 20),
                                      [4] = enc(THUNDERFURY), [5] = enc(WOOL, 57) }),
                [1] = container(36, { [1] = enc(ORE, 1000), [2] = enc(LINEN, 55) }),
            },
            bank = { [6] = container(98, { [1] = enc(WOOL, 400), [2] = enc(POTION, 60) }, "Consumables") },
            equipped = container(19, { [16] = enc(THUNDERFURY) }),
            mail = { items = { { e = enc(LINEN, 20), x = now + 86400 * 20 } }, scannedAt = now - 1830 },
            mailSold = { { e = enc(ORE, 200), money = 4500000, at = now - 930, x = now + 86400 * 30 } },
            auctions = { scannedAt = now - 630, items = {
                { e = enc(POTION, 40), x = now + 86400, id = 11, u = 125000 },
                { e = enc(THUNDERFURY), x = now + 86400 * 2, id = 12, u = 99990000 },
            } },
            currency = { [3008] = 2450, [2815] = 12000, [3028] = 3, [2032] = 750 },
        },
        ["Bob-Blackhand"] = {
            name = "Bob", realm = "Blackhand", realmName = "Blackhand", class = "WARRIOR", level = 80,
            money = 5000000, lastSeen = now - 86400 * 3 - 43200,
            bags = { [0] = container(20, { [1] = enc(HEARTH), [2] = enc(LINEN, 3), [3] = enc(ORE, 12) }) },
            currency = { [3008] = 200, [2032] = 750 },
        },
        ["Carol-Proudmoore"] = {
            name = "Carol", realm = "Proudmoore", realmName = "Proudmoore", class = "PRIEST", level = 90,
            money = 987650000, lastSeen = now - 330,
            bags = { [0] = container(20, { [1] = enc(HEARTH), [2] = enc(LINEN, 7), [3] = enc(POTION, 5) }) },
            currency = { [3008] = 50, [2815] = 300 },
        },
    }
end

-- Forever: GUID keys, realm groups, full names, balances in copper, the
-- keyring (Enum.BagIndex.Keyring) and the ammo slot (INVSLOT_AMMO).
local NORMAL, PVP = GDAPI_REALMTYPE_NORMAL, GDAPI_REALMTYPE_PVP
local function realmKey(group) return (group:gsub("[%s%-']", "")) end

local function foreverChars(now)
    local normal, pvp = realmKey(NORMAL), realmKey(PVP)
    return {
        ["Player-5826-0A1B2C01"] = {
            name = "Maren Holloway", realm = normal, realmName = NORMAL, class = "PALADIN", level = 60,
            money = 1234567, lastSeen = now - 5400, bankAt = now - 9000,
            bags = {
                [0] = container(16, { [1] = enc(HEARTH), [2] = enc(LINEN, 20), [3] = enc(POTION, 5),
                                      [4] = enc(THUNDERFURY), [5] = enc(WOOL, 57) }),
                [1] = container(14, { [1] = enc(ORE, 40), [2] = enc(LINEN, 15) }),
                [Enum.BagIndex.Keyring] = container(12, { [1] = enc(KEY) }),
            },
            bank = { [6] = container(28, { [1] = enc(WOOL, 400), [2] = enc(POTION, 60) }) },
            equipped = container(19, { [16] = enc(THUNDERFURY), [INVSLOT_AMMO] = enc(ARROW, 200) }),
            mail = { items = { { e = enc(LINEN, 20), x = now + 86400 * 20 } }, scannedAt = now - 1830 },
            mailSold = { { e = enc(ORE, 20), money = 4500, at = now - 930, x = now + 86400 * 30 } },
            auctions = { scannedAt = now - 630, items = {
                { e = enc(POTION, 10), x = now + 86400, id = 11, u = 125 },
                { e = enc(THUNDERFURY), x = now + 86400 * 2, id = 12, u = 99990000 },
            } },
        },
        ["Player-5826-0A1B2C02"] = {
            name = "Maren Ashcombe", realm = pvp, realmName = PVP, class = "WARRIOR", level = 42,
            money = 45678, lastSeen = now - 86400 * 3 - 43200,
            bags = { [0] = container(16, { [1] = enc(HEARTH), [2] = enc(LINEN, 3), [3] = enc(ORE, 12) }) },
        },
        ["Player-5826-0A1B2C03"] = {
            name = "Tobin Reed", realm = normal, realmName = NORMAL, class = "PRIEST", level = 60,
            money = 98765, lastSeen = now - 330,
            bags = { [0] = container(16, { [1] = enc(HEARTH), [2] = enc(LINEN, 7), [3] = enc(POTION, 5) }) },
        },
    }
end

EUIAltsSimFixture.MAIN = FOREVER and "Player-5826-0A1B2C01" or "Aldrianna-Blackhand"
EUIAltsSimFixture.SECOND = FOREVER and "Player-5826-0A1B2C02" or "Bob-Blackhand"
EUIAltsSimFixture.REALM = "*realm:" .. (FOREVER and realmKey(NORMAL) or "Blackhand")
EUIAltsSimFixture.GUILD = "@Knights of Ellesmere-" .. (FOREVER and realmKey(NORMAL) or "Blackhand")

function EUIAltsSimFixture.Install()
    if saved then return end
    local db = ns.db
    saved = { chars = {}, warband = db.warband, guilds = db.guilds, currencyMeta = db.currencyMeta }
    for k, v in pairs(db.chars) do saved.chars[k] = v end
    local infoInstant, info, quality = C_Item.GetItemInfoInstant, C_Item.GetItemInfo, C_Item.GetItemQualityByID
    saved.infoInstant, saved.info, saved.quality = infoInstant, info, quality
    C_Item.GetItemInfoInstant = function(item) return WithFixtureIcon(item, infoInstant(item)) end
    C_Item.GetItemInfo = function(item) return WithFixtureInfo(item, info(item)) end
    C_Item.GetItemQualityByID = function(item)
        local own = ItemOf(item)
        local q = quality(item)
        if own and own[3] and q == nil then return own[3] end
        return q
    end
    HookCurrencyName()
    HookItemName()
    local now = time()
    if FOREVER then
        for k, v in pairs(foreverChars(now)) do db.chars[k] = v end
        local normal = realmKey(NORMAL)
        db.guilds = { ["Knights of Ellesmere-" .. normal] = { name = "Knights of Ellesmere", realm = normal,
            money = 1500000, scannedAt = now - 86400 - 43200,
            tabs = { [1] = container(98, { [1] = enc(POTION, 200) }, "Potions") } } }
        ns.Index:Invalidate()
        ns.Browser:RequestRefresh()
        return
    end
    for k, v in pairs(chars(now)) do db.chars[k] = v end
    db.warband = { money = 250000000, bankAt = now - 9000, bank = {
        [12] = container(98, { [1] = enc(ORE, 500), [2] = enc(WOOL, 1000) }, "Mats"),
    } }
    db.guilds = { ["Knights of Ellesmere-Blackhand"] = { name = "Knights of Ellesmere", realm = "Blackhand",
        money = 1500000000, scannedAt = now - 86400 - 43200, tabs = { [1] = container(98, { [1] = enc(POTION, 200) }, "Potions") } } }
    local meta = {}
    for k, v in pairs(db.currencyMeta or {}) do meta[k] = v end
    meta[3008] = meta[3008] or { t = false, w = false }
    meta[2815] = meta[2815] or { t = true, w = false }
    meta[3028] = meta[3028] or { t = true, w = false }
    meta[2032] = meta[2032] or { t = false, w = true }
    db.currencyMeta = meta
    ns.Index:Invalidate()
    ns.Browser:RequestRefresh()
end

function EUIAltsSimFixture.Uninstall()
    if not saved then return end
    local db = ns.db
    wipe(db.chars)
    for k, v in pairs(saved.chars) do db.chars[k] = v end
    db.warband, db.guilds, db.currencyMeta = saved.warband, saved.guilds, saved.currencyMeta
    C_Item.GetItemInfoInstant, C_Item.GetItemInfo = saved.infoInstant, saved.info
    C_Item.GetItemQualityByID = saved.quality
    saved = nil
    ns.Index:Invalidate()
    ns.Browser:RequestRefresh()
end
