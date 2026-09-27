# Work checklist: EllesmereUIBags_Alts (archived)

> **Archived.** This is the development checklist as it stood at version 0.8.0,
> translated from German. It is kept as a record of how the addon was built;
> the current state is described in the [README](../../README.md) and the
> rules for further work in [CONTRIBUTING.md](../../CONTRIBUTING.md).

Decisions (2026-09-26): name `EllesmereUIBags_Alts`, local git only (feature
branches, commits in functional groups), tools project-local only (`.tools/`),
scope MVP + header button + guild bank. No auctions, no LDB/minimap. (Auction
tracking was added later, see section 11.)

## 0. Setup
- [x] Git repository, .gitignore, checklist
- [x] Lua 5.1 built project-locally
- [x] LuaRocks project-locally, busted + luacheck
- [x] References: wow-ui-source (Blizzard API docs), Ketho vscode-wow-api, EllesmereUI source
- [x] Headless emulator: wowless only via Docker (rejected); wow-ui-sim (Osso) built natively, loads Blizzard UI 12.1.0

## 1. API research (verified against wow-ui-source)
- [x] C_Container / Enum.BagIndex (bags, bank tabs, warband tabs)
- [x] C_Bank (tab IDs, money), PlayerInteractionType
- [x] Mail API, guild bank API
- [x] C_CurrencyInfo, inventory slots, C_Item.GetItemCount
- [x] TooltipDataProcessor, Settings API, ItemButton, issecretvalue

## 2. Addon core
- [x] TOC, init/event dispatcher, feature registry (lazy enable/disable)
- [x] DB + defaults + schema/migration
- [x] Keys (character key, realm scope, item encoding)

## 3. Collectors
- [x] Bags (dirty scan), equipped gear, gold, character meta
- [x] Character bank + warband bank
- [x] Mail (inbox + sent mail to own alts)
- [x] Currencies
- [x] Guild bank

## 4. Index + tooltip
- [x] Incremental item index
- [x] Tooltip hook, line cache, modifier, realm scope, live count

## 5. Connector / extension API (upstreamable)
- [x] EUIBagsExt layer: skin, fonts, accent, tooltip/popup helpers, SkinItemButton, ClassifyItem
- [x] RegisterHeaderButton (shim + upstream form)

## 6. UI
- [x] Browser window, character sidebar, tabs
- [x] Item grid (pool, not secure), loading item data
- [x] Search across all characters + result view
- [x] Header button

## 7. Options + opt-in
- [x] Settings page, slash commands, first-run popup, data deletion
- [x] Localization enUS/deDE (ASCII-escaped at the time; later UTF-8 in all ten EUI locales)

## 8. Tests
- [x] WoW API mock environment (frames, events, APIs)
- [x] Unit tests keys/DB/index
- [x] Integration tests collectors, tooltip, UI, options
- [x] Criteria tests (no events/frames while off, no OnUpdate/C_Timer)
- [x] Contract tests against the real EllesmereUI source
- [x] luacheck, ASCII check, Lua 5.1 syntax
- [x] In-game self-test (`/alts selftest`)

## 9. Wrap-up
- [x] README (installation, in-game test guide)
- [x] Package zip
- [x] Update PLAN.md

## 10. Done in addition
- [x] Public API `EllesmereUIBagsAlts` (GetItemCount, GetCharacters, ...)
- [x] wow-ui-sim integration tests: with EUI, without EUI and with patched EUI (upstream API)
- [x] Upstream proposal `upstream/` (drop-in file, patch, rationale against the five criteria)
- [x] Hardening: foreign guild bank events, first run without popup collision, no HideUIPanel, tooltip ID fallback
- [x] Layout check via the simulator's dump-tree (real anchor solver)

## 11. Auction house tracking (0.2.0)
- [x] API against the 12.1 docs (GetOwnedAuctions, OwnedAuctionInfo, AuctionStatus, TimeLeftBand, events)
- [x] Collector: passive (OWNED_AUCTIONS_UPDATED), opt-in query, only complete results, only active auctions
- [x] Cancelled/expired -> "mail in transit", expiry pruning at login
- [x] Index, tooltip, browser tab, options, self-test, locales (10 languages)
- [x] Tests: busted (mock C_AuctionHouse), simulator (real C_AuctionHouse surface, combat/taint)
- [x] 0.2.1: posted auctions appear immediately (post hooks + AUCTION_HOUSE_AUCTION_CREATED, confirmation, multisell)
- [x] 0.2.1: cancellation moves the item to mail reliably by ID, expiry at login moves it to mail
- [x] 0.3.0: cancellation via CancelAuction hook + queue (live: AUCTION_CANCELED passes "1", no ID), fallback by absence from the list, paged list like Blizzard's
- [x] 0.3.0: sold -> "Mail -> Sold" with amount (notification anywhere, "Sold" list, diff, partial commodity sales)
- [x] 0.3.0: unit prices, "On the auction house" total in the auctions footer, "Gold in mail" in the mail footer
- [x] 0.3.0: `/alts debug`

