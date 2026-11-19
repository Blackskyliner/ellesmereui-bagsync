-- The browser's value list: price sources, the auction house cut, bound
-- items, which owners and locations count, equipment sets and sorting.
local wow = require("wow")

local HELM_REF = "item:230000::::::::80:66::13:1:10256"

-- Price addons as their globals look to another addon. prices: itemID ->
-- { region, realm, auctionator, age, tsm }.
local function installPriceAddons(env, prices, opts)
    opts = opts or {}
    local function idOf(ref) return tonumber(tostring(ref):match("item:(%d+)")) or tonumber(ref) end
    env.OEMarketInfo = function(item, result)
        if item == 0 then return true end
        if opts.oeThrows then error("OE broke") end
        for k in pairs(result) do result[k] = nil end
        local p = prices[idOf(item)]
        if p then result.region, result.market = p.region, p.realm end
        return result
    end
    local scanned = 0
    for _, p in pairs(prices) do if p.auctionator then scanned = scanned + 1 end end
    env.Auctionator = { Database = { GetItemCount = function() return opts.emptyScan and 0 or scanned end },
                        API = { v1 = {
        GetAuctionPriceByItemID = function(caller, id)
            assert(caller == "EllesmereUIBags_Alts")
            return prices[id] and prices[id].auctionator
        end,
        GetAuctionPriceByItemLink = function(caller, link)
            assert(caller == "EllesmereUIBags_Alts")
            local p = prices[idOf(link)]
            return p and p.auctionator
        end,
        GetAuctionAgeByItemID = function(_, id) return prices[id] and prices[id].age end,
        GetAuctionAgeByItemLink = function(_, link) local p = prices[idOf(link)] return p and p.age end,
    } } }
    env.TSM_API = {
        ToItemString = function(ref) return "i:" .. idOf(ref) end,
        GetCustomPriceValue = function(priceString, itemString)
            env.__tsmPriceString = priceString
            local p = prices[tonumber(itemString:match("i:(%d+)"))]
            return p and p.tsm
        end,
    }
end

local function container(map, sets)
    return { size = 20, items = wow.pack(map), sets = sets }
end

-- Alice (player): linen 20 and a free helm in her bags, a soulbound helm
-- worn, an ore stack in a set slot, wool in the bank, linen in the mail and
-- an auction of ore. Bob (same realm): a warbound-until-equipped cloak and
-- a soulbound hearthstone. Carol (other realm): linen 7. Warband bank: ore
-- 500. Guild bank: wool 40.
local function world(prices, opts)
    wow.ITEMS[2589].sellPrice = 10       -- linen
    wow.ITEMS[2592].sellPrice = 25       -- wool
    wow.ITEMS[190396].sellPrice = 50     -- ore
    wow.ITEMS[231000].sellPrice = 5000   -- cloak
    wow.ITEMS[6948].sellPrice = 0        -- hearthstone: does not sell
    local env, ns = wow.boot(wow.defaultState())
    local db = ns.db
    local alice = ns.GetPlayerChar()
    alice.bags = { [0] = container({
        [1] = ns.EncodeItem(2589, 20),
        [2] = ns.EncodeItem(230000, 1, HELM_REF),
        [3] = ns.EncodeItem(190396, 10),
    }, { [3] = "PvP" }) }
    alice.equipped = container({ [1] = ns.EncodeItem(230000, 1, HELM_REF, "soul") })
    alice.bank = { [6] = container({ [1] = ns.EncodeItem(2592, 8) }) }
    alice.mail = { items = { { e = ns.EncodeItem(2589, 5), x = 0 } } }
    alice.auctions = { items = { { e = ns.EncodeItem(190396, 100), x = 0, id = 1, u = 99 } } }
    db.chars["Player-1-Bob"] = { name = "Bob", realm = "Blackhand", realmName = "Blackhand", class = "WARRIOR",
        bags = { [0] = container({ [1] = ns.EncodeItem(231000, 1, nil, "wue"), [2] = ns.EncodeItem(6948, 1, nil, "soul") }) },
        bank = {}, mail = { items = {} }, mailIncoming = {}, currency = {} }
    db.chars["Player-1-Carol"] = { name = "Carol", realm = "Proudmoore", realmName = "Proudmoore", class = "PRIEST",
        bags = { [0] = container({ [1] = ns.EncodeItem(2589, 7) }) },
        bank = {}, mail = { items = {} }, mailIncoming = {}, currency = {} }
    db.warband.bank = { [12] = container({ [1] = ns.EncodeItem(190396, 500) }) }
    db.guilds["Guild-Blackhand"] = { name = "Guild", realm = "Blackhand",
        tabs = { [1] = container({ [1] = ns.EncodeItem(2592, 40) }) } }
    installPriceAddons(env, prices or {}, opts)
    return env, ns
