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
--  out meanwhile. A cancel is captured when C_AuctionHouse.CancelAuction runs
--  (post-hook; the auction is still in the owned list then, with the ID the
--  cancel uses) and queued. AUCTION_CANCELED does not carry that ID (the live
--  client sends e.g. "1"), so each event confirms the oldest queued cancel; a
--  missing event is covered by the auction's absence from the next complete
--  owned list. A provisional entry recorded under a different ID (posting) is
--  removed by content, so nothing is counted twice; each auction is mailed at
--  most once.
--
--  Sold auctions become "sold" mail entries with the price achieved (gross,
--  the mail deducts the AH cut), shown until the owner opens the mailbox:
--    * AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION(AuctionSold, itemName, auctionID)
--      fires anywhere; matched by ID, else by item name. Commodities are left
--      to the list diff (a notification does not say how many units sold).
--    * Diff on every owned list (Auctions tab): an auction listed as Sold is
--      handled even from a partial list; with a complete list, a stored
--      auction that is gone was cancelled (queued -> mail), expired (time over
--      -> mail) or sold (time left); a commodity with fewer units sold the rest.
--  Each entry keeps its unit price (u, copper): exact from PostItem/PostCommodity,
--  from the owned list otherwise (buyout, else bid; per unit for commodities,
--  which carry no item link).
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
local cancelCaptured = {} -- auctionID -> entry (or false) captured at CancelAuction
local cancelQueue = {}    -- auctionIDs in CancelAuction order, confirmed by AUCTION_CANCELED
local feature

local function AuctionsOf(c)
    if type(c.auctions) ~= "table" then c.auctions = { items = {} } end
    return c.auctions
end

-- OwnedAuctionInfo -> stored entry { e = enc, x = expires, id = auctionID } or nil
-- Unit price of an owned auction (copper) or nil.
local function UnitPriceFromInfo(info, quantity)
    local price = info.buyoutAmount or info.bidAmount
    if type(price) ~= "number" or ns.IsSecret(price) then return nil end
    if info.itemLink == nil then return price end               -- commodity: per unit
    return math.floor(price / math.max(1, quantity or 1))
end

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
    return { e = ns.EncodeItem(itemID, info.quantity or 1, link), x = now + seconds, id = info.auctionID,
             u = UnitPriceFromInfo(info, info.quantity) }
end

-- Value of the active auctions of one character: total copper, count.
function ns.AuctionValue(c)
    local total, count = 0, 0
    local items = type(c) == "table" and type(c.auctions) == "table" and c.auctions.items or {}
    for _, entry in ipairs(items) do
        local _, qty = ns.DecodeItemIDCount(entry.e)
        count = count + 1
        if entry.u and qty then total = total + entry.u * qty end
    end
    return total, count
end

