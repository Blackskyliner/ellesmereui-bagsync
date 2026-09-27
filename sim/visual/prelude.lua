-- Shared setup for screenshot scenarios (prepended to every scenario file).
-- Fixture data, browser at the screen's top-left corner, default scale.
EUIAltsSimFixture.Install()
local ns = EllesmereUIBagsAlts._ns

function VisualScene(owner, tab, query)
    ns.Browser:Open(owner)
    if tab then ns.Browser:SelectTab(tab) end
    ns.Browser:SetQuery(query or "")
    local f = EllesmereUIBagsAltsBrowser
    if query then
        f.search:SetText(query)
        -- The client fires OnTextChanged(userInput=false) on SetText (hiding
        -- the template's "Search" instructions); the simulator does not.
        f.search:GetScript("OnTextChanged")(f.search, false)
    end
    f:SetScale(1)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
    ns.Browser:Refresh()
    return f
end

-- Hover the first element of a pool (or a grid button) matching pred.
function VisualHover(list, count, pred)
    for i = 1, count do
        local e = list[i]
        if pred(e) then
            e:GetScript("OnEnter")(e)
            return e
        end
    end
    error("VisualHover: nothing matched")
end
