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
- [x] 0.3.0: Abbruch über CancelAuction-Hook + Warteschlange (live: AUCTION_CANCELED liefert „1“, keine ID), Fallback per Fehlen in der Liste, seitenweise Liste wie Blizzard
- [x] 0.3.0: Verkauft → „Post → Verkauft“ mit Betrag (Benachrichtigung überall, Liste „Verkauft“, Diff, Commodity-Teilverkäufe)
- [x] 0.3.0: Stückpreise, „Im Auktionshaus“-Summe im Auktionen-Footer, „Gold in der Post“ im Post-Footer
- [x] 0.3.0: /alts debug

## 12. Währungs-Kategorien (0.4.0)
- [x] Charaktergebunden / Überweisbar (+ Kriegsmeutenweit, nur wenn vorhanden)
- [x] Art accountweit gemerkt (db.currencyMeta) für Offline-Charaktere
- [x] Locales, Tests

## 13. Bindung und Ausrüstungssets (0.4.0)
- [x] Bindungsstatus pro Item (seelen-/kriegsmeutengebunden, Marker in der Kodierung, rückwärtskompatibel)
- [x] Browser-Tooltip über ProcessInfo mit linePreCall (Bindungszeile) und tooltipPostCall (Sets)
- [x] Ausrüstungssets pro Taschen-/Angelegt-Slot (C_EquipmentSet + EquipmentManager_GetLocationData)
- [x] Eigener Tooltip-Frame für den Browser (kein Taint auf GameTooltip)

## 14. Übersichten und Währungs-Tooltip (0.6.0, Tab „Alles“ pro Charakter 0.6.1)
- [x] Seitenleiste: „Alle Charaktere“ und anklickbare Realm-Überschriften
- [x] Zusammengefasste Items (Link bzw. itemID), gruppiert nach Gegenstandsklasse/EUI-Kategorie, Tab „Alles“
- [x] Tab „Alles“ auch für einzelne Charaktere (alle Orte des Charakters zusammengefasst)
- [x] Besitzer-Zeilen im Browser-Tooltip der Übersichten (unabhängig von der Tooltip-Option, ohne Doppelung)
- [x] Währungen: Summen in den Übersichten, Tooltip mit Aufteilung pro Charakter
- [x] Locales, busted- und Simulator-Tests

## 15. Fensterkopf und Währungssuche (0.6.2)
- [x] Titel, Suche und Schließen-Button zentriert in EUIs 25-px-Titelleiste
- [x] Schließen-Button relativ zum Fenster gelevelt (Template setzt absolut 510), Fenster ist Toplevel
- [x] Suche findet Währungen (Summe, Bestände pro Charakter, Tooltip, Chat-Link)

## 16. Layout- und Visual-Regression-Tests
- [x] wow-ui-sim zusätzlich mit GPU-Renderer (`target-gui/`), Python-venv mit Pillow
- [x] Fixture mit drei Charakteren, zwei Realms, Kriegsmeuten- und Gildenbank
- [x] Layout-Invarianten in jeder Browser-Ansicht (`sim/.../10_layout.lua`), Gegenprobe mit altem Kopf-Layout
- [x] Screenshots von 11 Szenarien in zwei Modi, Vergleich mit Referenzbildern, Diff-Bilder und HTML-Bericht
- [x] Gefunden und behoben: Qualitätsrahmen der ersten Grid-Spalte im Fallback-Look um 1,5 px abgeschnitten

## 17. Gildenbank-Scan (0.6.4)
- [x] Fächerliste kommt beim ersten Besuch einer Sitzung erst mit GUILDBANK_UPDATE_TABS: Warteschlange von dort nachfüllen
- [x] Gespeicherte Fächer nicht mehr löschen, solange der Client 0 Fächer meldet
- [x] Offener Browser zeigt die Gilde sofort nach dem Öffnen der Gildenbank
- [x] Debug-Ausgaben (`/alts debug`) für den Ablauf

## 18. Aktivierung bei erster Benutzung (0.7.0)
- [x] Login: nur Auslöser (EUI-Taschenfenster, ein NPC-Event, Browser, API, Tooltip bei aktiver Option), kein Scan, keine Datenprüfung
- [x] Aktivierung genau einmal pro Sitzung, danach Collector event-getrieben; auslösendes NPC-Fenster wird im selben Besuch erfasst
- [x] Keine Hooks an Blizzards Taschen (Taint), EUI Bags ist Voraussetzung
- [x] Keine Rescans bei Ladebildschirmen, Taschenwechsel über BAG_CONTAINER_UPDATE
- [x] `/alts status` zeigt die Aktivierung

## 19. EllesmereUI Bags als Abhängigkeit (0.7.1)
- [x] TOC `## Dependencies: EllesmereUIBags` (Standalone-Bags genügt), inert auf EUI_CLIENT_BLOCKED-Clients
- [x] Standalone-Ballast entfernt: Ersatz-Popup, GameTooltip-Fallback, No-EUI-Zweige, No-EUI-Tests, Simulator-Modus `noeui`
- [x] Bleibt: schlichte Optik ohne EUIs Blizzard-Skin-Modul, Drift-Schutz im Connector (fehlende EUI-Funktion -> leise)
- [x] Simulator-Modus `skin` (EUI-Kern + Bags + BlizzardSkin); Visual nur `bags` (Simulator-Fehler bei Objekt-Hooks, festgehalten)

## Offen (braucht den echten Client)
- [ ] Ingame-Testplan aus README.md durchgehen (Bank, Post, Auktionen, Gildenbank, Kampf/Instanz, taint.log)
