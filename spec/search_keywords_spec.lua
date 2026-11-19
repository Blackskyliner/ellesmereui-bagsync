-- The browser search beyond item names: tooltip text and the bind expressions
-- EllesmereUI Bags adds to the game's search.
local wow = require("wow")

-- Alice holds:
--   Hearthstone (BoP, soulbound), Void-Touched Helm (BoE, two stacks: one at
--   600, one at 610 with an enchant), Drifting Gauntlets (WuE, reported as
--   OnEquip), Warbound Cloak (warbound until equipped, bind type 9), Heirloom
--   Staff (bound to the warband), Linen Cloth (no binding).
local HELM_610 = "item:230000:7000::::::::80:::::"
local function world(stateHook)
    local s = wow.defaultState()
    wow.putItem(s, 0, 1, 6948, 1)
    s.bags[0].slots[1].bound = true
    wow.putItem(s, 0, 2, 230000, 1)
    wow.putItem(s, 0, 3, 230000, 1, wow.itemLink(230000, HELM_610))
    wow.putItem(s, 0, 4, 230001, 1)
    wow.putItem(s, 0, 5, 231000, 1)
    wow.putItem(s, 0, 6, 232000, 1)
    s.bags[0].slots[6].bound = true
    wow.putItem(s, 0, 7, 2589, 20)
    s.itemLevels = { [HELM_610] = 610 }
    if stateHook then stateHook(s) end
    return wow.boot(s)
end

local function ids(ns, text)
    local results, pending = ns.Search.Run(ns.Search.Parse(text))
    local out = {}
    for i, r in ipairs(results) do out[i] = r.itemID end
    table.sort(out)
    return out, pending
end

