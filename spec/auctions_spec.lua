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

    it("moves auctions that expired while offline into in-transit mail at login", function()
        local env, ns = world()
        openAH(env)
        env.FireEvent("OWNED_AUCTIONS_UPDATED")
        local _ = ns
        local env2, ns2 = wow.relog(env, { name = "Bob" }, { now = 1790000000 + 2 * 3600 })
        local alice = ns2.db.chars["Alice-Blackhand"]
        assert.are.equal(1, #alice.auctions.items)             -- only the 48h one survives 2h
        assert.truthy(alice.auctions.items[1].e:find("^230000,"))
        assert.are.equal(2, #alice.mailIncoming)               -- ore (1h) and the pet (1min) came back
        ns2.Index:EnsureBuilt()
        local byLoc = ns2.Index:Get(190396)["Alice-Blackhand"]
        assert.are.equal(200, byLoc.mail)
        assert.is_nil(byLoc.auctions)
        assert.are.same({}, env2.__errors)
    end)

    it("mails a cancelled auction even if a fresh list dropped it first, and only once", function()
        local env, ns = world()
        openAH(env)
        env.FireEvent("OWNED_AUCTIONS_UPDATED")
        table.remove(env.__state.ownedAuctions, 1)            -- auction 101 cancelled server-side
        env.FireEvent("OWNED_AUCTIONS_UPDATED")                -- list arrives before the cancel event
        env.FireEvent("AUCTION_CANCELED", 101)
        env.FireEvent("AUCTION_CANCELED", 101)                 -- duplicate event
        local c = ns.GetPlayerChar()
        assert.are.equal(1, #c.mailIncoming)
        assert.are.equal("190396,200", c.mailIncoming[1].e)
        ns.Index:EnsureBuilt()
        assert.are.equal(200, ns.Index:GetTotal(190396))       -- counted once, in mail
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

    describe("posting", function()
        local function postWorld(opts)
            local env, ns = world(opts)
            wow.putItem(env.__state, 0, 1, 230000, 1, wow.itemLink(230000, "item:230000::::::::80:66::13:1:10256"))
            wow.putItem(env.__state, 0, 2, 2589, 200)
            openAH(env)
            env.FireEvent("OWNED_AUCTIONS_UPDATED")            -- 3 known auctions
            return env, ns
        end

        it("appends a posted item immediately with its auction ID and duration", function()
            local env, ns = postWorld()
            env.C_AuctionHouse.PostItem(wow.itemLocation(0, 1), 2, 1, nil, 5000000)
            env.ProcessQueue()
            local items = ns.GetPlayerChar().auctions.items
            assert.are.equal(4, #items)
            local last = items[4]
            assert.truthy(last.e:find("10256", 1, true))
            assert.are.equal(9001, last.id)
            assert.are.equal(env.__state.now + 24 * 3600, last.x)
            ns.Index:EnsureBuilt()
            assert.are.equal(2, ns.Index:Get(230000)["Alice-Blackhand"].auctions)   -- listed helm + new one
        end)

        it("appends a posted commodity with its quantity", function()
            local env, ns = postWorld()
            env.C_AuctionHouse.PostCommodity(wow.itemLocation(0, 2), 1, 150, 99)
            env.ProcessQueue()
            local last = ns.GetPlayerChar().auctions.items[4]
            assert.are.equal("2589,150", last.e)
            assert.are.equal(env.__state.now + 12 * 3600, last.x)
            ns.Index:EnsureBuilt()
            local byLoc = ns.Index:Get(2589)["Alice-Blackhand"]
            assert.are.equal(150, byLoc.auctions)
            assert.are.equal(50, byLoc.bags)                   -- bag scan after BAG_UPDATE
        end)

        it("waits for confirmation and does not record a cancelled confirmation", function()
            local env, ns = postWorld({ postNeedsConfirm = true })
            env.C_AuctionHouse.PostItem(wow.itemLocation(0, 1), 3, 1, nil, 1)   -- dialog, user cancels
            env.ProcessQueue()
            assert.are.equal(3, #ns.GetPlayerChar().auctions.items)
            env.C_AuctionHouse.PostCommodity(wow.itemLocation(0, 2), 1, 20, 5)  -- new post: dialog again
            env.ProcessQueue()
            env.C_AuctionHouse.ConfirmPostCommodity(wow.itemLocation(0, 2), 1, 20, 5)
            env.ProcessQueue()
            local items = ns.GetPlayerChar().auctions.items
            assert.are.equal(4, #items)
            assert.are.equal("2589,20", items[4].e)            -- not the cancelled helm
        end)

        it("handles a confirmation warning that arrives before the post-hook", function()
            local env, ns = postWorld({ postNeedsConfirm = true, postWarningSync = true })
            env.C_AuctionHouse.PostItem(wow.itemLocation(0, 1), 3, 1, nil, 1)
            env.C_AuctionHouse.ConfirmPostItem(wow.itemLocation(0, 1), 3, 1, nil, 1)
            env.ProcessQueue()
            local items = ns.GetPlayerChar().auctions.items
            assert.are.equal(4, #items)
            assert.are.equal(env.__state.now + 48 * 3600, items[4].x)
        end)

        it("records one auction per multisell repetition", function()
            local env, ns = postWorld({ multisell = 4 })
            env.C_AuctionHouse.PostItem(wow.itemLocation(0, 2), 1, 20, nil, 1)
            env.ProcessQueue()
            local items = ns.GetPlayerChar().auctions.items
            assert.are.equal(7, #items)
            for i = 4, 7 do assert.are.equal("2589,5", items[i].e) end
        end)

        it("a posted auction that is cancelled goes to the mail", function()
            local env, ns = postWorld()
            env.C_AuctionHouse.PostItem(wow.itemLocation(0, 1), 1, 1, nil, 1)
            env.ProcessQueue()
            env.FireEvent("AUCTION_CANCELED", 9001)
            local c = ns.GetPlayerChar()
            assert.are.equal(3, #c.auctions.items)
            assert.truthy(c.mailIncoming[1].e:find("10256", 1, true))
        end)

        it("the next complete list replaces the provisional entries", function()
            local env, ns = postWorld()
            env.C_AuctionHouse.PostCommodity(wow.itemLocation(0, 2), 1, 150, 99)
            env.ProcessQueue()
            env.FireEvent("OWNED_AUCTIONS_UPDATED")
            local items = ns.GetPlayerChar().auctions.items
            assert.are.equal(4, #items)                        -- same auction, not duplicated
            ns.Index:EnsureBuilt()
            local incremental = wow.deepCopy(ns.Index.data)
            ns.Index:Build()
            assert.are.same(ns.Index.data, incremental)
        end)

        it("ignores posts while the feature is off or the AH is closed", function()
            local env, ns = postWorld()
            closeAH(env)
            env.C_AuctionHouse.PostItem(wow.itemLocation(0, 1), 1, 1, nil, 1)
            env.ProcessQueue()
            assert.are.equal(3, #ns.GetPlayerChar().auctions.items)
            assert.are.same({}, env.__errors)
        end)
    end)
end)
