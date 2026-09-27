-- luacheck config: WoW runs Lua 5.1. Every global the addon reads is listed
-- here on purpose; scripts/check-api.py verifies each one exists in the
-- Blizzard 12.x client sources / API annotations.
std = "lua51"
max_line_length = false
codes = true
exclude_files = { ".tools/**", "spec/fixtures/**" }
ignore = {
    "212/self",   -- unused self in methods
    "212/_.*",    -- unused args prefixed with _
}

files["EllesmereUIBags_Alts/**/*.lua"] = {
    globals = {
        "EllesmereUIBagsAltsDB", "EllesmereUIBagsExt", "EllesmereUIBagsAlts",
        "SLASH_EUIALTS1", "SLASH_EUIALTS2", "SlashCmdList",
    },
    read_globals = {
        -- Lua/WoW stdlib extensions
        "wipe", "tinsert", "time", "date", "strsplit", "Mixin", "CreateFromMixins", "next",
        "securecallfunction", "geterrorhandler", "issecretvalue", "hooksecurefunc",
        -- Frames / UI
        "CreateFrame", "UIParent", "GameTooltip", "ItemRefTooltip", 
        "BattlePetTooltip", "BattlePetToolTip_ShowLink", "UISpecialFrames", "DEFAULT_CHAT_FRAME",
        "STANDARD_TEXT_FONT", "GameFontHighlight", "BackdropTemplateMixin", 
        "SetItemButtonTexture", "SetItemButtonCount", "SetItemButtonQuality",
        "HandleModifiedItemClick", "IsModifiedClick", "IsShiftKeyDown", "IsControlKeyDown", "IsAltKeyDown",
        "BreakUpLargeNumbers", "ITEM_QUALITY_COLORS", "OKAY", "CANCEL",
        "Settings", "CreateSettingsListSectionHeaderInitializer", "CreateSettingsButtonInitializer",
        "TooltipDataProcessor", "Enum", "GetLocale",
        -- Namespaced APIs
        "C_AddOns", "C_Container", "C_PlayerInteractionManager", "C_Bank", "C_Item", "C_AuctionHouse", "C_EquipmentSet",
        "ItemLocation", "EquipmentManager_GetLocationData", "ITEM_SOULBOUND", "ITEM_ACCOUNTBOUND", "C_CurrencyInfo", "C_AutoComplete", "C_ClassColor",
        -- Character / world
        "UnitName", "UnitClass", "UnitRace", "UnitFactionGroup", "UnitLevel", "GetRealmName",
        "GetNormalizedRealmName", "GetMoney", "IsInGuild", "GetGuildInfo",
        "GetInventoryItemLink", "GetInventoryItemID", "INVSLOT_FIRST_EQUIPPED", "INVSLOT_LAST_EQUIPPED",
        -- Mail
        "GetInboxNumItems", "GetInboxHeaderInfo", "GetInboxItem", "GetInboxItemLink",
        "GetSendMailItem", "GetSendMailItemLink", "ATTACHMENTS_MAX_RECEIVE", "ATTACHMENTS_MAX_SEND",
        -- Guild bank
        "GetNumGuildBankTabs", "GetGuildBankTabInfo", "GetGuildBankItemInfo", "GetGuildBankItemLink",
        "QueryGuildBankTab", "GetCurrentGuildBankTab", "GetGuildBankMoney",
        -- EllesmereUI (optional host; only touched through feature detection)
        "EllesmereUI", "EllesmereUIDB", "EUI_Bags", "EUI_CategoryManager", "EUI_CLIENT_BLOCKED",
    },
}

files["spec/**/*.lua"] = { std = "+busted", globals = { "_G" }, allow_defined_top = true, ignore = { "111", "112", "113", "122", "142", "143", "631" } }
files["sim/**/*.lua"] = { allow_defined_top = true, ignore = { "111", "112", "113", "122", "631" } }
-- Proposed drop-in for EllesmereUIBags: extends EUI's own global bag frame.
files["upstream/**/*.lua"] = {
    globals = { "EUI_Bags" },
    read_globals = { "EllesmereUI", "EUI_CLIENT_BLOCKED", "CreateFrame" },
}
