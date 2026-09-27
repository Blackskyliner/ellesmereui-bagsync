simtest("addon loaded and booted", function()
    assertNotNil(EllesmereUIBagsAlts)
    assertNotNil(EllesmereUIBagsAlts._ns.db)
    assertTrue(EllesmereUIBagsAlts._ns.ready)
end)

simtest("unused after login: nothing scanned, only the activation trigger registered", function()
    local ns = EllesmereUIBagsAlts._ns
    assertTrue(not ns.IsActivated())
    local events = ns.GetRegisteredEvents()
    assertEquals(1, #events)
    assertEquals("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", events[1])
    assertNil(ns.db.chars[ns.GetPlayerKey()])
    assertTrue(not ns.featureByKey.bags.active)
end)

-- EllesmereUI builds its bag window 0.5 s after login.
local function bagsReady()
    return EUI_Bags and EUI_Bags.Header ~= nil
end

simtest_when(bagsReady, "the bag key (EUI's ToggleAllBags) activates once", function()
    local ns = EllesmereUIBagsAlts._ns
    -- Blizzard's own bag functions are never hooked by the addon.
    for _, name in ipairs({ "ToggleBackpack", "OpenBackpack", "ToggleBag", "OpenBag", "OpenAllBags" }) do
        local _, source = issecurevariable(name)
        assertTrue(source ~= "EllesmereUIBags_Alts", name)
    end
    ToggleAllBags()
    assertTrue(ns.IsActivated())
    assertEquals("bags", ns.activatedBy)
    ToggleAllBags()
    assertNotNil(ns.db.chars[ns.GetPlayerKey()])
    assertTrue(ns.featureByKey.bags.active)
end)
