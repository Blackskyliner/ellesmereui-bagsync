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
        env.C_AuctionHouse.CancelAuction(101)
        env.ProcessQueue()                                     -- AUCTION_CANCELED, 1
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
        env.C_AuctionHouse.CancelAuction(101)
        table.remove(env.__state.ownedAuctions, 1)            -- auction 101 cancelled server-side
        env.FireEvent("OWNED_AUCTIONS_UPDATED")                -- list arrives before the cancel event
        env.FireEvent("AUCTION_CANCELED", 1)
        env.FireEvent("AUCTION_CANCELED", 1)                   -- stray duplicate event
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
            env.C_AuctionHouse.CancelAuction(9001)
            env.ProcessQueue()
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

    describe("cancelling (through C_AuctionHouse.CancelAuction like Blizzard's dialog)", function()
        -- The helm is posted; the owned list uses another ID than the created
        -- event (createdIDOffset) and never reports itself complete.
        local function cancelWorld(opts)
            local o = { ownedAuctionsFull = false, createdIDOffset = 50, ownedAuctions = {} }
            for k, v in pairs(opts or {}) do o[k] = v end
            local env, ns = world(o)
            wow.putItem(env.__state, 0, 1, 230000, 1, wow.itemLink(230000, "item:230000::::::::80:66::13:1:10256"))
            openAH(env)
            env.C_AuctionHouse.PostItem(wow.itemLocation(0, 1), 1, 1, nil, 1)
            env.ProcessQueue()
            env.FireEvent("OWNED_AUCTIONS_UPDATED")            -- Auctions tab: partial list
            return env, ns, 9051                               -- the ID Blizzard's cancel uses
        end

        local function assertHelmMailed(ns)
            local c = ns.GetPlayerChar()
            local inMail, inAuctions = 0, 0
            for _, m in ipairs(c.mailIncoming) do if m.e:find("^230000,") then inMail = inMail + 1 end end
            for _, a in ipairs(c.auctions.items) do if a.e:find("^230000,") then inAuctions = inAuctions + 1 end end
            assert.are.equal(1, inMail)
            assert.are.equal(0, inAuctions)
            ns.Index:EnsureBuilt()
            local incremental = wow.deepCopy(ns.Index.data)
            ns.Index:Build()
            assert.are.same(ns.Index.data, incremental)
            assert.are.equal(1, ns.Index:GetTotal(230000))     -- counted once
        end

        it("mails the posted auction although the cancel uses the owned-list ID (regression)", function()
            local env, ns, listID = cancelWorld()
            env.C_AuctionHouse.CancelAuction(listID)
            env.ProcessQueue()
            assertHelmMailed(ns)
        end)

        it("works with the live event argument (AUCTION_CANCELED, 1)", function()
            local env, ns, listID = cancelWorld({ cancelEvent = "one" })
            env.C_AuctionHouse.CancelAuction(listID)
            env.ProcessQueue()
            assertHelmMailed(ns)
        end)

        it("works when AUCTION_CANCELED carries no argument", function()
            local env, ns, listID = cancelWorld({ cancelEvent = "none" })
            env.C_AuctionHouse.CancelAuction(listID)
            env.ProcessQueue()
            assertHelmMailed(ns)
        end)

        it("works when AUCTION_CANCELED does carry the auction ID", function()
            local env, ns, listID = cancelWorld({ cancelEvent = "id" })
            env.C_AuctionHouse.CancelAuction(listID)
            env.ProcessQueue()
            assertHelmMailed(ns)
        end)

        it("confirms several quick cancels in request order", function()
            local env, ns = world()
            openAH(env)
            env.FireEvent("OWNED_AUCTIONS_UPDATED")
            env.C_AuctionHouse.CancelAuction(102)
            env.C_AuctionHouse.CancelAuction(101)
            env.ProcessQueue()
            local c = ns.GetPlayerChar()
            assert.are.equal(2, #c.mailIncoming)
            assert.truthy(c.mailIncoming[1].e:find("^230000,"))
            assert.are.equal("190396,200", c.mailIncoming[2].e)
            assert.are.equal(1, #c.auctions.items)
        end)

        it("ignores AUCTION_CANCELED without a preceding cancel request", function()
            local env, ns = world()
            openAH(env)
            env.FireEvent("OWNED_AUCTIONS_UPDATED")
            env.FireEvent("AUCTION_CANCELED", 1)
            assert.are.equal(0, #ns.GetPlayerChar().mailIncoming)
            assert.are.equal(3, #ns.GetPlayerChar().auctions.items)
        end)

        it("confirms a cancel by absence from the next complete list when no event comes", function()
            local env, ns, listID = cancelWorld({ cancelEvent = "missing", refreshAfterCancel = true })
            env.C_AuctionHouse.CancelAuction(listID)
            env.ProcessQueue()
            assertHelmMailed(ns)
        end)

        it("mails nothing if the cancel never happened (no event, still listed)", function()
            local env, ns, listID = cancelWorld({ cancelEvent = "missing" })
            env.C_AuctionHouse.CancelAuction(listID)
            -- server refused: auction stays; a complete list still contains it
            table.insert(env.__state.ownedAuctions, wow.ownedAuction(listID, 230000, 1, { seconds = 3600 }))
            env.ProcessQueue()
            env.__state.ownedAuctionsFull = true
            env.FireEvent("OWNED_AUCTIONS_UPDATED")
            assert.are.equal(0, #ns.GetPlayerChar().mailIncoming)
        end)

        it("mails a listed (not provisional) auction once", function()
            local env, ns = world()
            openAH(env)
            env.FireEvent("OWNED_AUCTIONS_UPDATED")
            env.__state.refreshAfterCancel = true
            env.C_AuctionHouse.CancelAuction(101)
            env.ProcessQueue()
            local c = ns.GetPlayerChar()
            assert.are.equal(1, #c.mailIncoming)
            assert.are.equal("190396,200", c.mailIncoming[1].e)
            assert.are.equal(2, #c.auctions.items)
        end)

        it("reads the owned list through the indexed API when the table API is empty", function()
            local env, ns = world({ ownedTableEmpty = true })
            openAH(env)
            env.FireEvent("OWNED_AUCTIONS_UPDATED")
            assert.are.equal(3, #ns.GetPlayerChar().auctions.items)
        end)

        it("explains itself with /alts debug", function()
            local env, ns, listID = cancelWorld({ cancelEvent = "one" })
            env.Slash("debug")
            assert.is_true(ns.db.settings.debug)
            env.C_AuctionHouse.CancelAuction(listID)
            env.ProcessQueue()
            local chat = table.concat(env.__chat, "\n")
            assert.truthy(chat:find("cancel requested 9051", 1, true))
            assert.truthy(chat:find("AUCTION_CANCELED 1 confirms requested 9051", 1, true))
            assert.truthy(chat:find("-> mail", 1, true))
            env.Slash("debug")
            local n = #env.__chat
            env.FireEvent("OWNED_AUCTIONS_UPDATED")
            assert.are.equal(n, #env.__chat)                   -- silent again
        end)
    end)

    describe("diff on the owned list (Auctions tab)", function()
        it("drops auctions that sold (gone, time left) and mails ones that expired", function()
            local env, ns = world()
            openAH(env)
            env.FireEvent("OWNED_AUCTIONS_UPDATED")            -- 101 ore (1h), 102 helm (48h), 104 pet (1min)
            env.__state.now = env.__state.now + 120            -- pet auction ran out, ore/helm still running
            env.__state.ownedAuctions = { env.__state.ownedAuctions[2] }   -- ore and pet gone
            env.FireEvent("OWNED_AUCTIONS_UPDATED")
            local c = ns.GetPlayerChar()
            assert.are.equal(1, #c.auctions.items)             -- helm left
            assert.are.equal(1, #c.mailIncoming)               -- expired pet came back
            assert.truthy(c.mailIncoming[1].e:find("^82800,"))
            assert.are.equal(1, #c.mailSold)                   -- ore sold: gold waits in the mailbox
            assert.are.equal("190396,200", c.mailSold[1].e)
            assert.are.equal(200 * 10000, c.mailSold[1].money) -- commodity: buyout is per unit
            ns.Index:EnsureBuilt()
            assert.are.equal(0, ns.Index:GetTotal(190396))     -- sold ore is no longer an item anywhere
        end)

        it("drops auctions the list reports as Sold even when the list is partial", function()
            local env, ns = world()
            openAH(env)
            env.FireEvent("OWNED_AUCTIONS_UPDATED")
            env.__state.ownedAuctionsFull = false
            env.__state.ownedAuctions[1].status = 1           -- ore now Sold
            env.FireEvent("OWNED_AUCTIONS_UPDATED")
            local items = ns.GetPlayerChar().auctions.items
            assert.are.equal(2, #items)
            for _, a in ipairs(items) do assert.is_nil(a.e:find("^190396,")) end
            assert.are.equal(0, #ns.GetPlayerChar().mailIncoming)
        end)

        it("a partial list never removes auctions that are merely missing from it", function()
            local env, ns = world()
            openAH(env)
            env.FireEvent("OWNED_AUCTIONS_UPDATED")
            env.__state.ownedAuctionsFull = false
            env.__state.ownedAuctions = { env.__state.ownedAuctions[1] }
            env.FireEvent("OWNED_AUCTIONS_UPDATED")
            assert.are.equal(3, #ns.GetPlayerChar().auctions.items)
        end)
    end)

    describe("sold auctions and value", function()
        local function notify(env, kind, text, id)
            env.FireEvent("AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION", kind, text, id)
        end

        it("a sale notification (anywhere) turns an item auction into sold mail with its price", function()
            local env, ns = world()
            openAH(env)
            env.FireEvent("OWNED_AUCTIONS_UPDATED")
            closeAH(env)                                       -- works without the AH open
            notify(env, 4, "Void-Touched Helm", 102)
            local c = ns.GetPlayerChar()
            assert.are.equal(2, #c.auctions.items)
            assert.are.equal(1, #c.mailSold)
            assert.truthy(c.mailSold[1].e:find("^230000,1,"))
            assert.are.equal(10000, c.mailSold[1].money)
            assert.are.equal(env.__state.now, c.mailSold[1].at)
            ns.Index:EnsureBuilt()
            assert.are.equal(0, ns.Index:GetTotal(230000))
        end)

        it("matches the notification by item name when the ID does not fit", function()
            local env, ns = world()
            openAH(env)
            env.FireEvent("OWNED_AUCTIONS_UPDATED")
            notify(env, 4, "Void-Touched Helm", 1)            -- like AUCTION_CANCELED's "1"
            assert.are.equal(1, #ns.GetPlayerChar().mailSold)
        end)

        it("leaves commodity sales to the list diff (quantity unknown), then records partial sales", function()
            local env, ns = world()
            openAH(env)
            env.FireEvent("OWNED_AUCTIONS_UPDATED")
            notify(env, 4, "Serevite Ore", 101)
            assert.are.equal(0, #ns.GetPlayerChar().mailSold)
            env.__state.ownedAuctions[1].quantity = 120        -- 80 of 200 units sold
            env.FireEvent("OWNED_AUCTIONS_UPDATED")
            local c = ns.GetPlayerChar()
            assert.are.equal(1, #c.mailSold)
            assert.are.equal("190396,80", c.mailSold[1].e)
            assert.are.equal(80 * 10000, c.mailSold[1].money)
            ns.Index:EnsureBuilt()
            assert.are.equal(120, ns.Index:Get(190396)["Alice-Blackhand"].auctions)
        end)

        it("an expiry notification moves the auction into in-transit mail", function()
            local env, ns = world()
            openAH(env)
            env.FireEvent("OWNED_AUCTIONS_UPDATED")
            notify(env, 5, "Void-Touched Helm", 102)
            local c = ns.GetPlayerChar()
            assert.are.equal(1, #c.mailIncoming)
            assert.are.equal(0, #c.mailSold)
        end)

        it("an auction listed as Sold is recorded with the list's price", function()
            local env, ns = world()
            openAH(env)
            env.FireEvent("OWNED_AUCTIONS_UPDATED")
            env.__state.ownedAuctionsFull = false
            env.__state.ownedAuctions[2].status = 1
            env.__state.ownedAuctions[2].buyoutAmount = 5000000
            env.FireEvent("OWNED_AUCTIONS_UPDATED")
            local sold = ns.GetPlayerChar().mailSold
            assert.are.equal(1, #sold)
            assert.are.equal(10000, sold[1].money)             -- the price stored when first listed wins
        end)

        it("keeps the exact posting price and sums what is on the auction house", function()
            local env, ns = world({ ownedAuctions = {} })
            wow.putItem(env.__state, 0, 1, 230000, 1, wow.itemLink(230000, "item:230000::::::::80:66::13:1:10256"))
            wow.putItem(env.__state, 0, 2, 2589, 200)
            openAH(env)
            env.C_AuctionHouse.PostItem(wow.itemLocation(0, 1), 3, 1, 100, 2500000)     -- 250g buyout
            env.C_AuctionHouse.PostCommodity(wow.itemLocation(0, 2), 1, 150, 1234)    -- 150 x 12s34c
            env.ProcessQueue()
            local c = ns.GetPlayerChar()
            assert.are.equal(2500000, c.auctions.items[1].u)
            assert.are.equal(1234, c.auctions.items[2].u)
            local value, count = ns.AuctionValue(c)
            assert.are.equal(2500000 + 150 * 1234, value)
            assert.are.equal(2, count)
            env.FireEvent("OWNED_AUCTIONS_UPDATED")             -- list keeps the posting prices
            assert.are.equal(2500000 + 150 * 1234, (ns.AuctionValue(c)))
        end)

        it("shows value in the auctions footer and sold gold in the mail tab", function()
            local env, ns = world()
            openAH(env)
            env.FireEvent("OWNED_AUCTIONS_UPDATED")
            notify(env, 4, "Void-Touched Helm", 102)
            ns.Browser:Open()
            ns.Browser:SelectTab("auctions")
            local f = env.EllesmereUIBagsAltsBrowser
            assert.truthy(f.footer.text:find("On the auction house", 1, true))
            assert.truthy(f.footer.text:find("(2)", 1, true))
            ns.Browser:SelectTab("mail")
            assert.truthy(f.footer.text:find("Gold in mail: 1|cffffd700g|r", 1, true))
            assert.are.equal(1, f.results.used)
            assert.truthy(f.results.items[1].name.text:find("Void-Touched Helm", 1, true))
            assert.truthy(f.results.items[1].total.text:find("1|cffffd700g|r", 1, true))
        end)

        it("opening the mailbox clears sold entries; they also expire after 30 days", function()
            local env, ns = world()
            openAH(env)
            env.FireEvent("OWNED_AUCTIONS_UPDATED")
            notify(env, 4, "Void-Touched Helm", 102)
            local env2, ns2 = wow.relog(env, { name = "Alice" }, { now = 1790000000 + 31 * 86400 })
            assert.are.equal(0, #ns2.GetPlayerChar().mailSold)
            local _ = { ns, env2 }
            local env3, ns3 = world()
            openAH(env3)
            env3.FireEvent("OWNED_AUCTIONS_UPDATED")
            notify(env3, 4, "Void-Touched Helm", 102)
            env3.FireEvent("MAIL_SHOW")
            assert.are.equal(0, #ns3.GetPlayerChar().mailSold)
        end)

        it("formats money with gold, silver and copper", function()
            local _, ns = world()
            assert.are.equal("12|cffffd700g|r 34|cffc7c7cfs|r", ns.W.FormatMoney(123456))
            assert.are.equal("34|cffc7c7cfs|r 56|cffeda55fc|r", ns.W.FormatMoney(3456))
            assert.are.equal("0|cffeda55fc|r", ns.W.FormatMoney(0))
        end)
    end)
end)
