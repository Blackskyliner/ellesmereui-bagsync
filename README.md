# EllesmereUI Bags: Alts

Companion-Addon für **EllesmereUI Bags** (WoW Midnight 12.x). Es speichert Taschen,
Ausrüstung, Bank, Kriegsmeutenbank, Post, eigene Auktionen, Währungen und optional die Gildenbank
aller deiner Charaktere. Die Bestände zeigt es auf Wunsch im Item-Tooltip und in
einem eigenen Browser-Fenster an, ähnlich wie Baganator.

- Eigenständiges Addon, **EllesmereUI wird nicht verändert**. Ohne EllesmereUI
  läuft es auch, dann mit eigener, schlichter Optik.
- Alles Sichtbare ist standardmäßig **aus** und wird erst nach Zustimmung aktiv
  (siehe „Erster Start“).
- Eine Zwischenschicht (`Libs/EUIBagsExt`) kapselt jeden Zugriff auf EllesmereUI.
  Der passende Upstream-Vorschlag für EllesmereUI liegt in `upstream/`.

## Sprachen

Das Addon hat dieselben Sprachen wie das EllesmereUI-Repo: Englisch (Basis),
Deutsch, Spanisch (EU und Lateinamerika), Französisch, Italienisch, Koreanisch,
Portugiesisch (Brasilien), Russisch, Chinesisch (vereinfacht und traditionell).
Es gelten die Konventionen aus EUIs `CONTRIBUTING_TRANSLATIONS.md`:
- Der englische Text ist der Schlüssel.
- Die Dateien sind UTF-8 ohne BOM, mit echten Sonderzeichen.
- Nur die Datei der Client-Sprache legt Einträge an.
- Fehlende Einträge fallen auf Englisch zurück.

Spielbegriffe (Kriegsmeutenbank, Reagenzientasche usw.) folgen Blizzards bzw.
EllesmereUIs eigenen Übersetzungen. Die Übersetzungen sind KI-erstellt
und nicht muttersprachlich geprüft. Korrekturen sind willkommen, der Test
`spec/locales_spec.lua` prüft dabei Abdeckung, Platzhalter und Kodierung.

## Installation

1. Den Ordner `EllesmereUIBags_Alts` (oder den Inhalt von
   `dist/EllesmereUIBags_Alts-0.5.0.zip`) nach
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
| `/alts debug` | Diagnose-Ausgaben im Chat an/aus, etwa zu Auktions-Events mit IDs. Hilfreich für Fehlerberichte. |
| `/alts selftest` | Gleicht die gespeicherten Daten dieses Charakters mit dem Spiel ab (siehe unten) |
| `/alts delete Name-Realm` | Daten eines anderen Charakters löschen (mit Rückfrage) |

**Browser:** links die Charaktere nach Realm gruppiert, dazu Kriegsmeutenbank
und Gildenbanken. Oben die Tabs Taschen, Bank, Angelegt, Post, Auktionen und Währungen,
rechts die Items. Hover zeigt den Item-Tooltip, Shift-Klick verlinkt im Chat,
Strg-Klick öffnet die Anprobe. Der Browser zeigt nur an und nimmt, verschiebt
oder benutzt keine Items.

**Übersichten:** Ganz oben in der Seitenleiste steht „Alle Charaktere“, jede
Realm-Überschrift ist ebenfalls anklickbar. Beide zeigen alle gespeicherten
Items zusammengefasst: gleiche Items ergeben einen Platz mit der Gesamtzahl,
Ausrüstung mit unterschiedlichem Link bleibt getrennt. Die Items sind nach
Gegenstandsklasse gruppiert (oder nach EUI-Kategorien, wenn die Option an ist).
Der Tab „Alles“ umfasst Taschen, Banken, Angelegtes, Post,
Auktionen und Gildenbanken, die übrigen Tabs filtern nach Ort. Auch jeder
einzelne Charakter hat den Tab „Alles“: dieselbe zusammengefasste Ansicht über
alle Orte dieses Charakters, der Tooltip nennt die Orte (z. B. „Taschen: 20,
Bank: 5“). Der Tooltip
zeigt hier immer, wer wie viel hat, auch wenn die Tooltip-Option aus ist. Die
Realm-Übersicht enthält nur die Charaktere und Gildenbanken dieses Realms. Die
Kriegsmeutenbank ist accountweit und gehört nur zu „Alle Charaktere“. Im
Footer stehen die Goldsumme und die Zahl der Charaktere.

