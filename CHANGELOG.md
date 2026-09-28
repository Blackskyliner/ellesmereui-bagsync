# Changelog

Each release has a `## <version>` section; the release workflow publishes that
section as the changelog on CurseForge and GitHub (`scripts/release-check.sh`).
The version must match `## Version` in the TOC.

Every entry starts with one of these prefixes, in this order within a version:
**New** (a feature that did not exist), **Enhanced** (an existing feature works
better, faster or reads better), **Bugfix** (something did not work as intended),
**Removed** (a feature or mode is gone).

0.8.4 is the first public release. The versions before it were development
builds, each tested in the game by the maintainer.

## 0.8.4

First public release, on CurseForge and as a GitHub release. It works like 0.8.3;
the development versions before it are listed in CHANGELOG.md in the repository.

## 0.8.3

- **Enhanced:** Caged battle pets in the browser show on a pet tooltip of the
  browser's own instead of Blizzard's shared one.
- **Enhanced:** An equipment set swap records the worn gear once instead of once
  per slot.
- **Enhanced:** README and CONTRIBUTING describe the addon as it is (options,
  limitations, public API).
- **Bugfix:** "Request own auctions when the auction house opens" sends exactly
  one request when the auction house opens; posting several auctions no longer
  sends one request per auction.
- **Bugfix:** A bound flag the game hides in combat defers the bag scan like the
  other item data, instead of storing the item as unbound.

## 0.8.2

- **Enhanced:** Translations use the game client's own words for game terms in
  every language (for example "tropa" and "hermandad" in Latin American Spanish,
  the Auctions tab name in French and Russian, soulbound in Chinese).
- **Enhanced:** `/alts status` lists every activation trigger and names the
  activation reason and the self-test results in the client's language.

## 0.8.1

- **Enhanced:** Documentation in English: README for the current state,
  CONTRIBUTING with the rules and the test tooling, note on AI assistance and
  AI-generated translations.

## 0.8.0

- **Enhanced:** Compact storage: one string per bag, bank tab and guild bank tab,
  item links reduced to their `item:` core. With 20 characters the saved data
  shrinks from about 320 KB to 200 KB and loads in under a millisecond. Older
  data is converted once on the first use.

## 0.7.2

- **Enhanced:** The browser's header uses the metrics of EllesmereUI Bags' bag
  header (height, title, search box, close glyph).

## 0.7.1

- **Enhanced:** Depends on EllesmereUI Bags alone: the standalone Bags download
  is enough, the rest of the EllesmereUI suite is not needed. On clients where
  EllesmereUI switches itself off, the addon stays inert with it.

## 0.7.0

- **Enhanced:** Activation on first use: nothing is scanned or registered at
  login. The first opening of the bags, a bank, mailbox, auction house or guild
  bank, the browser, the public API or (with tooltip counts on) an item tooltip
  activates the addon for the session.
- **Enhanced:** Loading screens no longer trigger rescans.
- **Bugfix:** Swapping a bag is recorded.

## 0.6.4

- **Bugfix:** The guild bank is recorded on the first visit of a session too (the
  tab list arrives after the window opens).

## 0.6.3

- **Bugfix:** The quality border of the first item column is no longer clipped.

## 0.6.2

- **New:** The search finds currencies next to items, with totals and
  per-character amounts.
- **Bugfix:** The browser's close button no longer sits above other windows;
  title, search and close button fit the title bar.

## 0.6.1

- **New:** Every character has an "Everything" tab that merges all of its
  locations.

## 0.6.0

- **New:** "All characters" and every realm header open overviews that merge all
  stored items, grouped by item class or EllesmereUI category.
- **New:** In the overviews the item tooltip lists who holds how many, even with
  tooltip counts off.
- **New:** Currency tooltips list every character's amount and the total.

## 0.5.0

- **New:** Stored items remember whether they are soulbound or warbound and which
  equipment sets they belong to; the browser tooltip shows both.

## 0.4.0

- **New:** The currency tab groups currencies into character-bound, transferable
  and warband-wide.

## 0.3.1

- **Enhanced:** Tooltip counts cost nothing on unit and world tooltips; item
  tooltip refreshes read only the cache.

## 0.3.0

- **New:** Sold auctions appear under "Mail -> Sold" with the price until the
  mailbox is opened.
- **New:** The mail footer shows the gold waiting in the mailbox, the auctions
  footer the value of all active auctions.
- **New:** `/alts debug` for diagnostic chat output.
- **Bugfix:** Cancelled auctions reach the mail reliably.

## 0.2.1

- **Enhanced:** Posted auctions appear at once, also with the confirmation dialog
  and multi-posts.
- **Bugfix:** Cancelled and expired auctions move to "Mail -> In transit"
  reliably.

## 0.2.0

- **New:** Own auctions are tracked per character; the tooltip and the browser
  show them.

## 0.1.1

- **Bugfix:** Offline characters no longer show 0 gold after switching
  characters.

## 0.1.0

- **New:** Bags, equipped gear, gold, bank, warband bank, mail, currencies and
  (opt-in) guild bank of every character.
- **New:** Opt-in tooltip counts, the cross-character browser with search, the
  EllesmereUI bag header button, settings page, slash commands and self-test.
- **New:** English plus ten translations.
