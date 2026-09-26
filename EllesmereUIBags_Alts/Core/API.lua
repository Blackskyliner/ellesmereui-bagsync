-------------------------------------------------------------------------------
--  Core/API.lua
--  Public, read-mostly API for other addons, macros and tests:
--
--    EllesmereUIBagsAlts.GetItemCount(itemID)  -> total, { [owner] = { [location] = n } }
--        owner: "Name-Realm", "#warband" or "@Guild-Realm";
--        location: bags, bank, equipped, mail, warband, guild. Copy, safe to keep.
--    EllesmereUIBagsAlts.GetCharacters()        -> sorted { "Name-Realm", ... }
--    EllesmereUIBagsAlts.GetCharacterInfo(key)  -> { name, realm, class, level, money, lastSeen } or nil
--    EllesmereUIBagsAlts.ToggleBrowser() / OpenBrowser([owner]) / Search(text)
--    EllesmereUIBagsAlts.RunSelfTest()          -> ok, report
--
--  EllesmereUIBagsAlts._ns is the private namespace, exposed for diagnostics and
--  the simulator tests only: no stability guarantee.
-------------------------------------------------------------------------------
local _, ns = ...

local API = {}

API.VERSION = ns.VERSION

function API.GetItemCount(itemID)
    if type(itemID) ~= "number" or not ns.db then return 0, {} end
    local byOwner = ns.Index:Get(itemID)
    local copy = {}
    if byOwner then
        for owner, byLoc in pairs(byOwner) do
            local c = {}
            for loc, n in pairs(byLoc) do c[loc] = n end
            copy[owner] = c
        end
    end
    return ns.Index:GetTotal(itemID), copy
end

function API.GetCharacters()
    return ns.GetSortedCharKeys()
end

function API.GetCharacterInfo(key)
    local c = ns.db and ns.db.chars[key]
    if not c then return nil end
    return { name = c.name, realm = c.realm, class = c.class, level = c.level, money = c.money, lastSeen = c.lastSeen }
end

function API.ToggleBrowser() ns.Browser:Toggle() end
function API.OpenBrowser(owner) ns.Browser:Open(owner) end
function API.Search(text) ns.Browser:OpenSearch(text) end
function API.RunSelfTest() return ns.RunSelfTest(false) end

API._ns = ns

_G.EllesmereUIBagsAlts = API
