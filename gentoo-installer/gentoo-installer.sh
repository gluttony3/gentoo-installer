#!/bin/bash
# gentoo-installer.sh — Automated Gentoo Linux Installer
#
# Stack:
#   Init    : OpenRC + elogind
#   Desktop : KDE Plasma (minimal, Wayland)
#   Audio   : PipeWire + WirePlumber
#   Network : NetworkManager
#   Boot    : GRUB (UEFI/BIOS auto-detected)
#   Kernel  : gentoo-kernel-bin  (pre-compiled — no kernel build wait!)
#
# Hardware : Lenovo IdeaPad Slim 3 15ABR8 (Ryzen 5 7430U / Zen 3 / RDNA 2)
# Usage    : run as root from any Linux live environment with internet access

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Source modules ─────────────────────────────────────────────────
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/detect.sh"
source "${SCRIPT_DIR}/lib/disk.sh"
source "${SCRIPT_DIR}/lib/install.sh"
source "${SCRIPT_DIR}/lib/configure.sh"

export SCRIPT_DIR

# ── Cleanup on any exit ────────────────────────────────────────────
cleanup() {
    local exit_code=$?
    if (( exit_code != 0 )); then
        echo ""
        log_warn "Installer exited with error (code $exit_code)"
        log_warn "Attempting to unmount filesystems..."
    fi
    swapoff "${PART_SWAP:-}" 2>/dev/null || true
    # Unmount pseudo-filesystems first (reverse order)
    umount "${MOUNTPOINT}/run"     2>/dev/null || true
    umount "${MOUNTPOINT}/dev/pts" 2>/dev/null || true
    umount -l "${MOUNTPOINT}/dev"  2>/dev/null || true
    umount -l "${MOUNTPOINT}/sys"  2>/dev/null || true
    umount "${MOUNTPOINT}/proc"    2>/dev/null || true
    # Then real partitions
    umount "${MOUNTPOINT}/boot/efi" 2>/dev/null || true
    umount -R "${MOUNTPOINT}"       2>/dev/null || true
}
trap cleanup EXIT

# ── Welcome screen ─────────────────────────────────────────────────
show_welcome() {
    clear
    echo -e "${BOLD}${BLUE}"
    echo "  ╔══════════════════════════════════════════════════════╗"
    echo "  ║           GENTOO LINUX INSTALLER                     ║"
    echo "  ║   OpenRC  |  KDE Plasma  |  PipeWire  |  Wayland    ║"
    echo "  ║   Ryzen 5 7430U (Zen 3)  |  Binary kernel  |  Fast  ║"
    echo "  ╚══════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo "  This installer will:"
    echo "    1. Detect hardware  (CPU microarch, GPU, disk type)"
    echo "    2. Partition and format the chosen disk"
    echo "    3. Download + extract Gentoo stage3 (OpenRC)"
    echo "    4. Configure Portage (binary packages enabled)"
    echo "    5. Install KDE Plasma Wayland + PipeWire audio"
    echo "    6. Install pre-compiled kernel  (no wait for kernel build!)"
    echo "    7. Install GRUB, configure OpenRC services"
    echo "    8. Create user account and finalize system"
    echo ""
    echo "  Time estimate: ~1-2 h  (internet speed dependent)"
    echo "  Compilation   : minimized via gentoo-kernel-bin + binpkgs"
    echo ""
    log_warn "The target disk will be COMPLETELY ERASED."
    echo ""
    confirm "Start the installer?" || { echo "Bye."; exit 0; }
}

# ── Finish ─────────────────────────────────────────────────────────
show_finish() {
    log_section "Installation Finished!"
    echo ""
    echo -e "  ${GREEN}Gentoo Linux is installed and ready.${NC}"
    echo ""
    echo "  What to do next:"
    echo "    1. Remove the installation media (USB/CD)"
    echo "    2. Reboot"
    echo "    3. At the SDDM login screen, choose 'Plasma (Wayland)' session"
    echo "    4. Login as: ${BOLD}${USERNAME}${NC}"
    echo ""
    echo "  Post-install tips:"
    echo "    - Run 'emerge --sync && emerge -uDN @world' to keep system updated"
    echo "    - Use 'emerge --search <package>' to find packages"
    echo "    - KDE System Settings -> Audio -> PipeWire should be active"
    echo ""
    confirm "Reboot now?" && reboot
}

# ── Main flow ──────────────────────────────────────────────────────
main() {
    check_root
    check_deps
    detect_boot_mode
    show_welcome

    # Step 1: Hardware detection
    detect_cpu
    detect_gpu

    # Step 2: Disk setup
    select_disk
    plan_partitions
    do_partition
    do_format
    do_mount

    # Step 3: User preferences
    ask_user_info

    # Step 4: Stage3 + Portage
    download_stage3
    extract_stage3
    setup_portage

    # Step 5: fstab
    generate_fstab

    # Step 6: Configure system inside chroot
    run_chroot_config

    show_finish
}

main
