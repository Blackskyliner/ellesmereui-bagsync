-- Browser window chrome: title row inside the shell's title bar and no frame
-- above other windows of the same strata.
local wow = require("wow")
local fakeEUI = require("fake_eui")

local function open(withEUI)
    local env, ns = wow.boot(wow.defaultState(), nil, withEUI and {
        beforeLoad = function(e) fakeEUI.install(e) end,
    } or nil)
    ns.Browser:Open()
    return env, ns, env.EllesmereUIBagsAltsBrowser
end

-- The anchor puts the widget's vertical centre on the header's centre line.
local function centredInHeader(f, widget)
    local p = widget.points[1]
    local point, rel, relPoint, _, y = p[1], p[2], p[3], p[4], p[5]
    assert.truthy(point == "LEFT" or point == "RIGHT" or point == "CENTER", point)
    assert.truthy(relPoint == "LEFT" or relPoint == "RIGHT" or relPoint == "CENTER", relPoint)
    assert.are.equal(0, y or 0)
    -- anchored to the header, or to a widget that is itself centred in it
    if rel ~= f.header then centredInHeader(f, rel) end
end

for _, withEUI in ipairs({ true, false }) do
    describe("Browser chrome (" .. (withEUI and "EUI skin" or "fallback") .. ")", function()
        it("keeps title, search and close button inside the 25 px title bar", function()
            local env, ns, f = open(withEUI)
            assert.are.equal(ns.W.HEADER_H, f.header:GetHeight())
            assert.are.equal(25, ns.W.HEADER_H)
            for _, w in ipairs({ f.title, f.search, f.close }) do centredInHeader(f, w) end
            assert.is_true(f.search:GetHeight() <= ns.W.HEADER_H - 2)
            assert.is_true(f.close:GetHeight() <= ns.W.HEADER_H - 2)
            -- content starts below the bar
            assert.is_true(-f.sidebar.points[1][3] >= ns.W.HEADER_H)
            assert.are.same({}, env.__errors)
        end)

        it("levels the close button relative to its window, not at the template's 510", function()
            local _, _, f = open(withEUI)
            local level = f.close:GetFrameLevel()
            assert.is_true(level > f:GetFrameLevel())
            assert.is_true(level <= f:GetFrameLevel() + 10)
            assert.are.equal(f:GetFrameStrata(), f.close:GetFrameStrata())
        end)

        it("no browser frame pins an absolute frame level", function()
            local _, _, f = open(withEUI)
            local function walk(frame)
                assert.is_true(frame:GetFrameLevel() < 100, tostring(frame.template))
                for _, child in ipairs(frame.children or {}) do walk(child) end
            end
            walk(f)
        end)
    end)
end
