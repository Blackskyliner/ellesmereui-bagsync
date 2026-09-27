-------------------------------------------------------------------------------
--  Core/DB.lua
--  SavedVariables (account wide): EllesmereUIBagsAltsDB
--
--  Deliberately NOT stored inside EllesmereUIDB: EUI wipes db.profile on
--  profile import and must never ship a character roster in profile exports.
--
--  Layout
--    schema   = <number>
--    settings = { collect = {...}, tooltip = {...}, ui = {...}, firstRunAsked }
--    chars    = { ["Name-Realm"] = CharRecord }
--    warband  = { money, moneyAt, bank = Container, bankAt }
--    guilds   = { ["Guild-Realm"] = { name, realm, faction, money, scannedAt, tabs = { [tab] = Container } } }
--    currencyMeta = { [currencyID] = { t = transferable, w = warbandWide } }
--
--  Container = { size = n, name = str?, icon = fileID?, items = "slot:enc;..." (packed, Keys.lua),
--                sets = { [slot] = "Set A, Set B" }? }   -- equipment sets (bags, worn)
--  CharRecord = { name, realm, realmName, class, race, faction, level, guild,
--                 money, lastSeen, bags = {[bagID]=Container}, bank = {[tabID]=Container},
--                 bankAt, equipped = Container, mail = { items = { {e=enc, x=expires} } },
--                 mailAt, mailIncoming = { {e=enc, x=expires, from=key} }, currency = {[id]=qty},
--                 mailSold = { {e=enc, money=copper, at=time, x=expires, id=auctionID} },
--                 auctions = { scannedAt, items = { {e=enc, x=expires, id=auctionID, u=unitPrice, p=provisional} } } }
-------------------------------------------------------------------------------
local _, ns = ...

local type, pairs = type, pairs

ns.SCHEMA = 1

-- New behavior defaults OFF (acceptance criterion 2). Collection of the
-- character's own data is the addon's purpose and has no visible effect, so
-- installing the addon is the opt-in for it; everything that changes what the
-- player sees (tooltip lines, the button in the EUI bag) starts disabled.
ns.DEFAULTS = {
    settings = {
        collect = {
            bags      = true,
            equipped  = true,
            bank      = true,
            mail      = true,
            currency  = true,
            guildbank = false,
            auctions  = true,        -- passive: reads what the client already reports
            auctionsQuery = false,   -- opt-in: request own auctions when the AH opens
        },
        tooltip = {
            enabled     = false,
            modifier    = "none",       -- "none" | "shift" | "ctrl" | "alt"
            realmScope  = "connected",  -- "all" | "connected" | "realm"
            showTotal   = true,
            hideCurrent = false,
            showWarband = true,
            showGuild   = true,
            maxChars    = 10,
        },
        ui = {
            headerButton     = false,
            useEUICategories = false,
            browserScale     = 1,
        },
        firstRunAsked = false,
        debug = false,   -- /alts debug: chat diagnostics
    },
}

-- Migrations run in order for every schema step above the stored one.
-- MIGRATIONS[n] upgrades a schema n-1 database to schema n.
local MIGRATIONS = {
    -- [2] = function(db) end,
}

local function MergeDefaults(target, defaults)
    for k, dv in pairs(defaults) do
        local tv = target[k]
        if type(dv) == "table" then
            if type(tv) ~= "table" then
                tv = {}
                target[k] = tv
            end
            MergeDefaults(tv, dv)
        elseif tv == nil or type(tv) ~= type(dv) then
            target[k] = dv
        end
    end
end
ns.MergeDefaults = MergeDefaults

-- Drops anything that is not shaped like our data instead of erroring later.
-- Re-encodes a stored stack (item links shortened to their "item:" core);
-- nil when it does not decode.
local function Recode(enc)
    if type(enc) ~= "string" then return nil end
    local id, count, link, bound = ns.DecodeItem(enc)
    if not id then return nil end
    return ns.EncodeItem(id, count, link, bound)
end

-- Up to 0.7.x containers kept a table { [slot] = enc }: packed here once.
-- Packed strings are re-packed only when they hold something malformed.
local function SanitizeItems(items)
    local map, clean = {}, true
    if type(items) == "table" then
        clean = false
        for slot, enc in pairs(items) do
            if type(slot) == "number" then map[slot] = Recode(enc) end
        end
    elseif type(items) == "string" then
        for slot, enc in ns.EachItem(items) do
            local good = Recode(enc)
            if good ~= enc then clean = false end
            map[slot] = good
        end
    else
        return ""
    end
    if clean then return items end
    return ns.PackItems(map)
end

local function SanitizeContainer(c)
    if type(c) ~= "table" then return nil end
    c.items = SanitizeItems(c.items)
    if type(c.size) ~= "number" then c.size = 0 end
    if c.sets ~= nil then
        if type(c.sets) ~= "table" then
            c.sets = nil
        else
            for slot, names in pairs(c.sets) do
                if type(slot) ~= "number" or type(names) ~= "string" then c.sets[slot] = nil end
            end
        end
    end
    return c
end

