#!/usr/bin/env bash
# Full verification: lint, API surface, unit/integration tests (busted),
# simulator tests with and without EllesmereUI per client, and a scan of every
# simulator run for Lua errors raised by this addon.
#   --require-sim       fail instead of skipping when a simulator is not built
#                       (CI: a broken simulator build must not pass as "skipped")
#   --client=<name>     simulator tests of one client only: retail or forever
#                       (default: both; lint, API check and busted cover both
#                       clients in every run, the visual tests retail only)
set -uo pipefail
REQUIRE_SIM=0 CLIENTS="retail forever"
for arg in "$@"; do
  case "$arg" in
    --require-sim) REQUIRE_SIM=1 ;;
    --client=retail|--client=forever) CLIENTS="${arg#--client=}" ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$ROOT/.tools"
cd "$ROOT"
fail=0
step() { printf '\n== %s\n' "$1"; }

step "luacheck"
"$T/rocks/bin/luacheck" -q EllesmereUIBags_Alts spec sim upstream || fail=1

step "API surface (Blizzard sources of every client, EllesmereUI contract, ASCII)"
python3 scripts/check-api.py || fail=1

step "CHANGELOG section of the TOC version"
notes="$(mktemp)"
bash scripts/release-check.sh "$(sed -n 's/^## Version: *//p' EllesmereUIBags_Alts/EllesmereUIBags_Alts.toc | tr -d '\r')" "$notes" || fail=1
rm -f "$notes"

step "busted"
"$T/rocks/bin/busted" -o utfTerminal || fail=1

# One simulator run: prints the test lines; returns 1 on a failed test or a Lua
# error raised by the addon.
sim_run() {
  local client="$1" mode="$2" log rc=0
  log="$(mktemp)"
  bash scripts/sim-test.sh --client="$client" "$mode" >"$log" 2>&1 || rc=1
  python3 - "$log" <<'PY'
import sys
s = open(sys.argv[1], encoding="utf-8", errors="ignore").read()
body = s[s.find("Running"):]
for line in body.splitlines():
    if "✓" in line or "✗" in line or "tests," in line:
        print(line)
    elif line.startswith("    ") and not any(x in line for x in ("in function", "xpcall", "tail call", "main chunk", "MerchantFrame")):
        print(line)
PY
  # No summary means the run never got to the tests (crash, missing library):
  # the filter above would print nothing, so show the end of the raw output.
  if ! grep -a -q "tests," "$log"; then
    echo "no test summary; last lines of the run:"; tail -n 15 "$log"
    rc=1
  fi
  if grep -a "Lua error" "$log" | grep -a -q "EllesmereUIBags_Alts/\|EUIBagsExt"; then
    echo "Lua errors raised by the addon:"; grep -a "Lua error" "$log" | grep -a "EllesmereUIBags_Alts/\|EUIBagsExt" | sort -u
    rc=1
  fi
  rm -f "$log"
  return $rc
}

for client in $CLIENTS; do
  if [ "$client" = forever ]; then sim="$T/vendor/wow-ui-sim-forever"; else sim="$T/vendor/wow-ui-sim"; fi
  if [ -x "$sim/target/release/wow-sim" ]; then
    for mode in tests skin upstream; do
      step "wow-ui-sim $client ($mode)"
      sim_run "$client" "$mode" || fail=1
    done
  else
    step "wow-ui-sim $client skipped (not built)"
    [ "$REQUIRE_SIM" = 0 ] || { echo "--require-sim: simulator missing"; fail=1; }
  fi
done

case " $CLIENTS " in *" retail "*) visual=1 ;; *) visual=0 ;; esac
if [ "$visual" = 1 ] && [ -x "$T/vendor/wow-ui-sim/target-gui/release/wow-sim" ] && [ -x "$T/venv/bin/python" ]; then
  step "visual regression (wow-ui-sim screenshots vs sim/visual/baselines)"
  vlog="$(mktemp)"
  if bash scripts/visual-test.sh >"$vlog" 2>&1; then
    tail -1 "$vlog"
  else
    grep -v "^OK " "$vlog"
    fail=1
  fi
  rm -f "$vlog"
else
  step "visual regression skipped (retail only; GUI build or venv missing)"
fi

printf '\n'
if [ $fail -eq 0 ]; then echo "ALL CHECKS PASSED"; else echo "CHECKS FAILED"; fi
exit $fail
