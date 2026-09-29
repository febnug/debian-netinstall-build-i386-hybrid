#!/usr/bin/env bash

set -euo pipefail

# ============================================================
# Debian 12 Bookworm i386 Hybrid ISO Builder
#
# Boot targets:
#   - Legacy BIOS
#   - UEFI IA32
#   - UEFI x86_64
#
# Installed OS:
#   - Debian Bookworm i386
# ============================================================

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ISO_ROOT="${PROJECT_DIR}/iso"
WORK_DIR="${PROJECT_DIR}/work"
DIST_DIR="${PROJECT_DIR}/dist"

ISO_NAME="debian-bookworm-i386-hybrid.iso"
ISO_OUTPUT="${DIST_DIR}/${ISO_NAME}"

# Debian Bookworm i386 installer
DEBIAN_BASE="https://ftp.debian.org/debian/dists/bookworm/main/installer-i386/current/images/netboot/debian-installer/i386"

# Installer files
LINUX="${ISO_ROOT}/install.i386/linux"
INITRD="${ISO_ROOT}/install.i386/initrd.gz"

# GRUB configuration
GRUB_CFG="${ISO_ROOT}/boot/grub/grub.cfg"

# ============================================================
# Helpers
# ============================================================

die() {
    echo
    echo "[ERROR] $*" >&2
    exit 1
}

info() {
    echo
    echo "[+] $*"
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || \
        die "Required command not found: $1"
}

require_path() {
    [ -e "$1" ] || \
        die "Required path not found: $1"
}

# ============================================================
# Dependency check
# ============================================================

info "Checking dependencies"

for cmd in \
    wget \
    xorriso \
    grub-mkrescue \
    grub-mkstandalone \
    file \
    strings
do
    require_command "$cmd"
done

# ============================================================
# Check GRUB platforms
# ============================================================

info "Checking GRUB platform support"

require_path "/usr/lib/grub/i386-pc/modinfo.sh"
require_path "/usr/lib/grub/i386-efi/modinfo.sh"
require_path "/usr/lib/grub/x86_64-efi/modinfo.sh"

echo "  i386-pc     : OK"
echo "  i386-efi    : OK"
echo "  x86_64-efi  : OK"

# ============================================================
# Prepare directories
# ============================================================

info "Preparing build directories"

rm -rf "$ISO_ROOT" "$WORK_DIR"

mkdir -p \
    "$ISO_ROOT/boot/grub" \
    "$ISO_ROOT/install.i386" \
    "$WORK_DIR" \
    "$DIST_DIR"

# ============================================================
# Download Debian Installer kernel
# ============================================================

info "Downloading Debian Bookworm i386 Installer kernel"

wget \
    --show-progress \
    --https-only \
    "${DEBIAN_BASE}/linux" \
    -O "$LINUX"

[ -s "$LINUX" ] || \
    die "Failed to download Debian Installer kernel"

# ============================================================
# Download Debian Installer initrd
# ============================================================

info "Downloading Debian Bookworm i386 Installer initrd"

wget \
    --show-progress \
    --https-only \
    "${DEBIAN_BASE}/initrd.gz" \
    -O "$INITRD"

[ -s "$INITRD" ] || \
    die "Failed to download Debian Installer initrd"

# ============================================================
# Generate GRUB configuration
# ============================================================

info "Generating GRUB configuration"

cat > "$GRUB_CFG" <<'EOF'
insmod iso9660
insmod search
insmod linux
insmod normal

search --no-floppy --file --set=root /install.i386/linux

set default=0
set timeout=5

menuentry "Debian GNU/Linux 12 i386 Installer" {
    linux /install.i386/linux ---
    initrd /install.i386/initrd.gz
}

menuentry "Debian Installer - Expert Mode" {
    linux /install.i386/linux priority=low ---
    initrd /install.i386/initrd.gz
}

menuentry "Debian Installer - Rescue Mode" {
    linux /install.i386/linux rescue/enable=true ---
    initrd /install.i386/initrd.gz
}
EOF

