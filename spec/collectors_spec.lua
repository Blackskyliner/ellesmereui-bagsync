local wow = require("wow")

local function countCalls(env, ns_name, fn_name)
    local tbl = env[ns_name]
    local orig = tbl[fn_name]
    local counter = { n = 0, args = {} }
    tbl[fn_name] = function(...)
        counter.n = counter.n + 1
        counter.args[#counter.args + 1] = { ... }
        return orig(...)
    end
    return counter
end

describe("Bags collector", function()
    local env, ns, S
    before_each(function()
        local state = wow.defaultState()
        wow.putItem(state, 0, 1, 6948, 1)
        wow.putItem(state, 1, 3, 2589, 17)
        env, ns = wow.boot(state)
        S = env.__state
    end)

    it("scans all inventory bags at login", function()
        local c = ns.GetPlayerChar()
        assert.are.equal(20, c.bags[0].size)
        assert.are.equal("2589,17", c.bags[1].items[3])
        for bag = 0, 5 do assert.is_table(c.bags[bag]) end
    end)

    it("rescans only dirty bags, once per BAG_UPDATE_DELAYED burst", function()
        local calls = countCalls(env, "C_Container", "GetContainerNumSlots")
        wow.putItem(S, 1, 4, 2592, 2)
        for _ = 1, 25 do env.FireEvent("BAG_UPDATE", 1) end
        assert.are.equal(0, calls.n)             -- BAG_UPDATE only marks
        env.FireEvent("BAG_UPDATE_DELAYED")
        assert.are.equal(1, calls.n)             -- one bag, one scan
        assert.are.equal(1, calls.args[1][1])
        assert.are.equal("2592,2", ns.GetPlayerChar().bags[1].items[4])
        env.FireEvent("BAG_UPDATE_DELAYED")
        assert.are.equal(1, calls.n)             -- nothing dirty, nothing scanned
    end)

    it("ignores bank and unknown container IDs", function()
        local calls = countCalls(env, "C_Container", "GetContainerNumSlots")
        env.FireEvent("BAG_UPDATE", 7)
        env.FireEvent("BAG_UPDATE", -2)
        env.FireEvent("BAG_UPDATE_DELAYED")
        assert.are.equal(0, calls.n)
    end)

    it("defers while container data is secret and rescans after combat", function()
        S.secret = true
        S.inCombat = true
        wow.putItem(S, 0, 2, 2592, 9)
        env.FireEvent("BAG_UPDATE", 0)
        env.FireEvent("BAG_UPDATE_DELAYED")
        assert.is_nil(ns.GetPlayerChar().bags[0].items[2])
        assert.are.same({}, env.__errors)           -- no comparisons on secrets
        S.secret = false
        S.inCombat = false
        env.FireEvent("PLAYER_REGEN_ENABLED")
        assert.are.equal("2592,9", ns.GetPlayerChar().bags[0].items[2])
        assert.is_false(ns.IsEventRegistered(ns.featureByKey.bags, "PLAYER_REGEN_ENABLED"))
    end)

    it("tracks bag size changes on world entry", function()
        S.bags[2].size = 30
        env.FireEvent("PLAYER_ENTERING_WORLD", false, true)
        assert.are.equal(30, ns.GetPlayerChar().bags[2].size)
    end)

    it("stops listening when disabled and keeps the stored data", function()
        ns.db.settings.collect.bags = false
        ns.SettingsChanged()
        assert.is_false(ns.IsEventRegistered(ns.featureByKey.bags, "BAG_UPDATE"))
        wow.putItem(S, 0, 5, 2592, 1)
        env.FireEvent("BAG_UPDATE", 0)
        env.FireEvent("BAG_UPDATE_DELAYED")
        assert.is_nil(ns.GetPlayerChar().bags[0].items[5])
        assert.are.equal("6948,1", ns.GetPlayerChar().bags[0].items[1])
    end)
end)

describe("Bank collector", function()
    local env, ns, S
    before_each(function()
        local state = wow.defaultState()
        state.bankTabs[0] = { { ID = 6, name = "Gear", icon = 1 }, { ID = 7, name = "", icon = 2 } }
        state.bankTabs[2] = { { ID = 12, name = "Mats", icon = 3 } }
        state.bags[6] = { size = 98, slots = {} }
        state.bags[7] = { size = 98, slots = {} }
        state.bags[12] = { size = 98, slots = {} }
        wow.putItem(state, 6, 1, 230000, 1, wow.itemLink(230000, "item:230000::::::::80:66::13:1:10256"))
        wow.putItem(state, 7, 10, 2589, 200)
        wow.putItem(state, 12, 5, 190396, 1000)
        env, ns = wow.boot(state)
        S = env.__state
    end)

    local function openBank(kind)
        env.FireEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", kind or 8)
    end
    local function closeBank(kind)
        env.FireEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", kind or 8)
    end

    it("reads nothing and listens only to open/close while no banker is open", function()
        local f = ns.featureByKey.bank
        assert.is_true(ns.IsEventRegistered(f, "PLAYER_INTERACTION_MANAGER_FRAME_SHOW"))
        assert.is_false(ns.IsEventRegistered(f, "BAG_UPDATE"))
        assert.are.same({}, ns.GetPlayerChar().bank)
        assert.is_nil(next(ns.db.warband.bank))
    end)

    it("scans character and warband tabs when a banker opens", function()
        openBank()
        local c = ns.GetPlayerChar()
        assert.are.equal("Gear", c.bank[6].name)
        assert.truthy(c.bank[6].items[1]:find("item:230000", 1, true))
        assert.are.equal("2589,200", c.bank[7].items[10])
        assert.are.equal("190396,1000", ns.db.warband.bank[12].items[5])
        assert.are.equal("Mats", ns.db.warband.bank[12].name)
        assert.are.equal(S.now, c.bankAt)
        assert.are.equal(S.warbandMoney, ns.db.warband.money)
    end)

    it("follows item moves while open and stops after close", function()
        openBank()
        local f = ns.featureByKey.bank
        assert.is_true(ns.IsEventRegistered(f, "BAG_UPDATE"))
        S.bags[7].slots[10] = nil
        wow.putItem(S, 12, 6, 2589, 200)
        env.FireEvent("BAG_UPDATE", 7)
        env.FireEvent("BAG_UPDATE", 12)
        env.FireEvent("BAG_UPDATE_DELAYED")
        assert.is_nil(ns.GetPlayerChar().bank[7].items[10])
        assert.are.equal("2589,200", ns.db.warband.bank[12].items[6])
        closeBank()
        assert.is_false(ns.IsEventRegistered(f, "BAG_UPDATE"))
        assert.is_false(ns.IsEventRegistered(f, "ACCOUNT_MONEY"))
    end)

    it("handles the account-banker-only interaction and view permissions", function()
        S.canViewBank[0] = false
        openBank(68)
        assert.are.same({}, ns.GetPlayerChar().bank)
        assert.are.equal("190396,1000", ns.db.warband.bank[12].items[5])
    end)

    it("keeps warband money in sync while the bank is open", function()
        openBank()
        S.warbandMoney = 42
        env.FireEvent("ACCOUNT_MONEY")
        assert.are.equal(42, ns.db.warband.money)
    end)

    it("shares the warband bank between characters after a relog", function()
        openBank()
        closeBank()
        local env2, ns2 = wow.relog(env, { name = "Bob", class = "WARRIOR" })
        assert.are.equal("190396,1000", ns2.db.warband.bank[12].items[5])
        assert.are.equal("2589,200", ns2.db.chars["Alice-Blackhand"].bank[7].items[10])
        assert.are.same({}, env2.__errors)
    end)
end)

describe("Mail collector", function()
    local env, ns, S
    before_each(function()
        local state = wow.defaultState()
        state.inbox = {
            { sender = "Auction House", daysLeft = 2.5, items = { { id = 2589, count = 20 }, { id = 2592, count = 5 } } },
            { sender = "Friend", daysLeft = 29, items = { { id = 1792, count = 1, isCurrency = true } } },
        }
        env, ns = wow.boot(state)
        S = env.__state
    end)

    it("scans the inbox at the mailbox with expiry, skipping currency attachments", function()
        env.FireEvent("MAIL_SHOW")
        local mail = ns.GetPlayerChar().mail
        assert.are.equal(2, #mail.items)
        assert.are.equal("2589,20", mail.items[1].e)
        assert.are.equal(S.now + math.floor(2.5 * 86400), mail.items[1].x)
        assert.are.equal("Auction House", mail.items[1].from)
    end)

    it("registers inbox events only while the mailbox is open", function()
        local f = ns.featureByKey.mail
        assert.is_false(ns.IsEventRegistered(f, "MAIL_INBOX_UPDATE"))
        env.FireEvent("MAIL_SHOW")
        assert.is_true(ns.IsEventRegistered(f, "MAIL_INBOX_UPDATE"))
        env.FireEvent("MAIL_CLOSED")
        assert.is_false(ns.IsEventRegistered(f, "MAIL_INBOX_UPDATE"))
    end)

    it("tracks mail sent to an own character until that character reads it", function()
        -- Bob exists (logged in once before)
        local env2, ns2 = wow.relog(env, { name = "Bob" })
        local env3, ns3 = wow.relog(env2, { name = "Alice" })
        env3.__state.sendItems = { { id = 190396, count = 200 }, { id = 2589, count = 1 } }
        env3.FireEvent("MAIL_SHOW")
        env3.SendMail("bob", "mats", "")
        env3.FireEvent("MAIL_SEND_SUCCESS")
        local incoming = ns3.db.chars["Bob-Blackhand"].mailIncoming
        assert.are.equal(2, #incoming)
        assert.are.equal("190396,200", incoming[1].e)
        assert.are.equal("Alice-Blackhand", incoming[1].from)
        ns3.Index:EnsureBuilt()
        assert.are.equal(200, ns3.Index:GetTotal(190396))

        -- Bob logs in and opens the mailbox: inbox replaces "in transit"
        local env4, ns4 = wow.relog(env3, { name = "Bob" }, {
            inbox = { { sender = "Alice", daysLeft = 30, items = { { id = 190396, count = 200 }, { id = 2589, count = 1 } } } },
        })
        env4.FireEvent("MAIL_SHOW")
        local bob = ns4.GetPlayerChar()
        assert.are.equal(0, #bob.mailIncoming)
        assert.are.equal(2, #bob.mail.items)
        assert.are.equal(200, ns4.Index:GetTotal(190396))
        assert.are.same({}, env4.__errors)
        local _ = ns2
    end)

    it("ignores mail to strangers and failed sends", function()
        env.__state.sendItems = { { id = 2589, count = 1 } }
        env.FireEvent("MAIL_SHOW")
        env.SendMail("Stranger-OtherRealm", "", "")
        env.FireEvent("MAIL_SEND_SUCCESS")
        for key, c in pairs(ns.db.chars) do assert.are.equal(0, #c.mailIncoming, key) end
    end)

    it("drops expired mail at login", function()
        env.FireEvent("MAIL_SHOW")
        local env2, ns2 = wow.relog(env, { name = "Alice" }, { now = 1790000000 + 3 * 86400 })
        local mail = ns2.GetPlayerChar().mail.items
        assert.are.equal(0, #mail)   -- both AH stacks expired after 2.5 days
        assert.are.same({}, env2.__errors)
    end)
end)

describe("Character, equipment and currency", function()
    it("stores meta, money, gear and currencies", function()
        local state = wow.defaultState()
        state.equipped[1] = { id = 230000, link = wow.itemLink(230000, "item:230000::::::::80:66::13:1:10256") }
        state.equipped[16] = { id = 19019, link = wow.itemLink(19019) }
        state.currencies = {
            { name = "Dungeon and Raid", header = true },
            { id = 3008, name = "Valorstones", quantity = 1234, icon = 1 },
            { name = "Old", id = 0, quantity = 0 },
        }
        local env, ns = wow.boot(state)
        local c = ns.GetPlayerChar()
        assert.are.equal("MAGE", c.class)
        assert.are.equal(80, c.level)
        assert.are.equal(12345678, c.money)
        assert.are.equal("Blackhand", c.realmName)
        assert.truthy(c.equipped.items[1]:find("10256", 1, true))
        assert.are.equal(1234, c.currency[3008])

        env.__state.money = 99
        env.FireEvent("PLAYER_MONEY")
        assert.are.equal(99, c.money)

        env.__state.currencies[2].quantity = 1300
        env.FireEvent("CURRENCY_DISPLAY_UPDATE", 3008, 1300, 66)
        assert.are.equal(1300, c.currency[3008])
        env.FireEvent("CURRENCY_DISPLAY_UPDATE", 3008, 0, -1300)
        assert.is_nil(c.currency[3008])

        env.__state.equipped[16] = nil
        env.FireEvent("PLAYER_EQUIPMENT_CHANGED", 16, true)
        assert.is_nil(c.equipped.items[16])

        env.FireEvent("PLAYER_LEVEL_UP", 81)
        assert.are.equal(81, c.level)
        assert.are.same({}, env.__errors)
    end)

    it("records last seen and money on logout", function()
        local env, ns = wow.boot(wow.defaultState())
        env.__state.now = env.__state.now + 500
        env.__state.money = 7
        local sv = wow.logout(env)
        assert.are.equal(7, sv.chars["Alice-Blackhand"].money)
        assert.are.equal(env.__state.now, sv.chars["Alice-Blackhand"].lastSeen)
        local _ = ns
    end)
end)

describe("Guild bank collector (opt-in)", function()
    local function guildState()
        local state = wow.defaultState()
        state.guild = { name = "Knights", realm = nil, money = 777, tabs = {
            { name = "Mats", slots = { [1] = { id = 2589, count = 100 }, [98] = { id = 190396, count = 20 } } },
            { name = "Officers", viewable = false, slots = { [1] = { id = 19019, count = 1 } } },
            { name = "Potions", slots = { [3] = { id = 212345, count = 40 } } },
        } }
        return state
    end

    it("is off by default and registers nothing", function()
        local env, ns = wow.boot(guildState())
        local f = ns.featureByKey.guildbank
        assert.is_false(f.active)
        assert.is_false(ns.IsEventRegistered(f, "PLAYER_INTERACTION_MANAGER_FRAME_SHOW"))
        env.FireEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 10)
        env.ProcessQueue()
        assert.is_nil(next(ns.db.guilds))
    end)

    it("walks every viewable tab, event driven, when enabled", function()
        local env, ns = wow.boot(guildState())
        ns.db.settings.collect.guildbank = true
        ns.SettingsChanged()
        env.FireEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 10)
        env.ProcessQueue()
        local g = ns.db.guilds["Knights-Blackhand"]
        assert.is_table(g)
        assert.are.equal("Knights", g.name)
        assert.are.equal(777, g.money)
        assert.are.equal("2589,100", g.tabs[1].items[1])
        assert.are.equal("190396,20", g.tabs[1].items[98])
        assert.is_nil(g.tabs[2])                          -- not viewable
        assert.are.equal("212345,40", g.tabs[3].items[3])
        ns.Index:EnsureBuilt()
        assert.are.equal(100, ns.Index:GetTotal(2589))
        env.FireEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 10)
        assert.is_false(ns.IsEventRegistered(ns.featureByKey.guildbank, "GUILDBANKBAGSLOTS_CHANGED"))
        assert.are.same({}, env.__errors)
    end)

    it("recovers when a foreign slots event arrives before the requested tab's data", function()
        local env, ns = wow.boot(guildState())
        ns.db.settings.collect.guildbank = true
        ns.SettingsChanged()
        env.FireEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 10)
        -- Blizzard's UI fires the event before our query for tab 1 is answered
        env.FireEvent("GUILDBANKBAGSLOTS_CHANGED")
        env.ProcessQueue()
        local g = ns.db.guilds["Knights-Blackhand"]
        assert.are.equal("2589,100", g.tabs[1].items[1])
        assert.are.equal("212345,40", g.tabs[3].items[3])
    end)

    it("keeps following moves in the viewed tab after the walk", function()
        local env, ns = wow.boot(guildState())
        ns.db.settings.collect.guildbank = true
        ns.SettingsChanged()
        env.FireEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 10)
        env.ProcessQueue()
        env.__state.guild.tabs[1].slots[1] = nil
        env.FireEvent("GUILDBANKBAGSLOTS_CHANGED")
        assert.is_nil(ns.db.guilds["Knights-Blackhand"].tabs[1].items[1])
    end)
end)
