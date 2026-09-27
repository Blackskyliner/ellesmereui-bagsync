-- Search over stored currency names next to the item search.
local wow = require("wow")

local CURRENCIES = {
    { id = 3008, name = "Valorstones", quantity = 1000, icon = 1 },
    { id = 2815, name = "Resonance Crystals", quantity = 900, icon = 2, transferable = true },
    { id = 2032, name = "Trader's Tender", quantity = 750, icon = 4, accountWide = true },
    { id = 3100, name = "Weathered Crest 2", quantity = 5, icon = 5 },
}

-- Alice: all currencies + linen; Bob: 200 valorstones, 750 tender (shared).
local function world()
    local s = wow.defaultState({ currencies = CURRENCIES })
    wow.putItem(s, 0, 1, 2589, 20)
    local env = wow.boot(s)
    local envB = wow.relog(env, { name = "Bob", class = "WARRIOR" }, { currencies = {
        { id = 3008, name = "Valorstones", quantity = 200, icon = 1 },
        { id = 2032, name = "Trader's Tender", quantity = 750, icon = 4, accountWide = true },
    } })
    local state = wow.defaultState({ currencies = CURRENCIES })
    wow.putItem(state, 0, 1, 2589, 20)
    return wow.boot(state, (wow.logout(envB)))
end

local function rows(f)
    local out = {}
    for i = 1, f.results.used do
        local r = f.results.items[i]
        out[#out + 1] = { name = r.name.text, total = r.total.text, detail = r.detail.text,
                          currencyID = r.currencyID, itemID = r.itemID, row = r }
    end
    return out
end

local function headers(f)
    local out = {}
    for i = 1, f.grid.usedHeaders do out[#out + 1] = f.grid.headers[i].text end
    return out
end

describe("Currency search", function()
    it("finds currencies by name with the total over all characters", function()
        local env, ns = world()
        ns.Browser:OpenSearch("valor")
        local f = env.EllesmereUIBagsAltsBrowser
        local r = rows(f)
        assert.are.equal(1, #r)
        assert.are.equal("Valorstones", r[1].name)
        assert.are.equal(3008, r[1].currencyID)
        assert.are.equal("1200", r[1].total)
        -- holders, most first
        assert.truthy(r[1].detail:find("Alice|r 1000, ", 1, true))
        assert.truthy(r[1].detail:find("Bob|r 200", 1, true))
        assert.are.same({ "Currency" }, headers(f))
        assert.are.equal("1 results", f.footer.text)
        assert.are.same({}, env.__errors)
    end)

    it("lists currencies before items, each under its own header", function()
        local env, ns = world()
        ns.Browser:OpenSearch("n")                     -- "Linen Cloth", "Valorstones", ...
        local f = env.EllesmereUIBagsAltsBrowser
        local r = rows(f)
        assert.are.same({ "Currency", "Items" }, headers(f))
        assert.is_not_nil(r[1].currencyID)
        assert.are.equal(2589, r[#r].itemID)
        local y = {}
        for i, row in ipairs(r) do y[i] = -row.row.points[1][3] end
        for i = 2, #y do assert.is_true(y[i] > y[i - 1]) end      -- top to bottom
    end)

    it("counts a warband-wide currency once and says it is shared", function()
        local env, ns = world()
        ns.Browser:OpenSearch("tender")
        local r = rows(env.EllesmereUIBagsAltsBrowser)
        assert.are.equal("750", r[1].total)
        assert.are.equal("Warband-wide (shared)", r[1].detail)
    end)

    it("matches a bare number in the name; id:, q: and t: filter items only", function()
        local _, ns = world()
        local S = ns.Search
        assert.are.equal(1, #S.RunCurrencies(S.Parse("2")))            -- "Weathered Crest 2"
        assert.are.equal(0, #S.RunCurrencies(S.Parse("id:3008")))
        assert.are.equal(0, #S.RunCurrencies(S.Parse("valor q:epic")))
        assert.are.equal(0, #S.RunCurrencies(S.Parse("valor t:armor")))
        assert.are.equal(0, #S.RunCurrencies(S.Parse("valor crystals"))) -- every word must match
        assert.are.equal(1, #S.RunCurrencies(S.Parse("valorstones")))    -- case-insensitive
    end)

    it("shows the currency tooltip with holders on hover and links on shift-click", function()
        local env, ns = world()
        ns.Browser:OpenSearch("valor")
        local r = rows(env.EllesmereUIBagsAltsBrowser)[1].row
        r:RunScript("OnEnter")
        local tt = env.EllesmereUIBagsAltsTooltip
        assert.are.equal(5, tt.processingInfo.tooltipData.type)
        local text = {}
        for _, l in ipairs(tt.lines) do text[#text + 1] = table.concat(l, " | ") end
        text = table.concat(text, "\n")
        assert.truthy(text:find("Total | 1200", 1, true))
        env.__state.modifiers.shift = true
        r:RunScript("OnClick", "LeftButton")
        assert.truthy(env.__clicks[#env.__clicks]:find("|Hcurrency:3008", 1, true))
    end)

    it("a reused result row loses its currency when it shows an item", function()
        local env, ns = world()
        ns.Browser:OpenSearch("valor")
        ns.Browser:SetQuery("linen")
        local r = rows(env.EllesmereUIBagsAltsBrowser)
        assert.are.equal(1, #r)
        assert.is_nil(r[1].currencyID)
        r[1].row:RunScript("OnEnter")
        assert.are.equal(0, env.EllesmereUIBagsAltsTooltip.processingInfo.tooltipData.type)
    end)

    it("reports nothing found for neither currencies nor items", function()
        local env, ns = world()
        ns.Browser:OpenSearch("zzzz")
        assert.are.equal("Nothing found.", env.EllesmereUIBagsAltsBrowser.empty.text)
    end)
end)
