local ns = EllesmereUIBagsAlts._ns

simtest("all-characters view merges stacks and lists owners in the private tooltip", function()
    ns.Browser:Open(ns.Browser.ALL_OWNER)
    ns.Browser:SelectTab("all")
    local f = _G.EllesmereUIBagsAltsBrowser
    assertTrue(f.grid.used >= 1)
    assertTrue(not f.delete:IsShown())
    local b = f.grid.buttons[1]
    b:GetScript("OnEnter")(b)
    local tooltip = _G.EllesmereUIBagsAltsTooltip
    assertEquals(b.itemID, tooltip.processingInfo.euiAltsOwners)
    -- the simulator renders no native tooltip lines: ours are spacer + holder
    assertTrue(tooltip:NumLines() >= 2)
    local left2 = _G.EllesmereUIBagsAltsTooltipTextLeft2:GetText() or ""
    assertTrue(left2:find(UnitName("player"), 1, true) ~= nil)
    assertTrue(GameTooltip:GetOwner() ~= b)
    b:GetScript("OnLeave")(b)
end)

simtest("realm view renders the current realm's characters", function()
    ns.Browser:Select(ns.Browser.RealmOwner(GetNormalizedRealmName()))
    local f = _G.EllesmereUIBagsAltsBrowser
    assertTrue(f.grid.used >= 1)
end)

simtest("currency rows show Blizzard's currency tooltip plus the holders", function()
    local c = ns.GetPlayerChar()
    local injected = next(c.currency) == nil
    if injected then c.currency[3008] = 1234 end           -- Valorstones
    ns.Browser:Select(ns.GetPlayerKey())
    ns.Browser:SelectTab("currency")
    local f = _G.EllesmereUIBagsAltsBrowser
    assertTrue(f.currencies.used >= 1)
    local row = f.currencies.items[1]
    row:GetScript("OnEnter")(row)
    local tooltip = _G.EllesmereUIBagsAltsTooltip
    assertTrue(tooltip:IsShown())
    -- the simulator renders no native tooltip lines: ours are spacer + holder
    assertTrue(tooltip:NumLines() >= 2)
    local left2 = _G.EllesmereUIBagsAltsTooltipTextLeft2:GetText() or ""
    assertTrue(left2:find(UnitName("player"), 1, true) ~= nil)
    row:GetScript("OnLeave")(row)
    assertTrue(not tooltip:IsShown())
    if injected then c.currency[3008] = nil end
    ns.Browser:SelectTab("bags")
    ns.Browser:Close()
end)

simtest("search lists matching currencies with the holder tooltip", function()
    local c = ns.GetPlayerChar()
    local id, info
    for cid in pairs(c.currency) do
        info = C_CurrencyInfo.GetCurrencyInfo(cid)
        if info and info.name and info.name ~= "" then id = cid break end
    end
    local injected
    if not id then
        id, injected = 3008, true
        info = C_CurrencyInfo.GetCurrencyInfo(id)
        c.currency[id] = 1234
    end
    if not (info and info.name and info.name ~= "") then
        if injected then c.currency[id] = nil end
        return                                             -- client has no currency names
    end
    ns.Browser:OpenSearch(info.name)
    local f = _G.EllesmereUIBagsAltsBrowser
    local row = f.results.items[1]
    assertEquals(id, row.currencyID)
    row:GetScript("OnEnter")(row)
    assertTrue(_G.EllesmereUIBagsAltsTooltip:IsShown())
    row:GetScript("OnLeave")(row)
    ns.Browser:OpenSearch("")
    ns.Browser:Close()
    if injected then c.currency[id] = nil end
end)
