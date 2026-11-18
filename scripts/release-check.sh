#!/usr/bin/env bash
# Checks that a release tag can be published and writes its release notes.
#   scripts/release-check.sh [--allow-unreleased] <tag> [notes-file]
# The tag must equal the TOC's ## Version (the version in the TOC is the one
# the addon reports in game, so a tag must never disagree with it), and
# CHANGELOG.md must have a "## <version>" section: its text becomes the
# changelog on CurseForge and GitHub (default notes file: .release-notes.md).
# Its entries start with **New:**, **Enhanced:**, **Bugfix:** or **Removed:**,
# in that order.
# Changes not yet released wait as fragments in changelog.d/ (one file per
# change, so pull requests never edit the same lines); every fragment is
# checked for the same prefixes. scripts/changelog-release.py turns them into
# the next version's section. A tag is never released while fragments wait:
# they would miss its changelog. --allow-unreleased accepts waiting fragments
# (tests and pull request checks).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ALLOW_UNRELEASED=0
if [ "${1:-}" = "--allow-unreleased" ]; then ALLOW_UNRELEASED=1; shift; fi
TAG="${1:?usage: release-check.sh [--allow-unreleased] <tag> [notes-file]}"
NOTES="${2:-$ROOT/.release-notes.md}"
VERSION="$(sed -n 's/^## Version: *//p' "$ROOT/EllesmereUIBags_Alts/EllesmereUIBags_Alts.toc" | tr -d '\r')"

if [ "$TAG" != "$VERSION" ]; then
  echo "tag $TAG does not match the TOC version $VERSION" >&2
  exit 1
fi

# check_fragment <file>: entries with a prefix, continuation lines indented by
# two spaces, nothing else.
check_fragment() {
  awk '
    /^[[:space:]]*$/ { next }
    /^- \*\*(New|Enhanced|Bugfix|Removed):\*\* [^[:space:]]/ { entries++; next }
    /^  [^[:space:]]/ && entries { next }
    { print FILENAME ": not an entry or its continuation: " $0; bad = 1 }
    END {
      if (!entries) { print FILENAME ": no entry"; bad = 1 }
      exit bad
    }
  ' "$1" >&2
}
fragments=()
for f in "$ROOT"/changelog.d/*.md; do
  [ -f "$f" ] && [ "$(basename "$f")" != README.md ] && fragments+=("$f")
done
bad=0
for f in ${fragments[@]+"${fragments[@]}"}; do check_fragment "$f" || bad=1; done
if [ "$bad" = 1 ]; then
  echo "changelog.d: every entry starts with - **New:**, **Enhanced:**, **Bugfix:** or **Removed:** (changelog.d/README.md)" >&2
  exit 1
fi
if [ "${#fragments[@]}" -gt 0 ] && [ "$ALLOW_UNRELEASED" = 0 ]; then
  echo "changelog.d holds ${#fragments[@]} unreleased fragment(s); scripts/changelog-release.py moves them into CHANGELOG.md" >&2
  exit 1
fi

awk -v v="$VERSION" '
  $0 == "## " v { found = 1; next }
  found && /^## / { exit }
  found { print }
' "$ROOT/CHANGELOG.md" | sed -e '/./,$!d' > "$NOTES.tmp"
if ! grep -q '[^[:space:]]' "$NOTES.tmp"; then
  rm -f "$NOTES.tmp"
  echo "CHANGELOG.md has no \"## $VERSION\" section" >&2
  exit 1
fi
# Every entry starts with a prefix, in this order (CHANGELOG.md, top).
if ! awk '
  BEGIN { rank["New"] = 1; rank["Enhanced"] = 2; rank["Bugfix"] = 3; rank["Removed"] = 4 }
  /^- / {
    if (!match($0, /^- \*\*(New|Enhanced|Bugfix|Removed):\*\* /)) { print "no prefix: " $0; bad = 1; next }
    p = substr($0, 5); sub(/:.*/, "", p)
    if (rank[p] < last) { print "out of order: " $0; bad = 1 }
    last = rank[p]
  }
  END { exit bad }
' "$NOTES.tmp" >&2; then
  rm -f "$NOTES.tmp"
  echo "CHANGELOG.md $VERSION: entries need a New/Enhanced/Bugfix/Removed prefix, in that order" >&2
  exit 1
fi
{ printf '# EllesmereUI Bags: Alts %s\n\n' "$VERSION"; cat "$NOTES.tmp"; } > "$NOTES"
rm -f "$NOTES.tmp"
echo "release $VERSION ok, notes in $NOTES"
