local wow = require("wow")
local fakeEUI = require("fake_eui")

local function bootWithEUI(eopts, state)
    local rec
    local env, ns = wow.boot(state or wow.defaultState(), nil, {
        beforeLoad = function(env) rec = fakeEUI.install(env, eopts) end,
    })
    return env, ns, rec
end

local function richWorld()
    local s = wow.defaultState()
    wow.putItem(s, 0, 1, 19019, 1)
    wow.putItem(s, 0, 2, 2589, 20)
    wow.putItem(s, 1, 1, 230000, 1, wow.itemLink(230000, "item:230000::::::::80:66::13:1:10256"))
    wow.putItem(s, 1, 2, 6948, 1)
    return s
end

describe("EUIBagsExt connector without EllesmereUI", function()
    local env, Ext
    before_each(function()
        env = wow.boot(wow.defaultState())
        Ext = env.EllesmereUIBagsExt
    end)

    it("reports EUI as absent and falls back everywhere", function()
        assert.is_false(Ext:IsEUILoaded())
        assert.is_false(Ext:IsBagsLoaded())
        assert.is_false(Ext:RegisterSkin("x", function() end))
        assert.are.same({ env.STANDARD_TEXT_FONT, "" }, { Ext:GetFont() })
        local r, g, b = Ext:GetAccentColor()
        assert.is_number(r); assert.is_number(g); assert.is_number(b)
        assert.are.equal("Hello", Ext:L("Hello"))
        assert.is_false(Ext:SkinItemButton(env.CreateFrame("ItemButton")))
        assert.is_nil(Ext:ClassifyItem("x", 1))
        assert.is_false(Ext:RegisterHeaderButton("k", {}))
        assert.are.equal("", Ext:GetBagSearchText())
    end)

    it("uses its own popup for confirmations", function()
        local confirmed = false
        Ext:Confirm({ title = "T", message = "M", onConfirm = function() confirmed = true end })
        local popup = env.EllesmereUIBagsExtPopup
        assert.is_true(popup:IsShown())
        popup.confirm:Click()
        assert.is_true(confirmed)
        assert.is_false(popup:IsShown())
    end)

    it("shows plain GameTooltip text as widget tooltip fallback", function()
        local owner = env.CreateFrame("Button")
        Ext:ShowTooltip(owner, "hi")
        assert.are.equal(owner, env.GameTooltip.owner)
    end)

    it("keeps the highest embedded version", function()
        local ns = env.__ns
        local _ = ns
        local lib = env.EllesmereUIBagsExt
        assert.are.equal(1, lib.minor)
        lib.minor = 99
        local chunk = assert(loadfile(wow.ROOT .. "/EllesmereUIBags_Alts/Libs/EUIBagsExt/EUIBagsExt.lua"))
        setfenv(chunk, env)
        chunk()
        assert.are.equal(99, env.EllesmereUIBagsExt.minor)
    end)
end)

