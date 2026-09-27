-- Geometry helpers for layout invariants: rectangles as the simulator lays
-- them out from the real anchors (GetRect), text measured with GetStringWidth.
EUIAltsLayout = {}
local L = EUIAltsLayout

local TOL = 0.5   -- sub-pixel slack for float layout

-- -> { l, r, b, t } or nil for regions without a resolved rect
function L.Rect(region)
    local left, bottom, width, height = region:GetRect()
    if not left or not width or not height then return nil end
    return { l = left, r = left + width, b = bottom, t = bottom + height, w = width, h = height }
end

-- The painted part of a FontString: its text, not the whole anchored box.
function L.TextRect(fs)
    local rect = L.Rect(fs)
    if not rect then return nil end
    local sw = fs:GetStringWidth() or 0
    if sw < rect.w then
        local justify = fs:GetJustifyH()
        if justify == "RIGHT" then rect.l = rect.r - sw
        elseif justify == "CENTER" then
            local mid = (rect.l + rect.r) / 2
            rect.l, rect.r = mid - sw / 2, mid + sw / 2
        else rect.r = rect.l + sw end
        rect.w = sw
    end
    return rect
end

function L.Inside(inner, outer)
    return inner.l >= outer.l - TOL and inner.r <= outer.r + TOL and inner.b >= outer.b - TOL and inner.t <= outer.t + TOL
end

function L.InsideX(inner, outer)
    return inner.l >= outer.l - TOL and inner.r <= outer.r + TOL
end

function L.Overlap(a, b)
    return a.l < b.r - TOL and b.l < a.r - TOL and a.b < b.t - TOL and b.b < a.t - TOL
end

function L.Describe(name, rect)
    if not rect then return name .. "=<none>" end
    return string.format("%s=[%.1f..%.1f x %.1f..%.1f]", name, rect.l, rect.r, rect.b, rect.t)
end

local function IsText(region) return region.GetStringWidth ~= nil and region:IsObjectType("FontString") end

-- Calls fn(region, isFrame) for every visible frame and region below root.
function L.Walk(root, fn)
    local function visit(frame)
        for _, child in ipairs({ frame:GetChildren() }) do
            if child:IsVisible() then
                fn(child, true)
                visit(child)
            end
        end
        for _, region in ipairs({ frame:GetRegions() }) do
            if region:IsVisible() then fn(region, false) end
        end
    end
    visit(root)
end

-- Not painted, or painted with known transparent padding:
--  * alpha 0 (EUI's item skin fades the stock slot art this way)
--  * an ItemButton's NormalTexture: UI-Quickslot2 is a 64 px file around a
--    37 px slot, the extra is transparent (and clipped by the scroll frame)
local function Unpainted(region)
    if region:GetAlpha() == 0 then return true end
    local parent = region:GetParent()
    -- ItemButton intrinsic: recognised by its IconBorder field
    return parent and parent.IconBorder ~= nil and parent.GetNormalTexture ~= nil
        and parent:GetNormalTexture() == region or false
end

-- Every painted element stays inside the window; the scroll child may run
-- past the bottom (it scrolls) but never sideways. -> list of offenders
function L.Escapees(window, scrollFrame)
    local out = {}
    local win = L.Rect(window)
    local clip = scrollFrame and L.Rect(scrollFrame)
    local scrollChild = scrollFrame and scrollFrame:GetScrollChild()
    local function underScroll(region)
        if region == scrollChild then return true end
        local p = region:GetParent()
        while p do
            if p == scrollChild then return true end
            p = p:GetParent()
        end
        return false
    end
    L.Walk(window, function(region)
        local rect = not Unpainted(region) and (IsText(region) and L.TextRect(region) or L.Rect(region))
        if rect and rect.w > 0 and rect.h > 0 then
            local ok
            if underScroll(region) then ok = L.InsideX(rect, clip) else ok = L.Inside(rect, win) end
            if not ok then
                out[#out + 1] = L.Describe(region:GetDebugName() or region:GetObjectType(), rect)
            end
        end
    end)
    return out
end

-- Pairs of the given regions that overlap. items: { { name, rect }, ... }
function L.Overlaps(items)
    local out = {}
    for i = 1, #items do
        for j = i + 1, #items do
            if items[i][2] and items[j][2] and L.Overlap(items[i][2], items[j][2]) then
                out[#out + 1] = L.Describe(items[i][1], items[i][2]) .. " vs " .. L.Describe(items[j][1], items[j][2])
            end
        end
    end
    return out
end

-- Frames whose level runs far above their window (absolute template levels).
function L.LevelOutliers(window, maxAbove)
    local out = {}
    local limit = window:GetFrameLevel() + maxAbove
    L.Walk(window, function(region, isFrame)
        if isFrame and region:GetFrameLevel() > limit then
            out[#out + 1] = (region:GetDebugName() or "?") .. " level " .. region:GetFrameLevel()
        end
    end)
    return out
end

function L.AssertNone(list, what)
    if #list > 0 then error(what .. ": " .. table.concat(list, "; "), 2) end
end
