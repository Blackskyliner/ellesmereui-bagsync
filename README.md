# EllesmereUI Bags: Alts

Companion-Addon für **EllesmereUI Bags** (WoW Midnight 12.x). Es speichert Taschen,
Ausrüstung, Bank, Kriegsmeutenbank, Post, Währungen und optional die Gildenbank
aller deiner Charaktere. Die Bestände zeigt es auf Wunsch im Item-Tooltip und in
einem eigenen Browser-Fenster an, ähnlich wie Baganator.

- Eigenständiges Addon, **EllesmereUI wird nicht verändert**. Ohne EllesmereUI
  läuft es auch, dann mit eigener, schlichter Optik.
- Alles Sichtbare ist standardmäßig **aus** und wird erst nach Zustimmung aktiv
  (siehe „Erster Start“).
- Eine Zwischenschicht (`Libs/EUIBagsExt`) kapselt jeden Zugriff auf EllesmereUI.
  Der passende Upstream-Vorschlag für EllesmereUI liegt in `upstream/`.

## Installation

1. Den Ordner `EllesmereUIBags_Alts` (oder den Inhalt von
   `dist/EllesmereUIBags_Alts-0.1.0.zip`) nach
   `World of Warcraft/_retail_/Interface/AddOns/` kopieren.
2. Im Charakterauswahl-Bildschirm unter „AddOns“ prüfen, dass
   „EllesmereUI Bags: Alts“ aktiv ist.
3. Einloggen. Daten sammeln sich ab jetzt pro Charakter: **jeden Charakter
   einmal einloggen**, für Bankdaten einmal einen Bankier besuchen und für
   Postdaten einmal einen Briefkasten öffnen.

## Erster Start

- Beim ersten Login erscheint nur eine Chat-Zeile mit Hinweis auf `/alts`.
- Mit EllesmereUI fragt beim **ersten Öffnen der Tasche** ein Popup, ob die
  Tooltip-Anzahlen und der Button im Taschen-Kopf aktiviert werden sollen. Die
  Frage kommt erst dann, weil EUI beim Login eigene Popups zeigt. Ohne EUI kommt
  die Frage direkt beim Login.
- Die Entscheidung lässt sich jederzeit ändern: Optionen → AddOns →
  „EllesmereUI Bags: Alts“ oder `/alts options`.

## Bedienung

| Befehl | Wirkung |
|---|---|
| `/alts` | Browser öffnen/schließen |
| `/alts search <text>` | Suche über alle Charaktere |
| `/alts options` | Einstellungen öffnen |
| `/alts tooltip` | Tooltip-Anzahlen an/aus |
| `/alts status` | Version, gespeicherte Charaktere, aktive Funktionen, registrierte Events |
| `/alts selftest` | Gleicht die gespeicherten Daten dieses Charakters mit dem Spiel ab (siehe unten) |
| `/alts delete Name-Realm` | Daten eines anderen Charakters löschen (mit Rückfrage) |

**Browser:** links die Charaktere nach Realm gruppiert, dazu Kriegsmeutenbank
und Gildenbanken. Oben die Tabs Taschen, Bank, Angelegt, Post und Währungen,
rechts die Items. Hover zeigt den Item-Tooltip, Shift-Klick verlinkt im Chat,
Strg-Klick öffnet die Anprobe. Der Browser zeigt nur an und nimmt, verschiebt
oder benutzt keine Items.

**Suche:** Wörter (Namensbestandteile), `12345` oder `id:12345` (Item-ID),
`q:epic` oder `q:4` (Qualität), `t:rüstung` (Typ/Untertyp). Mehrere Begriffe
müssen alle zutreffen.

**Tooltip:** Pro Charakter eine Zeile mit Aufteilung nach Ort, dazu
Kriegsmeutenbank, Gildenbank und Summe. Einstellbar sind: nur bei gedrückter
Umschalt-, Strg- oder Alt-Taste, Realm-Umfang (verbundene Realms, nur dieser
Realm oder alle), aktuellen Charakter ausblenden und maximale Zeilenzahl.

## Wann welche Daten erfasst werden

