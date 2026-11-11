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
        assert.are.equal("Player-1-Alice", retail.GetPlayerKey())
        assert.are.equal("Blackhand", retail.GetPlayerChar().realm)
        assert.are.equal("Knights-OtherRealm", (retail.GetPlayerGuildKey()))

        local state = forever({ guild = guild })
        state.player.ruleset = "RP-PvP"
        local env, fv = wow.boot(state)
        assert.are.equal("RPPvP", fv.GetPlayerChar().realm)
        assert.are.equal("Knights-RPPvP", (fv.GetPlayerGuildKey()))
        -- the realm part of EllesmereUI's gold ledger key, spaces and dashes kept
        assert.are.equal("RP-PvP", fv.GetPlayerChar().realmName)
        fv.db.chars["Player-1-Bob"] = { name = "Bob", realm = "RPPvP" }
        assert.are.equal("Player-1-Bob", fv.FindCharacterByName(fv.db.chars, "bob"))
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

    it("repairs 0g from a GUID-keyed ledger entry that carries the surname", function()
        local sv = { schema = 1, chars = {
            ["Bob-PvP"] = { name = "Bob", realm = "PvP", realmName = "PvP", money = 0 },
            ["Ann-PvP"] = { name = "Ann", realm = "PvP", realmName = "PvP", money = 0 },
        } }
        local env, ns = wow.boot(forever(), sv, { beforeLoad = function(e)
            fakeEUI.install(e)
            e.EllesmereUIDB = { goldLedger = { chars = {
                ["Player-1-0000000B"] = { money = 2500000, name = "Bob Miller", realm = "PvP" },
                -- two characters named Ann: the balance could be either one's
                ["Player-1-0000000A"] = { money = 10, name = "Ann Smith", realm = "PvP" },
                ["Player-1-0000000C"] = { money = 20, name = "Ann Jones", realm = "PvP" },
            } } }
        end })
        assert.are.equal(2500000, ns.db.chars["Bob-PvP"].money)
        assert.are.equal(0, ns.db.chars["Ann-PvP"].money)
        assert.are.same({}, env.__errors)
    end)
end)

describe("Character keys (Forever)", function()
    -- Logs the next character in on Forever, with the saved variables of env.
    local function relogForever(env, player)
        local sv = wow.logout(env)
        local state = forever()
        for k, v in pairs(player) do state.player[k] = v end
        return wow.boot(state, sv)
    end

    it("keeps characters with the same first name apart, with their full names", function()
        local state = forever()
        state.player.name, state.player.surname, state.player.guid = "Tåsk", "Force", "Player-1-0000000A"
        local env = wow.boot(state)
        local env2 = relogForever(env, { name = "Tåsk", surname = "Fôrce", guid = "Player-1-0000000B" })
        local env3, ns = relogForever(env2, { name = "Task", surname = "Force", guid = "Player-1-0000000C" })
        local keys = env3.EllesmereUIBagsAlts.GetCharacters()
        assert.are.equal(3, #keys)
        assert.are.equal("Tåsk Force", ns.db.chars["Player-1-0000000A"].name)
        assert.are.equal("Tåsk", ns.db.chars["Player-1-0000000A"].firstName)
        assert.are.equal("Tåsk Fôrce", ns.db.chars["Player-1-0000000B"].name)
        assert.are.equal("Task Force", ns.db.chars["Player-1-0000000C"].name)
        -- a typed full name finds its character; the shared first name finds none
        assert.are.equal("Player-1-0000000B", ns.FindCharacterByName(ns.db.chars, "tåsk fôrce"))
        assert.is_nil(ns.FindCharacterByName(ns.db.chars, "Tåsk"))
        assert.are.equal("Player-1-0000000C", ns.FindCharacterByName(ns.db.chars, "Task"))
        assert.are.same({}, env3.__errors)
    end)

    it("drops a record an older version filed under the first name", function()
        local sv = { schema = 1, chars = {
            ["Tåsk-PvP"] = { name = "Tåsk", realm = "PvP", money = 5,
                             bank = { [6] = { size = 1, items = "1:2589,20" } } },
        } }
        local state = forever()
        state.player.name, state.player.surname = "Tåsk", "Force"
        local env, ns = wow.boot(state, sv)
        env.EllesmereUIBagsAlts.GetCharacters()   -- activates
        assert.is_nil(ns.db.chars["Tåsk-PvP"])
        local c = ns.GetPlayerChar()
        assert.are.equal("Tåsk Force", c.name)
        assert.is_nil(c.bank[6])   -- the bank of the old record may be another character's
        assert.are.equal(0, (env.EllesmereUIBagsAlts.GetItemCount(2589)))
        assert.are.same({}, env.__errors)
    end)

    it("sends mail to a character by its full name", function()
        local state = forever()
        state.player.name, state.player.surname, state.player.guid = "Bob", "Miller", "Player-1-0000000B"
        local env = wow.boot(state)
        local env2, ns = relogForever(env, { name = "Ann", surname = "Smith", guid = "Player-1-0000000A" })
        env2.__state.sendItems = { { id = 2589, count = 3 } }
        env2.FireEvent("MAIL_SHOW")
        env2.SendMail("Bob Miller", "mats", "")
        env2.FireEvent("MAIL_SEND_SUCCESS")
        assert.are.equal(1, #ns.db.chars["Player-1-0000000B"].mailIncoming)
        assert.are.same({}, env2.__errors)
    end)
end)

describe("Money display (Forever)", function()
    it("shows silver and copper by default, retail whole gold", function()
        local _, fv = wow.boot(forever())
        assert.are.equal("gsc", fv.db.settings.ui.moneyFormat)
        assert.are.equal("43|cffc7c7cfs|r 21|cffeda55fc|r", fv.W.FormatGold(4321))
        local _, retail = wow.boot(wow.defaultState())
        assert.are.equal("g", retail.db.settings.ui.moneyFormat)
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
        assert.are.same({ "*all", "*realm:PvP", ns.GetPlayerKey() }, rows)
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
