#!/usr/bin/env bash
# Runs the simulator tests: real Blizzard FrameXML (12.1) + real EllesmereUI
# (core + Bags) + this addon, inside Osso/wow-ui-sim (built by setup-tools.sh).
#   scripts/sim-test.sh            run-tests (sim/EllesmereUIBags_Alts_SimTests/tests)
#   scripts/sim-test.sh errors     startup Lua errors as JSON
#   scripts/sim-test.sh skin       run-tests with EUI's Blizzard skin module loaded too
#   scripts/sim-test.sh upstream   run-tests with EUI Bags patched with upstream/EllesmereUIBags_ExtAPI.lua
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SIM="$ROOT/.tools/vendor/wow-ui-sim"
EUI="$ROOT/.tools/vendor/EllesmereUI"
BIN="$SIM/target/release/wow-sim"
[ -x "$BIN" ] || { echo "wow-sim not built; run scripts/setup-tools.sh" >&2; exit 2; }
ADDONS="$SIM/Interface/AddOns"
MODE="${1:-tests}"

# Link the addons under test (links are removed again on exit).
LINKS=("$ADDONS/EllesmereUIBags_Alts" "$ADDONS/EllesmereUIBags_Alts_SimTests" "$ADDONS/EllesmereUI" "$ADDONS/EllesmereUIBags" "$ADDONS/EllesmereUIBlizzardSkin")
cleanup() {
  local status=$?
  for l in "${LINKS[@]}"; do if [ -L "$l" ]; then rm "$l"; fi; done
  return $status
}
trap cleanup EXIT
ln -sfn "$ROOT/EllesmereUIBags_Alts" "$ADDONS/EllesmereUIBags_Alts"
ln -sfn "$ROOT/sim/EllesmereUIBags_Alts_SimTests" "$ADDONS/EllesmereUIBags_Alts_SimTests"
if [ "$MODE" = "upstream" ]; then
  # Copy of the real Bags module with the proposed extension file appended to its TOC.
  PATCHED="$ROOT/.tools/sim-upstream/EllesmereUIBags"
  rm -rf "$PATCHED" && mkdir -p "$(dirname "$PATCHED")" && cp -R "$EUI/EllesmereUIBags" "$PATCHED"
  cp "$ROOT/upstream/EllesmereUIBags_ExtAPI.lua" "$PATCHED/"
  printf '\nEllesmereUIBags_ExtAPI.lua\n' >> "$PATCHED/EllesmereUIBags.toc"
  ln -sfn "$EUI" "$ADDONS/EllesmereUI"
  ln -sfn "$PATCHED" "$ADDONS/EllesmereUIBags"
else
  ln -sfn "$EUI" "$ADDONS/EllesmereUI"
  ln -sfn "$EUI/EllesmereUIBags" "$ADDONS/EllesmereUIBags"
  if [ "$MODE" = "skin" ]; then ln -sfn "$EUI/EllesmereUIBlizzardSkin" "$ADDONS/EllesmereUIBlizzardSkin"; fi
fi

cd "$SIM"
export HOME="$ROOT/.tools/simhome"
export WOW_SIM_NO_SOUND=1
case "$MODE" in
  errors) "$BIN" --no-saved-vars lua-errors ;;
  *)      "$BIN" --no-saved-vars run-tests EllesmereUIBags_Alts_SimTests ;;
esac
