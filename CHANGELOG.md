# Changelog

Each release has a `## <version>` section; the release workflow publishes that
section as the changelog on CurseForge and GitHub (`scripts/release-check.sh`).
The version must match `## Version` in the TOC.

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
