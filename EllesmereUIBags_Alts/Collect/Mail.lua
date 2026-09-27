-------------------------------------------------------------------------------
--  Collect/Mail.lua
--  Inbox contents (only readable at a mailbox) plus mail you send to your own
--  characters, so those items are not "missing" until the alt opens its inbox.
--
--  Sending is observed with a post-hook on the global SendMail (hooksecurefunc:
--  runs after Blizzard's function, never replaces it, taint free). The hook is
--  installed on first enable and is a single boolean test while disabled.
-------------------------------------------------------------------------------
local _, ns = ...

local time = time
local DAY = 86400
local MAIL_LIFETIME_DAYS = 30

local isOpen = false
local hookInstalled = false
local pendingSend   -- { recipient = key, items = { enc, ... } } between SendMail and the result

local feature

local function ScanInbox()
    local key = ns.GetPlayerKey()
    local c = key and ns.GetChar(key, true)
    if not c then return end
    local now = time()
    local items = {}
    local numItems = GetInboxNumItems() or 0
    for index = 1, numItems do
        local _, _, sender, _, _, _, daysLeft, itemCount = GetInboxHeaderInfo(index)
        if itemCount and itemCount > 0 then
            local expires = now + math.floor((daysLeft or 0) * DAY)
            for attachment = 1, ATTACHMENTS_MAX_RECEIVE do
                local _, itemID, _, count, _, _, isCurrency = GetInboxItem(index, attachment)
                if itemID and not isCurrency and not ns.IsSecret(itemID) then
                    local link = GetInboxItemLink(index, attachment)
                    items[#items + 1] = { e = ns.EncodeItem(itemID, count, link), x = expires, from = sender }
                end
            end
        end
    end
    local old = c.mail.items
    local oldIncoming = c.mailIncoming
    -- The inbox now shows everything that was in transit to this character.
    ns.Index:Replace(key, "mail", old, items)
    ns.Index:Replace(key, "mail", oldIncoming, nil)
    c.mail.items = items
    c.mail.scannedAt = now
    c.mailIncoming = {}
    c.mailSold = {}   -- the sale gold is real mail in the inbox now
    ns.Fire("CHAR_UPDATED", key, "mail")
end

local function CaptureOutgoing(recipient)
    if not feature.active or not recipient then return end
    local key = ns.NormalizeCharacterName(recipient)
    local known = key and ns.FindKnownCharacter(ns.db.chars, key)
    if not known or known == ns.GetPlayerKey() then
        pendingSend = nil
        return
    end
    local items = {}
    for i = 1, ATTACHMENTS_MAX_SEND do
        local _, itemID, _, count = GetSendMailItem(i)
        if itemID and not ns.IsSecret(itemID) then
            items[#items + 1] = ns.EncodeItem(itemID, count, GetSendMailItemLink(i))
        end
    end
    pendingSend = #items > 0 and { recipient = known, items = items } or nil
end

-- Puts items "in transit" into a character's mailbox (sent mail, cancelled or
-- expired auctions). The character's next inbox scan replaces them.
function ns.AddIncomingMail(charKey, encodedItems, from)
    local c = ns.GetChar(charKey, false)
    if not c or #encodedItems == 0 then return end
    local expires = time() + MAIL_LIFETIME_DAYS * DAY
    local added = {}
    for i = 1, #encodedItems do
        local entry = { e = encodedItems[i], x = expires, from = from }
        c.mailIncoming[#c.mailIncoming + 1] = entry
        added[#added + 1] = entry
    end
    ns.Index:Replace(charKey, "mail", nil, added)
    ns.Fire("CHAR_UPDATED", charKey, "mail")
end

-- Records a sold auction: its gold waits in the owner's mailbox. Not an item
-- stack, so it never enters the item index. money = sale price in copper.
function ns.AddSoldMail(charKey, enc, money, auctionID)
    local c = ns.GetChar(charKey, false)
    if not c or not enc then return end
    local now = time()
    c.mailSold[#c.mailSold + 1] = { e = enc, money = money or 0, at = now,
        x = now + MAIL_LIFETIME_DAYS * DAY, id = auctionID }
    ns.Fire("CHAR_UPDATED", charKey, "mail")
end

local function CommitOutgoing()
    local send = pendingSend
    pendingSend = nil
    if not send then return end
    ns.AddIncomingMail(send.recipient, send.items, ns.GetPlayerKey())
end

local function OnMailShow()
    if isOpen then return end
    isOpen = true
    ns.RegisterEvent(feature, "MAIL_INBOX_UPDATE", ScanInbox)
    ns.RegisterEvent(feature, "MAIL_SEND_SUCCESS", CommitOutgoing)
    ns.RegisterEvent(feature, "MAIL_FAILED", function() pendingSend = nil end)
    ScanInbox()
end

local function OnMailClosed()
    if not isOpen then return end
    isOpen = false
    ns.UnregisterEvent(feature, "MAIL_INBOX_UPDATE")
    ns.UnregisterEvent(feature, "MAIL_SEND_SUCCESS")
    ns.UnregisterEvent(feature, "MAIL_FAILED")
    pendingSend = nil
end

-- Drops expired mail entries everywhere (they are gone or returned by now).
function ns.PruneExpiredMail()
    if not ns.db then return end
    local now = time()
    local changed = false
    local function prune(list)
        local out = {}
        for i = 1, #list do
            local m = list[i]
            if not m.x or m.x > now then out[#out + 1] = m else changed = true end
        end
        return out
    end
    for _, c in pairs(ns.db.chars) do
        c.mail.items = prune(c.mail.items)
        c.mailIncoming = prune(c.mailIncoming)
        c.mailSold = prune(c.mailSold)
    end
    if changed then ns.Index:Invalidate() end
end

feature = ns.RegisterFeature({
    key = "mail",
    IsEnabled = function(s) return s.collect.mail end,
    OnEnable = function(self)
        if not hookInstalled then
            hookInstalled = true
            hooksecurefunc("SendMail", CaptureOutgoing)
        end
        ns.PruneExpiredMail()
        ns.RegisterEvent(self, "MAIL_SHOW", OnMailShow)
        ns.RegisterEvent(self, "MAIL_CLOSED", OnMailClosed)
        ns.RegisterEvent(self, "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(_, _, interaction)
            if interaction == Enum.PlayerInteractionType.MailInfo then OnMailClosed() end
        end)
        -- Started while the mailbox is open (the visit that activated the addon).
        if ns.IsInteracting(Enum.PlayerInteractionType.MailInfo) then OnMailShow() end
    end,
    OnDisable = function()
        isOpen = false
        pendingSend = nil
    end,
})
