-------------------------------------------------------------------------------
--  UI/Widgets.lua
--  Small widget factory for the browser. Everything is created lazily (first
--  browser open) and styled through the EUI skin API when available, with a
--  flat dark fallback look otherwise.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local Ext = _G.EllesmereUIBagsExt
local W = {}
ns.W = W

-- EUI hands us the skin primitives once at login (registering is free and
-- runs nothing when the user disabled third-party skinning).
local skin
Ext:RegisterSkin(ADDON_NAME, function(S) skin = S end)
function W.GetSkin() return skin end

-- Title row height: EUI's shell draws a 25 px black bar behind the title.
W.HEADER_H = 25

local BG = { 0.06, 0.06, 0.06, 0.94 }
local BORDER = { 0.25, 0.25, 0.25, 1 }

function W.ApplyFlatBackdrop(frame, bg, border)
    if not frame.SetBackdrop then Mixin(frame, BackdropTemplateMixin) end
    frame:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeSize = 1 })
    bg, border = bg or BG, border or BORDER
    frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
    frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4])
end

function W.SetFont(fs, size, r, g, b)
    local path, flags = Ext:GetFont("bags")
    if not fs:SetFont(path, size or 12, flags or "") then
        fs:SetFontObject(GameFontHighlight)
    end
    if r then fs:SetTextColor(r, g, b) end
end

function W.Text(parent, size, layer, r, g, b)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    W.SetFont(fs, size, r or 1, g or 1, b or 1)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    return fs
end

function W.Window(name, width, height)
    local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    f:SetSize(width, height)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)          -- a click raises it above other HIGH windows
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if self.OnMoved then self:OnMoved() end
    end)
    if skin then
        skin.Shell(f)
    else
        W.ApplyFlatBackdrop(f)
        local bar = f:CreateTexture(nil, "BACKGROUND", nil, -5)
        bar:SetColorTexture(0, 0, 0, 0.5)
        bar:SetPoint("TOPLEFT", 1, -1)
        bar:SetPoint("TOPRIGHT", -1, -1)
        bar:SetHeight(W.HEADER_H - 1)
    end
    tinsert(UISpecialFrames, name)
    return f
end

function W.Panel(parent, inset)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    if skin then
        skin.Panel(f, inset and { inset = true } or nil)
    else
        W.ApplyFlatBackdrop(f, inset and { 0.03, 0.03, 0.03, 0.9 } or { 0.08, 0.08, 0.08, 0.9 })
    end
    return f
end

function W.Button(parent, text, width, height)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width or 100, height or 22)
    b:SetText(text or "")
    if skin then
        skin.Button(b)
        skin.WhiteButtonLabel(b)
    end
    return b
end

-- UIPanelCloseButton pins frameLevel="510" (SharedUIPanelTemplates.xml): an
-- absolute level that would draw it above every other window of the same
-- strata. Re-level it relative to its window (above EUI's border overlay, +6).
function W.CloseButton(parent)
    local b = CreateFrame("Button", nil, parent, "UIPanelCloseButton")
    b:SetFrameLevel(parent:GetFrameLevel() + 10)
    if skin then skin.CloseButton(b) end
    return b
end

function W.EditBox(parent, width, height)
    local e = CreateFrame("EditBox", nil, parent, "SearchBoxTemplate")
    e:SetSize(width or 180, height or 22)
    e:SetAutoFocus(false)
    if skin then skin.EditBox(e) end
    return e
end

function W.Scroll(parent)
    local sf = CreateFrame("ScrollFrame", nil, parent, "ScrollFrameTemplate")
    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(1, 1)
    sf:SetScrollChild(content)
    sf.content = content
    if skin and sf.ScrollBar then skin.ScrollBar(sf.ScrollBar) end
    return sf
end

function W.Tab(parent, text, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(22)
    b.label = W.Text(b, 12)
    b.label:SetPoint("CENTER")
    b.label:SetText(text)
    b:SetWidth(math.max(60, b.label:GetStringWidth() + 20))
    b.underline = b:CreateTexture(nil, "OVERLAY")
    b.underline:SetPoint("BOTTOMLEFT", 4, 0)
    b.underline:SetPoint("BOTTOMRIGHT", -4, 0)
    b.underline:SetHeight(2)
    b.underline:Hide()
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints()
    b.hl:SetColorTexture(1, 1, 1, 0.06)
    b:SetScript("OnClick", onClick)
    function b:SetSelected(selected)
        local r, g, bb = Ext:GetAccentColor()
        self.underline:SetColorTexture(r, g, bb, 1)
        self.underline:SetShown(selected)
        if selected then self.label:SetTextColor(1, 1, 1) else self.label:SetTextColor(0.6, 0.6, 0.6) end
    end
    return b
end

-- The browser's own item tooltip. Showing items through Blizzard's shared
-- GameTooltip from addon code makes its TooltipDataHandler write its state
-- (waitingForData, suppressAutomaticCompareItem, ...) in our execution
-- context, i.e. tainted; a private GameTooltipTemplate frame keeps GameTooltip
-- untouched. Created on first use.
local browserTooltip
function W.GetTooltip()
    if not browserTooltip then
        browserTooltip = CreateFrame("GameTooltip", "EllesmereUIBagsAltsTooltip", UIParent, "GameTooltipTemplate")
        browserTooltip:SetFrameStrata("TOOLTIP")
        ns.Fire("BROWSER_TOOLTIP_CREATED", browserTooltip)
    end
    return browserTooltip
end

-- Formats copper as "12,345g" (gold only; the browser is an overview).
function W.FormatGold(copper)
    if not copper then return "-" end
    local gold = math.floor(copper / 10000)
    local s = tostring(gold)
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    out = out:gsub("^,", "")
    return out .. "|cffffd700g|r"
end

-- Copper as "1,234g 56s 7c" (zero parts left out; below 1g silver/copper shown).
function W.FormatMoney(copper)
    copper = math.floor(copper or 0)
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local cop = copper % 100
    local parts = {}
    if gold > 0 then parts[#parts + 1] = W.FormatGold(copper) end
    if silver > 0 then parts[#parts + 1] = silver .. "|cffc7c7cfs|r" end
    if cop > 0 and gold == 0 then parts[#parts + 1] = cop .. "|cffeda55fc|r" end
    if #parts == 0 then return "0|cffeda55fc|r" end
    return table.concat(parts, " ")
end

function W.FormatAgo(timestamp)
    if not timestamp then return ns.L["never"] end
    local diff = time() - timestamp
    if diff < 60 then return ns.L["just now"] end
    if diff < 3600 then return string.format(ns.L["%d min ago"], math.floor(diff / 60)) end
    if diff < 86400 then return string.format(ns.L["%d h ago"], math.floor(diff / 3600)) end
    return string.format(ns.L["%d days ago"], math.floor(diff / 86400))
end

function W.ClassColor(class)
    local c = class and C_ClassColor and C_ClassColor.GetClassColor(class)
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end
