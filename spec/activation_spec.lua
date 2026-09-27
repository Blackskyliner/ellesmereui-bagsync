-- Activation on first use: nothing is scanned or registered at login beyond
-- the activation triggers; the first use starts the collectors exactly once.
local wow = require("wow")
local fakeEUI = require("fake_eui")

local LAZY = { "character", "bags", "equipped", "bank", "mail", "auctions", "currency", "guildbank" }

-- Counts calls of the scanning APIs.
local function countCalls(env)
    local calls = { container = 0, inventory = 0, currency = 0, money = 0 }
    local ci = env.C_Container.GetContainerItemInfo
    env.C_Container.GetContainerItemInfo = function(...) calls.container = calls.container + 1 return ci(...) end
    local inv = env.GetInventoryItemLink
    env.GetInventoryItemLink = function(...) calls.inventory = calls.inventory + 1 return inv(...) end
    local cur = env.C_CurrencyInfo.GetCurrencyListSize
    env.C_CurrencyInfo.GetCurrencyListSize = function(...) calls.currency = calls.currency + 1 return cur(...) end
    local money = env.GetMoney
    env.GetMoney = function(...) calls.money = calls.money + 1 return money(...) end
    return calls
end

local function world()
    local s = wow.defaultState({ currencies = { { id = 3008, name = "Valorstones", quantity = 10 } } })
    wow.putItem(s, 0, 1, 2589, 20)
    s.equipped[16] = { id = 19019, link = wow.itemLink(19019) }
    return s
end

-- Boots (with EllesmereUI, the supported setup) without using the addon;
-- the counters see everything from login on. extra.noEUI: EUI missing.
local function bootUnused(state, sv, extra)
    local calls
    local opts = { inactive = true, beforeLoad = function(env)
        calls = countCalls(env)
        if not (extra and extra.noEUI) then fakeEUI.install(env) end
    end }
    local env, ns = wow.boot(state or world(), sv, opts)
    return env, ns, calls
end

