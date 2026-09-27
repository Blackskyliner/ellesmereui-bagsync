-------------------------------------------------------------------------------
--  EUIBagsExt.lua  -- extension layer between third-party addons and
--  EllesmereUI Bags.
--
--  One stable, versioned surface for everything a companion addon wants from
--  EUI Bags, so companions never reach into EUI internals themselves:
--      * looks: skin registration, font, accent color, item-slot skin, border
--      * house UI: widget tooltip, confirm popup, localization
--      * data: category classification of any item link
--      * integration: buttons in the EUI bag header
--
--  EllesmereUI Bags (and with it the EllesmereUI core) is a dependency of
--  the companion. Every call still feature-detects the EUI function it uses
--  and degrades quietly when one is missing or changed (an EUI update renames
--  an internal): a companion built on this layer never throws because of EUI.
--  The skin callback only fires when EUI's Blizzard skin module is enabled;
--  callers keep their own plain look for the other case.
--
--  Upstream path: EllesmereUIBags can ship the native half (see
--  ../../../upstream/EllesmereUIBags_ExtAPI.lua). When EUI_Bags exposes
--  RegisterHeaderButton / SkinItemButton natively, this layer delegates to them
--  and the shim code below goes dormant.
--
--  Embedding: copy this file; the highest MINOR loaded wins (LibStub-style
--  guard without the LibStub dependency). ASCII only, Lua 5.1.
-------------------------------------------------------------------------------
local MAJOR, MINOR = "EllesmereUIBagsExt", 1

local lib = _G[MAJOR]
if lib and (lib.minor or 0) >= MINOR then return end
lib = lib or {}
lib.minor = MINOR
_G[MAJOR] = lib

local pcall, type, pairs, ipairs, sort = pcall, type, pairs, ipairs, table.sort

local EUI_ACCENT_DEFAULT = { 0.047, 0.824, 0.624 }   -- EUI green (0cd29f)

-------------------------------------------------------------------------------
--  Detection
-------------------------------------------------------------------------------
local function EUI()
    local e = _G.EllesmereUI
    if type(e) ~= "table" or _G.EUI_CLIENT_BLOCKED then return nil end
    return e
end

function lib:IsEUILoaded()
    return EUI() ~= nil
end

function lib:IsBagsLoaded()
    return EUI() ~= nil and type(_G.EUI_Bags) == "table"
end

-- The Bags module's private namespace, published by EUI for its LOD options.
local function BagsNS()
    local e = EUI()
    local registry = e and e._ModuleNS
    local mns = type(registry) == "table" and registry["EllesmereUIBags"]
    return type(mns) == "table" and mns or nil
end

-------------------------------------------------------------------------------
--  Looks
-------------------------------------------------------------------------------
-- Official EUI API (SKINNING_API.md, apiVersion 1). Returns true if accepted.
function lib:RegisterSkin(name, applyFn)
    local e = EUI()
    if e and type(e.RegisterSkin) == "function" then
        local ok, res = pcall(e.RegisterSkin, name, applyFn)
        return ok and res == true
    end
    return false
end

function lib:GetFont(addonKey)
    local e = EUI()
    if e and type(e.GetFontPath) == "function" then
        local ok, path = pcall(e.GetFontPath, addonKey or "bags")
        if ok and type(path) == "string" then
            local flag = ""
            if type(e.GetFontOutlineFlag) == "function" then
                local ok2, f = pcall(e.GetFontOutlineFlag, addonKey or "bags")
                if ok2 and type(f) == "string" then flag = f end
            end
            return path, flag
        end
    end
    return STANDARD_TEXT_FONT, ""
end

function lib:GetAccentColor()
    local e = EUI()
    if e and type(e.GetAccentColor) == "function" then
        local ok, r, g, b = pcall(e.GetAccentColor)
        if ok and type(r) == "number" then return r, g, b end
    end
    return EUI_ACCENT_DEFAULT[1], EUI_ACCENT_DEFAULT[2], EUI_ACCENT_DEFAULT[3]
end