local function SanitizeContainerMap(map)
    if type(map) ~= "table" then return {} end
    for id, c in pairs(map) do
        if type(id) ~= "number" or not SanitizeContainer(c) then map[id] = nil end
    end
    return map
end

local function SanitizeMailList(list)
    if type(list) ~= "table" then return {} end
    local out = {}
    for i = 1, #list do
        local m = list[i]
        local e = type(m) == "table" and Recode(m.e)
        if e then
            m.e = e
            out[#out + 1] = m
        end
    end
    return out
end

local function SanitizeChar(key, c)
    if type(key) ~= "string" or type(c) ~= "table" then return nil end
    c.bags = SanitizeContainerMap(c.bags)
    c.bank = SanitizeContainerMap(c.bank)
    c.equipped = SanitizeContainer(c.equipped)
    if type(c.mail) ~= "table" then c.mail = {} end
    c.mail.items = SanitizeMailList(c.mail.items)
    c.mailIncoming = SanitizeMailList(c.mailIncoming)
    c.mailSold = SanitizeMailList(c.mailSold)
    for _, m in ipairs(c.mailSold) do
        if type(m.money) ~= "number" then m.money = 0 end
    end
    if type(c.auctions) ~= "table" then c.auctions = {} end
    c.auctions.items = SanitizeMailList(c.auctions.items)
    if type(c.currency) ~= "table" then c.currency = {} end
    if not c.name then c.name, c.realm = ns.SplitKey(key) end
    return c
end

function ns.InitDB()
    local db = _G.EllesmereUIBagsAltsDB
    if type(db) ~= "table" then db = {} end

    local stored = type(db.schema) == "number" and db.schema or ns.SCHEMA
    for step = stored + 1, ns.SCHEMA do
        local migrate = MIGRATIONS[step]
        if migrate then ns.SafeCall(migrate, db) end
    end
    db.schema = ns.SCHEMA

    MergeDefaults(db, ns.DEFAULTS)

    -- Only the shape here; every stored record is checked by SanitizeData on
    -- activation, so an unused addon does not walk its data at login.
    if type(db.chars) ~= "table" then db.chars = {} end
    if type(db.warband) ~= "table" then db.warband = {} end
    if type(db.currencyMeta) ~= "table" then db.currencyMeta = {} end
    if type(db.guilds) ~= "table" then db.guilds = {} end

    _G.EllesmereUIBagsAltsDB = db
    ns.db = db
    return db
end

-- Repairs or drops malformed stored records (hand edits, old versions).
function ns.SanitizeData()
    local db = ns.db
    if not db then return end
    for key, c in pairs(db.chars) do
        if not SanitizeChar(key, c) then db.chars[key] = nil end
    end

    db.warband.bank = SanitizeContainerMap(db.warband.bank)

    for id, meta in pairs(db.currencyMeta) do
        if type(id) ~= "number" or type(meta) ~= "table" then db.currencyMeta[id] = nil end
    end

    for key, g in pairs(db.guilds) do
        if type(key) ~= "string" or type(g) ~= "table" then
            db.guilds[key] = nil
        else
            g.tabs = SanitizeContainerMap(g.tabs)
        end
    end
    if ns.Index then ns.Index:Invalidate() end
end

-------------------------------------------------------------------------------
--  Accessors
-------------------------------------------------------------------------------
function ns.GetChar(key, create)
    local db = ns.db
    if not db or not key then return nil end
    local c = db.chars[key]
    if not c and create then
        c = SanitizeChar(key, {})
        db.chars[key] = c
    end
    return c
end

function ns.GetPlayerChar(create)
    return ns.GetChar(ns.GetPlayerKey(), create)
end

function ns.GetGuild(key, create)
    local db = ns.db
    if not db or not key then return nil end
    local g = db.guilds[key]
    if not g and create then
        g = { tabs = {} }
        db.guilds[key] = g
    end
    return g
end

function ns.DeleteChar(key)
    if not ns.db or not ns.db.chars[key] then return false end
    ns.db.chars[key] = nil
    ns.Fire("DATA_RESET")
    return true
end

function ns.DeleteGuild(key)
    if not ns.db or not ns.db.guilds[key] then return false end
    ns.db.guilds[key] = nil
    ns.Fire("DATA_RESET")
    return true
end

function ns.ResetAllData()
    if not ns.db then return end
    ns.db.chars = {}
    ns.db.warband = { bank = {} }
    ns.db.guilds = {}
    ns.Fire("DATA_RESET")
end

-- Sorted character keys (realm, then name) for stable UI ordering.
function ns.GetSortedCharKeys()
    local keys = {}
    if not ns.db then return keys end
    for key in pairs(ns.db.chars) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b)
        local ca, cb = ns.db.chars[a], ns.db.chars[b]
        local ra, rb = ca.realm or "", cb.realm or ""
        if ra ~= rb then return ra < rb end
        return (ca.name or a) < (cb.name or b)
    end)
    return keys
end

function ns.GetSortedGuildKeys()
    local keys = {}
    if not ns.db then return keys end
    for key in pairs(ns.db.guilds) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end
