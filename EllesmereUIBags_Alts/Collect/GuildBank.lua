-------------------------------------------------------------------------------
--  Collect/GuildBank.lua   (opt-in, default OFF)
--  Guild bank tabs, readable only while the guild bank is open. The server
--  sends tab contents on request; this collector walks the viewable tabs one
--  at a time, driven purely by GUILDBANKBAGSLOTS_CHANGED (no timers):
--      open -> query tab 1 -> event -> scan, query tab 2 -> ... -> done
--  The event does not say which tab arrived (Blizzard's own UI queries tabs
--  too), so every event rescans all tabs requested so far this visit: tab
--  data stays cached once received, so an early scan of a tab that had not
--  arrived yet is simply corrected by the next event.
--  On the first visit of a session the tab list itself arrives after the
--  bank opened (GetNumGuildBankTabs() is 0 until GUILDBANK_UPDATE_TABS), so
--  the walk is (re)filled from that event, and stored tabs are only pruned
--  against a known, non-empty tab list.
-------------------------------------------------------------------------------
local _, ns = ...

local time = time
local MAX_GUILDBANK_SLOTS_PER_TAB = 98
local GUILD_BANKER = Enum.PlayerInteractionType.GuildBanker

local isOpen = false
local queue = {}      -- tabs still to be requested this visit
local requested = {}  -- tabs requested (or viewed) this visit -> true
local queued = {}     -- tabs in the queue -> true
local awaiting = false  -- a QueryGuildBankTab answer is outstanding
local feature

local function ScanTab(guildKey, g, tab)
    local name, icon, isViewable = GetGuildBankTabInfo(tab)
    if not isViewable then return false end
    local items = {}
    for slot = 1, MAX_GUILDBANK_SLOTS_PER_TAB do
        local link = GetGuildBankItemLink(tab, slot)
        if link then
            if ns.IsSecret(link) then return false end
            local _, count = GetGuildBankItemInfo(tab, slot)
            local id = C_Item.GetItemInfoInstant(link)
            if id then items[slot] = ns.EncodeItem(id, count or 1, link) end
        end
    end
    local container = { size = MAX_GUILDBANK_SLOTS_PER_TAB, name = name, icon = icon, items = items }
    local changed = ns.StoreContainer(g.tabs, tab, container, ns.GuildOwner(guildKey), "guild")
    if changed then
        local n = 0
        for _ in pairs(items) do n = n + 1 end
        ns.Debug("guildbank", "tab %d (%s): %d stacks", tab, name, n)
    end
    return changed
end

-- -> guildKey, record, isNew (record created or renamed now)
local function CurrentGuild()
    local guildKey, guildName = ns.GetPlayerGuildKey()
    if not guildKey then return nil end
    local isNew = ns.GetGuild(guildKey) == nil
    local g = ns.GetGuild(guildKey, true)
    if g.name ~= guildName then isNew = true end
    g.name = guildName
    g.realm = select(2, ns.SplitKey(guildKey))
    g.faction = UnitFactionGroup("player")
    return guildKey, g, isNew
end

local function RequestNext()
    local tab = table.remove(queue, 1)
    awaiting = tab ~= nil
    if tab then
        queued[tab] = nil
        requested[tab] = true
        QueryGuildBankTab(tab)
    end
end

-- Queues every viewable tab not requested yet; -> number of tabs in the list.
local function EnqueueViewableTabs()
    local numTabs = GetNumGuildBankTabs() or 0
    for tab = 1, numTabs do
        local _, _, isViewable = GetGuildBankTabInfo(tab)
        if isViewable and not requested[tab] and not queued[tab] then
            queue[#queue + 1] = tab
            queued[tab] = true
        end
    end
    return numTabs
end

-- Tabs that no longer exist are dropped, but only against a known list: the
-- client reports 0 tabs until the list of a new session has arrived.
local function PruneTabs(guildKey, g, numTabs)
    if numTabs <= 0 then return false end
    local changed = false
    for tab in pairs(g.tabs) do
        if tab > numTabs then
            ns.Index:Replace(ns.GuildOwner(guildKey), "guild", g.tabs[tab].items, nil)
            g.tabs[tab] = nil
            changed = true
        end
    end
    return changed
end

local function OnSlotsChanged()
    local guildKey, g = CurrentGuild()
    if not guildKey then return end
    local current = GetCurrentGuildBankTab()
    if current and current > 0 then requested[current] = true end
    local changed = false
    for tab in pairs(requested) do
        if ScanTab(guildKey, g, tab) then changed = true end
    end
    awaiting = false
    RequestNext()
    g.money = GetGuildBankMoney()
    g.scannedAt = time()
    if changed then ns.Fire("GUILD_UPDATED", guildKey) end
end

local function OnTabsUpdated()
    local guildKey, g = CurrentGuild()
    if not guildKey then return end
    local numTabs = EnqueueViewableTabs()
    ns.Debug("guildbank", "tab list: %d tabs, %d queued", numTabs, #queue)
    if PruneTabs(guildKey, g, numTabs) then ns.Fire("GUILD_UPDATED", guildKey) end
    if not awaiting then RequestNext() end
end

local function ResetVisit()
    wipe(queue)
    wipe(queued)
    wipe(requested)
    awaiting = false
end

local function OnOpened()
    if isOpen then return end
    local guildKey, g, isNew = CurrentGuild()
    if not guildKey then return end
    isOpen = true
    ResetVisit()
    local numTabs = EnqueueViewableTabs()
    ns.Debug("guildbank", "opened %s: %d tabs known, %d queued", guildKey, numTabs, #queue)
    local pruned = PruneTabs(guildKey, g, numTabs)
    if isNew or pruned then ns.Fire("GUILD_UPDATED", guildKey) end
    ns.RegisterEvent(feature, "GUILDBANKBAGSLOTS_CHANGED", OnSlotsChanged)
    ns.RegisterEvent(feature, "GUILDBANK_UPDATE_TABS", OnTabsUpdated)
    ns.RegisterEvent(feature, "GUILDBANK_UPDATE_MONEY", function()
        local _, gg = CurrentGuild()
        if gg then gg.money = GetGuildBankMoney() end
    end)
    RequestNext()
end

local function OnClosed()
    if not isOpen then return end
    isOpen = false
    ResetVisit()
    ns.UnregisterEvent(feature, "GUILDBANKBAGSLOTS_CHANGED")
    ns.UnregisterEvent(feature, "GUILDBANK_UPDATE_TABS")
    ns.UnregisterEvent(feature, "GUILDBANK_UPDATE_MONEY")
end

feature = ns.RegisterFeature({
    key = "guildbank",
    IsEnabled = function(s) return s.collect.guildbank end,
    OnEnable = function(self)
        ns.RegisterEvent(self, "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(_, _, interaction)
            if interaction == GUILD_BANKER then OnOpened() end
        end)
        ns.RegisterEvent(self, "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(_, _, interaction)
            if interaction == GUILD_BANKER then OnClosed() end
        end)
    end,
    OnDisable = function()
        isOpen = false
        ResetVisit()
    end,
})
