local wow = require("wow")

local function bootWith(fn)
    local state = wow.defaultState()
    if fn then fn(state) end
    return wow.boot(state)
end

describe("Keys", function()
    local ns
    before_each(function() local _; _, ns = bootWith() end)

    it("builds the character key from name and normalized realm", function()
        assert.are.equal("Alice-Blackhand", ns.GetPlayerKey())
        assert.are.same({ "Alice", "Blackhand" }, { ns.SplitKey("Alice-Blackhand") })
    end)

    it("encodes plain items without their link", function()
        assert.are.equal("2589,20", ns.EncodeItem(2589, 20, wow.itemLink(2589)))
        assert.are.same({ 2589, 20 }, { ns.DecodeItem("2589,20") })
    end)

    it("keeps links that carry bonus IDs, enchants, gems, pets and keystones", function()
        local bonus = wow.itemLink(230000, "item:230000::::::::80:66::13:2:10256:1520")
        local enchant = wow.itemLink(19019, "item:19019:6226:::::::80:::::")
        local gem = wow.itemLink(230000, "item:230000::213743::::::80:::::")
        local pet = "|cff0070dd|Hbattlepet:1387:25:3:1627:289:289:0000000000000000:0|h[Pet]|h|r"
        local key = "|cffa335ee|Hkeystone:180653:2649:12:10:0:0:0|h[Keystone]|h|r"
        -- item links keep only their "item:" core; pet and keystone links stay whole
        local expected = { [bonus] = "item:230000::::::::80:66::13:2:10256:1520", [enchant] = "item:19019:6226:::::::80:::::",
                           [gem] = "item:230000::213743::::::80:::::", [pet] = pet, [key] = key }
        for _, link in ipairs({ bonus, enchant, gem, pet, key }) do
            assert.is_true(ns.LinkIsRich(link), link)
            local enc = ns.EncodeItem(1, 1, link)
            local _, _, back = ns.DecodeItem(enc)
            assert.are.equal(expected[link], back)
            assert.is_true(ns.LinkIsRich(back))
        end
        assert.is_false(ns.LinkIsRich(wow.itemLink(230000, "item:230000::::::::80:66::13:0")))
        assert.is_false(ns.LinkIsRich(nil))
    end)

    it("rejects malformed encodings", function()
        assert.is_nil(ns.DecodeItem("abc"))
        assert.is_nil(ns.DecodeItem(nil))
        assert.is_nil(ns.DecodeItem(12))
    end)

    it("normalizes typed recipient names", function()
        assert.are.equal("Bob-Blackhand", ns.NormalizeCharacterName("bob"))
        assert.are.equal("Bob-MalGanis", ns.NormalizeCharacterName(" Bob-Mal'Ganis "))
        assert.are.equal("Bob-Area52", ns.NormalizeCharacterName("BOB-Area 52"))
        assert.is_nil(ns.NormalizeCharacterName(""))
        assert.is_nil(ns.NormalizeCharacterName(nil))
    end)

    it("finds known characters case-insensitively", function()
        local chars = { ["Bob-Blackhand"] = {} }
        assert.are.equal("Bob-Blackhand", ns.FindKnownCharacter(chars, "bob-blackhand"))
        assert.is_nil(ns.FindKnownCharacter(chars, "Carl-Blackhand"))
    end)

    it("scopes realms: realm, connected, all", function()
        assert.is_true(ns.IsRealmInScope("Blackhand", "realm"))
        assert.is_false(ns.IsRealmInScope("MalGanis", "realm"))
        assert.is_true(ns.IsRealmInScope("MalGanis", "connected"))
        assert.is_false(ns.IsRealmInScope("Antonidas", "connected"))
        assert.is_true(ns.IsRealmInScope("Antonidas", "all"))
    end)
end)

