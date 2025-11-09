#!/usr/bin/env bash
# prep-virt-host.sh — Ubuntu 24.04: KVM/QEMU/libvirt + IOMMU + optional GPU passthrough (reboot required)
#
# Usage examples:
#   sudo bash prep-virt-host.sh
#   sudo bash prep-virt-host.sh --gpu 0000:01:00.0,0000:01:00.1
#   sudo bash prep-virt-host.sh --gpu 0000:01:00.0,0000:01:00.1 --hugepages 16384
#   sudo bash prep-virt-host.sh --gpu 0000:01:00.0,0000:01:00.1 --blacklist nvidia
#
# Flags:
#   --gpu <PCI_LIST>      Comma-separated PCI addresses to bind to vfio-pci (e.g. 0000:01:00.0,0000:01:00.1)
#   --hugepages <N>       Reserve N *2MiB* hugepages (optional)
#   --blacklist <module>  Blacklist a GPU driver module (nouveau|nvidia|amdgpu) — optional & risky if in use
#   --no-default-net      Skip ensuring libvirt 'default' NAT network
#
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Run as root: sudo $0 …"; exit 1; }

GPU_FUNCS=""
HUGEPAGES=0
BLACKLIST=""
ENSURE_DEFAULT_NET=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --gpu)        GPU_FUNCS="$2"; shift 2;;
    --hugepages)  HUGEPAGES="$2"; shift 2;;
    --blacklist)  BLACKLIST="$2"; shift 2;;
    --no-default-net) ENSURE_DEFAULT_NET=0; shift;;
    *) echo "Unknown arg: $1" >&2; exit 1;;
  esac
done

# --- Sanity checks ---
. /etc/os-release
[[ "${ID:-}" == "ubuntu" ]] || { echo "This targets Ubuntu; detected ${ID:-?}"; exit 1; }
dpkg --compare-versions "${VERSION_ID:-0}" ge 24.04 || { echo "Need Ubuntu 24.04+"; exit 1; }

if ! lscpu | grep -qiE 'vmx|svm'; then
  echo "CPU virtualization flags (vmx/svm) not found. Enable in BIOS/UEFI." >&2
  exit 1
fi

echo "Installing virtualization stack…"
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  qemu-system qemu-utils libvirt-daemon-system libvirt-clients virt-manager \
  ovmf swtpm swtpm-tools dmidecode cpu-checker

systemctl enable --now libvirtd

# --- Enable IOMMU flags in GRUB ---
if grep -qi intel /proc/cpuinfo; then
  IOMMU_FLAGS="intel_iommu=on iommu=pt"
else
  IOMMU_FLAGS="amd_iommu=on iommu=pt"
fi

GRUBCFG=/etc/default/grub
if ! grep -q "$IOMMU_FLAGS" "$GRUBCFG"; then
  echo "Enabling IOMMU in GRUB: $IOMMU_FLAGS"
  sed -i "s/^GRUB_CMDLINE_LINUX=\"/GRUB_CMDLINE_LINUX=\"$IOMMU_FLAGS /" "$GRUBCFG"
  update-grub
else
  echo "IOMMU flags already present in GRUB."
fi

# --- Optional hugepages ---
if [[ "$HUGEPAGES" -gt 0 ]]; then
  echo "Configuring hugepages: $HUGEPAGES (2MiB pages)"
  sysctl -w vm.nr_hugepages="$HUGEPAGES" >/dev/null
  if grep -q '^vm.nr_hugepages' /etc/sysctl.conf; then
    sed -i "s/^vm.nr_hugepages=.*/vm.nr_hugepages=$HUGEPAGES/" /etc/sysctl.conf
  else
    echo "vm.nr_hugepages=$HUGEPAGES" >> /etc/sysctl.conf
  fi
fi