# ============================================================
# Build hybrid GRUB ISO
#
# grub-mkrescue automatically creates:
#
#   Legacy BIOS
#       /boot/grub/i386-pc/eltorito.img
#
#   UEFI IA32
#       EFI/BOOT/BOOTIA32.EFI
#
#   UEFI x86_64
#       EFI/BOOT/BOOTX64.EFI
#
# ============================================================

info "Building hybrid BIOS + UEFI ISO"

grub-mkrescue \
    --modules="iso9660 search linux normal" \
    -o "$ISO_OUTPUT" \
    "$ISO_ROOT"

# ============================================================
# Validate ISO
# ============================================================

info "Validating ISO"

file "$ISO_OUTPUT"

# ============================================================
# Check El Torito boot entries
# ============================================================

info "Checking El Torito boot information"

xorriso \
    -indev "$ISO_OUTPUT" \
    -report_el_torito plain

# ============================================================
# Check system area
# ============================================================

info "Checking ISO system area"

xorriso \
    -indev "$ISO_OUTPUT" \
    -report_system_area plain

# ============================================================
# Check ISO contents
# ============================================================

info "Checking ISO contents"

echo
echo "--- /boot/grub ---"

xorriso \
    -indev "$ISO_OUTPUT" \
    -ls /boot/grub

echo
echo "--- /boot/grub/i386-pc ---"

xorriso \
    -indev "$ISO_OUTPUT" \
    -ls /boot/grub/i386-pc

echo
echo "--- /install.i386 ---"

xorriso \
    -indev "$ISO_OUTPUT" \
    -ls /install.i386

echo
echo "--- /EFI/BOOT ---"

xorriso \
    -indev "$ISO_OUTPUT" \
    -ls /EFI/BOOT

# ============================================================
# Validate installer files
# ============================================================

info "Validating installer files"

require_path "$LINUX"
require_path "$INITRD"

file "$LINUX"
file "$INITRD"

# ============================================================
# Extract and validate EFI image from ISO
# ============================================================

info "Extracting EFI image from ISO"

EFI_EXTRACT="${WORK_DIR}/efi.img"

xorriso \
    -osirrox on \
    -indev "$ISO_OUTPUT" \
    -extract /efi.img "$EFI_EXTRACT"

require_path "$EFI_EXTRACT"

echo
echo "EFI image:"
file "$EFI_EXTRACT"

echo
echo "EFI filesystem:"
mdir -i "$EFI_EXTRACT" ::/EFI/BOOT

echo
echo "Checking IA32 EFI bootloader:"

mcopy \
    -i "$EFI_EXTRACT" \
    ::/EFI/BOOT/BOOTIA32.EFI \
    "$WORK_DIR/BOOTIA32.EFI"

file "$WORK_DIR/BOOTIA32.EFI"

echo
echo "Checking x86_64 EFI bootloader:"

mcopy \
    -i "$EFI_EXTRACT" \
    ::/EFI/BOOT/BOOTX64.EFI \
    "$WORK_DIR/BOOTX64.EFI"

file "$WORK_DIR/BOOTX64.EFI"
# ============================================================
# Check GRUB configuration
# ============================================================

info "Checking embedded ISO files"

xorriso \
    -indev "$ISO_OUTPUT" \
    -find /install.i386 \
    -type f \
    -print

# ============================================================
# SHA256
# ============================================================

info "Generating SHA256"

sha256sum "$ISO_OUTPUT"

# ============================================================
# Final result
# ============================================================

echo
echo "============================================================"
echo " DEBIAN BOOKWORM i386 HYBRID ISO BUILD SUCCESS"
echo "============================================================"
echo
echo "Output:"
echo "  $ISO_OUTPUT"
echo
echo "Size:"
du -h "$ISO_OUTPUT"

echo
echo "Supported boot modes:"
echo "  [OK] Legacy BIOS"
echo "  [OK] UEFI IA32"
echo "  [OK] UEFI x86_64"
echo
echo "Installed architecture:"
echo "  Debian Bookworm i386"
echo
echo "[+] Done."
