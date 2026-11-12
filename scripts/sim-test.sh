#!/usr/bin/env bash
# Runs the simulator tests: real Blizzard FrameXML + real EllesmereUI (core +
# Bags) + this addon, inside Osso/wow-ui-sim (built by setup-tools.sh).
#   scripts/sim-test.sh            run-tests (sim/EllesmereUIBags_Alts_SimTests/tests)
#   scripts/sim-test.sh errors     startup Lua errors as JSON
#   scripts/sim-test.sh skin       run-tests with EUI's Blizzard skin module loaded too
#   scripts/sim-test.sh upstream   run-tests with EUI Bags patched with upstream/EllesmereUIBags_ExtAPI.lua
# --client=forever before the mode runs the WoW Forever client (1.60 FrameXML,
# its own simulator build) instead of retail (12.1).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLIENT=retail
case "${1:-}" in
  --client=retail|--client=forever) CLIENT="${1#--client=}"; shift ;;
  --client=*) echo "unknown client: ${1#--client=}" >&2; exit 2 ;;
esac
if [ "$CLIENT" = forever ]; then SIM="$ROOT/.tools/vendor/wow-ui-sim-forever"; else SIM="$ROOT/.tools/vendor/wow-ui-sim"; fi
EUI="$ROOT/.tools/vendor/EllesmereUI"
BIN="$SIM/target/release/wow-sim"
[ -x "$BIN" ] || { echo "wow-sim ($CLIENT) not built; run scripts/setup-tools.sh" >&2; exit 2; }
ADDONS="$SIM/Interface/AddOns"
MODE="${1:-tests}"

# Link the addons under test (links are removed again on exit).
LINKS=("$ADDONS/EllesmereUIBags_Alts" "$ADDONS/EllesmereUIBags_Alts_SimTests" "$ADDONS/EllesmereUI" "$ADDONS/EllesmereUIBags" "$ADDONS/EllesmereUIBlizzardSkin")
cleanup() {
  local status=$?
  for l in "${LINKS[@]}"; do if [ -L "$l" ]; then rm "$l"; fi; done
  sim_lock_release
  return $status
}
# shellcheck source=sim-lock.sh
. "$ROOT/scripts/sim-lock.sh"
sim_lock_acquire
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
# Without game fonts the simulator measures all text in the first system font
# it finds, so the layout tests would depend on which fonts the machine has
# and the order its directory listing returns them in. On Linux that font is
# pinned to DejaVu Sans (installed by CI) through a fontconfig file whose only
# font directory holds that one face.
DEJAVU=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf
if [ "$(uname -s)" = Linux ] && [ -f "$DEJAVU" ]; then
  mkdir -p "$HOME/simfont"
  ln -sfn "$DEJAVU" "$HOME/simfont/DejaVuSans.ttf"
  printf '<?xml version="1.0"?>\n<fontconfig><dir>%s</dir></fontconfig>\n' "$HOME/simfont" > "$HOME/fonts.conf"
  export FONTCONFIG_FILE="$HOME/fonts.conf"
fi
# EllesmereUI's TOCs trail the live client's interface number (12.1.5:
# 120105), and wow-sim skips out-of-date addons like the client does. Ours is
# checked by scripts/check-api.py, for every client.
export WOW_SIM_LOAD_OUT_OF_DATE_ADDONS=1
export WOW_SIM_NO_SOUND=1
# Text in Blizzard's fonts (FRIZQT__, ARIALN) falls back to the first system
# font without a WoW install, a different one per operating system; EUI's
# default font stands in for them on every machine (scripts/patches/wow-ui-sim).
export WOW_SIM_FALLBACK_FONT="$EUI/media/fonts/Expressway.TTF"
# The binary also looks next to the sources it was built from; naming the
# directory keeps a cached or copied binary on this checkout's addons.
export WOW_SIM_ADDONS_PATH="$SIM/Interface/AddOns"
case "$MODE" in
  errors) "$BIN" --no-saved-vars lua-errors ;;
  *)      "$BIN" --no-saved-vars run-tests EllesmereUIBags_Alts_SimTests ;;
esac
