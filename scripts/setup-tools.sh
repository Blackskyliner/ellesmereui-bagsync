#!/usr/bin/env bash
# Builds the project-local toolchain into ./.tools (nothing is installed globally):
#   - Lua 5.1.5 (same language level as the WoW client)
#   - LuaRocks + busted (unit/integration tests) + luacheck (lint)
#   - reference sources: Gethe/wow-ui-source (Blizzard UI 12.x incl. generated API docs),
#     Ketho/vscode-wow-api (API annotations), EllesmereGaming/EllesmereUI (host addon),
#     Blizzard's GlobalStrings of every client locale (Ketho/BlizzardInterfaceResources)
#   - Osso/wow-ui-sim (headless WoW UI simulator, Rust) + Blizzard UI cache for it
# Requires: curl, git, a C compiler, make (Linux: readline headers for Lua);
# cargo and rsync for the simulator, python3 for the checks.
#
# Options (CI):
#   --no-sim   skip wow-ui-sim and the Python venv (lint, API check, busted only)
#   --no-gui   skip the GPU build of wow-ui-sim and the venv (no visual tests)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$ROOT/.tools"
SIM=1 GUI=1
for arg in "$@"; do
  case "$arg" in
    --no-sim) SIM=0; GUI=0 ;;
    --no-gui) GUI=0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done
mkdir -p "$T/src" "$T/vendor"

# The simulator is pinned: its Lua API grows with every commit, and the test
# suite is known to pass against this revision.
WOW_UI_SIM_REV=d08c5517aa029cecc94b01a64d37c5a8066803b5

case "$(uname -s)" in Darwin) LUA_TARGET=macosx ;; *) LUA_TARGET=linux ;; esac
if [ ! -x "$T/lua/bin/lua" ]; then
  (cd "$T/src" && curl -sSLO https://www.lua.org/ftp/lua-5.1.5.tar.gz && tar xzf lua-5.1.5.tar.gz \
    && cd lua-5.1.5 && make "$LUA_TARGET" INSTALL_TOP="$T/lua" >/dev/null && make install INSTALL_TOP="$T/lua" >/dev/null)
fi

if [ ! -x "$T/luarocks/bin/luarocks" ]; then
  (cd "$T/src" && curl -sSL -o luarocks.tar.gz https://luarocks.github.io/luarocks/releases/luarocks-3.11.1.tar.gz \
    && tar xzf luarocks.tar.gz && cd luarocks-3.11.1 \
    && ./configure --prefix="$T/luarocks" --with-lua="$T/lua" --with-lua-include="$T/lua/include" >/dev/null \
    && make >/dev/null && make install >/dev/null)
fi

for rock in busted luacheck; do
  "$T/luarocks/bin/luarocks" --tree "$T/rocks" show "$rock" >/dev/null 2>&1 \
    || "$T/luarocks/bin/luarocks" --tree "$T/rocks" install "$rock"
done

clone() { [ -d "$T/vendor/$2" ] || git clone -q --depth 1 ${3:+--branch "$3"} "$1" "$T/vendor/$2"; }
clone https://github.com/Gethe/wow-ui-source.git wow-ui-source live
clone https://github.com/Ketho/vscode-wow-api.git vscode-wow-api
clone https://github.com/EllesmereGaming/EllesmereUI.git EllesmereUI
if [ "$SIM" = 1 ] && [ ! -d "$T/vendor/wow-ui-sim" ]; then
  git init -q "$T/vendor/wow-ui-sim"
  git -C "$T/vendor/wow-ui-sim" fetch -q --depth 1 https://github.com/Osso/wow-ui-sim.git "$WOW_UI_SIM_REV"
  git -C "$T/vendor/wow-ui-sim" checkout -q FETCH_HEAD
fi

# Blizzard's own strings per client locale: the reference for game terms in our translations
# (spec/locales_spec.lua compares against them).
GS="$T/vendor/globalstrings"
mkdir -p "$GS"
for loc in enUS deDE esES esMX frFR itIT koKR ptBR ruRU zhCN zhTW; do
  [ -s "$GS/$loc.lua" ] || curl -sSfL -o "$GS/$loc.lua" \
    "https://raw.githubusercontent.com/Ketho/BlizzardInterfaceResources/live/Resources/GlobalStrings/$loc.lua"
done

if [ "$SIM" = 0 ]; then
  echo "--no-sim: skipping wow-ui-sim" >&2
elif command -v cargo >/dev/null 2>&1; then
  if [ ! -x "$T/vendor/wow-ui-sim/target/release/wow-sim" ]; then
    (cd "$T/vendor/wow-ui-sim" && CARGO_HOME="$T/cargo" cargo build --release --bin wow-sim \
      --no-default-features --features client-retail --locked)
  fi
  # Second build with the GPU renderer for screenshots (visual tests); own
  # target dir so the headless binary above stays untouched.
  if [ "$GUI" = 1 ] && [ ! -x "$T/vendor/wow-ui-sim/target-gui/release/wow-sim" ]; then
    (cd "$T/vendor/wow-ui-sim" && CARGO_HOME="$T/cargo" CARGO_TARGET_DIR="$T/vendor/wow-ui-sim/target-gui" \
      cargo build --release --bin wow-sim --no-default-features --features gui,client-retail --locked)
  fi
  # wow-sim reads Blizzard UI from $HOME/Library/Caches (macOS) or ~/.cache; point HOME at .tools/simhome.
  C="$T/simhome/Library/Caches/wow-ui-sim/blizzard-ui/retail/AddOns"
  if [ ! -f "$C/.wow-ui-sim-blizzard-ui-complete" ]; then
    mkdir -p "$C" && rsync -a "$T/vendor/wow-ui-source/Interface/AddOns/" "$C/"
    touch "$C/.wow-ui-sim-blizzard-ui-complete"
    printf 'profile=retail\nsource=gethe-image-build\nfallback=none\n' > "$C/.wow-ui-sim-blizzard-ui-provenance"
  fi
  mkdir -p "$T/simhome/.cache"
  ln -sfn "$T/simhome/Library/Caches/wow-ui-sim" "$T/simhome/.cache/wow-ui-sim"
else
  echo "cargo not found: skipping wow-ui-sim (simulator tests unavailable)" >&2
fi
# Python venv for the image comparison of the visual tests.
if [ "$GUI" = 1 ] && [ ! -x "$T/venv/bin/python" ]; then
  python3 -m venv "$T/venv" && "$T/venv/bin/pip" install -q "pillow==11.3.0"
fi
echo "toolchain ready in $T"
