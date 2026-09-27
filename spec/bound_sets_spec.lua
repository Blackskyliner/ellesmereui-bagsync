-- Bound state per stored item and equipment set membership.
local wow = require("wow")

local HELM_LINK = wow.itemLink(230000, "item:230000::::::::80:66::13:1:10256")

local function tooltipText(env, tooltip)
    local out = {}
    for _, l in ipairs((tooltip or env.EllesmereUIBagsAltsTooltip).lines) do out[#out + 1] = table.concat(l, " | ") end
    return table.concat(out, "\n")
end

local function hoverFirst(env, ns, tab, match)
    ns.Browser:Open()
    ns.Browser:SelectTab(tab)
    local f = env.EllesmereUIBagsAltsBrowser
    for i = 1, f.grid.used do
        local b = f.grid.buttons[i]
        if b.ref:find(match, 1, true) then
            b:RunScript("OnEnter")
            return tooltipText(env), b
        end
    end
    error("no button for " .. match)
end

describe("Bound state", function()
    it("encodes and decodes the marker, and old data still decodes as free", function()
        local _, ns = wow.boot(wow.defaultState())
        assert.are.equal("6948,1,!", ns.EncodeItem(6948, 1, nil, "soul"))
        assert.are.equal("232000,1,~", ns.EncodeItem(232000, 1, nil, "account"))
        local core = "item:230000::::::::80:66::13:1:10256"         -- stored: the link's item: core
        local enc = ns.EncodeItem(230000, 1, HELM_LINK, "soul")
        assert.are.equal("230000,1,!" .. core, enc)
        assert.are.same({ 230000, 1, core, "soul" }, { ns.DecodeItem(enc) })
        assert.are.same({ 230000, 1, HELM_LINK }, { ns.DecodeItem("230000,1," .. HELM_LINK) })   -- 0.3.x data
        assert.are.same({ 2589, 20 }, { ns.DecodeItem("2589,20") })
        assert.are.same({ 6948, 1 }, { ns.DecodeItemIDCount("6948,1,!") })
    end)

    it("records soulbound, warbound and free items from the bags", function()
        local s = wow.defaultState()
        wow.putItem(s, 0, 1, 230000, 1, HELM_LINK)          -- BoE, equipped once -> soulbound
        s.bags[0].slots[1].bound = true
        wow.putItem(s, 0, 2, 230000, 1, HELM_LINK)          -- BoE, never equipped -> free
        wow.putItem(s, 0, 3, 232000, 1)                      -- warbound (ToBnetAccount)
        s.bags[0].slots[3].bound = true
        wow.putItem(s, 0, 4, 231000, 1)                      -- warbound until equipped: still movable
        s.bags[0].slots[4].bound = true
        s.bags[0].slots[4].wue = true
        local _, ns = wow.boot(s)
        local items = wow.items(ns.GetPlayerChar().bags[0])
        assert.are.equal("soul", select(4, ns.DecodeItem(items[1])))
        assert.is_nil(select(4, ns.DecodeItem(items[2])))
        assert.are.equal("account", select(4, ns.DecodeItem(items[3])))
        assert.is_nil(select(4, ns.DecodeItem(items[4])))
        ns.Index:EnsureBuilt()
        assert.are.equal(2, ns.Index:GetTotal(230000))      -- counts are unaffected by the marker
    end)

    it("records worn gear as bound (warbound stays warbound)", function()
        local s = wow.defaultState()
        s.equipped[1] = { id = 230000, link = HELM_LINK }
        s.equipped[16] = { id = 232000, link = wow.itemLink(232000) }
        local _, ns = wow.boot(s)
        local items = wow.items(ns.GetPlayerChar().equipped)
        assert.are.equal("soul", select(4, ns.DecodeItem(items[1])))
        assert.are.equal("account", select(4, ns.DecodeItem(items[16])))
    end)

    it("shows Soulbound instead of 'Binds when equipped' for a bound stored item", function()
        local s = wow.defaultState()
        wow.putItem(s, 0, 1, 230000, 1, HELM_LINK)
        s.bags[0].slots[1].bound = true
        local env, ns = wow.boot(s)
        local text = tooltipText((function() hoverFirst(env, ns, "bags", "230000") return env end)())
        assert.truthy(text:find("Soulbound", 1, true))
        assert.falsy(text:find("Binds when equipped", 1, true))
        assert.are.same({}, env.__errors)
    end)

    it("keeps 'Binds when equipped' for a free item and shows Warbound / warbound-until-equipped correctly", function()
        local s = wow.defaultState()
        wow.putItem(s, 0, 1, 230000, 1, HELM_LINK)
        wow.putItem(s, 0, 2, 232000, 1)
        s.bags[0].slots[2].bound = true
        wow.putItem(s, 0, 3, 231000, 1)
        s.bags[0].slots[3].bound = true
        s.bags[0].slots[3].wue = true
        local env, ns = wow.boot(s)
        assert.truthy((hoverFirst(env, ns, "bags", "230000")):find("Binds when equipped", 1, true))
        local warbound = hoverFirst(env, ns, "bags", "232000")
        assert.truthy(warbound:find("Warbound", 1, true))
        local wue = hoverFirst(env, ns, "bags", "231000")
        assert.truthy(wue:find("Warbound until equipped", 1, true))
    end)

    it("the bound state survives a relog and shows on another character", function()
        local s = wow.defaultState()
        wow.putItem(s, 0, 1, 230000, 1, HELM_LINK)
        s.bags[0].slots[1].bound = true
        local env = wow.boot(s)
        local env2, ns2 = wow.relog(env, { name = "Bob" })
        ns2.Browser:Open("Alice-Blackhand")
        local text = hoverFirst(env2, ns2, "bags", "230000")
        assert.truthy(text:find("Soulbound", 1, true))
    end)

    it("uses Blizzard's tooltip pipeline scoped to the browser (no global line hooks)", function()
        local s = wow.defaultState()
        wow.putItem(s, 0, 1, 230000, 1, HELM_LINK)
        s.bags[0].slots[1].bound = true
        local env, ns = wow.boot(s)
        hoverFirst(env, ns, "bags", "230000")
        local info = env.EllesmereUIBagsAltsTooltip.processingInfo
        assert.are.equal("GetHyperlink", info.getterName)
        assert.is_function(info.linePreCall)
        assert.is_nil(env.GameTooltip.processingInfo)          -- Blizzard's GameTooltip never touched
        -- a normal item tooltip elsewhere is untouched
        env.GameTooltip:SetOwner(env.UIParent)
        env.GameTooltip:ProcessInfo({ getterName = "GetHyperlink", getterArgs = { "item:230000" } })
        assert.truthy(tooltipText(env, env.GameTooltip):find("Binds when equipped", 1, true))
    end)
end)

describe("Equipment sets", function()
    local function setWorld()
        local s = wow.defaultState()
        wow.putItem(s, 0, 1, 230000, 1, HELM_LINK)
        s.bags[0].slots[1].bound = true
        s.equipped[16] = { id = 19019, link = wow.itemLink(19019) }
        s.equipmentSets = {
            { id = 1, name = "Tank", items = { "b0:1", "e16" } },
            { id = 2, name = "PvP", items = { "b0:1" } },
        }
        return s
    end

    it("stores set names per bag slot and worn slot", function()
        local _, ns = wow.boot(setWorld())
        local c = ns.GetPlayerChar()
        assert.are.equal("Tank, PvP", c.bags[0].sets[1])
        assert.are.equal("Tank", c.equipped.sets[16])
        assert.is_nil(c.bags[1].sets)                         -- no sets, nothing stored
    end)

    it("lists the sets in the browser tooltip", function()
        local env, ns = wow.boot(setWorld())
        local text = hoverFirst(env, ns, "bags", "230000")
        assert.truthy(text:find("Equipment sets: |cffffffffTank, PvP|r", 1, true))
        local worn = hoverFirst(env, ns, "equipped", "19019")
        assert.truthy(worn:find("Equipment sets: |cffffffffTank|r", 1, true))
    end)

    it("follows set changes and item moves", function()
        local env, ns = wow.boot(setWorld())
        env.__state.equipmentSets[2] = nil                    -- PvP set deleted
        env.FireEvent("EQUIPMENT_SETS_CHANGED")
        assert.are.equal("Tank", ns.GetPlayerChar().bags[0].sets[1])
        -- helm moved from bag 0 slot 1 to slot 5; the set follows the item
        local S = env.__state
        S.bags[0].slots[5] = S.bags[0].slots[1]
        S.bags[0].slots[1] = nil
        S.equipmentSets[1].items = { "b0:5", "e16" }
        env.FireEvent("BAG_UPDATE", 0)
        env.FireEvent("BAG_UPDATE_DELAYED")
        local sets = ns.GetPlayerChar().bags[0].sets
        assert.is_nil(sets[1])
        assert.are.equal("Tank", sets[5])
    end)

    it("costs no set lookups for characters without sets", function()
        local env, ns = wow.boot(wow.defaultState())
        local calls = 0
        local orig = env.C_EquipmentSet.GetItemLocations
        env.C_EquipmentSet.GetItemLocations = function(...) calls = calls + 1 return orig(...) end
        env.FireEvent("BAG_UPDATE", 0)
        env.FireEvent("BAG_UPDATE_DELAYED")
        assert.are.equal(0, calls)
        local _ = ns
    end)

    it("sanitizes stored set data", function()
        local sv = { schema = 1, chars = { ["Bob-Blackhand"] = { bags = { [0] = { size = 4,
            items = { [1] = "6948,1,!" }, sets = { [1] = "Tank", [2] = 5, x = "y" } } } } } }
        local env, ns = wow.boot(wow.defaultState(), sv)
        assert.are.same({ [1] = "Tank" }, ns.db.chars["Bob-Blackhand"].bags[0].sets)
        assert.are.same({}, env.__errors)
    end)
end)

describe("Browser tooltip", function()
    it("shows the cross-character counts on the private tooltip too", function()
        local s = wow.defaultState()
        wow.putItem(s, 0, 1, 230000, 1, HELM_LINK)
        local env, ns = wow.boot(s)
        ns.db.settings.tooltip.enabled = true
        ns.SettingsChanged()
        local text = hoverFirst(env, ns, "bags", "230000")    -- tooltip frame created after enabling
        assert.truthy(text:find("Bags: 1", 1, true))
    end)
end)

