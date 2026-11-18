-- Layout invariants of the browser in every view, measured on the geometry
-- the simulator computes from the real anchors, templates and EUI skin.
local ns = EllesmereUIBagsAlts._ns
local Lay = EUIAltsLayout

local Fixture = EUIAltsSimFixture
local VIEWS = {
    { owner = Fixture.MAIN, tabs = { "all", "bags", "bank", "equipped", "mail", "auctions", "currency" } },
    { owner = Fixture.SECOND, tabs = { "bags", "bank" } },          -- empty bank: hint text
    { owner = "*all", tabs = { "all", "bags", "bank", "mail", "auctions", "currency" } },
    { owner = Fixture.REALM, tabs = { "all", "currency" } },
    { owner = Fixture.GUILD },
}
if ns.Compat.HAS_WARBAND_BANK then VIEWS[#VIEWS + 1] = { owner = "#warband" } end
local SEARCHES = { "n", "valor", "zzzz" }
-- The title row matches EllesmereUI Bags' bag header (HEADER_H = 35, inset
-- 1 px, EllesmereUIBags.lua CreateHeader); everything in it must fit it.
local TITLE_BAR_H = 1 + 35

local function frame() return _G.EllesmereUIBagsAltsBrowser end

local function show(owner, tab, query)
    ns.Browser:Open(owner)
    if tab then ns.Browser:SelectTab(tab) end
    ns.Browser:SetQuery(query or "")
    ns.Browser:Refresh()
    return frame()
end

local function label(owner, tab, query)
    return owner .. "/" .. tostring(tab) .. (query and ("?" .. query) or "")
end

