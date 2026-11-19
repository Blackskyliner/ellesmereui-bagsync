-------------------------------------------------------------------------------
--  Value/Prices.lua
--  Unit prices of stored items from the price addons the player has
--  installed (Oribos Exchange, Auctionator, TradeSkillMaster) and the vendor.
--  Nothing here runs before the value list asks: no events, no hooks, no
--  timers. The price addons are optional; each is looked up by its global at
--  call time and called through pcall, because their errors must never
--  become ours (acceptance criterion 4).
--
--  All prices are copper per unit. Auction prices are what a buyer pays;
--  ns.Prices.Evaluate takes the auction house cut off when that option is on.
-------------------------------------------------------------------------------
local _, ns = ...

local Prices = {}
ns.Prices = Prices

local pcall, rawget, type, floor = pcall, rawget, type, math.floor

-- Auctionator's API asks every caller to name itself.
local CALLER = "EllesmereUIBags_Alts"

-- The auction house keeps 5% of every sale (commodities and items alike).
local AH_CUT = 0.05
Prices.AH_CUT = AH_CUT

-- Display order of the sources, in the options and the source menu.
Prices.SOURCES = { "oeRegion", "oeRealm", "auctionator", "tsm", "vendor" }

-- Sources that price an auction; a bound item has none of them.
local AUCTION = { oeRegion = true, oeRealm = true, auctionator = true, tsm = true }
Prices.AUCTION = AUCTION

-- The TSM price strings the options offer; the first is the default. TSM's
-- realm market value is the closest to a quick sale, and its region average
-- covers items the realm has not seen. "custom" reads the player's own price
-- string (settings.value.tsmCustom).
Prices.TSM_CHOICES = {
    "first(DBMarket, DBRegionMarketAvg)",
    "DBMarket", "DBMinBuyout", "DBHistorical",
    "DBRegionMarketAvg", "DBRegionHistorical", "DBRegionSaleAvg",
    "custom",
}

-- The TSM price string in effect, nil when "custom" has none yet.
function Prices.TSMPriceString()
    local v = ns.db.settings.value
    if v.tsmPrice ~= "custom" then return v.tsmPrice end
    local custom = type(v.tsmCustom) == "string" and v.tsmCustom:match("^%s*(.-)%s*$") or ""
    return custom ~= "" and custom or nil
end

-------------------------------------------------------------------------------
--  Price addons
-------------------------------------------------------------------------------
local function OE()
    local fn = rawget(_G, "OEMarketInfo")
    return type(fn) == "function" and fn or nil
end

local function AuctionatorAPI()
    local a = rawget(_G, "Auctionator")
    local api = type(a) == "table" and type(a.API) == "table" and a.API.v1
    return type(api) == "table" and api or nil
end

local function TSM()
    local api = rawget(_G, "TSM_API")
    if type(api) == "table" and type(api.GetCustomPriceValue) == "function"
        and type(api.ToItemString) == "function" then
        return api
    end
    return nil
end

-- Auctionator's own database holds what its scans saw. Its public API
-- answers per item only, so an empty database (no scan yet) is read from the
-- database object itself, guarded: nil when that is not possible.
-- -> "missing" (not loaded), "empty" (loaded, no scan data), "ready"
function Prices.AuctionatorState()
    if not AuctionatorAPI() then return "missing" end
    local db = rawget(_G, "Auctionator").Database
    if type(db) ~= "table" then return "empty" end
    if type(db.GetItemCount) == "function" then
        local ok, count = pcall(db.GetItemCount, db)
        if ok and count == 0 then return "empty" end
    end
    return "ready"
end

-- Is the source usable right now? (The vendor always is.)
function Prices.IsAvailable(source)
    if source == "vendor" then return true end
    if source == "oeRegion" or source == "oeRealm" then
        local fn = OE()
        if not fn then return false end
        local ok, loaded = pcall(fn, 0)   -- 0 asks whether its market data is loaded
        return ok and loaded == true
    end
    if source == "auctionator" then return AuctionatorAPI() ~= nil end
    if source == "tsm" then return TSM() ~= nil end
    return false
end

-- Positive whole copper or nil.
local function Copper(v)
    if type(v) ~= "number" or v <= 0 then return nil end
    return floor(v)
end

local oeResult = {}

-- -> region price, realm price (OEMarketInfo fills one table per call)
local function LookupOE(ref)
    local fn = OE()
    if not fn then return nil, nil end
    local ok = pcall(fn, ref, oeResult)
    if not ok then return nil, nil end
    return Copper(oeResult.region), Copper(oeResult.market)
end

