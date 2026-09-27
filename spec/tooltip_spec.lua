local wow = require("wow")

-- Alice (Blackhand) and Bob (Blackhand) and Carl (Antonidas, not connected),
-- plus warband bank and a guild bank.
local function multiCharWorld()
    local s1 = wow.defaultState()
    wow.putItem(s1, 0, 1, 2589, 20)
    s1.bankTabs[2] = { { ID = 12, name = "Mats" } }
    s1.bags[12] = { size = 98, slots = {} }
    wow.putItem(s1, 12, 1, 2589, 100)
    s1.guild = { name = "Knights", money = 1, tabs = { { name = "T1", slots = { [1] = { id = 2589, count = 7 } } } } }
    local env, ns = wow.boot(s1)
    ns.db.settings.collect.guildbank = true
    ns.SettingsChanged()
    env.FireEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 8)
    env.FireEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 8)
    env.FireEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 10)
    env.ProcessQueue()
    env.FireEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 10)

    local env2 = wow.relog(env, { name = "Bob", class = "WARRIOR" })
    wow.putItem(env2.__state, 0, 2, 2589, 5)
    env2.FireEvent("BAG_UPDATE", 0)
    env2.FireEvent("BAG_UPDATE_DELAYED")

    local env3 = wow.relog(env2, { name = "Carl", realm = "Antonidas", realmName = "Antonidas" })
    wow.putItem(env3.__state, 0, 3, 2589, 3)
    env3.FireEvent("BAG_UPDATE", 0)
    env3.FireEvent("BAG_UPDATE_DELAYED")

    return wow.relog(env3, { name = "Alice" }, { bags = s1.bags })
end

local function tooltipLines(env, itemID)
    local tt = env.GameTooltip
    tt:SetOwner(env.UIParent)
    tt:SetHyperlink("item:" .. itemID)
    return tt.lines
end

