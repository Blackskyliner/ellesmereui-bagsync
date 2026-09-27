-- Aggregated browser views: all characters and one realm, merged stacks,
-- owner tooltips and currency totals with per-character tooltips.
local wow = require("wow")

local HELM_LINK = wow.itemLink(230000, "item:230000::::::::80:66::13:1:10256")
local HELM_REF = "item:230000::::::::80:66::13:1:10256"     -- what is stored and shown: the link's core

local CURRENCIES = {
    { id = 3008, name = "Valorstones", quantity = 1000, icon = 1 },
    { id = 2815, name = "Resonance Crystals", quantity = 900, icon = 2, transferable = true },
    { id = 2032, name = "Trader's Tender", quantity = 750, icon = 4, accountWide = true },
}

local function tooltipText(env)
    local out = {}
    for _, l in ipairs(env.EllesmereUIBagsAltsTooltip.lines) do out[#out + 1] = table.concat(l, " | ") end
    return table.concat(out, "\n")
end

local function counts(f)
    local out = {}
    for i = 1, f.grid.used do
        local b = f.grid.buttons[i]
        out[b.ref] = (out[b.ref] or 0) + b.__count
    end
    return out
end

local function headers(f)
    local out = {}
    for i = 1, f.grid.usedHeaders do out[#out + 1] = f.grid.headers[i].text end
    return out
end

local function currencyRow(f, name)
    for i = 1, f.currencies.used do
        local r = f.currencies.items[i]
        if r.name.text == name then return r end
    end
    error("no currency row " .. name)
end

-- Alice (Blackhand): linen 20, helm, hearthstone, currencies; bank tab with
-- linen 5; warband bank ore 500. Bob (Blackhand): linen 3, bound helm copy.
-- Carol (Proudmoore): linen 7, currencies with fewer valorstones.
local function aliceBags(s)
    wow.putItem(s, 0, 1, 2589, 20)
    wow.putItem(s, 0, 2, 230000, 1, HELM_LINK)
    wow.putItem(s, 0, 3, 6948, 1)
    return s
end

local function world()
    local env = wow.boot(aliceBags(wow.defaultState({ currencies = CURRENCIES })))
    local S = env.__state
    S.bankTabs[0] = { { ID = 6, name = "Main" } }
    S.bags[6] = { size = 98, slots = {} }
    wow.putItem(S, 6, 1, 2589, 5)
    S.bankTabs[2] = { { ID = 12, name = "Mats" } }
    S.bags[12] = { size = 98, slots = {} }
    wow.putItem(S, 12, 1, 190396, 500)
    env.FireEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 8)
    env.FireEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 8)

    local envB = wow.relog(env, { name = "Bob", class = "WARRIOR" }, { currencies = {
        { id = 3008, name = "Valorstones", quantity = 200, icon = 1 },
        { id = 2032, name = "Trader's Tender", quantity = 750, icon = 4, accountWide = true },
    } })
    wow.putItem(envB.__state, 0, 1, 2589, 3)
    wow.putItem(envB.__state, 0, 2, 230000, 1, HELM_LINK)
    envB.FireEvent("BAG_UPDATE", 0)
    envB.FireEvent("BAG_UPDATE_DELAYED")
    local envC = wow.relog(envB, { name = "Carol", realm = "Proudmoore", realmName = "Proudmoore", class = "PRIEST" },
        { currencies = { { id = 3008, name = "Valorstones", quantity = 50, icon = 1 } } })
    wow.putItem(envC.__state, 0, 1, 2589, 7)
    envC.FireEvent("BAG_UPDATE", 0)
    envC.FireEvent("BAG_UPDATE_DELAYED")
    local state = aliceBags(wow.defaultState({ currencies = CURRENCIES }))
    return wow.boot(state, (wow.logout(envC)))
end

