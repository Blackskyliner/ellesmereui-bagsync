#!/usr/bin/env bash
# Visual regression tests: renders every scenario in sim/visual/scenarios with
# wow-ui-sim (real Blizzard FrameXML + EllesmereUI + this
# addon + the fixture data of the simulator test addon) and compares the
# target frame against sim/visual/baselines/<mode>/<scenario>.webp (lossless).
#
#   scripts/visual-test.sh            compare (exit 1 on any difference)
#   scripts/visual-test.sh --update   accept the current renders as baselines
#   scripts/visual-test.sh [--update] <scenario>...   only these scenarios
#   scripts/visual-test.sh --inventory   list the textures every surface uses
#                                        (sim/visual/texture-inventory.lua) in
#                                        .tools/visual-out/inventory.log
#
# Mode: bags (EUI core + Bags, the dependency: our plain look). Not with EUI's
# Blizzard skin module: a simulator bug fades every texture there (see
# sim/.../tests/00_harness.lua); its geometry is covered by the layout tests
# of `sim-test.sh skin`. Output, diffs and
# an HTML report land in .tools/visual-out/. Needs wow-ui-sim and the
# Python venv from scripts/setup-tools.sh.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SIM="$ROOT/.tools/vendor/wow-ui-sim"
EUI="$ROOT/.tools/vendor/EllesmereUI"
BIN="$SIM/target/release/wow-sim"
PY="$ROOT/.tools/venv/bin/python"
OUT="$ROOT/.tools/visual-out"
[ -x "$BIN" ] || { echo "wow-sim not built; run scripts/setup-tools.sh" >&2; exit 2; }
[ -x "$PY" ] || { echo "Python venv missing; run scripts/setup-tools.sh" >&2; exit 2; }

UPDATE=() INVENTORY=0
if [ "${1:-}" = "--update" ]; then UPDATE=(--update); shift; fi
if [ "${1:-}" = "--inventory" ]; then INVENTORY=1; shift; fi
if [ $# -gt 0 ]; then
  SCENARIOS=("$@")
else
  SCENARIOS=()
  for f in "$ROOT"/sim/visual/scenarios/*.lua; do SCENARIOS+=("$(basename "$f" .lua)"); done
fi

ADDONS="$SIM/Interface/AddOns"
LINKS=("$ADDONS/EllesmereUIBags_Alts" "$ADDONS/EllesmereUIBags_Alts_SimTests" "$ADDONS/EllesmereUI" "$ADDONS/EllesmereUIBags" "$ADDONS/EllesmereUIBlizzardSkin")
unlink_all() { for l in "${LINKS[@]}"; do if [ -L "$l" ]; then rm "$l"; fi; done; }
trap unlink_all EXIT

rm -rf "${OUT:?}" && mkdir -p "$OUT"
export HOME="$ROOT/.tools/simhome"
# EllesmereUI's TOCs trail the live client's interface number (12.1.5:
# 120105), and wow-sim skips out-of-date addons like the client does. Ours is
# checked by scripts/check-api.py.
export WOW_SIM_LOAD_OUT_OF_DATE_ADDONS=1
export WOW_SIM_NO_SOUND=1
# Text in Blizzard's fonts (FRIZQT__, ARIALN) falls back to the first system
# font without a WoW install, a different one per operating system; EUI's
# default font stands in for them on every machine (scripts/patches/wow-ui-sim).
export WOW_SIM_FALLBACK_FONT="$EUI/media/fonts/Expressway.TTF"
# Blizzard's textures (icons, atlases, frame art): the files pinned in
# sim/visual/blizzard-art.lock.json, fetched from Blizzard's CDN into a
# minimal WoW install in .tools that holds only them (scripts/blizzard-art.py).
# Without CASC archives there, the simulator reads them from the install's
# extracted art tree; a real install on this machine is not used, so every
# machine renders the same textures.
ART="$("$PY" "$ROOT/scripts/blizzard-art.py" fetch | sed -n 's/^blizzard-art: [0-9]* files in \(.*\) ([0-9]* fetched)$/\1/p')"
[ -d "$ART/Data/data" ] || { echo "Blizzard textures missing; see scripts/blizzard-art.py" >&2; exit 2; }
export WOW_INSTALL_PATH="$ART" WOW_SIM_CASC=0
# The binary also looks next to the sources it was built from; naming the
# directory keeps a cached or copied binary on this checkout's addons.
export WOW_SIM_ADDONS_PATH="$SIM/Interface/AddOns"

if [ "$INVENTORY" = 1 ]; then
  ln -sfn "$ROOT/EllesmereUIBags_Alts" "$ADDONS/EllesmereUIBags_Alts"
  ln -sfn "$ROOT/sim/EllesmereUIBags_Alts_SimTests" "$ADDONS/EllesmereUIBags_Alts_SimTests"
  ln -sfn "$EUI" "$ADDONS/EllesmereUI"
  ln -sfn "$EUI/EllesmereUIBags" "$ADDONS/EllesmereUIBags"
  cat "$ROOT/sim/visual/prelude.lua" "$ROOT/sim/visual/texture-inventory.lua" > "$OUT/inventory.lua"
  (cd "$SIM" && "$BIN" --no-saved-vars --exec-lua "@$OUT/inventory.lua" dump-tree \
      --filter EllesmereUIBagsAltsBrowser > "$OUT/inventory.log" 2>&1) || true
  grep -q "TEXTURE-INVENTORY" "$OUT/inventory.log" || { echo "inventory failed (see $OUT/inventory.log)" >&2; exit 1; }
  echo "texture inventory: $OUT/inventory.log"
  exit 0
fi

for mode in bags; do
  unlink_all
  ln -sfn "$ROOT/EllesmereUIBags_Alts" "$ADDONS/EllesmereUIBags_Alts"
  ln -sfn "$ROOT/sim/EllesmereUIBags_Alts_SimTests" "$ADDONS/EllesmereUIBags_Alts_SimTests"
  ln -sfn "$EUI" "$ADDONS/EllesmereUI"
  ln -sfn "$EUI/EllesmereUIBags" "$ADDONS/EllesmereUIBags"
  if [ "$mode" = "skin" ]; then ln -sfn "$EUI/EllesmereUIBlizzardSkin" "$ADDONS/EllesmereUIBlizzardSkin"; fi
  mkdir -p "$OUT/$mode"
  for name in "${SCENARIOS[@]}"; do
    scenario="$ROOT/sim/visual/scenarios/$name.lua"
    [ -f "$scenario" ] || { echo "no scenario $name" >&2; exit 2; }
    frame="$(sed -n 's/^-- frame: *//p' "$scenario" | head -1)"
    frame="${frame:-EllesmereUIBagsAltsBrowser}"
    cat "$ROOT/sim/visual/prelude.lua" "$scenario" > "$OUT/$mode/$name.lua"
    (cd "$SIM" && "$BIN" --no-saved-vars --exec-lua "@$OUT/$mode/$name.lua" screenshot \
        -o "$OUT/$mode/$name.webp" -f "$frame" --dump-tree "$frame" > "$OUT/$mode/$name.log" 2>&1) || {
      echo "render failed: $mode/$name (see $OUT/$mode/$name.log)" >&2; exit 1; }
    echo "$frame" > "$OUT/$mode/$name.frame"
  done
done

"$PY" "$ROOT/scripts/visual-compare.py" ${UPDATE[@]+"${UPDATE[@]}"} "$OUT" "$ROOT/sim/visual/baselines" "${SCENARIOS[@]}"