local function flatten(lines)
    local out = {}
    for _, l in ipairs(lines) do out[#out + 1] = table.concat(l, " | ") end
    return table.concat(out, "\n")
end

describe("Tooltip (opt-in)", function()
    it("registers no tooltip hook until enabled", function()
        local env, ns = wow.boot(wow.defaultState())
        assert.are.equal(0, #env.__postCalls)
        ns.db.settings.tooltip.enabled = true
        ns.SettingsChanged()
        assert.are.equal(1, #env.__postCalls)
        ns.db.settings.tooltip.enabled = false
        ns.SettingsChanged()
        ns.db.settings.tooltip.enabled = true
        ns.SettingsChanged()
        assert.are.equal(1, #env.__postCalls)   -- installed once, never twice
    end)

    it("lists characters, warband bank, guild bank and total within the realm scope", function()
        local env, ns = multiCharWorld()
        ns.db.settings.tooltip.enabled = true
        ns.SettingsChanged()
        local text = flatten(tooltipLines(env, 2589))
        assert.truthy(text:find("Alice", 1, true))
        assert.truthy(text:find("Bags: 20", 1, true))
        assert.truthy(text:find("Bob", 1, true))
        assert.truthy(text:find("Warband Bank|r | 100", 1, true))
        assert.truthy(text:find("Knights", 1, true))
        assert.truthy(text:find("Guild Bank: 7", 1, true))
        assert.falsy(text:find("Carl", 1, true))               -- Antonidas is not connected
        assert.truthy(text:find("Total | 132", 1, true))       -- 20 + 5 + 100 + 7
        assert.are.same({}, env.__errors)
    end)

    it("honours realm scope 'all', hideCurrent, warband/guild toggles and maxChars", function()
        local env, ns = multiCharWorld()
        local t = ns.db.settings.tooltip
        t.enabled, t.realmScope, t.hideCurrent, t.showWarband, t.showGuild, t.maxChars = true, "all", true, false, false, 1
        ns.SettingsChanged()
        local text = flatten(tooltipLines(env, 2589))
        assert.falsy(text:find("Alice", 1, true))
        assert.falsy(text:find("Warband", 1, true))
        assert.falsy(text:find("Knights", 1, true))
        assert.truthy(text:find("Carl-Antonidas", 1, true) or text:find("Bob", 1, true))
        assert.truthy(text:find("and 1 more", 1, true))
    end)

    it("waits for the configured modifier", function()
        local env, ns = multiCharWorld()
        ns.db.settings.tooltip.enabled = true
        ns.db.settings.tooltip.modifier = "shift"
        ns.SettingsChanged()
        assert.are.equal(0, #tooltipLines(env, 2589))
        env.__state.modifiers.shift = true
        assert.is_true(#tooltipLines(env, 2589) > 0)
    end)

    it("updates cached lines when counts change", function()
        local env, ns = multiCharWorld()
        ns.db.settings.tooltip.enabled = true
        ns.SettingsChanged()
        assert.truthy(flatten(tooltipLines(env, 2589)):find("Bags: 20", 1, true))
        wow.putItem(env.__state, 0, 1, 2589, 19)
        env.FireEvent("BAG_UPDATE", 0)
        env.FireEvent("BAG_UPDATE_DELAYED")
        assert.truthy(flatten(tooltipLines(env, 2589)):find("Bags: 19", 1, true))
    end)

    it("adds lines once per tooltip content and ignores foreign or secret tooltips", function()
        local env, ns = multiCharWorld()
        ns.db.settings.tooltip.enabled = true
        ns.SettingsChanged()
        local tt = env.GameTooltip
        tt:SetOwner(env.UIParent)
        tt:SetHyperlink("item:2589")
        local n = #tt.lines
        ns.OnTooltipItem(tt, { id = 2589 })          -- second post-call within the same build
        assert.are.equal(n, #tt.lines)
        tt:SetHyperlink("item:2589")                 -- refresh: new build, lines again
        assert.are.equal(n, #tt.lines)
        local foreign = env.CreateFrame("GameTooltip", "SomeAddonTooltip")
        ns.OnTooltipItem(foreign, { id = 2589 })
        assert.are.equal(0, #foreign.lines)
        tt:ProcessTooltipData(0, { type = 0, id = wow.Secret(2589) })
        assert.are.equal(0, #tt.lines)
        assert.are.same({}, env.__errors)
    end)

    it("shows nothing for items nobody owns and nothing when disabled", function()
        local env, ns = multiCharWorld()
        ns.db.settings.tooltip.enabled = true
        ns.SettingsChanged()
        assert.are.equal(0, #tooltipLines(env, 19019))
        ns.db.settings.tooltip.enabled = false
        ns.SettingsChanged()
        assert.are.equal(0, #tooltipLines(env, 2589))
    end)

    it("does not allocate on repeated tooltip shows (cached lines)", function()
        local env, ns = multiCharWorld()
        ns.db.settings.tooltip.enabled = true
        ns.SettingsChanged()
        local tt = env.GameTooltip
        tooltipLines(env, 2589)   -- warm the cache
        local build = 0
        local orig = ns.BuildTooltipLines
        local _ = orig
        -- count Index lookups as a proxy for rebuilds
        local get = ns.Index.Get
        ns.Index.Get = function(self, id) build = build + 1; return get(self, id) end
        for _ = 1, 200 do tt:SetHyperlink("item:2589") end
        ns.Index.Get = get
        assert.are.equal(0, build)
    end)

    -- Counts every Lua call into the addon's own files while fn runs.
    local function addonCalls(fn)
        local n = 0
        debug.sethook(function()
            local src = debug.getinfo(2, "S").source
            if src:find("EllesmereUIBags_Alts/", 1, true) then n = n + 1 end
        end, "c")
        fn()
        debug.sethook()
        return n
    end

    it("costs zero addon calls for unit and world tooltips, even while enabled (regression)", function()
        local env, ns = multiCharWorld()
        ns.db.settings.tooltip.enabled = true
        ns.SettingsChanged()
        assert.is_nil(env.GameTooltip.hooks.OnTooltipCleared)       -- no clear hook
        for _, pc in ipairs(env.__postCalls) do assert.are.equal(0, pc[1]) end   -- Item type only
        local tt = env.GameTooltip
        tt:SetOwner(env.UIParent)
        local calls = addonCalls(function()
            for _ = 1, 1000 do tt:SetUnit("mouseover") end           -- 200 s of looking at an NPC
        end)
        assert.are.equal(0, calls)
    end)

    it("an item tooltip refresh only reads the cache (no counting, no allocation per refresh)", function()
        local env, ns = multiCharWorld()
        ns.db.settings.tooltip.enabled = true
        ns.SettingsChanged()
        local tt = env.GameTooltip
        tt:SetOwner(env.UIParent)
        tt:SetHyperlink("item:2589")                                  -- first show builds the lines
        local get, class = ns.Index.Get, env.C_ClassColor.GetClassColor
        local counted = 0
        ns.Index.Get = function(...) counted = counted + 1 return get(...) end
        env.C_ClassColor.GetClassColor = function(...) counted = counted + 1 return class(...) end
        local calls = addonCalls(function()
            for _ = 1, 1000 do tt:SetHyperlink("item:2589") end
        end)
        ns.Index.Get, env.C_ClassColor.GetClassColor = get, class
        assert.are.equal(0, counted)                                  -- nothing recounted
        assert.is_true(calls <= 1000 * 6, "calls per refresh: " .. calls / 1000)
    end)

    it("does not add counts to item tooltips of world objects", function()
        local env, ns = multiCharWorld()
        ns.db.settings.tooltip.enabled = true
        ns.SettingsChanged()
        local tt = env.GameTooltip
        tt:SetOwner(env.UIParent)
        tt:ProcessTooltipData(0, { type = 0, id = 2589, worldLootObjectGUID = "WorldLootObject-1" })
        assert.are.equal(0, #tt.lines)
        tt:ProcessTooltipData(0, { type = 0, id = 2589, guid = "GameObject-0-1-2-3-4" })
        assert.are.equal(0, #tt.lines)
        tt:ProcessTooltipData(0, { type = 0, id = 2589, guid = "Item-1-0-4000000123456789" })
        assert.is_true(#tt.lines > 0)                                 -- a real item (bag slot) still works
        assert.are.same({}, env.__errors)
    end)
end)
