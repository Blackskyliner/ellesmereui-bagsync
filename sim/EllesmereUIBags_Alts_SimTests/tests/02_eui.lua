-- Real EllesmereUI (core + Bags) is loaded next to the addon (scripts/sim-test.sh);
-- `sim-test.sh noeui` runs the fallback branch instead.
local Ext = EllesmereUIBagsExt

if not EllesmereUI then
    simtest("without EllesmereUI the connector reports absence and falls back", function()
        assertTrue(not Ext:IsEUILoaded())
        assertTrue(not Ext:IsBagsLoaded())
        assertTrue(not Ext:SkinItemButton(CreateFrame("ItemButton", nil, UIParent)))
        local path = Ext:GetFont("bags")
        assertEquals(STANDARD_TEXT_FONT, path)
        assertTrue(not Ext:RegisterHeaderButton("x", {}))
    end)
    return
end

simtest("EllesmereUI and its Bags module are present", function()
    assertNotNil(EllesmereUI)
    assertNotNil(EUI_Bags)
    assertTrue(Ext:IsEUILoaded())
    assertTrue(Ext:IsBagsLoaded())
end)

simtest_when(function() return EUI_Bags and EUI_Bags.Header ~= nil end, "EUI bag header exists (built 0.5 s after login) with the anchors the connector uses", function()
    local header = EUI_Bags.Header
    assertNotNil(header)
    assertNotNil(header.itemCount)
    assertNotNil(EUI_Bags._searchBox)
end)

simtest("connector reads EUI looks through the real functions", function()
    local path, flag = Ext:GetFont("bags")
    assertType("string", path)
    assertType("string", flag)
    local r, g, b = Ext:GetAccentColor()
    assertType("number", r); assertType("number", g); assertType("number", b)
    assertEquals("Inventory", Ext:L("Inventory"))
end)

simtest("connector skins a plain ItemButton with EUI's slot look", function()
    local btn = CreateFrame("ItemButton", nil, UIParent)
    assertTrue(Ext:SkinItemButton(btn))
    assertTrue(Ext:SetItemBorderColor(btn, 1, 0, 0, 1))
    assertEquals(34, math.floor(btn:GetWidth() + 0.5))
end)

simtest("connector classifies items with EUI's category manager", function()
    local idx, name = Ext:ClassifyItem("item:2589", 2589)
    -- May be nil if categories are not ready in the simulator; must never throw.
    if idx then
        assertType("number", idx)
        assertType("string", name)
    end
end)