**Währungen:** Der Tab gruppiert nach „Charaktergebunden“ und „Überweisbar“
(in der Kriegsmeute übertragbar). Kriegsmeutenweite Währungen teilen alle
Charaktere, sie sind also weder gebunden noch überweisbar. Sie stehen in einem
eigenen Abschnitt „Kriegsmeutenweit (geteilt)“, der nur erscheint, wenn solche
Währungen vorkommen. Die Art jeder Währung merkt sich das Addon accountweit,
damit auch die Währungen anderer Charaktere richtig einsortiert werden.
Hover über eine Währung zeigt Blizzards Währungs-Tooltip und darunter, welcher
Charakter wie viel hat, mit Summe. In den Übersichten werden Währungen
aufsummiert. Kriegsmeutenweite Währungen zählen dabei nur einmal.

**Bindung und Sets:** Das Addon merkt sich pro Item, ob es seelengebunden
oder kriegsmeutengebunden ist. Im Browser-Tooltip steht bei gebundenen Items
deshalb „Seelengebunden“ bzw. „Kriegsmeutengebunden“ statt der allgemeinen
Angabe „Beim Anlegen gebunden“. Items ohne diesen Hinweis sind noch frei
beweglich, „kriegsmeutengebunden bis zum Anlegen“ bleibt sichtbar. Gehört ein
Item zu einem Ausrüstungsset (Taschen oder angelegt), nennt der Tooltip die
Sets. Der Browser zeigt Items in einem eigenen Tooltip-Fenster, Blizzards
`GameTooltip` bleibt unberührt.

**Suche:** Wörter (Namensbestandteile), `12345` oder `id:12345` (Item-ID),
`q:epic` oder `q:4` (Qualität), `t:rüstung` (Typ/Untertyp). Mehrere Begriffe
müssen alle zutreffen. Wörter und eine Zahl durchsuchen auch die Namen der
gespeicherten Währungen. Treffer stehen oben unter „Währungen“ mit der Summe
über alle Charaktere und den Beständen pro Charakter, Hover zeigt den
Währungs-Tooltip, Shift-Klick verlinkt die Währung im Chat. `id:`, `q:` und
`t:` filtern nur Items.

**Tooltip:** Pro Charakter eine Zeile mit Aufteilung nach Ort, dazu
Kriegsmeutenbank, Gildenbank und Summe. Er erscheint nur an Item-Tooltips aus
Taschen, Bank, Chat-Links, AH usw., nicht an Units oder Objekten in der Welt. Einstellbar sind: nur bei gedrückter
Umschalt-, Strg- oder Alt-Taste, Realm-Umfang (verbundene Realms, nur dieser
Realm oder alle), aktuellen Charakter ausblenden und maximale Zeilenzahl.

## Wann welche Daten erfasst werden

**Erst ab der ersten Benutzung.** Beim Einloggen scannt das Addon nichts,
prüft keine gespeicherten Daten und registriert kein Collector-Event. Es hängt
nur seine Auslöser ein: EUIs Taschenfenster, ein einziges Event für Bank,
Briefkasten, Auktionshaus und Gildenbank, den Browser (`/alts`, Header-Button),
die öffentliche API und, wenn die Tooltip-Option an ist, den ersten
Item-Tooltip. Beim ersten Auslöser einer Sitzung wird das Addon aktiviert,
genau einmal. Dann erfasst es den aktuellen Charakter einmal vollständig, und
ab da gilt die Tabelle. Das NPC-Fenster, das die Aktivierung ausgelöst hat,
wird bei demselben Besuch schon erfasst. `/alts status` zeigt, ob und wodurch
das Addon aktiviert wurde. Blizzards eigene Taschenfenster werden nie
eingehängt, weil EllesmereUI Bags vorausgesetzt ist. Ladebildschirme
(Instanzen, Portale) lösen keine erneuten Scans aus.

