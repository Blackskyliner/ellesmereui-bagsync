-- Compact storage: one packed string per container, item links shortened to
-- their "item:" core, old saved variables converted on activation.
local wow = require("wow")

local HELM_LINK = wow.itemLink(230000, "item:230000::::::::80:66::13:1:10256")
local HELM_CORE = "item:230000::::::::80:66::13:1:10256"
local PET_LINK = "|cff0070dd|Hbattlepet:1387:25:3:1627:289:289:0000000000000000:0|h[Pet]|h|r"

describe("Packed containers", function()
    it("stores a scanned bag as one string in slot order", function()
        local s = wow.defaultState()
        wow.putItem(s, 0, 3, 6948, 1)
        wow.putItem(s, 0, 1, 2589, 20)
        wow.putItem(s, 0, 2, 230000, 1, HELM_LINK)
        local _, ns = wow.boot(s)
        assert.are.equal("1:2589,20;2:230000,1," .. HELM_CORE .. ";3:6948,1", ns.GetPlayerChar().bags[0].items)
        assert.are.equal("", ns.GetPlayerChar().bags[1].items)       -- empty bag
    end)

    it("round-trips through the addon's pack/unpack helpers", function()
        local _, ns = wow.boot(wow.defaultState())
        local map = { [98] = "2589,5", [1] = "6948,1", [7] = "230000,1,!" .. HELM_CORE, [2] = "82800,1," .. PET_LINK }
        local packed = ns.PackItems(map)
        assert.are.same(map, ns.UnpackItems(packed))
        local order = {}
        for slot in ns.EachItem(packed) do order[#order + 1] = slot end
        assert.are.same({ 1, 2, 7, 98 }, order)
        assert.are.same({}, ns.UnpackItems(""))
    end)

    it("keeps battle pet and keystone links whole, item links as their core", function()
        local _, ns = wow.boot(wow.defaultState())
        assert.are.equal("82800,1," .. PET_LINK, ns.EncodeItem(82800, 1, PET_LINK))
        assert.are.equal("230000,1," .. HELM_CORE, ns.EncodeItem(230000, 1, HELM_LINK))
        -- a link containing the separator keeps only id and count
        assert.are.equal("1,1", ns.EncodeItem(1, 1, "|cff0070dd|Hbattlepet:1:1|h[A;B]|h|r"))
    end)
end)

describe("Conversion of stored data (0.7.x and older)", function()
    local function oldSV()
        return { schema = 1, chars = {
            ["Bob-Blackhand"] = { name = "Bob", realm = "Blackhand",
                bags = { [0] = { size = 20, items = { [1] = "6948,1", [4] = "230000,1,!" .. HELM_LINK, [5] = 12, [6] = "junk" } } },
                bank = { [6] = { size = 98, items = { [10] = "2589,200" } } },
                equipped = { size = 19, items = { [16] = "19019,1," .. wow.itemLink(19019, "item:19019:6226:::::::80:::::") } },
                mail = { items = { { e = "190396,5," .. HELM_LINK, x = 2 ^ 31 } } },
            } },
            warband = { bank = { [12] = { size = 98, items = { [1] = "2589,5" } } } },
            guilds = { ["Knights-Blackhand"] = { name = "Knights", tabs = { [1] = { size = 98, items = { [3] = "212345,40" } } } } },
        }
    end

    it("packs old containers and shortens their links on activation, not at login", function()
        local env, ns = wow.boot(wow.defaultState(), oldSV(), { inactive = true })
        assert.is_table(ns.db.chars["Bob-Blackhand"].bags[0].items)  -- untouched until first use
        env.OpenBags()
        local bob = ns.db.chars["Bob-Blackhand"]
        assert.are.equal("1:6948,1;4:230000,1,!" .. HELM_CORE, bob.bags[0].items)   -- junk dropped
        assert.are.equal("10:2589,200", bob.bank[6].items)
        assert.are.equal("16:19019,1,item:19019:6226:::::::80:::::", bob.equipped.items)
        assert.are.equal("190396,5," .. HELM_CORE, bob.mail.items[1].e)
        assert.are.equal("1:2589,5", ns.db.warband.bank[12].items)
        assert.are.equal("3:212345,40", ns.db.guilds["Knights-Blackhand"].tabs[1].items)
        -- the converted data counts as before
        ns.Index:EnsureBuilt()
        assert.are.equal(205, ns.Index:GetTotal(2589))
        assert.are.equal(1, ns.Index:GetTotal(230000))
        assert.are.same({}, env.__errors)
    end)

    it("is idempotent and repairs a malformed packed string", function()
        local env = wow.boot(wow.defaultState(), oldSV())
        local sv = wow.logout(env)
        local before = sv.chars["Bob-Blackhand"].bags[0].items
        sv.chars["Bob-Blackhand"].bank[6].items = "10:2589,200;x:bad;11:nonsense;12:2592,3"
        local _, ns2 = wow.boot(wow.defaultState(), sv)
        local bob = ns2.db.chars["Bob-Blackhand"]
        assert.are.equal(before, bob.bags[0].items)
        assert.are.equal("10:2589,200;12:2592,3", bob.bank[6].items)
    end)
end)

describe("Links from stored cores", function()
    it("tooltip and shift-click work from the stored item: core", function()
        local s = wow.defaultState()
        wow.putItem(s, 0, 1, 230000, 1, HELM_LINK)
        local env, ns = wow.boot(s)
        ns.Browser:Open()
        ns.Browser:SelectTab("bags")
        local b = env.EllesmereUIBagsAltsBrowser.grid.buttons[1]
        assert.are.equal(HELM_CORE, b.ref)
        b:RunScript("OnEnter")
        assert.are.equal(HELM_CORE, env.EllesmereUIBagsAltsTooltip.processingInfo.getterArgs[1])
        env.__state.modifiers.shift = true
        b:RunScript("OnClick", "LeftButton")
        assert.truthy(env.__clicks[#env.__clicks]:find("|Hitem:230000", 1, true))   -- a full link for chat
    end)
end)

describe("Saved variables size", function()
    -- 20 characters with 150 items in the bags and 300 in the bank, 300 in
    -- the warband bank, one stack in five gear with a bonus-ID link.
    local function fill(ns)
        local function container(size, used, seed)
            local map = {}
            for k = 1, used do
                local slot = math.floor((k - 1) * size / used) + 1
                local id = 200000 + seed * 1000 + k
                local link = k % 5 == 0 and wow.itemLink(id, "item:" .. id .. "::::::::80:66::13:2:10256:" .. (1000 + k)) or nil
                map[slot] = ns.EncodeItem(id, k % 20 + 1, link)
            end
            return { size = size, items = ns.PackItems(map) }
        end
        for c = 1, 20 do
            local ch = ns.GetChar("Alt" .. c .. "-Blackhand", true)
            for bag = 0, 5 do ch.bags[bag] = container(36, 25, c * 20 + bag) end
            for tab = 6, 11 do ch.bank[tab] = container(98, 50, c * 20 + tab) end
        end
        for tab = 12, 16 do ns.db.warband.bank[tab] = container(98, 60, 900 + tab) end
    end

    it("stays small for the expected data volume", function()
        local env, ns = wow.boot(wow.defaultState())
        fill(ns)
        local _, bytes = wow.logout(env)
        assert.is_true(bytes < 240 * 1024, "SV size " .. bytes)
    end)
end)
