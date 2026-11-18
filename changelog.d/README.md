# Unreleased changes

A change that players notice adds one file here instead of editing
`CHANGELOG.md`, so pull requests never touch the same lines. Name it after the
change (`tooltip-sort.md`); it holds one or more entries for players, each
starting with one of the prefixes `CHANGELOG.md` explains:

```markdown
- **New:** Tooltip options to sort characters by amount, last played or name.
- **Bugfix:** The keyring shows as "Keyring" after the bags on WoW Forever.
```

Longer entries continue on lines indented by two spaces. The order across
files does not matter: the release pull request runs
`scripts/changelog-release.py <version>`, which writes the version's section
sorted by prefix, sets the version in the TOC and the README and deletes the
fragments. `scripts/release-check.sh` checks every fragment on each pull
request.