| Quelle | Wann (nach der Aktivierung) | Hinweis |
|---|---|---|
| Taschen inkl. Reagenzientasche | laufend | nach jeder Änderung, gebündelt pro Update-Schub |
| Angelegte Ausrüstung | laufend | |
| Gold, Level, Gilde | laufend | |
| Charakterbank + Kriegsmeutenbank | **nur am Bankier** | Zeitstempel „Bank erfasst“ im Browser |
| Post | **nur am Briefkasten** | Post an eigene Charaktere erscheint sofort als „Unterwegs“ beim Empfänger |
| Eigene Auktionen | **nur im Auktionshaus** | Standardmäßig passiv: Gelesen wird, was der Client meldet, etwa beim Öffnen des Reiters „Auktionen“. Opt-in: beim Öffnen selbst abfragen. **Neu eingestellte Auktionen erscheinen sofort**, auch mit Bestätigungsdialog und bei Mehrfach-Einstellungen. Abgebrochene Auktionen wandern sofort in „Post → Unterwegs“, abgelaufene spätestens beim nächsten Login. **Verkaufte Auktionen** stehen mit dem erzielten Betrag unter „Post → Verkauft“, bis du den Briefkasten öffnest. Sie werden live erkannt (Verkaufsmeldung, auch außerhalb des AH) und beim Abgleich mit der Auktionsliste, bei Commodities auch Teilverkäufe. Der Footer im Auktionen-Tab zeigt den möglichen Erlös aller aktiven Auktionen. |
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
   beide Zeilen und die Summe. „Alle Charaktere“ und die Realm-Überschrift
   anklicken: Die Items beider Charaktere erscheinen zusammengefasst, der Tab
   „Währungen“ zeigt Summen, Hover über eine Währung listet die Charaktere.
7. **Post:** Mit Charakter A etwas an Charakter B schicken. Im Browser taucht es
   bei B unter „Post → Unterwegs“ auf. Nach dem Einloggen von B und dem Öffnen
   des Briefkastens steht es unter „Posteingang“.
8. **Auktionen:** Ein Item einstellen. Es erscheint sofort im Browser unter
   „Auktionen“, ohne dass du den Reiter „Auktionen“ öffnen musst, und der
   Tooltip zeigt „Auktionen: n“. Der Footer zeigt „Im Auktionshaus: X (n)“.
   Den Reiter einmal öffnen, die Liste bleibt gleich und ist nicht doppelt.
   Eine Auktion abbrechen, das Item steht sofort unter „Post → Unterwegs“.
   Wird etwas verkauft, steht es mit Betrag unter „Post → Verkauft“, und der
   Footer zeigt „Gold in der Post“. Nach dem Öffnen des Briefkastens ist der
   Eintrag weg. Bei Abweichungen `/alts debug` einschalten und die Chatzeilen
   mitschicken.
9. **Gildenbank (optional):** In den Optionen „Gildenbank“ aktivieren (sie ist
   standardmäßig aus, `/alts status` listet `guildbank` unter den aktiven
   Features) und die Gildenbank öffnen. Die Fächer erscheinen im Browser unter
   „Gildenbanken“, auch beim ersten Besuch nach dem Einloggen. Mit
   `/alts debug` meldet der Chat, wie viele Fächer bekannt sind und welches
   Fach mit wie vielen Stapeln erfasst wurde.
