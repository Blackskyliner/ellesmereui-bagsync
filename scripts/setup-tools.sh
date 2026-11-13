#!/usr/bin/env bash
# Builds the project-local toolchain into ./.tools (nothing is installed globally):
#   - Lua 5.1.5 (same language level as the WoW client)
#   - LuaRocks + busted (unit/integration tests) + luacheck (lint)
#   - reference sources: Gethe/wow-ui-source (Blizzard UI incl. generated API docs, at
#     the retail 12.x and WoW Forever 1.60 builds the simulator pins),
#     Ketho/vscode-wow-api (API annotations), EllesmereGaming/EllesmereUI (host addon),
#     Blizzard's GlobalStrings of every client locale (Ketho/BlizzardInterfaceResources)
#   - Osso/wow-ui-sim (WoW UI simulator, Rust, with its GPU renderer) per client + Blizzard UI cache for it
# Requires: curl, git, a C compiler, make (Linux: readline headers for Lua);
# cargo, rsync and ICU4C >= 72 (pkg-config) for the simulator, python3 for the checks.
#
# Options (CI):
#   --no-sim          skip wow-ui-sim and the Python venv (lint, API check, busted only)
#   --client=<name>   build the simulator for one client only: retail or forever
#                     (default: both)
# Environment:
#   SIM_CARGO_DIR     keeps cargo's registry and build directory there instead
#                     of in .tools, so a machine whose .tools is wiped per run
#                     (a self-hosted CI runner) recompiles only what changed
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$ROOT/.tools"
SIM=1 CLIENTS="retail forever"
for arg in "$@"; do
  case "$arg" in
    --no-sim) SIM=0 ;;
    --client=retail|--client=forever) CLIENTS="${arg#--client=}" ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done
wants() { case " $CLIENTS " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }
sha256() {
  [ -f "$1" ] || return 0
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d" " -f1
}
mkdir -p "$T/src" "$T/vendor"

# The simulator and EllesmereUI are pinned to revisions the whole suite passes
# against, so a push is judged by its own changes. The simulator's Lua surface
# grows with every commit; EllesmereUI changes almost daily. ELLESMEREUI_REV=latest
# takes EllesmereUI's newest commit instead (.github/workflows/upstream.yml).
# Both clients build from the same revision, each in its own checkout.
WOW_UI_SIM_REV=54acfb8e01a938d1e1b374c53976e16abf6e35d6
WOW_UI_SIM_FOREVER_REV=54acfb8e01a938d1e1b374c53976e16abf6e35d6
# Blizzard's UI source (Gethe/wow-ui-source) at the client builds the
# simulator pins (its data/blizzard-ui-builds/<profile>.json, checked below):
# the simulator only runs the Blizzard UI of that build, and the API check
# reads the same tree. Moving the simulator pin moves these with it.
GETHE_RETAIL_REV=15881d522c44cd106d3d8660106ec9f9d2f44167  # 12.1.5.70575
GETHE_FOREVER_REV=aff0d8cd53bf4d9ef1c1dd2786b94461a276fb16 # 1.60.1.70707
# Fixes the suite needs before upstream has them: scripts/patches/<checkout>/
# holds them as git patches, each naming its upstream pull request, applied on
# top of the pin. scripts/patches/wow-ui-sim-forever links to wow-ui-sim's,
# as both checkouts sit at the same revision; it becomes a directory of its
# own when the pins part.
# wow-ui-sim 0001: FontString:SetFont with an addon's font file falls back to
# the default font; this loads the file
# (https://github.com/Osso/wow-ui-sim/pull/59). 0002: without a WoW install
# the default font is the first system font, which differs between macOS and
# Linux; WOW_SIM_FALLBACK_FONT pins it
# (https://github.com/Osso/wow-ui-sim/pull/60). 0003: an EditBox ignored its
# template's <FontString> and <TextInsets> (yellow text, no font object, no
# inset) and centered its text, where the client starts it at the left
# (https://github.com/Osso/wow-ui-sim/pull/61). 0004: text dropped inline
# |T and |A escapes and measured without them; the icons are drawn in the
# line, their widths counted and a line of icons alone is one line high, so
# tooltip location icons and separators render
# (https://github.com/Osso/wow-ui-sim/pull/62).
# The Forever profile reads selected spell data of client build 1.60.1.70685,
# which wow-cli generates from Blizzard's CDN (wow-ui-sim
# docs/specs/forever-spell-data.md gives this checksum for it).
FOREVER_SPELLS_SHA256=13122873d813481e85815946ddf964068b04132d4d2b2b44ba5ce61491595ad0
ELLESMEREUI_REV="${ELLESMEREUI_REV:-aa82437a3a60ac078fd7772942ea9d8f97f8036e}"

