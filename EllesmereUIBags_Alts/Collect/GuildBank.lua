-------------------------------------------------------------------------------
--  Collect/GuildBank.lua   (opt-in, default OFF)
--  Guild bank tabs, readable only while the guild bank is open. The server
--  sends tab contents on request; this collector walks the viewable tabs one
--  at a time, driven purely by GUILDBANKBAGSLOTS_CHANGED (no timers):
--      open -> query tab 1 -> event -> scan tab 1, query tab 2 -> ... -> done
--  After the walk every further event rescans the tab the player is viewing.
-------------------------------------------------------------------------------
local _, ns = ...

local time = time
local MAX_GUILDBANK_SLOTS_PER_TAB = 98
local GUILD_BANKER = Enum.PlayerInteractionType.GuildBanker

local isOpen = false
local queue = {}      -- tabs still to be requested this visit
local awaiting        -- tab whose data was last requested
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
    return ns.StoreContainer(g.tabs, tab, container, ns.GuildOwner(guildKey), "guild")
end

local function CurrentGuild()
    local guildKey, guildName = ns.GetPlayerGuildKey()
    if not guildKey then return nil end
    local g = ns.GetGuild(guildKey, true)
    g.name = guildName
    g.realm = select(2, ns.SplitKey(guildKey))
    g.faction = UnitFactionGroup("player")
    return guildKey, g
end

local function RequestNext()
    awaiting = table.remove(queue, 1)
    if awaiting then QueryGuildBankTab(awaiting) end
end

local function OnSlotsChanged()
    local guildKey, g = CurrentGuild()
    if not guildKey then return end
    local changed = false
    if awaiting then
        if ScanTab(guildKey, g, awaiting) then changed = true end
        RequestNext()
    end
    local current = GetCurrentGuildBankTab()
    if current and current > 0 and ScanTab(guildKey, g, current) then changed = true end
    g.money = GetGuildBankMoney()
    g.scannedAt = time()
    if changed then ns.Fire("GUILD_UPDATED", guildKey) end
end

local function OnOpened()
    if isOpen then return end
    local guildKey, g = CurrentGuild()
    if not guildKey then return end
    isOpen = true
    wipe(queue)
    local numTabs = GetNumGuildBankTabs() or 0
    for tab = 1, numTabs do
        local _, _, isViewable = GetGuildBankTabInfo(tab)
        if isViewable then queue[#queue + 1] = tab end
    end
    -- Tabs that no longer exist (or lost view rights) are dropped.
    for tab in pairs(g.tabs) do
        if tab > numTabs then
            ns.Index:Replace(ns.GuildOwner(guildKey), "guild", g.tabs[tab].items, nil)
            g.tabs[tab] = nil
        end
    end
    ns.RegisterEvent(feature, "GUILDBANKBAGSLOTS_CHANGED", OnSlotsChanged)
    ns.RegisterEvent(feature, "GUILDBANK_UPDATE_MONEY", function()
        local _, gg = CurrentGuild()
        if gg then gg.money = GetGuildBankMoney() end
    end)
    RequestNext()
end

local function OnClosed()
    if not isOpen then return end
    isOpen = false
    awaiting = nil
    wipe(queue)
    ns.UnregisterEvent(feature, "GUILDBANKBAGSLOTS_CHANGED")
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
        awaiting = nil
        wipe(queue)
    end,
})
