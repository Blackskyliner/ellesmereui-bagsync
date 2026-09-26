#!/usr/bin/env bash
# Full verification: lint, API surface, unit/integration tests (busted),
# simulator tests with and without EllesmereUI, and a scan of every simulator
# run for Lua errors raised by this addon.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$ROOT/.tools"
cd "$ROOT"
fail=0
step() { printf '\n== %s\n' "$1"; }

step "luacheck"
"$T/rocks/bin/luacheck" -q EllesmereUIBags_Alts spec sim upstream || fail=1

step "API surface (Blizzard 12.x sources, EllesmereUI contract, ASCII)"
python3 scripts/check-api.py || fail=1

step "busted"
"$T/rocks/bin/busted" -o utfTerminal || fail=1

if [ -x "$T/vendor/wow-ui-sim/target/release/wow-sim" ]; then
  for mode in tests noeui; do
    step "wow-ui-sim ($mode)"
    log="$(mktemp)"
    bash scripts/sim-test.sh "$mode" >"$log" 2>&1
    rc=$?
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
    if grep -a "Lua error" "$log" | grep -a -q "EllesmereUIBags_Alts/\|EUIBagsExt"; then
      echo "Lua errors raised by the addon:"; grep -a "Lua error" "$log" | grep -a "EllesmereUIBags_Alts/\|EUIBagsExt" | sort -u
      fail=1
    fi
    [ $rc -eq 0 ] || fail=1
    rm -f "$log"
  done
else
  step "wow-ui-sim skipped (not built)"
fi

printf '\n'
if [ $fail -eq 0 ]; then echo "ALL CHECKS PASSED"; else echo "CHECKS FAILED"; fi
exit $fail