10. **Kampf/Instanz:** In einem Dungeon kämpfen, Taschen öffnen und `/alts`
   öffnen. BugSack bleibt leer, und `taint.log` enthält keine Zeile mit
   `EllesmereUIBags_Alts`.
11. **Abschalten:** `/alts tooltip` blendet die Tooltip-Zeilen aus. Bei
    abgeschaltetem Button in den Optionen verschwindet er aus dem Taschen-Kopf.
12. **Ohne EUI (optional):** EllesmereUI deaktivieren. Das Addon lädt weiter,
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
- Commodity-Verkäufe außerhalb des AH erscheinen erst beim nächsten Blick in
  die Auktionsliste. Die Verkaufsmeldung sagt nicht, wie viele Einheiten
  verkauft wurden.
- Beträge sind Brutto, die AH-Gebühr zieht erst die Post ab. Für Auktionen, die
  nicht über dieses Addon eingestellt wurden, stammt der Preis aus der Liste.
  Bei Commodities wird er als Stückpreis gewertet, das ist im Client zu
  bestätigen.

## Entwicklung

```bash
scripts/setup-tools.sh
```

`setup-tools.sh` baut die projektlokale Toolchain in `.tools/`: Lua 5.1, busted,
luacheck, Referenzquellen und den wow-ui-sim-Simulator. Den Simulator gibt es
zweimal: headless für die Tests (`target/`) und mit GPU-Renderer für
Screenshots (`target-gui/`). Dazu kommt eine Python-Umgebung (`.tools/venv`)
mit Pillow für den Bildvergleich.

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
   Addon lässt den Lauf scheitern. `08_secure_combat.lua` ruft jeden Addon-Pfad
   im Kampf als unsicheren Code auf. Der Simulator erzwingt geschützte Frames,
   und jeder Treffer würde `ADDON_ACTION_BLOCKED` auslösen. Eine Positivkontrolle
   in jedem Lauf beweist, dass die Sperre aktiv ist. Dazu prüft der Test, dass
   kein eigener Frame geschützt ist und dass der Taint des Addons auf keinem
   fremden globalen oder Blizzard/EUI-Tabellen-Slot liegt.
   **Nicht abgedeckt:** Taint, der zur Laufzeit in Event-Handlern entsteht und
   sich in Blizzards sicheren Code ausbreitet. Der Simulator verwirft ihn, das
   deckt nur der Ingame-Schritt 9 mit `taint.log` ab.
   `10_layout.lua` prüft Layout-Invarianten in jeder Browser-Ansicht (Charakter
   mit allen Tabs, „Alle Charaktere“, Realm, Kriegsmeuten- und Gildenbank,
   Suche) und bei zwei Skalierungen. Gemessen wird die Geometrie, die der
   Simulator aus den echten Ankern berechnet. Nichts ragt aus dem Fenster
   (Scrollinhalt nicht seitlich), Titel, Suche und Schließen-Button liegen in
   EUIs 25-px-Titelleiste, Tabs, Grid-Slots und Textzeilen überlappen nicht,
   und kein Frame liegt weit über dem Level seines Fensters. Die Testdaten
   (`sim/.../Fixture.lua`) sind drei Charaktere auf zwei Realms mit Bank, Post,
   Auktionen, Währungen, Kriegsmeuten- und Gildenbank.
