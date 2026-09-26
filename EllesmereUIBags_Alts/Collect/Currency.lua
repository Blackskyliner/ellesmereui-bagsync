-------------------------------------------------------------------------------
--  Collect/Currency.lua
--  Currency quantities per character. The initial pass walks the currency
--  list; afterwards CURRENCY_DISPLAY_UPDATE names the changed currency, so each
--  update is a single C_CurrencyInfo.GetCurrencyInfo call.
-------------------------------------------------------------------------------
local _, ns = ...

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
    if quantity == nil then
        local info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
        quantity = info and info.quantity
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
