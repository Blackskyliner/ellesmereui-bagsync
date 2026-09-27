-------------------------------------------------------------------------------
--  Collect/Auctions.lua
--  Your own active auctions, per character.
--
--  Owned auctions are only known while an auctioneer is open. By default this
--  collector is passive: it reads C_AuctionHouse.GetOwnedAuctions() whenever
--  the client reports fresh data (OWNED_AUCTIONS_UPDATED, e.g. when the
--  Auctions tab is opened or after posting) and never sends server requests of
--  its own, so it cannot interfere with the auction house search throttle.
--  The opt-in setting collect.auctionsQuery issues one QueryOwnedAuctions when
--  the auction house opens (the same call and sorts Blizzard's UI uses).
--
--  Only Active auctions count (Sold ones no longer hold the item). A cancelled
--  or expired auction is mailed back by the game, so it moves straight into
--  the owner's "in transit" mail; expired entries are dropped at login.
-------------------------------------------------------------------------------
local _, ns = ...

local time = time
local AUCTIONEER = Enum.PlayerInteractionType.Auctioneer
local STATUS_ACTIVE = Enum.AuctionStatus.Active
local PET_CAGE_ITEM_ID = 82800

-- Upper bound of each time-left band (seconds), used when timeLeftSeconds is nil.
local BAND_SECONDS = {
    [Enum.AuctionHouseTimeLeftBand.Short] = 30 * 60,
    [Enum.AuctionHouseTimeLeftBand.Medium] = 2 * 3600,
    [Enum.AuctionHouseTimeLeftBand.Long] = 12 * 3600,
    [Enum.AuctionHouseTimeLeftBand.VeryLong] = 48 * 3600,
}

local OWNED_SORTS = {
    { sortOrder = Enum.AuctionHouseSortOrder.Name, reverseSort = false },
    { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false },
}

local isOpen = false
local feature

local function AuctionsOf(c)
    if type(c.auctions) ~= "table" then c.auctions = { items = {} } end
    return c.auctions
end

-- OwnedAuctionInfo -> stored entry { e = enc, x = expires, id = auctionID } or nil
local function EntryFromInfo(info, now)
    if type(info) ~= "table" or info.status ~= STATUS_ACTIVE then return nil end
    local key = info.itemKey
    local itemID = key and key.itemID
    if not itemID or ns.IsSecret(itemID) or ns.IsSecret(info.quantity) then return nil end
    local link = info.itemLink
    if link and ns.IsSecret(link) then link = nil end
    if key.battlePetSpeciesID and key.battlePetSpeciesID > 0 then itemID = PET_CAGE_ITEM_ID end
    local seconds = info.timeLeftSeconds
    if type(seconds) ~= "number" or ns.IsSecret(seconds) then
        seconds = BAND_SECONDS[info.timeLeft] or BAND_SECONDS[Enum.AuctionHouseTimeLeftBand.VeryLong]
    end
    return { e = ns.EncodeItem(itemID, info.quantity or 1, link), x = now + seconds, id = info.auctionID }
end

local function ScanOwned()
    local key = ns.GetPlayerKey()
    local c = key and ns.GetChar(key, true)
    if not c then return end
    -- Partial results would under-count: keep the last full list until the
    -- client has everything (another OWNED_AUCTIONS_UPDATED follows).
    if not C_AuctionHouse.HasFullOwnedAuctionResults() then return end
    local owned = C_AuctionHouse.GetOwnedAuctions()
    if type(owned) ~= "table" then return end
    local now = time()
    local items = {}
    for i = 1, #owned do
        local entry = EntryFromInfo(owned[i], now)
        if entry then items[#items + 1] = entry end
    end
    local auctions = AuctionsOf(c)
    ns.Index:Replace(key, "auctions", auctions.items, items)
    auctions.items = items
    auctions.scannedAt = now
    ns.Fire("CHAR_UPDATED", key, "auctions")
end

-- A cancelled/expired auction leaves the list and arrives by mail.
local function MoveToMail(auctionID)
    local key = ns.GetPlayerKey()
    local c = key and ns.GetChar(key, false)
    if not c or not auctionID then return end
    local auctions = AuctionsOf(c)
    local kept, moved = {}, {}
    for _, entry in ipairs(auctions.items) do
        if entry.id == auctionID then moved[#moved + 1] = entry else kept[#kept + 1] = entry end
    end
    if #moved == 0 then return end
    ns.Index:Replace(key, "auctions", auctions.items, kept)
    auctions.items = kept
    local encs = {}
    for i = 1, #moved do encs[i] = moved[i].e end
    ns.AddIncomingMail(key, encs, key)
    ns.Fire("CHAR_UPDATED", key, "auctions")
end

local function OnOpened()
    if isOpen then return end
    isOpen = true
    ns.RegisterEvent(feature, "OWNED_AUCTIONS_UPDATED", ScanOwned)
    ns.RegisterEvent(feature, "AUCTION_CANCELED", function(_, _, auctionID) MoveToMail(auctionID) end)
    ns.RegisterEvent(feature, "AUCTION_HOUSE_AUCTIONS_EXPIRED", function(_, _, auctionID) MoveToMail(auctionID) end)
    ns.RegisterEvent(feature, "AUCTION_HOUSE_AUCTION_CREATED", function()
        if ns.db.settings.collect.auctionsQuery then C_AuctionHouse.QueryOwnedAuctions(OWNED_SORTS) end
    end)
    ScanOwned()   -- results the client already holds (no-op unless complete)
    if ns.db.settings.collect.auctionsQuery then C_AuctionHouse.QueryOwnedAuctions(OWNED_SORTS) end
end

local function OnClosed()
    if not isOpen then return end
    isOpen = false
    ns.UnregisterEvent(feature, "OWNED_AUCTIONS_UPDATED")
    ns.UnregisterEvent(feature, "AUCTION_CANCELED")
    ns.UnregisterEvent(feature, "AUCTION_HOUSE_AUCTIONS_EXPIRED")
    ns.UnregisterEvent(feature, "AUCTION_HOUSE_AUCTION_CREATED")
end

-- Drops auctions whose time ran out (the item came back by mail).
function ns.PruneExpiredAuctions()
    if not ns.db then return end
    local now = time()
    local changed = false
    for _, c in pairs(ns.db.chars) do
        if type(c.auctions) == "table" and type(c.auctions.items) == "table" then
            local kept = {}
            for _, entry in ipairs(c.auctions.items) do
                if entry.x and entry.x <= now then changed = true else kept[#kept + 1] = entry end
            end
            c.auctions.items = kept
        end
    end
    if changed then ns.Index:Invalidate() end
end

feature = ns.RegisterFeature({
    key = "auctions",
    IsEnabled = function(s) return s.collect.auctions end,
    OnEnable = function(self)
        ns.PruneExpiredAuctions()
        ns.RegisterEvent(self, "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(_, _, interaction)
            if interaction == AUCTIONEER then OnOpened() end
        end)
        ns.RegisterEvent(self, "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(_, _, interaction)
            if interaction == AUCTIONEER then OnClosed() end
        end)
        ns.RegisterEvent(self, "AUCTION_HOUSE_SHOW", OnOpened)
        ns.RegisterEvent(self, "AUCTION_HOUSE_CLOSED", OnClosed)
    end,
    OnDisable = function()
        isOpen = false
    end,
})
