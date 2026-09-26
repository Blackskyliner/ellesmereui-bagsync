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
- [ ] TOC, Init/Event-Dispatcher, Feature-Registry (lazy enable/disable)
- [ ] DB + Defaults + Schema/Migration
- [ ] Keys (Char-Key, Realm-Scope, Item-Kodierung)

## 3. Collector
- [ ] Taschen (Dirty-Scan), Ausrüstung, Gold, Char-Meta
- [ ] Charakter-Bank + Warband-Bank
- [ ] Post (Posteingang + versendete Post an eigene Alts)
- [ ] Währungen
- [ ] Gildenbank

## 4. Index + Tooltip
- [ ] ItemIndex inkrementell
- [ ] Tooltip-Hook, Zeilen-Cache, Modifier, Realm-Scope, Live-Count

## 5. Connector / Erweiterungs-API (upstream-fähig)
- [ ] EUIBagsExt-Schicht: Skin, Fonts, Akzent, Tooltip-/Popup-Helper, SkinItemButton, ClassifyItem
- [ ] RegisterHeaderButton (Shim + Upstream-Form)

## 6. UI
- [ ] Browser-Fenster, Char-Sidebar, Tabs
- [ ] Item-Grid (Pool, nicht secure), Item-Daten nachladen
- [ ] Suche über alle Chars + Ergebnisansicht
- [ ] Header-Button

## 7. Optionen + Opt-in
- [ ] Settings-Seite, Slash-Commands, Erststart-Popup, Daten löschen
- [ ] Lokalisierung enUS/deDE (ASCII-escaped)

## 8. Tests
- [ ] WoW-API-Mock-Umgebung (Frames, Events, APIs)
- [ ] Unit-Tests Keys/DB/Index
- [ ] Integrationstests Collector, Tooltip, UI, Optionen
- [ ] Kriterien-Tests (keine Events/Frames im Aus-Zustand, kein OnUpdate/C_Timer)
- [ ] Contract-Tests gegen echten EllesmereUI-Quellcode
- [ ] luacheck, ASCII-Check, Lua-5.1-Syntax
- [ ] In-Game-Selbsttest (/alts selftest)

## 9. Abschluss
- [ ] README (Installation, Ingame-Testanleitung)
- [ ] Paket-Zip
- [ ] PLAN.md aktualisieren