## 12. Currency categories (0.4.0)
- [x] Character-bound / transferable (+ warband-wide, only when present)
- [x] Kind remembered account-wide (db.currencyMeta) for offline characters
- [x] Locales, tests

## 13. Bound state and equipment sets (0.4.0)
- [x] Bound state per item (soulbound/warbound, marker in the encoding, backwards compatible)
- [x] Browser tooltip via ProcessInfo with linePreCall (binding line) and tooltipPostCall (sets)
- [x] Equipment sets per bag/worn slot (C_EquipmentSet + EquipmentManager_GetLocationData)
- [x] Own tooltip frame for the browser (no taint on GameTooltip)

## 14. Overviews and currency tooltip (0.6.0, per-character "Everything" tab 0.6.1)
- [x] Sidebar: "All characters" and clickable realm headers
- [x] Merged items (link or itemID), grouped by item class/EUI category, "Everything" tab
- [x] "Everything" tab for single characters too (all locations of the character merged)
- [x] Owner lines in the browser tooltip of the overviews (independent of the tooltip option, no duplicates)
- [x] Currencies: totals in the overviews, tooltip with per-character breakdown
- [x] Locales, busted and simulator tests

## 15. Title row and currency search (0.6.2)
- [x] Title, search and close button centred in EUI's 25 px title bar (superseded in 0.7.2)
- [x] Close button levelled relative to the window (the template pins 510), window is toplevel
- [x] Search finds currencies (total, per-character amounts, tooltip, chat link)

## 16. Layout and visual regression tests
- [x] wow-ui-sim additionally with the GPU renderer (`target-gui/`), Python venv with Pillow
- [x] Fixture with three characters, two realms, warband and guild bank
- [x] Layout invariants in every browser view (`sim/.../10_layout.lua`), counter-check with the old title layout
- [x] Screenshots of 11 scenarios, comparison with baselines, diff images and HTML report
- [x] Found and fixed: quality border of the first grid column clipped by 1.5 px in the fallback look

## 17. Guild bank scan (0.6.4)
- [x] The tab list arrives with GUILDBANK_UPDATE_TABS on the first visit of a session: refill the queue from there
- [x] Stored tabs are no longer wiped while the client reports 0 tabs
- [x] An open browser shows the guild as soon as the guild bank opens
- [x] Debug output (`/alts debug`) for the walk

## 18. Activation on first use (0.7.0)
- [x] Login: only triggers (EUI bag window, one NPC event, browser, API, tooltip when enabled), no scan, no data check
- [x] Activation exactly once per session, then event-driven collectors; the NPC window that triggered it is read in the same visit
- [x] No hooks on Blizzard's bags (taint), EUI Bags is a requirement
- [x] No rescans on loading screens, bag swaps via BAG_CONTAINER_UPDATE
- [x] `/alts status` shows the activation

## 19. EllesmereUI Bags as a dependency (0.7.1)
- [x] TOC `## Dependencies: EllesmereUIBags` (standalone Bags suffices), inert on EUI_CLIENT_BLOCKED clients
- [x] Standalone ballast removed: fallback popup, GameTooltip fallback, no-EUI branches, no-EUI tests, simulator mode `noeui`
- [x] Kept: plain look without EUI's Blizzard skin module, drift guards in the connector (missing EUI function -> quiet)
- [x] Simulator mode `skin` (EUI core + Bags + BlizzardSkin); visual tests `bags` only (simulator bug with object hooks, pinned by a test)

## 20. Header like EUI Bags (0.7.2)
- [x] 35 px header with EUI Bags' metrics (title 13/8 px, grey subtitle 11, search 22 px, EUI close glyph 12 px, separator)
- [x] EUI skin without its own 25 px title bar (noTopBar), search box without skin in the style of the bag search (PanelPP border)

## 21. Compact storage format (0.8.0)
- [x] One packed string per container (`slot:enc;...`), index and diff directly on the string
- [x] Item links only as their `item:` core (pet and keystone links whole), name/chat link from the item cache
- [x] Idempotent conversion of old data in the data check on activation
- [x] Tests: format, conversion, links from the core, SV size (20 characters, 150/300/300)

## In-game validation
- [x] In-game test plan from the README (bank, mail, auctions, guild bank, combat/instance, taint.log): validated in the game by the maintainer
