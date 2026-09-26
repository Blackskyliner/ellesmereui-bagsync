-------------------------------------------------------------------------------
--  Collect/Scanner.lua
--  Shared container scanning + a small dirty-set helper used by every
--  container based collector (bags, bank tabs).
--
--  Pattern (acceptance criterion 3, event driven, no timers):
--      BAG_UPDATE(bagID)   -> mark bagID dirty (O(1))
--      BAG_UPDATE_DELAYED  -> rescan only the dirty bags, once per burst
-------------------------------------------------------------------------------
local _, ns = ...

local pairs, next = pairs, next

-- -> Container or nil; second return true when the data was secret (retry later).
function ns.ScanContainer(bagID)
    local size = C_Container.GetContainerNumSlots(bagID)
    if ns.IsSecret(size) then return nil, true end
    size = size or 0
    local items = {}
    for slot = 1, size do
        local info = C_Container.GetContainerItemInfo(bagID, slot)
        if info then
            local id = info.itemID
            if ns.IsSecret(id) or ns.IsSecret(info.stackCount) or ns.IsSecret(info.hyperlink) then
                return nil, true
            end
            if id then
                items[slot] = ns.EncodeItem(id, info.stackCount, info.hyperlink)
            end
        end
    end
    return { size = size, items = items }
end

local function ItemsEqual(a, b)
    if a == b then return true end
    if not a or not b then return false end
    for k, v in pairs(a) do
        if b[k] ~= v then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end
ns.ItemsEqual = ItemsEqual

-- Stores a freshly scanned container into map[id], keeping the index in sync.
-- Returns true when the contents changed.
function ns.StoreContainer(map, id, container, owner, loc)
    local old = map[id]
    if old and container and old.size == container.size and ItemsEqual(old.items, container.items) then
        return false
    end
    ns.Index:Replace(owner, loc, old and old.items, container and container.items)
    if container and old then
        container.name = container.name or old.name
        container.icon = container.icon or old.icon
    end
    map[id] = container
    return true
end

-- Replaces a whole container map (full rescan) and drops containers that no
-- longer exist. Returns true when anything changed.
function ns.StoreContainerMap(map, scanned, owner, loc)
    local changed = false
    for id in pairs(map) do
        if scanned[id] == nil then
            ns.Index:Replace(owner, loc, map[id].items, nil)
            map[id] = nil
            changed = true
        end
    end
    for id, container in pairs(scanned) do
        if ns.StoreContainer(map, id, container, owner, loc) then changed = true end
    end
    return changed
end

-------------------------------------------------------------------------------
--  Dirty set
-------------------------------------------------------------------------------
local DirtySet = {}
DirtySet.__index = DirtySet

function ns.NewDirtySet()
    return setmetatable({ set = {} }, DirtySet)
end

function DirtySet:Mark(id) self.set[id] = true end
function DirtySet:IsEmpty() return next(self.set) == nil end
function DirtySet:Clear() wipe(self.set) end

-- Calls fn(id) for each dirty id; ids for which fn returns false stay dirty.
function DirtySet:Flush(fn)
    local pending = self.set
    self.set = {}
    for id in pairs(pending) do
        if fn(id) == false then self.set[id] = true end
    end
end
