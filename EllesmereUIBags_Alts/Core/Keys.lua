-------------------------------------------------------------------------------
--  Core/Keys.lua
--  Identity helpers (character / guild keys, realm scope) and the compact item
--  encoding used in the saved variables.
--
--  Character key: "Name-NormalizedRealm" (the same shape the client uses for
--  cross-realm names, e.g. mail recipients), never cached before the client
--  can answer (UnitName/GetNormalizedRealmName may be nil very early).
--
--  Item encoding: one string per stack.
--      "<itemID>,<count>"            plain items (the vast majority)
--      "<itemID>,<count>,<link>"     items whose link carries identity beyond
--                                    the ID (gear with bonus IDs/enchants/gems,
--                                    caged battle pets, keystones)
--  Item links are stored as their "item:..." core only (no colour, no name:
--  both come back from the item cache); battle pet and keystone links stay
--  whole. An optional bound marker follows the count: "!" soulbound, "~"
--  warbound, e.g. "230000,1,!item:230000:..." or "6948,1,!". No marker = not
--  bound (free to move). Commas never occur in item links, so decoding is a
--  single match.
--
--  Containers store all their stacks in ONE string, in slot order:
--      "<slot>:<enc>;<slot>:<enc>;..."        ("" = empty container)
--  One string per container instead of a table with a string per slot makes
--  the saved variables smaller and loading them cheaper; the index and the
--  change detection walk the string directly.
-------------------------------------------------------------------------------
local _, ns = ...

local strmatch, strfind, strlower, strgsub, tonumber, tostring =
    string.match, string.find, string.lower, string.gsub, tonumber, tostring

-------------------------------------------------------------------------------
--  Character / realm
-------------------------------------------------------------------------------
local playerKey, playerRealm

function ns.GetPlayerRealm()
    if playerRealm then return playerRealm end
    local realm = GetNormalizedRealmName()
    if realm and realm ~= "" then playerRealm = realm end
    return playerRealm
end

function ns.GetPlayerKey()
    if playerKey then return playerKey end
    local name = UnitName("player")
    local realm = ns.GetPlayerRealm()
    if not name or name == "" or not realm then return nil end
    playerKey = name .. "-" .. realm
    return playerKey
end

-- Test hook: forget the cached identity (tests switch characters).
function ns.ResetIdentityCache()
    playerKey, playerRealm = nil, nil
end

function ns.SplitKey(key)
    local name, realm = strmatch(key or "", "^(.-)%-(.+)$")
    return name or key, realm
end

-- "bob", "Bob-Other Realm" -> "Bob-OtherRealm" (normalized, current realm default)
function ns.NormalizeCharacterName(input)
    if type(input) ~= "string" then return nil end
    input = strgsub(input, "^%s+", "")
    input = strgsub(input, "%s+$", "")
    if input == "" then return nil end
    local name, realm = strmatch(input, "^(.-)%-(.+)$")
    if not name then name, realm = input, ns.GetPlayerRealm() end
    if not realm or name == "" then return nil end
    realm = strgsub(realm, "[%s%-']", "")
    -- WoW names are stored capitalized; keep the rest as typed (UTF-8 safe for
    -- ASCII initials, non-ASCII initials are matched case-sensitively).
    name = name:sub(1, 1):upper() .. name:sub(2):lower()
    return name .. "-" .. realm
end

-- Case-insensitive lookup of a known character key.
function ns.FindKnownCharacter(chars, key)
    if not key or not chars then return nil end
    if chars[key] then return key end
    local lk = strlower(key)
    for k in pairs(chars) do
        if strlower(k) == lk then return k end
    end
    return nil
end

-------------------------------------------------------------------------------
--  Realm scope for tooltips: "all" | "connected" | "realm"
-------------------------------------------------------------------------------
local connectedSet

function ns.GetConnectedRealms()
    if connectedSet then return connectedSet end
    local set = {}
    local own = ns.GetPlayerRealm()
    if own then set[own] = true end
    local list = C_AutoComplete.GetAutoCompleteRealms()
    if type(list) == "table" then
        for i = 1, #list do set[strgsub(list[i], "[%s%-']", "")] = true end
    end
    if own then connectedSet = set end  -- do not cache before the realm is known
    return set
end

function ns.ResetRealmCache()
    connectedSet = nil
end

function ns.IsRealmInScope(realm, scope)
    if scope == "all" or not realm then return true end
    local own = ns.GetPlayerRealm()
    if scope == "realm" then return realm == own end
    return ns.GetConnectedRealms()[realm] == true
end

-------------------------------------------------------------------------------
--  Guild key
-------------------------------------------------------------------------------
function ns.GetPlayerGuildKey()
    if not IsInGuild() then return nil end
    local guildName, _, _, guildRealm = GetGuildInfo("player")
    if not guildName or guildName == "" then return nil end
    local realm = guildRealm and guildRealm ~= "" and strgsub(guildRealm, "[%s%-']", "") or ns.GetPlayerRealm()
    if not realm then return nil end
    return guildName .. "-" .. realm, guildName