local function check(where)
    local f = frame()
    local ok, err = pcall(function()
        -- 1. nothing is painted outside the window (scroll content: not sideways)
        Lay.AssertNone(Lay.Escapees(f, f.scroll), "outside the window")
        -- 2. title row: all inside the bag-style header, none overlapping
        local win = Lay.Rect(f)
        local header = { l = win.l, r = win.r, t = win.t, b = win.t - TITLE_BAR_H }
        local title, search, close = Lay.TextRect(f.title), Lay.Rect(f.search), Lay.Rect(f.close)
        local help = Lay.Rect(f.searchHelp)
        local subtitle = f.subtitle and Lay.TextRect(f.subtitle)
        for _, item in ipairs({ { "title", title }, { "subtitle", subtitle }, { "search", search }, { "help", help }, { "close", close } }) do
            if item[2] then
            if not Lay.Inside(item[2], header) then error(Lay.Describe(item[1], item[2]) .. " outside " .. Lay.Describe("header", header)) end
            end
        end
        Lay.AssertNone(Lay.Overlaps({ { "title", title }, { "subtitle", subtitle }, { "search", search }, { "help", help }, { "close", close } }), "title row overlap")
        -- 3. tabs: side by side inside the content column, below the title bar
        local tabs, content = {}, Lay.Rect(f.content)
        for _, tab in ipairs(f.tabs) do
            if tab:IsVisible() then
                local r = Lay.Rect(tab)
                tabs[#tabs + 1] = { "tab " .. tab.key, r }
                if r.r > content.r + 0.5 then error(Lay.Describe("tab " .. tab.key, r) .. " past " .. Lay.Describe("content", content)) end
                if r.t > header.b + 0.5 then error(Lay.Describe("tab " .. tab.key, r) .. " reaches into the title bar") end
            end
        end
        Lay.AssertNone(Lay.Overlaps(tabs), "tab overlap")
        -- 4. sidebar rows: name and gold never collide
        for i = 1, f.sideRows.used do
            local row = f.sideRows.items[i]
            Lay.AssertNone(Lay.Overlaps({ { "name " .. i, Lay.TextRect(row.left) }, { "gold " .. i, Lay.TextRect(row.right) } }), "sidebar row")
        end
        -- 5. item grid: no two slots overlap
        local slots = {}
        for i = 1, f.grid.used do slots[i] = { "slot " .. i, Lay.Rect(f.grid.buttons[i]) } end
        Lay.AssertNone(Lay.Overlaps(slots), "grid overlap")
        -- 6. result rows: name, detail and total apart
        for i = 1, f.results.used do
            local r = f.results.items[i]
            Lay.AssertNone(Lay.Overlaps({ { "name", Lay.TextRect(r.name) }, { "total", Lay.TextRect(r.total) } }), "result row " .. i)
            Lay.AssertNone(Lay.Overlaps({ { "detail", Lay.TextRect(r.detail) }, { "total", Lay.TextRect(r.total) } }), "result row " .. i)
        end
        -- 7. currency rows: name and amount apart
        for i = 1, f.currencies.used do
            local r = f.currencies.items[i]
            Lay.AssertNone(Lay.Overlaps({ { "name", Lay.TextRect(r.name) }, { "qty", Lay.TextRect(r.qty) } }), "currency row " .. i)
        end
        -- 8. no frame pinned far above the window (other windows must cover it)
        Lay.AssertNone(Lay.LevelOutliers(f, 20), "frame level")
    end)
    if not ok then error(where .. ": " .. tostring(err), 0) end
end

simtest("layout invariants hold in every browser view", function()
    EUIAltsSimFixture.Install()
    local ok, err = pcall(function()
        for _, view in ipairs(VIEWS) do
            for _, tab in ipairs(view.tabs or { false }) do
                show(view.owner, tab or nil)
                check(label(view.owner, tab or nil))
            end
        end
        for _, q in ipairs(SEARCHES) do
            show("*all", nil, q)
            check(label("*all", nil, q))
        end
    end)
    ns.Browser:SetQuery("")
    ns.Browser:SelectTab("bags")
    ns.Browser:Close()
    EUIAltsSimFixture.Uninstall()
    if not ok then error(err, 0) end
end)

simtest("layout invariants hold at a smaller and a larger browser scale", function()
    EUIAltsSimFixture.Install()
    local ok, err = pcall(function()
        for _, scale in ipairs({ 0.8, 1.25 }) do
            show("*all", "all")
            frame():SetScale(scale)
            ns.Browser:Refresh()
            check("scale " .. scale)
        end
    end)
    frame():SetScale(ns.db.settings.ui.browserScale or 1)
    ns.Browser:SelectTab("bags")
    ns.Browser:Close()
    EUIAltsSimFixture.Uninstall()
    if not ok then error(err, 0) end
end)

simtest("the sidebar's context menu holds its title and entries", function()
    EUIAltsSimFixture.Install()
    local ok, err = pcall(function()
        local f = show(Fixture.MAIN, "bags")
        local row
        for i = 1, f.sideRows.used do
            if f.sideRows.items[i].ownerKey == Fixture.SECOND then row = f.sideRows.items[i] end
        end
        row:Click("RightButton")
        local menu = _G.EllesmereUIBagsAltsMenu
        assertTrue(menu:IsVisible())
        -- above the browser, which a click outside the menu must not reach
        assertTrue(menu:GetFrameStrata() == "FULLSCREEN_DIALOG")
        assertTrue(menu.catcher:GetFrameStrata() == "DIALOG")
        local box = Lay.Rect(menu)
        local parts = { { "title", Lay.TextRect(menu.title) } }
        for i, entry in ipairs(menu.entries) do
            if entry:IsVisible() then parts[#parts + 1] = { "entry " .. i, Lay.TextRect(entry.label) } end
        end
        for _, part in ipairs(parts) do
            if not Lay.Inside(part[2], box) then error(Lay.Describe(part[1], part[2]) .. " outside " .. Lay.Describe("menu", box)) end
        end
        Lay.AssertNone(Lay.Overlaps(parts), "menu")
        menu.catcher:Click()
        assertTrue(not menu:IsVisible())
    end)
    ns.Browser:Close()
    EUIAltsSimFixture.Uninstall()
    if not ok then error(err, 0) end
end)
