-------------------------------------------------------------------------------
--  Collect/Character.lua
--  Character meta data: class, race, faction, level, guild, money, last seen.
--  Always active (the other collectors key their data by this record); it
--  listens to four rare events and does O(1) work per event.
-------------------------------------------------------------------------------
local _, ns = ...

local time = time

local function UpdateMeta()
    local key = ns.GetPlayerKey()
    if not key then return end
    local c = ns.GetChar(key, true)
    c.name, c.realm = ns.SplitKey(key)
    c.realmName = GetRealmName and GetRealmName() or c.realm
    local _, classFile = UnitClass("player")
    c.class = classFile or c.class
    local _, raceFile = UnitRace("player")
    c.race = raceFile or c.race
    c.faction = UnitFactionGroup("player") or c.faction
    c.level = UnitLevel("player") or c.level
    local guildKey = ns.GetPlayerGuildKey()
    c.guild = guildKey
    c.money = GetMoney()
    c.lastSeen = time()
    return c
end
ns.UpdateCharacterMeta = UpdateMeta

ns.RegisterFeature({
    key = "character",
    IsEnabled = function() return true end,
    OnEnable = function(self)
        UpdateMeta()
        ns.RegisterEvent(self, "PLAYER_MONEY", function()
            local c = ns.GetPlayerChar(true)
            if c then
                c.money = GetMoney()
                ns.Fire("CHAR_UPDATED", ns.GetPlayerKey(), "money")
            end
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
            local c = ns.GetPlayerChar(false)
            if c then
                c.lastSeen = time()
                c.money = GetMoney()
            end
        end)
    end,
})