case "$(uname -s)" in Darwin) LUA_TARGET=macosx ;; *) LUA_TARGET=linux ;; esac
# Lua's sources from lua.org, else from the mirror at PUC-Rio (another host):
# lua.org is at times unreachable from CI runners. The checksum is the one
# both serve for lua-5.1.5.tar.gz.
LUA_SHA256=2640fc56a795f29d28ef15e13c34a47e223960b0240e8cb0a82d9b0738695333
fetch_lua() {
  local url sum
  for url in https://www.lua.org/ftp/lua-5.1.5.tar.gz \
             https://webserver2.tecgraf.puc-rio.br/lua/ftp/lua-5.1.5.tar.gz; do
    if curl -sSfL --connect-timeout 20 --retry 3 --retry-all-errors -o lua-5.1.5.tar.gz "$url"; then
      sum=$( (sha256sum lua-5.1.5.tar.gz 2>/dev/null || shasum -a 256 lua-5.1.5.tar.gz) | cut -d' ' -f1)
      [ "$sum" = "$LUA_SHA256" ] && return 0
      echo "lua-5.1.5.tar.gz from $url: checksum $sum" >&2
    fi
  done
  return 1
}
if [ ! -x "$T/lua/bin/lua" ]; then
  (cd "$T/src" && fetch_lua && tar xzf lua-5.1.5.tar.gz \
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
  # -f: patches applied to the old pin (patched below) must not block the move.
  git -C "$dir" -c advice.detachedHead=false checkout -q -f FETCH_HEAD
}
# patches_id <checkout>: identifies the patch set of scripts/patches/<checkout>
# (empty without patches), for the build stamp and the CI cache key.
patches_id() {
  local p="$ROOT/scripts/patches/$1"
  ls "$p"/*.patch >/dev/null 2>&1 || return 0
  cat "$p"/*.patch | if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi | cut -c1-12
}
# patched <checkout>: applies scripts/patches/<checkout>/*.patch in name order
# to the pinned commit; a checkout already carrying this set is left as it is,
# so its sources keep their timestamps.
patched() {
  local dir="$T/vendor/$1" id want have
  id="$(patches_id "$1")"
  [ -n "$id" ] || return 0
  want="$(git -C "$dir" rev-parse HEAD) $id"
  have="$(cat "$dir/.git/eui-patches" 2>/dev/null || true)"
  [ "$have" = "$want" ] && return 0
  git -C "$dir" checkout -q -f HEAD
  # checkout leaves the files an earlier patch set created; git apply would
  # stop at those the set creates again.
  sed -n '/^--- \/dev\/null$/{n;s|^+++ b/||p;}' "$ROOT"/scripts/patches/"$1"/*.patch \
    | while read -r f; do rm -f "$dir/$f"; done
  git -C "$dir" apply "$ROOT"/scripts/patches/"$1"/*.patch
  echo "$want" > "$dir/.git/eui-patches"
}
pinned https://github.com/Gethe/wow-ui-source.git wow-ui-source "$GETHE_RETAIL_REV"
pinned https://github.com/Gethe/wow-ui-source.git wow-ui-source-forever "$GETHE_FOREVER_REV"
# gethe_pin_matches <sim checkout> <profile> <revision>: the Gethe pin above
# must be the source revision the simulator pins for that profile.
gethe_pin_matches() {
  local want
  want="$(sed -n 's/.*"gethe_revision": *"\([0-9a-f]*\)".*/\1/p' "$T/vendor/$1/data/blizzard-ui-builds/$2.json")"
  [ "$want" = "$3" ] || { echo "wow-ui-sim pins $2 to Gethe $want; update GETHE_*_REV" >&2; exit 1; }
}
follow https://github.com/Ketho/vscode-wow-api.git vscode-wow-api
pinned https://github.com/EllesmereGaming/EllesmereUI.git EllesmereUI "$ELLESMEREUI_REV"
if [ "$SIM" = 1 ]; then
  if wants retail; then
    pinned https://github.com/Osso/wow-ui-sim.git wow-ui-sim "$WOW_UI_SIM_REV"
    patched wow-ui-sim
    gethe_pin_matches wow-ui-sim retail "$GETHE_RETAIL_REV"
  fi
  if wants forever; then
    pinned https://github.com/Osso/wow-ui-sim.git wow-ui-sim-forever "$WOW_UI_SIM_FOREVER_REV"
    patched wow-ui-sim-forever
    gethe_pin_matches wow-ui-sim-forever wowforever "$GETHE_FOREVER_REV"
  fi
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
  # sim_build <checkout> <revision> <target dir> <features> [binary]: builds
  # the binary (default wow-sim) unless the one there was built from that
  # revision and patch set with these features against the ICU installed now
  # (<binary>.rev): it links ICU's versioned libraries, so an ICU update
  # (Homebrew, a new runner image) leaves it unable to start. The stamp lets CI
  # restore only the binary from its cache and skip the Rust build.
  # With SIM_CARGO_DIR every checkout and feature set builds in one directory
  # there: cargo keeps each crate per feature set side by side, so the two
  # clients share the dependencies they have in common, and only the binary
  # is copied to <checkout>/<target dir>, where the scripts look for it.
  sim_build() {
    local sim="$T/vendor/$1" bin="${5:-wow-sim}" stamp patches home="$T/cargo" target
    target="$sim/$3"
    patches="$(patches_id "$1")"
    stamp="$2 $4 icu-$(pkg-config --modversion icu-i18n 2>/dev/null)${patches:+ patches-$patches}"
    [ -x "$target/release/$bin" ] && [ "$(cat "$target/release/$bin.rev" 2>/dev/null)" = "$stamp" ] && return 0
    if [ -n "${SIM_CARGO_DIR:-}" ]; then home="$SIM_CARGO_DIR/home" target="$SIM_CARGO_DIR/target"; fi
    (cd "$sim" && CARGO_HOME="$home" CARGO_TARGET_DIR="$target" cargo build --release --locked --bin "$bin" \
      --no-default-features --features "$4")
    if [ "$target" != "$sim/$3" ]; then
      mkdir -p "$sim/$3/release" && cp "$target/release/$bin" "$sim/$3/release/$bin"
    fi
    echo "$stamp" > "$sim/$3/release/$bin.rev"
  }
  # Each pin and feature set adds its own build to SIM_CARGO_DIR; past this
  # size the build directory starts over, the registry stays.
  if [ -n "${SIM_CARGO_DIR:-}" ] && [ -d "$SIM_CARGO_DIR/target" ] \
      && [ "$(du -sk "$SIM_CARGO_DIR/target" | cut -f1)" -gt $((30 * 1024 * 1024)) ]; then
    echo "SIM_CARGO_DIR: build directory over 30 GB, starting over" >&2
    rm -rf "${SIM_CARGO_DIR:?}/target"
  fi
  # wow-sim reads Blizzard UI from $HOME/Library/Caches (macOS) or ~/.cache;
  # HOME points at .tools/simhome, where both lead to the same directory.
  mkdir -p "$T/simhome/.cache" "$T/simhome/Library/Caches/wow-ui-sim"
  ln -sfn "$T/simhome/Library/Caches/wow-ui-sim" "$T/simhome/.cache/wow-ui-sim"
  # ui_sync <checkout> <profile> <Gethe revision>: retail runs only the
  # Blizzard UI of the build the simulator pins, which it downloads from
  # Blizzard's CDN itself when its cache lacks it; one start of wow-sim fills
  # the cache, so the tests start offline.
  ui_sync() {
    local c="$T/simhome/Library/Caches/wow-ui-sim/blizzard-ui/$2/AddOns"
    grep -qx "gethe_revision=$3" "$c/.wow-ui-sim-blizzard-ui-provenance" 2>/dev/null && return 0
    echo "syncing the $2 Blizzard UI from Blizzard's CDN (log: $T/ui-sync-$2.log)" >&2
    (cd "$T/vendor/$1" && HOME="$T/simhome" ./target/release/wow-sim --no-addons --no-saved-vars \
      dump-tree --filter UIParent >/dev/null 2>"$T/ui-sync-$2.log") || true
    grep -qx "gethe_revision=$3" "$c/.wow-ui-sim-blizzard-ui-provenance" \
      || { tail -20 "$T/ui-sync-$2.log" >&2; echo "wow-sim did not fill its $2 Blizzard UI cache" >&2; exit 1; }
  }
  # ui_cache <source checkout> <profile>: Forever's Blizzard UI comes from a
  # WoW install there; without one the cache is a copy of the Gethe tree at
  # the build the simulator pins, redone whenever the source moved
  # (.wow-ui-source-rev).
  ui_cache() {
    local c="$T/simhome/Library/Caches/wow-ui-sim/blizzard-ui/$2/AddOns" rev
    rev="$(git -C "$T/vendor/$1" rev-parse HEAD)"
    if [ ! -f "$c/.wow-ui-sim-blizzard-ui-complete" ] || [ "$(cat "$c/.wow-ui-source-rev" 2>/dev/null)" != "$rev" ]; then
      mkdir -p "$c" && rsync -a --delete --exclude '.wow-ui-*' "$T/vendor/$1/Interface/AddOns/" "$c/"
      echo "$rev" > "$c/.wow-ui-source-rev"
      touch "$c/.wow-ui-sim-blizzard-ui-complete"
      printf 'profile=%s\nsource=gethe-image-build\nfallback=none\n' "$2" > "$c/.wow-ui-sim-blizzard-ui-provenance"
    fi
  }
  # wow-ui-sim links ICU4C >= 72 through pkg-config: libicu-dev on Linux, the
  # keg-only icu4c of Homebrew on macOS (not on pkg-config's default path).
  if ! pkg-config --exists 'icu-i18n >= 72' 2>/dev/null && command -v brew >/dev/null 2>&1; then
    export PKG_CONFIG_PATH="$(brew --prefix icu4c)/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
  fi
  # One build per client, with the GPU renderer (gui): the same binary runs
  # the tests headless and renders the screenshots of the visual tests.
  SIM_FEATURES=gui,client-retail
  FOREVER_SIM_FEATURES=gui,client-wowforever,prefork-full-ui
  if wants retail; then
    sim_build wow-ui-sim "$WOW_UI_SIM_REV" target "$SIM_FEATURES"
    ui_sync wow-ui-sim retail "$GETHE_RETAIL_REV"
  fi
  if wants forever; then
    sim_build wow-ui-sim-forever "$WOW_UI_SIM_FOREVER_REV" target "$FOREVER_SIM_FEATURES"
    ui_cache wow-ui-source-forever wowforever
    SPELLS="$T/simhome/Library/Caches/wow-ui-sim/spells/wowforever/spells.json"
    if [ "$(sha256 "$SPELLS")" != "$FOREVER_SPELLS_SHA256" ]; then
      # wow-cli is only needed for this file (CI keeps the file in its cache).
      sim_build wow-ui-sim-forever "$WOW_UI_SIM_FOREVER_REV" target-cli "tools,casc,$FOREVER_SIM_FEATURES" wow-cli
      mkdir -p "$(dirname "$SPELLS")"
      "$T/vendor/wow-ui-sim-forever/target-cli/release/wow-cli" casc sync-forever-spells --source cdn --output "$SPELLS"
      [ "$(sha256 "$SPELLS")" = "$FOREVER_SPELLS_SHA256" ] \
        || { echo "Forever spell data does not match FOREVER_SPELLS_SHA256" >&2; exit 1; }
    fi
  fi
else
  echo "cargo not found: skipping wow-ui-sim (simulator tests unavailable)" >&2
fi
# Python venv for the image comparison of the visual tests.
if [ "$SIM" = 1 ] && [ ! -x "$T/venv/bin/python" ]; then
  python3 -m venv "$T/venv" && "$T/venv/bin/pip" install -q "pillow==11.3.0"
fi
echo "toolchain ready in $T"
