-------------------------------------------------------------------------------
--  Collect/Bank.lua
--  Character bank tabs and the warband (account) bank.
--
--  Bank contents are only readable while a banker interaction is open. While
--  closed this feature listens to the open/close events only; the item events
--  are registered for the duration of the visit (acceptance criterion 3).
--
--  Tab IDs from C_Bank.FetchPurchasedBankTabData are container IDs
--  (Enum.BagIndex.CharacterBankTab_1.. / AccountBankTab_1..), exactly what
--  Blizzard's BankPanelMixin passes to C_Container.
-------------------------------------------------------------------------------
local _, ns = ...

local time = time
local BankType = Enum.BankType
local PIT = Enum.PlayerInteractionType

local BANKER_TYPES = {
    [PIT.Banker] = true,
    [PIT.CharacterBanker] = true,
    [PIT.AccountBanker] = true,
}

local isOpen = false
local dirty = ns.NewDirtySet()
local tabOwner = {}   -- bagID -> "character" | "account" for the tabs seen this visit

local feature

local function Owner(kind)
    if kind == "account" then return ns.WARBAND_OWNER, "warband" end
    return ns.GetPlayerKey(), "bank"
end

local function TargetMap(kind)
    if kind == "account" then
        return ns.db.warband.bank
    end
    local c = ns.GetPlayerChar(true)
    return c and c.bank
end

local function StampScan(kind)
    if kind == "account" then
        ns.db.warband.bankAt = time()
    else
        local c = ns.GetPlayerChar(true)
        if c then c.bankAt = time() end
    end
end

local function FetchTabs(bankType)
    if not C_Bank.CanViewBank(bankType) then return nil end
    local tabs = C_Bank.FetchPurchasedBankTabData(bankType)
    if type(tabs) ~= "table" or ns.IsSecret(tabs) then return nil end
    return tabs
end

-- Full rescan of one bank type. Returns true when anything changed.
local function ScanBankType(kind, bankType)
    local tabs = FetchTabs(bankType)
    if not tabs then return false end
    local map = TargetMap(kind)
    if not map then return false end
    local owner, loc = Owner(kind)
    local scanned = {}
    for i = 1, #tabs do
        local tab = tabs[i]
        local bagID = tab.ID
        if bagID then
            local container, secret = ns.ScanContainer(bagID)
            if secret then return false end
            container.name = tab.name
            container.icon = tab.icon
            scanned[bagID] = container
            tabOwner[bagID] = kind
        end
    end
    local changed = ns.StoreContainerMap(map, scanned, owner, loc)
    StampScan(kind)
    return changed
end

local function ScanAll()
    local a = ScanBankType("character", BankType.Character)
    local b = ScanBankType("account", BankType.Account)
    if a then ns.Fire("CHAR_UPDATED", ns.GetPlayerKey(), "bank") end
    if b then ns.Fire("WARBAND_UPDATED") end
end

local function CaptureWarbandMoney()
    local money = C_Bank.FetchDepositedMoney(BankType.Account)
    if money and not ns.IsSecret(money) then
        ns.db.warband.money = money
        ns.db.warband.moneyAt = time()
    end
end

local function FlushDirty()
    if dirty:IsEmpty() then return end
    local changedChar, changedAccount = false, false
    dirty:Flush(function(bagID)
        local kind = tabOwner[bagID]
        if not kind then return true end
        local map = TargetMap(kind)
        if not map then return true end
        local container, secret = ns.ScanContainer(bagID)
        if secret then return false end
        local owner, loc = Owner(kind)
        if ns.StoreContainer(map, bagID, container, owner, loc) then
            if kind == "account" then changedAccount = true else changedChar = true end
        end
        return true
    end)
    if changedChar then
        StampScan("character")
        ns.Fire("CHAR_UPDATED", ns.GetPlayerKey(), "bank")
    end
    if changedAccount then
        StampScan("account")
        ns.Fire("WARBAND_UPDATED")
    end
end

local function OnBankOpened()
    if isOpen then return end
    isOpen = true
    wipe(tabOwner)
    ns.RegisterEvent(feature, "BAG_UPDATE", function(_, _, bagID)
        if tabOwner[bagID] then dirty:Mark(bagID) end
    end)
    ns.RegisterEvent(feature, "BAG_UPDATE_DELAYED", FlushDirty)
    ns.RegisterEvent(feature, "BANK_TABS_CHANGED", ScanAll)
    ns.RegisterEvent(feature, "BANK_TAB_SETTINGS_UPDATED", ScanAll)
    ns.RegisterEvent(feature, "ACCOUNT_MONEY", CaptureWarbandMoney)
    ScanAll()
    CaptureWarbandMoney()
end

local function OnBankClosed()
    if not isOpen then return end
    FlushDirty()
    isOpen = false
    dirty:Clear()
    ns.UnregisterEvent(feature, "BAG_UPDATE")
    ns.UnregisterEvent(feature, "BAG_UPDATE_DELAYED")
    ns.UnregisterEvent(feature, "BANK_TABS_CHANGED")
    ns.UnregisterEvent(feature, "BANK_TAB_SETTINGS_UPDATED")
    ns.UnregisterEvent(feature, "ACCOUNT_MONEY")
end

feature = ns.RegisterFeature({
    key = "bank",
    IsEnabled = function(s) return s.collect.bank end,
    OnEnable = function(self)
        ns.RegisterEvent(self, "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(_, _, interaction)
            if BANKER_TYPES[interaction] then OnBankOpened() end
        end)
        ns.RegisterEvent(self, "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(_, _, interaction)
            if BANKER_TYPES[interaction] then OnBankClosed() end
        end)
        -- Also covered by the interaction manager; kept as a belt-and-braces signal.
        ns.RegisterEvent(self, "BANKFRAME_OPENED", OnBankOpened)
        ns.RegisterEvent(self, "BANKFRAME_CLOSED", OnBankClosed)
        -- Started while the bank is open (the visit that activated the addon).
        for interaction in pairs(BANKER_TYPES) do
            if ns.IsInteracting(interaction) then OnBankOpened() break end
        end
    end,
    OnDisable = function()
        isOpen = false
        dirty:Clear()
        wipe(tabOwner)
    end,
})

function ns.IsBankOpen() return isOpen end
