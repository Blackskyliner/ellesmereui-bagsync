-- WoW Forever against its own FrameXML and EllesmereUI's real Forever code
-- (`sim-test.sh --client=forever`). The simulator models neither keyring nor
-- bank bags nor ammo yet; spec/forever_spec.lua covers those paths.
local ns = EllesmereUIBagsAlts._ns

simtest_only("forever", "the client is taken from EllesmereUI", function()
    assertTrue(EllesmereUI.IS_FOREVER == true)
    assertTrue(ns.Compat.IS_FOREVER)
    assertTrue(not ns.Compat.HAS_WARBAND_BANK)
end)

simtest_only("forever", "characters are keyed by EllesmereUI's realm group", function()
    local group = EllesmereUI.RealmGroupName()
    assertType("string", group)
    assertEquals(UnitName("player") .. "-" .. group:gsub("[%s%-']", ""), ns.GetPlayerKey())
    assertEquals(group, ns.GetPlayerChar().realmName)
end)

simtest_only("forever", "a bank visit scans the character bank and leaves the warband alone", function()
    A_Admin.FireEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", Enum.PlayerInteractionType.Banker)
    assertTrue(ns.IsBankOpen())
    A_Admin.FireEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", Enum.PlayerInteractionType.Banker)
    assertTrue(not ns.IsBankOpen())
    assertNil(next(ns.db.warband.bank))
    assertNil(ns.db.warband.money)
end)

simtest_only("forever", "the browser lists no warband bank", function()
    ns.Browser:Open()
    local f = _G.EllesmereUIBagsAltsBrowser
    for i = 1, f.sideRows.used do
        assertTrue(f.sideRows.items[i].ownerKey ~= ns.WARBAND_OWNER)
    end
    ns.Browser:Close()
end)

simtest_only("forever", "caged pets fall back to the item tooltip", function()
    local owner = CreateFrame("Frame", nil, UIParent)
    assertTrue(not ns.W.ShowPetTooltip(owner, "|Hbattlepet:39:25:3:1627:289:289:0000000000000000:0|h[Pet]|h"))
    assertNil(_G.EllesmereUIBagsAltsPetTooltip)
end)