end

local PRICES = {
    [2589]   = { region = 100, realm = 80, auctionator = 120, age = 2, tsm = 90 },   -- linen
    [2592]   = { region = 300, realm = 400, auctionator = nil, tsm = 350 },          -- wool
    [190396] = { region = 1000, realm = 1100, auctionator = 900, tsm = 1200 },       -- ore
    [230000] = { region = 500000, realm = 450000 },                                  -- helm
    [231000] = { region = 900000, realm = 900000, auctionator = 900000 },            -- cloak (wue)
}

local function open(ns, owner)
    ns.Browser:Open(owner)
    ns.Browser:SelectTab("value")
    return ns.ValueList.rows
end

local function find(rows, owner, loc, id)
    for _, m in ipairs(rows) do
        if m.owner == owner and m.loc == loc and m.id == id then return m end
    end
    return nil
end

local function rowTooltip(env, ns, id, loc)
    for _, r in ipairs(ns.ValueList.pool) do
        if r:IsShown() and r.data and r.data.id == id and r.data.loc == loc then
            r:RunScript("OnEnter")
            local out = {}
            for _, l in ipairs(env.NotGameTooltipEllesmereUIBagsAlts.lines) do out[#out + 1] = table.concat(l, " | ") end
            return table.concat(out, "\n")
        end
    end
    error("no row for " .. id .. " " .. loc)
end

local function keys(rows)
    local out = {}
    for _, m in ipairs(rows) do out[#out + 1] = m.owner .. " " .. m.loc .. " " .. m.id end
    table.sort(out)
    return out
end

describe("Value list", function()
    after_each(function()
        for _, id in ipairs({ 2589, 2592, 190396, 231000, 6948 }) do wow.ITEMS[id].sellPrice = nil end
    end)

    it("is a browser tab of characters, the aggregated views and both kinds of bank", function()
        local env, ns = world(PRICES)
        ns.Browser:Open()
        local f = env.EllesmereUIBagsAltsBrowser
        for _, owner in ipairs({ "Player-1-Alice", ns.Browser.ALL_OWNER, "*realm:Blackhand" }) do
            ns.Browser:Open(owner)
            local shown = {}
            for _, tab in ipairs(f.tabs) do if tab:IsShown() then shown[#shown + 1] = tab.key end end
            assert.are.equal("value", shown[#shown])
            assert.are.equal(8, #shown)
        end
        for _, owner in ipairs({ ns.WARBAND_OWNER, "@Guild-Blackhand" }) do
            ns.Browser:Open(owner)
            local shown = {}
            for _, tab in ipairs(f.tabs) do if tab:IsShown() then shown[#shown + 1] = tab.key end end
            assert.are.same({ "all", "value" }, shown)
        end
        assert.are.same({}, env.__errors)
    end)

    it("prices each stack by the highest source after the auction house cut", function()
        local env, ns = world(PRICES)
        local rows = open(ns, "Player-1-Alice")
        local linen = find(rows, "Player-1-Alice", "bags", 2589)
        assert.are.equal("auctionator", linen.source)
        assert.are.equal(114, linen.unit)                     -- 120 - 5%
        assert.are.equal(20 * 114, linen.value)
        assert.are.equal(20 * (114 - 10), linen.gain)         -- over the vendor's 10
        local wool = find(rows, "Player-1-Alice", "bank", 2592)
        assert.are.equal("oeRealm", wool.source)
        assert.are.equal(380, wool.unit)
        assert.are.same({}, env.__errors)
    end)

    it("shows buyer prices when the cut option is off", function()
        local _, ns = world(PRICES)
        ns.db.settings.value.ahCut = false
        local linen = find(open(ns, "Player-1-Alice"), "Player-1-Alice", "bags", 2589)
        assert.are.equal(120, linen.unit)
    end)

    it("compares only the sources the options tick, and one source when chosen", function()
        local env, ns = world(PRICES)
        local v = ns.db.settings.value
        v.auctionator = false
        local linen = find(open(ns, "Player-1-Alice"), "Player-1-Alice", "bags", 2589)
        assert.are.equal("oeRegion", linen.source)
        assert.are.equal(95, linen.unit)
        v.source = "tsm"
        ns.Browser:Refresh()
        linen = find(ns.ValueList.rows, "Player-1-Alice", "bags", 2589)
        assert.are.equal("tsm", linen.source)
        assert.are.equal(85, linen.unit)                       -- 90 - 5%
        assert.are.equal("first(DBMarket, DBRegionMarketAvg)", env.__tsmPriceString)
        v.source = "vendor"
        ns.Browser:Refresh()
        linen = find(ns.ValueList.rows, "Player-1-Alice", "bags", 2589)
        assert.are.equal(10, linen.unit)
        assert.are.equal(20 * (95 - 10), linen.gain)           -- against the best ticked AH source: OE region
    end)

    it("prices bound items at the vendor only and leaves out what has no price", function()
        local _, ns = world(PRICES)
        local rows = open(ns, ns.Browser.ALL_OWNER)
        local cloak = find(rows, "Player-1-Bob", "bags", 231000)
        assert.are.equal("vendor", cloak.source)               -- warbound until equipped: no AH
        assert.are.equal(5000, cloak.unit)
        assert.is_nil(cloak.gain)
        assert.is_nil(find(rows, "Player-1-Bob", "bags", 6948)) -- soulbound and unsellable
    end)

    it("counts bags, bank, mail and the warband bank of all characters, never worn gear, auctions or guilds", function()
        local _, ns = world(PRICES)
        assert.are.same({
            "#warband warband 190396",
            "Player-1-Alice bags 230000", "Player-1-Alice bags 2589",
            "Player-1-Alice bank 2592", "Player-1-Alice mail 2589",
            "Player-1-Bob bags 231000",
            "Player-1-Carol bags 2589",
        }, keys(open(ns, ns.Browser.ALL_OWNER)))
        local helm = find(ns.ValueList.rows, "Player-1-Alice", "bags", 230000)
        assert.is_nil(helm.bound)                              -- the free copy, not the worn one
    end)

    it("narrows to a realm, a character, the warband bank or one guild bank", function()
        local _, ns = world(PRICES)
        assert.are.same({ "Player-1-Carol bags 2589" }, keys(open(ns, "*realm:Proudmoore")))
        assert.are.same({ "Player-1-Bob bags 231000" }, keys(open(ns, "Player-1-Bob")))
        assert.are.same({ "#warband warband 190396" }, keys(open(ns, ns.WARBAND_OWNER)))
        assert.are.same({ "@Guild-Blackhand guild 2592" }, keys(open(ns, "@Guild-Blackhand")))
    end)

    it("hides equipment set items and shows them as a group of their own on request", function()
        local env, ns = world(PRICES)
        open(ns, "Player-1-Alice")
        local f = env.EllesmereUIBagsAltsBrowser
        assert.is_nil(find(ns.ValueList.rows, "Player-1-Alice", "bags", 190396))
        assert.truthy(f.footer.text:find("Hidden equipment set stacks: 1", 1, true))
        ns.db.settings.value.showSets = true
        ns.Browser:Refresh()
        local list = ns.ValueList.list
        local ore = list[#list]
        assert.are.equal(190396, ore.id)                        -- after the rest, though most valuable
        assert.are.equal("PvP", ore.sets)
        assert.are.equal("Equipment sets", list[#list - 1].header)
    end)

    it("counts a soulbound bank item as a set item when a set asks for it and it is the only one", function()
        local env, ns = world(PRICES)
        local alice = ns.GetPlayerChar()
        alice.bank[6] = container({ [1] = ns.EncodeItem(2592, 8), [2] = ns.EncodeItem(19019, 1, nil, "soul") })
        alice.setItemIDs = { [19019] = "Raid" }
        ns.Index:Invalidate()
        assert.is_nil(find(open(ns, "Player-1-Alice"), "Player-1-Alice", "bank", 19019))
        ns.db.settings.value.showSets = true
        ns.Browser:Refresh()
        assert.are.equal("Raid", find(ns.ValueList.rows, "Player-1-Alice", "bank", 19019).sets)
        -- a second copy anywhere: the set cannot tell which one it means
        alice.bags[1] = container({ [1] = ns.EncodeItem(19019, 1, nil, "soul") })
        ns.Index:Invalidate()
        ns.Browser:Refresh()
        assert.is_nil(find(ns.ValueList.rows, "Player-1-Alice", "bank", 19019).sets)
        assert.are.same({}, env.__errors)
    end)

    it("records which items the character's equipment sets ask for", function()
        local s = wow.defaultState()
        s.equipmentSets = { { id = 1, name = "Raid", items = {}, itemIDs = { [16] = 19019, [1] = 230000 } },
                            { id = 2, name = "PvP", items = {}, itemIDs = { [16] = 19019 } } }
        local _, ns = wow.boot(s)
        local ids = ns.GetPlayerChar().setItemIDs
        assert.are.equal("Raid", ids[230000])
        assert.truthy(ids[19019]:find("Raid", 1, true) and ids[19019]:find("PvP", 1, true))
        assert.is_nil(ids[1])                                   -- the ignored-slot marker
    end)

    it("sorts by every column and flips the direction on a second click", function()
        local env, ns = world(PRICES)
        local rows = open(ns, ns.Browser.ALL_OWNER)
        for i = 2, #rows do assert.is_true(rows[i - 1].value >= rows[i].value) end
        local heads = ns.ValueList.frame.heads
        for _, col in ipairs(ns.ValueList.COLUMNS) do
            heads[col.key]:RunScript("OnClick")
            assert.are.equal(col.key, ns.db.settings.value.sort)
            local first = ns.db.settings.value.sortDesc
            heads[col.key]:RunScript("OnClick")
            assert.are.equal(not first, ns.db.settings.value.sortDesc)
        end
        heads.char:RunScript("OnClick")
        if ns.db.settings.value.sortDesc then heads.char:RunScript("OnClick") end
        rows = ns.ValueList.rows
        for i = 2, #rows do assert.is_true(rows[i - 1].ownerText:lower() <= rows[i].ownerText:lower()) end
        heads.loc:RunScript("OnClick")
        if ns.db.settings.value.sortDesc then heads.loc:RunScript("OnClick") end
        assert.are.equal("bags", ns.ValueList.rows[1].loc)
        assert.are.equal("warband", ns.ValueList.rows[#ns.ValueList.rows].loc)
        assert.are.same({}, env.__errors)
    end)

    it("shows every source's price in the row tooltip", function()
        local env, ns = world(PRICES)
        open(ns, "Player-1-Alice")
        local row
        for _, r in ipairs(ns.ValueList.pool) do
            if r:IsShown() and r.data and r.data.id == 2589 and r.data.loc == "bags" then row = r end
        end
        assert.truthy(row)
        row:RunScript("OnEnter")
        local out = {}
        for _, l in ipairs(env.NotGameTooltipEllesmereUIBagsAlts.lines) do out[#out + 1] = table.concat(l, " | ") end
        local text = table.concat(out, "\n")
        assert.truthy(text:find("Oribos Exchange (region)", 1, true))
        assert.truthy(text:find("> Auctionator", 1, true))
        assert.truthy(text:find("seen 2 days ago", 1, true))
        assert.truthy(text:find("TradeSkillMaster", 1, true))
        assert.truthy(text:find("Total (20)", 1, true))
        assert.are.same({}, env.__errors)
    end)

    it("prefers Auctionator's scan over Oribos Exchange and TSM, which only estimate", function()
        local _, ns = world(PRICES)
        local ore = find(open(ns, ns.Browser.ALL_OWNER), "#warband", "warband", 190396)
        assert.are.equal("auctionator", ore.source)            -- 900, though TSM says 1200
        assert.are.equal(855, ore.unit)
        local wool = find(ns.ValueList.rows, "Player-1-Alice", "bank", 2592)
        assert.are.equal("oeRealm", wool.source)               -- not in the scans: highest estimate
        ns.db.settings.value.auctionator = false
        ns.Browser:Refresh()
        ore = find(ns.ValueList.rows, "#warband", "warband", 190396)
        assert.are.equal("tsm", ore.source)
    end)

    it("says when Auctionator has no scan yet or did not see the item, and leaves out missing addons", function()
        local env, ns = world(PRICES, { emptyScan = true })
        env.TSM_API = nil
        open(ns, "Player-1-Alice")
        local text = rowTooltip(env, ns, 2589, "bags")
        assert.truthy(text:find("no scan yet", 1, true))
        assert.falsy(text:find("TradeSkillMaster", 1, true))   -- not installed: not listed
        local env2, ns2 = world(PRICES)
        open(ns2, "Player-1-Alice")
        assert.truthy(rowTooltip(env2, ns2, 2592, "bank"):find("not in the scans", 1, true))
    end)

    it("reads a custom TSM price string, and none while it is empty", function()
        local env, ns = world(PRICES)
        local v = ns.db.settings.value
        v.tsmPrice, v.tsmCustom, v.source = "custom", "  DBRecent  ", "tsm"
        local linen = find(open(ns, "Player-1-Alice"), "Player-1-Alice", "bags", 2589)
        assert.are.equal("DBRecent", env.__tsmPriceString)
        assert.are.equal(85, linen.unit)
        v.tsmCustom = ""
        env.__tsmPriceString = nil
        ns.Browser:Refresh()
        assert.is_nil(find(ns.ValueList.rows, "Player-1-Alice", "bags", 2589))
        assert.is_nil(env.__tsmPriceString)
        v.source = "auto"
        ns.Browser:Refresh()
        assert.truthy(rowTooltip(env, ns, 2589, "bags"):find("no price string set", 1, true))
    end)

    it("offers the custom TSM field in the options only while it is chosen, and saves it", function()
        local env, ns = world(PRICES)
        ns.Options:Register()
        local button
        for _, init in ipairs(env.__settingsLayout.initializers) do
            if init.button == "Custom price string" then button = init end
        end
        assert.truthy(button)
        assert.is_false(button:ShouldShow())
        ns.db.settings.value.tsmPrice = "custom"
        assert.is_true(button:ShouldShow())
        button.click()
        local dialog = env.EllesmereUIBagsAltsTSMPrice
        assert.is_true(dialog:IsShown())
        dialog.input:SetText("DBRecent")
        dialog.save:RunScript("OnClick")
        assert.are.equal("DBRecent", ns.db.settings.value.tsmCustom)
        assert.is_false(dialog:IsShown())
        assert.are.same({}, env.__errors)
    end)

    it("filters the list with the search box instead of searching everything", function()
        local env, ns = world(PRICES)
        open(ns, ns.Browser.ALL_OWNER)
        ns.Browser:SetQuery("wool")
        local f = env.EllesmereUIBagsAltsBrowser
        assert.are.same({ "Player-1-Alice bank 2592" }, keys(ns.ValueList.rows))
        assert.is_true(ns.ValueList.frame:IsShown())
        assert.are.equal(0, f.results.used)                    -- no global search results
        local shown = 0
        for _, tab in ipairs(f.tabs) do if tab:IsShown() then shown = shown + 1 end end
        assert.are.equal(8, shown)
        ns.Browser:SetQuery("zzzz")
        assert.are.equal(0, #ns.ValueList.rows)
        assert.are.equal("Nothing found.", f.empty.text)
        ns.Browser:SetQuery("")
        ns.Browser:SelectTab("bags")
        ns.Browser:SetQuery("wool")
        assert.is_true(f.results.used > 0)                     -- other tabs: the global search
    end)

    it("the source menu keeps its entries above the click catcher after the browser was raised", function()
        local env, ns = world(PRICES)
        open(ns, "Player-1-Alice")
        ns.Browser:RaiseAboveSettings()
        ns.ValueList:SourceMenu()
        local menu = env.EllesmereUIBagsAltsMenu
        menu:Hide()
        -- The client carries a window's strata to its children: the browser
        -- lowered on hide leaves the catcher at HIGH, raised at DIALOG.
        menu.catcher:SetFrameStrata("HIGH")
        menu.catcher:SetFrameLevel(999)
        ns.Browser:Close()
        open(ns, "Player-1-Alice")
        ns.ValueList:SourceMenu()
        assert.are.equal("FULLSCREEN_DIALOG", menu.catcher.strata)
        for _, b in ipairs(menu.entries) do
            if b:IsShown() then assert.is_true(b:GetFrameLevel() > menu.catcher:GetFrameLevel()) end
        end
        menu.entries[3]:RunScript("OnClick")                  -- Oribos Exchange (realm)
        assert.are.equal("oeRealm", ns.db.settings.value.source)
    end)

    it("filters by EllesmereUI Bags' bind expressions per stack", function()
        local _, ns = world(PRICES)
        open(ns, ns.Browser.ALL_OWNER)
        ns.Browser:SetQuery("wue")
        assert.are.same({ "Player-1-Bob bags 231000" }, keys(ns.ValueList.rows))   -- recorded as warbound until equipped
        ns.Browser:SetQuery("boe")
        assert.are.same({ "Player-1-Alice bags 230000" }, keys(ns.ValueList.rows))
    end)

    it("keeps working when a price addon errors or is missing", function()
        local env, ns = world(PRICES, { oeThrows = true })
        env.TSM_API = nil
        local linen = find(open(ns, "Player-1-Alice"), "Player-1-Alice", "bags", 2589)
        assert.are.equal("auctionator", linen.source)
        env.Auctionator = nil
        ns.Browser:Refresh()
        linen = find(ns.ValueList.rows, "Player-1-Alice", "bags", 2589)
        assert.are.equal("vendor", linen.source)
        assert.are.same({}, env.__errors)
    end)

    it("waits for item data and renders again once it arrives", function()
        local env, ns = world(PRICES)
        env.__state.uncachedItems = { [2592] = true }
        open(ns, "@Guild-Blackhand")
        local m = ns.ValueList.rows[1]
        assert.are.equal("item:2592", m.name)                   -- priced by OE, name still loading
        assert.is_true(ns.ValueList.pending[2592])
        env.ProcessQueue()
        env.RunOnUpdates()
        assert.are.equal("Wool Cloth", ns.ValueList.rows[1].name)
    end)

    it("leaves the full content area to the other tabs", function()
        local env, ns = world(PRICES)
        open(ns, "Player-1-Alice")
        local f = env.EllesmereUIBagsAltsBrowser
        assert.is_true(ns.ValueList.frame:IsShown())
        ns.Browser:SelectTab("bags")
        assert.is_false(ns.ValueList.frame:IsShown())
        assert.is_true(f.grid.used > 0)
    end)
end)