describe("Activation", function()
    it("an unused addon registers only the activation trigger and scans nothing", function()
        local env, ns, calls = bootUnused()
        assert.is_false(ns.IsActivated())
        assert.are.same({ "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" }, ns.GetRegisteredEvents())
        for _, key in ipairs(LAZY) do assert.is_false(ns.featureByKey[key].active, key) end
        assert.are.same({ container = 0, inventory = 0, currency = 0, money = 0 }, calls)
        assert.is_nil(next(ns.db.chars))                      -- no record created either
        assert.are.same({}, env.__errors)
    end)

    it("does not walk the stored data at login", function()
        local sv = { schema = 1, chars = { ["Bob-Blackhand"] = { bags = { [0] = { size = "x", items = { [1] = 5 } } } } } }
        local _, ns = bootUnused(nil, sv)
        assert.are.equal("x", ns.db.chars["Bob-Blackhand"].bags[0].size)  -- untouched until activation
    end)

    it("the first bag open activates: one scan, then event driven, never again", function()
        local env, ns, calls = bootUnused()
        local fired = 0
        ns.On("ACTIVATED", fired, function() fired = fired + 1 end)
        env.OpenBags()
        assert.is_true(ns.IsActivated())
        assert.are.equal("bags", ns.activatedBy)
        assert.are.equal(1, fired)
        assert.are.equal("2589,20", ns.GetPlayerChar().bags[0].items[1])
        assert.is_table(ns.GetPlayerChar().equipped.items[16] and ns.GetPlayerChar().equipped)
        assert.are.equal(1, calls.currency)
        assert.is_true(ns.IsEventRegistered(ns.featureByKey.bags, "BAG_UPDATE"))
        -- the trigger is gone; later opens, NPC visits and browser opens activate nothing again
        env.CloseBags()
        env.OpenBags()
        env.FireEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 8)
        env.FireEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 8)
        ns.Browser:Open()
        assert.are.equal(1, fired)
        assert.are.equal("bags", ns.activatedBy)
        assert.are.equal(1, calls.currency)                   -- no second full scan
        assert.are.same({}, env.__errors)
    end)

    it("the stored data is checked on activation", function()
        local sv = { schema = 1, chars = { ["Bob-Blackhand"] = { bags = { [0] = { size = "x", items = { [1] = 5 } } } } } }
        local env, ns = bootUnused(nil, sv)
        env.OpenBags()
        assert.are_not.equal("x", ns.db.chars["Bob-Blackhand"].bags[0] and ns.db.chars["Bob-Blackhand"].bags[0].size)
    end)

    it("never hooks Blizzard's bag frames or bag functions", function()
        local env, ns = bootUnused(nil, nil, { noEUI = true })
        env.ToggleAllBags()                                    -- Blizzard's own bag window
        assert.is_false(ns.IsActivated())                      -- EUI Bags is the supported bag UI
        assert.is_nil(env.ContainerFrameCombinedBags.hooks.OnShow)
        for i = 1, env.NUM_CONTAINER_FRAMES do assert.is_nil(env["ContainerFrame" .. i].hooks.OnShow) end
        ns.Browser:Open()                                      -- still usable through the browser
        assert.are.equal("browser", ns.activatedBy)
    end)

    it("the browser, the public API and the self-test activate", function()
        local _, ns = bootUnused()
        ns.Browser:Open()
        assert.are.equal("browser", ns.activatedBy)
        local env2, ns2 = bootUnused()
        assert.are.equal(20, (env2.EllesmereUIBagsAlts.GetItemCount(2589)))  -- current character counted
        assert.are.equal("api", ns2.activatedBy)
        local _, ns3 = bootUnused()
        ns3.RunSelfTest(false)
        assert.are.equal("selftest", ns3.activatedBy)
    end)

    it("with the tooltip option on, the first item tooltip activates and counts the current character", function()
        local sv = { schema = 1, settings = { tooltip = { enabled = true } } }
        local env, ns = bootUnused(nil, sv)
        assert.is_true(ns.featureByKey.tooltip.active)        -- eager: its hook is the trigger
        assert.is_false(ns.IsActivated())
        assert.are.same({ "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" }, ns.GetRegisteredEvents())
        env.GameTooltip:SetOwner(env.UIParent)
        env.GameTooltip:SetHyperlink("item:2589")
        assert.are.equal("tooltip", ns.activatedBy)
        local text = {}
        for _, l in ipairs(env.GameTooltip.lines) do text[#text + 1] = table.concat(l, " | ") end
        assert.truthy(table.concat(text, "\n"):find("Bags: 20", 1, true))
    end)

    describe("an NPC window activates and is captured in the same visit", function()
        it("bank", function()
            local s = world()
            s.bankTabs[0] = { { ID = 6, name = "Gear" } }
            s.bags[6] = { size = 98, slots = {} }
            wow.putItem(s, 6, 1, 2592, 80)
            local env, ns = bootUnused(s)
            env.FireEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 8)
            assert.are.equal("bank", ns.activatedBy)
            assert.are.equal("2592,80", ns.GetPlayerChar().bank[6].items[1])
            env.FireEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 8)
            assert.are.same({}, env.__errors)
        end)

        for _, order in ipairs({ "interaction first", "MAIL_SHOW first" }) do
            it("mailbox (" .. order .. ")", function()
                local s = world()
                s.inbox = { { sender = "Alice", daysLeft = 30, items = { { id = 190396, count = 200 } } } }
                local env, ns = bootUnused(s)
                if order == "MAIL_SHOW first" then env.FireEvent("MAIL_SHOW") end
                assert.is_false(ns.IsActivated())             -- MAIL_SHOW alone is no trigger
                env.FireEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 17)
                if order == "interaction first" then env.FireEvent("MAIL_SHOW") end
                assert.are.equal("mail", ns.activatedBy)
                local mail = ns.GetPlayerChar().mail.items
                assert.are.equal(1, #mail)
                assert.are.equal("190396,200", mail[1].e)
                assert.are.same({}, env.__errors)
            end)
        end

        it("guild bank (option on)", function()
            local s = world()
            s.guild = { name = "Knights", money = 5, tabs = { { name = "Mats", slots = { [1] = { id = 2589, count = 100 } } } } }
            local sv = { schema = 1, settings = { collect = { guildbank = true } } }
            local env, ns = bootUnused(s, sv)
            assert.is_false(ns.featureByKey.guildbank.active)   -- lazy even when switched on
            env.FireEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 10)
            env.ProcessQueue()
            assert.are.equal("guildbank", ns.activatedBy)
            assert.are.equal("2589,100", ns.db.guilds["Knights-Blackhand"].tabs[1].items[1])
        end)

        it("other interactions (a vendor) do not activate", function()
            local env, ns = bootUnused()
            env.FireEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 5)
            assert.is_false(ns.IsActivated())
        end)
    end)

    it("switching a collector on before activation starts nothing", function()
        local env, ns, calls = bootUnused()
        ns.db.settings.collect.guildbank = true
        ns.SettingsChanged()
        assert.is_false(ns.featureByKey.guildbank.active)
        assert.are.same({ "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" }, ns.GetRegisteredEvents())
        assert.are.equal(0, calls.container)
        local _ = env
    end)

    it("an unused session leaves the stored data alone at logout", function()
        local env = wow.boot(world())                          -- used session: Alice stored
        local seen = env.EllesmereUIBagsAltsDB.chars["Alice-Blackhand"].lastSeen
        local sv = wow.logout(env)
        sv.chars["Alice-Blackhand"].lastSeen = seen - 5000
        local env2, ns2 = bootUnused(world(), sv)
        local sv2 = wow.logout(env2)
        assert.are.equal(seen - 5000, sv2.chars["Alice-Blackhand"].lastSeen)
        assert.is_false(ns2.IsActivated())
    end)

    it("after activation, loading screens do not rescan", function()
        local env, ns, calls = bootUnused()
        env.OpenBags()
        local c, i = calls.container, calls.inventory
        env.FireEvent("PLAYER_ENTERING_WORLD", false, false)   -- instance portal
        assert.are.equal(c, calls.container)
        assert.are.equal(i, calls.inventory)
        -- a swapped bag still rescans (slot count changes without item events)
        env.__state.bags[1] = { size = 30, slots = {} }
        env.FireEvent("BAG_CONTAINER_UPDATE")
        assert.are.equal(30, ns.GetPlayerChar().bags[1].size)
    end)
end)
