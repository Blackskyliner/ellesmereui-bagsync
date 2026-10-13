#!/usr/bin/env bash
# Builds the project-local toolchain into ./.tools (nothing is installed globally):
#   - Lua 5.1.5 (same language level as the WoW client)
#   - LuaRocks + busted (unit/integration tests) + luacheck (lint)
#   - reference sources: Gethe/wow-ui-source (Blizzard UI 12.x incl. generated API docs),
#     Ketho/vscode-wow-api (API annotations), EllesmereGaming/EllesmereUI (host addon),
#     Blizzard's GlobalStrings of every client locale (Ketho/BlizzardInterfaceResources)
#   - Osso/wow-ui-sim (headless WoW UI simulator, Rust) + Blizzard UI cache for it
# Requires: curl, git, a C compiler, make (Linux: readline headers for Lua);
# cargo, rsync and ICU4C >= 72 (pkg-config) for the simulator, python3 for the checks.
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

# The simulator and EllesmereUI are pinned to revisions the whole suite passes
# against, so a push is judged by its own changes. The simulator's Lua surface
# grows with every commit; EllesmereUI changes almost daily. ELLESMEREUI_REV=latest
# takes EllesmereUI's newest commit instead (.github/workflows/upstream.yml).
WOW_UI_SIM_REV=fcb0b7823d2f70ea61d5b2f2d2b69c94b8920157
ELLESMEREUI_REV="${ELLESMEREUI_REV:-eccc25a0f9ebd18b48a6345654e80e7c78ee4927}"

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
# follow <url> <dir> [branch]: the newest commit of the branch (default: the
# remote's default branch), on every run, like a fresh CI checkout. Offline the
# checkout stays where it is.
follow() {
  local dir="$T/vendor/$2"
  if [ ! -d "$dir" ]; then clone "$@"; return; fi
  if git -C "$dir" fetch -q --depth 1 "$1" "${3:-HEAD}"; then
    git -C "$dir" -c advice.detachedHead=false checkout -q FETCH_HEAD
  else
    echo "offline? keeping $2 at $(git -C "$dir" rev-parse --short HEAD)" >&2
  fi
}
# pinned <url> <dir> <commit|latest>: one commit, fetched without history; a
# checkout at another commit (the pin moved) is moved along.
pinned() {
  local dir="$T/vendor/$2"
  if [ "$3" = latest ]; then clone "$1" "$2"; return; fi
  [ -d "$dir" ] && [ "$(git -C "$dir" rev-parse HEAD 2>/dev/null)" = "$3" ] && return 0
  [ -d "$dir/.git" ] || git init -q "$dir"
  git -C "$dir" fetch -q --depth 1 "$1" "$3"
  git -C "$dir" -c advice.detachedHead=false checkout -q FETCH_HEAD
}
follow https://github.com/Gethe/wow-ui-source.git wow-ui-source live
follow https://github.com/Ketho/vscode-wow-api.git vscode-wow-api
pinned https://github.com/EllesmereGaming/EllesmereUI.git EllesmereUI "$ELLESMEREUI_REV"
if [ "$SIM" = 1 ]; then
  pinned https://github.com/Osso/wow-ui-sim.git wow-ui-sim "$WOW_UI_SIM_REV"
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
  # sim_build <target dir> <features>: builds wow-sim unless the binary there
  # was built from the pinned revision with these features (wow-sim.rev). The
  # stamp lets CI restore only the binary from its cache and skip the Rust build.
  sim_build() {
    local sim="$T/vendor/wow-ui-sim"
    [ -x "$sim/$1/release/wow-sim" ] && [ "$(cat "$sim/$1/release/wow-sim.rev" 2>/dev/null)" = "$WOW_UI_SIM_REV $2" ] && return 0
    (cd "$sim" && CARGO_HOME="$T/cargo" CARGO_TARGET_DIR="$sim/$1" cargo build --release --locked --bin wow-sim \
      --no-default-features --features "$2")
    echo "$WOW_UI_SIM_REV $2" > "$sim/$1/release/wow-sim.rev"
  }
  # wow-ui-sim links ICU4C >= 72 through pkg-config: libicu-dev on Linux, the
  # keg-only icu4c of Homebrew on macOS (not on pkg-config's default path).
  if ! pkg-config --exists 'icu-i18n >= 72' 2>/dev/null && command -v brew >/dev/null 2>&1; then
    export PKG_CONFIG_PATH="$(brew --prefix icu4c)/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
  fi
  # The retail profile at the API of the live client: wow-ui-sim's client-retail
  # bundle trails it, and Blizzard's UI from wow-ui-source live already calls
  # the natives of the newer patch (12.1.5: table.contains, math.clamp, ...).
  SIM_FEATURES=profile-retail,retail-12-1-5,prefork-full-ui
  sim_build target "$SIM_FEATURES"
  # Second build with the GPU renderer for screenshots (visual tests); own
  # target dir so the headless binary above stays untouched.
  if [ "$GUI" = 1 ]; then sim_build target-gui "gui,$SIM_FEATURES"; fi
  # wow-sim reads Blizzard UI from $HOME/Library/Caches (macOS) or ~/.cache; point HOME at .tools/simhome.
  # The copy is redone whenever wow-ui-source moved (.wow-ui-source-rev), so the
  # simulator runs the same Blizzard UI the API check reads.
  C="$T/simhome/Library/Caches/wow-ui-sim/blizzard-ui/retail/AddOns"
  UI_REV="$(git -C "$T/vendor/wow-ui-source" rev-parse HEAD)"
  if [ ! -f "$C/.wow-ui-sim-blizzard-ui-complete" ] || [ "$(cat "$C/.wow-ui-source-rev" 2>/dev/null)" != "$UI_REV" ]; then
    mkdir -p "$C" && rsync -a --delete --exclude '.wow-ui-*' "$T/vendor/wow-ui-source/Interface/AddOns/" "$C/"
    echo "$UI_REV" > "$C/.wow-ui-source-rev"
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
