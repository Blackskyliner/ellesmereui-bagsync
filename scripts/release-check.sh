#!/usr/bin/env bash
# Checks that a release tag can be published and writes its release notes.
#   scripts/release-check.sh <tag> [notes-file]
# The tag must equal the TOC's ## Version (the version in the TOC is the one
# the addon reports in game, so a tag must never disagree with it), and
# CHANGELOG.md must have a "## <version>" section: its text becomes the
# changelog on CurseForge and GitHub (default notes file: .release-notes.md).
# Its entries start with **New:**, **Enhanced:**, **Bugfix:** or **Removed:**,
# in that order.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TAG="${1:?usage: release-check.sh <tag> [notes-file]}"
NOTES="${2:-$ROOT/.release-notes.md}"
VERSION="$(sed -n 's/^## Version: *//p' "$ROOT/EllesmereUIBags_Alts/EllesmereUIBags_Alts.toc" | tr -d '\r')"

if [ "$TAG" != "$VERSION" ]; then
  echo "tag $TAG does not match the TOC version $VERSION" >&2
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
