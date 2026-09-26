local wow = require("wow")
local fakeEUI = require("fake_eui")

local function readAll(path)
    local fh = assert(io.open(path))
    local s = fh:read("*a")
    fh:close()
    return s
end

-- Source without comments, so prose mentioning an API never trips a check.
local function stripComments(s)
    s = s:gsub("%-%-%[%[.-%]%]", "")
    s = s:gsub("%-%-[^\n]*", "")
    return s
end

local function addonSources()
    local out = {}
    local p = io.popen('find "' .. wow.ROOT .. '/EllesmereUIBags_Alts" -name "*.lua"')
    for path in p:lines() do out[path:match("EllesmereUIBags_Alts/.*$")] = stripComments(readAll(path)) end
    p:close()
    return out
end

describe("Options", function()
    it("registers a settings category with every setting wired to the DB", function()
        local env, ns = wow.boot(wow.defaultState())
        local cat = env.__settingsRegistered
        assert.is_table(cat)
        local expected = { "tooltip_enabled", "tooltip_modifier", "tooltip_realmScope", "tooltip_showTotal",
            "tooltip_hideCurrent", "tooltip_showWarband", "tooltip_showGuild", "ui_headerButton",
            "ui_useEUICategories", "collect_bags", "collect_equipped", "collect_bank", "collect_mail",
            "collect_currency", "collect_guildbank" }
        for _, v in ipairs(expected) do assert.is_table(cat.settings["EUIALTS_" .. v], v) end
        local setting = cat.settings.EUIALTS_tooltip_enabled
        assert.is_false(setting:GetValue())
        setting:SetValue(true)
        assert.is_true(ns.db.settings.tooltip.enabled)
        assert.is_true(ns.featureByKey.tooltip.active)
        assert.are.equal(1, #env.__postCalls)
    end)

    it("offers the documented dropdown choices", function()
        local env = wow.boot(wow.defaultState())
        local values = {}
        for _, c in ipairs(env.__settingsCategory.controls) do
            if c.kind == "dropdown" then
                local list = {}
                for _, o in ipairs(c.options) do list[#list + 1] = o.value end
                values[c.setting.variable] = table.concat(list, ",")
            end
        end
        assert.are.equal("none,shift,ctrl,alt", values.EUIALTS_tooltip_modifier)
        assert.are.equal("connected,realm,all", values.EUIALTS_tooltip_realmScope)
    end)

    it("handles slash commands", function()
        local env, ns = wow.boot(wow.defaultState())
        env.Slash("tooltip")
        assert.is_true(ns.db.settings.tooltip.enabled)
        env.Slash("status")
        assert.truthy(table.concat(env.__chat, "\n"):find("active features", 1, true))
        env.Slash("search cloth")
        assert.is_true(ns.Browser:IsShown())
        assert.are.equal("cloth", ns.Browser:GetState().queryText)
        env.Slash("")
        assert.is_false(ns.Browser:IsShown())
        env.Slash("options")
        assert.are.equal(42, env.__settingsOpened)
        env.Slash("delete Nobody")
        assert.truthy(env.__chat[#env.__chat]:find("Unknown character", 1, true))
        env.Slash("delete alice")
        assert.truthy(env.__chat[#env.__chat]:find("cannot be deleted", 1, true))
        env.Slash("help")
        assert.truthy(env.__chat[#env.__chat]:find("/alts", 1, true))
        assert.are.same({}, env.__errors)
    end)

    it("with EUI, asks once at the first bag open; accepting enables tooltip and header button", function()
        local rec
        local env, ns = wow.boot(wow.defaultState(), nil, { beforeLoad = function(e) rec = fakeEUI.install(e) end })
        assert.are.equal(0, #rec.popups)                       -- no clash with EUI's login popups
        assert.truthy(table.concat(env.__chat, "\n"):find("/alts", 1, true))
        env.EUI_Bags:Show()
        assert.are.equal(1, #rec.popups)
        env.EUI_Bags:Hide()
        env.EUI_Bags:Show()
        assert.are.equal(1, #rec.popups)                       -- asked exactly once
        assert.is_false(ns.db.settings.tooltip.enabled)       -- nothing before consent
        rec.popups[1].onConfirm()
        assert.is_true(ns.db.settings.tooltip.enabled)
        assert.is_true(ns.db.settings.ui.headerButton)
        assert.is_table(env.EllesmereUIBagsExt:GetHeaderButton("EllesmereUIBags_Alts"))
        local rec2
        local sv = wow.logout(env)
        local env2 = wow.boot(wow.defaultState(), sv, { beforeLoad = function(e) rec2 = fakeEUI.install(e) end })
        env2.EUI_Bags:Show()
        assert.are.equal(0, #rec2.popups)                      -- never asked again
    end)

    it("declining the first-run prompt leaves everything off", function()
        local env, ns = wow.boot(wow.defaultState())
        local popup = env.EllesmereUIBagsExtPopup
        assert.is_true(popup:IsShown())
        popup.cancel:Click()
        assert.is_false(ns.db.settings.tooltip.enabled)
        assert.is_false(ns.db.settings.ui.headerButton)
        assert.is_true(ns.db.settings.firstRunAsked)
    end)
end)

describe("Self-test", function()
    it("passes when stored data matches the game", function()
        local s = wow.defaultState()
        wow.putItem(s, 0, 1, 2589, 20)
        wow.putItem(s, 1, 1, 2589, 5)
        s.equipped[16] = { id = 19019, link = wow.itemLink(19019) }
        local env, ns = wow.boot(s)
        local ok, report = ns.RunSelfTest(true)
        assert.is_true(ok)
        assert.are.equal(0, #report.missingAPIs)
        assert.are.equal(2, report.countsChecked)
        assert.is_true(report.indexConsistent)
        assert.truthy(table.concat(env.__chat, "\n"):find("OK", 1, true))
    end)

    it("reports mismatches and a corrupted incremental index", function()
        local s = wow.defaultState()
        wow.putItem(s, 0, 1, 2589, 20)
        local env, ns = wow.boot(s)
        ns.Index:EnsureBuilt()
        ns.Index.data[2589]["Alice-Blackhand"].bags = 999        -- simulate drift
        ns.GetPlayerChar().bags[0].items[1] = "2589,19"           -- stored differs from game
        local ok, report = ns.RunSelfTest(false)
        assert.is_false(ok)
        assert.are.equal(1, #report.countMismatches)
        assert.is_false(report.indexConsistent)
        local _ = env
    end)
end)

describe("Acceptance criteria", function()
    describe("1: zero cost unless enabled", function()
        it("creates no frames at load beyond the event dispatcher", function()
            local env = wow.newEnv(wow.defaultState())
            local baseline = #env.__frames
            wow.loadAddon(env)
            assert.are.equal(baseline + 1, #env.__frames)
        end)

        it("with every optional feature off, only the always-on collectors listen", function()
            local env, ns = wow.boot(wow.defaultState())
            local popup = env.EllesmereUIBagsExtPopup
            if popup then popup.cancel:Click() end
            for k in pairs(ns.db.settings.collect) do ns.db.settings.collect[k] = false end
            ns.SettingsChanged()
            assert.are.same({ "PLAYER_GUILD_UPDATE", "PLAYER_LEVEL_UP", "PLAYER_LOGOUT", "PLAYER_MONEY" },
                ns.GetRegisteredEvents())
            assert.are.equal(0, #env.__postCalls)
            assert.is_nil(env.EllesmereUIBagsAltsBrowser)
        end)

        it("default install listens only to cheap signals (no bank/mail/guild item events)", function()
            local _, ns = wow.boot(wow.defaultState())
            local ev = {}
            for _, e in ipairs(ns.GetRegisteredEvents()) do ev[e] = true end
            for _, forbidden in ipairs({ "MAIL_INBOX_UPDATE", "GUILDBANKBAGSLOTS_CHANGED", "ITEM_DATA_LOAD_RESULT",
                "ACCOUNT_MONEY", "BANK_TABS_CHANGED", "PLAYER_REGEN_ENABLED" }) do
                assert.is_nil(ev[forbidden], forbidden)
            end
        end)
    end)

    describe("3: low cost when enabled", function()
        local sources = addonSources()

        it("never uses C_Timer and never polls with OnUpdate", function()
            for rel, s in pairs(sources) do
                assert.is_nil(s:find("C_Timer", 1, true), rel)
                if not rel:find("UI/Browser.lua", 1, true) then
                    assert.is_nil(s:find("OnUpdate", 1, true), rel)
                end
            end
        end)

        it("the browser's only OnUpdate is a self-removing one-shot", function()
            local env, ns = wow.boot(wow.defaultState())
            ns.Browser:Open()
            ns.Fire("CHAR_UPDATED", "x", "bags")
            local f = env.EllesmereUIBagsAltsBrowser
            assert.is_function(f:GetScript("OnUpdate"))
            env.RunOnUpdates()
            assert.is_nil(f:GetScript("OnUpdate"))
        end)

        it("scans each dirty bag once per burst", function()
            local env, ns = wow.boot(wow.defaultState())
            local n = 0
            local orig = env.C_Container.GetContainerItemInfo
            env.C_Container.GetContainerItemInfo = function(...) n = n + 1 return orig(...) end
            for _ = 1, 50 do env.FireEvent("BAG_UPDATE", 0) end
            env.FireEvent("BAG_UPDATE_DELAYED")
            assert.are.equal(env.__state.bags[0].size, n)
            local _ = ns
        end)
    end)

    describe("4: zero taint risk (static)", function()
        local sources = addonSources()

        it("never replaces scripts on frames it does not own", function()
            for rel, s in pairs(sources) do
                for target in s:gmatch("([%w_%.]+):SetScript%(") do
                    assert.is_nil(target:find("EUI_", 1, true), rel .. ": " .. target)
                    assert.is_nil(target:find("GameTooltip", 1, true), rel .. ": " .. target)
                    assert.is_nil(target:find("Header", 1, true), rel .. ": " .. target)
                    assert.is_nil(target:find("bags", 1, true), rel .. ": " .. target)
                end
            end
        end)

        it("never writes fields onto EUI or Blizzard frames", function()
            for rel, s in pairs(sources) do
                assert.is_nil(s:match("EUI_Bags%.[%w_]+%s*=[^=]"), rel)
                assert.is_nil(s:match("header%.[%w_]+%s*=[^=]"), rel)
                assert.is_nil(s:match("GameTooltip%.[%w_]+%s*=[^=]"), rel)
                assert.is_nil(s:match("%f[%w_%.]tooltip%.[%w_]+%s*=[^=]"), rel)
            end
        end)

        it("uses no secure templates, StaticPopup or protected container actions", function()
            for rel, s in pairs(sources) do
                for _, bad in ipairs({ "ContainerFrameItemButtonTemplate", "SecureActionButtonTemplate", "StaticPopup_Show",
                    "UseContainerItem", "PickupContainerItem", "SplitContainerItem", "SetOverrideBinding" }) do
                    assert.is_nil(s:find(bad, 1, true), rel .. ": " .. bad)
                end
            end
        end)

        it("hooks Blizzard functions only post-hoc (hooksecurefunc)", function()
            local found = false
            for _, s in pairs(sources) do
                if s:find('hooksecurefunc("SendMail"', 1, true) then found = true end
                assert.is_nil(s:find("_G%.SendMail%s*="), "SendMail must never be replaced")
                assert.is_nil(s:find("\nSendMail%s*="), "SendMail must never be replaced")
            end
            assert.is_true(found)
        end)
    end)

    describe("5: Midnight only", function()
        it("targets 12.x interface versions and avoids deprecated globals", function()
            local toc = readAll(wow.ROOT .. "/EllesmereUIBags_Alts/EllesmereUIBags_Alts.toc")
            local iface = toc:match("## Interface: ([%d, ]+)")
            for v in iface:gmatch("%d+") do assert.is_true(tonumber(v) >= 120000, v) end
            for rel, src in pairs(addonSources()) do
                -- pre-12 globals that Midnight moved into namespaces must only appear namespaced
                for _, fn in ipairs({ "GetContainerItemInfo", "GetContainerNumSlots", "GetItemInfo",
                    "GetCurrencyListInfo", "GetAutoCompleteRealms", "GetItemCount" }) do
                    for pre in src:gmatch("([%w_%.:]*)" .. fn .. "%(") do
                        assert.truthy(pre:match("^C_[%w_]+%.$") or pre == "self." or pre:match("^[%w_]+%.$"),
                            rel .. ": un-namespaced " .. pre .. fn)
                    end
                end
                for _, gone in ipairs({ "ReagentBank", "BankFrame_", "REAGENTBANK", "GetNumBankSlots" }) do
                    assert.is_nil(src:find(gone, 1, true), rel .. ": " .. gone)
                end
            end
        end)
    end)
end)

describe("SavedVariables", function()
    it("serialize like the client and stay compact for a large account", function()
        local env, ns = wow.boot(wow.defaultState())
        -- 40 characters with full bags (5 x 36 slots) and 2 full bank tabs
        for c = 1, 40 do
            local ch = ns.GetChar("Alt" .. c .. "-Blackhand", true)
            ch.class = "MAGE"
            for bag = 0, 4 do
                ch.bags[bag] = { size = 36, items = {} }
                for slot = 1, 36 do ch.bags[bag].items[slot] = ns.EncodeItem(2589 + (slot % 5), slot) end
            end
            for tab = 6, 7 do
                ch.bank[tab] = { size = 98, items = {} }
                for slot = 1, 98 do ch.bank[tab].items[slot] = ns.EncodeItem(190396, 1000) end
            end
        end
        local sv, bytes = wow.logout(env)
        assert.are.equal(41, (function() local n = 0 for _ in pairs(sv.chars) do n = n + 1 end return n end)())
        assert.is_true(bytes < 1500000, "SV size " .. bytes)
        local t0 = os.clock()
        local env2, ns2 = wow.boot(wow.defaultState(), sv)
        ns2.Index:EnsureBuilt()
        assert.is_true(os.clock() - t0 < 1.0)
        assert.are.equal(40 * 2 * 98 * 1000, ns2.Index:GetTotal(190396))
        assert.are.same({}, env2.__errors)
    end)
end)
