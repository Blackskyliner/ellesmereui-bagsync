-------------------------------------------------------------------------------
--  Core/SelfTest.lua
--  /alts selftest -- verifies the live game against the stored data, so the
--  real client can confirm what the offline test suite simulates:
--    1. every API this addon calls exists in this client build
--    2. stored bag + equipped counts match C_Item.GetItemCount for each item
--    3. the incrementally maintained index equals a fresh rebuild
-------------------------------------------------------------------------------
local _, ns = ...
local L = ns.L

local REQUIRED_APIS = {
    "C_Container.GetContainerNumSlots", "C_Container.GetContainerItemInfo",
    "C_Bank.CanViewBank", "C_Bank.FetchPurchasedBankTabData", "C_Bank.FetchDepositedMoney",
    "C_Item.GetItemInfo", "C_Item.GetItemInfoInstant", "C_Item.GetItemCount",
    "C_Item.GetItemQualityByID", "C_Item.RequestLoadItemDataByID",
    "C_CurrencyInfo.GetCurrencyListSize", "C_CurrencyInfo.GetCurrencyListInfo",
    "C_CurrencyInfo.GetCurrencyInfo", "C_CurrencyInfo.GetCurrencyListLink",
    "C_CurrencyInfo.GetCurrencyIDFromLink", "C_AutoComplete.GetAutoCompleteRealms",
    "C_ClassColor.GetClassColor", "TooltipDataProcessor.AddTooltipPostCall",
    "Settings.RegisterVerticalLayoutCategory", "Settings.RegisterProxySetting",
    "GetInboxNumItems", "GetInboxHeaderInfo", "GetInboxItem", "GetInboxItemLink",
    "GetSendMailItem", "GetSendMailItemLink", "GetInventoryItemLink", "GetInventoryItemID",
    "GetNumGuildBankTabs", "GetGuildBankTabInfo", "GetGuildBankItemInfo", "GetGuildBankItemLink",
    "QueryGuildBankTab", "GetCurrentGuildBankTab", "GetGuildBankMoney", "GetGuildInfo",
    "C_AuctionHouse.GetOwnedAuctions", "C_AuctionHouse.HasFullOwnedAuctionResults",
    "C_AuctionHouse.QueryOwnedAuctions", "C_AuctionHouse.PostItem", "C_AuctionHouse.PostCommodity",
    "C_AuctionHouse.ConfirmPostItem", "C_AuctionHouse.ConfirmPostCommodity", "C_AuctionHouse.CancelAuction",
    "C_AuctionHouse.GetNumOwnedAuctions", "C_AuctionHouse.GetOwnedAuctionInfo",
    "C_Item.DoesItemExist", "C_Item.GetItemID", "C_Item.GetItemLink",
    "GetNormalizedRealmName", "HandleModifiedItemClick", "SetItemButtonTexture",
    "SetItemButtonCount", "SetItemButtonQuality",
}

local function Resolve(path)
    local node = _G
    for part in path:gmatch("[^%.]+") do
        if type(node) ~= "table" then return nil end
        node = node[part]
    end
    return node
end

local function CheckAPIs(report)
    local missing = {}
    for _, path in ipairs(REQUIRED_APIS) do
        if type(Resolve(path)) ~= "function" then missing[#missing + 1] = path end
    end
    report.missingAPIs = missing
    return #missing == 0
end

local function CheckCounts(report)
    local c = ns.GetPlayerChar(false)
    if not c then
        report.countError = "no data for the current character"
        return false
    end
    local stored = {}
    local function add(items)
        for _, enc in pairs(items or {}) do
            local id, count = ns.DecodeItemIDCount(enc)
            if id then stored[id] = (stored[id] or 0) + count end
        end
    end
    for _, cont in pairs(c.bags) do add(cont.items) end
    local bagsOnly = {}
    for id, n in pairs(stored) do bagsOnly[id] = n end
    if c.equipped then add(c.equipped.items) end

    local mismatches, checked = {}, 0
    for id, withEquipped in pairs(stored) do
        checked = checked + 1
        local live = C_Item.GetItemCount(id, false, false, false, false)
        -- GetItemCount includes worn gear for equippable items; accept either view.
        if live ~= withEquipped and live ~= (bagsOnly[id] or 0) then
            mismatches[#mismatches + 1] = string.format("%d: stored %d, game %d", id, withEquipped, live or -1)
        end
    end
    report.countsChecked = checked
    report.countMismatches = mismatches
    return #mismatches == 0
end

local function DeepEqual(a, b)
    for k, v in pairs(a) do
        if type(v) == "table" then
            if type(b[k]) ~= "table" or not DeepEqual(v, b[k]) then return false end
        elseif b[k] ~= v then
            return false
        end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

local function CheckIndex(report)
    local Index = ns.Index
    Index:EnsureBuilt()
    local incremental = Index.data
    local fresh = {}
    Index.data = fresh
    Index:Build()
    fresh = Index.data
    local ok = DeepEqual(incremental, fresh)
    report.indexConsistent = ok
    return ok
end

-- Runs all checks. verbose=true prints to chat. Returns ok, report.
function ns.RunSelfTest(verbose)
    local report = {}
    -- Make sure the latest bag state is stored before comparing.
    local bags = ns.featureByKey.bags
    if bags and bags.active and bags.Flush then bags:Flush() end

    local apiOK = CheckAPIs(report)
    local countsOK = CheckCounts(report)
    local indexOK = CheckIndex(report)
    local ok = apiOK and countsOK and indexOK
    ns.lastSelfTest = report

    if verbose then
        ns.Print("%s: %s", L["Self-test"], ok and "|cff40ff40OK|r" or "|cffff4040FAILED|r")
        ns.Print("  APIs: %s", apiOK and "ok" or ("missing " .. table.concat(report.missingAPIs, ", ")))
        if report.countError then
            ns.Print("  %s: %s", L["Counts"], report.countError)
        else
            ns.Print("  %s: %d %s, %d %s", L["Counts"], report.countsChecked or 0, L["items checked"],
                #report.countMismatches, L["mismatches"])
            for i = 1, math.min(5, #report.countMismatches) do ns.Print("    %s", report.countMismatches[i]) end
        end
        ns.Print("  Index: %s", indexOK and "ok" or "inconsistent (rebuilt)")
    end
    return ok, report
end
