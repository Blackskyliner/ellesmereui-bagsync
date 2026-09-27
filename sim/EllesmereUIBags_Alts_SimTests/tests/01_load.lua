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
    return not EllesmereUI or (EUI_Bags and EUI_Bags.Header ~= nil)
end

simtest_when(bagsReady, "first use activates once (EUI: the bag key; else: the browser)", function()
    local ns = EllesmereUIBagsAlts._ns
    if EllesmereUI then
        ToggleAllBags()
        assertTrue(ns.IsActivated())
        assertEquals("bags", ns.activatedBy)
        ToggleAllBags()
    else
        -- Blizzard's bag functions are never hooked (EUI Bags is required):
        -- they stay secure globals. Without EUI the API still activates.
        for _, name in ipairs({ "ToggleAllBags", "OpenAllBags", "ToggleBackpack", "OpenBackpack", "ToggleBag", "OpenBag" }) do
            assertTrue(issecurevariable(name), name)
        end
        EllesmereUIBagsAlts.GetCharacters()
        assertEquals("api", ns.activatedBy)
    end
    assertNotNil(ns.db.chars[ns.GetPlayerKey()])
    assertTrue(ns.featureByKey.bags.active)
end)