describe("EUIBagsExt connector with EllesmereUI", function()
    it("delegates looks, house UI and categories to EUI", function()
        local env, _, rec = bootWithEUI()
        local Ext = env.EllesmereUIBagsExt
        assert.is_true(Ext:IsBagsLoaded())
        local path, flag = Ext:GetFont("bags")
        assert.truthy(path:find("Expressway", 1, true))
        assert.are.equal("OUTLINE", flag)
        assert.are.same({ 0.1, 0.2, 0.3 }, { Ext:GetAccentColor() })
        local btn = env.CreateFrame("ItemButton")
        assert.is_true(Ext:SkinItemButton(btn))
        assert.is_true(rec.skinned[btn].anchorIcon)
        assert.is_true(Ext:SetItemBorderColor(btn, 1, 0, 0, 1))
        assert.are.same({ 1, 0, 0, 1 }, rec.borders[btn])
        Ext:Confirm({ title = "T" })
        assert.are.equal("T", rec.popups[#rec.popups].title)
        Ext:ShowTooltip(btn, "x")
        assert.are.equal("x", rec.tooltips[1][2])
        local idx, name = Ext:ClassifyItem(wow.itemLink(19019), 19019)
        assert.are.equal(1, idx)
        assert.are.equal("Weapons / Trinkets", name)
    end)

    it("survives EUI functions that throw", function()
        local env = bootWithEUI({ skinThrows = true, classifyThrows = true })
        local Ext = env.EllesmereUIBagsExt
        assert.is_false(Ext:RegisterSkin("x", function() end))
        assert.is_nil(Ext:ClassifyItem(wow.itemLink(19019), 19019))
        assert.are.same({}, env.__errors)
    end)

    it("places header buttons next to the item count without touching EUI frames", function()
        local env = bootWithEUI()
        local Ext = env.EllesmereUIBagsExt
        local header = env.EUI_Bags.Header
        local before = {}
        for k, v in pairs(header) do before[k] = v end
        local clicked = 0
        assert.is_true(Ext:RegisterHeaderButton("a", { tooltip = "A", onClick = function() clicked = clicked + 1 end, order = 2 }))
        assert.is_true(Ext:RegisterHeaderButton("b", { tooltip = "B", order = 1 }))
        local a, b = Ext:GetHeaderButton("a"), Ext:GetHeaderButton("b")
        assert.are.equal(header, a:GetParent())
        local p, rel = b:GetPoint(1)
        assert.are.equal("LEFT", p)
        assert.are.equal(header.itemCount, rel)
        local _, relA = a:GetPoint(1)
        assert.are.equal(b, relA)                      -- ordered: b then a
        a:Click()
        assert.are.equal(1, clicked)
        -- No field of the EUI header was written (children list aside).
        for k, v in pairs(header) do
            if k ~= "children" and k ~= "regions" and k ~= "points" then assert.are.equal(before[k], v, k) end
        end
        Ext:SetHeaderButtonShown("b", false)
        assert.is_false(b:IsShown())
        local _, relA2 = a:GetPoint(1)
        assert.are.equal(header.itemCount, relA2)      -- re-laid out
    end)

    it("attaches once the header appears (hooked OnShow), if it did not exist yet", function()
        local env = bootWithEUI({ lateHeader = true })
        local Ext = env.EllesmereUIBagsExt
        assert.is_true(Ext:RegisterHeaderButton("late", { tooltip = "L" }))
        assert.is_nil(Ext:GetHeaderButton("late"))
        fakeEUI.createHeader()
        env.EUI_Bags:Show()
        assert.is_table(Ext:GetHeaderButton("late"))
        assert.are.equal(env.EUI_Bags.Header, Ext:GetHeaderButton("late"):GetParent())
    end)

    it("delegates to a native upstream RegisterHeaderButton when EUI ships one", function()
        local env = bootWithEUI()
        local calls = {}
        function env.EUI_Bags:RegisterHeaderButton(key, opts) calls[#calls + 1] = { key, opts } return true end
        assert.is_true(env.EllesmereUIBagsExt:RegisterHeaderButton("n", { tooltip = "N" }))
        assert.are.equal("n", calls[1][1])
        assert.is_nil(env.EllesmereUIBagsExt:GetHeaderButton("n"))
    end)
end)

describe("Header button feature", function()
    it("is off by default and toggles with the setting", function()
        local env, ns = bootWithEUI(nil, richWorld())
        local Ext = env.EllesmereUIBagsExt
        assert.is_nil(Ext:GetHeaderButton("EllesmereUIBags_Alts"))
        ns.db.settings.ui.headerButton = true
        ns.SettingsChanged()
        local btn = Ext:GetHeaderButton("EllesmereUIBags_Alts")
        assert.is_true(btn:IsShown())
        btn:Click()
        assert.is_true(ns.Browser:IsShown())
        btn:Click()
        assert.is_false(ns.Browser:IsShown())
        ns.db.settings.ui.headerButton = false
        ns.SettingsChanged()
        assert.is_false(btn:IsShown())
    end)

    it("explains itself when EUI Bags is missing", function()
        local env, ns = wow.boot(wow.defaultState())
        ns.db.settings.ui.headerButton = true
        ns.SettingsChanged()
        assert.truthy(table.concat(env.__chat, "\n"):find("/alts", 1, true))
        assert.are.same({}, env.__errors)
    end)
end)

describe("Browser", function()
    -- Alice (with warband bank) and Bob, then Alice logs in again with EUI loaded.
    local function world()
        local env = bootWithEUI(nil, richWorld())
        env.__state.bankTabs[2] = { { ID = 12, name = "Mats" } }
        env.__state.bags[12] = { size = 98, slots = {} }
        wow.putItem(env.__state, 12, 1, 190396, 500)
        env.FireEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 8)
        env.FireEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 8)
        local env2 = wow.relog(env, { name = "Bob", class = "WARRIOR" })
        wow.putItem(env2.__state, 0, 1, 2589, 3)
        env2.FireEvent("BAG_UPDATE", 0)
        env2.FireEvent("BAG_UPDATE_DELAYED")
        local rec
        local envA, nsA = wow.boot(richWorld(), wow.logout(env2), {
            beforeLoad = function(e) rec = fakeEUI.install(e) end,
        })
        return envA, nsA, rec
    end

    it("is not built before the first open (zero cost unless used)", function()
        local env = wow.boot(wow.defaultState())
        assert.is_nil(env.EllesmereUIBagsAltsBrowser)
    end)

    it("lists characters, warband and renders the selected character's bags", function()
        local env, ns = world()
        env.Slash("")
        local f = env.EllesmereUIBagsAltsBrowser
        assert.is_true(f:IsShown())
        local rows = {}
        for i = 1, f.sideRows.used do rows[#rows + 1] = f.sideRows.items[i].ownerKey end
        assert.are.same({ "Alice-Blackhand", "Bob-Blackhand", "#warband" }, rows)
        assert.are.equal("Alice-Blackhand", ns.Browser:GetState().owner)
        assert.are.equal(4, f.grid.used)
        -- the rich link survives into the button reference
        local found = false
        for i = 1, f.grid.used do
            if f.grid.buttons[i].ref:find("10256", 1, true) then found = true end
        end
        assert.is_true(found)
        assert.are.same({}, env.__errors)
    end)

    it("switches owners and tabs", function()
        local env, ns = world()
        ns.Browser:Open()
        local f = env.EllesmereUIBagsAltsBrowser
        ns.Browser:Select("#warband")
        assert.are.equal(1, f.grid.used)
        assert.are.equal("190396,500", "190396," .. f.grid.buttons[1].__count)
        ns.Browser:Select("Bob-Blackhand")
        assert.are.equal(1, f.grid.used)
        ns.Browser:SelectTab("bank")
        assert.are.equal(0, f.grid.used)
        assert.truthy(f.empty.text:find("banker", 1, true))
        ns.Browser:SelectTab("currency")
        assert.are.equal(0, f.currencies.used)
    end)

    it("groups by EUI categories when enabled", function()
        local env, ns = world()
        ns.db.settings.ui.useEUICategories = true
        ns.Browser:Open()
        local f = env.EllesmereUIBagsAltsBrowser
        local titles = {}
        for i = 1, f.grid.usedHeaders do titles[#titles + 1] = f.grid.headers[i].text end
        assert.are.same({ "Weapons / Trinkets", "Armor", "Trade Goods", "Miscellaneous" }, titles)
    end)

    it("searches all characters and loads missing item data event driven", function()
        local env, ns = world()
        env.__state.uncachedItems = { [190396] = true }
        ns.Browser:OpenSearch("ore")
        local f = env.EllesmereUIBagsAltsBrowser
        assert.are.equal(0, f.results.used)
        assert.truthy(f.empty.text:find("loading", 1, true))
        env.ProcessQueue()          -- ITEM_DATA_LOAD_RESULT arrives
        env.RunOnUpdates()          -- coalesced one-shot refresh
        assert.are.equal(1, f.results.used)
        assert.are.equal(190396, f.results.items[1].itemID)
        assert.truthy(f.results.items[1].detail.text:find("Warband", 1, true))
        assert.is_nil(f:GetScript("OnUpdate"))   -- one-shot removed itself

        ns.Browser:SetQuery("cloth")
        assert.are.equal(1, f.results.used)
        assert.are.equal("23", f.results.items[1].total.text)   -- 20 Alice + 3 Bob
        ns.Browser:SetQuery("q:epic")
        assert.are.equal(1, f.results.used)
        ns.Browser:SetQuery("id:6948")
        assert.are.equal(1, f.results.used)
        ns.Browser:SetQuery("nothing-like-this")
        assert.are.equal(0, f.results.used)
        assert.are.same({}, env.__errors)
    end)

    it("listens for item data only while shown", function()
        local _, ns = world()
        ns.Browser:Open()
        assert.is_true(ns.IsEventRegistered(ns.Browser, "ITEM_DATA_LOAD_RESULT"))
        ns.Browser:Close()
        assert.is_false(ns.IsEventRegistered(ns.Browser, "ITEM_DATA_LOAD_RESULT"))
    end)

    it("refreshes on data changes only once per burst and lazily while hidden", function()
        local env, ns = world()
        ns.Browser:Open()
        local renders = 0
        local orig = ns.Browser.Refresh
        ns.Browser.Refresh = function(self) renders = renders + 1; return orig(self) end
        for _ = 1, 10 do ns.Fire("CHAR_UPDATED", "Alice-Blackhand", "bags") end
        env.RunOnUpdates()
        assert.are.equal(1, renders)
        ns.Browser:Close()
        ns.Fire("CHAR_UPDATED", "Alice-Blackhand", "bags")
        env.RunOnUpdates()
        assert.are.equal(1, renders)
        ns.Browser:Open()
        assert.are.equal(2, renders)
        ns.Browser.Refresh = orig
    end)

    it("links items on shift-click and shows item tooltips", function()
        local env, ns = world()
        ns.Browser:Open()
        local f = env.EllesmereUIBagsAltsBrowser
        local b = f.grid.buttons[1]
        b:RunScript("OnEnter")
        assert.are.equal(b, env.GameTooltip.owner)
        b:Click()
        assert.are.equal(0, #env.__clicks)            -- plain click does nothing
        env.__state.modifiers.shift = true
        b:Click()
        assert.are.equal(1, #env.__clicks)
    end)

    it("deletes another character after confirmation, never the current one", function()
        local env, ns, rec = world()
        ns.Browser:Open()
        local f = env.EllesmereUIBagsAltsBrowser
        assert.is_false(f.delete:IsShown())           -- current character
        ns.Browser:Select("Bob-Blackhand")
        assert.is_true(f.delete:IsShown())
        f.delete:Click()
        rec.popups[#rec.popups].onConfirm()
        assert.is_nil(ns.db.chars["Bob-Blackhand"])
        assert.are.equal("Alice-Blackhand", ns.Browser:GetState().owner)
        ns.Index:EnsureBuilt()
        assert.are.equal(20, ns.Index:GetTotal(2589))
    end)
end)
