#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Minimal safety checks
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root: sudo $0"
  exit 1
fi

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="/root/hybrid-gpu-backup-$TIMESTAMP"
mkdir -p "$BACKUP_DIR"

echo "Backup dir: $BACKUP_DIR"

# Backup relevant dirs if present
for d in /etc/X11/xorg.conf.d /etc/modprobe.d /etc/modules-load.d; do
  if [ -d "$d" ]; then
    echo "Backing up $d -> $BACKUP_DIR/$(basename "$d")"
    cp -a "$d" "$BACKUP_DIR/" || true
  fi
done

# Backup any xorg.conf if exists
if [ -f /etc/X11/xorg.conf ]; then
  cp /etc/X11/xorg.conf "$BACKUP_DIR/xorg.conf" || true
fi

# Detect GPU PCI addresses (first NVIDIA and first AMD detected)
NV_PCI_RAW="$(lspci -nn | grep -i 'NVIDIA' | head -n1 | awk '{print $1}' || true)"
AMD_PCI_RAW="$(lspci -nn | egrep -i 'AMD|ATI' | grep -v -i nvidia | head -n1 | awk '{print $1}' || true)"

if [ -z "$NV_PCI_RAW" ] || [ -z "$AMD_PCI_RAW" ]; then
  echo "Could not detect both GPUs automatically."
  echo "Detected NVIDIA: '$NV_PCI_RAW'"
  echo "Detected AMD:    '$AMD_PCI_RAW'"
  echo "Please ensure both GPUs are visible via: lspci | grep -E 'VGA|3D'"
  exit 1
fi

# Convert format e.g. 01:00.0 -> PCI:01:00:0 (Xorg wants last dot -> colon)
pci_to_busid() {
  local raw="$1"
  busid="PCI:${raw/./:}"
  echo "$busid"
}

NV_BUSID="$(pci_to_busid "$NV_PCI_RAW")"
AMD_BUSID="$(pci_to_busid "$AMD_PCI_RAW")"

echo "Detected NVIDIA PCI: $NV_PCI_RAW -> BusID $NV_BUSID"
echo "Detected AMD    PCI: $AMD_PCI_RAW -> BusID $AMD_BUSID"

# Move any existing nvidia blacklists to backup (do not delete)
echo "Backing up any modprobe blacklist files mentioning nvidia..."
grep -lR --line-number -i "nvidia" /etc/modprobe.d/* 2>/dev/null || true
for f in $(grep -lR -i "nvidia" /etc/modprobe.d 2>/dev/null || true); do
  echo "Moving $f -> $BACKUP_DIR/$(basename "$f")"
  mv "$f" "$BACKUP_DIR/$(basename "$f")"
done

# Create modprobe conf to enable nvidia DRM modeset
echo "Writing /etc/modprobe.d/nvidia.conf (enables nvidia_drm modeset=1)..."
cat > /etc/modprobe.d/nvidia.conf <<'EOF'
# Enable modeset for nvidia DRM — required for PRIME offload and hybrid setups
options nvidia_drm modeset=1
EOF

# Create modules-load to try to ensure the load order (amdgpu first)
echo "Writing /etc/modules-load.d/gpu.conf"
cat > /etc/modules-load.d/gpu.conf <<'EOF'
# ensure amdgpu is loaded first if present, then nvidia modules
amdgpu
nvidia
nvidia_uvm
nvidia_modeset
nvidia_drm
EOF

# Write minimal Xorg hybrid config
XCONF="/etc/X11/xorg.conf.d/10-hybrid.conf"
echo "Writing $XCONF (backing up existing file if any)"
mkdir -p /etc/X11/xorg.conf.d
if [ -f "$XCONF" ]; then
  cp "$XCONF" "$BACKUP_DIR/$(basename "$XCONF").bak"
fi

cat > "$XCONF" <<EOF
# Hybrid AMD (display) + NVIDIA (offload/compute) minimal configuration
# Generated: $TIMESTAMP
Section "ServerLayout"
    Identifier "layout"
    Screen 0 "amd"
EndSection

Section "Device"
    Identifier "AMDgpu"
    Driver "amdgpu"
    BusID "$AMD_BUSID"
    Option "DRI" "3"
    Option "TearFree" "true"
    Option "VariableRefresh" "true"
    Option "PrimaryGPU" "yes"
EndSection

Section "Device"
    Identifier "NVIDIA"
    Driver "nvidia"
    BusID "$NV_BUSID"
    Option "AllowEmptyInitialConfiguration"
    Option "AllowExternalGpus" "True"
EndSection
EOF

# Update initramfs & grub
echo "Updating initramfs for all kernels..."
update-initramfs -u -k all || echo "update-initramfs failed (check output)"

if command -v update-grub >/dev/null 2>&1; then
  echo "Updating grub.cfg..."
  update-grub || echo "update-grub failed (check output)"
fi

echo
echo "DONE. Backups saved at $BACKUP_DIR"
echo
echo "Next steps:"
echo "  1) Reboot now: sudo reboot"
echo "  2) After reboot, check:"
echo "       lsmod | egrep 'amdgpu|nvidia'"
echo "       nvidia-smi"
echo "       glxinfo | grep 'OpenGL renderer'"
echo "       __NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia glxinfo | grep 'OpenGL renderer'"
echo
echo "If something breaks, you can restore backups from $BACKUP_DIR (files copied there)."
echo
echo "If the GUI fails to start, switch to a TTY (Ctrl+Alt+F3), login as root and inspect:"
echo "  sudo journalctl -b -p err --no-pager"
echo "  sudo tail -n 200 /var/log/Xorg.0.log"
echo
exit 0
