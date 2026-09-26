-------------------------------------------------------------------------------
--  Index/ItemIndex.lua
--  Runtime index itemID -> owner -> location -> count. Not persisted.
--
--  Built lazily on the first query (tooltip or browser); afterwards collectors
--  feed it incrementally through ns.Index:Replace(), so a rescan of one bag
--  only touches the items that were or are in that bag.
--
--  Owners:    "<Name-Realm>" (characters), "#warband", "@<Guild-Realm>"
--  Locations: bags, bank, equipped, mail, warband, guild
-------------------------------------------------------------------------------
local _, ns = ...

local pairs, type, next = pairs, type, next
local DecodeItemIDCount = ns.DecodeItemIDCount

local Index = {
    built = false,
    data = {},
}
ns.Index = Index

ns.WARBAND_OWNER = "#warband"
function ns.GuildOwner(guildKey) return "@" .. guildKey end

-- Adds (sign = 1) or removes (sign = -1) every stack of an item collection.
-- items: { [slot] = enc } or { { e = enc }, ... } (mail lists).
local function Accumulate(data, owner, loc, items, sign, touched)
    if not items then return end
    for _, v in pairs(items) do
        local enc = type(v) == "table" and v.e or v
        if type(enc) == "string" then
            local id, count = DecodeItemIDCount(enc)
            if id then
                local byOwner = data[id]
                if not byOwner then
                    byOwner = {}
                    data[id] = byOwner
                end
                local byLoc = byOwner[owner]
                if not byLoc then
                    byLoc = {}
                    byOwner[owner] = byLoc
                end
                local n = (byLoc[loc] or 0) + sign * count
                if n <= 0 then n = nil end
                byLoc[loc] = n
                if next(byLoc) == nil then
                    byOwner[owner] = nil
                    if next(byOwner) == nil then data[id] = nil end
                end
                if touched then touched[id] = true end
            end
        end
    end
end

local function AccumulateMap(data, owner, loc, map, sign)
    if type(map) ~= "table" then return end
    for _, container in pairs(map) do
        if type(container) == "table" then
            Accumulate(data, owner, loc, container.items, sign)
        end
    end
end

function Index:Build()
    local data = {}
    local db = ns.db
    if db then
        for key, c in pairs(db.chars) do
            AccumulateMap(data, key, "bags", c.bags, 1)
            AccumulateMap(data, key, "bank", c.bank, 1)
            if c.equipped then Accumulate(data, key, "equipped", c.equipped.items, 1) end
            if c.mail then Accumulate(data, key, "mail", c.mail.items, 1) end
            Accumulate(data, key, "mail", c.mailIncoming, 1)
        end
        if db.warband then
            AccumulateMap(data, ns.WARBAND_OWNER, "warband", db.warband.bank, 1)
        end
        for key, g in pairs(db.guilds) do
            AccumulateMap(data, ns.GuildOwner(key), "guild", g.tabs, 1)
        end
    end
    self.data = data
    self.built = true
    ns.Fire("INDEX_REBUILT")
end

function Index:Invalidate()
    self.built = false
    self.data = {}
    ns.Fire("INDEX_REBUILT")
end

function Index:EnsureBuilt()
    if not self.built then self:Build() end
end

-- Swap an old item collection for a new one. Cheap no-op while unbuilt.
function Index:Replace(owner, loc, oldItems, newItems)
    if not self.built then return end
    local touched = {}
    Accumulate(self.data, owner, loc, oldItems, -1, touched)
    Accumulate(self.data, owner, loc, newItems, 1, touched)
    if next(touched) then ns.Fire("ITEM_COUNTS_CHANGED", touched) end
end

-- owner -> { loc = count } for one item (nil if nowhere). Do not mutate.
function Index:Get(itemID)
    self:EnsureBuilt()
    return self.data[itemID]
end

function Index:GetTotal(itemID)
    local byOwner = self:Get(itemID)
    local total = 0
    if byOwner then
        for _, byLoc in pairs(byOwner) do
            for _, n in pairs(byLoc) do total = total + n end
        end
    end
    return total
end

-- Iterator over every indexed itemID (search).
function Index:AllItemIDs()
    self:EnsureBuilt()
    return pairs(self.data)
end

ns.On("DATA_RESET", Index, function() Index:Invalidate() end)
