#!/usr/bin/env bash
# Runs the release packaging locally without uploading anything: the same
# BigWigsMods/packager version as .github/workflows/release.yml, on a temporary
# clone of HEAD tagged with the TOC version, then compares the package with
# scripts/package.sh. Needs bash >= 4.3 for the packager; on macOS (bash 3.2)
# a bash is built into .tools/bash once.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$ROOT/.tools"
PACKAGER_REV=v2.6.1     # keep in sync with .github/workflows/release.yml
BASH_VERSION_SRC=5.2.37

PACKAGER="$T/vendor/packager-$PACKAGER_REV/release.sh"
if [ ! -f "$PACKAGER" ]; then
  mkdir -p "$(dirname "$PACKAGER")"
  curl -sSfL -o "$PACKAGER" "https://raw.githubusercontent.com/BigWigsMods/packager/$PACKAGER_REV/release.sh"
fi

BASH5=bash
if [ "$(bash -c 'echo ${BASH_VERSINFO[0]}')" -lt 5 ]; then
  BASH5="$T/bash/bin/bash"
  if [ ! -x "$BASH5" ]; then
    (mkdir -p "$T/src" && cd "$T/src" && curl -sSfLO "https://ftp.gnu.org/gnu/bash/bash-$BASH_VERSION_SRC.tar.gz" \
      && tar xzf "bash-$BASH_VERSION_SRC.tar.gz" && cd "bash-$BASH_VERSION_SRC" \
      && ./configure --prefix="$T/bash" --without-bash-malloc >/dev/null && make -j4 >/dev/null && make install >/dev/null)
  fi
fi

VERSION="$(sed -n 's/^## Version: *//p' "$ROOT/EllesmereUIBags_Alts/EllesmereUIBags_Alts.toc" | tr -d '\r')"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
git clone -q "$ROOT" "$WORK/repo"
git -C "$WORK/repo" -c advice.detachedHead=false checkout -q "$(git -C "$ROOT" rev-parse HEAD)"
git -C "$WORK/repo" tag "$VERSION"

bash "$ROOT/scripts/release-check.sh" "$VERSION" "$WORK/repo/.release-notes.md"
(cd "$WORK/repo" && "$BASH5" "$PACKAGER" -d -u) > "$WORK/packager.log" 2>&1 \
  || { cat "$WORK/packager.log"; exit 1; }
grep -E '^(Current version|Build type|Game version):|[Cc]hangelog' "$WORK/packager.log"

PKG="$WORK/repo/.release/EllesmereUIBags_Alts-$VERSION.zip"
PACKED="$(DIST="$WORK/dist" bash "$ROOT/scripts/package.sh")"
OURS="${PACKED%%$'\n'*}"
mkdir -p "$WORK/a" "$WORK/b"
unzip -q "$PKG" -d "$WORK/a"
unzip -q "$OURS" -d "$WORK/b"
if diff -r "$WORK/b" "$WORK/a" >/dev/null; then
  echo "packager output equals $(basename "$OURS")"
else
  diff -r "$WORK/b" "$WORK/a" | head -20
  echo "packager output differs from scripts/package.sh" >&2
  exit 1
fi
echo "changelog:"
sed 's/^/  /' "$WORK/repo/.release-notes.md"