describe("DB", function()
    it("defaults every visible behavior to OFF (criterion 2)", function()
        local _, ns = bootWith()
        local s = ns.db.settings
        assert.is_false(s.tooltip.enabled)
        assert.is_false(s.ui.headerButton)
        assert.is_false(s.ui.useEUICategories)
        assert.is_false(s.collect.guildbank)
    end)

    it("sanitizes corrupted saved variables instead of erroring", function()
        local sv = {
            schema = 1,
            settings = { tooltip = "garbage", collect = { bags = "yes" } },
            chars = {
                ["Bob-Blackhand"] = { bags = { [0] = { size = 4, items = { [1] = "6948,1", [2] = 12, [3] = "junk" } }, x = { } },
                                      mail = "no", currency = 5 },
                [5] = { },
                ["Broken-Realm"] = "not a table",
            },
            warband = { bank = { [12] = { items = { [1] = "2589,5" } }, bad = 1 } },
            guilds = { ["G-R"] = { tabs = "x" }, [1] = {} },
        }
        local env, ns = wow.boot(wow.defaultState(), sv)
        assert.are.same({}, env.__errors)
        local bob = ns.db.chars["Bob-Blackhand"]
        assert.are.equal("1:6948,1", bob.bags[0].items)            -- old table format packed
        assert.are.same({}, bob.mail.items)
        assert.is_table(bob.currency)
        assert.is_nil(ns.db.chars[5])
        assert.is_nil(ns.db.chars["Broken-Realm"])
        assert.are.equal("table", type(ns.db.settings.tooltip))
        assert.is_true(ns.db.settings.collect.bags)
        assert.are.equal("2589,5", wow.items(ns.db.warband.bank[12])[1])
        assert.is_nil(ns.db.warband.bank.bad)
        assert.are.same({}, ns.db.guilds["G-R"].tabs)
        assert.is_nil(ns.db.guilds[1])
    end)

    it("keeps user settings across logins", function()
        local env, ns = bootWith()
        ns.db.settings.tooltip.maxChars = 3
        local env2, ns2 = wow.relog(env, { name = "Bob" })
        assert.are.equal(3, ns2.db.settings.tooltip.maxChars)
        assert.are.same({}, env2.__errors)
    end)
end)

describe("ItemIndex", function()
    it("matches a fresh rebuild after many random incremental changes", function()
        local env, ns = bootWith()
        local seed = 12345
        local function rand(n)
            seed = (seed * 1103515245 + 12345) % 2147483648
            return seed % n + 1
        end
        local ids = { 6948, 2589, 2592, 190396, 212345 }
        ns.Index:EnsureBuilt()
        local S = env.__state
        for step = 1, 400 do
            local bag = rand(2) - 1
            local slot = rand(S.bags[bag].size)
            if rand(3) == 1 then
                S.bags[bag].slots[slot] = nil
            else
                wow.putItem(S, bag, slot, ids[rand(#ids)], rand(200))
            end
            if step % 7 == 0 then S.bags[1].size = 12 + rand(8) end
            env.FireEvent("BAG_UPDATE", bag)
            if rand(2) == 1 then env.FireEvent("BAG_UPDATE_DELAYED") end
        end
        env.FireEvent("BAG_UPDATE", 1)
        env.FireEvent("BAG_UPDATE_DELAYED")
        local incremental = wow.deepCopy(ns.Index.data)
        ns.Index:Build()
        assert.are.same(ns.Index.data, incremental)
        assert.are.same({}, env.__errors)
    end)

    it("reports touched item IDs on change", function()
        local env, ns = bootWith(function(s) wow.putItem(s, 0, 1, 2589, 5) end)
        ns.Index:EnsureBuilt()
        local seen
        ns.On("ITEM_COUNTS_CHANGED", {}, function(_, touched) seen = touched end)
        wow.putItem(env.__state, 0, 1, 2592, 3)
        env.FireEvent("BAG_UPDATE", 0)
        env.FireEvent("BAG_UPDATE_DELAYED")
        assert.is_true(seen[2589])
        assert.is_true(seen[2592])
        assert.are.equal(3, ns.Index:GetTotal(2592))
        assert.are.equal(0, ns.Index:GetTotal(2589))
    end)
end)
