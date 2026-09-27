-- Known simulator limitation, pinned so a fix upstream is noticed: in
-- wow-ui-sim, hooksecurefunc(object, "Method", hook) fires the hook for every
-- object of that widget type (in the client: only for that object).
-- EllesmereUI's Blizzard skin pins its settings-tab textures that way, so in
-- `sim-test.sh skin` every texture drawn afterwards is faded, our item slots
-- included. That is why scripts/visual-test.sh renders without the skin
-- module. When this test fails, the simulator is fixed: add the skin mode to
-- the visual tests (scripts/visual-test.sh, visual-compare.py MODES).
simtest("known sim limitation: object method hooks leak to every object of the type", function()
    local a, b = UIParent:CreateTexture(), UIParent:CreateTexture()
    local hits = 0
    hooksecurefunc(a, "SetTexture", function() hits = hits + 1 end)
    b:SetTexture(134400)
    assertEquals(1, hits)
end)
