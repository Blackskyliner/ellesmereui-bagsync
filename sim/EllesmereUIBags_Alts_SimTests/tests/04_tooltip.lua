local ns = EllesmereUIBagsAlts._ns

local function lines()
    local out = {}
    for i = 1, GameTooltip:NumLines() do
        local l = _G["GameTooltipTextLeft" .. i]
        local r = _G["GameTooltipTextRight" .. i]
        out[#out + 1] = (l and l:GetText() or "") .. " | " .. (r and r:GetText() or "")
    end
    return table.concat(out, "\n")
end

-- The simulator's C_TooltipInfo.GetItemByID returns item data without id,
-- hyperlink or guid (the client always sets id; see Blizzard's
-- TooltipUtil.GetDisplayedItem). So the tests feed ProcessInfo tooltip data in
-- the client's shape and run Blizzard's real pipeline (pre-calls, ProcessLines,
-- TooltipDataProcessor post-calls) from there.
local function itemTooltipInfo(itemID, name)
    return { tooltipData = { type = Enum.TooltipDataType.Item, id = itemID,
        lines = { { type = 0, leftText = name, leftColor = CreateColor(1, 1, 1) } } } }
end

simtest("tooltip counts appear through the real TooltipDataProcessor once enabled", function()
    A_Admin.AddBagItem(0, 2, 2589, 7)
    A_Admin.FireEvent("BAG_UPDATE", 0)
    A_Admin.FireEvent("BAG_UPDATE_DELAYED")
    -- a second, offline character that owns the same item
    local other = ns.GetChar("Othertwink-" .. ns.GetPlayerRealm(), true)
    other.name, other.realm, other.class = "Othertwink", ns.GetPlayerRealm(), "WARRIOR"
    other.bags[0] = { size = 16, items = { [1] = "2589,5" } }
    ns.Index:Invalidate()

    ns.db.settings.tooltip.enabled = true
    ns.SettingsChanged()
    assertTrue(ns.IsFeatureActive("tooltip"))

    -- Blizzard's own Lua pipeline (TooltipDataHandlerMixin:ProcessInfo), which is
    -- what GameTooltip:SetItemByID/SetHyperlink run in the client.
    GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    GameTooltip:ProcessInfo(itemTooltipInfo(2589, "Linen Cloth"))
    local text = lines()
    assertContains(text, "Othertwink")
    assertContains(text, "Bags: 5")
    GameTooltip:Hide()
end)

simtest("tooltip adds nothing once disabled again", function()
    ns.db.settings.tooltip.enabled = false
    ns.SettingsChanged()
    GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    GameTooltip:ProcessInfo(itemTooltipInfo(2589, "Linen Cloth"))
    local text = lines()
    assertTrue(not text:find("Othertwink", 1, true))
    GameTooltip:Hide()
end)
