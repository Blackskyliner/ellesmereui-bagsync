#!/usr/bin/env bash
# Visual regression tests: renders every scenario in sim/visual/scenarios with
# the GUI build of wow-ui-sim (real Blizzard FrameXML + EllesmereUI + this
# addon + the fixture data of the simulator test addon) and compares the
# target frame against sim/visual/baselines/<mode>/<scenario>.webp (lossless).
#
#   scripts/visual-test.sh            compare (exit 1 on any difference)
#   scripts/visual-test.sh --update   accept the current renders as baselines
#   scripts/visual-test.sh [--update] <scenario>...   only these scenarios
#
# Mode: bags (EUI core + Bags, the dependency: our plain look). Not with EUI's
# Blizzard skin module: a simulator bug fades every texture there (see
# sim/.../tests/00_harness.lua); its geometry is covered by the layout tests
# of `sim-test.sh skin`. Output, diffs and
# an HTML report land in .tools/visual-out/. Needs the GUI build and the
# Python venv from scripts/setup-tools.sh.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SIM="$ROOT/.tools/vendor/wow-ui-sim"
EUI="$ROOT/.tools/vendor/EllesmereUI"
BIN="$SIM/target-gui/release/wow-sim"
PY="$ROOT/.tools/venv/bin/python"
OUT="$ROOT/.tools/visual-out"
[ -x "$BIN" ] || { echo "GUI build of wow-sim missing; run scripts/setup-tools.sh" >&2; exit 2; }
[ -x "$PY" ] || { echo "Python venv missing; run scripts/setup-tools.sh" >&2; exit 2; }

UPDATE=()
if [ "${1:-}" = "--update" ]; then UPDATE=(--update); shift; fi
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
export WOW_SIM_NO_SOUND=1

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