5. **Visual Regression** (`scripts/visual-test.sh`): Jedes Szenario in
   `sim/visual/scenarios/` wird mit dem GPU-Build gerendert, mit und ohne EUI,
   auf den Ziel-Frame zugeschnitten und mit `sim/visual/baselines/<modus>/`
   verglichen. Ein Pixel zählt als verändert, wenn ein Kanal um mehr als 24
   abweicht. Ein Szenario scheitert ab 0,1 % veränderten Pixeln, bei geänderter
   Größe oder bei einem Lua-Fehler. Ergebnis, Diff-Bilder (Änderungen rot) und
   `report.html` landen in `.tools/visual-out/`. Nach einer gewollten
   Änderung übernimmt `scripts/visual-test.sh --update [szenario...]` die neuen
   Bilder. Die Referenzbilder vor dem Commit ansehen.
   **Grenzen:** Ohne lokale WoW-Installation fehlen Blizzards Texturen
   (Item-Icons, Atlanten, Slot-Rahmen im Fallback-Look), und native
   Tooltip-Zeilen erzeugt der Simulator nicht. Die Bilder zeigen Layout, EUIs
   Skin und unsere Texte, nicht die exakte Optik im Spiel. Mit
   `WOW_INSTALL_PATH` auf eine WoW-Installation zeigen die Renders auch die
   Blizzard-Grafiken, dann müssen die Referenzbilder neu erzeugt werden.

Struktur: `EllesmereUIBags_Alts/` (Addon), `spec/` (busted), `sim/`
(Simulator-Tests), `upstream/` (Vorschlag für EllesmereUI), `scripts/`
(Toolchain, Checks, Tests), `PLAN.md` (Konzept), `TODO.md` (Arbeits-Checkliste).

### Öffentliche API für andere Addons

```lua
local total, byOwner = EllesmereUIBagsAlts.GetItemCount(itemID)
-- byOwner["Name-Realm"].bags / .bank / .equipped / .mail / .auctions, byOwner["#warband"].warband, byOwner["@Gilde-Realm"].guild
EllesmereUIBagsAlts.GetCharacters()          -- { "Name-Realm", ... }
EllesmereUIBagsAlts.GetCharacterInfo(key)    -- name, realm, class, level, money, lastSeen
EllesmereUIBagsAlts.OpenBrowser(key) / .ToggleBrowser() / .Search(text)
```

### Acceptance Criteria aus EllesmereUI (`.github/CONTRIBUTING.md`)

| # | Kriterium | Umsetzung | Test |
|---|---|---|---|
| 1 | Nichts kostet, solange es aus ist | Features registrieren Events erst beim Einschalten. Die Collector starten zudem erst mit der ersten Benutzung einer Sitzung. Bis dahin sind nur ein Event (NPC-Fenster) und ein Hook an EUIs Taschenfenster aktiv, es gibt keinen Scan beim Login. Der Browser wird erst beim ersten Öffnen gebaut. Der Tooltip-Hook entsteht erst beim ersten Einschalten. | `spec/options_criteria_spec.lua` (Criterion 1), `spec/activation_spec.lua`, Simulator |
| 2 | Keine Verhaltensänderung ohne Opt-in | Tooltip, Header-Button, EUI-Kategorien, Gildenbank und die aktive Auktionsabfrage sind standardmäßig aus. Die Opt-in-Frage kommt erst beim ersten Taschen-Öffnen. | DB- und Options-Specs |
| 3 | Geringe Kosten im Betrieb | Dirty-Set statt Voll-Scan, keine Timer, kein OnUpdate-Polling. Der Tooltip hängt nur an Item-Tooltips, es gibt keinen Clear-Hook. Unit-, NPC- und Welt-Tooltips kosten null Addon-Aufrufe. Die Anzahlen kommen aus dem Index-Cache, die Zeilen aus einem Cache pro Item. | Criterion 3: je ein Scan pro Burst. Tooltip: 0 Aufrufe bei 1000 Unit-Refreshes, kein Neuzählen bei 1000 Item-Refreshes. |
| 4 | Kein Taint-Risiko | Keine secure Templates, kein `SetScript` auf fremden Frames, keine Feldzugriffe auf EUI- oder Blizzard-Frames, nur `hooksecurefunc`/`HookScript`, keine geschützten Aktionen | statische Criterion-4-Tests, Simulator |
| 5 | Nur Midnight | Interface ab 120000, nur `C_*`-APIs, keine Legacy-Bank-Pfade | Criterion 5, API-Check |
