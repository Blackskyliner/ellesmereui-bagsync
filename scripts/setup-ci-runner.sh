#!/usr/bin/env bash
# Sets up a fresh Debian or Ubuntu machine as the self-hosted runner of the CI
# and Changelog jobs (CONTRIBUTING.md, "Self-hosted runner"). Run it as root on
# the machine itself; running it again is safe.
#
#   RUNNER_TOKEN=<token> ./setup-ci-runner.sh [options]
#
# The registration token is valid for one hour. Get it on your own machine:
#   gh api -X POST repos/Blackskyliner/ellesmereui-bagsync/actions/runners/registration-token -q .token
# Without RUNNER_TOKEN the script asks for it (the input is not shown). It is
# not taken as an argument, so it stays out of the shell history and of ps.
#
# Options:
#   --repo=<owner/name>   repository (default: Blackskyliner/ellesmereui-bagsync)
#   --labels=<a,b>        extra labels (default: eui-ci); GitHub adds
#                         self-hosted, Linux and the architecture itself
#   --name=<name>         runner name (default: the host name)
#   --user=<user>         system user the runner runs as (default: ghrunner)
#   --swap=<size>         swap file for the simulator's Rust build, 0 for none
#                         (default: 4G; skipped when swap exists)
#
# Afterwards set the repository variable CI_RUNNER to the labels as JSON:
#   gh variable set CI_RUNNER --body '["self-hosted","linux","eui-ci"]'
set -euo pipefail

REPO=Blackskyliner/ellesmereui-bagsync
LABELS=eui-ci
NAME="$(hostname)"
RUSER=ghrunner
SWAP=4G
for arg in "$@"; do
  case "$arg" in
    --repo=*) REPO="${arg#*=}" ;;
    --labels=*) LABELS="${arg#*=}" ;;
    --name=*) NAME="${arg#*=}" ;;
    --user=*) RUSER="${arg#*=}" ;;
    --swap=*) SWAP="${arg#*=}" ;;
    -h|--help) sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

step() { printf '\n==> %s\n' "$*"; }
die() { echo "error: $*" >&2; exit 1; }

[ "$(id -u)" = 0 ] || die "run as root"
command -v apt-get >/dev/null || die "Debian or Ubuntu required (apt-get)"
case "$(uname -m)" in
  x86_64) ARCH=x64 ;;
  aarch64) ARCH=arm64 ;;
  *) die "unsupported architecture: $(uname -m)" ;;
esac

# The packages ci.yml installs when they are missing (so the job never needs
# sudo here), what scripts/setup-tools.sh builds with, and what the runner
# itself and this script use.
PACKAGES=(
  ca-certificates curl git jq tar unzip rsync python3 build-essential
  libreadline-dev clang mold pkg-config libicu-dev fonts-dejavu-core libssl-dev
  unattended-upgrades
)
step "Packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get upgrade -y -q
apt-get install -y -q "${PACKAGES[@]}"

step "Automatic security updates"
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

# 4 GB of RAM is tight for the release build of wow-ui-sim; the swap file
# keeps the linker from being killed. A machine with swap is left alone.
if [ "$SWAP" != 0 ] && ! swapon --noheadings --show | grep -q .; then
  step "Swap file ($SWAP)"
  [ -f /swapfile ] || { fallocate -l "$SWAP" /swapfile; chmod 600 /swapfile; mkswap /swapfile >/dev/null; }
  swapon /swapfile
  grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# A user without a password, without sudo and outside the admin groups: a job
# can change its own home and work directory, nothing else on the machine.
step "Runner user $RUSER"
if ! id "$RUSER" >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash "$RUSER"
fi
passwd -l "$RUSER" >/dev/null
for group in sudo admin wheel docker; do
  if id -nG "$RUSER" | tr ' ' '\n' | grep -qx "$group"; then gpasswd -d "$RUSER" "$group" >/dev/null; fi
done
[ ! -e "/etc/sudoers.d/$RUSER" ] || die "/etc/sudoers.d/$RUSER grants $RUSER sudo; remove it first"
HOME_DIR="$(getent passwd "$RUSER" | cut -d: -f6)"
DIR="$HOME_DIR/actions-runner"
chmod 750 "$HOME_DIR"

# The newest runner release, checked against the SHA-256 that GitHub puts in
# the release notes.
step "GitHub Actions runner"
if [ ! -x "$DIR/config.sh" ]; then
  release="$(curl -fsSL https://api.github.com/repos/actions/runner/releases/latest)"
  version="$(jq -r .tag_name <<<"$release" | sed 's/^v//')"
  expected="$(jq -r .body <<<"$release" | sed -n "s/.*<!-- BEGIN SHA linux-$ARCH -->\([0-9a-f]\{64\}\)<!-- END SHA linux-$ARCH -->.*/\1/p")"
  [ -n "$version" ] && [ -n "$expected" ] || die "no runner release or checksum found"
  tarball="actions-runner-linux-$ARCH-$version.tar.gz"
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  curl -fsSL -o "$tmp/$tarball" "https://github.com/actions/runner/releases/download/v$version/$tarball"
  echo "$expected  $tmp/$tarball" | sha256sum -c - >/dev/null || die "checksum mismatch for $tarball"
  install -d -o "$RUSER" -g "$RUSER" -m 750 "$DIR"
  tar -xzf "$tmp/$tarball" -C "$DIR"
  chown -R "$RUSER:$RUSER" "$DIR"
  # the tarball's own root entry resets the mode install set
  chmod 750 "$DIR"
  echo "runner $version installed in $DIR"
else
  echo "already installed in $DIR (it updates itself)"
fi
"$DIR/bin/installdependencies.sh" >/dev/null

if [ ! -f "$DIR/.runner" ]; then
  step "Register with $REPO"
  if [ -z "${RUNNER_TOKEN:-}" ]; then
    read -r -s -p "Registration token: " RUNNER_TOKEN; echo
  fi
  [ -n "$RUNNER_TOKEN" ] || die "no registration token"
  # The token goes through stdin of su, not its command line.
  printf '%s\n' "$RUNNER_TOKEN" | su - "$RUSER" -c "cd '$DIR' && IFS= read -r token && ./config.sh --unattended --replace \
    --url 'https://github.com/$REPO' --token \"\$token\" --name '$NAME' --labels '$LABELS' --work _work"
else
  echo "already registered ($DIR/.runner); remove it with ./config.sh remove as $RUSER to register again"
fi

step "Service"
cd "$DIR"
if ! ./svc.sh status >/dev/null 2>&1 || ./svc.sh status 2>&1 | grep -q 'not installed'; then
  ./svc.sh install "$RUSER"
fi
./svc.sh start
./svc.sh status | sed -n '1,5p'

labels_json="$(jq -cn --arg l "$LABELS" '["self-hosted","linux"] + ($l | split(",") | map(select(. != "")))')"
cat <<EOF

Done. The runner should show as "Idle" under
  https://github.com/$REPO/settings/actions/runners
Then point the jobs at it:
  gh variable set CI_RUNNER --repo $REPO --body '$labels_json'
Unset the variable again when the runner goes offline:
  gh variable delete CI_RUNNER --repo $REPO
The runner needs no inbound ports: allow only SSH in the firewall.
EOF