-- -> price, days since Auctionator last saw the item (nil past 21 days)
local function LookupAuctionator(id, link)
    local api = AuctionatorAPI()
    if not api then return nil, nil end
    local okP, price, okA, age
    if link and type(api.GetAuctionPriceByItemLink) == "function" then
        okP, price = pcall(api.GetAuctionPriceByItemLink, CALLER, link)
        okA, age = pcall(api.GetAuctionAgeByItemLink, CALLER, link)
    elseif type(api.GetAuctionPriceByItemID) == "function" then
        okP, price = pcall(api.GetAuctionPriceByItemID, CALLER, id)
        okA, age = pcall(api.GetAuctionAgeByItemID, CALLER, id)
    end
    return okP and Copper(price) or nil, okA and type(age) == "number" and age or nil
end

local function LookupTSM(id, link)
    local api = TSM()
    if not api then return nil end
    local okS, itemString = pcall(api.ToItemString, link or ("item:" .. id))
    if not okS or type(itemString) ~= "string" then return nil end
    local priceString = Prices.TSMPriceString()
    if not priceString then return nil end
    local okV, value = pcall(api.GetCustomPriceValue, priceString, itemString)
    return okV and Copper(value) or nil
end

-- Vendor price from the item cache; nil when the item does not sell or its
-- data is not loaded yet (the list asks for it and renders again).
local function LookupVendor(id, link)
    local price = select(11, C_Item.GetItemInfo(link or id))
    return Copper(price)
end

-------------------------------------------------------------------------------
--  Cache: one lookup per item and source while a list is built. Prices
--  change only when the price addons get new data, which happens between
--  two openings of the list, not during one.
-------------------------------------------------------------------------------
local cache = {}

function Prices.Reset() wipe(cache) end

-- -> { oeRegion, oeRealm, auctionator, auctionatorAge, tsm, vendor } for one item
function Prices.All(id, link)
    local key = link or id
    local p = cache[key]
    if p then return p end
    p = {}
    local ref = link or id
    p.oeRegion, p.oeRealm = LookupOE(ref)
    p.auctionator, p.auctionatorAge = LookupAuctionator(id, link)
    p.tsm = LookupTSM(id, link)
    p.vendor = LookupVendor(id, link)
    -- The vendor price fills in once the item data arrives: do not keep its gap.
    if p.vendor or C_Item.GetItemInfo(ref) then cache[key] = p end
    return p
end

-------------------------------------------------------------------------------
--  Evaluation
-------------------------------------------------------------------------------
-- What one unit brings: an auction price after the cut (when that option is
-- on), a vendor price as it is.
function Prices.Net(source, price)
    if not price then return nil end
    if AUCTION[source] and ns.db.settings.value.ahCut then
        return floor(price * (1 - AH_CUT))
    end
    return price
end

-- Can the item sell through the source? Bound items (soulbound, warbound,
-- warbound until equipped) sell to vendors only.
function Prices.Applies(source, bound)
    return not AUCTION[source] or bound == nil
end

-- The auction price the automatic choice takes among the ticked sources:
-- Auctionator's, when its scans saw the item, as that is the current market;
-- otherwise the highest of Oribos Exchange and TSM, which only estimate it.
-- -> net unit, source (or nil)
local FALLBACK = { "oeRegion", "oeRealm", "tsm" }

local function AutoAuction(p, bound)
    if bound ~= nil then return nil end
    local enabled = ns.db.settings.value
    if enabled.auctionator then
        local net = Prices.Net("auctionator", p.auctionator)
        if net then return net, "auctionator" end
    end
    local unit, from
    for _, source in ipairs(FALLBACK) do
        local net = enabled[source] and Prices.Net(source, p[source])
        if net and (not unit or net > unit) then unit, from = net, source end
    end
    return unit, from
end

-- mode: "auto" (the auction price above, or the vendor's when that is
-- higher and ticked) or a source key.
-- -> unit (net copper or nil), source of it, auction unit (net) the gain
--    over the vendor compares with, the item's prices
function Prices.Evaluate(id, link, bound, mode)
    local p = Prices.All(id, link)
    local auction, auctionFrom = AutoAuction(p, bound)
    if mode == "auto" then
        local unit, from = auction, auctionFrom
        local vendor = ns.db.settings.value.vendor and p.vendor
        if vendor and (not unit or vendor > unit) then unit, from = vendor, "vendor" end
        return unit, from, auction, p
    end
    if not Prices.Applies(mode, bound) then return nil, nil, nil, p end
    local unit = Prices.Net(mode, p[mode])
    -- One auction source chosen: the gain is against that one. The vendor
    -- view keeps the automatic auction price, to show what the AH adds.
    if AUCTION[mode] then auction = unit end
    return unit, unit and mode or nil, auction, p
end