-- The owned list as the client holds it: the table API, or (like Blizzard's
-- Auctions tab) the indexed API when the table comes back empty.
-- -> list of OwnedAuctionInfo, source label
local function ReadOwnedList()
    local list = C_AuctionHouse.GetOwnedAuctions()
    if type(list) == "table" and #list > 0 then return list, "table" end
    local n = C_AuctionHouse.GetNumOwnedAuctions()
    if type(n) == "number" and not ns.IsSecret(n) and n > 0 then
        local out = {}
        for i = 1, n do
            local info = C_AuctionHouse.GetOwnedAuctionInfo(i)
            if info then out[#out + 1] = info end
        end
        return out, "index"
    end
    return type(list) == "table" and list or {}, "table"
end

local function StoredByID(auctions, auctionID)
    for i, entry in ipairs(auctions.items) do
        if entry.id == auctionID then return entry, i end
    end
    return nil
end

-- A cancelled/expired auction leaves the list and arrives by mail.
local function MoveToMail(auctionID, reason)
    local key = ns.GetPlayerKey()
    local c = key and ns.GetChar(key, false)
    if not c or not auctionID or mailedIDs[auctionID] then return false end
    local auctions = AuctionsOf(c)
    local stored, index = StoredByID(auctions, auctionID)
    local found = stored or cancelCaptured[auctionID] or knownByID[auctionID]
    if not found then
        ns.Debug("auctions", "%s %s: auction unknown, not mailed", reason, auctionID)
        return false
    end
    if not index then
        -- Recorded under another ID (provisional entry from posting): match by content.
        local wantID, wantCount = ns.DecodeItemIDCount(found.e)
        for i, entry in ipairs(auctions.items) do
            if entry.p then
                local id, count = ns.DecodeItemIDCount(entry.e)
                if id == wantID and (count == wantCount or not index) then
                    index = i
                    if count == wantCount then break end
                end
            end
        end
    end
    mailedIDs[auctionID] = true
    cancelCaptured[auctionID] = nil
    if index then
        local kept = {}
        for i, entry in ipairs(auctions.items) do
            if i ~= index then kept[#kept + 1] = entry end
        end
        ns.Index:Replace(key, "auctions", auctions.items, kept)
        auctions.items = kept
    end
    ns.AddIncomingMail(key, { found.e }, key)
    ns.Debug("auctions", "%s %s: %s -> mail", reason, auctionID, found.e)
    ns.Fire("CHAR_UPDATED", key, "auctions")
    return true
end

-- Records units of a stored auction as sold (gold to the mailbox) and removes
-- them from the auctions. soldQty nil = all units. unitPrice overrides entry.u.
local function MarkSold(auctions, index, soldQty, unitPrice, reason)
    local key = ns.GetPlayerKey()
    local entry = auctions.items[index]
    local id, qty, link = ns.DecodeItem(entry.e)
    soldQty = math.min(soldQty or qty, qty)
    local price = unitPrice or entry.u
    local kept = {}
    for i, e in ipairs(auctions.items) do
        if i ~= index then
            kept[#kept + 1] = e
        elseif soldQty < qty then
            local rest = {}
            for k, v in pairs(e) do rest[k] = v end
            rest.e = ns.EncodeItem(id, qty - soldQty, link)
            kept[#kept + 1] = rest
        end
    end
    ns.Index:Replace(key, "auctions", auctions.items, kept)
    auctions.items = kept
    local money = price and price * soldQty or 0
    ns.AddSoldMail(key, ns.EncodeItem(id, soldQty, link), money, entry.id)
    ns.Debug("auctions", "%s %s: %dx%s for %d", reason, entry.id, soldQty, id, money)
    ns.Fire("CHAR_UPDATED", key, "auctions")
end

local function ScanOwned()
    local key = ns.GetPlayerKey()
    local c = key and ns.GetChar(key, true)
    if not c then return end
    local owned, source = ReadOwnedList()
    local now = time()
    local items, present = {}, {}
    for i = 1, #owned do
        local info = owned[i]
        if type(info) == "table" and info.auctionID then
            present[info.auctionID] = info.status == STATUS_ACTIVE and (info.quantity or 1) or info
        end
        local entry = EntryFromInfo(info, now)
        if entry then
            items[#items + 1] = entry
            if entry.id then knownByID[entry.id] = entry end   -- partial results still identify auctions
        end
    end
    local full = C_AuctionHouse.HasFullOwnedAuctionResults()
    ns.Debug("auctions", "owned list: %d entries via %s, complete=%s", #owned, source, full)
    local auctions = AuctionsOf(c)
    -- Auctions the list reports as Sold (also from a partial list).
    for i = #auctions.items, 1, -1 do
        local entry = auctions.items[i]
        local info = entry.id and present[entry.id]
        if type(info) == "table" then
            local _, qty = ns.DecodeItemIDCount(entry.e)
            MarkSold(auctions, i, qty, entry.u or UnitPriceFromInfo(info, qty), "sold (listed)")
        end
    end
    -- Partial results would under-count: keep the last full list until the
    -- client has everything (another OWNED_AUCTIONS_UPDATED follows).
    if not full then return end
    -- Complete list. Queued cancels that are gone: cancelled (event missed).
    for i = #cancelQueue, 1, -1 do
        local auctionID = cancelQueue[i]
        if not present[auctionID] then
            table.remove(cancelQueue, i)
            MoveToMail(auctionID, "cancel (absent from list)")
        end
    end
    -- Other stored auctions: gone -> expired (mail) or sold; fewer units -> partly sold.
    for i = #auctions.items, 1, -1 do
        local entry = auctions.items[i]
        if entry.id and not entry.p and not mailedIDs[entry.id] then
            local listed = present[entry.id]
            local _, qty = ns.DecodeItemIDCount(entry.e)
            if listed == nil then
                if entry.x and entry.x <= now then
                    MoveToMail(entry.id, "expired (absent from list)")
                else
                    MarkSold(auctions, i, qty, nil, "sold (absent from list)")
                end
            elseif type(listed) == "number" and qty and listed < qty then
                MarkSold(auctions, i, qty - listed, nil, "partly sold")
            end
        end
    end
    -- The exact posting price wins over the list's price (whose per-unit
    -- meaning for commodities is inferred); list prices fill the rest.
    local priceByID = {}
    for _, entry in ipairs(auctions.items) do
        if entry.id and entry.u and (entry.p or entry.exact) then priceByID[entry.id] = entry.u end
    end
    for _, entry in ipairs(items) do
        local exact = entry.id and priceByID[entry.id]
        if exact then
            entry.u = exact
            entry.exact = true
        end
    end
    ns.Index:Replace(key, "auctions", auctions.items, items)
    auctions.items = items
    auctions.scannedAt = now
    ns.Fire("CHAR_UPDATED", key, "auctions")
end

-- Post-hook on C_AuctionHouse.CancelAuction: the auction is still listed now.
local function OnCancelAuction(auctionID)
    if not (feature.active and isOpen) or not auctionID or ns.IsSecret(auctionID) then return end
    cancelQueue[#cancelQueue + 1] = auctionID
    local key = ns.GetPlayerKey()
    local c = key and ns.GetChar(key, false)
    local entry = c and StoredByID(AuctionsOf(c), auctionID) or knownByID[auctionID]
    if not entry then
        local owned = ReadOwnedList()
        for i = 1, #owned do
            if owned[i].auctionID == auctionID then
                entry = EntryFromInfo(owned[i], time())
                break
            end
        end
    end
    cancelCaptured[auctionID] = entry or false
    ns.Debug("auctions", "cancel requested %s: %s", auctionID, entry and entry.e or "not in owned data")
end

-- AUCTION_CANCELED's argument is not the auction ID (live client: "1"), so
-- each event confirms the oldest queued CancelAuction call.
local function OnAuctionCanceled(arg)
    local id = table.remove(cancelQueue, 1)
    if not id then
        ns.Debug("auctions", "AUCTION_CANCELED %s without a cancel request, ignored", arg)
        return
    end
    ns.Debug("auctions", "AUCTION_CANCELED %s confirms requested %s", arg, id)
    MoveToMail(id, "cancel")
end

-------------------------------------------------------------------------------
--  Posting
-------------------------------------------------------------------------------
local function PostKey(p) return p.itemID .. ":" .. p.quantity .. ":" .. p.seconds end

local function ReadPost(item, duration, quantity, price, isCommodity)
    if type(item) ~= "table" or not C_Item.DoesItemExist(item) then return nil end
    local itemID = C_Item.GetItemID(item)
    local link = C_Item.GetItemLink(item)
    if not itemID or ns.IsSecret(itemID) or ns.IsSecret(quantity) or ns.IsSecret(duration) then return nil end
    if link and ns.IsSecret(link) then link = nil end
    if type(price) ~= "number" or ns.IsSecret(price) then price = nil end
    return { itemID = itemID, link = link, quantity = quantity or 1,
             seconds = DURATION_SECONDS[duration] or DURATION_SECONDS[3],
             price = price, commodity = isCommodity }
end

-- Unit price of a post: commodities pass a unit price, items a price per auction.
local function PostUnitPrice(post, perAuctionQty)
    if not post.price then return nil end
    if post.commodity then return post.price end
    return math.floor(post.price / math.max(1, perAuctionQty or 1))
end

local function OnPost(isCommodity, item, duration, quantity, a, b)
    if not (feature.active and isOpen) then return end
    -- PostItem(item, duration, quantity, bid, buyout) / PostCommodity(item, duration, quantity, unitPrice)
    local post = ReadPost(item, duration, quantity, isCommodity and a or (b or a), isCommodity)
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

local function OnConfirmPost(isCommodity, item, duration, quantity, a, b)
    if not (feature.active and isOpen) then return end
    local post = ReadPost(item, duration, quantity, isCommodity and a or (b or a), isCommodity)
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
    -- p = provisional: recorded from posting, replaced by the next complete list
    local entry = { e = ns.EncodeItem(post.itemID, quantity, post.link), x = time() + post.seconds, id = auctionID, p = true,
                    u = PostUnitPrice(post, quantity) }
    if auctionID then knownByID[auctionID] = entry end
    ns.Debug("auctions", "posted %s: %s", auctionID, entry.e)
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
    local function item(fn) return function(...) fn(false, ...) end end
    local function commodity(fn) return function(...) fn(true, ...) end end
    local hooks = { PostItem = item(OnPost), PostCommodity = commodity(OnPost),
                    ConfirmPostItem = item(OnConfirmPost), ConfirmPostCommodity = commodity(OnConfirmPost),
                    CancelAuction = OnCancelAuction }
    for name, fn in pairs(hooks) do
        -- hooksecurefunc errors on a missing function; skip rather than break the AH.
        if type(C_AuctionHouse[name]) == "function" then hooksecurefunc(C_AuctionHouse, name, fn) end
    end
end

-------------------------------------------------------------------------------
--  Sold/expired notifications (fire anywhere, AH open or not)
-------------------------------------------------------------------------------
local NOTIFY_SOLD = Enum.AuctionHouseNotification.AuctionSold
local NOTIFY_EXPIRED = Enum.AuctionHouseNotification.AuctionExpired

-- Stored auction for a notification: by ID, else a single-unit item by name.
local function FindNotified(auctions, auctionID, itemName)
    for i, entry in ipairs(auctions.items) do
        if auctionID and entry.id == auctionID then return i, entry end
    end
    if type(itemName) ~= "string" or itemName == "" or ns.IsSecret(itemName) then return nil end
    for i, entry in ipairs(auctions.items) do
        local id, _, link = ns.DecodeItem(entry.e)
        local name = link and link:match("|h%[(.-)%]|h") or C_Item.GetItemInfo(id)
        if name and itemName:find(name, 1, true) then return i, entry end
    end
    return nil
end

local function OnNotification(_, _, notification, text, auctionID)
    if notification ~= NOTIFY_SOLD and notification ~= NOTIFY_EXPIRED then return end
    local c = ns.GetPlayerChar(false)
    if not c then return end
    local auctions = AuctionsOf(c)
    local index, entry = FindNotified(auctions, auctionID, text)
    if not index then
        ns.Debug("auctions", "notification %s (%s, %s): no stored auction", notification, text, auctionID)
        return
    end
    if notification == NOTIFY_EXPIRED then
        if entry.id then MoveToMail(entry.id, "expired (notification)") end
        return
    end
    local _, qty, link = ns.DecodeItem(entry.e)
    if not link and qty > 1 then
        -- Commodity: the notification does not say how many units sold.
        ns.Debug("auctions", "commodity sale %s: waiting for the owned list", entry.id)
        return
    end
    MarkSold(auctions, index, qty, nil, "sold (notification)")
end

local function OnOpened()
    if isOpen then return end
    isOpen = true
    ns.Debug("auctions", "auction house opened (query on open: %s)", ns.db.settings.collect.auctionsQuery)
    ns.RegisterEvent(feature, "OWNED_AUCTIONS_UPDATED", ScanOwned)
    ns.RegisterEvent(feature, "AUCTION_CANCELED", function(_, _, auctionID) OnAuctionCanceled(auctionID) end)
    ns.RegisterEvent(feature, "AUCTION_HOUSE_AUCTIONS_EXPIRED", function(_, _, auctionID) MoveToMail(auctionID, "expired") end)
    -- No query here: the post-hooks already record each new auction with its
    -- ID, and a multisell would otherwise send one request per repetition.
    ns.RegisterEvent(feature, "AUCTION_HOUSE_AUCTION_CREATED", function(_, _, auctionID) OnAuctionCreated(auctionID) end)
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
    wipe(cancelCaptured)
    wipe(cancelQueue)
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
        ns.RegisterEvent(self, "AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION", OnNotification)
        ns.RegisterEvent(self, "AUCTION_HOUSE_CLOSED", OnClosed)
        -- Started at the auction house (the visit that activated the addon).
        if ns.IsInteracting(AUCTIONEER) then OnOpened() end
    end,
    OnDisable = function()
        isOpen = false
        wipe(knownByID)
        wipe(mailedIDs)
        wipe(cancelCaptured)
        wipe(cancelQueue)
        wipe(pendingPosts)
        warningBeforeHook = false
    end,
})
