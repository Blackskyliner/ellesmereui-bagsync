-------------------------------------------------------------------------------
--  UI/Search.lua
--  Search across every character, the warband bank and guild banks, plus the
--  names of the currencies stored for any character.
--  Own matcher on purpose: C_Container.SetItemSearch only filters live slots
--  and is client-global (it would also filter the EUI bag window).
--
--  Syntax (terms are AND-ed, case-insensitive):
--      words            item name or tooltip text contains every word
--      "two words"      a phrase: in the name or in one tooltip line as typed
--      12345 / id:12345 exact itemID
--      q:epic / q:4     quality (english keyword, localized name or number)
--      t:armor          item type or subtype contains the text
--  Currencies match on words and a bare number only; id:, q: and t: filter
--  items and exclude currencies.
--
--  Bind expressions, the keywords EllesmereUI Bags adds to the game's search:
--  a text made only of bop, boe, wue, boa, soulbound and warbound, each with
--  an optional item level (bop=300, boe>=280, wue 290-300), joined with
--  and / or / not (also & | !) and parentheses, is a bind expression and
--  matches stacks by their bind type and bound state. Any other text is the
--  syntax above, as in EllesmereUI Bags, where such a text goes to the game.
-------------------------------------------------------------------------------
local _, ns = ...

local strlower, strfind, strmatch, strgsub, tonumber, sort = string.lower, string.find, string.match, string.gsub,
    tonumber, table.sort
local min, max = math.min, math.max

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

-------------------------------------------------------------------------------
--  Bind expressions
--  Grammar: or-terms of and-terms of [not] primaries; a primary is a keyword
--  with an optional item level or a parenthesized expression. Terms side by
--  side mean and; not binds tighter than and, and tighter than or. A text that
--  does not fit parses to nil and is searched as words.
-------------------------------------------------------------------------------
local BIND_KEYWORDS = { bop = true, boe = true, wue = true, boa = true, soulbound = true, warbound = true }
local OPS = { ["="] = "=", ["=="] = "=", [">"] = ">", [">="] = ">=", ["<"] = "<", ["<="] = "<=" }
local MAX_DEPTH = 12   -- nesting limit, so a pasted text cannot exhaust the stack

