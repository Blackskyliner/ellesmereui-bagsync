-- The search's scope: everything (the result list) or the view shown, whose
-- stacks it dims or hides, set in the options and switched per session.
local wow = require("wow")

local CURRENCIES = {
    { id = 3008, name = "Valorstones", quantity = 1000, icon = 1 },
    { id = 2815, name = "Resonance Crystals", quantity = 900, icon = 2, transferable = true },
}

local function world()
    local s = wow.defaultState({ currencies = CURRENCIES })
    wow.putItem(s, 0, 1, 2589, 20)                       -- Linen Cloth
    wow.putItem(s, 0, 2, 2592, 5)                        -- Wool Cloth
    wow.putItem(s, 0, 3, 6948, 1)                        -- Hearthstone, soulbound
    s.bags[0].slots[3].bound = true
    local env, ns = wow.boot(s)
    ns.Browser:Open()
    ns.Browser:SelectTab("bags")
    return env, ns, env.EllesmereUIBagsAltsBrowser
end

local function buttons(f)
    local out = {}
    for i = 1, f.grid.used do
        local b = f.grid.buttons[i]
        out[b.itemID] = b:GetAlpha()
    end
    return out
end

local function tabsShown(f)
    local n = 0
    for _, tab in ipairs(f.tabs) do if tab:IsShown() then n = n + 1 end end
    return n
end

describe("Search scope", function()
    it("searches everything by default, as before", function()
        local _, ns, f = world()
        assert.are.equal("all", ns.db.settings.ui.searchScope)
        ns.Browser:SetQuery("linen")
        assert.is_true(f.results.used > 0)
        assert.are.equal(0, f.grid.used)
        assert.are.equal(0, tabsShown(f))
        assert.are.equal("Everywhere", f.scope.text or f.scope:GetText())
    end)

    it("dims what the view's search does not match and keeps the tabs", function()
        local env, ns, f = world()
        ns.db.settings.ui.searchScope = "view"
        ns.Browser:SetQuery("linen")
        assert.are.equal(0, f.results.used)
        assert.are.same({ [2589] = 1, [2592] = 0.25, [6948] = 0.25 }, buttons(f))
        assert.are.equal(8, tabsShown(f))
        assert.truthy(f.footer.text:find("1 results", 1, true))
        assert.are.same({}, env.__errors)
    end)

    it("hides it instead when the option says so", function()
        local _, ns, f = world()
        ns.db.settings.ui.searchScope, ns.db.settings.ui.searchMiss = "view", "hide"
        ns.Browser:SetQuery("cloth")
        assert.are.same({ [2589] = 1, [2592] = 1 }, buttons(f))
        ns.Browser:SetQuery("zzzz")
        assert.are.equal(0, f.grid.used)
        assert.are.equal("Nothing found.", f.empty.text)
    end)

    it("reads bind expressions per stack in the view", function()
        local _, ns, f = world()
        ns.db.settings.ui.searchScope, ns.db.settings.ui.searchMiss = "view", "hide"
        ns.Browser:SetQuery("soulbound")
        assert.are.same({ [6948] = 1 }, buttons(f))
    end)

    it("filters currencies by name", function()
        local _, ns, f = world()
        ns.db.settings.ui.searchScope, ns.db.settings.ui.searchMiss = "view", "hide"
        ns.Browser:SelectTab("currency")
        ns.Browser:SetQuery("valor")
        assert.are.equal(1, f.currencies.used)
        assert.are.equal("Valorstones", f.currencies.items[1].name.text)
        ns.db.settings.ui.searchMiss = "dim"
        ns.Browser:Refresh()
        assert.are.equal(2, f.currencies.used)
    end)

    it("switches for the session from the header, leaving the setting alone", function()
        local _, ns, f = world()
        ns.Browser:SetQuery("linen")
        f.scope:RunScript("OnClick")
        assert.are.equal("all", ns.db.settings.ui.searchScope)
        assert.are.equal(0, f.results.used)
        assert.are.equal(1, buttons(f)[2589])
        f.scope:RunScript("OnClick")
        assert.is_true(f.results.used > 0)
    end)

    it("/alts search lists every match, whatever the scope", function()
        local _, ns, f = world()
        ns.db.settings.ui.searchScope = "view"
        ns.Browser:OpenSearch("linen")
        assert.is_true(f.results.used > 0)
    end)

    it("filters the value list too", function()
        local _, ns, f = world()
        ns.db.settings.ui.searchScope, ns.db.settings.ui.searchMiss = "view", "hide"
        ns.Browser:SelectTab("value")
        ns.Browser:SetQuery("wool")
        assert.are.equal(1, #ns.ValueList.rows)
        assert.are.equal(2592, ns.ValueList.rows[1].id)
        ns.db.settings.ui.searchMiss = "dim"
        ns.Browser:Refresh()
        assert.is_true(#ns.ValueList.rows > 1)
        for _, m in ipairs(ns.ValueList.rows) do assert.are.equal(m.id ~= 2592, m.miss) end
        assert.truthy(f.footer.text:find("1 results", 1, true))
    end)
end)
