#!/usr/bin/env bash
# install-incus.sh — Install and bootstrap Incus on Ubuntu 24.04+
# Options:
#   --use-zabbly     Use Zabbly APT repo (feature releases)
#   --with-vm        Install QEMU/OVMF for VM support
#   --migrate        Install incus-tools (lxd-to-incus)
#   --ui             Install Incus Web UI (requires Zabbly)
#   --noninteractive Run 'incus admin init --minimal' non-interactively

set -euo pipefail

NEED_ZABBLY=0
WITH_VM=0
WITH_MIGRATE=0
WITH_UI=0
NONINTERACTIVE=0

for arg in "$@"; do
  case "$arg" in
    --use-zabbly) NEED_ZABBLY=1 ;;
    --with-vm) WITH_VM=1 ;;
    --migrate) WITH_MIGRATE=1 ;;
    --ui) WITH_UI=1 ;;
    --noninteractive) NONINTERACTIVE=1 ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

if [[ $EUID -ne 0 ]]; then
  echo "Re-running with sudo..."
  exec sudo -E bash "$0" "$@"
fi

. /etc/os-release
if [[ "${ID:-}" != "ubuntu" ]]; then
  echo "This script targets Ubuntu. Detected ID=${ID:-unknown}." >&2
  exit 1
fi
UBU_VER="${VERSION_ID:-0}"
dpkg --compare-versions "$UBU_VER" ge "24.04" || { echo "Ubuntu $UBU_VER detected; need 24.04+." >&2; exit 1; }

CALLER_USER=${SUDO_USER:-$USER}
ARCH=$(dpkg --print-architecture)
[[ "$ARCH" =~ ^(amd64|arm64)$ ]] || echo "Warning: architecture '$ARCH' may not have all packages."

# Optional: Zabbly repo (Incus feature releases + Web UI)
maybe_add_zabbly() {
  mkdir -p /etc/apt/keyrings
  curl -fsSL https://pkgs.zabbly.com/key.asc -o /etc/apt/keyrings/zabbly.asc
  chmod 0644 /etc/apt/keyrings/zabbly.asc
  cat >/etc/apt/sources.list.d/zabbly-incus-stable.sources <<'EOF'
Enabled: yes
Types: deb
URIs: https://pkgs.zabbly.com/incus/stable
Suites: noble
Components: main
Architectures: amd64 arm64
Signed-By: /etc/apt/keyrings/zabbly.asc
EOF
}

if [[ $WITH_UI -eq 1 && $NEED_ZABBLY -ne 1 ]]; then
  echo "Note: --ui requires --use-zabbly. Enabling Zabbly."
  NEED_ZABBLY=1
fi
[[ $NEED_ZABBLY -eq 1 ]] && maybe_add_zabbly

echo "Updating package lists..."
apt-get update -y

PKGS=(incus)
[[ $WITH_VM -eq 1 ]] && PKGS+=(qemu-system ovmf)
[[ $WITH_MIGRATE -eq 1 ]] && PKGS+=(incus-tools)
[[ $WITH_UI -eq 1 ]] && PKGS+=(incus-ui-canonical)

echo "Installing: ${PKGS[*]}"
DEBIAN_FRONTEND=noninteractive apt-get install -y "${PKGS[@]}"

# Ensure service is enabled and running
systemctl enable --now incus

# Ensure group and add caller
getent group incus-admin >/dev/null || groupadd -f incus-admin
usermod -aG incus-admin "$CALLER_USER"

# Helper: run a command as CALLER_USER inside incus-admin group (so no relogin needed)
run_as_incus_admin() {
  local cmd="$1"
  # Use 'sg' to switch to incus-admin group and 'sudo -u' to drop to the caller user
  sudo -u "$CALLER_USER" sg incus-admin -c "$cmd"
}

# Initialize immediately under correct group (no logout required)
if [[ $NONINTERACTIVE -eq 1 ]]; then
  echo "Running non-interactive init (minimal defaults) as $CALLER_USER..."
  run_as_incus_admin "incus admin init --minimal || true"
else
  echo "Running interactive initializer as $CALLER_USER (press Enter through defaults if unsure)..."
  run_as_incus_admin "incus admin init || true"
fi

# Show socket perms and quick sanity checks
echo "Verifying daemon and socket..."
ls -l /var/lib/incus/unix.socket || true
systemctl --no-pager --full status incus | sed -n '1,12p' || true

cat <<EOF

Done.
User '$CALLER_USER' is in 'incus-admin' and initialization ran under that group,
so you can use Incus immediately in this shell.

Quick test (run as $CALLER_USER):
  incus version
  incus launch images:ubuntu/24.04 demo
  incus list

If you still get permission issues in an *existing* shell, run:
  newgrp incus-admin

Web UI (if installed):
  incus webui

LXD migration:
  sudo lxd-to-incus
EOF
