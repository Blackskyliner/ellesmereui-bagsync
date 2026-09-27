-- Layout invariants of the browser in every view, measured on the geometry
-- the simulator computes from the real anchors, templates and EUI skin.
local ns = EllesmereUIBagsAlts._ns
local Lay = EUIAltsLayout

local VIEWS = {
    { owner = "Aldrianna-Blackhand", tabs = { "all", "bags", "bank", "equipped", "mail", "auctions", "currency" } },
    { owner = "Bob-Blackhand", tabs = { "bags", "bank" } },          -- empty bank: hint text
    { owner = "*all", tabs = { "all", "bags", "bank", "mail", "auctions", "currency" } },
    { owner = "*realm:Blackhand", tabs = { "all", "currency" } },
    { owner = "#warband" },
    { owner = "@Knights of Ellesmere-Blackhand" },
}
local SEARCHES = { "n", "valor", "zzzz" }
-- EUI's window shell paints a 25 px title bar (WSkin.Shell topBar); the title
-- row must fit it whether or not the code models it as its own frame.
local TITLE_BAR_H = 25

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
        -- 2. title row: all three inside the title bar, none overlapping
        local win = Lay.Rect(f)
        local header = { l = win.l, r = win.r, t = win.t, b = win.t - TITLE_BAR_H }
        local title, search, close = Lay.TextRect(f.title), Lay.Rect(f.search), Lay.Rect(f.close)
        for _, item in ipairs({ { "title", title }, { "search", search }, { "close", close } }) do
            if not Lay.Inside(item[2], header) then error(Lay.Describe(item[1], item[2]) .. " outside " .. Lay.Describe("header", header)) end
        end
        Lay.AssertNone(Lay.Overlaps({ { "title", title }, { "search", search }, { "close", close } }), "title row overlap")
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
        -- 8. footer text and delete button apart
        if f.delete:IsVisible() then
            Lay.AssertNone(Lay.Overlaps({ { "footer", Lay.TextRect(f.footer) }, { "delete", Lay.Rect(f.delete) } }), "footer")
        end
        -- 9. no frame pinned far above the window (other windows must cover it)
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
