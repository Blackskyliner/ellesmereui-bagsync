local wow = require("wow")

local function openAH(env) env.FireEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 21) end
local function closeAH(env) env.FireEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 21) end

local function world(opts)
    local s = wow.defaultState({ ownedAuctionsFull = true })
    s.ownedAuctions = {
        wow.ownedAuction(101, 190396, 200, { seconds = 3600 }),                          -- commodity, no link
        wow.ownedAuction(102, 230000, 1, { link = wow.itemLink(230000, "item:230000::::::::80:66::13:1:10256"), band = 3 }),
        wow.ownedAuction(103, 2589, 20, { sold = true, seconds = 100 }),               -- sold: item is gone
        wow.ownedAuction(104, 0, 1, { species = 1387, link = "|cff0070dd|Hbattlepet:1387:25:3:1627:289:289:0|h[Pet]|h|r", seconds = 60 }),
    }
    for k, v in pairs(opts or {}) do s[k] = v end
    return wow.boot(s)
end

describe("Auction collector", function()
    it("is on by default but passive: no events or requests until the AH opens", function()
        local env, ns = world({ ownedAuctionsFull = false })
        local f = ns.featureByKey.auctions
        assert.is_true(f.active)
        assert.is_false(ns.IsEventRegistered(f, "OWNED_AUCTIONS_UPDATED"))
        openAH(env)
        assert.is_true(ns.IsEventRegistered(f, "OWNED_AUCTIONS_UPDATED"))
        assert.are.equal(0, env.__state.auctionQueries)     -- never queries on its own by default
        closeAH(env)
        assert.is_false(ns.IsEventRegistered(f, "OWNED_AUCTIONS_UPDATED"))
    end)

    it("stores active auctions when the client reports them (Auctions tab)", function()
        local env, ns = world()
        openAH(env)
        env.FireEvent("OWNED_AUCTIONS_UPDATED")
        local a = ns.GetPlayerChar().auctions
        assert.are.equal(3, #a.items)                          -- sold one excluded
        assert.are.equal("190396,200", a.items[1].e)
        assert.are.equal(env.__state.now + 3600, a.items[1].x)
        assert.truthy(a.items[2].e:find("10256", 1, true))     -- rich link kept
        assert.are.equal(env.__state.now + 48 * 3600, a.items[2].x)   -- band fallback (VeryLong)
        assert.truthy(a.items[3].e:find("^82800,1,|c"))         -- caged pet as Pet Cage + link
        assert.are.equal(env.__state.now, a.scannedAt)
        ns.Index:EnsureBuilt()
        assert.are.equal(200, ns.Index:Get(190396)["Alice-Blackhand"].auctions)
        assert.are.equal(0, ns.Index:GetTotal(2589))
    end)

    it("never stores partial owned-auction results", function()
        local env, ns = world({ ownedAuctionsFull = false })
        openAH(env)
        env.__state.ownedAuctionsFull = false
        env.FireEvent("OWNED_AUCTIONS_UPDATED")
        assert.are.equal(0, #ns.GetPlayerChar().auctions.items)
        env.__state.ownedAuctionsFull = true
        env.FireEvent("OWNED_AUCTIONS_UPDATED")
        assert.are.equal(3, #ns.GetPlayerChar().auctions.items)
        env.__state.ownedAuctions = { env.__state.ownedAuctions[1] }
        env.__state.ownedAuctionsFull = false
        env.FireEvent("OWNED_AUCTIONS_UPDATED")                 -- partial: last full list stays
        assert.are.equal(3, #ns.GetPlayerChar().auctions.items)
    end)

    it("reads results the client already has when the AH opens", function()
        local env, ns = world()
        openAH(env)
        assert.are.equal(3, #ns.GetPlayerChar().auctions.items)
    end)

    it("opt-in: requests owned auctions on open and after posting", function()
        local env, ns = world({ ownedAuctionsFull = false })
        ns.db.settings.collect.auctionsQuery = true
        openAH(env)
        assert.are.equal(1, env.__state.auctionQueries)
        env.ProcessQueue()
        assert.are.equal(3, #ns.GetPlayerChar().auctions.items)
        table.insert(env.__state.ownedAuctions, wow.ownedAuction(105, 6948, 1, { seconds = 7200 }))
        env.FireEvent("AUCTION_HOUSE_AUCTION_CREATED", 105)
        assert.are.equal(2, env.__state.auctionQueries)
        env.ProcessQueue()
        assert.are.equal(4, #ns.GetPlayerChar().auctions.items)
    end)

    it("moves cancelled and expired auctions into in-transit mail", function()
        local env, ns = world()
        openAH(env)
        env.FireEvent("OWNED_AUCTIONS_UPDATED")
        env.FireEvent("AUCTION_CANCELED", 101)
        env.FireEvent("AUCTION_HOUSE_AUCTIONS_EXPIRED", 102)
        local c = ns.GetPlayerChar()
        assert.are.equal(1, #c.auctions.items)
        assert.are.equal(2, #c.mailIncoming)
        assert.are.equal("190396,200", c.mailIncoming[1].e)
        ns.Index:EnsureBuilt()
        local byLoc = ns.Index:Get(190396)["Alice-Blackhand"]
        assert.are.equal(200, byLoc.mail)
        assert.is_nil(byLoc.auctions)
        local incremental = wow.deepCopy(ns.Index.data)
        ns.Index:Build()
        assert.are.same(ns.Index.data, incremental)
    end)

    it("drops expired auctions at login and keeps the rest across relogs", function()
        local env, ns = world()
        openAH(env)
        env.FireEvent("OWNED_AUCTIONS_UPDATED")
        local _ = ns
        local env2, ns2 = wow.relog(env, { name = "Bob" }, { now = 1790000000 + 2 * 3600 })
        local a = ns2.db.chars["Alice-Blackhand"].auctions.items
        assert.are.equal(1, #a)                                -- only the 48h one survives 2h
        assert.truthy(a[1].e:find("^230000,"))
        assert.are.same({}, env2.__errors)
    end)

    it("ignores secret auction data", function()
        local env, ns = world()
        env.__state.ownedAuctions = { wow.ownedAuction(201, wow.Secret(2589), 5, { seconds = 60 }) }
        openAH(env)
        env.FireEvent("OWNED_AUCTIONS_UPDATED")
        assert.are.equal(0, #ns.GetPlayerChar().auctions.items)
        assert.are.same({}, env.__errors)
    end)

    it("shows auctions in the tooltip and in the browser tab", function()
        local env, ns = world()
        openAH(env)
        env.FireEvent("OWNED_AUCTIONS_UPDATED")
        ns.db.settings.tooltip.enabled = true
        ns.SettingsChanged()
        env.GameTooltip:SetOwner(env.UIParent)
        env.GameTooltip:SetHyperlink("item:190396")
        local text = {}
        for _, l in ipairs(env.GameTooltip.lines) do text[#text + 1] = table.concat(l, " | ") end
        assert.truthy(table.concat(text, "\n"):find("Auctions: 200", 1, true))
        ns.Browser:Open()
        ns.Browser:SelectTab("auctions")
        local f = env.EllesmereUIBagsAltsBrowser
        assert.are.equal(3, f.grid.used)
        assert.truthy(f.footer.text:find("Auctions scanned", 1, true))
        ns.Browser:Select("Alice-Blackhand")
        env.__state.ownedAuctions = {}
        env.FireEvent("OWNED_AUCTIONS_UPDATED")
        env.RunOnUpdates()
        assert.truthy(f.empty.text:find("Auctions tab", 1, true))
    end)

    it("can be switched off", function()
        local env, ns = world()
        ns.db.settings.collect.auctions = false
        ns.SettingsChanged()
        openAH(env)
        env.FireEvent("OWNED_AUCTIONS_UPDATED")
        assert.are.equal(0, #ns.GetPlayerChar().auctions.items)
    end)
end)
