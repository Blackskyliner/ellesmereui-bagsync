-------------------------------------------------------------------------------
--  Core/Init.lua
--  Namespace, event dispatcher and the feature registry.
--
--  Every piece of work this addon does lives in a "feature". A feature owns its
--  event registrations and builds nothing until it is enabled (acceptance
--  criterion 1: zero cost unless enabled). Features are (re)evaluated at login
--  and after every settings change via ns.RefreshFeatures().
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

ns.ADDON_NAME = ADDON_NAME
ns.VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version")) or "dev"

local pairs, type, select, pcall = pairs, type, select, pcall

-------------------------------------------------------------------------------
--  Error-isolated calls: one failing handler must never stop the others.
--  securecallfunction reports through the active error handler (BugSack etc.)
--  and keeps the caller running; pcall + geterrorhandler is the same contract.
-------------------------------------------------------------------------------
local function SafeCall(fn, ...)
    if securecallfunction then
        return securecallfunction(fn, ...)
    end
    local ok, err = pcall(fn, ...)
    if not ok then
        local handler = geterrorhandler and geterrorhandler()
        if handler then handler(err) end
    end
end
ns.SafeCall = SafeCall

-------------------------------------------------------------------------------
--  Secret values (Midnight): comparing or doing arithmetic on one throws.
-------------------------------------------------------------------------------
local issecretvalue = issecretvalue
function ns.IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end

-------------------------------------------------------------------------------
--  Event dispatcher. One frame; handlers keyed event -> owner -> fn.
--  Tables are copy-on-write so (un)registering from inside a handler never
--  disturbs the iteration in progress.
-------------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local handlers = {}

local function CopyWithout(tbl, skipKey)
    local copy = {}
    if tbl then
        for k, v in pairs(tbl) do
            if k ~= skipKey then copy[k] = v end
        end
    end
    return copy
end

function ns.RegisterEvent(owner, event, fn)
    local list = CopyWithout(handlers[event], nil)
    local wasEmpty = next(list) == nil
    list[owner] = fn
    handlers[event] = list
    if wasEmpty then eventFrame:RegisterEvent(event) end
end

function ns.UnregisterEvent(owner, event)
    local list = handlers[event]
    if not list or list[owner] == nil then return end
    list = CopyWithout(list, owner)
    if next(list) == nil then
        handlers[event] = nil
        eventFrame:UnregisterEvent(event)
    else
        handlers[event] = list
    end
end

function ns.UnregisterAllEvents(owner)
    local events = {}
    for event, list in pairs(handlers) do
        if list[owner] ~= nil then events[#events + 1] = event end
    end
    for i = 1, #events do ns.UnregisterEvent(owner, events[i]) end
end

function ns.IsEventRegistered(owner, event)
    local list = handlers[event]
    return list ~= nil and list[owner] ~= nil
end

-- Test/diagnostic helper: the events this addon currently listens to.
function ns.GetRegisteredEvents()
    local out = {}
    for event in pairs(handlers) do out[#out + 1] = event end
    table.sort(out)
    return out
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for owner, fn in pairs(list) do
        SafeCall(fn, owner, event, ...)
    end
end)

-------------------------------------------------------------------------------
--  Feature registry
--  def = {
--      key       = "bags",
--      IsEnabled = function(settings) return bool end,
--      OnEnable  = function(self) end,   -- register events, build lazily
--      OnDisable = function(self) end,   -- optional; events are dropped anyway
--  }
-------------------------------------------------------------------------------
ns.features = {}
ns.featureByKey = {}

function ns.RegisterFeature(def)
    assert(type(def) == "table" and type(def.key) == "string", "feature needs a key")
    assert(not ns.featureByKey[def.key], "duplicate feature " .. def.key)
    def.active = false
    ns.features[#ns.features + 1] = def
    ns.featureByKey[def.key] = def
    return def
end

local function SetFeatureActive(def, active)
    if def.active == active then return end
    def.active = active
    if active then
        if def.OnEnable then SafeCall(def.OnEnable, def) end
    else
        ns.UnregisterAllEvents(def)
        if def.OnDisable then SafeCall(def.OnDisable, def) end
    end
end

-- Enables/disables every feature to match the settings. Safe to call often.
function ns.RefreshFeatures()
    if not ns.ready then return end
    local settings = ns.db and ns.db.settings
    for i = 1, #ns.features do
        local def = ns.features[i]
        local want = settings ~= nil and def.IsEnabled ~= nil and def.IsEnabled(settings) == true
        SetFeatureActive(def, want)
    end
end

function ns.IsFeatureActive(key)
    local def = ns.featureByKey[key]
    return def ~= nil and def.active == true
end

-- Test hook: drop everything back to the disabled state.
function ns.DisableAllFeatures()
    for i = 1, #ns.features do SetFeatureActive(ns.features[i], false) end
end

-------------------------------------------------------------------------------
--  Messaging between modules (plain callbacks, no frames involved)
-------------------------------------------------------------------------------
local listeners = {}

function ns.On(message, owner, fn)
    local list = listeners[message]
    if not list then list = {}; listeners[message] = list end
    list[owner] = fn
end

function ns.Off(message, owner)
    local list = listeners[message]
    if list then list[owner] = nil end
end

function ns.Fire(message, ...)
    local list = listeners[message]
    if not list then return end
    for owner, fn in pairs(list) do
        SafeCall(fn, owner, ...)
    end
end

-------------------------------------------------------------------------------
--  Output
-------------------------------------------------------------------------------
local PREFIX = "|cff0cd29fEUI Alts|r: "
function ns.Print(fmt, ...)
    local msg = select("#", ...) > 0 and fmt:format(...) or fmt
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg)
    end
end