-- Applies EUI's bag slot look to an item button the caller owns.
-- Returns true when EUI styled it (then use lib:SetItemBorderColor for quality).
function lib:SkinItemButton(btn)
    local bags = _G.EUI_Bags
    if type(bags) == "table" and type(bags.SkinItemButton) == "function" then
        local ok = pcall(bags.SkinItemButton, bags, btn)
        if ok then return true end
    end
    local mns = BagsNS()
    if mns and type(mns.SkinItemButton) == "function" then
        local ok = pcall(mns.SkinItemButton, btn, { anchorIcon = true, flatHighlight = true })
        if ok then return true end
    end
    return false
end

-- Border color for a button styled by lib:SkinItemButton (quality color etc.).
function lib:SetItemBorderColor(btn, r, g, b, a)
    local bags = _G.EUI_Bags
    if type(bags) == "table" and type(bags.SetItemBorderColor) == "function" then
        if pcall(bags.SetItemBorderColor, bags, btn, r, g, b, a or 1) then return true end
    end
    local mns = BagsNS()
    if mns and type(mns.SetInsetBorderColor) == "function" then
        pcall(mns.SetInsetBorderColor, btn, r, g, b, a or 1)
        return true
    end
    return false
end

-------------------------------------------------------------------------------
--  House UI
-------------------------------------------------------------------------------
function lib:L(s)
    local e = EUI()
    if e and type(e.L) == "function" then
        local ok, t = pcall(e.L, s)
        if ok and type(t) == "string" then return t end
    end
    return s
end

-- EUI's own widget tooltip (never Blizzard's shared GameTooltip).
function lib:ShowTooltip(owner, text)
    local e = EUI()
    if e and type(e.ShowWidgetTooltip) == "function" then
        pcall(e.ShowWidgetTooltip, owner, text)
    end
end

function lib:HideTooltip()
    local e = EUI()
    if e and type(e.HideWidgetTooltip) == "function" then
        pcall(e.HideWidgetTooltip)
    end
end

-- EUI's confirm popup (never StaticPopup: its dialogs are shared with
-- Blizzard code and are a classic taint path).
-- opts = { title, message, confirmText, cancelText, onConfirm, onCancel }
-- -> true when the popup was shown
function lib:Confirm(opts)
    local e = EUI()
    if e and type(e.ShowConfirmPopup) == "function" then
        return pcall(e.ShowConfirmPopup, e, opts) == true
    end
    return false
end

-------------------------------------------------------------------------------
--  Categories
-------------------------------------------------------------------------------
local function CategoryManager()
    local cm = _G.EUI_CategoryManager
    if type(cm) == "table" and type(cm.ClassifyItem) == "function" then return cm end
    return nil
end

-- -> catIndex, catName, groupName  (nil when EUI categories are unavailable)
function lib:ClassifyItem(itemLink, itemID)
    local cm = CategoryManager()
    if not cm then return nil end
    local ok, idx = pcall(cm.ClassifyItem, cm, itemLink, itemID, nil, nil)
    if not ok or type(idx) ~= "number" then return nil end
    local name, group
    if type(cm.GetCategories) == "function" then
        local ok2, cats = pcall(cm.GetCategories, cm)
        local cat = ok2 and type(cats) == "table" and cats[idx]
        if type(cat) == "table" then
            name = cat.name or cat._defaultName
            group = cat.groupName
        end
    end
    return idx, name, group
end

-------------------------------------------------------------------------------
--  Bag header buttons
--  opts = { icon = texture, tooltip = string, onClick = fn(button, mouse), order = n }
-------------------------------------------------------------------------------
local headerButtons = {}      -- key -> button (ours)
local headerOpts = {}         -- key -> opts
local showHooked = false
local BUTTON_SIZE, BUTTON_GAP = 18, 6

