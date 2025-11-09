cat > install-snapshot-helpers.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "Please run with sudo/root"; exit 1; }

mkdir -p /usr/local/bin

# --- snapshot: create + refresh GRUB ---
cat > /usr/local/bin/snapshot <<'EOS'
#!/usr/bin/env bash
DESC="$*"
[ -n "$DESC" ] || { echo "Usage: snapshot <description>"; exit 1; }
echo "📸 Creating snapshot: \"$DESC\"..."
sudo snapper -c root create --description "$DESC"
echo "🔄 Updating GRUB..."
sudo update-grub >/dev/null || true
echo "✅ Latest snapshots:"
sudo snapper -c root list | tail -n 5
EOS
chmod +x /usr/local/bin/snapshot

# --- snapshot-list: robust pretty output (JSON → CSV → raw) ---
cat > /usr/local/bin/snapshot-list <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
echo "📋 Snapper Snapshots:"
echo
# JSON first
if snapper -c root list --jsonout >/tmp/snapper.json 2>/dev/null; then
  python3 - <<'PY'
import json
from datetime import datetime
data=json.load(open("/tmp/snapper.json"))
snaps=data.get("snapshots",[])
print(f"{'ID':<4}  {'Type':<8}  {'Pre#':<6}  {'Date':<25}  {'User':<10}  {'Cleanup':<10}  Description")
print("----  --------  ------  -------------------------  ----------  ----------  -----------------------------")
for s in snaps:
    id=s.get("number",""); typ=s.get("type",""); pre=s.get("pre_number","") or ""
    date=s.get("date","") or ""
    try:
        dt=datetime.fromisoformat(date.replace('Z','+00:00'))
        date=dt.strftime("%a %d %b %Y %H:%M:%S")
    except Exception: pass
    user=s.get("user","") or ""; cleanup=s.get("cleanup","") or ""; desc=s.get("description","") or ""
    print(f"{id:<4}  {typ:<8}  {pre:<6}  {date:<25}  {user:<10}  {cleanup:<10}  {desc}")
PY
  exit 0
fi
# CSV next
if snapper -c root list --columns number,type,pre-number,date,user,cleanup,description --csvout >/tmp/snapper.csv 2>/dev/null; then
  python3 - <<'PY'
import csv
print(f"{'ID':<4}  {'Type':<8}  {'Pre#':<6}  {'Date':<25}  {'User':<10}  {'Cleanup':<10}  Description")
print("----  --------  ------  -------------------------  ----------  ----------  -----------------------------")
with open("/tmp/snapper.csv", newline='') as f:
    r=csv.DictReader(f)
    for row in r:
        print(f"{row.get('number',''):<4}  {row.get('type',''):<8}  {row.get('pre-number',''):<6}  "
              f"{row.get('date',''):<25}  {row.get('user',''):<10}  {row.get('cleanup',''):<10}  {row.get('description','')}")
PY
  exit 0
fi
# Raw fallback
snapper -c root list
EOS
chmod +x /usr/local/bin/snapshot-list

# --- snapshot-clean: enforce number cleanup + refresh GRUB ---
cat > /usr/local/bin/snapshot-clean <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
echo "🧹 Enforcing Snapper number cleanup policy..."
sudo snapper -c root cleanup number
echo "🔄 Updating GRUB menu..."
sudo update-grub >/dev/null || true
echo "📦 Remaining snapshots:"
sudo snapper -c root list
EOS
chmod +x /usr/local/bin/snapshot-clean

# --- snapshot-rm: delete by ID (with confirm) + refresh GRUB ---
cat > /usr/local/bin/snapshot-rm <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
[ $# -ge 1 ] || { echo "Usage: snapshot-rm <ID> [ID ...]"; exit 1; }
for id in "$@"; do
  read -r -p "Delete snapshot ${id}? [y/N] " ans
  case "$ans" in
    y|Y|yes|YES)
      sudo snapper -c root delete "$id"
      ;;
    *) echo "Skipped $id";;
  esac
done
sudo update-grub >/dev/null || true
echo "🗑️  Deletions complete. GRUB refreshed."
EOS
chmod +x /usr/local/bin/snapshot-rm

# --- snapshot-important: mark important=yes ---
cat > /usr/local/bin/snapshot-important <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
[ $# -eq 1 ] || { echo "Usage: snapshot-important <ID>"; exit 1; }
sudo snapper -c root modify --userdata "important=yes" "$1"
echo "⭐ Marked snapshot $1 as important."
EOS
chmod +x /usr/local/bin/snapshot-important

# --- snapshot-rm-apt: remove all 'apt' snapshots in one go ---
cat > /usr/local/bin/snapshot-rm-apt <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
echo "🧹 Removing all 'apt' snapshots (pre/post and singles matching ' apt ')..."
ids=$(snapper -c root list | awk '/ apt / && $1 ~ /^[0-9]+$/ {print $1}')
if [ -z "$ids" ]; then
  echo "No 'apt' snapshots found."
  exit 0
fi
echo "Will delete IDs: $ids"
read -r -p "Proceed? [y/N] " ans
case "$ans" in
  y|Y|yes|YES)
    echo "$ids" | xargs -r -n1 snapper --no-dbus -c root delete
    sudo update-grub >/dev/null || true
    echo "✅ Removed all apt snapshots and refreshed GRUB."
    ;;
  *) echo "Aborted.";;
esac
EOS
chmod +x /usr/local/bin/snapshot-rm-apt

# --- pre-update: snapshot → apt update/upgrade ---
cat > /usr/local/bin/pre-update <<'EOS'
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
EOS
chmod +x /usr/local/bin/pre-update

# --- snapshot-help: quick reference ---
cat > /usr/local/bin/snapshot-help <<'EOS'
#!/usr/bin/env bash
cat <<'EOF'

📘  SNAPSHOT MAINTENANCE CHEAT SHEET
────────────────────────────────────────────────────────
Your system uses Btrfs + Snapper + grub-btrfs integration.
Snapshots appear in GRUB under “Ubuntu Snapshots” (read-only).

CREATE
  snapshot "<description>"
    → Create a snapshot and refresh GRUB.

LIST
  snapshot-list
    → Show all snapshots (pretty table).

MARK IMPORTANT
  snapshot-important <ID>
    → Protect snapshot from number cleanup.

CLEAN
  snapshot-clean
    → Enforce number-based cleanup (uses NUMBER_LIMIT and NUMBER_LIMIT_IMPORTANT in /etc/snapper/configs/root).

DELETE
  snapshot-rm <ID> [ID ...]
    → Delete one or more by ID (confirms) and refresh GRUB.
  snapshot-rm-apt
    → Remove all “apt” snapshots in one go (confirms) and refresh GRUB.

ROLLBACK (Ubuntu-safe approach)
  • Boot desired snapshot from GRUB (read-only) to confirm.
  • Clone it to a writable subvolume and switch via GRUB or fstab.
    (Ask Sol for the 'rollback-safe' flow if needed.)

TIPS
  • Keep a “Golden image – fully configured” snapshot:
        snapshot "Golden image – fully configured"
        ID=$(snapper -c root list | awk '/Golden image/{print $1}' | tail -n1)
        sudo snapper -c root modify --userdata "important=yes" "$ID"

EOF
EOS
chmod +x /usr/local/bin/snapshot-help

echo "✅ Helper commands installed in /usr/local/bin:"
printf "  - %s\n" snapshot snapshot-list snapshot-clean snapshot-rm snapshot-important snapshot-rm-apt pre-update snapshot-help

echo
echo "Run 'snapshot-help' for a quick how-to."
SH
