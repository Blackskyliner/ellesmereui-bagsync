-------------------------------------------------------------------------------
--  UI/Search.lua
--  Search across every character, the warband bank and guild banks.
--  Own matcher on purpose: C_Container.SetItemSearch only filters live slots
--  and is client-global (it would also filter the EUI bag window).
--
--  Syntax (terms are AND-ed, case-insensitive):
--      words            item name contains every word
--      12345 / id:12345 exact itemID
--      q:epic / q:4     quality (english keyword, localized name or number)
--      t:armor          item type or subtype contains the text
-------------------------------------------------------------------------------
local _, ns = ...

local strlower, strfind, strmatch, tonumber, sort = string.lower, string.find, string.match, tonumber, table.sort

local Search = {}
ns.Search = Search

local QUALITY_WORDS = {
    poor = 0, common = 1, uncommon = 2, rare = 3, epic = 4,
    legendary = 5, artifact = 6, heirloom = 7,
}

local function QualityFromWord(word)
    local n = tonumber(word)
    if n then return n end
    if QUALITY_WORDS[word] then return QUALITY_WORDS[word] end
    for q = 0, 8 do
        local desc = _G["ITEM_QUALITY" .. q .. "_DESC"]
        if type(desc) == "string" and strlower(desc) == word then return q end
    end
    return nil
end

function Search.Parse(text)
    if type(text) ~= "string" then return nil end
    text = strlower(text:gsub("^%s+", ""):gsub("%s+$", ""))
    if text == "" then return nil end
    local q = { words = {} }
    for token in text:gmatch("%S+") do
        local key, value = strmatch(token, "^(%a+):(.+)$")
        if key == "id" and tonumber(value) then
            q.itemID = tonumber(value)
        elseif key == "q" then
            q.quality = QualityFromWord(value)
            if q.quality == nil then q.invalid = true end
        elseif key == "t" then
            q.typeText = value
        elseif not key and tonumber(token) and #q.words == 0 and not q.itemID then
            q.itemID = tonumber(token)
            q.numericToken = token      -- also allow names containing the number
        else
            q.words[#q.words + 1] = token
        end
    end
    return q
end

-- -> matches (bool), pending (true when item data is not cached yet)
function Search.Matches(q, itemID)
    if q.invalid then return false, false end
    if q.itemID and not q.numericToken and itemID ~= q.itemID then return false, false end
    local needName = #q.words > 0 or q.numericToken ~= nil
    local needInfo = needName or q.quality ~= nil
    local name, quality
    if needInfo then
        local n, _, qual = C_Item.GetItemInfo(itemID)
        if not n then return false, true end
        name, quality = strlower(n), qual
    end
    if q.numericToken then
        if itemID ~= q.itemID and not strfind(name, q.numericToken, 1, true) then return false, false end
    end
    for i = 1, #q.words do
        if not strfind(name, q.words[i], 1, true) then return false, false end
    end
    if q.quality ~= nil and quality ~= q.quality then return false, false end
    if q.typeText then
        local _, itemType, itemSubType = C_Item.GetItemInfoInstant(itemID)
        local t = strlower((itemType or "") .. " " .. (itemSubType or ""))
        if not strfind(t, q.typeText, 1, true) then return false, false end
    end
    return true, false
end

-- -> results = { { itemID, total, name }, ... } (sorted by name), pendingIDs = { id, ... }
function Search.Run(q, limit)
    local results, pending = {}, {}
    if not q then return results, pending end
    limit = limit or 500
    for itemID in ns.Index:AllItemIDs() do
        local ok, isPending = Search.Matches(q, itemID)
        if ok then
            results[#results + 1] = { itemID = itemID, total = ns.Index:GetTotal(itemID),
                name = C_Item.GetItemInfo(itemID) or ("item:" .. itemID) }
        elseif isPending then
            pending[#pending + 1] = itemID
        end
    end
    sort(results, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return a.itemID < b.itemID
    end)
    for i = #results, limit + 1, -1 do results[i] = nil end
    return results, pending
end
