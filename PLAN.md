# EUI BagSync: Plan

> **Umsetzungsstand (2026-09-26):** umgesetzt als `EllesmereUIBags_Alts` (Version 0.1.0).
> Details, Installation und Ingame-Testplan stehen in [README.md](README.md), die Arbeits-Checkliste in [TODO.md](TODO.md).
>
> Abweichungen vom ursprünglichen Plan:
> - **Name:** `EllesmereUIBags_Alts` (Titel „EllesmereUI Bags: Alts“), SavedVariable `EllesmereUIBagsAltsDB`.
> - **Umfang:** ohne LDB/Minimap-Button. Header-Button und Gildenbank sind drin (beide Opt-in). Eigene Auktionen kamen in 0.2.0 dazu: standardmäßig passiv, eine aktive Abfrage ist Opt-in.
> - **Erststart-Frage:** Mit EUI kommt sie erst beim ersten Öffnen der Tasche. EUI zeigt beim Login eigene Popups über denselben Dialog.
> - **Settings-Button:** öffnet den Browser über dem Settings-Panel und schließt das Panel nicht (kein `HideUIPanel` aus Addon-Code, wegen Taint-Gefahr).
> - **Gildenbank:** Jedes Slots-Event liest alle bisher angefragten Fächer neu, weil das Event nicht sagt, welches Fach geantwortet hat.
> - **Tooltip:** nur `GameTooltip` und `ItemRefTooltip`, keine Vergleichs-Tooltips. Die Item-ID kommt aus `data.id`, sonst aus Hyperlink oder GUID.
> - **Zusätzlich:** öffentliche API `EllesmereUIBagsAlts`, In-Game-Selbsttest `/alts selftest`, Upstream-Drop-in `upstream/EllesmereUIBags_ExtAPI.lua` samt Patch.
> - **Tests:** projektlokale Toolchain mit busted-Mock und API-Check gegen Blizzards 12.1-Quellen, dazu der Headless-Simulator [wow-ui-sim](https://github.com/Osso/wow-ui-sim) mit echtem FrameXML und echtem EllesmereUI.

Ein eigenständiges Companion-Addon für **EllesmereUI Bags**. Es sammelt Inventardaten über alle Charaktere, speichert sie accountweit, zeigt sie optional im Item-Tooltip und bietet ein Browser-Fenster über alle Charaktere, ähnlich wie Baganator.

Stand der Analyse: EllesmereUI `main`, Bags-Modul v9.2.9 (Interface 120000–120100, Midnight 12.1+).

---

## 1. Machbarkeit: Ergebnis

**Ja, das geht als eigenes Addon, ohne Änderung am EllesmereUI-Code.** Eine Einschränkung gibt es aber:

| Funktion | Als eigenes Addon machbar? | Begründung |
|---|---|---|
| Daten sammeln und speichern | Ja, vollständig | Reine WoW-API (`C_Container`, `C_Bank`, Mail, Equipment). Kein EUI-Code nötig. |
| Tooltip mit Beständen aller Chars | Ja, vollständig | `TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, ...)`. EUI nutzt denselben Mechanismus selbst, beides läuft nebeneinander. |
| Eigenes Browser-Fenster im EUI-Look | Ja | Offizielle API `EllesmereUI.RegisterSkin` (siehe `SKINNING_API.md`), dazu Fonts und Akzentfarbe über EUI-Helper. |
| Button im Header der EUI-Tasche | Ja, aber fragil | `EUI_Bags` ist global, `EUI_Bags.Header` wird bei `CreateHeader()` gesetzt. Das ist keine offizielle API und kann sich mit EUI-Updates ändern. |
| Andere Chars **direkt in der EUI-Tasche** anzeigen (Char-Umschalter wie in Baganator) | **Nein, nicht ohne Core-Änderung** | `EUI_Bags:RefreshInventory()` ruft `C_Container.*` direkt auf. Die Slots sind secure `ContainerFrameItemButtonTemplate`-Buttons an echten Bag-Slots, und die Suche läuft über den client-globalen `C_Container.SetItemSearch`. Offline-Daten lassen sich dort nicht einspeisen. |

Daraus folgt: **Das Browser-Fenster ist ein eigenes Fenster**, das optisch zu EUI passt. Wer die Anzeige direkt in der Tasche will, braucht später einen Upstream-PR mit Daten-Abstraktion. Der Maintainer würde den wegen Größe und Taint-Risiko sehr wahrscheinlich ablehnen (siehe Phase 8).

### Andockpunkte in EllesmereUI

| Andockpunkt | Status | Nutzung |
|---|---|---|
| `EllesmereUI.RegisterSkin(name, fn)` | **offiziell**, `apiVersion = 1`, soll nur wachsen | Shell, Panel, Button, EditBox, ScrollBar, Tab für das Browser-Fenster |
| `EllesmereUI.ShowWidgetTooltip` / `HideWidgetTooltip` | intern, von CONTRIBUTING vorgeschrieben | Tooltips für eigene Buttons |
| `EllesmereUI:ShowConfirmPopup` | intern, von CONTRIBUTING vorgeschrieben | "Charakterdaten löschen?" |
| `EllesmereUI.GetFontPath("bags")`, `GetFontOutlineFlag`, `EllesmereUI.L` | intern | gleiche Schrift und Übersetzung wie die Tasche |
| `EUI_Bags` (global Frame), `EUI_Bags.Header`, `EUI_Bags._searchBox` | intern | optionaler Header-Button, optional Suchtext übernehmen |
| `EllesmereUI._ModuleNS["EllesmereUIBags"]` (Modul-`ns`) | intern, mit `_` markiert | `ns.SkinItemButton`, `ns.CreateInsetBorder`, `ns.AttachGridScrollbar` für identische Slot-Optik |
| `_G.EUI_CategoryManager:ClassifyItem(link, id, nil, nil)` | intern | Offline-Items in dieselben Kategorien sortieren wie die Tasche. `bag`/`slot` braucht die Funktion nur für Quest-Infos, `nil` ist also unkritisch. |
| `EllesmereUIDB.characterGold`, `EllesmereUIDB.warbandGold` | intern, EUI trackt Gold pro Char schon (`enableGoldTracking`, Default an) | nur lesen, als Fallback oder zum Abgleich. Eigenes Gold-Tracking bleibt die Quelle. |

**Regel:** Alles außer `RegisterSkin` wird per Feature-Detection genutzt (`if EUI_Bags and EUI_Bags.Header then ... end`). Fehlt etwas, fällt das Addon still auf eigene Optik zurück. Es darf nie einen Lua-Fehler werfen.

---

## 2. Die Acceptance Criteria aus `.github/CONTRIBUTING.md`

Das Repo hat keine README. Die fünf Acceptance Criteria stehen in `.github/CONTRIBUTING.md`. Streng genommen gelten sie nur für PRs ins EUI-Repo. Das Addon hält sie trotzdem ein: Dann bleibt es im Geist von EUI und kann später ganz oder teilweise upstream angeboten werden.

| # | Kriterium | Umsetzung in BagSync |
|---|---|---|
| 1 | **Zero cost unless enabled** | Jedes Teilfeature (Collector pro Datenquelle, Tooltip, Header-Button, Browser, Guild Bank) registriert Events und baut Frames **erst beim ersten Aktivieren** (lazy). Beim Deaktivieren folgt `UnregisterEvent`. Der Tooltip-PostCall lässt sich nicht deregistrieren. Er wird deshalb erst beim ersten Enable registriert und prüft danach als Erstes ein lokales Boolean. |
| 2 | **Zero behavior change without opt-in** | Alle Settings stehen per Default auf **OFF**. Die Installation gilt nur als Opt-in für das Sammeln der Daten, das nichts Sichtbares ändert. Tooltip-Zeilen und der Header-Button in der EUI-Tasche kommen erst nach Zustimmung. Beim ersten Login fragt ein `ShowConfirmPopup` "Tooltip und Taschen-Button aktivieren?". |
| 3 | **Low cost when enabled** | Rein event-getrieben: `BAG_UPDATE` markiert nur `dirty[bagID] = true`, `BAG_UPDATE_DELAYED` scannt dann nur die markierten Bags. Kein `OnUpdate`, kein `C_Timer` als Logik-Gate. Keine Tabellen-Allokation pro Tooltip-Anzeige: Die Zeilen kommen aus einem vorberechneten Cache pro itemID. Der Cache wird bei Datenänderung für die betroffenen IDs invalidiert. |
| 4 | **Zero taint risk** | Keine secure Templates. Browser-Slots nutzen `ItemButtonTemplate` (nicht secure) oder einen reinen `Button`. Keine Schreibzugriffe auf Blizzard- oder EUI-Frames: eigener Zustand liegt in Weak-Tables. Nur `HookScript` und `hooksecurefunc`, nie `SetScript` auf fremden Frames. `ToggleAllBags` und Co. nicht anfassen, EUI ersetzt die bereits. Keine Aktionen, die geschützte Funktionen auslösen (Item benutzen, verschieben). Im Browser gibt es nur Anzeige, Shift-Klick zum Verlinken und Strg-Klick zur Anprobe über `HandleModifiedItemClick`. |
| 5 | **Midnight only** | TOC `## Interface: 120000, 120001, 120005, 120007, 120100` wie EUI. Nur aktuelle APIs (`C_Container`, `C_Bank`, `C_Item`, `C_TooltipInfo`, `C_CurrencyInfo`). Keine Versions-Gates, keine Legacy-Bank- oder Reagenzbank-Pfade. `issecretvalue` wird beachtet (siehe 5.3). |

Dazu kommen die Code-Style-Regeln aus derselben Datei: **Lua 5.1** (kein `goto`), **nur ASCII** in Code, Kommentaren und Strings, eigene UI über die EUI-Systeme (siehe oben), Optionen im `W:DualRow`-Stil, falls sie je in die EUI-Optionen wandern.

---

## 3. Architektur

```
EUIBagSync/
  EUIBagSync.toc
  Core/
    Init.lua          -- ns, Event-Dispatcher, Enable/Disable-Registry je Feature
    DB.lua            -- SavedVariables, Defaults, Schema-Version, Migrationen
    Keys.lua          -- Char-Key, Realm-/Connected-Realm-Handling, Item-Key-Normalisierung
  Collect/
    Bags.lua          -- Rucksack + Taschen + Reagenztasche (BagIndex 0..5)
    Equipped.lua      -- Ausruestung (Slots 1..19)
    Bank.lua          -- Charakter-Bank-Tabs + Warband-Bank-Tabs
    Mail.lua          -- Postfach inkl. Ablaufdatum
    Currency.lua      -- Waehrungen + Gold
    Auctions.lua      -- (optional) eigene Auktionen
    GuildBank.lua     -- (optional, Phase 2b) Gildenbank
  Index/
    ItemIndex.lua     -- itemKey -> { [charKey] = {bags=,bank=,mail=,...} }, inkrementell
  Tooltip/
    Tooltip.lua       -- AddTooltipPostCall, Zeilen-Cache, Modifier-Gate
  UI/
    Skin.lua          -- RegisterSkin-Bruecke, Fallback-Optik ohne EUI
    Browser.lua       -- Hauptfenster
    CharList.lua      -- Sidebar mit Charakteren/Realms
    ItemGrid.lua      -- Slot-Pool + Grid-Rendering (offline)
    Search.lua        -- Suche ueber alle Chars
    HeaderButton.lua  -- Button im EUI_Bags.Header (optional)
  Options/
    Options.lua       -- Blizzard Settings API + Slash-Commands
  Locales/
    enUS.lua, deDE.lua
```

**TOC-Eckdaten:**

```
## Interface: 120000, 120001, 120005, 120007, 120100
## Title: EUI BagSync
## Notes: Cross-character inventory data, tooltips and browser for EllesmereUI Bags.
## OptionalDeps: EllesmereUI, EllesmereUIBags
## SavedVariables: EUIBagSyncDB
```

Nur `OptionalDeps`, keine harte Abhängigkeit. Dann funktioniert Sammeln und Tooltip auch ohne EUI, und EUI lädt vorher, wenn es da ist. Ein Kategorie-Feature wird erst genutzt, wenn `EUI_CategoryManager` existiert.

**Speicherort:** Die Daten liegen bewusst in einer **eigenen** SavedVariable (`EUIBagSyncDB`), nicht in `EllesmereUIDB`. EUI überschreibt `db.profile` beim Profil-Import komplett (`ApplyProfileData`). Eigene Keys im EUI-Root würden außerdem in Profil-Exporte geraten (EUI warnt im Code ausdrücklich vor der "PRIVATE_ADDON_KEYS leak class").

---

## 4. Datenmodell

```lua
EUIBagSyncDB = {
  schema = 1,
  settings = {                  -- alles default OFF bis auf Collector-Basics
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

**Item-Kodierung (kompakt, speicherarm):**

- Normale Items: `"i:<itemID>:<count>"`.
- Items mit relevanten Bonus-IDs (Gear, Crafting-Qualität): `"l:<itemString>:<count>"`. Nur der ItemString ohne Farbcodes.
- Battle Pets (`battlepet:`-Links) und Keystones als eigener Typ, weil sie keine normale itemID-Semantik haben.

**Schema-Versionierung:** `schema` plus Migrationsfunktionen in `DB.lua` (vgl. EUI `EllesmereUI_Migration.lua`). Unbekannte oder kaputte Einträge werden beim Laden verworfen und nicht crashend übernommen.

**Index (Laufzeit, nicht persistiert):** `ItemIndex[itemID] = { [charKey] = { bags=n, bank=n, mail=n, equipped=n, auctions=n } }` plus Warband und Gilde. Aufgebaut wird er lazy beim ersten Tooltip- oder Browser-Bedarf, danach inkrementell. Wenn Bag X von Char Y neu gescannt wird, zieht das Addon die alten Beiträge ab und addiert die neuen. Ein kompletter Rebuild ist nicht nötig.

---

## 5. Umsetzung nach Bereichen

### 5.1 Collector

| Quelle | Wann lesbar | Events / API |
|---|---|---|
| Taschen (0–5) | immer | `BAG_UPDATE` (dirty markieren) → `BAG_UPDATE_DELAYED` (scannen). `C_Container.GetContainerNumSlots`, `C_Container.GetContainerItemInfo` (liefert `itemID`, `hyperlink`, `stackCount`). |
| Ausrüstung | immer | `PLAYER_EQUIPMENT_CHANGED`, `GetInventoryItemLink("player", slot)` |
| Charakter-Bank-Tabs | **nur am Bankier** | `PLAYER_INTERACTION_MANAGER_FRAME_SHOW` mit `Enum.PlayerInteractionType.Banker`, danach `PLAYERBANKSLOTS_CHANGED` / `BAG_UPDATE` auf `Enum.BagIndex.CharacterBankTab_*`. `C_Bank.FetchPurchasedBankTabData(Enum.BankType.Character)` für die Tab-Liste. |
| Warband-Bank | nur am Bankier, von jedem Char | `Enum.BankType.Account`, `Enum.BagIndex.AccountBankTab_*`, `PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED`, Gold über `C_Bank.FetchDepositedMoney(Enum.BankType.Account)` |
| Post | nur am Briefkasten | `MAIL_SHOW`, `MAIL_INBOX_UPDATE`, `GetInboxHeaderInfo` (Ablauf), `GetInboxItemLink` / `GetInboxItem`. Dazu **eigene verschickte Post an eigene Alts** vormerken (`MAIL_SEND_SUCCESS` + zwischengespeicherte Anhänge), damit Items "unterwegs" nicht verschwinden. |
| Gold | immer | `PLAYER_MONEY`, `GetMoney()` |
| Währungen | immer | `CURRENCY_DISPLAY_UPDATE`, `C_CurrencyInfo.GetCurrencyListSize` / `GetCurrencyListInfo` |
| Auktionen (opt.) | nur im AH | `OWNED_AUCTIONS_UPDATED`, `C_AuctionHouse.GetOwnedAuctions()` |
| Gildenbank (opt.) | nur an der Gildenbank, pro Tab | `PLAYER_INTERACTION_MANAGER_FRAME_SHOW` (GuildBanker), `GUILDBANKBAGSLOTS_CHANGED`, `GetGuildBankItemLink`, `GetGuildBankItemInfo`. Jeden Tab einzeln abfragen (`QueryGuildBankTab`), sonst fehlen Daten. |

Details:

- **Char-Key** `Name-Realm` erst ab `PLAYER_LOGIN` bilden, niemals einen Stub cachen (EUI macht es in `BagsCharKey()` genauso).
- **Realm-Scope** für den Tooltip: `GetAutoCompleteRealms()` für verbundene Realms, dazu Faction-Filter optional.
- **Veraltete Daten kennzeichnen:** `scannedAt` pro Quelle. Browser und Tooltip zeigen z. B. "Bank: vor 12 Tagen" in Grau.
- **Aktueller Char im Tooltip:** Live-Wert statt Snapshot, über `C_Item.GetItemCount(itemID, includeBank, includeUses, includeReagentBank, includeAccountBank)`. Das ist immer aktuell und kostet keinen Scan.

### 5.2 Tooltip

- Registrierung einmalig und lazy: `TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItemTooltip)`.
- Ablauf in `OnItemTooltip(tooltip, data)`:
  1. `if not tooltipEnabled then return end` (Kriterium 1)
  2. nur für `GameTooltip`, `ItemRefTooltip` und `ShoppingTooltip1/2`. Tooltips anderer Addons nicht anfassen.
  3. itemID aus `data.id`. Bei `issecretvalue(data.id)` sofort abbrechen.
  4. Modifier-Gate (`none | shift | ctrl | alt`), analog zum EUI-Pattern `spellIDModifier`.
  5. Zeilen aus dem Cache `lineCache[itemID]` holen. Bei Cache-Miss einmal aufbauen: Char-Name klassenfarbig, rechts "Taschen 5, Bank 20, Post 1", dazu Warband-Zeile und Summe.
  6. `tooltip:AddDoubleLine(...)` pro Zeile. Die Obergrenze ist konfigurierbar (z. B. max. 8 Chars + "und N weitere").
- Keine Allokation pro Anzeige. Der Cache wird bei Index-Änderung nur für die betroffenen itemIDs geleert.
- Koexistenz: EUI hängt selbst per `AddTooltipPostCall` Item-ID- und Stack-Zeilen an (`EllesmereUI.lua`, `ItemIDTooltipHook`). Die Reihenfolge ist egal, weil beide nur Zeilen anhängen.

### 5.3 Midnight-Spezifika

- **Secret Values:** Midnight markiert bestimmte Werte in Kampf und Instanzen als "secret". EUI prüft das in seinem Tooltip-Hook mit `issecretvalue`. BagSync macht das auch, für jeden Wert aus `data`. Rechnen oder Vergleichen mit einem Secret Value wirft einen Fehler, und das verbietet Kriterium 4.
- **Bank:** Seit dem Bank-Umbau (11.2) gibt es nur noch Tabs (`CharacterBankTab_*`, `AccountBankTab_*`), keine separate Reagenzbank. Keine Legacy-Pfade bauen.
- **Kampf:** Nicht-secure Frames darf man im Kampf erstellen und zeigen. Das Browser-Fenster geht also auch in Kampf. Trotzdem wird der Slot-Pool beim ersten Öffnen außerhalb vom Kampf vorgewärmt. Grund ist die Performance, nicht Taint.

### 5.4 Browser-Fenster

Aufbau nach dem Vorbild von Baganator ("Characters"/"Search everywhere"), optisch wie EUI:

- **Fenster:** eigener Frame, per `S.Shell(frame)` geskinnt. Verschiebbar, Position in `settings.ui.browserPos`. Schließen mit ESC über `tinsert(UISpecialFrames, "EUIBagSyncBrowser")`.
- **Sidebar links:** Chars gruppiert nach Realm, klassenfarbig, mit Level, Gold und "zuletzt gesehen". Ganz oben die Einträge "Alle Charaktere" und "Warband-Bank", optional "Gildenbanken". Rechtsklick öffnet ein Menü mit "Daten löschen" über `EllesmereUI:ShowConfirmPopup`. Wenn verfügbar, per `ns.CreateSidebarHeader` gebaut, sonst mit eigener Optik.
- **Tabs oben:** Taschen | Bank | Ausrüstung | Post | Währungen | (Auktionen).
- **Grid:** Pool aus `ItemButtonTemplate`-Buttons (nicht secure). Gefüllt über `SetItemButtonTexture`, `SetItemButtonCount`, `SetItemButtonQuality`. Optik über `ns.SkinItemButton(btn, { anchorIcon=true, flatHighlight=true })`, falls vorhanden. Die Funktion arbeitet nur mit Methoden und ist daher auch für nicht-secure Buttons geeignet. Kompatibilität trotzdem in Phase 5 prüfen, sonst Fallback. Scrollbar per `ns.AttachGridScrollbar` oder `S.ScrollBar`.
- **Kategorien (optional):** Offline-Items über `EUI_CategoryManager:ClassifyItem(link, itemID)` gruppieren. Dann sieht die Offline-Ansicht aus wie die Tasche. Ohne EUI gibt es eine flache Liste, sortiert nach Qualität, Typ und Name.
- **Item-Tooltip im Grid:** `GameTooltip:SetHyperlink(link)`. Der BagSync-Tooltip-Hook hängt dann automatisch die Char-Bestände an.
- **Klicks:** nur `HandleModifiedItemClick(link)` (Shift = Chat-Link, Strg = Anprobe). Keine weiteren Aktionen.
- **Item-Daten nachladen:** Offline-Links sind evtl. nicht im Client-Cache. Deshalb `Item:CreateFromItemID(id):ContinueOnItemLoad(...)` bzw. `ITEM_DATA_LOAD_RESULT`, nur für sichtbare Slots, gebündelt pro Render.

### 5.5 Suche über alle Charaktere

- Eingabefeld im Browser (`S.EditBox`). Optional kann der Text aus `EUI_Bags._searchBox` übernommen werden. Der Hook läuft per `HookScript("OnTextChanged")`, nie per `SetScript`.
- **Eigenes Matching.** `C_Container.SetItemSearch` funktioniert nur für Live-Slots und würde außerdem die EUI-Tasche mitfiltern, weil die Suche client-global ist.
  - Stufe 1: Name (Teilstring, case-insensitive), itemID, Qualität (`q:epic`), Typ/Subtyp aus `C_Item.GetItemInfoInstant`.
  - Stufe 2 (optional): Itemlevel-Operatoren (`ilvl>=600`), Bindung, Erweiterung (`C_Item.GetItemInfo` → `expansionID`).
  - Stufe 3 (optional, teuer): Tooltip-Volltext über `C_TooltipInfo.GetHyperlink`. Nur auf Anfrage, lazy und pro Link gecacht.
- **Ergebnisansicht "Alle Charaktere":** eine Liste pro Item: Icon, Name, Gesamtmenge, darunter die Verteilung auf Char und Ort. Das entspricht dem "Search everywhere" von Baganator.
- Suche entprellt über Enter bzw. `OnTextChanged` mit Mindestlänge 2 statt über einen Timer (Kriterium 3).

### 5.6 Einstiegspunkte

- `/bagsync` bzw. `/bs` öffnet den Browser. `/bs search <text>` öffnet direkt die Suche.
- **Header-Button in der EUI-Tasche** (Default OFF): Nach `EUI_Bags:HookScript("OnShow", ...)` beim ersten Auftreten von `EUI_Bags.Header` einen eigenen Button erzeugen. Parent ist der Header, Anker links neben dem Sort-Button. Der Button bekommt ein eigenes Icon in `Media/` und den Tooltip über `EllesmereUI.ShowWidgetTooltip`. Es wird nichts auf den Header-Frame geschrieben.
- Optional LibDataBroker-Launcher (Minimap/Broker). LibDataBroker selbst bündeln, nicht auf EUIs `Libs` verlassen.

### 5.7 Optionen

- EUI bietet **keine öffentliche API für Options-Seiten von Drittaddons**. Die Optionen liegen im LoD-Addon `EllesmereUIOptions`, extern gibt es nur `RegisterSkin` und `RegisterExternalInstaller`.
- Deshalb eine eigene Seite über die Blizzard **Settings API** (`Settings.RegisterVerticalLayoutCategory` oder eine Canvas mit eigenen Widgets im EUI-Stil), zusätzlich Slash-Commands.
- Einstellungen: Datenquellen einzeln an/aus, Tooltip (an/aus, Modifier, Realm-Scope, aktuellen Char ausblenden, Summe, max. Zeilen), Header-Button, EUI-Kategorien verwenden, Char-Daten löschen, alles zurücksetzen.
- Erststart: einmaliges `ShowConfirmPopup` (bzw. ein eigenes Popup ohne EUI) mit der Frage, ob Tooltip und Taschen-Button aktiviert werden sollen. Die Antwort landet in `firstRunAsked`.

---

## 6. Phasen und Meilensteine

| Phase | Inhalt | Ergebnis / Abnahme |
|---|---|---|
| **0. Setup** | Repo, TOC, Ordnerstruktur, Symlink nach `_retail_/Interface/AddOns/EUIBagSync`, `luacheck` mit WoW-Globals, ASCII-Check (Pre-Commit), BugGrabber+BugSack, `.pkgmeta` für BigWigs Packager (CurseForge/Wago) | Addon lädt fehlerfrei, `/bs` antwortet |
| **1. Kern-Collector** | DB + Schema, Char-Meta, Taschen, Ausrüstung, Gold. Dirty-Bag-Scan über `BAG_UPDATE_DELAYED` | Nach Relog auf einem Twink sind die Daten des Mains in der SavedVariable korrekt |
| **2. Weitere Quellen** | Charakter-Bank, Warband-Bank, Post (inkl. versendeter Post), Währungen. (2b optional: Auktionen, Gildenbank) | Bank und Post werden am NPC korrekt erfasst, `scannedAt` stimmt |
| **3. Index + Tooltip** | ItemIndex (inkrementell), Tooltip-PostCall, Zeilen-Cache, Modifier, Realm-Scope, Live-Count für den aktuellen Char | Tooltip zeigt korrekte Summen; ohne aktivierten Tooltip hängt keine einzige Zeile dran |
| **4. Browser** | Fenster, Char-Sidebar, Tabs, Item-Grid mit Pool, Nachladen von Item-Daten, Suche Stufe 1, Ansicht "Alle Charaktere" | Jeder Char und jeder Ort durchsuchbar, Shift-Klick verlinkt |
| **5. EUI-Integration** | `RegisterSkin`, EUI-Fonts und Akzentfarbe, `ns.SkinItemButton`, Header-Button, EUI-Kategorien, Suchtext-Übernahme. Alles hinter Feature-Detection | Browser sieht aus wie die EUI-Tasche; mit deaktiviertem oder fehlendem EUI läuft alles weiter |
| **6. Optionen + Opt-in** | Settings-Seite, Erststart-Popup, Daten löschen, Lokalisierung enUS/deDE | Alle Features standardmäßig aus, einzeln schaltbar |
| **7. Härtung** | Taint-Test (siehe unten), Kampf- und Instanz-Test, Performance und Speicher messen, Test mit EUI-Update | Checkliste in Abschnitt 7 ist komplett grün |
| **8. (optional) Upstream** | Mit Ellesmere auf Discord über **kleine Extension-Hooks** sprechen, statt ein Feature einzureichen | siehe unten |

### Phase 8: Was man upstream vorschlagen könnte

Laut CONTRIBUTING soll man größere Features vorab per Discord-DM mit @ellesmere abstimmen. Realistisch ist nicht der ganze Sync, sondern nur eine minimale, kostenlose Erweiterungs-API, die das Companion-Addon robuster macht:

- `EUI_Bags:RegisterHeaderButton(key, opts)`: offizieller Platz für einen Drittanbieter-Button statt Anker-Raterei.
- `EllesmereUI.Bags.SkinItemButton` als stabiler öffentlicher Export des heutigen `ns.SkinItemButton`.
- Optional ein Callback nach `RefreshInventory`, falls je ein Overlay nötig wird.

Das Ganze kostet nichts, solange niemand es aufruft, ändert kein Verhalten und bringt kein Taint-Risiko mit. Damit erfüllt es alle fünf Kriterien und ist klein genug, um eine Chance zu haben.

---

## 7. Test- und Abnahme-Checkliste

**Funktional**
- [ ] Zwei oder mehr Chars auf demselben Realm und auf verbundenen Realms: Tooltip-Summen stimmen
- [ ] Bank und Warband-Bank werden nur am NPC aktualisiert, sonst bleibt der alte Stand mit Zeitstempel
- [ ] Post an einen eigenen Twink erscheint sofort als "unterwegs", nach Abholung in dessen Taschen
- [ ] Char löschen oder umbenennen: Daten lassen sich entfernen, der Index baut sich korrekt neu
- [ ] Battle Pets, Keystones und Crafting-Qualitäten werden korrekt dargestellt und gezählt

**Kriterium 1 und 2**
- [ ] Frische Installation: keine Tooltip-Zeile, kein Header-Button, bis der Nutzer zustimmt
- [ ] Deaktiviertes Feature: `/etrace` zeigt keine Events der BagSync-Frames für dieses Feature
- [ ] Kein Frame des Browsers existiert, bevor er zum ersten Mal geöffnet wird (Prüfung mit `/fstack` oder per Frame-Name)

**Kriterium 3**
- [ ] Kein `OnUpdate`, kein `C_Timer` in der Logik (Code-Grep als CI-Check)
- [ ] CPU über `C_AddOnProfiler` bzw. das Addon-Profiling im Client messen: Taschenwechsel, Loot-Spam, Tooltip-Hover
- [ ] Speicher mit 20 oder mehr Chars messen (`UpdateAddOnMemoryUsage` / `GetAddOnMemoryUsage`), Größe der SavedVariable prüfen

**Kriterium 4**
- [ ] `/console taintLog 2`, danach Kampf, M+, Bank, Taschen öffnen, Items benutzen, Browser im Kampf öffnen: keine BagSync-Einträge im `taint.log`, kein `ADDON_ACTION_FORBIDDEN`/`BLOCKED`
- [ ] Tooltip in Instanzen und im Kampf: keine Fehler durch Secret Values
- [ ] EUI deaktiviert, EUI-Bags deaktiviert, EUI auf neue Version aktualisiert: keine Lua-Fehler, sauberer Fallback

**Kriterium 5 und Style**
- [ ] Keine Legacy-APIs (`GetContainerItemInfo` global, `ReagentBank*` usw.) per Grep
- [ ] Nur ASCII in allen `.lua`-Dateien (`LC_ALL=C grep -nP '[^\x00-\x7F]'` liefert nichts)
- [ ] Lua 5.1: `luacheck --std lua51`

---

## 8. Risiken

| Risiko | Auswirkung | Gegenmaßnahme |
|---|---|---|
| EUI ändert interne Felder (`EUI_Bags.Header`, `ns.*`, `EUI_CategoryManager`) | Header-Button, Optik oder Kategorien fallen aus | Feature-Detection, `pcall` um optionale Aufrufe mit Fallback, Tests gegen jede neue EUI-Version. Langfristig die Hooks aus Phase 8 |
| Blizzard ändert Bank- oder Mail-APIs | Quelle liefert nichts | Collector pro Quelle isolieren; ein Ausfall darf andere Quellen nicht blockieren |
| Secret Values erweitern sich auf Item-Daten | Tooltip-Fehler | durchgängig `issecretvalue`-Guard, im Zweifel in Kampf und Instanz nichts anhängen |
| Große Accounts (50+ Chars, volle Gildenbanken) | SavedVariable-Größe, Login-Zeit | kompakte Kodierung, lazy Index, Gildenbank optional und pro Gilde abschaltbar |
| Überschneidung mit Baganator, Syndicator oder BagSync (Original) | doppelte Tooltip-Zeilen | Tooltip standardmäßig aus; beim Erststart erkennen, wenn Syndicator oder BagSync geladen ist, und den Nutzer darauf hinweisen |
| Name-Konflikt | "BagSync" ist ein bestehendes Addon | endgültigen Namen vor dem Release wählen (z. B. "EllesmereUI Bags: Alts" oder "EUI Warband Ledger") |

---

## 9. Grober Aufwand

| Phase | Aufwand (erfahrener WoW-Addon-Entwickler) |
|---|---|
| 0–1 | 1–2 Tage |
| 2 (ohne 2b) | 1–2 Tage |
| 3 | 1–2 Tage |
| 4 | 3–5 Tage (UI ist der größte Block) |
| 5 | 1–2 Tage |
| 6 | 1 Tag |
| 7 | 2–3 Tage |
| **Summe MVP** | **ca. 2–3 Wochen Teilzeit** |

MVP-Vorschlag: Phasen 0–3 zuerst liefern (Sammeln und Tooltip). Das bringt schon ca. 70 % des Nutzens von Baganator bzw. Syndicator für Alts. Browser und EUI-Optik folgen im zweiten Release.
