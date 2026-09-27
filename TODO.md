# Arbeits-Checkliste: EllesmereUIBags_Alts

Entscheidungen (2026-09-26): Name `EllesmereUIBags_Alts`, nur lokales Git (Feature-Branch,
Commits in funktionalen Gruppen), Tools nur projektlokal (`.tools/`), Umfang MVP +
Header-Button + Gildenbank. Keine Auktionen, kein LDB/Minimap.

## 0. Setup
- [x] Git-Repo, .gitignore, Checkliste
- [x] Lua 5.1 projektlokal gebaut
- [x] LuaRocks projektlokal, busted + luacheck
- [x] Referenzen: wow-ui-source (Blizzard API-Doku), Ketho vscode-wow-api, EllesmereUI-Quellcode
- [x] Headless-Emulator: wowless nur per Docker (verworfen); wow-ui-sim (Osso) nativ gebaut, lädt Blizzard UI 12.1.0

## 1. API-Recherche (gegen wow-ui-source verifizieren)
- [x] C_Container / Enum.BagIndex (Taschen, Bank-Tabs, Warband-Tabs)
- [x] C_Bank (Tab-IDs, Geld), PlayerInteractionType
- [x] Mail-API, Gildenbank-API
- [x] C_CurrencyInfo, Inventar-Slots, C_Item.GetItemCount
- [x] TooltipDataProcessor, Settings API, ItemButton, issecretvalue

## 2. Addon-Kern
- [x] TOC, Init/Event-Dispatcher, Feature-Registry (lazy enable/disable)
- [x] DB + Defaults + Schema/Migration
- [x] Keys (Char-Key, Realm-Scope, Item-Kodierung)

## 3. Collector
- [x] Taschen (Dirty-Scan), Ausrüstung, Gold, Char-Meta
- [x] Charakter-Bank + Warband-Bank
- [x] Post (Posteingang + versendete Post an eigene Alts)
- [x] Währungen
- [x] Gildenbank

## 4. Index + Tooltip
- [x] ItemIndex inkrementell
- [x] Tooltip-Hook, Zeilen-Cache, Modifier, Realm-Scope, Live-Count

## 5. Connector / Erweiterungs-API (upstream-fähig)
- [x] EUIBagsExt-Schicht: Skin, Fonts, Akzent, Tooltip-/Popup-Helper, SkinItemButton, ClassifyItem
- [x] RegisterHeaderButton (Shim + Upstream-Form)

## 6. UI
- [x] Browser-Fenster, Char-Sidebar, Tabs
- [x] Item-Grid (Pool, nicht secure), Item-Daten nachladen
- [x] Suche über alle Chars + Ergebnisansicht
- [x] Header-Button

## 7. Optionen + Opt-in
- [x] Settings-Seite, Slash-Commands, Erststart-Popup, Daten löschen
- [x] Lokalisierung enUS/deDE (ASCII-escaped)

## 8. Tests
- [x] WoW-API-Mock-Umgebung (Frames, Events, APIs)
- [x] Unit-Tests Keys/DB/Index
- [x] Integrationstests Collector, Tooltip, UI, Optionen
- [x] Kriterien-Tests (keine Events/Frames im Aus-Zustand, kein OnUpdate/C_Timer)
- [x] Contract-Tests gegen echten EllesmereUI-Quellcode
- [x] luacheck, ASCII-Check, Lua-5.1-Syntax
- [x] In-Game-Selbsttest (/alts selftest)

## 9. Abschluss
- [x] README (Installation, Ingame-Testanleitung)
- [x] Paket-Zip
- [x] PLAN.md aktualisieren

## 10. Zusätzlich erledigt
- [x] Öffentliche API `EllesmereUIBagsAlts` (GetItemCount, GetCharacters, ...)
- [x] wow-ui-sim-Integrationstests: mit EUI, ohne EUI und mit gepatchtem EUI (Upstream-API)
- [x] Upstream-Vorschlag `upstream/` (Drop-in-Datei, Patch, Begründung gegen die fünf Kriterien)
- [x] Härtung: Gildenbank-Fremdevents, Erststart ohne Popup-Kollision, kein HideUIPanel, Tooltip-ID-Fallback
- [x] Layout-Prüfung über den dump-tree des Simulators (echter Anker-Solver)

## 11. Auktionshaus-Tracking (0.2.0)
- [x] API gegen 12.1-Doku (GetOwnedAuctions, OwnedAuctionInfo, AuctionStatus, TimeLeftBand, Events)
- [x] Collector: passiv (OWNED_AUCTIONS_UPDATED), Opt-in-Abfrage, nur vollständige Ergebnisse, nur aktive Auktionen
- [x] Abgebrochen/abgelaufen → „Post unterwegs“, Ablauf-Pruning beim Login
- [x] Index, Tooltip, Browser-Tab, Optionen, Selbsttest, Locales (10 Sprachen)
- [x] Tests: busted (Mock C_AuctionHouse), Simulator (echte C_AuctionHouse-Oberfläche, Kampf/Taint)
- [x] 0.2.1: Eingestellte Auktionen sofort (Post-Hooks + AUCTION_HOUSE_AUCTION_CREATED, Bestätigung, Multisell)
- [x] 0.2.1: Abbruch robust per ID in die Post, Ablauf beim Login in die Post

## Offen (braucht den echten Client)
- [ ] Ingame-Testplan aus README.md durchgehen (Bank, Post, Auktionen, Gildenbank, Kampf/Instanz, taint.log)
