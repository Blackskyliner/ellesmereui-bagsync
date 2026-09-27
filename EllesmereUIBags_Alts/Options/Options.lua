-------------------------------------------------------------------------------
--  Options/Options.lua
--  Settings page (Blizzard Settings API; EUI has no public options API for
--  third-party addons), slash commands and the one-time opt-in prompt.
-------------------------------------------------------------------------------
local _, ns = ...
local L = ns.L
local Ext = _G.EllesmereUIBagsExt

local Options = {}
ns.Options = Options

-- Applies a settings change: re-evaluates features, drops caches.
function ns.SettingsChanged()
    ns.Fire("SETTINGS_CHANGED")
    ns.RefreshFeatures()
    if ns.Browser and ns.Browser:IsShown() then ns.Browser:RequestRefresh() end
end

local function Proxy(category, variable, path, name, varType)
    local group, field = path[1], path[2]
    local defaults = ns.DEFAULTS.settings[group]
    local function get() return ns.db.settings[group][field] end
    local function set(value)
        ns.db.settings[group][field] = value
        ns.SettingsChanged()
    end
    return Settings.RegisterProxySetting(category, "EUIALTS_" .. variable, varType, name, defaults[field], get, set)
end

local function Checkbox(category, variable, path, name, tooltip)
    local setting = Proxy(category, variable, path, name, Settings.VarType.Boolean)
    Settings.CreateCheckbox(category, setting, tooltip)
    return setting
end

local function Dropdown(category, variable, path, name, tooltip, choices)
    local setting = Proxy(category, variable, path, name, Settings.VarType.String)
    local function GetOptions()
        local container = Settings.CreateControlTextContainer()
        for _, choice in ipairs(choices) do container:Add(choice[1], choice[2]) end
        return container:GetData()
    end
    Settings.CreateDropdown(category, setting, GetOptions, tooltip)
    return setting
end

function Options:Register()
    if self.category then return end
    local category, layout = Settings.RegisterVerticalLayoutCategory(L["EllesmereUI Bags: Alts"])
    self.category = category

    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(L["Tooltip"]))
    Checkbox(category, "tooltip_enabled", { "tooltip", "enabled" }, L["Show item counts of all characters in tooltips"],
        L["Adds a line per character (and warband/guild bank) that owns the item."])
    Dropdown(category, "tooltip_modifier", { "tooltip", "modifier" }, L["Show counts"], nil, {
        { "none", L["Always"] }, { "shift", L["While Shift is held"] },
        { "ctrl", L["While Ctrl is held"] }, { "alt", L["While Alt is held"] },
    })
    Dropdown(category, "tooltip_realmScope", { "tooltip", "realmScope" }, L["Characters"], nil, {
        { "connected", L["Connected realms"] }, { "realm", L["This realm only"] }, { "all", L["All realms"] },
    })
    Checkbox(category, "tooltip_showTotal", { "tooltip", "showTotal" }, L["Show total"])
    Checkbox(category, "tooltip_hideCurrent", { "tooltip", "hideCurrent" }, L["Hide the current character"])
    Checkbox(category, "tooltip_showWarband", { "tooltip", "showWarband" }, L["Include the warband bank"])
    Checkbox(category, "tooltip_showGuild", { "tooltip", "showGuild" }, L["Include guild banks"])

    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(L["EllesmereUI integration"]))
    Checkbox(category, "ui_headerButton", { "ui", "headerButton" }, L["Button in the EllesmereUI bag header"],
        L["Adds a small button next to the item count that opens the browser."])
    Checkbox(category, "ui_useEUICategories", { "ui", "useEUICategories" }, L["Group browser items by EllesmereUI categories"])

    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(L["Data collection"]))
    Checkbox(category, "collect_bags", { "collect", "bags" }, L["Bags"])
    Checkbox(category, "collect_equipped", { "collect", "equipped" }, L["Equipped gear"])
    Checkbox(category, "collect_bank", { "collect", "bank" }, L["Bank and warband bank"])
    Checkbox(category, "collect_mail", { "collect", "mail" }, L["Mail"])
    Checkbox(category, "collect_currency", { "collect", "currency" }, L["Currencies"])
    Checkbox(category, "collect_guildbank", { "collect", "guildbank" }, L["Guild bank"],
        L["Scans the guild bank tabs you can view while the guild bank is open."])
    Checkbox(category, "collect_auctions", { "collect", "auctions" }, L["Own auctions"],
        L["Stores your active auctions whenever the auction house shows them (Auctions tab)."])
    Checkbox(category, "collect_auctionsQuery", { "collect", "auctionsQuery" }, L["Request own auctions when the auction house opens"],
        L["Sends one owned-auctions request when you open the auction house, so the Auctions tab does not need to be opened."])

    -- The Settings panel is left alone (no HideUIPanel from addon code: taint
    -- path); the browser opens above it at DIALOG strata.
    layout:AddInitializer(CreateSettingsButtonInitializer(L["Browser"], L["Open"], function()
        ns.Browser:Open()
        ns.Browser:RaiseAboveSettings()
    end, L["Opens the cross-character browser (/alts)."], true))

    Settings.RegisterAddOnCategory(category)
