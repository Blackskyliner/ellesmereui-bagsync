-------------------------------------------------------------------------------
--  UI/HeaderButton.lua   (opt-in, default OFF)
--  A small button in the EllesmereUI bag header that opens the browser.
--  Placement goes through the extension layer (EUIBagsExt), which only
--  parents our own button to the header -- nothing is written onto EUI frames.
-------------------------------------------------------------------------------
local _, ns = ...
local L = ns.L
local Ext = _G.EllesmereUIBagsExt

local KEY = "EllesmereUIBags_Alts"

ns.RegisterFeature({
    key = "headerButton",
    eager = true,     -- clicking it opens the browser, which activates
    IsEnabled = function(s) return s.ui.headerButton end,
    OnEnable = function()
        local placed = Ext:RegisterHeaderButton(KEY, {
            icon = "Interface\\Icons\\INV_Misc_GroupNeedMore",
            tooltip = L["Alts: browse all characters"],
            order = 10,
            onClick = function() ns.Browser:Toggle() end,
        })
        if not placed then
            ns.Print(L["EllesmereUI Bags is not loaded; the bag button is unavailable. Use /alts instead."])
        end
        Ext:SetHeaderButtonShown(KEY, true)
    end,
    OnDisable = function()
        Ext:SetHeaderButtonShown(KEY, false)
    end,
})
