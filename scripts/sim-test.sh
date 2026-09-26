#!/usr/bin/env bash
# Runs the simulator tests: real Blizzard FrameXML (12.1) + real EllesmereUI
# (core + Bags) + this addon, inside Osso/wow-ui-sim (built by setup-tools.sh).
#   scripts/sim-test.sh            run-tests (sim/EllesmereUIBags_Alts_SimTests/tests)
#   scripts/sim-test.sh errors     startup Lua errors as JSON
#   scripts/sim-test.sh noeui      run-tests without EllesmereUI loaded
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SIM="$ROOT/.tools/vendor/wow-ui-sim"
EUI="$ROOT/.tools/vendor/EllesmereUI"
BIN="$SIM/target/release/wow-sim"
[ -x "$BIN" ] || { echo "wow-sim not built; run scripts/setup-tools.sh" >&2; exit 2; }
ADDONS="$SIM/Interface/AddOns"
MODE="${1:-tests}"

# Link the addons under test (links are removed again on exit).
LINKS=("$ADDONS/EllesmereUIBags_Alts" "$ADDONS/EllesmereUIBags_Alts_SimTests" "$ADDONS/EllesmereUI" "$ADDONS/EllesmereUIBags")
cleanup() {
  local status=$?
  for l in "${LINKS[@]}"; do if [ -L "$l" ]; then rm "$l"; fi; done
  return $status
}
trap cleanup EXIT
ln -sfn "$ROOT/EllesmereUIBags_Alts" "$ADDONS/EllesmereUIBags_Alts"
ln -sfn "$ROOT/sim/EllesmereUIBags_Alts_SimTests" "$ADDONS/EllesmereUIBags_Alts_SimTests"
if [ "$MODE" != "noeui" ]; then
  ln -sfn "$EUI" "$ADDONS/EllesmereUI"
  ln -sfn "$EUI/EllesmereUIBags" "$ADDONS/EllesmereUIBags"
fi

cd "$SIM"
export HOME="$ROOT/.tools/simhome"
export WOW_SIM_NO_SOUND=1
case "$MODE" in
  errors) "$BIN" --no-saved-vars lua-errors ;;
  *)      "$BIN" --no-saved-vars run-tests EllesmereUIBags_Alts_SimTests ;;
esac
