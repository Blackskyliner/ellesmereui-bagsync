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
# LICENSE lives in the repository root, where GitHub reads it; the CurseForge
# packager copies root files into the addon folder, so the zip does the same.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
mkdir "$STAGE/EllesmereUIBags_Alts"
cp "$ROOT/LICENSE" "$STAGE/EllesmereUIBags_Alts/"
(cd "$STAGE" && zip -q "$OUT" EllesmereUIBags_Alts/LICENSE)
echo "$OUT"
unzip -l "$OUT" | tail -1
