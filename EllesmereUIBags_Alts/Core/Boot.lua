-------------------------------------------------------------------------------
--  Core/Boot.lua
--  ADDON_LOADED  -> saved variables are available: init the DB
--  PLAYER_LOGIN  -> identity is known: enable features, register options
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local boot = {}

ns.RegisterEvent(boot, "ADDON_LOADED", function(_, _, name)
    if name ~= ADDON_NAME then return end
    ns.UnregisterEvent(boot, "ADDON_LOADED")
    ns.InitDB()
end)

ns.RegisterEvent(boot, "PLAYER_LOGIN", function()
    ns.UnregisterEvent(boot, "PLAYER_LOGIN")
    if not ns.db then ns.InitDB() end
    ns.ready = true
    -- Each step isolated: a failure in one (e.g. the Settings UI) must not
    -- keep the collectors from starting.
    ns.SafeCall(ns.RefreshFeatures)
    ns.SafeCall(ns.Options.RegisterSlash, ns.Options)
    ns.SafeCall(ns.Options.Register, ns.Options)
    ns.SafeCall(ns.Options.MaybeAskFirstRun, ns.Options)
end)
