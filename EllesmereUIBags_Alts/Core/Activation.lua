-------------------------------------------------------------------------------
--  Core/Activation.lua
--  Nothing is scanned or registered at login. The addon activates on its
--  first use in a session and only then starts the collectors (one scan of
--  the current character, afterwards event driven). Until then the only
--  things installed are the activation triggers themselves:
--    * opening the bags: an OnShow hook on EllesmereUI's bag window. EUI
--      Bags is a requirement of this companion and routes every bag key and
--      bag button there. Nothing hooks Blizzard's bag frames or functions:
--      insecure code inside their Show() would put the item buttons Blizzard
--      creates afterwards on a tainted path (blocked item use in combat).
--    * one event, PLAYER_INTERACTION_MANAGER_FRAME_SHOW, for the windows
--      whose data is only readable while they are open (bank, mailbox,
--      auction house, guild bank); the collectors check on start whether
--      their window is open, so the visit that activated is not lost
--    * direct calls: opening the browser, the public API, the self-test and,
--      when the tooltip option is on, the first item tooltip
--  Activate() runs once per session; the trigger event is dropped after it
--  and the hooks (which cannot be removed) return at their first line.
-------------------------------------------------------------------------------
local _, ns = ...

local armed = false
local trigger = {}   -- event owner of the activation trigger

local PIT = Enum.PlayerInteractionType
local NPC_TRIGGERS = {
    [PIT.Banker] = "bank",
    [PIT.CharacterBanker or -1] = "bank",
    [PIT.AccountBanker or -1] = "bank",
    [PIT.MailInfo] = "mail",
    [PIT.Auctioneer] = "auctions",
    [PIT.GuildBanker] = "guildbank",
}

function ns.IsActivated() return ns.activated == true end

-- -> true when this call activated the addon
function ns.Activate(reason)
    if ns.activated or not ns.ready then return false end
    ns.activated = true            -- first: re-entrant calls from the scans return
    ns.activatedBy = reason
    ns.UnregisterEvent(trigger, "PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
    ns.Debug("activation", "activated by %s", tostring(reason))
    ns.SafeCall(ns.SanitizeData)
    ns.RefreshFeatures()
    ns.Fire("ACTIVATED", reason)
    return true
end

local function OnBagsOpened()
    if not ns.activated then ns.Activate("bags") end
end

-- Called once at PLAYER_LOGIN.
function ns.ArmActivation()
    if armed or ns.activated then return end
    armed = true
    -- EllesmereUI's bag window is an addon frame: hooking it taints nothing of Blizzard's.
    if _G.EllesmereUIBagsExt:IsBagsLoaded() then _G.EUI_Bags:HookScript("OnShow", OnBagsOpened) end
    ns.RegisterEvent(trigger, "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(_, _, interaction)
        local reason = NPC_TRIGGERS[interaction]
        if reason then ns.Activate(reason) end
    end)
end

-- For collectors of NPC windows: is that window open right now?
function ns.IsInteracting(interaction)
    return C_PlayerInteractionManager ~= nil
        and C_PlayerInteractionManager.IsInteractingWithNpcOfType(interaction) == true
end