local function LayoutHeaderButtons(header)
    local keys = {}
    for key in pairs(headerButtons) do keys[#keys + 1] = key end
    sort(keys, function(a, b)
        local oa, ob = headerOpts[a].order or 100, headerOpts[b].order or 100
        if oa ~= ob then return oa < ob end
        return a < b
    end)
    local anchor = header.itemCount or header.title
    local prev
    for _, key in ipairs(keys) do
        local btn = headerButtons[key]
        if btn:IsShown() then
            btn:ClearAllPoints()
            if prev then
                btn:SetPoint("LEFT", prev, "RIGHT", BUTTON_GAP, 0)
            elseif anchor then
                btn:SetPoint("LEFT", anchor, "RIGHT", BUTTON_GAP + 2, 0)
            else
                btn:SetPoint("LEFT", header, "LEFT", 8, 0)
            end
            prev = btn
        end
    end
end

local function CreateHeaderButton(header, key, opts)
    local btn = CreateFrame("Button", nil, header)
    btn:SetSize(opts.size or BUTTON_SIZE, opts.size or BUTTON_SIZE)
    btn:SetFrameLevel(header:GetFrameLevel() + 5)
    local icon = btn:CreateTexture(nil, "OVERLAY")
    icon:SetAllPoints()
    icon:SetTexture(opts.icon or "Interface\\Icons\\INV_Misc_Bag_10")
    icon:SetAlpha(0.9)
    btn:SetScript("OnEnter", function(self)
        icon:SetAlpha(1)
        if opts.tooltip then lib:ShowTooltip(self, opts.tooltip) end
    end)
    btn:SetScript("OnLeave", function()
        icon:SetAlpha(0.9)
        lib:HideTooltip()
    end)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:SetScript("OnClick", function(self, mouse)
        if opts.onClick then opts.onClick(self, mouse) end
    end)
    headerButtons[key] = btn
    return btn
end

local function AttachPending()
    local bags = _G.EUI_Bags
    local header = type(bags) == "table" and bags.Header
    if type(header) ~= "table" or not header.GetObjectType then return false end
    for key, opts in pairs(headerOpts) do
        if not headerButtons[key] then CreateHeaderButton(header, key, opts) end
    end
    LayoutHeaderButtons(header)
    return true
end

-- Returns true when the button is (or will be, once the bag header exists) placed.
function lib:RegisterHeaderButton(key, opts)
    if type(key) ~= "string" or type(opts) ~= "table" then return false end
    local bags = _G.EUI_Bags
    if not self:IsBagsLoaded() then return false end
    -- Native upstream API present: delegate entirely.
    if type(bags.RegisterHeaderButton) == "function" then
        local ok, res = pcall(bags.RegisterHeaderButton, bags, key, opts)
        return ok and res ~= false
    end
    headerOpts[key] = opts
    if headerButtons[key] then headerButtons[key]:Show() end
    if not AttachPending() and not showHooked and bags.HookScript then
        showHooked = true
        bags:HookScript("OnShow", function()
            if next(headerOpts) then AttachPending() end
        end)
    end
    return true
end

function lib:SetHeaderButtonShown(key, shown)
    local bags = _G.EUI_Bags
    if type(bags) == "table" and type(bags.SetHeaderButtonShown) == "function" then
        pcall(bags.SetHeaderButtonShown, bags, key, shown)
        return
    end
    local btn = headerButtons[key]
    if not btn then return end
    btn:SetShown(shown and true or false)
    local header = btn:GetParent()
    if header then LayoutHeaderButtons(header) end
end

-- The shim's button for key (nil when EUI's native API owns the buttons).
function lib:GetHeaderButton(key)
    return headerButtons[key]
end

-- Native EUI extension API version (0 = not available, shim in use).
function lib:GetNativeAPIVersion()
    local bags = _G.EUI_Bags
    return type(bags) == "table" and tonumber(bags.extAPIVersion) or 0
end

-------------------------------------------------------------------------------
--  Character gold tracked by EUI Bags (read-only)
--  EllesmereUIDB.characterGold["Name-Realm Name"] = { gold, lastUpdated, ... },
--  keyed by UnitName .. "-" .. GetRealmName() (display realm, spaces kept).
-------------------------------------------------------------------------------
-- -> gold (copper), lastUpdated (epoch) or nil
function lib:GetCharacterGold(name, realmName)
    if not EUI() or type(name) ~= "string" or type(realmName) ~= "string" then return nil end
    local db = _G.EllesmereUIDB
    local all = type(db) == "table" and db.characterGold
    local entry = type(all) == "table" and all[name .. "-" .. realmName]
    if type(entry) ~= "table" or type(entry.gold) ~= "number" then return nil end
    return entry.gold, type(entry.lastUpdated) == "number" and entry.lastUpdated or nil
end

-------------------------------------------------------------------------------
--  Search
-------------------------------------------------------------------------------
function lib:GetBagSearchText()
    local bags = _G.EUI_Bags
    local box = type(bags) == "table" and bags._searchBox
    if type(box) == "table" and box.GetText then
        local ok, text = pcall(box.GetText, box)
        if ok and type(text) == "string" then return text end
    end
    return ""
end
