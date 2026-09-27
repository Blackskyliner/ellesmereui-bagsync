-------------------------------------------------------------------------------
--  Collect/Equipped.lua
--  Worn gear (inventory slots INVSLOT_FIRST_EQUIPPED..INVSLOT_LAST_EQUIPPED).
-------------------------------------------------------------------------------
local _, ns = ...

local FIRST_SLOT = INVSLOT_FIRST_EQUIPPED or 1
local LAST_SLOT  = INVSLOT_LAST_EQUIPPED or 19

local function Scan()
    local key = ns.GetPlayerKey()
    local c = key and ns.GetChar(key, true)
    if not c then return end
    ns.InvalidateEquipmentSets()
    local lookup = ns.GetEquipmentSetLookup()
    local items, sets = {}, nil
    for slot = FIRST_SLOT, LAST_SLOT do
        local link = GetInventoryItemLink("player", slot)
        if link and not ns.IsSecret(link) then
            local id = GetInventoryItemID("player", slot)
            if id and not ns.IsSecret(id) then
                -- Worn gear is always bound; warbound stays warbound.
                local bound = ns.BoundState(true, ItemLocation:CreateFromEquipmentSlot(slot), id)
                items[slot] = ns.EncodeItem(id, 1, link, bound)
                local setNames = lookup["e" .. slot]
                if setNames then
                    sets = sets or {}
                    sets[slot] = setNames
                end
            end
        end
    end
    local holder = { equipped = c.equipped }
    if ns.StoreContainer(holder, "equipped", { size = LAST_SLOT, items = ns.PackItems(items), sets = sets }, key, "equipped") then
        c.equipped = holder.equipped
        ns.Fire("CHAR_UPDATED", key, "equipped")
    end
end

-- PLAYER_EQUIPMENT_CHANGED fires once per slot, an equipment set swap about
-- 16 times in a row; one scan on the next frame covers the burst
-- (self-removing one-shot OnUpdate, not polling).
local batch
local function ScanNextFrame()
    batch = batch or CreateFrame("Frame")
    batch:SetScript("OnUpdate", function(f)
        f:SetScript("OnUpdate", nil)
        Scan()
    end)
end

ns.RegisterFeature({
    key = "equipped",
    IsEnabled = function(s) return s.collect.equipped end,
    OnEnable = function(self)
        Scan()
        ns.RegisterEvent(self, "PLAYER_EQUIPMENT_CHANGED", ScanNextFrame)
        ns.RegisterEvent(self, "EQUIPMENT_SETS_CHANGED", Scan)
        -- Item links can be incomplete right at login; the first world entry
        -- fixes them (only relevant when activated before it).
        ns.RegisterEvent(self, "PLAYER_ENTERING_WORLD", function(_, _, isInitialLogin, isReloadingUi)
            if isInitialLogin or isReloadingUi then Scan() end
        end)
    end,
    OnDisable = function()
        if batch then batch:SetScript("OnUpdate", nil) end
    end,
})