local function Tokenize(s)
    local toks, i, n = {}, 1, #s
    while i <= n do
        local c = s:sub(i, i)
        if strfind(c, "^%s") then
            i = i + 1
        elseif c == "(" then toks[#toks + 1] = { k = "lp" }; i = i + 1
        elseif c == ")" then toks[#toks + 1] = { k = "rp" }; i = i + 1
        elseif c == "!" then toks[#toks + 1] = { k = "not" }; i = i + 1
        elseif c == "&" then toks[#toks + 1] = { k = "and" }; i = i + #strmatch(s, "^&&?", i)
        elseif c == "|" then toks[#toks + 1] = { k = "or" }; i = i + #strmatch(s, "^||?", i)
        elseif strfind(c, "^[<>=]") then
            local op = strmatch(s, "^[<>=]=?", i)
            if not OPS[op] then return nil end
            toks[#toks + 1] = { k = "op", v = OPS[op] }; i = i + #op
        elseif strfind(c, "^%d") then
            local a, b, e = strmatch(s, "^(%d+)%s*%-%s*(%d+)()", i)
            if a then
                toks[#toks + 1] = { k = "range", lo = tonumber(a), hi = tonumber(b) }; i = e
            else
                local d = strmatch(s, "^%d+", i)
                toks[#toks + 1] = { k = "num", v = tonumber(d) }; i = i + #d
            end
        elseif strfind(c, "^%a") then
            local w = strmatch(s, "^%a+", i)
            i = i + #w
            if w == "and" or w == "or" or w == "not" then toks[#toks + 1] = { k = w }
            elseif BIND_KEYWORDS[w] then toks[#toks + 1] = { k = "kw", v = w }
            else return nil end
        else
            return nil
        end
    end
    return toks
end

-- lower-cased, trimmed text -> expression tree or nil
local function ParseBind(text)
    local toks = Tokenize(text)
    if not toks or #toks == 0 then return nil end
    local p = 1
    local ParseOr

    local function ParsePrimary(depth)
        local t = toks[p]
        if not t then return nil end
        if t.k == "lp" then
            if depth >= MAX_DEPTH then return nil end
            p = p + 1
            local e = ParseOr(depth + 1)
            if not e or not toks[p] or toks[p].k ~= "rp" then return nil end
            p = p + 1
            return e
        end
        if t.k ~= "kw" then return nil end
        p = p + 1
        local node = { t = "term", kw = t.v }
        local nx = toks[p]
        if nx and nx.k == "op" then
            local num = toks[p + 1]
            if not num or num.k ~= "num" then return nil end
            node.op, node.lo = nx.v, num.v
            p = p + 2
        elseif nx and nx.k == "range" then
            node.op, node.lo, node.hi = "-", min(nx.lo, nx.hi), max(nx.lo, nx.hi)
            p = p + 1
        elseif nx and nx.k == "num" then
            node.op, node.lo = "=", nx.v
            p = p + 1
        end
        return node
    end

    local function ParseNot(depth)
        local t = toks[p]
        if t and t.k == "not" then
            if depth >= MAX_DEPTH then return nil end
            p = p + 1
            local a = ParseNot(depth + 1)
            return a and { t = "not", a = a }
        end
        return ParsePrimary(depth)
    end

    local function ParseAnd(depth)
        local l = ParseNot(depth)
        while l and toks[p] and (toks[p].k == "and" or toks[p].k == "kw" or toks[p].k == "not" or toks[p].k == "lp") do
            if toks[p].k == "and" then p = p + 1 end
            local r = ParseNot(depth)
            l = r and { t = "and", a = l, b = r }
        end
        return l
    end

    ParseOr = function(depth)
        local l = ParseAnd(depth)
        while l and toks[p] and toks[p].k == "or" do
            p = p + 1
            local r = ParseAnd(depth)
            l = r and { t = "or", a = l, b = r }
        end
        return l
    end

    local root = ParseOr(0)
    if root and p == #toks + 1 then return root end
    return nil
end

-- The stack under test, set by StackMatches before each Eval. Warbound until
-- equipped and the item level are looked up only when a term asks.
local cur = {}

local function LevelMatches(n)
    if cur.ilvl == nil then
        cur.ilvl = C_Item.GetDetailedItemLevelInfo(cur.ref) or false
    end
    local ilvl, op, lo = cur.ilvl, n.op, n.lo
    if not ilvl then return false end
    if op == "=" then return ilvl == lo end
    if op == ">" then return ilvl > lo end
    if op == ">=" then return ilvl >= lo end
    if op == "<" then return ilvl < lo end
    if op == "<=" then return ilvl <= lo end
    return ilvl >= lo and ilvl <= n.hi
end

local function TermMatches(n)
    local k, bindType, bound = n.kw, cur.bindType, cur.bound
    local match
    if k == "bop" then
        match = bindType == Enum.ItemBind.OnAcquire
    elseif k == "boa" then
        match = bindType == Enum.ItemBind.ToWoWAccount
    elseif k == "soulbound" then
        match = bound == "soul"
    elseif k == "warbound" then
        match = bound == "account"
    elseif bound == "wue" then
        -- Recorded as warbound until equipped: not bound yet, and no BoE.
        match = k == "wue"
    elseif bound then
        -- BoE and WuE both mean "not bound yet".
        match = false
    else
        if cur.wue == nil then
            -- The game reports most WuE items as OnEquip, so the item itself
            -- tells the two apart.
            cur.wue = bindType == Enum.ItemBind.ToBnetAccountUntilEquipped
                or C_Item.IsItemBindToAccountUntilEquip(cur.ref) == true
        end
        if k == "wue" then
            match = cur.wue
        else
            match = not cur.wue and bindType == Enum.ItemBind.OnEquip
        end
    end
    if match and n.op then match = LevelMatches(n) end
    return match
end

local function Eval(n)
    local t = n.t
    if t == "term" then return TermMatches(n) end
    if t == "not" then return not Eval(n.a) end
    if t == "and" then return Eval(n.a) and Eval(n.b) end
    return Eval(n.a) or Eval(n.b)
end

-- A stored stack against a bind expression. bindType: the item's bind type.
local function StackMatches(expr, enc, bindType)
    local _, _, _, bound = ns.DecodeItem(enc)
    cur.bindType, cur.bound, cur.ref = bindType, bound, ns.ItemRef(enc)
    cur.wue, cur.ilvl = nil, nil
    return Eval(expr) and true or false
end

-------------------------------------------------------------------------------
--  Parsing
-------------------------------------------------------------------------------
function Search.Parse(text)
    if type(text) ~= "string" then return nil end
    text = strlower(text:gsub("^%s+", ""):gsub("%s+$", ""))
    if text == "" then return nil end
    local bind = ParseBind(text)
    if bind then return { words = {}, bind = bind } end
    local q = { words = {} }
    -- "quoted text" is one word with its spaces: it has to stand in the name
    -- or in one tooltip line as typed; an unclosed quote runs to the end
    text = strgsub(text, '"([^"]*)"?', function(phrase)
        phrase = strgsub(strgsub(strgsub(phrase, "^%s+", ""), "%s+$", ""), "%s+", " ")
        if phrase ~= "" then q.words[#q.words + 1] = phrase end
        return " "
    end)
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

-------------------------------------------------------------------------------
--  Tooltip text
--  The game's own bag search matches the whole tooltip ("equip" finds every
--  item that binds when equipped), so words that are not in the name are
--  looked up there. Built once per item and session: an item's tooltip by ID
--  does not change, and building it is the expensive part of a search.
--  The binding line is kept apart: a stored stack that is bound reads
--  "Soulbound" or "Warbound" there, as its tooltip in the browser and the
--  game's search of a live bag do, not the item's generic "Binds when
--  equipped".
-------------------------------------------------------------------------------
local BINDING_LINE = Enum.TooltipDataLineType.ItemBinding
local tooltipText = {}   -- itemID -> { rest = lower-cased lines, bind = binding line or nil }

-- colour codes would split words ("|cffffffffBinds" never matches "binds")
local function Plain(text)
    return strlower(strgsub(strgsub(text, "|c%x%x%x%x%x%x%x%x", ""), "|r", ""))
end

local function TooltipText(itemID)
    local tip = tooltipText[itemID]
    if tip then return tip end
    local data = C_TooltipInfo.GetItemByID(itemID)
    local lines = type(data) == "table" and data.lines
    local parts, bind = {}, nil
    local function usable(t) return type(t) == "string" and not ns.IsSecret(t) and t ~= "" end
    if type(lines) == "table" then
        for _, line in ipairs(lines) do
            if line.type == BINDING_LINE and usable(line.leftText) then
                bind = Plain(line.leftText)
            else
                if usable(line.leftText) then parts[#parts + 1] = line.leftText end
                if usable(line.rightText) then parts[#parts + 1] = line.rightText end
            end
        end
    end
    tip = { rest = Plain(table.concat(parts, "\n")), bind = bind }
    tooltipText[itemID] = tip
    return tip
end

-- The binding line of a stack in a bound state ("free", "soul", "account").
local function BindingText(tip, state)
    if state == "soul" then return strlower(ITEM_SOULBOUND) end
    if state == "account" then return strlower(ITEM_ACCOUNTBOUND) end
    return tip.bind
end

-- itemID -> { [state] = true } over every stored stack ("free", "soul", "account")
local function BoundStates()
    local states = {}
    ns.Index:EachStack(function(enc)
        local id, _, _, bound = ns.DecodeItem(enc)
        if id then
            local set = states[id]
            if not set then set = {}; states[id] = set end
            set[bound or "free"] = true
        end
    end)
    return states
end

-- Every word in the tooltip of at least one stack: words the generic lines
-- hold, the rest in that stack's binding line.
local function TooltipMatches(itemID, words, stateSets)
    local tip = TooltipText(itemID)
    local missing
    for i = 1, #words do
        if not strfind(tip.rest, words[i], 1, true) then
            missing = missing or {}
            missing[#missing + 1] = words[i]
        end
    end
    if not missing then return true end
    for state in pairs(stateSets and stateSets[itemID] or { free = true }) do
        local bind = BindingText(tip, state)
        local all = bind ~= nil
        for i = 1, all and #missing or 0 do
            if not strfind(bind, missing[i], 1, true) then all = false; break end
        end
        if all then return true end
    end
    return false
end

-- Currency name (lower-cased) against the words and the bare number.
local function NameMatches(q, name)
    if q.numericToken and not strfind(name, q.numericToken, 1, true) then return false end
    for i = 1, #q.words do
        if not strfind(name, q.words[i], 1, true) then return false end
    end
    return true
end

-- -> matches (bool), pending (true when item data is not cached yet).
-- stateSets: the bound states of the stacks (BoundStates), or a function
-- returning them, read when a word needs the tooltip; without it the item
-- counts as unbound.
function Search.Matches(q, itemID, stateSets)
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
    if q.quality ~= nil and quality ~= q.quality then return false, false end
    if q.typeText then
        local _, itemType, itemSubType = C_Item.GetItemInfoInstant(itemID)
        local t = strlower((itemType or "") .. " " .. (itemSubType or ""))
        if not strfind(t, q.typeText, 1, true) then return false, false end
    end
    local tipWords
    for i = 1, #q.words do
        if not strfind(name, q.words[i], 1, true) then
            tipWords = tipWords or {}
            tipWords[#tipWords + 1] = q.words[i]
        end
    end
    if tipWords then
        if type(stateSets) == "function" then stateSets = stateSets() end
        if not TooltipMatches(itemID, tipWords, stateSets) then return false, false end
    end
    return true, false
end

-- One stored stack against a query: a bind expression by the stack's own
-- bind state, other terms by its item, tooltip words read with the stack's
-- binding line. -> matches, pending (item data not cached yet)
function Search.StackMatches(q, enc)
    if q.invalid then return false, false end
    local id, _, _, bound = ns.DecodeItem(enc)
    if not id then return false, false end
    if q.bind then
        local name, _, _, _, _, _, _, _, _, _, _, _, _, bindType = C_Item.GetItemInfo(id)
        if not name then return false, true end
        return StackMatches(q.bind, enc, bindType or Enum.ItemBind.None), false
    end
    return Search.Matches(q, id, { [id] = { [bound or "free"] = true } })
end

local function Result(itemID)
    return { itemID = itemID, total = ns.Index:GetTotal(itemID),
             name = C_Item.GetItemInfo(itemID) or ("item:" .. itemID) }
end

-- Items with at least one stack the bind expression matches.
local function RunBind(expr, results, pending)
    local bindTypes, matched = {}, {}   -- itemID -> bind type, or false while not cached
    ns.Index:EachStack(function(enc)
        local id = ns.DecodeItemIDCount(enc)
        if not id or matched[id] then return end
        local bindType = bindTypes[id]
        if bindType == nil then
            local name, _, _, _, _, _, _, _, _, _, _, _, _, bt = C_Item.GetItemInfo(id)
            bindType = name and (bt or Enum.ItemBind.None) or false
            bindTypes[id] = bindType
            if not bindType then pending[#pending + 1] = id end
        end
        if bindType and StackMatches(expr, enc, bindType) then
            matched[id] = true
            results[#results + 1] = Result(id)
        end
    end)
end

-- -> results = { { itemID, total, name, bound }, ... } (sorted by name), pendingIDs = { id, ... }
-- bound: "soul" or "account" when every stored stack of the item is bound so
function Search.Run(q, limit)
    local results, pending = {}, {}
    if not q then return results, pending end
    limit = limit or 500
    local stateSets
    if q.bind then
        ns.Index:EnsureBuilt()
        RunBind(q.bind, results, pending)
    else
        -- walked once and only when a word needs a tooltip
        local function states()
            stateSets = stateSets or BoundStates()
            return stateSets
        end
        for itemID in ns.Index:AllItemIDs() do
            local ok, isPending = Search.Matches(q, itemID, states)
            if ok then
                results[#results + 1] = Result(itemID)
            elseif isPending then
                pending[#pending + 1] = itemID
            end
        end
    end
    sort(results, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return a.itemID < b.itemID
    end)
    for i = #results, limit + 1, -1 do results[i] = nil end
    if #results > 0 then
        -- the state every stack of a hit shares, for its tooltip
        stateSets = stateSets or BoundStates()
        for _, r in ipairs(results) do
            local set = stateSets[r.itemID]
            local only = set and next(set)
            if only and only ~= "free" and next(set, only) == nil then r.bound = only end
        end
    end
    return results, pending
end

-- Lower-cased first word of a client string, or the fallback. The examples
-- come from the client so they match in its language: a "t:" or "q:" value
-- is one word.
local function ExampleWord(text, fallback)
    local word = type(text) == "string" and strmatch(text, "%S+")
    return word and strlower(word) or fallback
end

-- The syntax help of the search box -> { title, rows = { { left, right } }, notes = { text } }
function Search.HelpLines()
    local L = ns.L
    local quality = ExampleWord(_G.ITEM_QUALITY4_DESC, "epic")
    local itemType = ExampleWord(C_Item.GetItemClassInfo(Enum.ItemClass.Armor), "armor")
    local bindRows
    if ns.Compat.HAS_ACCOUNT_BINDING then
        bindRows = {
            { "bop  boe  wue  boa", L["Bind type"] },
            { "soulbound  warbound", L["Bound to a character or the warband"] },
            { "boe>=600  wue 590-610", L["Bind type and item level"] },
            { "bop or (boe and not wue)", L["Bind terms with and, or, not"] },
        }
    else
        bindRows = {
            { "bop  boe", L["Bind type"] },
            { "soulbound", L["Bound to a character"] },
            { "boe>=20  bop 10-30", L["Bind type and item level"] },
            { "bop or (boe and not soulbound)", L["Bind terms with and, or, not"] },
        }
    end
    local help = {
        title = L["Search syntax"],
        rows = {
            { L["words"], L["Name or tooltip contains every word"] },
            { '"' .. L["two words"] .. '"', L["Phrase in the name or one tooltip line"] },
            { "12345  id:12345", L["Item ID"] },
            { "q:" .. quality .. "  q:4", L["Quality (name or number)"] },
            { "t:" .. itemType, L["Item type or subtype"] },
            { "q:" .. quality .. " t:" .. itemType, L["All terms must match"] },
        },
        notes = {
            L["Currencies match words and numbers only."],
            L["Bind terms do not mix with words, q: and t:."],
        },
    }
    for _, row in ipairs(bindRows) do help.rows[#help.rows + 1] = row end
    return help
end

-- -> { { currencyID, name, info }, ... } sorted by name
function Search.RunCurrencies(q)
    local out = {}
    if not q or q.invalid or q.bind or q.quality ~= nil or q.typeText or (q.itemID and not q.numericToken) then
        return out
    end
    local seen = {}
    for _, c in pairs(ns.db.chars) do
        for id in pairs(c.currency or {}) do
            if not seen[id] then
                seen[id] = true
                local info = C_CurrencyInfo.GetCurrencyInfo(id)
                local name = info and info.name
                if type(name) == "string" and not ns.IsSecret(name) and name ~= "" and NameMatches(q, strlower(name)) then
                    out[#out + 1] = { currencyID = id, name = name, info = info }
                end
            end
        end
    end
    sort(out, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return a.currencyID < b.currencyID
    end)
    return out
end
