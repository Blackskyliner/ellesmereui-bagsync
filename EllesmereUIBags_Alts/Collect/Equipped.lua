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
    local items = {}
    for slot = FIRST_SLOT, LAST_SLOT do
        local link = GetInventoryItemLink("player", slot)
        if link and not ns.IsSecret(link) then
            local id = GetInventoryItemID("player", slot)
            if id and not ns.IsSecret(id) then
                items[slot] = ns.EncodeItem(id, 1, link)
            end
        end
    end
    local holder = { equipped = c.equipped }
    if ns.StoreContainer(holder, "equipped", { size = LAST_SLOT, items = items }, key, "equipped") then
        c.equipped = holder.equipped
        ns.Fire("CHAR_UPDATED", key, "equipped")
    end
end

ns.RegisterFeature({
    key = "equipped",
    IsEnabled = function(s) return s.collect.equipped end,
    OnEnable = function(self)
        Scan()
        ns.RegisterEvent(self, "PLAYER_EQUIPMENT_CHANGED", Scan)
        -- Item links can be incomplete right at login; the first world entry fixes them.
        ns.RegisterEvent(self, "PLAYER_ENTERING_WORLD", Scan)
    end,
})
