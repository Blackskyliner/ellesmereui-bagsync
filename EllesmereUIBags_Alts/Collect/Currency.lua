-------------------------------------------------------------------------------
--  Collect/Currency.lua
--  Currency quantities per character. The initial pass walks the currency
--  list; afterwards CURRENCY_DISPLAY_UPDATE names the changed currency, so each
--  update is a single C_CurrencyInfo.GetCurrencyInfo call.
--
--  Currency kind (character-bound / warband-transferable / warband-wide) is
--  static per currency; it is remembered account wide in db.currencyMeta so the
--  browser can group currencies of offline characters even when the client has
--  no info for them.
-------------------------------------------------------------------------------
local _, ns = ...

local function RememberKind(id, info)
    if type(info) ~= "table" or not id or ns.IsSecret(id) then return end
    local t, w = info.isAccountTransferable, info.isAccountWide
    if ns.IsSecret(t) or ns.IsSecret(w) then return end
    local meta = ns.db.currencyMeta[id]
    if meta and meta.t == (t == true) and meta.w == (w == true) then return end
    ns.db.currencyMeta[id] = { t = t == true, w = w == true }
end

local function Store(c, id, quantity)
    if not id or ns.IsSecret(id) or ns.IsSecret(quantity) then return false end
    local q = (quantity and quantity > 0) and quantity or nil
    if c.currency[id] == q then return false end
    c.currency[id] = q
    return true
end

local function FullScan()
    local c = ns.GetPlayerChar(true)
    if not c then return end
    local changed = false
    local size = C_CurrencyInfo.GetCurrencyListSize() or 0
    for index = 1, size do
        local info = C_CurrencyInfo.GetCurrencyListInfo(index)
        if info and not info.isHeader then
            local id = info.currencyID
            if not id or id == 0 then
                local link = C_CurrencyInfo.GetCurrencyListLink(index)
                id = link and C_CurrencyInfo.GetCurrencyIDFromLink(link)
            end
            if Store(c, id, info.quantity) then changed = true end
            RememberKind(id, info)
        end
    end
    if changed then ns.Fire("CHAR_UPDATED", ns.GetPlayerKey(), "currency") end
end

local function OnCurrencyUpdate(_, _, currencyID, quantity)
    local c = ns.GetPlayerChar(true)
    if not c then return end
    if not currencyID then
        FullScan()
        return
    end
    if quantity == nil or not ns.db.currencyMeta[currencyID] then
        local info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
        if quantity == nil then quantity = info and info.quantity end
        RememberKind(currencyID, info)
    end
    if Store(c, currencyID, quantity) then
        ns.Fire("CHAR_UPDATED", ns.GetPlayerKey(), "currency")
    end
end

ns.RegisterFeature({
    key = "currency",
    IsEnabled = function(s) return s.collect.currency end,
    OnEnable = function(self)
        FullScan()
        ns.RegisterEvent(self, "CURRENCY_DISPLAY_UPDATE", OnCurrencyUpdate)
    end,
})