# --- Optional blacklist (use with care) ---
if [[ -n "$BLACKLIST" ]]; then
  case "$BLACKLIST" in
    nouveau|nvidia|amdgpu)
      echo "Blacklisting GPU driver module: $BLACKLIST"
      echo "blacklist $BLACKLIST" > "/etc/modprobe.d/blacklist-$BLACKLIST.conf"
      update-initramfs -u
      ;;
    *)
      echo "Unsupported --blacklist value: $BLACKLIST (use nouveau|nvidia|amdgpu)"; exit 1;;
  esac
fi

# --- vfio-pci binding for the chosen GPU functions ---
if [[ -n "$GPU_FUNCS" ]]; then
  echo "Preparing vfio-pci binding…"
  IFS=',' read -r -a FUNCS <<< "$GPU_FUNCS"
  IDS=()
  for F in "${FUNCS[@]}"; do
    F=$(echo "$F" | xargs)
    ID=$(lspci -n -s "$F" | awk '{print $3}')
    [[ -n "$ID" ]] || { echo "Could not resolve vendor:device ID for $F"; exit 1; }
    IDS+=("$ID")
  done

  # Ensure vfio modules load early
  cat > /etc/modules-load.d/vfio.conf <<EOF
vfio
vfio_pci
vfio_iommu_type1
EOF

  # Bind by IDs
  echo "options vfio-pci ids=$(IFS=,; echo "${IDS[*]}") disable_vga=1" > /etc/modprobe.d/vfio-pci-ids.conf

  # Prevent common GPU drivers from grabbing the device first (optional — uncomment to force)
  # echo "softdep nouveau pre: vfio-pci"  > /etc/modprobe.d/vfio-softdeps.conf
  # echo "softdep nvidia pre: vfio-pci"  >> /etc/modprobe.d/vfio-softdeps.conf
  # echo "softdep amdgpu pre: vfio-pci"  >> /etc/modprobe.d/vfio-softdeps.conf

  update-initramfs -u
  echo "vfio-pci will claim: ${IDS[*]} (after reboot)"
fi

# --- Libvirt default NAT network (persistent) ---
if [[ "$ENSURE_DEFAULT_NET" -eq 1 ]]; then
  if virsh net-info default >/dev/null 2>&1; then
    echo "Libvirt network 'default' already exists."
  else
    echo "Creating libvirt network 'default' (NAT)…"
    cat > /tmp/net-default.xml <<'XML'
<network>
  <name>default</name>
  <forward mode='nat'/>
  <bridge name='virbr0' stp='on' delay='0'/>
  <ip address='192.168.122.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.122.100' end='192.168.122.254'/>
    </dhcp>
  </ip>
</network>
XML
    virsh net-define /tmp/net-default.xml
  fi
  virsh net-autostart default || true
  virsh net-start default || true
fi

# --- User access ---
CALLER=${SUDO_USER:-$USER}
usermod -aG libvirt,kvm "$CALLER"

echo
echo "✅ Base virtualization environment is ready."
echo
echo "Next steps:"
echo "  • Reboot to activate IOMMU and any vfio/blacklist changes:  sudo reboot"
if [[ -n "$GPU_FUNCS" ]]; then
  echo "  • After reboot: confirm vfio binding for your GPU:"
  echo "      lspci -k -s ${GPU_FUNCS/,/ -s } | egrep -A2 'Kernel driver in use'"
fi
echo "  • Launch 'virt-manager' to create your Windows 11 VM:"
echo "      - Firmware: OVMF (UEFI) — use /usr/share/OVMF/OVMF_CODE_4M.fd"
echo "      - TPM 2.0: swtpm"
echo "      - CPU: host-passthrough"
echo "      - Disk/NIC: VirtIO (use virtio-win ISO during install)"
echo
echo "Tips:"
echo "  • Keep the host display on an iGPU or a second GPU; don't pass through the GPU driving your desktop."
echo "  • If the vendor driver still grabs the GPU, consider --blacklist or moving to a headless session."
