#!/usr/bin/env bash
# Builds dist/EllesmereUIBags_Alts-<version>.zip (addon folder only), ready to
# unpack into World of Warcraft/_retail_/Interface/AddOns.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(sed -n 's/^## Version: *//p' "$ROOT/EllesmereUIBags_Alts/EllesmereUIBags_Alts.toc" | tr -d '\r')"
DIST="${DIST:-$ROOT/dist}"   # the release dry run packs into a temporary directory
mkdir -p "$DIST"
OUT="$DIST/EllesmereUIBags_Alts-$VERSION.zip"
rm -f "$OUT"
(cd "$ROOT" && zip -qr "$OUT" EllesmereUIBags_Alts -x '*.DS_Store')
echo "$OUT"
unzip -l "$OUT" | tail -1
