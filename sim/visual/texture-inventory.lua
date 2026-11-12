-- Texture inventory for scripts/blizzard-art.py lock (run after
-- sim/visual/prelude.lua). Opens every surface the addon shows -- each owner
-- kind and tab, the tooltips, EllesmereUI's bag window -- and lists the
-- textures of their frame trees, hidden regions and button states included
-- (highlight, pushed, disabled, checked), plus backdrop files. The list
-- leaves through error(), the one channel --exec-lua reports in the log.
local ns = EllesmereUIBagsAlts._ns
local seen, out = {}, {}

local function add(kind, value)
    if value == nil or value == "" then return end
    local key = kind .. " " .. tostring(value)
    if not seen[key] then
        seen[key] = true
        out[#out + 1] = key
    end
end

local function texture(t)
    if t.GetAtlas then add("atlas", t:GetAtlas()) end
    if t.GetTexture then
        local file = t:GetTexture()
        if type(file) == "number" then add("fdid", file) else add("path", file) end
    end
end

local visited = {}
local function walk(frame)
    if not frame or visited[frame] then return end
    visited[frame] = true
    local backdrop = frame.backdropInfo or (frame.GetBackdrop and frame:GetBackdrop())
    if type(backdrop) == "table" then
        add("path", backdrop.bgFile)
        add("path", backdrop.edgeFile)
    end
    for _, region in ipairs({ frame:GetRegions() }) do
        if region:GetObjectType() == "Texture" or region:GetObjectType() == "MaskTexture" then texture(region) end
    end
    for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture",
                              "GetDisabledTexture", "GetCheckedTexture", "GetStatusBarTexture" }) do
        local t = frame[getter] and frame[getter](frame)
        if t then texture(t) end
    end
    for _, child in ipairs({ frame:GetChildren() }) do walk(child) end
end

local function sweep()
    visited = {}
    for _, name in ipairs({ "EllesmereUIBagsAltsBrowser", "EllesmereUIBagsAltsTooltip", "GameTooltip",
                            "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2",
                            "BattlePetTooltip", "EUI_Bags" }) do
        walk(_G[name])
    end
end

local function hoverAll(list, count)
    for i = 1, count or 0 do
        local e = list[i]
        local onEnter = e and e:GetScript("OnEnter")
        if onEnter then
            onEnter(e)
            sweep()
            local onLeave = e:GetScript("OnLeave")
            if onLeave then onLeave(e) end
        end
    end
end

local TABS = { "all", "bags", "bank", "equipped", "mail", "auctions", "currency" }
local owners = { "*all", "*realm:Blackhand", ns.WARBAND_OWNER }
for key in pairs(ns.db.chars) do owners[#owners + 1] = key end
for key in pairs(ns.db.guilds or {}) do owners[#owners + 1] = "@" .. key end

for _, owner in ipairs(owners) do
    for _, tab in ipairs(TABS) do
        local ok = pcall(VisualScene, owner, tab)
        if ok then
            local f = EllesmereUIBagsAltsBrowser
            sweep()
            hoverAll(f.grid and f.grid.buttons, f.grid and f.grid.used)
            hoverAll(f.currencies and f.currencies.items, f.currencies and f.currencies.used)
        end
    end
end
VisualScene("*all", nil, "n")
sweep()
local f = EllesmereUIBagsAltsBrowser
if f.searchHelp then f.searchHelp:GetScript("OnEnter")(f.searchHelp); sweep() end

-- EllesmereUI's own bag window, which the addon extends.
if EUI_Bags and not EUI_Bags:IsShown() then ToggleAllBags() end
sweep()

table.sort(out)
error("TEXTURE-INVENTORY\n" .. table.concat(out, "\n"))
