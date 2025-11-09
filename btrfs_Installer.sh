#!/usr/bin/env bash
# Ubuntu 24.04 Btrfs + Snapper + grub-btrfs bootstrap
# Sets up manual snapshots with bootable entries, plus helper commands.

set -euo pipefail

# --- Safety & environment checks ---
if [ "$(id -u)" -ne 0 ]; then
  echo "Please run as root (use: sudo bash $0)"; exit 1
fi

if ! command -v findmnt >/dev/null 2>&1; then
  apt update && apt install -y util-linux
fi

ROOT_FSTYPE="$(findmnt -no FSTYPE / || true)"
if [ "$ROOT_FSTYPE" != "btrfs" ]; then
  echo "ERROR: / is not on Btrfs (detected: ${ROOT_FSTYPE})."
  echo "This script expects a fresh Ubuntu installed with a Btrfs root."
  exit 1
fi

echo "✅ Detected Btrfs on /"

# --- Repositories & base packages ---
echo "==> Enabling Universe & updating..."
sed -i 's/^# deb/deb/' /etc/apt/sources.list || true
apt update

echo "==> Installing packages..."
DEBIAN_FRONTEND=noninteractive apt install -y \
  snapper inotify-tools dbus git make python3

# Ensure dbus is available on next boots
systemctl enable dbus.service >/dev/null 2>&1 || true

# --- Snapper config ---
echo "==> Ensuring /.snapshots is a Btrfs subvolume and creating Snapper config..."
if [ -e "/.snapshots" ] && ! btrfs subvolume show /.snapshots >/dev/null 2>&1; then
  # Exists but not a subvolume
  rmdir /.snapshots 2>/dev/null || true
fi
if ! btrfs subvolume show /.snapshots >/dev/null 2>&1; then
  btrfs subvolume create /.snapshots >/dev/null
fi

# Create snapper config for root if missing
if [ ! -f /etc/snapper/configs/root ]; then
  # avoid dbus requirement during first run
  snapper --no-dbus -c root create-config /
fi

# Tweak snapper config for MANUAL snapshots only
SNCONF="/etc/snapper/configs/root"
if [ -f "$SNCONF" ]; then
  echo "==> Configuring Snapper (manual snapshots, number cleanup only)..."
  sed -i 's/^TIMELINE_CREATE=.*/TIMELINE_CREATE="no"/' "$SNCONF" || true
  sed -i 's/^TIMELINE_CLEANUP=.*/TIMELINE_CLEANUP="no"/' "$SNCONF" || true
  sed -i 's/^NUMBER_CLEANUP=.*/NUMBER_CLEANUP="yes"/' "$SNCONF" || true
  sed -i 's/^NUMBER_MIN_AGE=.*/NUMBER_MIN_AGE="1800"/' "$SNCONF" || true
  # Keep last 10 snapshots + up to 5 marked important
  if grep -q '^NUMBER_LIMIT=' "$SNCONF"; then
    sed -i 's/^NUMBER_LIMIT=.*/NUMBER_LIMIT="10"/' "$SNCONF"
  else
    echo 'NUMBER_LIMIT="10"' >> "$SNCONF"
  fi
  if grep -q '^NUMBER_LIMIT_IMPORTANT=' "$SNCONF"; then
    sed -i 's/^NUMBER_LIMIT_IMPORTANT=.*/NUMBER_LIMIT_IMPORTANT="5"/' "$SNCONF"
  else
    echo 'NUMBER_LIMIT_IMPORTANT="5"' >> "$SNCONF"
  fi
fi

# Disable timeline timers (we're manual only)
systemctl disable --now snapper-timeline.timer snapper-cleanup.timer >/dev/null 2>&1 || true
# Snapper daemon on for apt pre/post and general operations
systemctl enable --now snapperd.service >/dev/null 2>&1 || true

