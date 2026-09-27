local ns = EllesmereUIBagsAlts._ns

simtest("browser is built lazily with real Blizzard templates and EUI skin", function()
    assertNil(_G.EllesmereUIBagsAltsBrowser)
    SlashCmdList["EUIALTS"]("")
    local f = _G.EllesmereUIBagsAltsBrowser
    assertNotNil(f)
    assertTrue(f:IsShown())
    assertNotNil(f.search)
    assertNotNil(f.scroll.ScrollBar)
    assertTrue(f.grid.used >= 1)
    assertTrue(f.sideRows.used >= 2)          -- current character + warband
end)

simtest("grid buttons are plain ItemButtons, not secure container buttons", function()
    local b = _G.EllesmereUIBagsAltsBrowser.grid.buttons[1]
    assertTrue(b:IsObjectType("Button"))
    assertTrue(not b:IsProtected())
end)

simtest("search finds items across characters", function()
    ns.Browser:SetQuery("id:2589")
    local f = _G.EllesmereUIBagsAltsBrowser
    assertEquals(1, f.results.used)
    assertEquals(2589, f.results.items[1].itemID)
    ns.Browser:SetQuery("")
end)

simtest("browser closes via slash toggle and stops listening for item data", function()
    SlashCmdList["EUIALTS"]("")
    assertTrue(not _G.EllesmereUIBagsAltsBrowser:IsShown())
    assertTrue(not ns.IsEventRegistered(ns.Browser, "ITEM_DATA_LOAD_RESULT"))
end)

if not EllesmereUI then
    simtest("header button setting without EllesmereUI only prints a hint", function()
        ns.db.settings.ui.headerButton = true
        ns.SettingsChanged()
        assertNil(EllesmereUIBagsExt:GetHeaderButton("EllesmereUIBags_Alts"))
        ns.db.settings.ui.headerButton = false
        ns.SettingsChanged()
    end)
    return
end

simtest_when(function() return EUI_Bags and EUI_Bags.Header ~= nil end, "header button attaches to the real EUI bag header on first bag open", function()
    ns.db.settings.ui.headerButton = true
    ns.SettingsChanged()
    -- EUI's replacement opens EUI_Bags -> OnShow hook attaches. Close first if an
    -- earlier test (e.g. the auction house event) left the bags open.
    if EUI_Bags:IsShown() then ToggleAllBags() end
    ToggleAllBags()
    assertTrue(EUI_Bags:IsShown())
    if EllesmereUIBagsExt:GetNativeAPIVersion() > 0 then return end   -- covered by 07_upstream.lua
    local btn = EllesmereUIBagsExt:GetHeaderButton("EllesmereUIBags_Alts")
    assertNotNil(btn)
    assertEquals(EUI_Bags.Header, btn:GetParent())
    local point, rel = btn:GetPoint(1)
    assertEquals("LEFT", point)
    assertEquals(EUI_Bags.Header.itemCount, rel)
    btn:Click()
    assertTrue(_G.EllesmereUIBagsAltsBrowser:IsShown())
    btn:Click()
    assertTrue(not _G.EllesmereUIBagsAltsBrowser:IsShown())
    ns.db.settings.ui.headerButton = false
    ns.SettingsChanged()
    assertTrue(not btn:IsShown())
    ToggleAllBags()
end)
