-- Translations: every locale of the EllesmereUI repo, checked for coverage,
-- stale keys, placeholder parity, valid UTF-8 and that only the client's
-- locale builds entries.
local wow = require("wow")

local LOCALES = { "deDE", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW" }

-- Keys that may legitimately stay English (product names, loan words).
local MAY_STAY_ENGLISH = {
    ["Alts"] = true, ["EllesmereUI Bags: Alts"] = true, ["Account"] = true, ["Bank"] = true,
    ["Browser"] = true, ["Gold"] = true, ["Tooltip"] = true, ["Total"] = true, ["version"] = true,
}

-- Keys reached through lookup tables instead of literal L["..."] in the code.
local INDIRECT_KEYS = { "Backpack", "Bag 1", "Bag 2", "Bag 3", "Bag 4", "Reagent Bag", "Currency",
    "Bags", "Bank", "Equipped", "Mail", "Auctions", "Warband Bank", "Guild Bank",
    "Character-bound", "Transferable", "Warband-wide (shared)", "Soulbound", "Warbound", "Everything" }

local function readAll(path)
    local fh = assert(io.open(path, "rb"))
    local s = fh:read("*a")
    fh:close()
    return s
end

local function usedKeys()
    local keys = {}
    local p = io.popen('find "' .. wow.ROOT .. '/EllesmereUIBags_Alts" -name "*.lua" -not -path "*/Locales/*"')
    for path in p:lines() do
        for k in readAll(path):gmatch('L%["(.-)"%]') do keys[k] = true end
    end
    p:close()
    for _, k in ipairs(INDIRECT_KEYS) do keys[k] = true end
    return keys
end

local function placeholders(s)
    local out = {}
    for ph in s:gmatch("%%%d*%$?[ds]") do out[#out + 1] = ph end
    return table.concat(out, " ")
end

local function validUTF8(s)
    local i, n = 1, #s
    while i <= n do
        local c = s:byte(i)
        local len = c < 0x80 and 1 or (c >= 0xC2 and c <= 0xDF) and 2 or (c >= 0xE0 and c <= 0xEF) and 3
            or (c >= 0xF0 and c <= 0xF4) and 4 or nil
        if not len then return false end
        for j = i + 1, i + len - 1 do
            local cc = s:byte(j)
            if not cc or cc < 0x80 or cc > 0xBF then return false end
        end
        i = i + len
    end
    return true
end

local function loadLocale(code)
    local env, ns = wow.boot(wow.defaultState({ locale = code }))
    return env, ns
end

describe("Locales", function()
    local keys = usedKeys()

    it("the TOC lists every locale of the EllesmereUI repo", function()
        local toc = readAll(wow.ROOT .. "/EllesmereUIBags_Alts/EllesmereUIBags_Alts.toc")
        for _, code in ipairs(LOCALES) do
            assert.truthy(toc:find("Locales\\" .. code .. ".lua", 1, true), code)
        end
    end)

    for _, code in ipairs(LOCALES) do
        describe(code, function()
            local path = wow.ROOT .. "/EllesmereUIBags_Alts/Locales/" .. code .. ".lua"
            local text = readAll(path)

            it("is UTF-8 without BOM and guards on its locale", function()
                assert.are_not.equal("\239\187\191", text:sub(1, 3))
                assert.is_true(validUTF8(text))
                assert.truthy(text:find('if GetLocale() ~= "' .. code .. '" then return end', 1, true))
            end)

            it("translates every used key and contains no stale keys", function()
                local _, ns = loadLocale(code)
                local defined = {}
                for k in text:gmatch('\nL%["(.-)"%] = ') do defined[k] = true end
                for k in pairs(defined) do assert.is_true(keys[k] == true, "stale key: " .. k) end
                for k in pairs(keys) do
                    if not MAY_STAY_ENGLISH[k] then
                        assert.are_not.equal(k, ns.L[k], "untranslated: " .. k)
                    end
                end
            end)

            it("keeps placeholders and formats without errors", function()
                local _, ns = loadLocale(code)
                for k in pairs(keys) do
                    local v = ns.L[k]
                    assert.are.equal(placeholders(k), placeholders(v), code .. ": " .. k)
                    local args = {}
                    for ph in k:gmatch("%%[ds]") do args[#args + 1] = ph == "%d" and 3 or "Bob-Realm" end
                    assert.has_no.errors(function() string.format(v, unpack(args)) end, k)
                end
            end)

            it("boots, renders the browser and tooltip in this language", function()
                local s = wow.defaultState({ locale = code })
                wow.putItem(s, 0, 1, 2589, 20)
                local env, ns = wow.boot(s)
                ns.db.settings.tooltip.enabled = true
                ns.SettingsChanged()
                ns.Browser:Open()
                env.GameTooltip:SetOwner(env.UIParent)
                env.GameTooltip:SetHyperlink("item:2589")
                env.Slash("status")
                assert.are.same({}, env.__errors)
                local f = env.EllesmereUIBagsAltsBrowser
                assert.are.equal(ns.L["Backpack"], f.grid.headers[1].text)
            end)
        end)
    end

    it("an English client builds no translation", function()
        local _, ns = loadLocale("enUS")
        assert.are.equal("Warband Bank", ns.L["Warband Bank"])
        assert.are.equal(0, (function() local n = 0 for _ in pairs(ns.L) do n = n + 1 end return n end)())
    end)
end)
