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

simtest("close button is levelled relative to the window (template pins 510)", function()
    local f = _G.EllesmereUIBagsAltsBrowser
    local level = f.close:GetFrameLevel()
    assertTrue(level > f:GetFrameLevel())
    assertTrue(level <= f:GetFrameLevel() + 10)
    assertTrue(f.search:GetHeight() <= f.header:GetHeight())
    assertTrue(f.close:GetHeight() <= f.header:GetHeight())
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

simtest("search words match the client's tooltip text of an item", function()
    -- a stored item and a word of its tooltip that its name lacks (the
    -- simulator has tooltips for few items)
    local itemID, word
    for id in ns.Index:AllItemIDs() do
        local data, name = C_TooltipInfo.GetItemByID(id), C_Item.GetItemInfo(id)
        for i = 2, #(name and data and data.lines or {}) do
            local text = (data.lines[i].leftText or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):lower()
            for w in text:gmatch("%a%a%a%a+") do
                if not word and not name:lower():find(w, 1, true) then itemID, word = id, w end
            end
        end
    end
    assertNotNil(word)
    local found = false
    for _, r in ipairs((ns.Search.Run(ns.Search.Parse(word)))) do found = found or r.itemID == itemID end
    assertTrue(found)
end)

simtest("bind expressions run against the client's item data", function()
    local q = ns.Search.Parse("(bop or boe or wue or boa) and not (soulbound | warbound) or boe>=1")
    assertNotNil(q.bind)
    ns.Browser:SetQuery("not bop")
    local f = _G.EllesmereUIBagsAltsBrowser
    local found = false
    for i = 1, f.results.used do found = found or f.results.items[i].itemID == 2589 end
    assertTrue(found)                          -- Linen Cloth does not bind
    ns.Browser:SetQuery("")
end)

simtest("browser closes via slash toggle and stops listening for item data", function()
    SlashCmdList["EUIALTS"]("")
    assertTrue(not _G.EllesmereUIBagsAltsBrowser:IsShown())
    assertTrue(not ns.IsEventRegistered(ns.Browser, "ITEM_DATA_LOAD_RESULT"))
end)

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

simtest("hovering a grid item uses the private tooltip through Blizzard's ProcessInfo", function()
    ns.Browser:Open()
    ns.Browser:SelectTab("bags")
    local f = _G.EllesmereUIBagsAltsBrowser
    local b = f.grid.buttons[1]
    assertNotNil(b)
    b:GetScript("OnEnter")(b)
    local tooltip = _G.NotGameTooltipEllesmereUIBagsAlts
    assertNotNil(tooltip)
    local info = tooltip.processingInfo
    assertNotNil(info)
    assertEquals("GetHyperlink", info.getterName)
    assertTrue(GameTooltip:GetOwner() ~= b)
    b:GetScript("OnLeave")(b)
    ns.Browser:Close()
end)

simtest_only("retail", "caged pets show on a private BattlePetTooltipTemplate frame", function()
    -- species 39 (Mechanical Squirrel) is in the simulator's pet journal
    local link = "|cff0070dd|Hbattlepet:39:25:3:1627:289:289:0000000000000000:0|h[Pet]|h|r"
    local owner = CreateFrame("Frame", nil, UIParent)
    assertTrue(ns.W.ShowPetTooltip(owner, link))
    local pet = _G.EllesmereUIBagsAltsPetTooltip
    assertNotNil(pet)
    assertTrue(pet:IsShown())
    assertTrue(pet ~= _G.BattlePetTooltip)
    assertEquals("Mechanical Squirrel", pet.Name:GetText())
    assertTrue(not (_G.BattlePetTooltip and _G.BattlePetTooltip:IsShown()))
    ns.W.HidePetTooltip()
    assertTrue(not pet:IsShown())
end)
