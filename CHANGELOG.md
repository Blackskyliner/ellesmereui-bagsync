# Changelog

Each release has a `## <version>` section; the release workflow publishes that
section as the changelog on CurseForge and GitHub (`scripts/release-check.sh`).
The version must match `## Version` in the TOC.

0.8.4 is the first public release. The versions before it were development
builds, each tested in the game by the maintainer.

## 0.8.4

First public release.

- Remembers bags, equipped gear, gold, character bank, warband bank, mail, own
  auctions, currencies and (opt-in) the guild bank of every character you use it on.
- Tooltip counts (opt-in): which character holds how many of an item and where,
  plus warband bank, guild banks and a total.
- Browser (`/alts`) in EllesmereUI's look: every character, realm overviews and an
  "All characters" view, tabs per location, search across items and currencies.
- Auction tracking: posted, cancelled, expired and sold auctions, with the gold
  waiting in the mailbox.
- Optional button in the EllesmereUI bag header.
- Nothing runs until the first use in a session; no taint, no polling.
- English plus ten translations (AI-generated, corrections welcome).

## 0.8.3

- Caged battle pets in the browser show on a pet tooltip of the browser's own
  instead of Blizzard's shared one.
- "Request own auctions when the auction house opens" sends exactly one request
  when the auction house opens; posting several auctions no longer sends one
  request per auction.
- An equipment set swap records the worn gear once instead of once per slot.
- A bound flag the game hides in combat defers the bag scan like the other item
  data, instead of storing the item as unbound.
- README and CONTRIBUTING describe the addon as it is (options, limitations,
  public API).

## 0.8.2

- Translations use the game client's own words for game terms in every language
  (for example "tropa" and "hermandad" in Latin American Spanish, the Auctions tab
  name in French and Russian, soulbound in Chinese).
- `/alts status` lists every activation trigger and names the activation reason
  and the self-test results in the client's language.

## 0.8.1

- Documentation in English: README for the current state, CONTRIBUTING with the
  rules and the test tooling, note on AI assistance and AI-generated translations.

## 0.8.0

- Compact storage: one string per bag, bank tab and guild bank tab, item links
  reduced to their `item:` core. With 20 characters the saved data shrinks from
  about 320 KB to 200 KB and loads in under a millisecond. Older data is converted
  once on the first use.

## 0.7.2

- The browser's header uses the metrics of EllesmereUI Bags' bag header (height,
  title, search box, close glyph).

## 0.7.1

- EllesmereUI Bags is a required dependency; the standalone fallbacks are gone.
  The addon stays inert on clients where EllesmereUI switches itself off.

## 0.7.0

- Activation on first use: nothing is scanned or registered at login. The first
  opening of the bags, a bank, mailbox, auction house or guild bank, the browser,
  the public API or (with tooltip counts on) an item tooltip activates the addon
  for the session.
- Loading screens no longer trigger rescans; swapping a bag is recorded.

## 0.6.4

- The guild bank is recorded on the first visit of a session too (the tab list
  arrives after the window opens).

## 0.6.3

- The quality border of the first item column is no longer clipped.

## 0.6.2

- The search finds currencies next to items, with totals and per-character
  amounts.
- The browser's close button no longer sits above other windows; title, search
  and close button fit the title bar.

## 0.6.1

- Every character has an "Everything" tab that merges all of its locations.

## 0.6.0

- "All characters" and every realm header open overviews that merge all stored
  items, grouped by item class or EllesmereUI category.
- In the overviews the item tooltip lists who holds how many, even with tooltip
  counts off.
- Currency tooltips list every character's amount and the total.

## 0.5.0

- Stored items remember whether they are soulbound or warbound and which
  equipment sets they belong to; the browser tooltip shows both.

## 0.4.0

- The currency tab groups currencies into character-bound, transferable and
  warband-wide.

## 0.3.1

- Tooltip counts cost nothing on unit and world tooltips; item tooltip refreshes
  read only the cache.

## 0.3.0

- Sold auctions appear under "Mail -> Sold" with the price until the mailbox is
  opened; cancelled auctions reach the mail reliably.
- The mail footer shows the gold waiting in the mailbox, the auctions footer the
  value of all active auctions.
- `/alts debug` for diagnostic chat output.

## 0.2.1

- Posted auctions appear at once, also with the confirmation dialog and
  multi-posts; cancelled and expired ones move to "Mail -> In transit".

## 0.2.0

- Own auctions are tracked per character; the tooltip and the browser show them.

## 0.1.1

- Offline characters no longer show 0 gold after switching characters.

## 0.1.0

- Bags, equipped gear, gold, bank, warband bank, mail, currencies and (opt-in)
  guild bank of every character.
- Opt-in tooltip counts, the cross-character browser with search, the EllesmereUI
  bag header button, settings page, slash commands and self-test.
- English plus ten translations.
