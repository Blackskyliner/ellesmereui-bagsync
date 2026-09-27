-------------------------------------------------------------------------------
--  Collect/Character.lua
--  Character meta data: class, race, faction, level, guild, money, last seen.
--  Always active (the other collectors key their data by this record); it
--  listens to a few rare events and does O(1) work per event.
--
--  Money is only taken from reliable moments: PLAYER_MONEY (a real change)
--  and world entry. It is never read at logout: while the client tears the
--  character down GetMoney() can report 0, which would store 0g for every
--  character you leave. A money value cannot change while a character is
--  offline, so a 0 reading at login/zoning never overwrites a stored amount;
--  a real drop to 0 arrives as PLAYER_MONEY and is stored.
-------------------------------------------------------------------------------
local _, ns = ...

local time = time

local leavingWorld = false

-- allowZero: the reading comes from a real money change (PLAYER_MONEY).
local function StoreMoney(c, allowZero)
    local money = GetMoney()
    if money == nil or ns.IsSecret(money) then return false end
    if money == 0 and (c.money or 0) > 0 and (not allowZero or leavingWorld) then
        return false   -- client not ready (login) or tearing down (logout/loading screen)
    end
    if c.money == money then return false end
    c.money = money
    c.moneyAt = time()
    return true
end

-- One-time repair for data saved by 0.1.0, which read money at logout and so
-- stored 0g for characters that were left: take EllesmereUI's own per-character
-- gold record (never written at logout) for offline characters stuck at 0.
-- Runs at the first activation of a database; db.moneyRepaired marks it done.
local function RepairMoneyFromEUI()
    if ns.db.moneyRepaired then return 0 end
    ns.db.moneyRepaired = true
    local Ext = _G.EllesmereUIBagsExt
    local playerKey = ns.GetPlayerKey()
    local repaired = 0
    for key, c in pairs(ns.db.chars) do
        if key ~= playerKey and (c.money or 0) == 0 and c.name and c.realmName then
            local gold, updated = Ext:GetCharacterGold(c.name, c.realmName)
            if gold and gold > 0 then
                c.money = gold
                c.moneyAt = updated
                repaired = repaired + 1
            end
        end
    end
    return repaired
end
ns.RepairMoneyFromEUI = RepairMoneyFromEUI

local function UpdateMeta()
    local key = ns.GetPlayerKey()
    if not key then return end
    local c = ns.GetChar(key, true)
    c.name, c.realm = ns.SplitKey(key)
    c.realmName = GetRealmName() or c.realm
    local _, classFile = UnitClass("player")
    c.class = classFile or c.class
    local _, raceFile = UnitRace("player")
    c.race = raceFile or c.race
    c.faction = UnitFactionGroup("player") or c.faction
    c.level = UnitLevel("player") or c.level
    c.guild = ns.GetPlayerGuildKey()
    StoreMoney(c, false)
    c.lastSeen = time()
    return c
end
ns.UpdateCharacterMeta = UpdateMeta

ns.RegisterFeature({
    key = "character",
    IsEnabled = function() return true end,
    OnEnable = function(self)
        leavingWorld = false
        UpdateMeta()
        RepairMoneyFromEUI()
        ns.RegisterEvent(self, "PLAYER_MONEY", function()
            local c = ns.GetPlayerChar(true)
            if c and StoreMoney(c, true) then
                ns.Fire("CHAR_UPDATED", ns.GetPlayerKey(), "money")
            end
        end)
        ns.RegisterEvent(self, "PLAYER_ENTERING_WORLD", function()
            leavingWorld = false
            local c = ns.GetPlayerChar(true)
            if c and StoreMoney(c, false) then
                ns.Fire("CHAR_UPDATED", ns.GetPlayerKey(), "money")
            end
        end)
        ns.RegisterEvent(self, "PLAYER_LEAVING_WORLD", function()
            leavingWorld = true
        end)
        ns.RegisterEvent(self, "PLAYER_LEVEL_UP", function(_, _, level)
            local c = ns.GetPlayerChar(true)
            if c then c.level = level or UnitLevel("player") end
        end)
        ns.RegisterEvent(self, "PLAYER_GUILD_UPDATE", function(_, _, unit)
            if unit and unit ~= "player" then return end
            local c = ns.GetPlayerChar(true)
            if c then c.guild = ns.GetPlayerGuildKey() end
        end)
        ns.RegisterEvent(self, "PLAYER_LOGOUT", function()
            -- Only the timestamp: money is deliberately not read here (see header).
            local c = ns.GetPlayerChar(false)
            if c then c.lastSeen = time() end
        end)
    end,
})
