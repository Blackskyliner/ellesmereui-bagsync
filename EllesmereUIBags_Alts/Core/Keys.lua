-------------------------------------------------------------------------------
--  Core/Keys.lua
--  Identity helpers (character / guild keys, realm scope) and the compact item
--  encoding used in the saved variables.
--
--  Character key: the character's GUID ("Player-<server>-<id>"), like
--  EllesmereUI's gold ledger. A name is no key: on WoW Forever characters
--  with the same first name differ only by surname, and a GUID survives a
--  rename. The record carries name and realm (Collect/Character.lua); the
--  realm part is GetNormalizedRealmName(), on WoW Forever the realm group
--  (ns.Compat.RealmKey). Records of versions before 0.10.0 are keyed
--  "FirstName-Realm" until that character logs in (ns.AdoptLegacyChar).
--  Nothing is cached before the client can answer (UnitGUID/UnitName may be
--  nil very early).
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
local playerKey, playerRealm, playerName

function ns.GetPlayerRealm()
    if playerRealm then return playerRealm end
    local realm = ns.Compat.RealmKey()
    if realm and realm ~= "" then playerRealm = realm end
    return playerRealm
end

-- Full name: "First Last" on WoW Forever, the name elsewhere.
function ns.GetPlayerName()
    if playerName then return playerName end
    local name = ns.Compat.PlayerFullName()
    if type(name) == "string" and not ns.IsSecret(name) and name ~= "" then playerName = name end
    return playerName
end

-- nil until GUID, name and realm are known: a record needs all three.
function ns.GetPlayerKey()
    if playerKey then return playerKey end
    local guid = UnitGUID("player")
    if type(guid) ~= "string" or ns.IsSecret(guid) or guid == "" then return nil end
    if not ns.GetPlayerName() or not ns.GetPlayerRealm() then return nil end
    playerKey = guid
    return playerKey
end

-- The key versions before 0.10.0 filed this character under.
function ns.GetLegacyPlayerKey()
    local first = UnitName("player")
    local realm = ns.GetPlayerRealm()
    if type(first) ~= "string" or ns.IsSecret(first) or first == "" or not realm then return nil end
    return first .. "-" .. realm
end

function ns.IsGUIDKey(key)
    return type(key) == "string" and strfind(key, "^Player%-") ~= nil
end

-- Test hook: forget the cached identity (tests switch characters).
function ns.ResetIdentityCache()
    playerKey, playerRealm, playerName = nil, nil, nil
end

-- "Name-Realm" -> "Name", "Realm" (guild keys, records of older versions).
-- Names hold no hyphen, realms can.
function ns.SplitKey(key)
    local name, realm = strmatch(key or "", "^([^%-]+)%-(.+)$")
    return name or key, realm
end

local function Trim(s)
    return (strgsub(strgsub(s, "^%s+", ""), "%s+$", ""))
end

-- Typed character name -> key of a known character or nil, and true when the
-- name fits more than one record. Takes "name" (current realm) and
-- "name-realm", ignoring case and the spaces, hyphens and apostrophes of the
-- realm. The full name matches (on WoW Forever "First Last"); a first name
-- alone only when one character on that realm has it. Of two records with the
-- same name (one not yet moved to its GUID) the GUID-keyed one is returned,
-- as it belongs to the live character; callers that remove data check the
-- second value, since the other record may be the one meant.
function ns.FindCharacterByName(chars, input)
    if type(input) ~= "string" or type(chars) ~= "table" then return nil end
    input = Trim(input)
    if input == "" then return nil end
    local name, realm = strmatch(input, "^([^%-]+)%-(.+)$")
    if not name then name, realm = input, ns.GetPlayerRealm() end
    if not realm then return nil end
    name, realm = strlower(Trim(name)), strlower(strgsub(realm, "[%s%-']", ""))
    local exact, exactCount, byFirst, firstCount = nil, 0, nil, 0
    for key, c in pairs(chars) do
        if type(c) == "table" and type(c.name) == "string" and type(c.realm) == "string"
            and strlower(c.realm) == realm then
            if strlower(c.name) == name then
                exactCount = exactCount + 1
                if not exact or ns.IsGUIDKey(key) then exact = key end
            elseif type(c.firstName) == "string" and strlower(c.firstName) == name then
                byFirst, firstCount = key, firstCount + 1
            end
        end
    end
    if exact then return exact, exactCount > 1 end
    if firstCount == 1 then return byFirst, false end
    return nil, firstCount > 1
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
    local realm = ns.Compat.GuildRealmKey(guildRealm) or ns.GetPlayerRealm()
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
