#!/usr/bin/env bash
# install-incus.sh — Ubuntu 24.04+: Install Incus + Btrfs storage + bridge networking
# Options:
#   --use-zabbly     Use Zabbly repo (feature releases; provides incus-ui-canonical)
#   --with-vm        Install QEMU/OVMF for VM support
#   --migrate        Install incus-tools (lxd-to-incus)
#   --ui             Install Incus Web UI (requires --use-zabbly)
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

# --- OS checks ---
. /etc/os-release
[[ "${ID:-}" == "ubuntu" ]] || { echo "This script targets Ubuntu; got ID=${ID:-?}." >&2; exit 1; }
dpkg --compare-versions "${VERSION_ID:-0}" ge 24.04 || { echo "Need Ubuntu 24.04+." >&2; exit 1; }

CALLER_USER=${SUDO_USER:-$USER}

# --- Optional Zabbly repo (feature releases + Web UI) ---
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

echo "Updating APT..."
apt-get update -y

# --- Install packages ---
PKGS=(incus)
[[ $WITH_VM -eq 1 ]] && PKGS+=(qemu-system ovmf)
[[ $WITH_MIGRATE -eq 1 ]] && PKGS+=(incus-tools)
[[ $WITH_UI -eq 1 ]] && PKGS+=(incus-ui-canonical)

echo "Installing: ${PKGS[*]}"
DEBIAN_FRONTEND=noninteractive apt-get install -y "${PKGS[@]}"

# --- Enable & start incus service ---
systemctl enable --now incus

# --- Group + helper to run as user inside incus-admin group ---
getent group incus-admin >/dev/null || groupadd -f incus-admin
usermod -aG incus-admin "$CALLER_USER"

run_as_incus_admin() {
  local cmd="$1"
  sudo -u "$CALLER_USER" sg incus-admin -c "$cmd"
}

# --- Initialize Incus (minimal or interactive) ---
if [[ $NONINTERACTIVE -eq 1 ]]; then
  echo "Running non-interactive init (minimal defaults) as $CALLER_USER..."
  run_as_incus_admin "incus admin init --minimal || true"
else
  echo "Running interactive initializer as $CALLER_USER..."
  run_as_incus_admin "incus admin init || true"
fi

# --- Btrfs storage pool 'default' ---
BTRFS_POOL=default
BTRFS_PATH=/var/lib/incus/storage-pools/${BTRFS_POOL}

echo "Configuring Btrfs storage pool '${BTRFS_POOL}' at ${BTRFS_PATH}..."
if run_as_incus_admin "incus storage show ${BTRFS_POOL} >/dev/null 2>&1"; then
  echo "Storage pool '${BTRFS_POOL}' already exists. Skipping create."
else
  if [[ -d "${BTRFS_PATH}" ]]; then
    if [[ -z "$(find "${BTRFS_PATH}" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
      echo "Removing empty pre-created directory ${BTRFS_PATH} so Incus can create it..."
      rmdir "${BTRFS_PATH}"
    else
      echo "ERROR: ${BTRFS_PATH} exists and is not empty. Move contents or choose another pool/path." >&2
      exit 1
    fi
  fi
  run_as_incus_admin "incus storage create ${BTRFS_POOL} btrfs source=${BTRFS_PATH}"
fi

# --- Ensure default profile has a root disk on that pool ---
echo "Ensuring 'default' profile has root disk on pool '${BTRFS_POOL}'..."
if run_as_incus_admin "incus profile show default | grep -q '^  root:'"; then
  echo "Root disk already present on 'default' profile."
else
  run_as_incus_admin "incus profile device add default root disk path=/ pool=${BTRFS_POOL}"
fi

# --- Networking: create NAT bridge incusbr0 and attach to default profile ---
BRIDGE=incusbr0
echo "Configuring managed bridge '${BRIDGE}' (IPv4 NAT, no IPv6)..."
if run_as_incus_admin "incus network show ${BRIDGE} >/dev/null 2>&1"; then
  echo "Network '${BRIDGE}' already exists. Skipping create."
else
  run_as_incus_admin "incus network create ${BRIDGE} ipv4.address=auto ipv4.nat=true ipv6.address=none"
fi

echo "Ensuring 'default' profile has NIC 'eth0' on '${BRIDGE}'..."
if run_as_incus_admin "incus profile show default | grep -q '^  eth0:'"; then
  echo "NIC 'eth0' already present on 'default' profile."
else
  run_as_incus_admin "incus profile device add default eth0 nic nictype=bridged parent=${BRIDGE} name=eth0"
fi

# --- Status ---
echo "Verifying daemon & socket..."
ls -l /var/lib/incus/unix.socket || true
systemctl --no-pager --full status incus | sed -n '1,12p' || true

cat <<'EOF'

All set ✅

You can now launch a container with networking:
  incus launch images:ubuntu/24.04 demo
  incus list

If you open a *previously existing* shell and hit permissions, run:
  newgrp incus-admin

Autostart a container at boot (optional):
  incus config set demo boot.autostart true

Web UI (if installed from Zabbly):
  incus webui

Migrate from LXD:
  sudo lxd-to-incus
EOF
