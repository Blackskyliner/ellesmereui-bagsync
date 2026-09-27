-- Deterministic multi-character data for layout tests and screenshots.
-- EUIAltsSimFixture.Install() adds three characters on two realms, a warband
-- bank and a guild bank next to whatever the simulator's own character holds;
-- Uninstall() restores the previous data. Timestamps are relative to time()
-- and sit mid-bucket (e.g. 2.5 h), so "x h ago" texts render the same in
-- every run, however long the simulator takes to start.
EUIAltsSimFixture = {}

local ns = EllesmereUIBagsAlts._ns
local saved

local LINEN, WOOL, HEARTH, THUNDERFURY, ORE, POTION = 2589, 2592, 6948, 19019, 190396, 212345

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

function EUIAltsSimFixture.Install()
    if saved then return end
    local db = ns.db
    saved = { chars = {}, warband = db.warband, guilds = db.guilds, currencyMeta = db.currencyMeta }
    for k, v in pairs(db.chars) do saved.chars[k] = v end
    local now = time()
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
    saved = nil
    ns.Index:Invalidate()
    ns.Browser:RequestRefresh()
end
