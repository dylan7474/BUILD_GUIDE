#!/usr/bin/env bash
# install-incus.sh — Install and bootstrap Incus on Ubuntu 24.04+
# Usage:
#   bash install-incus.sh [--use-zabbly] [--with-vm] [--migrate] [--ui] [--noninteractive]
#   --use-zabbly     Use Zabbly APT repo (newer feature releases of Incus)
#   --with-vm        Install QEMU bits so you can run Incus VMs too
#   --migrate        Install incus-tools (lxd-to-incus) for LXD migration
#   --ui             Install the Incus Web UI package (from Zabbly only)
#   --noninteractive Run incus admin init --minimal (skips interactive questions)

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

# 1) Sanity checks
. /etc/os-release
if [[ "${ID:-}" != "ubuntu" ]]; then
  echo "This script targets Ubuntu. Detected ID=${ID:-unknown}. Aborting." >&2
  exit 1
fi

UBU_VER="${VERSION_ID:-0}"
if dpkg --compare-versions "$UBU_VER" lt "24.04"; then
  echo "Ubuntu ${UBU_VER} detected. This script expects 24.04 or newer." >&2
  exit 1
fi

echo "Ubuntu $UBU_VER detected."

# 2) Optional: add Zabbly repo (feature releases)
if [[ $NEED_ZABBLY -eq 1 ]]; then
  echo "Adding Zabbly Incus repository..."
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
fi

# 3) Install packages
echo "Updating package lists..."
apt-get update -y

# Base Incus (Ubuntu archive or Zabbly, depending on above)
PKGS=(incus)

# VM support (QEMU & firmware meta)
if [[ $WITH_VM -eq 1 ]]; then
  # 'qemu-system' is enough per upstream docs; include ovmf where available
  PKGS+=(qemu-system ovmf)
fi

# LXD migration tool
if [[ $WITH_MIGRATE -eq 1 ]]; then
  PKGS+=(incus-tools)
fi

# Incus Web UI (package name provided by Zabbly)
if [[ $WITH_UI -eq 1 ]]; then
  if [[ $NEED_ZABBLY -ne 1 ]]; then
    echo "Note: --ui requires --use-zabbly (Web UI package comes from Zabbly). Enabling Zabbly."
    NEED_ZABBLY=1
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
    apt-get update -y
  fi
  PKGS+=(incus-ui-canonical)
fi

echo "Installing: ${PKGS[*]}"
DEBIAN_FRONTEND=noninteractive apt-get install -y "${PKGS[@]}"

# 4) Add current user to incus-admin group
CALLER_USER=${SUDO_USER:-$USER}
if ! getent group incus-admin >/dev/null; then
  # Should be created by packages, but ensure it exists
  groupadd -f incus-admin
fi
usermod -aG incus-admin "$CALLER_USER"

# 5) Initialize Incus
if [[ $NONINTERACTIVE -eq 1 ]]; then
  echo "Running non-interactive init (minimal defaults)..."
  # Minimal: default 'dir' storage and a basic bridge; you can reconfigure later.
  incus admin init --minimal || true
else
  echo
  echo "Incus installed. You can run the interactive initializer now:"
  echo "  sudo -u \"$CALLER_USER\" incus admin init"
  echo
fi

echo
echo "Done."
echo "User '$CALLER_USER' added to 'incus-admin'. Open a NEW terminal or run 'newgrp incus-admin' to use Incus without sudo."
echo
echo "Quick test:"
echo "  incus version"
echo "  incus launch images:ubuntu/24.04 demo"
echo "  incus list"
echo
echo "Optional (Web UI from Zabbly):"
echo "  incus webui"
echo
echo "If migrating from LXD, run:"
echo "  sudo lxd-to-incus"
echo