| Quelle | Wann | Hinweis |
|---|---|---|
| Taschen inkl. Reagenzientasche | laufend | nach jeder Änderung, gebündelt pro Update-Schub |
| Angelegte Ausrüstung | laufend | |
| Gold, Level, Gilde | laufend | |
| Charakterbank + Kriegsmeutenbank | **nur am Bankier** | Zeitstempel „Bank erfasst“ im Browser |
| Post | **nur am Briefkasten** | Post an eigene Charaktere erscheint sofort als „Unterwegs“ beim Empfänger |
| Währungen | laufend | Die Erstliste enthält nur aufgeklappte Kategorien, danach wird jede Änderung erfasst |
| Gildenbank (Opt-in) | **nur an der Gildenbank** | liest alle Fächer, die du sehen darfst |

Die Daten liegen accountweit in `WTF/Account/<ACCOUNT>/SavedVariables/EllesmereUIBags_Alts.lua`
(Variable `EllesmereUIBagsAltsDB`), bewusst getrennt von `EllesmereUIDB`.

## Ingame-Testplan

Vorbereitung: [BugGrabber](https://www.curseforge.com/wow/addons/bug-grabber) und
[BugSack](https://www.curseforge.com/wow/addons/bugsack) installieren, dann einmal
`/console taintLog 1` eingeben (das Log landet in `Logs/taint.log`).

1. **Laden:** Einloggen, keine BugSack-Meldung. `/alts status` zeigt 1
   Charakter und die aktiven Funktionen `character, bags, equipped, bank, mail,
   currency`.
2. **Opt-in:** Tasche öffnen, das Popup erscheint. „Aktivieren“ klicken, danach
   ist neben der Item-Anzahl im Kopf der EUI-Tasche ein kleiner Button zu sehen.
3. **Selbsttest:** `/alts selftest` zeigt „OK“. Er prüft, dass alle genutzten
   APIs im Client existieren, dass die gespeicherten Taschen- und
   Ausrüstungs-Anzahlen `C_Item.GetItemCount` entsprechen und dass der
   inkrementelle Index einem Neuaufbau entspricht.
4. **Taschen live:** Ein Item verschieben, aufteilen oder verkaufen, dann erneut
   `/alts selftest` ausführen. Das Ergebnis bleibt „OK“.
5. **Bank:** Einen Bankier besuchen, im Browser unter „Bank“ erscheinen die
   Fächer und bei „Kriegsmeutenbank“ die Warband-Fächer. Bei offener Bank ein
   Item in die Bank legen, es erscheint dort sofort.
6. **Zweiter Charakter:** Einen Twink einloggen, der Browser zeigt beide
   Charaktere. Beim Hover über ein Item, das beide besitzen, zeigt der Tooltip
   beide Zeilen und die Summe.
7. **Post:** Mit Charakter A etwas an Charakter B schicken. Im Browser taucht es
   bei B unter „Post → Unterwegs“ auf. Nach dem Einloggen von B und dem Öffnen
   des Briefkastens steht es unter „Posteingang“.
8. **Gildenbank (optional):** In den Optionen „Gildenbank“ aktivieren und die
   Gildenbank öffnen. Die Fächer erscheinen im Browser unter „Gildenbanken“.
9. **Kampf/Instanz:** In einem Dungeon kämpfen, Taschen öffnen und `/alts`
   öffnen. BugSack bleibt leer, und `taint.log` enthält keine Zeile mit
   `EllesmereUIBags_Alts`.
10. **Abschalten:** `/alts tooltip` blendet die Tooltip-Zeilen aus. Bei
    abgeschaltetem Button in den Optionen verschwindet er aus dem Taschen-Kopf.
11. **Ohne EUI (optional):** EllesmereUI deaktivieren. Das Addon lädt weiter,
    der Browser hat dann die schlichte eigene Optik.

Falls etwas auffällt, bitte `/alts status` und `/alts selftest` ausführen und
die Ausgabe sowie die BugSack-Meldung festhalten.

## Grenzen

- Bank, Post und Gildenbank sind nur so aktuell wie der letzte Besuch.
  Zeitstempel stehen im Browser-Footer.
- Nachverfolgt wird nur Post an Charaktere, die schon einmal mit dem Addon
  eingeloggt waren.
- Die erste Währungsliste enthält keine zugeklappten Kategorien. Das Addon
  klappt keine UI-Elemente für dich auf.
- Eigene Auktionen werden nicht erfasst.

## Entwicklung

```bash
scripts/setup-tools.sh
```

`setup-tools.sh` baut die projektlokale Toolchain in `.tools/`: Lua 5.1, busted,
luacheck, Referenzquellen und den wow-ui-sim-Simulator.

```bash
scripts/test.sh
```

`test.sh` führt alle Prüfungen aus:

1. **luacheck** (Lua 5.1, jede genutzte globale Variable deklariert).
2. **API-Check** (`scripts/check-api.py`): Jede globale Funktion, jede
   `C_*`-Funktion, jeder `Enum`-Wert, jedes Event und jedes Template muss in
   Blizzards 12.1-Quellen bzw. den API-Annotationen existieren. Dazu kommen der
   Vertrag mit dem EllesmereUI-Quellcode (18 Symbole) und die ASCII-Prüfung.
3. **busted** (`spec/`): WoW-Client-Mock mit Taschen, Bank, Post, Gildenbank,
   Secret Values und Relogs samt serialisierten SavedVariables. Nicht
   modellierte Frame-Methoden werden nur akzeptiert, wenn sie echte
   Widget-Methoden laut Blizzard-Doku sind.
4. **wow-ui-sim** (`sim/`): Das Addon läuft im Headless-Simulator mit Blizzards
   echtem FrameXML 12.1 und echtem EllesmereUI. Es gibt drei Durchläufe: mit
   EUI, ohne EUI und mit gepatchtem EUI (Upstream-API). Jeder Lua-Fehler aus dem
   Addon lässt den Lauf scheitern.

Struktur: `EllesmereUIBags_Alts/` (Addon), `spec/` (busted), `sim/`
(Simulator-Tests), `upstream/` (Vorschlag für EllesmereUI), `scripts/`
(Toolchain, Checks, Tests), `PLAN.md` (Konzept), `TODO.md` (Arbeits-Checkliste).

### Öffentliche API für andere Addons

```lua
local total, byOwner = EllesmereUIBagsAlts.GetItemCount(itemID)
-- byOwner["Name-Realm"].bags / .bank / .equipped / .mail, byOwner["#warband"].warband, byOwner["@Gilde-Realm"].guild
EllesmereUIBagsAlts.GetCharacters()          -- { "Name-Realm", ... }
EllesmereUIBagsAlts.GetCharacterInfo(key)    -- name, realm, class, level, money, lastSeen
EllesmereUIBagsAlts.OpenBrowser(key) / .ToggleBrowser() / .Search(text)
```

### Acceptance Criteria aus EllesmereUI (`.github/CONTRIBUTING.md`)

| # | Kriterium | Umsetzung | Test |
|---|---|---|---|
| 1 | Nichts kostet, solange es aus ist | Features registrieren Events erst beim Einschalten. Der Browser wird erst beim ersten Öffnen gebaut. Der Tooltip-Hook entsteht erst beim ersten Einschalten. | `spec/options_criteria_spec.lua` (Criterion 1), Simulator |
| 2 | Keine Verhaltensänderung ohne Opt-in | Tooltip, Header-Button, EUI-Kategorien und Gildenbank sind standardmäßig aus. Die Opt-in-Frage kommt erst beim ersten Taschen-Öffnen. | DB- und Options-Specs |
| 3 | Geringe Kosten im Betrieb | Dirty-Set statt Voll-Scan, keine Timer, kein OnUpdate-Polling. Tooltip-Zeilen kommen aus einem Cache. | Criterion 3: je ein Scan pro Burst, Test ohne Allokationen |
| 4 | Kein Taint-Risiko | Keine secure Templates, kein `SetScript` auf fremden Frames, keine Feldzugriffe auf EUI- oder Blizzard-Frames, nur `hooksecurefunc`/`HookScript`, keine geschützten Aktionen | statische Criterion-4-Tests, Simulator |
| 5 | Nur Midnight | Interface ab 120000, nur `C_*`-APIs, keine Legacy-Bank-Pfade | Criterion 5, API-Check |