# --- grub-btrfs install (from source) ---
GRUB_BTRFS_DIR="/opt/grub-btrfs"
if [ ! -d "$GRUB_BTRFS_DIR" ]; then
  echo "==> Installing grub-btrfs from GitHub..."
  git clone https://github.com/Antynea/grub-btrfs "$GRUB_BTRFS_DIR"
  make -C "$GRUB_BTRFS_DIR"
  make -C "$GRUB_BTRFS_DIR" install
else
  echo "==> Updating grub-btrfs..."
  (cd "$GRUB_BTRFS_DIR" && git pull --ff-only && make && make install)
fi

# Enable watcher (adds snapshots to GRUB automatically)
systemctl enable --now grub-btrfsd.service >/dev/null 2>&1 || true

# --- Helper tools ---
echo "==> Installing helper commands into /usr/local/bin ..."

# snapshot: create + update-grub
tee /usr/local/bin/snapshot >/dev/null <<'SH'
#!/usr/bin/env bash
DESC="$*"
[ -n "$DESC" ] || { echo "Usage: snapshot <description>"; exit 1; }
echo "📸 Creating snapshot: \"$DESC\"..."
sudo snapper -c root create --description "$DESC"
echo "🔄 Updating GRUB..."
sudo update-grub >/dev/null || true
echo "✅ Latest snapshots:"
sudo snapper -c root list | tail -n 5
SH
chmod +x /usr/local/bin/snapshot

# snapshot-clean: enforce number cleanup + update-grub
tee /usr/local/bin/snapshot-clean >/dev/null <<'SH'
#!/usr/bin/env bash
set -euo pipefail
echo "🧹 Enforcing Snapper number cleanup policy..."
sudo snapper -c root cleanup number
echo "🔄 Updating GRUB menu..."
sudo update-grub >/dev/null || true
echo "📦 Remaining snapshots:"
sudo snapper -c root list
SH
chmod +x /usr/local/bin/snapshot-clean

# snapshot-rm: delete one snapshot by ID + update-grub
tee /usr/local/bin/snapshot-rm >/dev/null <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[ $# -eq 1 ] || { echo "Usage: snapshot-rm <ID>"; exit 1; }
id="$1"
read -r -p "Delete snapshot ${id}? [y/N] " ans
case "$ans" in
  y|Y|yes|YES) ;;
  *) echo "Aborted."; exit 1;;
esac
sudo snapper -c root delete "$id"
sudo update-grub >/dev/null || true
echo "🗑️  Deleted snapshot $id and refreshed GRUB."
SH
chmod +x /usr/local/bin/snapshot-rm

