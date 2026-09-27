# EUI BagSync: plan (archived)

> **Archived.** This is the original design plan, translated from German. It
> was written before the implementation started (working title "EUI
> BagSync") and is kept as a record of the reasoning. The addon that came out
> of it is `EllesmereUIBags_Alts`; its current state is described in the
> [README](../../README.md). Where the implementation later went a different
> way, the notes below and the [work checklist](TODO.md) say so. Notable
> later changes: EllesmereUI Bags became a hard dependency (0.7.1), the
> addon now does nothing until it is first used in a session (0.7.0), and the
> storage format became one packed string per container (0.8.0).

> **Implementation status (2026-09-26):** implemented as `EllesmereUIBags_Alts` (version 0.1.0).
> Details, installation and the in-game test plan are in the README, the work checklist in [TODO.md](TODO.md).
>
> Deviations from the original plan:
> - **Name:** `EllesmereUIBags_Alts` (title "EllesmereUI Bags: Alts"), saved variable `EllesmereUIBagsAltsDB`.
> - **Scope:** no LDB/minimap button. Header button and guild bank are in (both opt-in). Own auctions were added in 0.2.0: passive by default, an active query is opt-in.
> - **First-run question:** with EUI it only comes at the first bag open. EUI shows its own popups at login through the same dialog.
> - **Settings button:** opens the browser above the settings panel and does not close the panel (no `HideUIPanel` from addon code, because of the taint risk).
> - **Guild bank:** every slots event rereads all tabs requested so far, because the event does not say which tab answered.
> - **Tooltip:** only `GameTooltip` and `ItemRefTooltip`, no comparison tooltips. The item ID comes from `data.id`, otherwise from the hyperlink or the GUID.
> - **In addition:** public API `EllesmereUIBagsAlts`, in-game self-test `/alts selftest`, upstream drop-in `upstream/EllesmereUIBags_ExtAPI.lua` with a patch.
> - **Tests:** project-local toolchain with a busted mock and an API check against Blizzard's 12.1 sources, plus the headless simulator [wow-ui-sim](https://github.com/Osso/wow-ui-sim) with real FrameXML and real EllesmereUI.

A standalone companion addon for **EllesmereUI Bags**. It collects inventory data across all characters, stores it account-wide, optionally shows it in the item tooltip and offers a browser window across all characters, similar to Baganator.

State of the analysis: EllesmereUI `main`, Bags module v9.2.9 (interface 120000-120100, Midnight 12.1+).

---

## 1. Feasibility: result

**Yes, this works as a separate addon, without changing EllesmereUI's code.** There is one limitation:

| Feature | Possible as a separate addon? | Reason |
|---|---|---|
| Collecting and storing data | Yes, fully | Plain WoW API (`C_Container`, `C_Bank`, mail, equipment). No EUI code needed. |
| Tooltip with the stock of all characters | Yes, fully | `TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, ...)`. EUI uses the same mechanism itself; both run side by side. |
| Own browser window in EUI's look | Yes | Official API `EllesmereUI.RegisterSkin` (see `SKINNING_API.md`), plus fonts and accent colour through EUI helpers. |
| Button in the header of the EUI bag | Yes, but fragile | `EUI_Bags` is global, `EUI_Bags.Header` is set in `CreateHeader()`. That is not an official API and may change with EUI updates. |
| Showing other characters **directly in the EUI bag** (character switcher as in Baganator) | **No, not without a core change** | `EUI_Bags:RefreshInventory()` calls `C_Container.*` directly. The slots are secure `ContainerFrameItemButtonTemplate` buttons on real bag slots, and the search runs through the client-global `C_Container.SetItemSearch`. Offline data cannot be fed in there. |

It follows that **the browser is its own window** that matches EUI visually. Anyone who wants the display directly in the bag needs an upstream PR with a data abstraction later. The maintainer would very likely reject it because of its size and taint risk (see phase 8).

### Integration points in EllesmereUI

| Integration point | Status | Use |
|---|---|---|
| `EllesmereUI.RegisterSkin(name, fn)` | **official**, `apiVersion = 1`, meant to only grow | shell, panel, button, edit box, scroll bar, tab for the browser window |
| `EllesmereUI.ShowWidgetTooltip` / `HideWidgetTooltip` | internal, required by CONTRIBUTING | tooltips for our own buttons |
| `EllesmereUI:ShowConfirmPopup` | internal, required by CONTRIBUTING | "Delete character data?" |
| `EllesmereUI.GetFontPath("bags")`, `GetFontOutlineFlag`, `EllesmereUI.L` | internal | same font and translation as the bag |
| `EUI_Bags` (global frame), `EUI_Bags.Header`, `EUI_Bags._searchBox` | internal | optional header button, optionally take over the search text |
| `EllesmereUI._ModuleNS["EllesmereUIBags"]` (module `ns`) | internal, marked with `_` | `ns.SkinItemButton`, `ns.CreateInsetBorder`, `ns.AttachGridScrollbar` for an identical slot look |
| `_G.EUI_CategoryManager:ClassifyItem(link, id, nil, nil)` | internal | sort offline items into the same categories as the bag. The function only needs `bag`/`slot` for quest info, so `nil` is harmless. |
| `EllesmereUIDB.characterGold`, `EllesmereUIDB.warbandGold` | internal, EUI already tracks gold per character (`enableGoldTracking`, on by default) | read only, as a fallback or for cross-checks. Our own gold tracking stays the source. |

**Rule:** everything except `RegisterSkin` is used through feature detection (`if EUI_Bags and EUI_Bags.Header then ... end`). If something is missing, the addon silently falls back to its own look. It must never raise a Lua error.

---

## 2. The acceptance criteria from `.github/CONTRIBUTING.md`

The repository has no README. The five acceptance criteria are in `.github/CONTRIBUTING.md`. Strictly speaking they only apply to PRs into the EUI repository. The addon follows them anyway: that keeps it in the spirit of EUI, and parts or all of it can be offered upstream later.

| # | Criterion | Implementation in BagSync |
|---|---|---|
| 1 | **Zero cost unless enabled** | Every sub-feature (collector per data source, tooltip, header button, browser, guild bank) registers events and builds frames **only on first enable** (lazy). Disabling is followed by `UnregisterEvent`. The tooltip post-call cannot be unregistered. It is therefore only registered on the first enable and then checks a local boolean first. |
| 2 | **Zero behavior change without opt-in** | All settings default to **OFF**. Installing counts as opt-in only for collecting data, which changes nothing visible. Tooltip lines and the header button in the EUI bag only come after consent. At first login a `ShowConfirmPopup` asks "Enable tooltip and bag button?". |
| 3 | **Low cost when enabled** | Purely event-driven: `BAG_UPDATE` only marks `dirty[bagID] = true`, `BAG_UPDATE_DELAYED` then scans only the marked bags. No `OnUpdate`, no `C_Timer` as a logic gate. No table allocation per tooltip display: the lines come from a precomputed cache per itemID. The cache is invalidated for the affected IDs when data changes. |
| 4 | **Zero taint risk** | No secure templates. Browser slots use `ItemButtonTemplate` (not secure) or a plain `Button`. No writes to Blizzard or EUI frames: our own state lives in weak tables. Only `HookScript` and `hooksecurefunc`, never `SetScript` on foreign frames. Do not touch `ToggleAllBags` and friends, EUI replaces them already. No actions that trigger protected functions (using or moving items). The browser only offers display, shift-click to link and ctrl-click to try on through `HandleModifiedItemClick`. |
| 5 | **Midnight only** | TOC `## Interface: 120000, 120001, 120005, 120007, 120100` like EUI. Only current APIs (`C_Container`, `C_Bank`, `C_Item`, `C_TooltipInfo`, `C_CurrencyInfo`). No version gates, no legacy bank or reagent bank paths. `issecretvalue` is respected (see 5.3). |

Plus the code style rules from the same file: **Lua 5.1** (no `goto`), **ASCII only** in code, comments and strings, own UI through EUI's systems (see above), options in the `W:DualRow` style should they ever move into EUI's options.

---

## 3. Architecture

```
EUIBagSync/
  EUIBagSync.toc
  Core/
    Init.lua          -- ns, event dispatcher, enable/disable registry per feature
    DB.lua            -- saved variables, defaults, schema version, migrations
    Keys.lua          -- character key, realm/connected-realm handling, item key normalization
  Collect/
    Bags.lua          -- backpack + bags + reagent bag (BagIndex 0..5)
    Equipped.lua      -- equipment (slots 1..19)
    Bank.lua          -- character bank tabs + warband bank tabs
    Mail.lua          -- mailbox incl. expiry
    Currency.lua      -- currencies + gold
    Auctions.lua      -- (optional) own auctions
    GuildBank.lua     -- (optional, phase 2b) guild bank
  Index/
    ItemIndex.lua     -- itemKey -> { [charKey] = {bags=,bank=,mail=,...} }, incremental
  Tooltip/
    Tooltip.lua       -- AddTooltipPostCall, line cache, modifier gate
  UI/
    Skin.lua          -- RegisterSkin bridge, fallback look without EUI
    Browser.lua       -- main window
    CharList.lua      -- sidebar with characters/realms
    ItemGrid.lua      -- slot pool + grid rendering (offline)
    Search.lua        -- search across all characters
    HeaderButton.lua  -- button in EUI_Bags.Header (optional)
  Options/
    Options.lua       -- Blizzard Settings API + slash commands
  Locales/
    enUS.lua, deDE.lua
```

**TOC essentials:**

```
## Interface: 120000, 120001, 120005, 120007, 120100
## Title: EUI BagSync
## Notes: Cross-character inventory data, tooltips and browser for EllesmereUI Bags.
## OptionalDeps: EllesmereUI, EllesmereUIBags
## SavedVariables: EUIBagSyncDB
```

Only `OptionalDeps`, no hard dependency. Then collecting and the tooltip also work without EUI, and EUI loads first when present. A category feature is only used when `EUI_CategoryManager` exists. *(Later: EllesmereUI Bags became a hard dependency in 0.7.1.)*

**Storage location:** the data deliberately lives in its **own** saved variable (`EUIBagSyncDB`), not in `EllesmereUIDB`. EUI overwrites `db.profile` completely on a profile import (`ApplyProfileData`). Own keys in EUI's root would also end up in profile exports (EUI explicitly warns about the "PRIVATE_ADDON_KEYS leak class" in its code).

---

## 4. Data model

```lua
EUIBagSyncDB = {
  schema = 1,
  settings = {                  -- everything default OFF except the collector basics
    collect = { bags=true, equipped=true, bank=true, mail=true, currency=true,
                auctions=false, guildbank=false },
    tooltip = { enabled=false, modifier="none", showTotal=true, hideCurrent=false,
                realmScope="connected", showWarband=true, showGuild=false },
    ui      = { headerButton=false, useEUICategories=false, browserPos=nil },
    firstRunAsked = false,
  },
  chars = {
    ["Name-Realm"] = {
      class="MAGE", race="Human", faction="Alliance", level=80, guild="Foo-Realm",
      lastSeen=1790000000, money=12345678,
      bags     = { [bagID] = { size=36, [slot] = "i:12345:20" } },
      bank     = { [tabID] = { size=98, [slot] = "..." }, scannedAt=... },
      equipped = { [invSlot] = "..." },
      mail     = { scannedAt=..., items = { { "i:...:1", expires=... }, ... } },
      auctions = { scannedAt=..., items = { ... } },
      currency = { [currencyID] = quantity },
    },
  },
  warband = { money=..., bank = { [tabID] = {...} }, scannedAt=... },
  guilds  = { ["Guild-Realm"] = { tabs = {...}, scannedAt=... } },
}
```

**Item encoding (compact, memory-friendly):**

- Plain items: `"i:<itemID>:<count>"`.
- Items with relevant bonus IDs (gear, crafting quality): `"l:<itemString>:<count>"`. Only the item string, without colour codes.
- Battle pets (`battlepet:` links) and keystones as their own type, because they do not have normal itemID semantics.

*(Implemented as `"<itemID>,<count>[,<link>]"` per stack, since 0.8.0 packed into one string per container.)*

**Schema versioning:** `schema` plus migration functions in `DB.lua` (cf. EUI's `EllesmereUI_Migration.lua`). Unknown or broken entries are dropped on load instead of being taken over and crashing.

**Index (runtime, not persisted):** `ItemIndex[itemID] = { [charKey] = { bags=n, bank=n, mail=n, equipped=n, auctions=n } }` plus warband and guild. It is built lazily on the first tooltip or browser need, then incrementally. When bag X of character Y is rescanned, the addon subtracts the old contributions and adds the new ones. A full rebuild is not needed.

---

## 5. Implementation by area

### 5.1 Collectors

| Source | Readable when | Events / API |
|---|---|---|
| Bags (0-5) | always | `BAG_UPDATE` (mark dirty) -> `BAG_UPDATE_DELAYED` (scan). `C_Container.GetContainerNumSlots`, `C_Container.GetContainerItemInfo` (returns `itemID`, `hyperlink`, `stackCount`). |
| Equipment | always | `PLAYER_EQUIPMENT_CHANGED`, `GetInventoryItemLink("player", slot)` |
| Character bank tabs | **only at the banker** | `PLAYER_INTERACTION_MANAGER_FRAME_SHOW` with `Enum.PlayerInteractionType.Banker`, then `PLAYERBANKSLOTS_CHANGED` / `BAG_UPDATE` on `Enum.BagIndex.CharacterBankTab_*`. `C_Bank.FetchPurchasedBankTabData(Enum.BankType.Character)` for the tab list. |
| Warband bank | only at the banker, from any character | `Enum.BankType.Account`, `Enum.BagIndex.AccountBankTab_*`, `PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED`, gold via `C_Bank.FetchDepositedMoney(Enum.BankType.Account)` |
| Mail | only at the mailbox | `MAIL_SHOW`, `MAIL_INBOX_UPDATE`, `GetInboxHeaderInfo` (expiry), `GetInboxItemLink` / `GetInboxItem`. Plus note **our own sent mail to our own alts** (`MAIL_SEND_SUCCESS` + buffered attachments), so items "in transit" do not vanish. |
| Gold | always | `PLAYER_MONEY`, `GetMoney()` |
| Currencies | always | `CURRENCY_DISPLAY_UPDATE`, `C_CurrencyInfo.GetCurrencyListSize` / `GetCurrencyListInfo` |
| Auctions (opt.) | only at the AH | `OWNED_AUCTIONS_UPDATED`, `C_AuctionHouse.GetOwnedAuctions()` |
| Guild bank (opt.) | only at the guild bank, per tab | `PLAYER_INTERACTION_MANAGER_FRAME_SHOW` (GuildBanker), `GUILDBANKBAGSLOTS_CHANGED`, `GetGuildBankItemLink`, `GetGuildBankItemInfo`. Query every tab separately (`QueryGuildBankTab`), otherwise data is missing. |

Details:

- **Character key** `Name-Realm` only from `PLAYER_LOGIN` on, never cache a stub (EUI does the same in `BagsCharKey()`).
- **Realm scope** for the tooltip: `GetAutoCompleteRealms()` for connected realms, optionally a faction filter.
- **Mark stale data:** `scannedAt` per source. Browser and tooltip show e.g. "Bank: 12 days ago" in grey.
- **Current character in the tooltip:** a live value instead of a snapshot, via `C_Item.GetItemCount(itemID, includeBank, includeUses, includeReagentBank, includeAccountBank)`. Always current and costs no scan.

### 5.2 Tooltip

- One-time lazy registration: `TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItemTooltip)`.
- Flow in `OnItemTooltip(tooltip, data)`:
  1. `if not tooltipEnabled then return end` (criterion 1)
  2. only for `GameTooltip`, `ItemRefTooltip` and `ShoppingTooltip1/2`. Do not touch other addons' tooltips.
  3. itemID from `data.id`. Abort immediately on `issecretvalue(data.id)`.
  4. Modifier gate (`none | shift | ctrl | alt`), analogous to EUI's `spellIDModifier` pattern.
  5. Take the lines from the cache `lineCache[itemID]`. On a cache miss build them once: class-coloured character name, on the right "Bags 5, Bank 20, Mail 1", plus a warband line and the total.
  6. `tooltip:AddDoubleLine(...)` per line. The limit is configurable (e.g. max. 8 characters + "and N more").
- No allocation per display. The cache is only cleared for the affected itemIDs when the index changes.
- Coexistence: EUI itself appends item ID and stack lines via `AddTooltipPostCall` (`EllesmereUI.lua`, `ItemIDTooltipHook`). The order does not matter, since both only append lines.

### 5.3 Midnight specifics

- **Secret values:** Midnight marks certain values as "secret" in combat and instances. EUI checks this in its tooltip hook with `issecretvalue`. BagSync does the same, for every value from `data`. Computing with or comparing a secret value raises an error, and criterion 4 forbids that.
- **Bank:** since the bank rework (11.2) there are only tabs (`CharacterBankTab_*`, `AccountBankTab_*`), no separate reagent bank. Build no legacy paths.
- **Combat:** non-secure frames may be created and shown in combat. So the browser window also works in combat. The slot pool is still warmed up outside combat on the first open. The reason is performance, not taint.

### 5.4 Browser window

Built after Baganator's model ("Characters"/"Search everywhere"), looking like EUI:

- **Window:** own frame, skinned with `S.Shell(frame)`. Movable, position in `settings.ui.browserPos`. Closes with ESC via `tinsert(UISpecialFrames, "EUIBagSyncBrowser")`.
- **Sidebar on the left:** characters grouped by realm, class-coloured, with level, gold and "last seen". At the top the entries "All characters" and "Warband bank", optionally "Guild banks". A right click opens a menu with "Delete data" via `EllesmereUI:ShowConfirmPopup`. Built with `ns.CreateSidebarHeader` if available, otherwise in our own look.
- **Tabs at the top:** Bags | Bank | Equipment | Mail | Currencies | (Auctions).
- **Grid:** pool of `ItemButtonTemplate` buttons (not secure). Filled through `SetItemButtonTexture`, `SetItemButtonCount`, `SetItemButtonQuality`. Look via `ns.SkinItemButton(btn, { anchorIcon=true, flatHighlight=true })` if present. The function only works with methods and is therefore also suited for non-secure buttons. Still check compatibility in phase 5, otherwise fall back. Scroll bar via `ns.AttachGridScrollbar` or `S.ScrollBar`.
- **Categories (optional):** group offline items via `EUI_CategoryManager:ClassifyItem(link, itemID)`. Then the offline view looks like the bag. Without EUI there is a flat list, sorted by quality, type and name.
- **Item tooltip in the grid:** `GameTooltip:SetHyperlink(link)`. The BagSync tooltip hook then appends the character stock automatically. *(Later replaced by a private tooltip frame, see TODO section 13.)*
- **Clicks:** only `HandleModifiedItemClick(link)` (shift = chat link, ctrl = try on). No other actions.
- **Loading item data:** offline links may not be in the client cache. So `Item:CreateFromItemID(id):ContinueOnItemLoad(...)` or `ITEM_DATA_LOAD_RESULT`, only for visible slots, batched per render.

### 5.5 Search across all characters

- Input box in the browser (`S.EditBox`). Optionally the text can be taken over from `EUI_Bags._searchBox`. The hook runs via `HookScript("OnTextChanged")`, never via `SetScript`.
- **Own matching.** `C_Container.SetItemSearch` only works for live slots and would also filter the EUI bag, since the search is client-global.
  - Stage 1: name (substring, case-insensitive), itemID, quality (`q:epic`), type/subtype from `C_Item.GetItemInfoInstant`.
  - Stage 2 (optional): item level operators (`ilvl>=600`), binding, expansion (`C_Item.GetItemInfo` -> `expansionID`).
  - Stage 3 (optional, expensive): tooltip full text via `C_TooltipInfo.GetHyperlink`. Only on request, lazy and cached per link.
- **Result view "All characters":** one list per item: icon, name, total amount, below it the distribution over characters and locations. This matches Baganator's "Search everywhere".
- Search debounced via Enter or `OnTextChanged` with a minimum length of 2 instead of a timer (criterion 3).

### 5.6 Entry points

- `/bagsync` or `/bs` opens the browser. `/bs search <text>` opens the search directly. *(Implemented as `/alts`.)*
- **Header button in the EUI bag** (default OFF): after `EUI_Bags:HookScript("OnShow", ...)`, create our own button when `EUI_Bags.Header` first appears. Its parent is the header, anchored left of the sort button. The button gets its own icon in `Media/` and its tooltip via `EllesmereUI.ShowWidgetTooltip`. Nothing is written onto the header frame.
- Optional LibDataBroker launcher (minimap/broker). Bundle LibDataBroker ourselves, do not rely on EUI's `Libs`.

### 5.7 Options

- EUI offers **no public API for option pages of third-party addons**. The options live in the load-on-demand addon `EllesmereUIOptions`; externally there are only `RegisterSkin` and `RegisterExternalInstaller`.
- Therefore our own page through the Blizzard **Settings API** (`Settings.RegisterVerticalLayoutCategory` or a canvas with our own widgets in EUI's style), plus slash commands.
- Settings: data sources individually on/off, tooltip (on/off, modifier, realm scope, hide current character, total, max. lines), header button, use EUI categories, delete character data, reset everything.
- First run: a one-time `ShowConfirmPopup` (or an own popup without EUI) asking whether tooltip and bag button should be enabled. The answer is stored in `firstRunAsked`.

---

## 6. Phases and milestones

| Phase | Content | Result / acceptance |
|---|---|---|
| **0. Setup** | repository, TOC, folder structure, symlink into `_retail_/Interface/AddOns/EUIBagSync`, `luacheck` with WoW globals, ASCII check (pre-commit), BugGrabber+BugSack, `.pkgmeta` for the BigWigs packager (CurseForge/Wago) | addon loads without errors, `/bs` answers |
| **1. Core collectors** | DB + schema, character meta, bags, equipment, gold. Dirty bag scan via `BAG_UPDATE_DELAYED` | after a relog onto an alt the main's data in the saved variable is correct |
| **2. More sources** | character bank, warband bank, mail (incl. sent mail), currencies. (2b optional: auctions, guild bank) | bank and mail are captured correctly at the NPC, `scannedAt` is right |
| **3. Index + tooltip** | item index (incremental), tooltip post-call, line cache, modifier, realm scope, live count for the current character | tooltip shows correct totals; with the tooltip disabled not a single line is appended |
| **4. Browser** | window, character sidebar, tabs, item grid with pool, loading item data, search stage 1, "All characters" view | every character and location searchable, shift-click links |
| **5. EUI integration** | `RegisterSkin`, EUI fonts and accent colour, `ns.SkinItemButton`, header button, EUI categories, taking over the search text. Everything behind feature detection | the browser looks like the EUI bag; with EUI disabled or missing everything keeps working |
| **6. Options + opt-in** | settings page, first-run popup, data deletion, localization enUS/deDE | all features off by default, individually switchable |
| **7. Hardening** | taint test (see below), combat and instance test, measure performance and memory, test with an EUI update | the checklist in section 7 is fully green |
| **8. (optional) Upstream** | talk to Ellesmere on Discord about **small extension hooks** instead of submitting a feature | see below |

### Phase 8: what could be proposed upstream

According to CONTRIBUTING, larger features should be agreed in advance by Discord DM with @ellesmere. Realistic is not the whole sync but only a minimal, free extension API that makes the companion addon more robust:

- `EUI_Bags:RegisterHeaderButton(key, opts)`: an official place for a third-party button instead of guessing anchors.
- `EllesmereUI.Bags.SkinItemButton` as a stable public export of today's `ns.SkinItemButton`.
- Optionally a callback after `RefreshInventory`, should an overlay ever be needed.

All of it costs nothing as long as nobody calls it, changes no behaviour and carries no taint risk. It thus meets all five criteria and is small enough to stand a chance.

---

## 7. Test and acceptance checklist

**Functional**
- [ ] Two or more characters on the same realm and on connected realms: tooltip totals are right
- [ ] Bank and warband bank are only updated at the NPC; otherwise the old state stays with its timestamp
- [ ] Mail to an own alt appears immediately as "in transit", after pickup in its bags
- [ ] Deleting or renaming a character: data can be removed, the index rebuilds correctly
- [ ] Battle pets, keystones and crafting qualities are shown and counted correctly

**Criteria 1 and 2**
- [ ] Fresh install: no tooltip line, no header button until the user agrees
- [ ] Disabled feature: `/etrace` shows no events of BagSync's frames for that feature
- [ ] No browser frame exists before it is opened for the first time (checked with `/fstack` or by frame name)

**Criterion 3**
- [ ] No `OnUpdate`, no `C_Timer` in the logic (code grep as a CI check)
- [ ] Measure CPU via `C_AddOnProfiler` or the client's addon profiling: bag changes, loot spam, tooltip hover
- [ ] Measure memory with 20 or more characters (`UpdateAddOnMemoryUsage` / `GetAddOnMemoryUsage`), check the size of the saved variable

**Criterion 4**
- [ ] `/console taintLog 2`, then combat, M+, bank, opening bags, using items, opening the browser in combat: no BagSync entries in `taint.log`, no `ADDON_ACTION_FORBIDDEN`/`BLOCKED`
- [ ] Tooltip in instances and in combat: no errors from secret values
- [ ] EUI disabled, EUI Bags disabled, EUI updated to a new version: no Lua errors, clean fallback

**Criterion 5 and style**
- [ ] No legacy APIs (global `GetContainerItemInfo`, `ReagentBank*` etc.) by grep
- [ ] Only ASCII in all `.lua` files (`LC_ALL=C grep -nP '[^\x00-\x7F]'` finds nothing)
- [ ] Lua 5.1: `luacheck --std lua51`

---

## 8. Risks

| Risk | Impact | Countermeasure |
|---|---|---|
| EUI changes internal fields (`EUI_Bags.Header`, `ns.*`, `EUI_CategoryManager`) | header button, look or categories fail | feature detection, `pcall` around optional calls with a fallback, tests against every new EUI version. Long term the hooks from phase 8 |
| Blizzard changes bank or mail APIs | a source returns nothing | isolate the collector per source; one failure must not block other sources |
| Secret values extend to item data | tooltip errors | an `issecretvalue` guard throughout; when in doubt append nothing in combat and instances |
| Large accounts (50+ characters, full guild banks) | saved variable size, login time | compact encoding, lazy index, guild bank optional and switchable per guild |
| Overlap with Baganator, Syndicator or BagSync (the original) | duplicate tooltip lines | tooltip off by default; detect Syndicator or BagSync at first run and point it out to the user |
| Name conflict | "BagSync" is an existing addon | pick the final name before release (e.g. "EllesmereUI Bags: Alts" or "EUI Warband Ledger") |

---

## 9. Rough effort

| Phase | Effort (experienced WoW addon developer) |
|---|---|
| 0-1 | 1-2 days |
| 2 (without 2b) | 1-2 days |
| 3 | 1-2 days |
| 4 | 3-5 days (the UI is the biggest block) |
| 5 | 1-2 days |
| 6 | 1 day |
| 7 | 2-3 days |
| **Total MVP** | **approx. 2-3 weeks part-time** |

MVP proposal: deliver phases 0-3 first (collecting and tooltip). That already brings about 70 % of the benefit of Baganator or Syndicator for alts. The browser and EUI's look follow in the second release.