describe("Search by tooltip text", function()
    it("finds a word that only the tooltip holds, like the game's bag search", function()
        local _, ns = world()
        -- "Binds when equipped", "Warbound until equipped"
        assert.are.same({ 230000, 230001, 231000 }, (ids(ns, "equipped")))
        assert.are.same({ 230000 }, (ids(ns, "stamina")))
        assert.are.same({ 230000 }, (ids(ns, "plate")))                  -- right-hand text too
    end)

    it("needs every word in the name or the tooltip", function()
        local _, ns = world()
        assert.are.same({ 230000 }, (ids(ns, "helm stamina")))
        assert.are.same({}, (ids(ns, "linen stamina")))
    end)

    it("reads a bound stack's binding line as Soulbound, like its tooltip in the browser", function()
        local bindHelms = function(s) s.bags[0].slots[2].bound = true; s.bags[0].slots[3].bound = true end
        local _, ns = world(bindHelms)
        assert.are.same({ 230001, 231000 }, (ids(ns, "equipped")))       -- both helms are bound
        assert.are.same({ 6948, 230000 }, (ids(ns, "soulbound")))
        assert.are.same({ 230000 }, (ids(ns, "helm soulbound")))
        assert.are.same({ 232000 }, (ids(ns, "warbound staff")))
        -- one free stack keeps the generic line for the item
        local _, ns2 = world(function(s) s.bags[0].slots[2].bound = true end)
        assert.are.same({ 230000 }, (ids(ns2, "helm equipped")))
        assert.are.same({ 230000 }, (ids(ns2, "helm soulbound")))
        assert.are.same({}, (ids(ns2, "soulbound equipped")))           -- never both on one stack
    end)

    it("matches a quoted phrase in the name or in one tooltip line", function()
        local _, ns = world(function(s) s.bags[0].slots[2].bound = true; s.bags[0].slots[3].bound = true end)
        assert.are.same({ 230000 }, (ids(ns, '"+120  stamina"')))
        assert.are.same({}, (ids(ns, '"stamina +120"')))
        assert.are.same({}, (ids(ns, '"head plate"')))                   -- left and right text apart
        assert.are.same({ 230000 }, (ids(ns, '"void-touched helm"')))
        -- the bound helms keep their "Equip:" line, not "Binds when equipped"
        assert.are.same({ 230000, 230001, 231000 }, (ids(ns, "equip")))
        assert.are.same({ 230001 }, (ids(ns, '"binds when equipped"')))
        assert.are.same({ 230001 }, (ids(ns, '"binds when'))) -- unclosed: to the end
        assert.are.same({ 230001 }, (ids(ns, '"binds when" gauntlets')))     -- a phrase and a word
    end)

    it("shows Soulbound in a hit's tooltip when every stack is bound", function()
        local env, ns = world(function(s) s.bags[0].slots[2].bound = true; s.bags[0].slots[3].bound = true end)
        ns.Browser:OpenSearch("helm")
        local f = env.EllesmereUIBagsAltsBrowser
        local row = f.results.items[1]
        assert.are.equal(230000, row.itemID)
        row:RunScript("OnEnter")
        local tt = env.NotGameTooltipEllesmereUIBagsAlts
        local text = {}
        for _, l in ipairs(tt.lines) do text[#text + 1] = table.concat(l, " | ") end
        text = table.concat(text, "\n")
        assert.truthy(text:find("Soulbound", 1, true), text)
        assert.falsy(text:find("Binds when equipped", 1, true), text)
        -- one free stack: the item's own line
        local env2, ns2 = world(function(s) s.bags[0].slots[2].bound = true end)
        ns2.Browser:OpenSearch("helm")
        env2.EllesmereUIBagsAltsBrowser.results.items[1]:RunScript("OnEnter")
        text = {}
        for _, l in ipairs(env2.NotGameTooltipEllesmereUIBagsAlts.lines) do text[#text + 1] = table.concat(l, " | ") end
        assert.truthy(table.concat(text, "\n"):find("Binds when equipped", 1, true))
        assert.are.same({}, env.__errors)
    end)

    it("reads an item's tooltip once and only for words its name lacks", function()
        local env, ns = world()
        local S = env.__state
        S.tooltipCalls = 0
        ids(ns, "hearthstone")                 -- every item but the Hearthstone
        assert.are.equal(5, S.tooltipCalls)
        ids(ns, "hearthstone")
        assert.are.equal(5, S.tooltipCalls)
        ids(ns, "stamina")                     -- the Hearthstone is new
        assert.are.equal(6, S.tooltipCalls)
    end)
end)

describe("Bind expressions", function()
    it("matches each keyword by bind type and bound state", function()
        local _, ns = world()
        assert.are.same({ 6948 }, (ids(ns, "bop")))
        assert.are.same({ 230000 }, (ids(ns, "boe")))
        assert.are.same({ 230001, 231000 }, (ids(ns, "wue")))           -- bind type 9 and the OnEquip one
        assert.are.same({ 6948 }, (ids(ns, "soulbound")))
        assert.are.same({ 232000 }, (ids(ns, "warbound")))
        assert.are.same({ 6948, 230000, 230001, 231000 }, (ids(ns, "BOP or BoE or wue")))
    end)

    it("filters by the item level of each stack", function()
        local _, ns = world()
        assert.are.same({ 230000 }, (ids(ns, "boe=610")))
        assert.are.same({ 230000 }, (ids(ns, "boe 600")))
        assert.are.same({}, (ids(ns, "boe>610")))
        assert.are.same({ 230000 }, (ids(ns, "boe 605-615")))
        assert.are.same({ 230001 }, (ids(ns, "wue<=595")))
    end)

    it("joins terms with and, or, not, symbols and parentheses", function()
        local _, ns = world()
        assert.are.same({ 230000, 230001, 231000 }, (ids(ns, "(boe | wue) & !warbound")))
        assert.are.same({ 230001, 231000 }, (ids(ns, "wue not soulbound")))   -- side by side means and
        assert.are.same({}, (ids(ns, "bop and boe")))
    end)

    it("leaves other texts to the word search", function()
        local _, ns = world()
        assert.is_nil(ns.Search.Parse("boe helm").bind)
        assert.is_nil(ns.Search.Parse("boe and").bind)
        assert.is_nil(ns.Search.Parse("(boe").bind)
        assert.is_nil(ns.Search.Parse("not").bind)
        assert.is_not_nil(ns.Search.Parse("  BoE  ").bind)
    end)

    it("leaves the account bind keywords out of the help on WoW Forever", function()
        local function examples(ns)
            local out = {}
            for _, r in ipairs(ns.Search.HelpLines().rows) do out[#out + 1] = r[1] end
            return table.concat(out, "\n")
        end
        local _, retail = world()
        local _, fv = world(function(s) s.client = "forever" end)
        for _, kw in ipairs({ "wue", "boa", "warbound" }) do
            assert.truthy(examples(retail):find(kw, 1, true), kw)
            assert.falsy(examples(fv):find(kw, 1, true), kw)
        end
        for _, ex in ipairs({ "bop or boe", "soulbound", "boe>=20  bop 10-30", "bop or (boe and not soulbound)" }) do
            assert.truthy(examples(fv):find(ex, 1, true) or ex == "bop or boe", ex)
            assert.is_not_nil(fv.Search.Parse(ex).bind, ex)
        end
    end)

    it("waits for item data it does not have and finds no currencies", function()
        local _, ns = world(function(s) s.uncachedItems = { [6948] = true } end)
        local found, pending = ids(ns, "bop")
        assert.are.same({}, found)
        assert.are.same({ 6948 }, pending)
        assert.are.same({}, ns.Search.RunCurrencies(ns.Search.Parse("bop")))
    end)

    it("shows in the browser and its help", function()
        local env, ns = world()
        ns.Browser:OpenSearch("soulbound")
        local f = env.EllesmereUIBagsAltsBrowser
        assert.are.equal(1, f.results.used)
        assert.are.equal(6948, f.results.items[1].itemID)
        local rows = {}
        for _, r in ipairs(ns.Search.HelpLines().rows) do rows[#rows + 1] = r[1] end
        rows = table.concat(rows, "\n")
        for _, example in ipairs({ "bop  boe  wue  boa", "boe>=600", "bop or (boe and not wue)" }) do
            assert.truthy(rows:find(example, 1, true), example)
            local example1 = example:gsub("  ", " or ")
            assert.is_not_nil(ns.Search.Parse(example1).bind, example1)
        end
        assert.are.same({}, env.__errors)
    end)
end)