end

function Options:Open()
    if self.category then Settings.OpenToCategory(self.category:GetID()) end
end

-------------------------------------------------------------------------------
--  First run: ask before anything visible is turned on (criterion 2).
--  With EllesmereUI the question waits for the first bag open: at login EUI
--  shows its own popups and ShowConfirmPopup is one shared dialog.
-------------------------------------------------------------------------------
local firstRunHookPending = false

local function AskFirstRun()
    local s = ns.db.settings
    if s.firstRunAsked then return end
    s.firstRunAsked = true
    Ext:Confirm({
        title = L["EllesmereUI Bags: Alts"],
        message = L["Show item counts of your other characters in tooltips and add a browser button to the EllesmereUI bag header? You can change this any time in the options or with /alts."],
        confirmText = L["Enable"],
        cancelText = L["Not now"],
        onConfirm = function()
            s.tooltip.enabled = true
            if Ext:IsBagsLoaded() then s.ui.headerButton = true end
            ns.SettingsChanged()
        end,
    })
end
Options.AskFirstRun = AskFirstRun

function Options:MaybeAskFirstRun()
    if ns.db.settings.firstRunAsked then return end
    ns.Print(L["Tracking your characters' items. Type /alts to browse, /alts options for tooltip counts."])
    if Ext:IsBagsLoaded() then
        if not firstRunHookPending then
            firstRunHookPending = true
            EUI_Bags:HookScript("OnShow", function()
                if firstRunHookPending then
                    firstRunHookPending = false
                    AskFirstRun()
                end
            end)
        end
    else
        AskFirstRun()
    end
end

-------------------------------------------------------------------------------
--  Slash commands
-------------------------------------------------------------------------------
local function PrintStatus()
    local count = 0
    for _ in pairs(ns.db.chars) do count = count + 1 end
    ns.Print("%s %s - %d %s", L["version"], ns.VERSION, count, L["characters stored"])
    local active = {}
    for _, def in ipairs(ns.features) do
        if def.active then active[#active + 1] = def.key end
    end
    ns.Print("%s: %s", L["active features"], table.concat(active, ", "))
    ns.Print("%s: %s", L["events"], table.concat(ns.GetRegisteredEvents(), ", "))
end

local function Usage()
    ns.Print("/alts - " .. L["toggle the browser"])
    ns.Print("/alts search <text> - " .. L["search all characters"])
    ns.Print("/alts options - " .. L["open the options"])
    ns.Print("/alts tooltip - " .. L["toggle tooltip counts"])
    ns.Print("/alts selftest - " .. L["check this character's stored data against the game"])
    ns.Print("/alts status - " .. L["show status"])
    ns.Print("/alts delete <Name-Realm> - " .. L["delete a character's data"])
end

function Options:HandleSlash(msg)
    msg = msg or ""
    local cmd, rest = msg:match("^%s*(%S*)%s*(.-)%s*$")
    cmd = (cmd or ""):lower()
    if cmd == "" then
        ns.Browser:Toggle()
    elseif cmd == "search" or cmd == "s" then
        ns.Browser:OpenSearch(rest)
    elseif cmd == "options" or cmd == "config" then
        self:Open()
    elseif cmd == "tooltip" then
        local t = ns.db.settings.tooltip
        t.enabled = not t.enabled
        ns.SettingsChanged()
        ns.Print("%s: %s", L["Tooltip"], t.enabled and L["on"] or L["off"])
    elseif cmd == "selftest" then
        ns.RunSelfTest(true)
    elseif cmd == "status" then
        PrintStatus()
    elseif cmd == "delete" then
        local key = ns.FindKnownCharacter(ns.db.chars, ns.NormalizeCharacterName(rest))
        if not key then
            ns.Print(L["Unknown character: %s"], rest)
        elseif key == ns.GetPlayerKey() then
            ns.Print(L["The current character cannot be deleted."])
        else
            Ext:Confirm({
                title = L["Delete data"],
                message = string.format(L["Delete all stored data of %s?"], key),
                confirmText = L["Delete"],
                cancelText = CANCEL or "Cancel",
                onConfirm = function() ns.DeleteChar(key) end,
            })
        end
    else
        Usage()
    end
end

function Options:RegisterSlash()
    SLASH_EUIALTS1 = "/alts"
    SLASH_EUIALTS2 = "/euialts"
    SlashCmdList["EUIALTS"] = function(msg) Options:HandleSlash(msg) end
end
