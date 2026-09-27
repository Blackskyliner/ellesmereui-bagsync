--------------------------------------------------------------------------------
--  spec/helpers/fake_eui.lua
--  Minimal stand-in for the EllesmereUI surfaces the connector touches, with
--  the same names and signatures as the real code (checked by
--  scripts/check-api.py against the EllesmereUI source).
--------------------------------------------------------------------------------
local M = {}

function M.install(env, opts)
    opts = opts or {}
    local rec = { skins = {}, tooltips = {}, popups = {}, skinned = {}, borders = {} }
    local S = {}
    for _, prim in ipairs({ "Shell", "Panel", "Button", "WhiteButtonLabel", "EditBox", "ScrollBar", "CloseButton", "Tab" }) do
        S[prim] = function(frame) table.insert(rec.skins, { prim, frame }) end
    end
    S.GetAccentColor = function() return 1, 0.5, 0 end

    local EUI = {
        _skinRegistry = {},
        _ModuleNS = {},
        -- Without EUI's Blizzard skin module (opts.noSkin) the core only
        -- queues the registration and the callback never fires.
        RegisterSkin = function(name, fn)
            if opts.skinThrows then error("boom") end
            table.insert(rec.skins, { "register", name })
            if not opts.noSkin then fn(S) end
            return true
        end,
        GetFontPath = function(key) return "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.ttf", key end,
        GetFontOutlineFlag = function() return "OUTLINE" end,
        GetAccentColor = function() return 0.1, 0.2, 0.3 end,
        L = function(s) return s end,
        PanelPP = { mult = 1, CreateBorder = function(frame, r, g, b, a)
            rec.borders[frame] = { r, g, b, a }
        end },
        ShowWidgetTooltip = function(owner, text) table.insert(rec.tooltips, { owner, text }) end,
        HideWidgetTooltip = function() rec.tooltipHidden = true end,
    }
    function EUI:ShowConfirmPopup(o) table.insert(rec.popups, o) end
    EUI._ModuleNS["EllesmereUIBags"] = {
        SkinItemButton = function(btn, o) rec.skinned[btn] = o; return {} end,
        SetInsetBorderColor = function(btn, r, g, b, a) rec.borders[btn] = { r, g, b, a } end,
    }
    env.EllesmereUI = EUI

    -- EUI_Bags: global frame; the header exists after EUI's StartAddon.
    local bags = env.CreateFrame("Frame", "EUI_MainBagFrame", env.UIParent)
    bags:Hide()
    env.EUI_Bags = bags
    function M.createHeader()
        local header = env.CreateFrame("Frame", nil, bags)
        header.title = header:CreateFontString(nil, "OVERLAY")
        header.itemCount = header:CreateFontString(nil, "OVERLAY")
        bags.Header = header
        bags._searchBox = env.CreateFrame("EditBox", "EUI_BagSearchBox", header)
        return header
    end
    if not opts.lateHeader then M.createHeader() end

    env.EUI_CategoryManager = {
        GetCategories = function() return {
            { name = "Weapons / Trinkets" }, { name = "Armor" }, { name = "Trade Goods" }, { name = "Miscellaneous" },
        } end,
        ClassifyItem = function(_, link, itemID)
            if opts.classifyThrows then error("classify failed") end
            if not link then return nil end
            if itemID == 19019 then return 1 end
            if itemID == 230000 then return 2 end
            if itemID == 2589 or itemID == 2592 or itemID == 190396 then return 3 end
            return 4
        end,
    }
    return rec
end

return M