# snapshot-important: mark snapshot important=yes
tee /usr/local/bin/snapshot-important >/dev/null <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[ $# -eq 1 ] || { echo "Usage: snapshot-important <ID>"; exit 1; }
id="$1"
sudo snapper -c root modify --userdata "important=yes" "$id"
echo "⭐ Marked snapshot $id as important (immune to normal cleanup)."
SH
chmod +x /usr/local/bin/snapshot-important

# snapshot-list: robust pretty list (JSON/CSV fallback)
tee /usr/local/bin/snapshot-list >/dev/null <<'SH'
#!/usr/bin/env bash
set -euo pipefail

echo "📋 Snapper Snapshots:"
echo

# Try JSON first
if snapper -c root list --jsonout >/tmp/snapper.json 2>/dev/null; then
  python3 - <<'PY'
import json
from datetime import datetime
data = json.load(open("/tmp/snapper.json"))
snaps = data.get("snapshots", [])
print(f"{'ID':<4}  {'Type':<8}  {'Pre#':<6}  {'Date':<25}  {'User':<10}  {'Cleanup':<10}  Description")
print("----  --------  ------  -------------------------  ----------  ----------  -----------------------------")
for s in snaps:
    id = s.get("number","")
    typ = s.get("type","")
    pre = s.get("pre_number","") or ""
    date = s.get("date","") or ""
    try:
        dt = datetime.fromisoformat(date.replace('Z','+00:00'))
        date = dt.strftime("%a %d %b %Y %H:%M:%S")
    except Exception:
        pass
    user = s.get("user","") or ""
    cleanup = s.get("cleanup","") or ""
    desc = s.get("description","") or ""
    print(f"{id:<4}  {typ:<8}  {pre:<6}  {date:<25}  {user:<10}  {cleanup:<10}  {desc}")
PY
  exit 0
fi

# Try CSV
if snapper -c root list --columns number,type,pre-number,date,user,cleanup,description --csvout >/tmp/snapper.csv 2>/dev/null; then
  python3 - <<'PY'
import csv
print(f"{'ID':<4}  {'Type':<8}  {'Pre#':<6}  {'Date':<25}  {'User':<10}  {'Cleanup':<10}  Description")
print("----  --------  ------  -------------------------  ----------  ----------  -----------------------------")
with open("/tmp/snapper.csv", newline='') as f:
    r = csv.DictReader(f)
    for row in r:
        print(f"{row.get('number',''):<4}  {row.get('type',''):<8}  {row.get('pre-number',''):<6}  "
              f"{row.get('date',''):<25}  {row.get('user',''):<10}  {row.get('cleanup',''):<10}  {row.get('description','')}")
PY
  exit 0
fi

# Fallback to raw
snapper -c root list
SH
chmod +x /usr/local/bin/snapshot-list

# pre-update: snapshot -> update -> show recent
tee /usr/local/bin/pre-update >/dev/null <<'SH'
#!/usr/bin/env bash
set -euo pipefail
DESC="Pre-update $(date -Iseconds)"
echo "📸 $DESC"
sudo snapper -c root create --description "$DESC"
sudo update-grub >/dev/null || true
echo "⬆️  Running updates..."
sudo apt update
sudo apt upgrade -y
echo "✅ Done. Recent snapshots:"
sudo snapper -c root list | tail -n 6
SH
chmod +x /usr/local/bin/pre-update

# --- Create an initial snapshot so GRUB has something to list ---
if ! snapper -c root list | awk 'NR>2{exit 1}'; then
  # (there are already snapshots) no-op
  true
fi
if ! snapper -c root list | grep -q "Golden image"; then
  echo "==> Creating initial snapshot: 'Initial clean install'..."
  snapper -c root create --description "Initial clean install" || true
fi

echo "==> Refreshing GRUB menu..."
update-grub >/dev/null || true

# --- Final summary / how-to ---
cat <<'EOT'

🎉 All set! Your system now has:
  • Snapper configured for manual snapshots (no hourly timeline)
  • grub-btrfs adding snapshots to GRUB ("Ubuntu Snapshots" submenu)
  • Helper commands installed in /usr/local/bin:

    snapshot "<description>"
        → Create a snapshot and refresh GRUB
        e.g. snapshot "Before NVIDIA driver install"

    snapshot-list
        → Show snapshots in a clean table

    snapshot-rm <ID>
        → Delete one snapshot (prompts for confirmation) and refresh GRUB

    snapshot-important <ID>
        → Mark a snapshot as important (survives number cleanup)

    snapshot-clean
        → Enforce number cleanup (keeps last 10; plus up to 5 important)

    pre-update
        → Auto-snapshot with timestamp, then apt update/upgrade

🧠 Tips:
  • Keep a “Golden image – fully configured” snapshot and mark it important:
        snapshot "Golden image – fully configured"
        ID=$(snapper -c root list | awk '/Golden image/{print $1}' | tail -n1)
        sudo snapper -c root modify --userdata "important=yes" "$ID"

  • Roll back to a snapshot:
        sudo snapper -c root rollback <ID>
        sudo reboot

  • GRUB shows snapshots as read-only boot entries under "Ubuntu Snapshots".

Done!
EOT
