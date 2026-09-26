-- Only meaningful in `sim-test.sh upstream`: the real EUI Bags module carries
-- upstream/EllesmereUIBags_ExtAPI.lua and the connector must delegate to it.
local ns = EllesmereUIBagsAlts._ns

if not (EUI_Bags and EUI_Bags.extAPIVersion) then
    simtest("native EUI extension API absent: connector uses its shim", function()
        assertEquals(0, EllesmereUIBagsExt:GetNativeAPIVersion())
    end)
    return
end

simtest("native EUI extension API is detected", function()
    assertEquals(1, EllesmereUIBagsExt:GetNativeAPIVersion())
end)

simtest_when(function() return EUI_Bags.Header ~= nil end, "header button comes from EUI's native API", function()
    ns.db.settings.ui.headerButton = true
    ns.SettingsChanged()
    ToggleAllBags()
    assertNil(EllesmereUIBagsExt:GetHeaderButton("EllesmereUIBags_Alts"))
    local native
    for _, child in ipairs({ EUI_Bags.Header:GetChildren() }) do
        local p, rel = child:GetPoint(1)
        if rel == EUI_Bags.Header.itemCount and p == "LEFT" then native = child end
    end
    assertNotNil(native)
    native:Click()
    assertTrue(_G.EllesmereUIBagsAltsBrowser:IsShown())
    native:Click()
    ns.db.settings.ui.headerButton = false
    ns.SettingsChanged()
    assertTrue(not native:IsShown())
    ToggleAllBags()
end)

simtest("item buttons are skinned through the native API", function()
    local btn = CreateFrame("ItemButton", nil, UIParent)
    assertTrue(EllesmereUIBagsExt:SkinItemButton(btn))
    assertTrue(EllesmereUIBagsExt:SetItemBorderColor(btn, 0, 1, 0, 1))
end)