end

-------------------------------------------------------------------------------
--  Item encoding
-------------------------------------------------------------------------------
-- Does this link identify more than its itemID?
--   item:ID:enchant:gem1:gem2:gem3:gem4:suffix:unique:linkLevel:spec:modMask:context:numBonus:...
local function LinkIsRich(link)
    if not link then return false end
    if strfind(link, "|Hbattlepet:", 1, true) or strfind(link, "|Hkeystone:", 1, true) then
        return true
    end
    local itemString = strmatch(link, "item:([%-%d:]+)")
    if not itemString then return false end
    -- field 1=itemID, 2=enchant, 3..6=gems, 7=suffix, 13=numBonusIDs
    local i = 0
    for field in (itemString .. ":"):gmatch("([^:]*):") do
        i = i + 1
        if i >= 2 and i <= 7 then
            if field ~= "" and field ~= "0" then return true end
        elseif i == 13 then
            local numBonus = tonumber(field)
            return numBonus ~= nil and numBonus > 0
        end
    end
    return false
end
ns.LinkIsRich = LinkIsRich

-- "|cff...|Hitem:...|h[Name]|h|r" -> "item:..."; other links unchanged.
local function CompactLink(link)
    if type(link) ~= "string" then return link end
    return strmatch(link, "|H(item:[^|]+)|h") or link
end
ns.CompactLink = CompactLink

local BOUND_MARKER = { soul = "!", account = "~" }
local MARKER_BOUND = { ["!"] = "soul", ["~"] = "account" }

-- bound: nil (free) | "soul" | "account"
function ns.EncodeItem(itemID, count, link, bound)
    if not itemID then return nil end
    count = count or 1
    local marker = BOUND_MARKER[bound] or ""
    link = CompactLink(link)
    if LinkIsRich(link) and not strfind(link, ";", 1, true) then   -- ";" separates packed stacks
        return itemID .. "," .. count .. "," .. marker .. link
    end
    if marker ~= "" then return itemID .. "," .. count .. "," .. marker end
    return itemID .. "," .. count
end

-- -> itemID (number), count (number), link (string or nil), bound (nil | "soul" | "account")
function ns.DecodeItem(enc)
    if type(enc) ~= "string" then return nil end
    local id, count, rest = strmatch(enc, "^(%d+),(%d+),?(.*)$")
    if not id then return nil end
    local bound = MARKER_BOUND[rest:sub(1, 1)]
    if bound then rest = rest:sub(2) end
    if rest == "" then rest = nil end
    return tonumber(id), tonumber(count), rest, bound
end

-- Bound state of a live item: nil while it may still move (unbound or
-- "warbound until equipped"), else "soul" or "account" (warbound).
function ns.BoundState(isBound, itemLocation, itemID)
    if ns.IsSecret(isBound) or not isBound then return nil end
    if itemLocation and C_Item.IsBoundToAccountUntilEquip(itemLocation) then return nil end
    local bindType = select(14, C_Item.GetItemInfo(itemID))
    if bindType == Enum.ItemBind.ToWoWAccount or bindType == Enum.ItemBind.ToBnetAccount then
        return "account"
    end
    return "soul"
end

-- Cheap variant for hot paths that only need the numbers.
function ns.DecodeItemIDCount(enc)
    local id, count = strmatch(enc, "^(%d+),(%d+)")
    return tonumber(id), tonumber(count)
end

-------------------------------------------------------------------------------
--  Packed containers
-------------------------------------------------------------------------------
-- { [slot] = enc } -> "slot:enc;slot:enc;..." in slot order
function ns.PackItems(map)
    if type(map) ~= "table" then return "" end
    local slots = {}
    for slot, enc in pairs(map) do
        if type(slot) == "number" and type(enc) == "string" then slots[#slots + 1] = slot end
    end
    table.sort(slots)
    local parts = {}
    for i, slot in ipairs(slots) do parts[i] = slot .. ":" .. map[slot] end
    return table.concat(parts, ";")
end

-- Iterator over a packed container: for slot, enc in ns.EachItem(packed)
function ns.EachItem(packed)
    local nextMatch = string.gmatch(type(packed) == "string" and packed or "", "(%d+):([^;]+)")
    return function()
        local slot, enc = nextMatch()
        if slot then return tonumber(slot), enc end
    end
end

-- packed -> { [slot] = enc }
function ns.UnpackItems(packed)
    local map = {}
    for slot, enc in ns.EachItem(packed) do map[slot] = enc end
    return map
end

-- Link to use for tooltips/chat for an encoded stack (rich link or plain ID).
function ns.ItemRef(enc)
    local id, _, link = ns.DecodeItem(enc)
    if link then return link end
    if id then return "item:" .. tostring(id) end
    return nil
end
