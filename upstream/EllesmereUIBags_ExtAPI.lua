if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIBags_ExtAPI.lua
--  Public extension points of the Bags module for companion addons.
--  Copyright (c) 2026 Blackskyliner. SPDX-License-Identifier: MIT
--
--  Loaded after EllesmereUIBags.lua (TOC). Defines functions only: nothing is
--  created, hooked or registered until a companion calls in, so users without
--  companions pay nothing (zero cost unless used, zero behavior change).
--
--    EUI_Bags.extAPIVersion                 -- 1
--    EUI_Bags:RegisterHeaderButton(key, opts) -> true
--        opts = { icon = texture, tooltip = string, onClick = fn(btn, mouse), order = n, size = px }
--        Small icon button in the bag header, laid out left to right after
--        the item count. Built on the first call once the header exists
--        (StartAddon), otherwise on the first bag open.
--    EUI_Bags:SetHeaderButtonShown(key, shown)
--    EUI_Bags:SkinItemButton(btn) -> overlay  -- the house slot look for a
--        companion's own (non-secure) item button; quality border via
--        EUI_Bags:SetItemBorderColor(btn, r, g, b, a)
--
--  Buttons are the module's own frames parented to its own header; nothing is
--  written onto Blizzard frames (taint-free by construction).
-------------------------------------------------------------------------------
local ns = select(2, ...)
local EUI = EllesmereUI

local BUTTON_SIZE, BUTTON_GAP = 18, 6

local _buttons = {}     -- key -> button
local _opts = {}        -- key -> opts
local _showHooked = false

local function LayoutHeaderButtons()
    local header = EUI_Bags.Header
    if not header then return end
    local keys = {}
    for key in pairs(_buttons) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b)
        local oa, ob = _opts[a].order or 100, _opts[b].order or 100
        if oa ~= ob then return oa < ob end
        return a < b
    end)
    local prev
    for _, key in ipairs(keys) do
        local btn = _buttons[key]
        if btn:IsShown() then
            btn:ClearAllPoints()
            if prev then
                btn:SetPoint("LEFT", prev, "RIGHT", BUTTON_GAP, 0)
            else
                btn:SetPoint("LEFT", header.itemCount, "RIGHT", BUTTON_GAP + 2, 0)
            end
            prev = btn
        end
    end
end

local function BuildButton(key, opts)
    local header = EUI_Bags.Header
    local btn = CreateFrame("Button", nil, header)
    btn:SetSize(opts.size or BUTTON_SIZE, opts.size or BUTTON_SIZE)
    btn:SetFrameLevel(header:GetFrameLevel() + 5)
    local icon = btn:CreateTexture(nil, "OVERLAY")
    icon:SetAllPoints()
    icon:SetTexture(opts.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    icon:SetAlpha(0.9)
    btn:SetScript("OnEnter", function(self)
        icon:SetAlpha(1)
        if opts.tooltip then EUI.ShowWidgetTooltip(self, opts.tooltip) end
    end)
    btn:SetScript("OnLeave", function()
        icon:SetAlpha(0.9)
        EUI.HideWidgetTooltip()
    end)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:SetScript("OnClick", function(self, mouse)
        if opts.onClick then opts.onClick(self, mouse) end
    end)
    _buttons[key] = btn
end

local function BuildPending()
    if not EUI_Bags.Header then return false end
    for key, opts in pairs(_opts) do
        if not _buttons[key] then BuildButton(key, opts) end
    end
    LayoutHeaderButtons()
    return true
end

function EUI_Bags:RegisterHeaderButton(key, opts)
    if type(key) ~= "string" or type(opts) ~= "table" then return false end
    _opts[key] = opts
    if _buttons[key] then _buttons[key]:Show() end
    if not BuildPending() and not _showHooked then
        _showHooked = true
        EUI_Bags:HookScript("OnShow", BuildPending)
    end
    return true
end

function EUI_Bags:SetHeaderButtonShown(key, shown)
    local btn = _buttons[key]
    if not btn then return end
    btn:SetShown(shown and true or false)
    LayoutHeaderButtons()
end

function EUI_Bags:SkinItemButton(btn)
    return ns.SkinItemButton(btn, { anchorIcon = true, flatHighlight = true })
end

function EUI_Bags:SetItemBorderColor(btn, r, g, b, a)
    ns.SetInsetBorderColor(btn, r, g, b, a or 1)
end

EUI_Bags.extAPIVersion = 1
