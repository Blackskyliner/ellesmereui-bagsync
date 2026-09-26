-- The proposed upstream file (upstream/EllesmereUIBags_ExtAPI.lua) loaded into
-- the fake EllesmereUI: the connector must switch to the native API.
local wow = require("wow")
local fakeEUI = require("fake_eui")

local function bootWithUpstream(opts)
    local rec
    local env, ns = wow.boot(wow.defaultState(), nil, {
        beforeLoad = function(env)
            rec = fakeEUI.install(env, opts)
            local chunk = assert(loadfile(wow.ROOT .. "/upstream/EllesmereUIBags_ExtAPI.lua"))
            setfenv(chunk, env)
            chunk("EllesmereUIBags", env.EllesmereUI._ModuleNS["EllesmereUIBags"])
        end,
    })
    return env, ns, rec
end

describe("Upstream EllesmereUIBags_ExtAPI", function()
    it("defines only functions: no frames, hooks or events until used", function()
        local env = wow.newEnv(wow.defaultState())
        fakeEUI.install(env)
        local before = #env.__frames
        local chunk = assert(loadfile(wow.ROOT .. "/upstream/EllesmereUIBags_ExtAPI.lua"))
        setfenv(chunk, env)
        chunk("EllesmereUIBags", env.EllesmereUI._ModuleNS["EllesmereUIBags"])
        assert.are.equal(before, #env.__frames)
        assert.is_nil(env.EUI_Bags.hooks.OnShow)
        assert.are.equal(1, env.EUI_Bags.extAPIVersion)
    end)

    it("is picked up by the connector, which stops using its shim", function()
        local env, ns = bootWithUpstream()
        local Ext = env.EllesmereUIBagsExt
        assert.are.equal(1, Ext:GetNativeAPIVersion())
        ns.db.settings.ui.headerButton = true
        ns.SettingsChanged()
        assert.is_nil(Ext:GetHeaderButton("EllesmereUIBags_Alts"))   -- not the shim
        -- the native button sits right after the item count
        local header = env.EUI_Bags.Header
        local native
        for _, child in ipairs(header.children) do
            if child.__type == "Button" then native = child end
        end
        assert.is_table(native)
        local p, rel = native:GetPoint(1)
        assert.are.equal("LEFT", p)
        assert.are.equal(header.itemCount, rel)
        native:Click()
        assert.is_true(ns.Browser:IsShown())
        ns.db.settings.ui.headerButton = false
        ns.SettingsChanged()
        assert.is_false(native:IsShown())
        assert.are.same({}, env.__errors)
    end)

    it("defers native buttons to the first bag open when the header is built late", function()
        local env, ns = bootWithUpstream({ lateHeader = true })
        ns.db.settings.ui.headerButton = true
        ns.SettingsChanged()
        fakeEUI.createHeader()
        env.EUI_Bags:Show()
        local found = false
        for _, child in ipairs(env.EUI_Bags.Header.children) do
            if child.__type == "Button" then found = true end
        end
        assert.is_true(found)
    end)

    it("skins item buttons natively", function()
        local env, _, rec = bootWithUpstream()
        local btn = env.CreateFrame("ItemButton")
        assert.is_true(env.EllesmereUIBagsExt:SkinItemButton(btn))
        assert.is_true(rec.skinned[btn].flatHighlight)
        assert.is_true(env.EllesmereUIBagsExt:SetItemBorderColor(btn, 0, 1, 0))
        assert.are.same({ 0, 1, 0, 1 }, rec.borders[btn])
    end)
end)
