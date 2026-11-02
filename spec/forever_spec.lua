local wow = require("wow")
local fakeEUI = require("fake_eui")

-- WoW Forever (state.client = "forever"): the differences Core/ClientCompat.lua
-- covers, each next to what retail does in the same place.
local function forever(overrides)
    local state = wow.defaultState(overrides)
    state.client = "forever"
    return state
end

describe("Client compatibility", function()
    it("follows EllesmereUI's client decision", function()
        local _, retail = wow.boot(wow.defaultState())
        local _, fv = wow.boot(forever())
        assert.is_false(retail.Compat.IS_FOREVER)
        assert.is_true(retail.Compat.HAS_WARBAND_BANK)
        assert.is_true(fv.Compat.IS_FOREVER)
        assert.is_false(fv.Compat.HAS_WARBAND_BANK)
        assert.is_false(fv.Compat.HAS_PET_BATTLES)
    end)

    it("keys Forever characters and guilds by realm group, retail ones by realm", function()
        local guild = { name = "Knights", realm = "Other Realm", money = 0, tabs = {} }
        local _, retail = wow.boot(wow.defaultState({ guild = guild }))
        assert.are.equal("Alice-Blackhand", retail.GetPlayerKey())
        assert.are.equal("Knights-OtherRealm", (retail.GetPlayerGuildKey()))

        local state = forever({ guild = guild })
        state.player.ruleset = "RP-PvP"
        local env, fv = wow.boot(state)
        assert.are.equal("Alice-RPPvP", fv.GetPlayerKey())
        assert.are.equal("Knights-RPPvP", (fv.GetPlayerGuildKey()))
        -- the realm part of EllesmereUI's gold ledger key, spaces and dashes kept
        assert.are.equal("RP-PvP", fv.GetPlayerChar().realmName)
        assert.are.equal("Bob-RPPvP", fv.NormalizeCharacterName("bob"))
        assert.are.same({}, env.__errors)
    end)

    it("repairs 0g from the gold ledger under the realm group on Forever", function()
        local sv = { schema = 1, chars = {
            ["Bob-PvP"] = { name = "Bob", realm = "PvP", realmName = "PvP", money = 0 },
        } }
        local env, ns = wow.boot(forever(), sv, { beforeLoad = function(e)
            fakeEUI.install(e)
            e.EllesmereUIDB = { goldLedger = { chars = {
                ["Bob-PvP"] = { money = 2500000, updated = 1789990000, name = "Bob", realm = "PvP" },
            } } }
        end })
        assert.are.equal(2500000, ns.db.chars["Bob-PvP"].money)
        assert.are.same({}, env.__errors)
    end)
end)

describe("Keyring (Forever)", function()
    it("is scanned with the bags and followed by BAG_UPDATE", function()
        local state = forever()
        state.bags[-1] = { size = 32, slots = {} }
        wow.putItem(state, -1, 2, 6948, 1)
        local env, ns = wow.boot(state)
        local c = ns.GetPlayerChar()
        assert.are.equal(32, c.bags[-1].size)
        assert.are.equal("6948,1", wow.items(c.bags[-1])[2])
        assert.are.equal(1, (env.EllesmereUIBagsAlts.GetItemCount(6948)))

        wow.putItem(env.__state, -1, 3, 2589, 4)
        env.FireEvent("BAG_UPDATE", -1)
        env.FireEvent("BAG_UPDATE_DELAYED")
        assert.are.equal("2589,4", wow.items(c.bags[-1])[3])
        assert.are.same({}, env.__errors)
    end)

    it("is no bag on retail", function()
        local state = wow.defaultState()
        wow.putItem(state, -1, 2, 6948, 1)
        local env, ns = wow.boot(state)
        assert.is_nil(ns.GetPlayerChar().bags[-1])
        env.FireEvent("BAG_UPDATE", -1)
        env.FireEvent("BAG_UPDATE_DELAYED")
        assert.is_nil(ns.GetPlayerChar().bags[-1])
    end)
end)

describe("Ammo slot (Forever)", function()
    it("stores the worn ammo stack with its count", function()
        local state = forever()
        state.equipped[0] = { id = 2589, count = 200, link = wow.itemLink(2589) }
        state.equipped[16] = { id = 19019, link = wow.itemLink(19019) }
        local env, ns = wow.boot(state)
        local items = wow.items(ns.GetPlayerChar().equipped)
        assert.are.equal("2589,200", items[0])
        assert.truthy(items[16])
        assert.are.equal(200, env.EllesmereUIBagsAlts.GetItemCount(2589))
    end)

    it("is no slot on retail", function()
        local state = wow.defaultState()
        state.equipped[0] = { id = 2589, count = 200, link = wow.itemLink(2589) }
        local _, ns = wow.boot(state)
        assert.is_nil(wow.items(ns.GetPlayerChar().equipped)[0])
    end)
end)

describe("Bank (Forever)", function()
    it("scans the base slots and each bank bag, and never the warband", function()
        local state = forever()
        -- tab 1 = base slots, tab 2 = a placed 16-slot bag, tab 3 = bought, no bag
        state.bankTabs[0] = { { ID = 6 }, { ID = 7 }, { ID = 8 } }
        state.bags[6] = { size = 24, slots = {} }
        state.bags[7] = { size = 16, slots = {} }
        state.bags[8] = { size = 0, slots = {} }
        wow.putItem(state, 6, 1, 2589, 20)
        wow.putItem(state, 7, 16, 2592, 5)
        local env, ns = wow.boot(state)
        env.FireEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 8)
        local c = ns.GetPlayerChar()
        assert.are.equal("2589,20", wow.items(c.bank[6])[1])
        assert.are.equal("2592,5", wow.items(c.bank[7])[16])
        assert.are.equal(0, c.bank[8].size)
        env.FireEvent("ACCOUNT_MONEY")
        assert.is_nil(next(ns.db.warband.bank))
        assert.is_nil(ns.db.warband.money)
        assert.is_nil(ns.db.warband.bankAt)
        assert.are.same({}, env.__errors)
    end)
end)

describe("Mail links", function()
    it("store a stack by item ID when the client lacks the link API", function()
        local state = forever()
        state.inbox = { { sender = "Friend", daysLeft = 3, items = { { id = 2589, count = 20 } } } }
        local env, ns = wow.boot(state)
        env.GetInboxItemLink = nil
        env.FireEvent("MAIL_SHOW")
        assert.are.equal("2589,20", ns.GetPlayerChar().mail.items[1].e)
        assert.are.same({}, env.__errors)
    end)
end)

describe("Interface (Forever)", function()
    it("lists no warband bank in the browser", function()
        local env, ns = wow.boot(forever())
        env.Slash("")
        local f = env.EllesmereUIBagsAltsBrowser
        local rows = {}
        for i = 1, f.sideRows.used do rows[#rows + 1] = f.sideRows.items[i].ownerKey end
        assert.are.same({ "*all", "*realm:PvP", "Alice-PvP" }, rows)
        assert.are.equal(ns.GetPlayerKey(), ns.Browser:GetState().owner)
        assert.are.same({}, env.__errors)
    end)

    it("leaves caged pets to the item tooltip", function()
        local env, ns = wow.boot(forever())
        local owner = env.CreateFrame("Frame", nil, env.UIParent)
        assert.is_false(ns.W.ShowPetTooltip(owner, "|Hbattlepet:39:25:3:1627:289:289:0000000000000000:0|h[Pet]|h"))
        assert.is_nil(env.EllesmereUIBagsAltsPetTooltip)
    end)
end)