describe("All characters view", function()
    it("is the first sidebar entry, with realm entries before their characters", function()
        local env, ns = world()
        ns.Browser:Open()
        local f = env.EllesmereUIBagsAltsBrowser
        local rows = {}
        for i = 1, f.sideRows.used do rows[#rows + 1] = f.sideRows.items[i].ownerKey end
        assert.are.same({ "*all", "*realm:Blackhand", "Alice-Blackhand", "Bob-Blackhand",
            "*realm:Proudmoore", "Carol-Proudmoore", "#warband" }, rows)
        assert.are.same({}, env.__errors)
    end)

    it("merges every stack of all characters, the warband bank included", function()
        local env, ns = world()
        ns.Browser:Open(ns.Browser.ALL_OWNER)
        ns.Browser:SelectTab("all")
        local f = env.EllesmereUIBagsAltsBrowser
        local c = counts(f)
        assert.are.equal(35, c["item:2589"])            -- 20 + 5 bank + 3 Bob + 7 Carol
        assert.are.equal(2, c[HELM_REF])               -- same link: one button
        assert.are.equal(500, c["item:190396"])         -- warband bank
        assert.are.equal(1, c["item:6948"])
        -- one button per merged item
        assert.are.equal(4, f.grid.used)
        -- grouped by item class, in class order
        assert.are.same({ "Armor", "Tradeskill", "Miscellaneous" }, headers(f))
        assert.falsy(f.delete:IsShown())
        assert.are.same({}, env.__errors)
    end)

    it("keeps the per-kind tabs next to the Everything tab", function()
        local env, ns = world()
        ns.Browser:Open(ns.Browser.ALL_OWNER)
        local f = env.EllesmereUIBagsAltsBrowser
        local shown = {}
        for _, tab in ipairs(f.tabs) do if tab:IsShown() then shown[#shown + 1] = tab.key end end
        assert.are.same({ "all", "bags", "bank", "equipped", "mail", "auctions", "currency" }, shown)
        ns.Browser:SelectTab("bags")
        assert.are.equal(30, counts(f)["item:2589"])    -- bags only: no bank
        assert.is_nil(counts(f)["item:190396"])
        ns.Browser:SelectTab("bank")
        assert.are.equal(5, counts(f)["item:2589"])
        assert.are.equal(500, counts(f)["item:190396"])
    end)


    it("shows who holds the item in the tooltip, without the opt-in tooltip setting", function()
        local env, ns = world()
        assert.is_false(ns.db.settings.tooltip.enabled)
        ns.Browser:Open(ns.Browser.ALL_OWNER)
        ns.Browser:SelectTab("all")
        local f = env.EllesmereUIBagsAltsBrowser
        for i = 1, f.grid.used do
            if f.grid.buttons[i].itemID == 2589 then f.grid.buttons[i]:RunScript("OnEnter") end
        end
        local text = tooltipText(env)
        assert.truthy(text:find("Alice", 1, true))
        assert.truthy(text:find("Bags: 20, Bank: 5", 1, true))
        assert.truthy(text:find("Carol%-Proudmoore"))  -- other realm: listed with its realm
        assert.truthy(text:find("Total | 35", 1, true))
        assert.are.same({}, env.__errors)
    end)

    it("adds the owner lines once when the tooltip feature is on too", function()
        local env, ns = world()
        ns.db.settings.tooltip.enabled = true
        ns.SettingsChanged()
        ns.Browser:Open(ns.Browser.ALL_OWNER)
        ns.Browser:SelectTab("all")
        local f = env.EllesmereUIBagsAltsBrowser
        for i = 1, f.grid.used do
            if f.grid.buttons[i].itemID == 2589 then f.grid.buttons[i]:RunScript("OnEnter") end
        end
        local _, n = tooltipText(env):gsub("Total", "")
        assert.are.equal(1, n)
        -- a single character's bag tab keeps the normal (feature) lines
        ns.Browser:Select("Alice-Blackhand")
        ns.Browser:SelectTab("bags")
        for i = 1, f.grid.used do
            if f.grid.buttons[i].itemID == 2589 then f.grid.buttons[i]:RunScript("OnEnter") end
        end
        assert.is_nil(env.EllesmereUIBagsAltsTooltip.processingInfo.euiAltsOwners)
        assert.truthy(tooltipText(env):find("Total", 1, true))
    end)

    it("sums currencies over all characters, warband-wide ones counted once", function()
        local env, ns = world()
        ns.Browser:Open(ns.Browser.ALL_OWNER)
        ns.Browser:SelectTab("currency")
        local f = env.EllesmereUIBagsAltsBrowser
        assert.are.equal("1250", currencyRow(f, "Valorstones").qty.text)        -- 1000 + 200 + 50
        assert.are.equal("900", currencyRow(f, "Resonance Crystals").qty.text)
        assert.are.equal("750", currencyRow(f, "Trader's Tender").qty.text)     -- shared, not 1500
        assert.are.same({}, env.__errors)
    end)

    it("footer sums gold of all characters and the warband", function()
        local env, ns = world()
        for _, c in pairs(ns.db.chars) do c.money = 10000 end
        ns.db.warband.money = 50000
        ns.Browser:Open(ns.Browser.ALL_OWNER)
        local f = env.EllesmereUIBagsAltsBrowser
        assert.truthy(f.footer.text:find("3 characters", 1, true))
        assert.truthy(f.footer.text:find(ns.W.FormatGold(80000), 1, true))
    end)
end)

describe("Everything tab of a character", function()
    it("merges all locations of that one character, without warband or guild", function()
        local env, ns = world()
        ns.Browser:Open("Alice-Blackhand")
        ns.Browser:SelectTab("all")
        local f = env.EllesmereUIBagsAltsBrowser
        local shown = {}
        for _, tab in ipairs(f.tabs) do if tab:IsShown() then shown[#shown + 1] = tab.key end end
        assert.are.same({ "all", "bags", "bank", "equipped", "mail", "auctions", "currency" }, shown)
        local c = counts(f)
        assert.are.equal(25, c["item:2589"])            -- bags 20 + bank 5, not Bob or Carol
        assert.are.equal(1, c[HELM_REF])
        assert.is_nil(c["item:190396"])                 -- warband bank is not the character's
        assert.are.same({ "Armor", "Tradeskill", "Miscellaneous" }, headers(f))
        assert.is_true(f.delete:IsShown() == false)     -- current character: never deletable
        -- footer stays the character's
        assert.truthy(f.footer.text:find("Last seen", 1, true))
        assert.are.same({}, env.__errors)
    end)

    it("tooltip shows where the stacks are", function()
        local env, ns = world()
        ns.Browser:Open("Alice-Blackhand")
        ns.Browser:SelectTab("all")
        local f = env.EllesmereUIBagsAltsBrowser
        for i = 1, f.grid.used do
            if f.grid.buttons[i].itemID == 2589 then f.grid.buttons[i]:RunScript("OnEnter") end
        end
        assert.truthy(tooltipText(env):find("Bags: 20, Bank: 5", 1, true))
        -- the per-location tabs keep their own tooltip (no owner lines)
        ns.Browser:SelectTab("bags")
        for i = 1, f.grid.used do
            if f.grid.buttons[i].itemID == 2589 then f.grid.buttons[i]:RunScript("OnEnter") end
        end
        assert.is_nil(env.EllesmereUIBagsAltsTooltip.processingInfo.euiAltsOwners)
    end)

    it("stays on Everything when switching characters", function()
        local env, ns = world()
        ns.Browser:Open("Alice-Blackhand")
        ns.Browser:SelectTab("all")
        ns.Browser:Select("Carol-Proudmoore")
        assert.are.equal("all", ns.Browser:GetState().tab)
        assert.are.equal(7, counts(env.EllesmereUIBagsAltsBrowser)["item:2589"])
    end)
end)

describe("Realm view", function()
    it("aggregates only the characters of that realm, without the warband bank", function()
        local env, ns = world()
        ns.Browser:Open(ns.Browser.RealmOwner("Blackhand"))
        ns.Browser:SelectTab("all")
        local f = env.EllesmereUIBagsAltsBrowser
        local c = counts(f)
        assert.are.equal(28, c["item:2589"])            -- Alice 25 + Bob 3, not Carol
        assert.is_nil(c["item:190396"])
        ns.Browser:Select(ns.Browser.RealmOwner("Proudmoore"))
        c = counts(f)
        assert.are.equal(7, c["item:2589"])
        assert.is_nil(c[HELM_REF])
        assert.truthy(f.footer.text:find("1 characters", 1, true))
        assert.falsy(f.delete:IsShown())
        assert.are.same({}, env.__errors)
    end)

    it("sums currencies of the realm only", function()
        local env, ns = world()
        ns.Browser:Open(ns.Browser.RealmOwner("Blackhand"))
        ns.Browser:SelectTab("currency")
        local f = env.EllesmereUIBagsAltsBrowser
        assert.are.equal("1200", currencyRow(f, "Valorstones").qty.text)
    end)

    it("falls back when the realm's last character is deleted", function()
        local env, ns = world()
        ns.Browser:Open(ns.Browser.RealmOwner("Proudmoore"))
        ns.DeleteChar("Carol-Proudmoore")
        ns.Browser:Refresh()
        assert.are.equal("Alice-Blackhand", ns.Browser:GetState().owner)
        local _ = env
    end)
end)

describe("Currency tooltip", function()
    it("shows Blizzard's currency tooltip plus who holds how many", function()
        local env, ns = world()
        ns.Browser:Open("Alice-Blackhand")
        ns.Browser:SelectTab("currency")
        local f = env.EllesmereUIBagsAltsBrowser
        currencyRow(f, "Valorstones"):RunScript("OnEnter")
        local tt = env.EllesmereUIBagsAltsTooltip
        assert.are.equal(5, tt.processingInfo.tooltipData.type)   -- currency tooltip data
        local lines = {}
        for _, l in ipairs(tt.lines) do lines[#lines + 1] = table.concat(l, " | ") end
        assert.are.equal("Valorstones", lines[1])
        -- sorted by amount
        assert.truthy(lines[3]:find("Alice", 1, true) and lines[3]:find("1000", 1, true))
        assert.truthy(lines[4]:find("Bob", 1, true) and lines[4]:find("200", 1, true))
        assert.truthy(lines[5]:find("Carol-Proudmoore", 1, true) and lines[5]:find("50", 1, true))
        assert.are.equal("Total | 1250", lines[6])
        assert.are.same({}, env.__errors)
    end)

    it("marks warband-wide currencies as shared instead of listing characters", function()
        local env, ns = world()
        ns.Browser:Open(ns.Browser.ALL_OWNER)
        ns.Browser:SelectTab("currency")
        local f = env.EllesmereUIBagsAltsBrowser
        currencyRow(f, "Trader's Tender"):RunScript("OnEnter")
        local text = tooltipText(env)
        assert.truthy(text:find("Warband-wide (shared)", 1, true))
        assert.falsy(text:find("Alice", 1, true))
    end)

    it("never touches Blizzard's GameTooltip", function()
        local env, ns = world()
        ns.Browser:Open()
        ns.Browser:SelectTab("currency")
        currencyRow(env.EllesmereUIBagsAltsBrowser, "Valorstones"):RunScript("OnEnter")
        assert.is_nil(env.GameTooltip.processingInfo)
        currencyRow(env.EllesmereUIBagsAltsBrowser, "Valorstones"):RunScript("OnLeave")
        assert.is_false(env.EllesmereUIBagsAltsTooltip:IsShown())
    end)
end)
