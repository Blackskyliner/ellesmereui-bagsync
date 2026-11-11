-- Client APIs that the simulator does not implement for a client, while
-- EllesmereUI, Blizzard's own UI or this addon call them there. Each stand-in
-- answers like the documented API (SimGapSignatures.lua, generated from the
-- client's API docs) for a player on mouse and keyboard with the test
-- fixture's state, and is installed only while the simulator lacks the API,
-- so a simulator that adds it takes over.
--
-- Gap(name, client, fn, opts) registers one: client is "retail", "forever"
-- or "both"; opts.rarely marks a stand-in the test run may never call, and
-- opts.nilable names the client code that shows a return the docs call
-- non-nilable can be nil (the types are still checked).
-- scripts/check-api.py checks that each name is an API of its client, and
-- tests/99_sim_gaps.lua that each stand-in is still missing in the simulator,
-- was called, and returned what the docs promise.

SIM_CLIENT = (EllesmereUI and EllesmereUI.IS_FOREVER == true) and "forever" or "retail"

SimGapRegistry = {}

local function Resolve(name)
    local ns, fn = name:match("^([%w_]+)%.([%w_]+)$")
    if ns then
        _G[ns] = _G[ns] or {}
        return _G[ns], fn
    end
    return _G, name
end

-- Compares one call's returns with the documented ones; the first mismatch
-- per stand-in is kept for tests/99_sim_gaps.lua.
local function CheckReturns(gap, ...)
    local sig = SimGapSignatures and SimGapSignatures[SIM_CLIENT] and SimGapSignatures[SIM_CLIENT][gap.name]
    if not sig or gap.mismatch then return end
    local n = select("#", ...)
    local anyNil = gap.nilable ~= nil
    if n > #sig then
        gap.mismatch = ("returned %d values, documented %d"):format(n, #sig)
        return
    end
    for i, want in ipairs(sig) do
        local value = select(i, ...)
        local documentedNilable = want:sub(-1) == "?"
        local nilable = documentedNilable or anyNil
        local t = documentedNilable and want:sub(1, -2) or want
        if value == nil then
            if not nilable then gap.mismatch = ("return %d is nil, documented %s"):format(i, want) return end
        elseif t ~= "*" and type(value) ~= t then
            gap.mismatch = ("return %d is a %s, documented %s"):format(i, type(value), want)
            return
        end
    end
end

function Gap(name, client, fn, opts)
    local gap = { name = name, client = client, rarely = opts and opts.rarely, nilable = opts and opts.nilable,
                  calls = 0 }
    SimGapRegistry[#SimGapRegistry + 1] = gap
    if client ~= "both" and client ~= SIM_CLIENT then return end
    gap.applies = true
    local tbl, key = Resolve(name)
    if tbl[key] ~= nil then return end
    gap.installed = true
    tbl[key] = function(...)
        gap.calls = gap.calls + 1
        local function pass(...) CheckReturns(gap, ...) return ... end
        return pass(fn(...))
    end
end

-- Retail: EllesmereUI's gamepad support asks it whenever its bag window opens.
Gap("IsUsingGamepad", "retail", function() return false end)

-- Forever: PlayerInteractionManagerDocumentation.lua: no NPC window is open.
Gap("C_PlayerInteractionManager.IsInteractingWithNpcOfType", "forever", function() return false end)
-- AuctionHouseDocumentation.lua: the character has no auctions.
Gap("C_AuctionHouse.GetOwnedAuctions", "forever", function() return {} end)
-- AzeriteEmpoweredItemDocumentation.lua: Blizzard's item buttons ask it; no
-- Forever item is Azerite empowered.
Gap("C_AzeriteEmpoweredItem.IsAzeriteEmpoweredItemByID", "forever", function() return false end)
-- BankDocumentation.lua: a banker opens the character bank; Forever has no
-- warband bank to view.
Gap("C_Bank.CanViewBank", "forever", function(bankType) return bankType == Enum.BankType.Character end)
-- CurrencyInfoDocumentation.lua: the ID of a currency link, 0 for any other
-- string (the field is not nilable).
Gap("C_CurrencyInfo.GetCurrencyIDFromLink", "forever", function(link)
    return tonumber(type(link) == "string" and link:match("currency:(%d+)") or nil) or 0
end, { rarely = true })
-- ItemDocumentation.lua: Blizzard's item buttons ask these for their icon
-- overlay; no Forever item is corrupted, cosmetic, a curio, relic or decor.
Gap("C_Item.IsCorruptedItem", "forever", function() return false end)
Gap("C_Item.IsCosmeticItem", "forever", function() return false end)
Gap("C_Item.IsCurioItem", "forever", function() return false end)
Gap("C_Item.IsRelicItem", "forever", function() return false end)
Gap("C_Item.IsDecorItem", "forever", function() return false end)
-- SoulbindsDocumentation.lua: asked by the same overlay code; Forever has no
-- conduits.
Gap("C_Soulbinds.IsItemConduitByItemInfo", "forever", function() return false end)
