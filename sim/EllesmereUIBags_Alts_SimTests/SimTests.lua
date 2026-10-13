-- wow-ui-sim runs tests/*.lua of this addon after startup. Sync test failures
-- are reported through print(), which the simulator does not always flush;
-- async tests report on stderr, so every test is wrapped as an async test.
function simtest(name, fn)
    async_test(name, function(done) done(fn) end)
end

-- Like simtest, but waits (one check per simulator frame) until cond() is
-- true, e.g. for EllesmereUI Bags, which builds its window 0.5 s after login.
-- Never true -> the simulator reports a timeout, i.e. a failure.
function simtest_when(cond, name, fn)
    async_test(name, function(done)
        local f = CreateFrame("Frame")
        f:SetScript("OnUpdate", function(self)
            if cond() then
                self:SetScript("OnUpdate", nil)
                done(fn)
            end
        end)
    end)
end

-- Item tooltips the way the client shows them: Blizzard's secure code calls
-- GameTooltip, and C_TooltipInfo hands it data written untainted. Test code
-- that reads the addon's globals runs tainted by the addon (Elune taints
-- execution that reads tainted values); calling GameTooltip from there, or
-- handing it fields written there, would write GameTooltip's own fields with
-- that taint, which 08_secure_combat.lua then reports against the addon.
-- The simulator's C_TooltipInfo.GetItemByID returns item data without id,
-- hyperlink or guid (the client always sets id; see Blizzard's
-- TooltipUtil.GetDisplayedItem), so the data is built here in the client's
-- shape and runs Blizzard's real pipeline (pre-calls, ProcessLines,
-- TooltipDataProcessor post-calls) from ProcessInfo on.
local function untainted(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for k, v in pairs(value) do securecallfunction(rawset, copy, k, untainted(v)) end
    return copy
end

function simShowItemTooltip(itemID, name)
    local info = { tooltipData = { type = Enum.TooltipDataType.Item, id = itemID,
        lines = { { type = 0, leftText = name or "Item", leftColor = securecallfunction(CreateColor, 1, 1, 1) } } } }
    securecallfunction(GameTooltip.SetOwner, GameTooltip, UIParent, "ANCHOR_NONE")
    securecallfunction(GameTooltip.ProcessInfo, GameTooltip, untainted(info))
end

function simHideTooltip()
    securecallfunction(GameTooltip.Hide, GameTooltip)
end
