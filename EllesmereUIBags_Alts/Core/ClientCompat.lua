-------------------------------------------------------------------------------
--  Core/ClientCompat.lua
--  Everything that differs between the clients this addon runs on: retail
--  (12.x) and WoW Forever (1.60, Blizzard game type "camelot": the 12.1 engine
--  with vanilla content and rules). The rest of the addon asks ns.Compat and
--  never checks the client itself. scripts/check-api.py lets only this file
--  use an API that one of the clients lacks; each such use is guarded here.
-------------------------------------------------------------------------------
local _, ns = ...

local strgsub = string.gsub

local Compat = {}
ns.Compat = Compat

-- EllesmereUI decides the client once (EllesmereUI_ClientGate.lua) and is
-- loaded before this addon (TOC dependency); taking its answer keeps both
-- addons on the same side of every difference.
local EUI = _G.EllesmereUI
Compat.IS_FOREVER = type(EUI) == "table" and EUI.IS_FOREVER == true

-- Forever has no warband: no account bank, no warband gold.
Compat.HAS_WARBAND_BANK = not Compat.IS_FOREVER

-- Forever characters with the same first name differ only by surname.
Compat.UNIQUE_FIRST_NAMES = not Compat.IS_FOREVER

-- Forever has no pet battles; its BattlePetTooltipTemplate (Camelot variant)
-- lacks the battle stats and the Owned line the private pet tooltip fills.
Compat.HAS_PET_BATTLES = not Compat.IS_FOREVER

-------------------------------------------------------------------------------
--  Realms
--  Forever groups characters by ruleset instead of realm (normal, PvP, RP,
--  hardcore). EllesmereUI.RealmGroupName() returns that group on Forever and
--  GetRealmName() everywhere else; EllesmereUI keys its gold ledger by it.
-------------------------------------------------------------------------------
-- Realm part of the gold ledger key: display name, spaces kept.
function Compat.RealmGroupName()
    if type(EUI) == "table" and type(EUI.RealmGroupName) == "function" then
        return EUI.RealmGroupName()
    end
    return GetRealmName()
end

-- Realm part of a character key: GetNormalizedRealmName() on retail, the
-- realm group without spaces, hyphens and apostrophes on Forever (the same
-- normalization ns.FindCharacterByName applies to typed names).
function Compat.RealmKey()
    if not Compat.IS_FOREVER then return GetNormalizedRealmName() end
    local group = Compat.RealmGroupName()
    if type(group) ~= "string" then return nil end
    return (strgsub(group, "[%s%-']", ""))
end

-- Realm part of a guild key. A Forever guild belongs to the realm group of
-- its members, whatever GetGuildInfo reports as its realm.
function Compat.GuildRealmKey(guildRealm)
    if Compat.IS_FOREVER or not guildRealm or guildRealm == "" then return nil end
    return (strgsub(guildRealm, "[%s%-']", ""))
end

-------------------------------------------------------------------------------
--  Names
--  A Forever character carries a surname, which UnitName returns as its
--  second value (retail: the realm). Its first name alone is not unique, so
--  the stored name is "First Last", joined like Blizzard's frames and
--  EllesmereUI's gold ledger do (EllesmereUI.WithSurname).
-------------------------------------------------------------------------------
-- The current character's full name, whatever the show-surname preference.
function Compat.PlayerFullName()
    if not Compat.IS_FOREVER then return UnitName("player") end
    local name, surname = (UnitNameUnmodified or UnitName)("player")
    if type(EUI.WithSurname) == "function" then return EUI.WithSurname(name, surname, true) end
    return name
end

-------------------------------------------------------------------------------
--  Containers
-------------------------------------------------------------------------------
-- Forever's keyring (Enum.BagIndex.Keyring): a bag of its own next to the
-- backpack, only on clients that show it.
function Compat.HasKeyring()
    return C_ActionBar ~= nil and type(C_ActionBar.ShouldShowKeyring) == "function"
        and C_ActionBar.ShouldShowKeyring() == true
end

-------------------------------------------------------------------------------
--  Ammo slot (Forever): a stack of arrows or bullets worn in INVSLOT_AMMO,
--  outside the range ns collects as worn gear.
--  -> itemID, count, link or nil
-------------------------------------------------------------------------------
function Compat.AmmoStack()
    if type(UnitUsesAmmo) ~= "function" then return nil end
    local id = GetInventoryItemID("player", INVSLOT_AMMO)
    if not id or ns.IsSecret(id) then return nil end
    local count = GetInventoryItemCount("player", INVSLOT_AMMO)
    if not count or ns.IsSecret(count) or count <= 0 then return nil end
    return id, count, GetInventoryItemLink("player", INVSLOT_AMMO)
end

-------------------------------------------------------------------------------
--  Mail links. Neither client's Blizzard code reads them, so no client
--  source proves them; without one a stack is stored by item ID only.
-------------------------------------------------------------------------------
function Compat.InboxItemLink(index, attachment)
    if type(GetInboxItemLink) ~= "function" then return nil end
    return GetInboxItemLink(index, attachment)
end

function Compat.SendMailItemLink(index)
    if type(GetSendMailItemLink) ~= "function" then return nil end
    return GetSendMailItemLink(index)
end
