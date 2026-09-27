-- Secure frames and taint, as far as wow-ui-sim models them:
--   * protected-frame enforcement: insecure caller + combat + protected frame
--     -> call is dropped and ADDON_ACTION_BLOCKED fires (verified by a positive
--     control in every run, so a silent simulator cannot fake a pass);
--   * slot taint for globals written while an addon's files load.
-- Not modelled by the simulator (and therefore NOT covered here): execution
-- taint inside event/script handlers (the simulator computes it and drops it)
-- and taint propagation into Blizzard's secure code paths. Those remain for the
-- in-game test with taintLog (README, test plan step 10).
local ns = EllesmereUIBagsAlts._ns

local blocked = {}
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("ADDON_ACTION_BLOCKED")
watcher:RegisterEvent("ADDON_ACTION_FORBIDDEN")
watcher:SetScript("OnEvent", function(_, event, addon, fn)
    blocked[#blocked + 1] = event .. " " .. tostring(addon) .. " " .. tostring(fn)
end)

local function itemTooltipInfo(itemID)
    return { tooltipData = { type = Enum.TooltipDataType.Item, id = itemID,
        lines = { { type = 0, leftText = "Item", leftColor = CreateColor(1, 1, 1) } } } }
end

local function assertNoneProtected(frame, path)
    assertTrue(not frame:IsProtected(), (path or "frame") .. " is protected")
    for i, child in ipairs({ frame:GetChildren() }) do
        assertNoneProtected(child, (path or "frame") .. "." .. i)
    end
end

-- Runs fn as insecure (addon) code, like a click or slash command would.
local function insecurely(fn)
    forceinsecure()
    return fn()
end

simtest("positive control: the simulator blocks insecure protected calls in combat", function()
    wipe(blocked)
    local probe = CreateFrame("Button", "EUIAltsSecureProbe", UIParent, "SecureActionButtonTemplate")
    assertTrue(probe:IsProtected())
    A_Admin.SetInCombat(true)
    insecurely(function() probe:Hide() end)
    A_Admin.SetInCombat(false)
    assertTrue(probe:IsShown())               -- the call was dropped
    assertEquals(1, #blocked)
    assertContains(blocked[1], "EUIAltsSecureProbe:Hide()")
end)

local function exerciseEverything()
    -- tooltip on and through Blizzard's pipeline
    ns.db.settings.tooltip.enabled = true
    ns.SettingsChanged()
    GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    GameTooltip:ProcessInfo(itemTooltipInfo(2589))
    GameTooltip:Hide()
    -- browser: open, search, switch owners/tabs, close
    SlashCmdList["EUIALTS"]("")
    ns.Browser:SetQuery("id:2589")
    ns.Browser:SetQuery("")
    ns.Browser:Select(ns.WARBAND_OWNER)
    ns.Browser:Select(ns.GetPlayerKey())
    for _, tab in ipairs({ "bank", "equipped", "mail", "auctions", "currency", "bags" }) do ns.Browser:SelectTab(tab) end
    ns.Browser:RaiseAboveSettings()
    SlashCmdList["EUIALTS"]("")
    -- header button on/off (EUI header exists; bags themselves are EUI's business)
    ns.db.settings.ui.headerButton = true
    ns.SettingsChanged()
    ns.db.settings.ui.headerButton = false
    ns.SettingsChanged()
    -- collectors, self-test, slash commands
    ns.RunSelfTest(false)
    SlashCmdList["EUIALTS"]("status")
    SlashCmdList["EUIALTS"]("options")
    SlashCmdList["EUIALTS"]("tooltip")
end

simtest_when(function() return EUI_Bags == nil or EUI_Bags.Header ~= nil end,
    "every addon path, run as insecure code in combat, touches no protected frame", function()
    wipe(blocked)
    A_Admin.SetInCombat(true)
    assertTrue(InCombatLockdown())
    insecurely(exerciseEverything)
    A_Admin.SetInCombat(false)
    if #blocked > 0 then error("blocked: " .. table.concat(blocked, " | ")) end
end)

simtest("the addon's frames are never protected", function()
    ns.Browser:Open()
    assertNoneProtected(_G.EllesmereUIBagsAltsBrowser, "browser")
    ns.Browser:Close()
    if EllesmereUIBagsExt:IsBagsLoaded() and EllesmereUIBagsExt:GetNativeAPIVersion() == 0 then
        ns.db.settings.ui.headerButton = true
        ns.SettingsChanged()
        local btn = EllesmereUIBagsExt:GetHeaderButton("EllesmereUIBags_Alts")
        if btn then assertNoneProtected(btn, "headerButton") end
        ns.db.settings.ui.headerButton = false
        ns.SettingsChanged()
    end
end)

-- Regions the ItemButton intrinsic names itself ($parentNormalTexture etc.);
-- for anonymous buttons these become fresh globals owned by the addon's frames.
local function OwnedByAddon(value)
    if type(value) ~= "table" or type(value.GetParent) ~= "function" then return false end
    local browser = _G.EllesmereUIBagsAltsBrowser
    local node = value
    for _ = 1, 20 do
        node = node:GetParent()
        if not node then return false end
        if node == browser then return true end
    end
    return false
end

simtest("taint: only the addon's own globals carry its taint", function()
    local expected = { EllesmereUIBagsAlts = true, EllesmereUIBagsAltsDB = true, EllesmereUIBagsExt = true }
    local unexpected = {}
    for key, value in pairs(_G) do
        if type(key) == "string" then
            local secure, source = issecurevariable(key)
            if not secure and source == "EllesmereUIBags_Alts" and not expected[key] and not OwnedByAddon(value) then
                unexpected[#unexpected + 1] = key
            end
        end
    end
    if #unexpected > 0 then error("tainted by the addon: " .. table.concat(unexpected, ", ")) end
    -- Blizzard / EUI tables the addon interacts with keep secure slots
    local watched = { SlashCmdList = SlashCmdList, GameTooltip = GameTooltip, ItemRefTooltip = ItemRefTooltip,
        TooltipDataProcessor = TooltipDataProcessor, EUI_Bags = EUI_Bags, EllesmereUI = EllesmereUI }
    local taintedSlots = {}
    for name, tbl in pairs(watched) do
        if type(tbl) == "table" then
            for key in pairs(tbl) do
                local secure, source = issecurevariable(tbl, key)
                if not secure and source == "EllesmereUIBags_Alts" then
                    taintedSlots[#taintedSlots + 1] = name .. "." .. tostring(key)
                end
            end
        end
    end
    if #taintedSlots > 0 then error("tainted slots: " .. table.concat(taintedSlots, ", ")) end
    -- Blizzard functions the addon hooks stay secure (hooksecurefunc, never replaced).
    -- The auction post-hooks are installed on the first auction house visit.
    assertTrue((issecurevariable("SendMail")))
    A_Admin.FireEvent("AUCTION_HOUSE_SHOW")
    for _, name in ipairs({ "PostItem", "PostCommodity", "ConfirmPostItem", "ConfirmPostCommodity" }) do
        if type(C_AuctionHouse[name]) == "function" then
            local secure, source = issecurevariable(C_AuctionHouse, name)
            assertTrue(secure or source ~= "EllesmereUIBags_Alts", "C_AuctionHouse." .. name .. " tainted by the addon")
        end
    end
    A_Admin.FireEvent("AUCTION_HOUSE_CLOSED")
    if EUI_Bags and EUI_Bags:IsShown() then ToggleAllBags() end
end)
