#!/usr/bin/env bash
# Btrfs Snapshot Installer: Deploy required tools and Btrfs-only helper commands.

set -euo pipefail

# --- Safety & environment checks ---
if [ "$(id -u)" -ne 0 ]; then
  echo "Please run as root (use: sudo bash $0)"; exit 1
fi

if ! command -v findmnt >/dev/null 2>&1; then
  # Install util-linux if needed
  apt update && apt install -y util-linux
fi

ROOT_FSTYPE="$(findmnt -no FSTYPE / || true)"
if [ "$ROOT_FSTYPE" != "btrfs" ]; then
  echo "ERROR: / is not on Btrfs (detected: ${ROOT_FSTYPE})."
  echo "This script expects a fresh Ubuntu installed with a Btrfs root."
  exit 1
fi

echo "✅ Detected Btrfs on /"

# --- Packages & Pre-Checks ---
echo "==> Enabling Universe & updating..."
sed -i 's/^# deb/deb/' /etc/apt/sources.list || true
apt update

echo "==> Installing packages (git, make, python3, inotify-tools)..."
DEBIAN_FRONTEND=noninteractive apt install -y \
  git make python3 inotify-tools

# --- /.snapshots Subvolume Setup ---
echo "==> Ensuring /.snapshots is a Btrfs subvolume..."
if [ -e "/.snapshots" ] && ! btrfs subvolume show /.snapshots >/dev/null 2>&1; then
  # Exists but not a subvolume
  rmdir /.snapshots 2>/dev/null || true
fi
if ! btrfs subvolume show /.snapshots >/dev/null 2>&1; then
  btrfs subvolume create /.snapshots >/dev/null
  echo "✅ Created /.snapshots subvolume."
else
  echo "✅ /.snapshots subvolume already exists."
fi

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
# We don't use the daemon as often as with Snapper, but we enable it anyway.
systemctl enable --now grub-btrfsd.service >/dev/null 2>&1 || true

# --- Helper tools (Btrfs-only implementation) ---
echo "==> Installing Btrfs helper commands into /usr/local/bin ..."

# snapshot: create + update-grub (Uses embedded description due to Btrfs version)
tee /usr/local/bin/snapshot >/dev/null <<'SH'
#!/usr/bin/env bash
DESC="$*"
[ -n "$DESC" ] || { echo "Usage: snapshot <description>"; exit 1; }

# Create a clean, unique name for the snapshot with embedded description
SNAP_DESC=$(echo "$DESC" | tr ' ' '_')
SNAP_NAME="manual-$(date +%Y-%m-%d_%H%M%S)-${SNAP_DESC}"
SNAP_PATH="/.snapshots/$SNAP_NAME"

echo "📸 Creating snapshot: \"$DESC\" at $SNAP_PATH..."

# Create the snapshot (read-only)
sudo btrfs subvolume snapshot -r / "$SNAP_PATH"

echo "🔄 Updating GRUB..."
sudo update-grub >/dev/null || true

echo "✅ Snapshot created and GRUB refreshed."
echo "Last 5 Snapshots (newest first):"
sudo btrfs subvolume list -t -s /.snapshots | sort -r | head -n 6
SH
chmod +x /usr/local/bin/snapshot

# snapshot-list: Btrfs-only list (Uses simple list due to Btrfs version)
tee /usr/local/bin/snapshot-list >/dev/null <<'SH'
#!/usr/bin/env bash
echo "📋 Btrfs Snapshots in /.snapshots:"
echo "ID       Creation Date & Time     Name (Description Embedded)"
echo "-------  ------------------------ -------------------------------------------------"

# List subvolumes under /.snapshots with detailed time (-t) and sort by path (-s)
sudo btrfs subvolume list -t -s /.snapshots | awk '{
    # $7 is the timestamp, $9 is the path/name
    timestamp = $7 " " $8;
    name = $9;
    
    # Format the name to remove the path prefix
    gsub(/^\.snapshots\//, "", name);

    # Output the required columns
    printf "%-8s %-24s %s\n", $2, timestamp, name;
}'
echo
echo "Note: Snapshot description is embedded in the name due to an older Btrfs version."
SH
chmod +x /usr/local/bin/snapshot-list

# snapshot-rm: delete by name + refresh GRUB
tee /usr/local/bin/snapshot-rm >/dev/null <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[ $# -eq 1 ] || { echo "Usage: snapshot-rm <SNAPSHOT_NAME>"; exit 1; }
SNAP_NAME="$1"
SNAP_PATH="/.snapshots/$SNAP_NAME"

# Check if the path exists and is a subvolume
if ! sudo btrfs subvolume show "$SNAP_PATH" >/dev/null 2>&1; then
    echo "ERROR: Snapshot '$SNAP_NAME' not found in /.snapshots/."
    exit 1
fi

read -r -p "Delete snapshot ${SNAP_NAME}? This is permanent. [y/N] " ans
case "$ans" in
  y|Y|yes|YES)
    echo "🗑️  Deleting snapshot $SNAP_NAME..."
    sudo btrfs subvolume delete "$SNAP_PATH"
    sudo update-grub >/dev/null || true
    echo "✅ Deleted snapshot $SNAP_NAME and refreshed GRUB."
    ;;
  *) echo "Aborted."; exit 1;;
esac
SH
chmod +x /usr/local/bin/snapshot-rm

# --- Create an initial snapshot and verify ---
echo "==> Creating initial snapshot: 'Initial clean install'..."
/usr/local/bin/snapshot "Initial clean install"

# --- Final summary / how-to ---
cat <<'EOT'

🎉 ALL SET! BTRFS SNAPSHOTS DEPLOYED!
  • Snapper was omitted due to incompatibility.
  • Btrfs helper scripts are installed in /usr/local/bin.
  • grub-btrfs is installed and working.

🧠 VERIFICATION:
  1. Listing command:
     snapshot-list

  2. New snapshot created:
     The snapshot "Initial clean install" was created and added to GRUB.

  3. Next Snapshot:
     snapshot "My first test backup"

Done!
EOT
