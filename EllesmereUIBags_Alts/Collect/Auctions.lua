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
--  the owner's "in transit" mail: on AUCTION_CANCELED / AUCTION_HOUSE_AUCTIONS_EXPIRED
--  while the auction house is open, and at login for auctions whose time ran
--  out meanwhile. Auctions seen during the visit are remembered by ID, so a
--  cancel still reaches the mail when a fresh list already dropped the auction,
--  and each auction is mailed at most once.
--
--  Freshly posted auctions appear right away: post-hooks (hooksecurefunc, never
--  replacing Blizzard's call) on C_AuctionHouse.PostItem/PostCommodity and
--  their Confirm* variants note item, quantity and duration; the next
--  AUCTION_HOUSE_AUCTION_CREATED(auctionID) appends that auction. A post that
--  needs confirmation (AUCTION_HOUSE_POST_WARNING/ERROR) waits for Confirm*;
--  a new post while one is waiting means the dialog was cancelled. Multisell
--  (AUCTION_MULTISELL_*) creates one auction per repetition. The next complete
--  owned-auctions list replaces these provisional entries.
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

-- Posting durations (luaIndex 1..3 = AUCTION_DURATION_ONE/TWO/THREE).
local DURATION_SECONDS = { 12 * 3600, 24 * 3600, 48 * 3600 }

local isOpen = false
local postHooksInstalled = false
local pendingPosts = {}   -- FIFO of { itemID, link, quantity, seconds, awaitingConfirm, multisell }
local warningBeforeHook = false
local knownByID = {}      -- auctionID -> entry, everything seen during this AH visit
local mailedIDs = {}      -- auctionID -> true once moved to mail (never twice)
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
    for _, entry in ipairs(items) do
        if entry.id then knownByID[entry.id] = entry end
    end
    ns.Index:Replace(key, "auctions", auctions.items, items)
    auctions.items = items
    auctions.scannedAt = now
    ns.Fire("CHAR_UPDATED", key, "auctions")
end

-- A cancelled/expired auction leaves the list and arrives by mail.
local function MoveToMail(auctionID)
    local key = ns.GetPlayerKey()
    local c = key and ns.GetChar(key, false)
    if not c or not auctionID or mailedIDs[auctionID] then return end
    local auctions = AuctionsOf(c)
    local kept, found = {}, nil
    for _, entry in ipairs(auctions.items) do
        if entry.id == auctionID then found = entry else kept[#kept + 1] = entry end
    end
    found = found or knownByID[auctionID]   -- a fresh list may already have dropped it
    if not found then return end
    mailedIDs[auctionID] = true
    if #kept ~= #auctions.items then
        ns.Index:Replace(key, "auctions", auctions.items, kept)
        auctions.items = kept
    end
    ns.AddIncomingMail(key, { found.e }, key)
    ns.Fire("CHAR_UPDATED", key, "auctions")
end

-------------------------------------------------------------------------------
--  Posting
-------------------------------------------------------------------------------
local function PostKey(p) return p.itemID .. ":" .. p.quantity .. ":" .. p.seconds end

local function ReadPost(item, duration, quantity)
    if type(item) ~= "table" or not C_Item.DoesItemExist(item) then return nil end
    local itemID = C_Item.GetItemID(item)
    local link = C_Item.GetItemLink(item)
    if not itemID or ns.IsSecret(itemID) or ns.IsSecret(quantity) or ns.IsSecret(duration) then return nil end
    if link and ns.IsSecret(link) then link = nil end
    return { itemID = itemID, link = link, quantity = quantity or 1,
             seconds = DURATION_SECONDS[duration] or DURATION_SECONDS[3] }
end

local function OnPost(item, duration, quantity)
    if not (feature.active and isOpen) then return end
    local post = ReadPost(item, duration, quantity)
    if not post then return end
    -- A new post while one waits for confirmation: that dialog was cancelled.
    for i = #pendingPosts, 1, -1 do
        if pendingPosts[i].awaitingConfirm then table.remove(pendingPosts, i) end
    end
    if warningBeforeHook then
        post.awaitingConfirm = true
        warningBeforeHook = false
    end
    pendingPosts[#pendingPosts + 1] = post
end

local function OnConfirmPost(item, duration, quantity)
    if not (feature.active and isOpen) then return end
    local post = ReadPost(item, duration, quantity)
    if not post then return end
    local key = PostKey(post)
    for _, p in ipairs(pendingPosts) do
        if p.awaitingConfirm and PostKey(p) == key then
            p.awaitingConfirm = false
            return
        end
    end
    pendingPosts[#pendingPosts + 1] = post
end

local function OnPostNeedsConfirm()
    local last = pendingPosts[#pendingPosts]
    if last and not last.awaitingConfirm and not last.multisell then
        last.awaitingConfirm = true
    else
        warningBeforeHook = true   -- event came before the hook ran
    end
end

local function FirstReadyPost()
    for i, p in ipairs(pendingPosts) do
        if not p.awaitingConfirm then return p, i end
    end
    return nil
end

local function OnAuctionCreated(auctionID)
    local post, index = FirstReadyPost()
    if not post then return end
    local quantity = post.quantity
    if post.multisell then
        quantity = post.multisell.per
        post.multisell.left = post.multisell.left - 1
        if post.multisell.left <= 0 then table.remove(pendingPosts, index) end
    else
        table.remove(pendingPosts, index)
    end
    local key = ns.GetPlayerKey()
    local c = key and ns.GetChar(key, true)
    if not c then return end
    local auctions = AuctionsOf(c)
    for _, entry in ipairs(auctions.items) do
        if auctionID and entry.id == auctionID then return end   -- already known
    end
    local entry = { e = ns.EncodeItem(post.itemID, quantity, post.link), x = time() + post.seconds, id = auctionID }
    if auctionID then knownByID[auctionID] = entry end
    local items = {}
    for i, e in ipairs(auctions.items) do items[i] = e end
    items[#items + 1] = entry
    ns.Index:Replace(key, "auctions", auctions.items, items)
    auctions.items = items
    ns.Fire("CHAR_UPDATED", key, "auctions")
end

local function OnMultisellStart(numRepetitions)
    local post = FirstReadyPost()
    if post and numRepetitions and numRepetitions > 1 then
        post.multisell = { left = numRepetitions, per = math.max(1, math.floor(post.quantity / numRepetitions)) }
    end
end

local function InstallPostHooks()
    if postHooksInstalled then return end
    postHooksInstalled = true
    local hooks = { PostItem = OnPost, PostCommodity = OnPost,
                    ConfirmPostItem = OnConfirmPost, ConfirmPostCommodity = OnConfirmPost }
    for name, fn in pairs(hooks) do
        -- hooksecurefunc errors on a missing function; skip rather than break the AH.
        if type(C_AuctionHouse[name]) == "function" then hooksecurefunc(C_AuctionHouse, name, fn) end
    end
end

local function OnOpened()
    if isOpen then return end
    isOpen = true
    ns.RegisterEvent(feature, "OWNED_AUCTIONS_UPDATED", ScanOwned)
    ns.RegisterEvent(feature, "AUCTION_CANCELED", function(_, _, auctionID) MoveToMail(auctionID) end)
    ns.RegisterEvent(feature, "AUCTION_HOUSE_AUCTIONS_EXPIRED", function(_, _, auctionID) MoveToMail(auctionID) end)
    ns.RegisterEvent(feature, "AUCTION_HOUSE_AUCTION_CREATED", function(_, _, auctionID)
        OnAuctionCreated(auctionID)
        if ns.db.settings.collect.auctionsQuery then C_AuctionHouse.QueryOwnedAuctions(OWNED_SORTS) end
    end)
    ns.RegisterEvent(feature, "AUCTION_HOUSE_POST_WARNING", OnPostNeedsConfirm)
    ns.RegisterEvent(feature, "AUCTION_HOUSE_POST_ERROR", OnPostNeedsConfirm)
    ns.RegisterEvent(feature, "AUCTION_MULTISELL_START", function(_, _, n) OnMultisellStart(n) end)
    ns.RegisterEvent(feature, "AUCTION_MULTISELL_FAILURE", function()
        local post, index = FirstReadyPost()
        if post and post.multisell then table.remove(pendingPosts, index) end
    end)
    InstallPostHooks()
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
    ns.UnregisterEvent(feature, "AUCTION_HOUSE_POST_WARNING")
    ns.UnregisterEvent(feature, "AUCTION_HOUSE_POST_ERROR")
    ns.UnregisterEvent(feature, "AUCTION_MULTISELL_START")
    ns.UnregisterEvent(feature, "AUCTION_MULTISELL_FAILURE")
    wipe(pendingPosts)
    wipe(knownByID)
    wipe(mailedIDs)
    warningBeforeHook = false
end

-- Auctions whose time ran out were mailed back by the game: move them into
-- the owner's in-transit mail (the owner's next inbox scan takes over).
function ns.PruneExpiredAuctions()
    if not ns.db then return end
    local now = time()
    for key, c in pairs(ns.db.chars) do
        if type(c.auctions) == "table" and type(c.auctions.items) == "table" then
            local kept, expired = {}, {}
            for _, entry in ipairs(c.auctions.items) do
                if entry.x and entry.x <= now then expired[#expired + 1] = entry.e else kept[#kept + 1] = entry end
            end
            if #expired > 0 then
                ns.Index:Replace(key, "auctions", c.auctions.items, kept)
                c.auctions.items = kept
                ns.AddIncomingMail(key, expired, key)
            end
        end
    end
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
        wipe(knownByID)
        wipe(mailedIDs)
        wipe(pendingPosts)
        warningBeforeHook = false
    end,
})
