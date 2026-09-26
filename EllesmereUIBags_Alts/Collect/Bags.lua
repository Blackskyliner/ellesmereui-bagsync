-------------------------------------------------------------------------------
--  Collect/Bags.lua
--  Backpack, the four bag slots and the reagent bag (Enum.BagIndex 0..5).
-------------------------------------------------------------------------------
local _, ns = ...

local FIRST_BAG = Enum.BagIndex.Backpack      -- 0
local LAST_BAG  = Enum.BagIndex.ReagentBag    -- 5

local dirty = ns.NewDirtySet()
local deferredForCombat = false

local function IsInventoryBag(bagID)
    return type(bagID) == "number" and bagID >= FIRST_BAG and bagID <= LAST_BAG
end
ns.IsInventoryBag = IsInventoryBag

local feature

-- -> "changed" | "same" | "retry"
local function ScanOne(bagID)
    local key = ns.GetPlayerKey()
    local c = key and ns.GetChar(key, true)
    if not c then return "retry" end
    local container, secret = ns.ScanContainer(bagID)
    if secret then
        -- Restricted data (combat/instance): keep dirty, retry after combat.
        if not deferredForCombat then
            deferredForCombat = true
            ns.RegisterEvent(feature, "PLAYER_REGEN_ENABLED", function()
                ns.UnregisterEvent(feature, "PLAYER_REGEN_ENABLED")
                deferredForCombat = false
                feature:Flush()
            end)
        end
        return "retry"
    end
    return ns.StoreContainer(c.bags, bagID, container, key, "bags") and "changed" or "same"
end

feature = ns.RegisterFeature({
    key = "bags",
    IsEnabled = function(s) return s.collect.bags end,
    OnEnable = function(self)
        for bagID = FIRST_BAG, LAST_BAG do dirty:Mark(bagID) end
        self:Flush()
        ns.RegisterEvent(self, "BAG_UPDATE", function(_, _, bagID)
            if IsInventoryBag(bagID) then dirty:Mark(bagID) end
        end)
        ns.RegisterEvent(self, "BAG_UPDATE_DELAYED", function() self:Flush() end)
        -- Bag slots can change size (bag swapped) without item events.
        ns.RegisterEvent(self, "PLAYER_ENTERING_WORLD", function()
            for bagID = FIRST_BAG, LAST_BAG do dirty:Mark(bagID) end
            self:Flush()
        end)
    end,
    OnDisable = function()
        dirty:Clear()
        deferredForCombat = false
    end,
})

function feature:Flush()
    if dirty:IsEmpty() then return end
    local changed = false
    dirty:Flush(function(bagID)
        local result = ScanOne(bagID)
        if result == "changed" then changed = true end
        return result ~= "retry"
    end)
    if changed then ns.Fire("CHAR_UPDATED", ns.GetPlayerKey(), "bags") end
end
