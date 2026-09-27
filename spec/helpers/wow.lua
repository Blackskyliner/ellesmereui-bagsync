--------------------------------------------------------------------------------
--  spec/helpers/wow.lua
--  A deterministic WoW client stand-in for busted.
--
--  * Loads the addon exactly like the client: TOC order, one shared addon
--    namespace, chunk(...) = (addonName, ns), each file in a private global
--    environment (so tests never leak globals into each other).
--  * Frames with scripts, hooks, event registration and a global event bus.
--  * A scriptable game state (player, bags, bank tabs, warband, mail, guild
--    bank, currencies, equipment, combat/secret mode) behind the real API
--    names and return shapes (verified against Blizzard's 12.1 API docs).
--  * SavedVariables survive "relogs": wow.relog(env, newPlayer) serializes the
--    SV like the client and boots a fresh environment for another character.
--
--  Frame methods not modelled explicitly are permissive no-ops; the headless
--  simulator test (sim/) covers method existence against the real FrameXML.
--------------------------------------------------------------------------------
local M = {}

-- Real widget method names (generated from Blizzard's API docs).
local WIDGET_METHODS = dofile((debug.getinfo(1, "S").source:match("^@(.*)/helpers/wow%.lua$") or "spec") .. "/fixtures/widget_methods.lua")
M.WIDGET_METHODS = WIDGET_METHODS

local ROOT = (debug.getinfo(1, "S").source:match("^@(.*)/spec/helpers/wow%.lua$")) or "."
M.ROOT = ROOT
local ADDON = "EllesmereUIBags_Alts"
M.ADDON = ADDON

local function shallowCopy(t)
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    return out
end

local function deepCopy(v, seen)
    if type(v) ~= "table" then return v end
    seen = seen or {}
    if seen[v] then return seen[v] end
    local out = {}
    seen[v] = out
    for k, x in pairs(v) do out[deepCopy(k, seen)] = deepCopy(x, seen) end
    return out
end
M.deepCopy = deepCopy

--------------------------------------------------------------------------------
--  Secret values: opaque boxes the addon must never compare or compute with.
--------------------------------------------------------------------------------
local SecretMT = {
    __eq = function() error("attempt to compare a secret value", 2) end,
    __lt = function() error("attempt to compare a secret value", 2) end,
    __le = function() error("attempt to compare a secret value", 2) end,
    __add = function() error("attempt to perform arithmetic on a secret value", 2) end,
    __sub = function() error("attempt to perform arithmetic on a secret value", 2) end,
    __concat = function() error("attempt to concatenate a secret value", 2) end,
    __tostring = function() return "<secret>" end,
}
local function Secret(v) return setmetatable({ value = v }, SecretMT) end

--------------------------------------------------------------------------------
--  Item database used by the mock client (itemID -> info)
--------------------------------------------------------------------------------
M.ITEMS = {
    [6948]   = { name = "Hearthstone", quality = 1, icon = 134414, type = "Miscellaneous", subtype = "Junk", equipLoc = "", bindType = 1 },
    [2589]   = { name = "Linen Cloth", quality = 1, icon = 132889, type = "Tradeskill", subtype = "Cloth", equipLoc = "" },
    [2592]   = { name = "Wool Cloth", quality = 1, icon = 132911, type = "Tradeskill", subtype = "Cloth", equipLoc = "" },
    [190396] = { name = "Serevite Ore", quality = 1, icon = 4555563, type = "Tradeskill", subtype = "Metal & Stone", equipLoc = "" },
    [212345] = { name = "Algari Mana Potion", quality = 1, icon = 5931169, type = "Consumable", subtype = "Potion", equipLoc = "" },
    [19019]  = { name = "Thunderfury, Blessed Blade of the Windseeker", quality = 5, icon = 135349, type = "Weapon", subtype = "One-Handed Swords", equipLoc = "INVTYPE_WEAPON", bindType = 1 },
    [230000] = { name = "Void-Touched Helm", quality = 4, icon = 5925000, type = "Armor", subtype = "Plate", equipLoc = "INVTYPE_HEAD", bindType = 2 },
    [231000] = { name = "Warbound Cloak", quality = 4, icon = 5925001, type = "Armor", subtype = "Cloth", equipLoc = "INVTYPE_CLOAK", bindType = 9 },
    [232000] = { name = "Heirloom Staff", quality = 7, icon = 5925002, type = "Weapon", subtype = "Staves", equipLoc = "INVTYPE_2HWEAPON", bindType = 8 },
    [82800]  = { name = "Pet Cage", quality = 1, icon = 132599, type = "Miscellaneous", subtype = "Companion Pets", equipLoc = "" },
    [180653] = { name = "Mythic Keystone", quality = 4, icon = 4352494, type = "Reagent", subtype = "Keystone", equipLoc = "" },
}

-- Item class IDs / names (Enum.ItemClass, C_Item.GetItemClassInfo).
M.CLASS_IDS = { Consumable = 0, Weapon = 2, Armor = 4, Reagent = 5, Tradeskill = 7, Miscellaneous = 15 }
M.CLASS_NAMES = { [0] = "Consumable", [2] = "Weapon", [4] = "Armor", [5] = "Reagent", [7] = "Tradeskill",
                  [15] = "Miscellaneous" }

-- OwnedAuctionInfo as returned by C_AuctionHouse.GetOwnedAuctions (12.1 docs).
function M.ownedAuction(auctionID, itemID, quantity, opts)
    opts = opts or {}
    return {
        auctionID = auctionID,
        itemKey = { itemID = itemID, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = opts.species or 0 },
        itemLink = opts.link,
        status = opts.sold and 1 or 0,
        quantity = quantity or 1,
        timeLeftSeconds = opts.seconds,
        timeLeft = opts.band,
        buyoutAmount = opts.buyout or 10000,
    }
end

function M.itemLocation(bagID, slotIndex) return { bagID = bagID, slotIndex = slotIndex } end

function M.itemLink(id, itemString)
    local info = M.ITEMS[id] or { name = "Item " .. id, quality = 1 }
    local colors = { [0] = "ff9d9d9d", "ffffffff", "ff1eff00", "ff0070dd", "ffa335ee", "ffff8000", "ffe6cc80", "ff00ccff" }
    itemString = itemString or ("item:" .. id .. "::::::::80:::::")
    return string.format("|c%s|H%s|h[%s]|h|r", colors[info.quality] or "ffffffff", itemString, info.name)
end

--------------------------------------------------------------------------------
--  Enums (values from Blizzard_APIDocumentationGenerated, 12.1.0)
--------------------------------------------------------------------------------
local function Enums()
    return {
        BagIndex = {
            Accountbanktab = -3, Characterbanktab = -2, Keyring = -1, Backpack = 0,
            Bag_1 = 1, Bag_2 = 2, Bag_3 = 3, Bag_4 = 4, ReagentBag = 5,
            CharacterBankTab_1 = 6, CharacterBankTab_2 = 7, CharacterBankTab_3 = 8,
            CharacterBankTab_4 = 9, CharacterBankTab_5 = 10, CharacterBankTab_6 = 11,
            AccountBankTab_1 = 12, AccountBankTab_2 = 13, AccountBankTab_3 = 14,
            AccountBankTab_4 = 15, AccountBankTab_5 = 16,
        },
        BankType = { Character = 0, Guild = 1, Account = 2 },
        PlayerInteractionType = {
            Banker = 8, GuildBanker = 10, MailInfo = 17, Auctioneer = 21,
            CharacterBanker = 67, AccountBanker = 68,
        },
        TooltipDataType = { Item = 0, Currency = 5 },
        ItemClass = { Consumable = 0, Weapon = 2, Armor = 4, Reagent = 5, Tradegoods = 7, Miscellaneous = 15 },
        TooltipDataLineType = { None = 0, ItemName = 22, ItemBinding = 20 },
        ItemBind = { None = 0, OnAcquire = 1, OnEquip = 2, OnUse = 3, Quest = 4, ToWoWAccount = 7,
                     ToBnetAccount = 8, ToBnetAccountUntilEquipped = 9 },
        AuctionStatus = { Active = 0, Sold = 1 },
        AuctionHouseTimeLeftBand = { Short = 0, Medium = 1, Long = 2, VeryLong = 3 },
        AuctionHouseSortOrder = { Price = 0, Name = 1, Level = 2, Bid = 3, Buyout = 4, TimeRemaining = 5 },
        AuctionHouseNotification = { BidPlaced = 0, AuctionRemoved = 1, AuctionWon = 2, AuctionOutbid = 3,
                                     AuctionSold = 4, AuctionExpired = 5 },
    }
end

--------------------------------------------------------------------------------
--  Frames
--------------------------------------------------------------------------------
local function NewRegion(kind, parent)
    local r = { __kind = kind, parent = parent, shown = true, text = "", points = {} }
    return setmetatable(r, { __index = function(_, k)
        local fn = ({
            SetText = function(self, v) self.text = v end,
            GetText = function(self) return self.text end,
            SetTexture = function(self, v) self.texture = v end,
            GetTexture = function(self) return self.texture end,
            SetColorTexture = function(self, cr, cg, cb, ca) self.color = { cr, cg, cb, ca } end,
            SetTextColor = function(self, cr, cg, cb) self.textColor = { cr, cg, cb } end,
            Show = function(self) self.shown = true end,
            Hide = function(self) self.shown = false end,
            SetShown = function(self, v) self.shown = v and true or false end,
            IsShown = function(self) return self.shown end,
            SetFont = function(self, path, size, flags) self.font = { path, size, flags }; return true end,
            GetStringWidth = function(self) return #tostring(self.text or "") * 6 end,
            SetPoint = function(self, ...) self.points[#self.points + 1] = { ... } end,
            ClearAllPoints = function(self) self.points = {} end,
            GetParent = function(self) return self.parent end,
            SetParent = function(self, p) self.parent = p end,
        })[k]
        if fn then return fn end
        if WIDGET_METHODS[k] then return function() end end
        return nil
    end })
end

local FrameMethods = {}

function FrameMethods:GetObjectType() return self.__type end
function FrameMethods:GetName() return self.__name end
function FrameMethods:IsForbidden() return false end
function FrameMethods:SetScript(what, fn)
    self.scripts[what] = fn
    self.hooks[what] = nil
    if what == "OnUpdate" then
        self.env.__onUpdateSets[#self.env.__onUpdateSets + 1] = { frame = self, fn = fn }
    end
end
function FrameMethods:GetScript(what) return self.scripts[what] end
function FrameMethods:HookScript(what, fn)
    self.hooks[what] = self.hooks[what] or {}
    table.insert(self.hooks[what], fn)
end
function FrameMethods:RunScript(what, ...)
    local fn = self.scripts[what]
    if fn then fn(self, ...) end
    for _, h in ipairs(self.hooks[what] or {}) do h(self, ...) end
end
function FrameMethods:RegisterEvent(event)
    self.events[event] = true
    if not self.__inEventOrder then
        self.__inEventOrder = true
        table.insert(self.env.__eventOrder, self)
    end
end
function FrameMethods:UnregisterEvent(event) self.events[event] = nil end
function FrameMethods:IsEventRegistered(event) return self.events[event] == true end
function FrameMethods:UnregisterAllEvents() self.events = {} end
function FrameMethods:Show()
    if self.shown then return end
    self.shown = true
    self:RunScript("OnShow")
end
function FrameMethods:Hide()
    if not self.shown then return end
    self.shown = false
    self:RunScript("OnHide")
end
function FrameMethods:SetShown(v) if v then self:Show() else self:Hide() end end
function FrameMethods:IsShown() return self.shown end
function FrameMethods:IsVisible()
    local f = self
    while f do
        if f.shown == false then return false end
        f = f.parent
    end
    return true
end
function FrameMethods:SetPoint(...) self.points[#self.points + 1] = { ... } end
function FrameMethods:GetPoint(i)
    local p = self.points[i or 1]
    if not p then return nil end
    return p[1], p[2], p[3], p[4], p[5]
end
function FrameMethods:ClearAllPoints() self.points = {} end
function FrameMethods:SetSize(w, h) self.width, self.height = w, h end
function FrameMethods:SetWidth(w) self.width = w end
function FrameMethods:SetHeight(h) self.height = h end
function FrameMethods:GetWidth() return self.width or 0 end
function FrameMethods:GetHeight() return self.height or 0 end
function FrameMethods:GetParent() return self.parent end
function FrameMethods:SetParent(p) self.parent = p end
function FrameMethods:GetFrameLevel() return self.level or 1 end
function FrameMethods:SetFrameStrata(s) self.strata = s end
function FrameMethods:GetFrameStrata()
    local f = self
    while f do
        if f.strata then return f.strata end
        f = f.parent
    end
    return "MEDIUM"
end
function FrameMethods:SetFrameLevel(l) self.level = l end
function FrameMethods:SetText(t)
    self.text = t
    if self.__type == "EditBox" then self:RunScript("OnTextChanged", false) end
end
function FrameMethods:GetText() return self.text or "" end
function FrameMethods:SetScale(s) self.scale = s end
function FrameMethods:SetScrollChild(c) self.scrollChild = c end
function FrameMethods:CreateTexture(_, layer)
    local t = NewRegion("Texture", self)
    t.layer = layer
    table.insert(self.regions, t)
    return t
end
function FrameMethods:CreateFontString(_, layer)
    local t = NewRegion("FontString", self)
    t.layer = layer
    table.insert(self.regions, t)
    return t
end
function FrameMethods:Click(button)
    self:RunScript("OnClick", button or "LeftButton")
end
-- Tooltip model
function FrameMethods:SetOwner(owner) self.owner = owner; self.lines = {} end
function FrameMethods:ClearLines()
    self.lines = {}
    self:RunScript("OnTooltipCleared")
end
function FrameMethods:AddLine(text) table.insert(self.lines, { text }) end
function FrameMethods:AddDoubleLine(l, r) table.insert(self.lines, { l, r }) end
function FrameMethods:NumLines() return #self.lines end
-- Like TooltipDataHandlerMixin:ProcessInfo: clear, new processingInfo, run
-- the post-calls registered for the data's type.
function FrameMethods:ProcessTooltipData(dataType, data)
    self:ClearLines()
    self.processingInfo = { tooltipData = data }
    for _, pc in ipairs(self.env.__postCalls) do
        if pc[1] == dataType then pc[2](self, data) end
    end
end
function FrameMethods:SetHyperlink(link)
    local id = tonumber(tostring(link):match("item:(%d+)"))
    self:ProcessTooltipData(0, { type = 0, id = id })
end
-- TooltipDataHandlerMixin:ProcessInfo with getter, per-call linePreCall and
-- tooltipPostCall, then the global post-calls (as Blizzard's pipeline does).
local BIND_TEXT = { [1] = "Binds when picked up", [2] = "Binds when equipped", [3] = "Binds when used",
                    [7] = "Warbound", [8] = "Warbound", [9] = "Warbound until equipped" }
function FrameMethods:ProcessInfo(info)
    self:ClearLines()
    self.processingInfo = info
    local data = info.tooltipData
    if not data then
        local id = tonumber(tostring(info.getterArgs[1]):match("item:(%d+)"))
        local item = M.ITEMS[id] or {}
        data = { type = 0, id = id, lines = { { type = 22, leftText = item.name or "?" } } }
        if BIND_TEXT[item.bindType] then
            table.insert(data.lines, { type = 20, leftText = BIND_TEXT[item.bindType],
                                       leftColor = { r = 1, g = 1, b = 1 } })
        end
    end
    for _, line in ipairs(data.lines) do
        local consumed = info.linePreCall and info.linePreCall(self, line)
        if not consumed then self:AddLine(line.leftText) end
    end
    if info.tooltipPostCall then info.tooltipPostCall(self) end
    for _, pc in ipairs(self.env.__postCalls) do
        if pc[1] == data.type then pc[2](self, data) end
    end
end
-- GameTooltip:SetCurrencyByID (TooltipDataHandlerMixin): currency name line.
function FrameMethods:SetCurrencyByID(id)
    self:ProcessTooltipData(5, { type = 5, id = id })
    local info = self.env.C_CurrencyInfo.GetCurrencyInfo(id)
    self:AddLine(info and info.name or ("currency:" .. tostring(id)))
end
-- Unit/world tooltips (type 2 = Unit, 18 = Object); refreshed every 0.2 s in the client.
function FrameMethods:SetUnit(unit)
    self:ProcessTooltipData(2, { type = 2, guid = "Creature-0-0-0-0-1234-0000" .. tostring(unit) })
end
-- Backdrop
function FrameMethods:SetBackdrop(b) self.backdrop = b end

local TEMPLATE_FRAME_LEVEL = { UIPanelCloseButton = 510, UIPanelCloseButtonNoScripts = 510 }

local function NewFrame(env, ftype, name, parent, template)
    local f = {
        __type = ftype, __name = name, env = env, parent = parent, template = template,
        scripts = {}, hooks = {}, events = {}, points = {}, regions = {}, children = {},
        shown = true, lines = {},
    }
    setmetatable(f, { __index = function(_, k)
        local m = FrameMethods[k]
        if m then return m end
        -- permissive no-op only for real, unmodelled widget methods; anything
        -- else (typos, fields) is nil exactly like on a client frame.
        if WIDGET_METHODS[k] then return function() end end
        return nil
    end })
    if parent and parent.children then table.insert(parent.children, f) end
    -- Frame level as in the client: one above the parent, unless the template
    -- pins an absolute level (SharedUIPanelTemplates.xml).
    f.level = TEMPLATE_FRAME_LEVEL[template] or ((parent and parent.GetFrameLevel and parent:GetFrameLevel() or 0) + 1)
    -- Template / intrinsic children
    if ftype == "ItemButton" then
        f.icon = f:CreateTexture(nil, "BORDER")
        f.Count = f:CreateFontString(nil, "ARTWORK")
        f.IconBorder = f:CreateTexture(nil, "OVERLAY")
        f.NormalTexture = f:CreateTexture(nil, "BORDER")
    end
    if template and template:find("ScrollFrameTemplate", 1, true) then
        f.ScrollBar = NewFrame(env, "EventFrame", nil, f)
    end
    if template == "BattlePetTooltipTemplate" then
        f.Owned = f:CreateFontString(nil, "ARTWORK")
    end
    if template and template:find("BackdropTemplate", 1, true) then
        f.SetBackdropColor = function() end
        f.SetBackdropBorderColor = function() end
    end
    env.__frames[#env.__frames + 1] = f
    if name then env[name] = f end
    return f
end

--------------------------------------------------------------------------------
--  Default game state
--------------------------------------------------------------------------------
function M.defaultState(overrides)
    local s = {
        player = { name = "Alice", realm = "Blackhand", realmName = "Blackhand", class = "MAGE", race = "Human",
                   faction = "Alliance", level = 80 },
        connectedRealms = { "Blackhand", "Mal'Ganis" },
        money = 12345678,
        now = 1790000000,
        bags = { [0] = { size = 20, slots = {} }, [1] = { size = 16, slots = {} }, [2] = { size = 0, slots = {} },
                 [3] = { size = 0, slots = {} }, [4] = { size = 0, slots = {} }, [5] = { size = 0, slots = {} } },
        equipped = {},
        bankTabs = { [0] = {}, [2] = {} },   -- BankType -> list of { ID, name, icon }
        canViewBank = { [0] = true, [2] = true },
        warbandMoney = 5000000,
        inbox = {},
        sendItems = {},
        guild = nil,     -- { name, realm, money, tabs = { { name, icon, viewable, slots = { [slot] = { id, count } } } } }
        ownedAuctions = {},   -- list of OwnedAuctionInfo-shaped tables (C_AuctionHouse.GetOwnedAuctions)
        ownedAuctionsFull = false,
        auctionQueries = 0,
        nextAuctionID = 9000,
        postNeedsConfirm = false,   -- PostItem/PostCommodity return true, AUCTION_HOUSE_POST_WARNING follows
        postWarningSync = false,    -- fire that warning inside the call (before post-hooks run)
        multisell = nil,            -- n: PostItem(quantity) creates n auctions
        createdIDOffset = 0,        -- AUCTION_HOUSE_AUCTION_CREATED id differs from the owned-list id
        ownedTableEmpty = false,    -- GetOwnedAuctions() returns {} while the indexed API has data
        cancelEvent = "one",        -- live client: AUCTION_CANCELED fires with 1, not the auction ID.
                                    -- "one" | "id" | "none" (no arg) | "missing" (no event)
        refreshAfterCancel = false, -- client sends a complete owned list after a cancel
        currencies = {}, -- list of { id, name, quantity, icon, header }
        loadedItems = {},
        inCombat = false,
        secret = false,
        modifiers = { shift = false, ctrl = false, alt = false },
        locale = "enUS",
    }
    for k, v in pairs(overrides or {}) do s[k] = v end
    return s
end

function M.putItem(state, bagID, slot, itemID, count, link)
    state.bags[bagID] = state.bags[bagID] or { size = 98, slots = {} }
    state.bags[bagID].slots[slot] = { id = itemID, count = count or 1, link = link or M.itemLink(itemID) }
end

--------------------------------------------------------------------------------
--  Environment (globals the addon sees)
--------------------------------------------------------------------------------
function M.newEnv(state, savedVariables)
    local env = {}
    env._G = env
    env.__frames, env.__eventOrder, env.__onUpdateSets, env.__errors, env.__chat = {}, {}, {}, {}, {}
    env.__postCalls, env.__queue, env.__clicks, env.__slashOut = {}, {}, {}, {}
    env.__state = state or M.defaultState()
    local S = env.__state

    -- Lua stdlib
    for _, k in ipairs({ "assert", "error", "ipairs", "next", "pairs", "pcall", "print", "rawequal", "rawget",
        "rawset", "select", "setmetatable", "getmetatable", "tonumber", "tostring", "type", "unpack", "xpcall",
        "string", "table", "math", "os", "coroutine", "debug", "loadstring", "setfenv", "getfenv" }) do
        env[k] = _G[k]
    end
    env.strsplit = function(sep, str) local out = {} for p in (str .. sep):gmatch("(.-)" .. sep) do out[#out + 1] = p end return unpack(out) end
    env.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    env.tinsert = table.insert
    env.time = function() return S.now end
    env.date = os.date
    env.Mixin = function(obj, ...) for i = 1, select("#", ...) do for k, v in pairs((select(i, ...))) do obj[k] = v end end return obj end
    env.CreateFromMixins = function(...) return env.Mixin({}, ...) end
    env.geterrorhandler = function() return function(err) table.insert(env.__errors, tostring(err)) end end
    -- Calls fn; an error goes to the error handler and the caller keeps running.
    env.securecallfunction = function(fn, ...)
        local r = { pcall(fn, ...) }
        if not r[1] then env.geterrorhandler()(r[2]) return end
        return unpack(r, 2, table.maxn(r))
    end
    env.issecretvalue = function(v) return getmetatable(v) == SecretMT end
    env.hooksecurefunc = function(a, b, c)
        local tbl, name, fn = env, a, b
        if type(a) == "table" then tbl, name, fn = a, b, c end
        local orig = tbl[name]
        assert(type(orig) == "function", "hooksecurefunc on missing function " .. tostring(name))
        tbl[name] = function(...)
            local r = { orig(...) }
            fn(...)
            return unpack(r)
        end
    end
    env.InCombatLockdown = function() return S.inCombat end
    env.GetLocale = function() return S.locale end

    local function maybeSecret(v) if S.secret then return Secret(v) end return v end

    -- Frames & UI globals
    env.CreateFrame = function(ftype, name, parent, template) return NewFrame(env, ftype, name, parent, template) end
    env.UIParent = NewFrame(env, "Frame", "UIParent")
    for _, name in ipairs({ "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2", "BattlePetTooltip" }) do
        NewFrame(env, "GameTooltip", name, env.UIParent)
    end
    -- Battle pet tooltip API (Blizzard_FrameXML/BattlePetTooltip.lua,
    -- FloatingPetBattleTooltip.lua). The shared BattlePetTooltip path records
    -- its use so tests can prove the browser never takes it.
    env.BattlePetToolTip_UnpackBattlePetLink = function(link)
        local opts, name = tostring(link):match("|Hbattlepet:([^|]*)|h%[(.-)%]|h")
        if not opts then return nil end
        local species, level, quality, health, power, speed = env.strsplit(":", opts)
        return tonumber(species), tonumber(level), tonumber(quality), tonumber(health), tonumber(power),
            tonumber(speed), name
    end
    env.BattlePetToolTip_ShowLink = function() env.__sharedPetTooltipUsed = true; return true end
    env.BattlePetTooltipTemplate_SetBattlePet = function(frame, data)
        assert(data.petType, "BattlePetTooltipTemplate_SetBattlePet needs petType")
        frame.petData = data
    end
    env.C_PetJournal = {
        GetPetInfoBySpeciesID = function(speciesID) return "Species " .. speciesID, 1, 3 end,
        GetOwnedBattlePetString = function() return "Collected (1/3)" end,
    }
    env.UISpecialFrames = {}
    env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) table.insert(env.__chat, msg) end }
    env.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
    env.GameFontHighlight = {}
    env.BackdropTemplateMixin = { SetBackdrop = function(self, b) self.backdrop = b end,
        SetBackdropColor = function() end, SetBackdropBorderColor = function() end }
    env.OKAY, env.CANCEL = "Okay", "Cancel"
    env.ITEM_SOULBOUND, env.ITEM_ACCOUNTBOUND = "Soulbound", "Warbound"
    env.ITEM_QUALITY_COLORS = {}
    for q = 0, 8 do env.ITEM_QUALITY_COLORS[q] = { r = q / 8, g = 0.5, b = 1 - q / 8 } end
    env.ITEM_QUALITY4_DESC = "Epic"
    env.INVSLOT_FIRST_EQUIPPED, env.INVSLOT_LAST_EQUIPPED = 1, 19
    env.ATTACHMENTS_MAX_RECEIVE, env.ATTACHMENTS_MAX_SEND = 16, 12
    env.SlashCmdList = {}
    env.Enum = Enums()
    env.SetItemButtonTexture = function(b, tex) b.__texture = tex end
    env.SetItemButtonCount = function(b, n) b.__count = n end
    env.SetItemButtonQuality = function(b, q) b.__quality = q end
    env.IsModifiedClick = function() return S.modifiers.shift or S.modifiers.ctrl end
    env.HandleModifiedItemClick = function(link) table.insert(env.__clicks, link) end
    env.IsShiftKeyDown = function() return S.modifiers.shift end
    env.IsControlKeyDown = function() return S.modifiers.ctrl end
    env.IsAltKeyDown = function() return S.modifiers.alt end
    env.BreakUpLargeNumbers = function(n) return tostring(n) end
    env.HideUIPanel = function(f) if f then f:Hide() end end
    env.C_AddOns = { GetAddOnMetadata = function(_, field) if field == "Version" then return "test" end end }

    -- Player
    env.UnitName = function(unit) if unit == "player" then return S.player.name end end
    env.GetNormalizedRealmName = function() return S.player.realm end
    env.GetRealmName = function() return S.player.realmName end
    env.UnitClass = function() return "Mage", S.player.class end
    env.UnitRace = function() return "Human", S.player.race end
    env.UnitFactionGroup = function() return S.player.faction end
    env.UnitLevel = function() return S.player.level end
    -- The client reports 0 while it tears a character down (logout) and, on
    -- some logins, before the money is known (moneyZeroUntilWorld).
    env.GetMoney = function()
        if S.loggingOut or S.moneyZeroUntilWorld then return 0 end
        return S.money
    end
    env.C_AutoComplete = { GetAutoCompleteRealms = function() return S.connectedRealms end }
    S.interacting = S.interacting or {}
    env.C_PlayerInteractionManager = {
        IsInteractingWithNpcOfType = function(t) return S.interacting[t] == true end,
    }
    env.C_ClassColor = { GetClassColor = function(class)
        return { r = 0.25, g = 0.78, b = 0.92, GenerateHexColor = function() return "ff3fc7eb" end, class = class }
    end }

    -- Items
    local function infoFor(ref)
        local id = type(ref) == "number" and ref or tonumber(tostring(ref):match("item:(%d+)")) or tonumber(ref)
        return id, M.ITEMS[id]
    end
    env.C_Item = {
        GetItemInfo = function(ref)
            local id, info = infoFor(ref)
            if not info or (S.uncachedItems and S.uncachedItems[id] and not S.loadedItems[id]) then return nil end
            return info.name, M.itemLink(id), info.quality, 80, 1, info.type, info.subtype, 20, info.equipLoc, info.icon,
                100, 4, 1, info.bindType or 0
        end,
        GetItemInfoInstant = function(ref)
            local id, info = infoFor(ref)
            if not id then return nil end
            info = info or {}
            return id, info.type, info.subtype, info.equipLoc, info.icon, M.CLASS_IDS[info.type] or 15, 0
        end,
        GetItemClassInfo = function(classID) return M.CLASS_NAMES[classID] or "" end,
        DoesItemExist = function(loc)
            local bag = type(loc) == "table" and S.bags[loc.bagID]
            return bag ~= nil and bag and bag.slots[loc.slotIndex] ~= nil or false
        end,
        GetItemID = function(loc)
            local it = S.bags[loc.bagID] and S.bags[loc.bagID].slots[loc.slotIndex]
            return it and it.id
        end,
        GetItemLink = function(loc)
            local it = S.bags[loc.bagID] and S.bags[loc.bagID].slots[loc.slotIndex]
            return it and it.link
        end,
        -- slot.wue: "warbound until equipped" (still movable in the warband)
        IsBoundToAccountUntilEquip = function(loc)
            local it = loc.bagID and S.bags[loc.bagID] and S.bags[loc.bagID].slots[loc.slotIndex]
            return it and it.wue or false
        end,
        GetItemQualityByID = function(ref)
            local id, info = infoFor(ref)
            if S.uncachedItems and S.uncachedItems[id] and not S.loadedItems[id] then return nil end
            return info and info.quality
        end,
        RequestLoadItemDataByID = function(id)
            table.insert(env.__queue, function()
                S.loadedItems[id] = true
                env.FireEvent("ITEM_DATA_LOAD_RESULT", id, true)
            end)
        end,
        GetItemCount = function(ref, includeBank)
            local id = infoFor(ref)
            local n = 0
            for bagID, bag in pairs(S.bags) do
                if bagID <= 5 or (includeBank and bagID >= 6 and bagID <= 11) then
                    for _, it in pairs(bag.slots) do if it.id == id then n = n + it.count end end
                end
            end
            for _, it in pairs(S.equipped) do if it.id == id then n = n + 1 end end
            return n
        end,
    }

    -- Containers
    env.C_Container = {
        GetContainerNumSlots = function(bagID)
            local bag = S.bags[bagID]
            return maybeSecret(bag and bag.size or 0)
        end,
        GetContainerItemInfo = function(bagID, slot)
            local bag = S.bags[bagID]
            local it = bag and bag.slots[slot]
            if not it then return nil end
            local info = M.ITEMS[it.id] or {}
            return { iconFileID = info.icon, stackCount = maybeSecret(it.count), isLocked = false, quality = info.quality,
                     isReadable = false, hasLoot = false, hyperlink = maybeSecret(it.link), isFiltered = false,
                     hasNoValue = false, itemID = maybeSecret(it.id), isBound = it.bound or false, itemName = info.name }
        end,
    }

    -- Bank
    env.C_Bank = {
        CanViewBank = function(bankType) return S.canViewBank[bankType] == true end,
        FetchPurchasedBankTabData = function(bankType)
            local out = {}
            for i, tab in ipairs(S.bankTabs[bankType] or {}) do
                out[i] = { ID = tab.ID, bankType = bankType, name = tab.name or "", icon = tab.icon or 0,
                           depositFlags = 0, tabCleanupConfirmation = "", tabNameEditBoxHeader = "" }
            end
            return out
        end,
        FetchDepositedMoney = function(bankType) if bankType == 2 then return S.warbandMoney end return 0 end,
    }

    -- ItemLocation (Blizzard_ObjectAPI)
    env.ItemLocation = {
        CreateFromBagAndSlot = function(_, bagID, slotIndex) return { bagID = bagID, slotIndex = slotIndex } end,
        CreateFromEquipmentSlot = function(_, slot) return { equipmentSlotIndex = slot } end,
    }

    -- Equipment sets. Locations use the client's packing (see EquipmentManager.lua):
    -- PLAYER 0x100000, BAGS 0x200000, bag << 8, slot.
    S.equipmentSets = S.equipmentSets or {}   -- { { id, name, items = { "e<slot>" | "b<bag>:<slot>" } } }
    env.C_EquipmentSet = {
        GetEquipmentSetIDs = function()
            local ids = {}
            for i, set in ipairs(S.equipmentSets) do ids[i] = set.id end
            return ids
        end,
        GetEquipmentSetInfo = function(id)
            for _, set in ipairs(S.equipmentSets) do if set.id == id then return set.name, 0, id end end
        end,
        GetItemLocations = function(id)
            for _, set in ipairs(S.equipmentSets) do
                if set.id == id then
                    local locs = { [2] = 1 }                       -- an "ignored" slot marker
                    for n, key in ipairs(set.items) do
                        local e = key:match("^e(%d+)$")
                        local b, sl = key:match("^b(%d+):(%d+)$")
                        if e then locs[100 + n] = 0x100000 + tonumber(e)
                        else locs[100 + n] = 0x100000 + 0x200000 + tonumber(b) * 256 + tonumber(sl) end
                    end
                    return locs
                end
            end
        end,
    }
    env.EquipmentManager_GetLocationData = function(location)
        local d = { isPlayer = location >= 0x100000 and (location % 0x200000) >= 0x100000 }
        d.isBags = location >= 0x200000
        d.isBank = false
        local rest = location
        if d.isBags then rest = rest - 0x200000 end
        if d.isPlayer then rest = rest - 0x100000 end
        if d.isBags then
            d.bag = math.floor(rest / 256)
            d.slot = rest - d.bag * 256
        else
            d.slot = rest
        end
        return d
    end

    -- Equipment
    env.GetInventoryItemLink = function(_, slot) local it = S.equipped[slot]; return it and it.link end
    env.GetInventoryItemID = function(_, slot) local it = S.equipped[slot]; return it and it.id end

    -- Currency
    env.C_CurrencyInfo = {
        GetCurrencyListSize = function() return #S.currencies end,
        GetCurrencyListInfo = function(i)
            local c = S.currencies[i]
            if not c then return nil end
            return { name = c.name, isHeader = c.header or false, quantity = c.quantity or 0,
                     currencyID = c.id or 0, iconFileID = c.icon or 0,
                     isAccountTransferable = c.transferable or false, isAccountWide = c.accountWide or false }
        end,
        GetCurrencyListLink = function(i) local c = S.currencies[i]; return c and c.id and ("|Hcurrency:" .. c.id .. "|h[x]|h") end,
        GetCurrencyIDFromLink = function(link) return tonumber(link:match("currency:(%d+)")) end,
        GetCurrencyLink = function(id, amount)
            return "|cffffffff|Hcurrency:" .. id .. ":" .. (amount or 0) .. "|h[currency]|h|r"
        end,
        GetCurrencyInfo = function(id)
            for _, c in ipairs(S.currencies) do
                if c.id == id then
                    return { name = c.name, quantity = c.quantity, iconFileID = c.icon, currencyID = id,
                             isAccountTransferable = c.transferable or false, isAccountWide = c.accountWide or false }
                end
            end
            return nil
        end,
    }

    -- Auction house (owned auctions)
    env.C_AuctionHouse = {
        GetOwnedAuctions = function()
            local out = {}
            if S.ownedTableEmpty then return out end
            for i, a in ipairs(S.ownedAuctions) do out[i] = a end
            return out
        end,
        GetNumOwnedAuctions = function() return #S.ownedAuctions end,
        GetOwnedAuctionInfo = function(i) return S.ownedAuctions[i] end,
        CancelAuction = function(auctionID)
            table.insert(env.__queue, function()
                for i, a in ipairs(S.ownedAuctions) do
                    if a.auctionID == auctionID then table.remove(S.ownedAuctions, i) break end
                end
                if S.cancelEvent == "one" then env.FireEvent("AUCTION_CANCELED", 1)
                elseif S.cancelEvent == "id" then env.FireEvent("AUCTION_CANCELED", auctionID)
                elseif S.cancelEvent == "none" then env.FireEvent("AUCTION_CANCELED") end
                if S.refreshAfterCancel then
                    S.ownedAuctionsFull = true
                    env.FireEvent("OWNED_AUCTIONS_UPDATED")
                end
            end)
        end,
        HasFullOwnedAuctionResults = function() return S.ownedAuctionsFull end,
        -- PostItem(item, duration, quantity, bid, buyout) / PostCommodity(item, duration, quantity, unitPrice)
        PostItem = function(loc, duration, quantity, bid, buyout) return env.__post(loc, duration, quantity, false, false, buyout or bid) end,
        PostCommodity = function(loc, duration, quantity, unitPrice) return env.__post(loc, duration, quantity, true, false, unitPrice) end,
        ConfirmPostItem = function(loc, duration, quantity, bid, buyout) env.__post(loc, duration, quantity, false, true, buyout or bid) end,
        ConfirmPostCommodity = function(loc, duration, quantity, unitPrice) env.__post(loc, duration, quantity, true, true, unitPrice) end,
        QueryOwnedAuctions = function(sorts)
            assert(type(sorts) == "table", "QueryOwnedAuctions needs a sorts table")
            S.auctionQueries = S.auctionQueries + 1
            table.insert(env.__queue, function()
                S.ownedAuctionsFull = true
                env.FireEvent("OWNED_AUCTIONS_UPDATED")
            end)
        end,
    }

    -- Posting: the client answers asynchronously (events on the queue).
    env.__post = function(loc, duration, quantity, isCommodity, confirmed, price)
        local bag = S.bags[loc.bagID]
        local it = bag and bag.slots[loc.slotIndex]
        assert(it, "posting an empty slot")
        if S.postNeedsConfirm and not confirmed then
            if S.postWarningSync then env.FireEvent("AUCTION_HOUSE_POST_WARNING")
            else table.insert(env.__queue, function() env.FireEvent("AUCTION_HOUSE_POST_WARNING") end) end
            return true
        end
        local id, link = it.id, it.link
        table.insert(env.__queue, function()
            local n = (not isCommodity and S.multisell and quantity > 1) and S.multisell or 1
            if n > 1 then env.FireEvent("AUCTION_MULTISELL_START", n) end
            for _ = 1, n do
                S.nextAuctionID = S.nextAuctionID + 1
                table.insert(S.ownedAuctions, M.ownedAuction(S.nextAuctionID + S.createdIDOffset, id, quantity / n,
                    { link = not isCommodity and link or nil, seconds = ({ 43200, 86400, 172800 })[duration],
                      buyout = price }))
                env.FireEvent("AUCTION_HOUSE_AUCTION_CREATED", S.nextAuctionID)
            end
            it.count = it.count - quantity
            if it.count <= 0 then bag.slots[loc.slotIndex] = nil end
            env.FireEvent("BAG_UPDATE", loc.bagID)
            env.FireEvent("BAG_UPDATE_DELAYED")
        end)
        return false
    end

    -- Mail
    env.GetInboxNumItems = function() return #S.inbox, #S.inbox end
    env.GetInboxHeaderInfo = function(i)
        local m = S.inbox[i]
        if not m then return nil end
        return nil, nil, m.sender, m.subject or "", 0, 0, m.daysLeft or 30, #(m.items or {}), false, false, false, true, false
    end
    env.GetInboxItem = function(i, a)
        local m = S.inbox[i]
        local it = m and m.items[a]
        if not it then return nil end
        local info = M.ITEMS[it.id] or {}
        return info.name, it.id, info.icon, it.count or 1, info.quality, true, it.isCurrency or false
    end
    env.GetInboxItemLink = function(i, a)
        local m = S.inbox[i]
        local it = m and m.items[a]
        return it and (it.link or M.itemLink(it.id))
    end
    env.GetSendMailItem = function(i)
        local it = S.sendItems[i]
        if not it then return nil end
        local info = M.ITEMS[it.id] or {}
        return info.name, it.id, info.icon, it.count or 1, info.quality
    end
    env.GetSendMailItemLink = function(i) local it = S.sendItems[i]; return it and M.itemLink(it.id) end
    env.SendMail = function(recipient) S.lastSendMail = recipient end

    -- Guild
    env.IsInGuild = function() return S.guild ~= nil end
    env.GetGuildInfo = function()
        if not S.guild then return nil end
        return S.guild.name, "Member", 3, S.guild.realm
    end
    -- S.guildTabsPending: first visit of a session, the tab list has not
    -- arrived yet (the client reports 0 tabs until GUILDBANK_UPDATE_TABS).
    env.GetNumGuildBankTabs = function()
        if S.guildTabsPending then return 0 end
        return S.guild and #S.guild.tabs or 0
    end
    env.GetGuildBankTabInfo = function(tab)
        if S.guildTabsPending then return nil end
        local t = S.guild and S.guild.tabs[tab]
        if not t then return nil end
        return t.name, t.icon or 0, t.viewable ~= false, true, 0, 0, false
    end
    local function guildSlot(tab, slot)
        local t = S.guild and S.guild.tabs[tab]
        if not t or not S.guildQueried[tab] then return nil end
        return t.slots[slot]
    end
    env.GetGuildBankItemInfo = function(tab, slot)
        local it = guildSlot(tab, slot)
        if not it then return nil end
        return 0, it.count or 1, false, false, 1
    end
    env.GetGuildBankItemLink = function(tab, slot)
        local it = guildSlot(tab, slot)
        return it and M.itemLink(it.id)
    end
    S.guildQueried = S.guildQueried or {}
    env.QueryGuildBankTab = function(tab)
        table.insert(env.__queue, function()
            S.guildQueried[tab] = true
            env.FireEvent("GUILDBANKBAGSLOTS_CHANGED")
        end)
    end
    env.GetCurrentGuildBankTab = function() return S.guildCurrentTab or 1 end
    env.GetGuildBankMoney = function() return S.guild and S.guild.money or 0 end

    -- Tooltips
    env.TooltipDataProcessor = {
        AddTooltipPostCall = function(dataType, fn) table.insert(env.__postCalls, { dataType, fn }) end,
    }
    env.__showTooltipData = function(tooltip, itemID)
        tooltip:ProcessTooltipData(0, { type = 0, id = itemID })
    end

    -- Settings API
    env.Settings = {
        VarType = { Boolean = "boolean", String = "string", Number = "number" },
        RegisterVerticalLayoutCategory = function(name)
            local cat = { name = name, settings = {}, controls = {}, GetID = function() return 42 end }
            local layout = { initializers = {}, AddInitializer = function(self, i) table.insert(self.initializers, i) end }
            env.__settingsCategory, env.__settingsLayout = cat, layout
            return cat, layout
        end,
        RegisterProxySetting = function(cat, variable, varType, name, default, get, set)
            local setting = { variable = variable, varType = varType, name = name, default = default,
                GetValue = function() return get() end, SetValue = function(_, v) set(v) end }
            cat.settings[variable] = setting
            return setting
        end,
        CreateCheckbox = function(cat, setting) table.insert(cat.controls, { kind = "checkbox", setting = setting }) end,
        CreateDropdown = function(cat, setting, options)
            table.insert(cat.controls, { kind = "dropdown", setting = setting, options = options() })
        end,
        CreateControlTextContainer = function()
            local data = {}
            return { Add = function(_, value, label) table.insert(data, { value = value, label = label }) end,
                     GetData = function() return data end }
        end,
        RegisterAddOnCategory = function(cat) env.__settingsRegistered = cat end,
        OpenToCategory = function(id) env.__settingsOpened = id end,
    }
    env.CreateSettingsListSectionHeaderInitializer = function(name) return { header = name } end
    env.CreateSettingsButtonInitializer = function(name, text, click) return { button = name, text = text, click = click } end

    -- Test helpers on the env
    -- Which interaction window is open (C_PlayerInteractionManager), kept like the
    -- client from the show/hide events the tests fire.
    local INTERACTION_EVENTS = {
        MAIL_SHOW = { 17, true }, MAIL_CLOSED = { 17, false },
        AUCTION_HOUSE_SHOW = { 21, true }, AUCTION_HOUSE_CLOSED = { 21, false },
        BANKFRAME_OPENED = { 8, true }, BANKFRAME_CLOSED = { 8, false },
    }
    function env.FireEvent(event, ...)
        if event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then S.interacting[(...)] = true
        elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then S.interacting[(...)] = nil
        elseif INTERACTION_EVENTS[event] then
            local e = INTERACTION_EVENTS[event]
            S.interacting[e[1]] = e[2] or nil
        end
        for _, f in ipairs(env.__eventOrder) do
            if f.events[event] then
                local fn = f.scripts.OnEvent
                if fn then fn(f, event, ...) end
            end
        end
    end
    function env.ProcessQueue()
        local guard = 0
        while #env.__queue > 0 do
            guard = guard + 1
            assert(guard < 10000, "queue did not settle")
            table.remove(env.__queue, 1)()
        end
    end
    function env.RunOnUpdates()
        for _, f in ipairs(env.__frames) do
            local fn = f.scripts.OnUpdate
            if fn then fn(f, 0.016) end
        end
    end
    function env.Slash(msg)
        env.SlashCmdList.EUIALTS(msg or "")
    end

    if savedVariables then
        env.EllesmereUIBagsAltsDB = deepCopy(savedVariables)
    end
    return env
end

--------------------------------------------------------------------------------
--  Addon loading
--------------------------------------------------------------------------------
function M.tocFiles(addonDir)
    local files = {}
    local fh = assert(io.open(addonDir .. "/" .. ADDON .. ".toc"))
    for line in fh:lines() do
        line = line:gsub("\r", "")
        if line ~= "" and not line:match("^#") then
            files[#files + 1] = (line:gsub("\\", "/"))
        end
    end
    fh:close()
    return files
end

function M.loadAddon(env)
    local dir = ROOT .. "/" .. ADDON
    local ns = {}
    for _, rel in ipairs(M.tocFiles(dir)) do
        local chunk, err = loadfile(dir .. "/" .. rel)
        assert(chunk, err)
        setfenv(chunk, env)
        chunk(ADDON, ns)
    end
    env.__ns = ns
    return ns
end

-- Full client boot: load, ADDON_LOADED, PLAYER_LOGIN, PLAYER_ENTERING_WORLD.
-- Blizzard's bag windows (ContainerFrame.xml): hidden until a bag opens.
local function CreateBagFrames(env)
    env.NUM_CONTAINER_FRAMES = 6
    local combined = env.CreateFrame("Frame", "ContainerFrameCombinedBags", env.UIParent)
    combined:Hide()
    env.ContainerFrameCombinedBags = combined
    for i = 1, env.NUM_CONTAINER_FRAMES do
        local f = env.CreateFrame("Frame", "ContainerFrame" .. i, env.UIParent)
        f:Hide()
        env["ContainerFrame" .. i] = f
    end
    -- Blizzard's bag functions (ContainerFrame.lua), hookable with hooksecurefunc.
    env.ToggleAllBags = function() combined:SetShown(not combined:IsShown()) end
    env.OpenAllBags = function() combined:Show() end
    env.OpenAllBagsMatchingContext = function() combined:Show() end
    env.ToggleBackpack = function() env.ContainerFrame1:SetShown(not env.ContainerFrame1:IsShown()) end
    env.OpenBackpack = function() env.ContainerFrame1:Show() end
    env.ToggleBag = function(id) local f = env["ContainerFrame" .. ((id or 0) + 1)] if f then f:SetShown(not f:IsShown()) end end
    env.OpenBag = function(id) local f = env["ContainerFrame" .. ((id or 0) + 1)] if f then f:Show() end end
    -- The player opens and closes the bags: EllesmereUI's bag window, which
    -- takes over every bag key.
    function env.OpenBags() env.EUI_Bags:Show() end
    function env.CloseBags() env.EUI_Bags:Hide() end
end

-- Logs in with EllesmereUI + Bags (the addon's dependency): opts.beforeLoad
-- may install EUI itself with options (fake_eui), otherwise the default fake
-- (with EUI's skin module) is used; opts.eui = { ... } passes install options.
-- Unless opts.inactive, the player then opens the bags once, the first use
-- that activates the addon (Core/Activation.lua).
function M.boot(state, savedVariables, opts)
    opts = opts or {}
    local env = M.newEnv(state, savedVariables)
    CreateBagFrames(env)
    if opts.beforeLoad then opts.beforeLoad(env) end
    if not env.EllesmereUI then env.__eui = require("fake_eui").install(env, opts.eui) end
    local ns = M.loadAddon(env)
    env.FireEvent("ADDON_LOADED", ADDON)
    if opts.beforeLogin then opts.beforeLogin(env, ns) end
    env.FireEvent("PLAYER_LOGIN")
    env.__state.moneyZeroUntilWorld = nil
    env.FireEvent("PLAYER_ENTERING_WORLD", true, false)
    env.FireEvent("BAG_UPDATE_DELAYED")
    if not opts.inactive then
        env.OpenBags()
        env.CloseBags()
    end
    return env, ns
end

--------------------------------------------------------------------------------
--  SavedVariables: serialize like the client (only strings/numbers/bools/tables)
--------------------------------------------------------------------------------
local function serialize(v, depth)
    depth = depth or 0
    assert(depth < 50, "SavedVariables nested too deep")
    local t = type(v)
    if t == "string" then return string.format("%q", v)
    elseif t == "number" or t == "boolean" then return tostring(v)
    elseif t == "table" then
        local parts = {}
        for k, x in pairs(v) do
            local kt = type(k)
            assert(kt == "string" or kt == "number", "SavedVariables key of type " .. kt)
            parts[#parts + 1] = "[" .. serialize(k, depth + 1) .. "]=" .. serialize(x, depth + 1)
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    error("SavedVariables cannot store a " .. t)
end
M.serialize = serialize

function M.logout(env)
    env.__state.loggingOut = true
    env.FireEvent("PLAYER_LEAVING_WORLD")
    env.FireEvent("PLAYER_MONEY")          -- teardown noise must not store 0g
    env.FireEvent("PLAYER_LOGOUT")
    env.__state.loggingOut = nil
    local src = "return " .. serialize(env.EllesmereUIBagsAltsDB)
    return assert(loadstring(src))(), #src
end

-- Switches to another character with the saved variables of the last session.
function M.relog(env, playerOverrides, stateOverrides)
    local sv = M.logout(env)
    local state = M.defaultState(stateOverrides)
    for k, v in pairs(playerOverrides or {}) do state.player[k] = v end
    return M.boot(state, sv)
end

-- Stored stacks of a packed container ("slot:enc;slot:enc", Keys.lua), parsed
-- independently of the addon: { [slot] = enc }.
function M.items(container)
    local map = {}
    local packed = container and container.items or ""
    assert(type(packed) == "string", "container items are not packed: " .. type(packed))
    for slot, enc in packed:gmatch("(%d+):([^;]+)") do map[tonumber(slot)] = enc end
    return map
end

-- { [slot] = enc } -> packed string (slot order)
function M.pack(map)
    local slots, parts = {}, {}
    for slot in pairs(map) do slots[#slots + 1] = slot end
    table.sort(slots)
    for i, slot in ipairs(slots) do parts[i] = slot .. ":" .. map[slot] end
    return table.concat(parts, ";")
end

function M.setItem(container, slot, enc)
    local map = M.items(container)
    map[slot] = enc
    container.items = M.pack(map)
end

M.Secret = Secret
M.shallowCopy = shallowCopy
return M
