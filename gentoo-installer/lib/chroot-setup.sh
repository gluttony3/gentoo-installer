#!/bin/bash
# lib/chroot-setup.sh — runs INSIDE chroot after stage3 extraction
# Installs the full Gentoo system: Portage sync, kernel, KDE Plasma,
# PipeWire, GRUB, OpenRC services, users.
#
# All config values come from /root/install-config.sh

set -euo pipefail

# ── Colors (standalone — no source available here) ─────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log_info()    { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[!!]${NC} $*"; }
log_step()    { echo -e "  ${CYAN}-->${NC} $*"; }
log_section() {
    echo ""
    echo -e "${BOLD}${BLUE}============================================${NC}"
    echo -e "${BOLD}${BLUE}  $*${NC}"
    echo -e "${BOLD}${BLUE}============================================${NC}"
}
die() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# ── Load config ────────────────────────────────────────────────────
[[ -f /root/install-config.sh ]] || die "/root/install-config.sh not found"
# shellcheck source=/dev/null
source /root/install-config.sh

ROOT_PASSWORD="$(cat /root/.rootpw)"
USER_PASSWORD="$(cat /root/.userpw)"
rm -f /root/.rootpw /root/.userpw

# ── 1. Portage tree sync ───────────────────────────────────────────
log_section "Syncing Portage Tree (emerge-webrsync)"
log_step "Downloading latest portage snapshot (faster than rsync)..."
emerge-webrsync || die "emerge-webrsync failed — check internet"
log_info "Portage tree ready"

# ── 2. Profile selection ───────────────────────────────────────────
log_section "Setting Portage Profile"
# KDE Plasma Wayland profile — sets kde, plasma, wayland USE flags
eselect profile set default/linux/amd64/23.0/desktop/plasma \
    || die "eselect profile failed — run 'eselect profile list' to see available profiles"
log_info "Profile: default/linux/amd64/23.0/desktop/plasma"

# ── 3. Timezone ────────────────────────────────────────────────────
log_section "Timezone: ${TIMEZONE}"
[[ -f "/usr/share/zoneinfo/${TIMEZONE}" ]] \
    || die "Timezone not found: /usr/share/zoneinfo/${TIMEZONE}"
ln -sf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
log_info "Timezone set: ${TIMEZONE}"

# ── 4. Locale ──────────────────────────────────────────────────────
log_section "Locale Configuration"
cat > /etc/locale.gen << 'EOF'
en_US.UTF-8 UTF-8
uk_UA.UTF-8 UTF-8
EOF
locale-gen

# Use English language, Ukrainian date/paper formats
eselect locale set en_US.utf8 2>/dev/null || true

cat > /etc/env.d/02locale << 'EOF'
LANG="en_US.UTF-8"
LC_TIME="uk_UA.UTF-8"
LC_PAPER="uk_UA.UTF-8"
EOF

# Console font with Cyrillic support
cat > /etc/conf.d/consolefont << 'EOF'
consolefont="ter-v16n"
EOF

env-update && source /etc/profile
log_info "Locale configured (en_US + uk_UA dates)"

# ── 5. @world update ───────────────────────────────────────────────
log_section "Updating @world Set (using binary packages where available)"
log_step "This resolves any USE flag changes from the plasma profile..."
emerge --update --deep --newuse --with-bdeps=y @world \
    || die "@world update failed"
log_info "@world updated"

# ── 6. Kernel + firmware ───────────────────────────────────────────
log_section "Installing Kernel (pre-compiled binary — no compilation!)"

log_step "Installing dracut (initramfs generator)..."
emerge sys-kernel/dracut || die "Failed to install dracut"

log_step "Installing linux-firmware (AMD GPU/WiFi/BT firmware)..."
emerge sys-kernel/linux-firmware || die "Failed to install linux-firmware"

# CPU-specific microcode
if [[ "${CPU_UCODE_PKG}" == "sys-firmware/intel-microcode" ]]; then
    log_step "Installing Intel microcode..."
    emerge sys-firmware/intel-microcode
fi
# AMD microcode is part of linux-firmware (already installed above)

log_step "Installing gentoo-kernel-bin (pre-built kernel + auto-initramfs)..."
emerge sys-kernel/gentoo-kernel-bin || die "Failed to install gentoo-kernel-bin"

# Verify kernel installed
local KVER
KVER=$(ls /boot/vmlinuz-* 2>/dev/null | tail -1 | sed 's|/boot/vmlinuz-||')
if [[ -n "$KVER" ]]; then
    log_info "Kernel installed: ${KVER}"
else
    log_warn "Could not detect kernel version — check /boot"
fi

# ── 7. Hostname ────────────────────────────────────────────────────
log_section "Hostname: ${HOSTNAME}"
echo "${HOSTNAME}" > /etc/hostname
# For OpenRC
sed -i "s/^hostname=.*/hostname=\"${HOSTNAME}\"/" /etc/conf.d/hostname 2>/dev/null || \
    echo "hostname=\"${HOSTNAME}\"" > /etc/conf.d/hostname

cat > /etc/hosts << EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain  ${HOSTNAME}
EOF
log_info "Hostname configured: ${HOSTNAME}"

# ── 8. Core system packages ────────────────────────────────────────
log_section "Installing Core System Packages"

log_step "Base tools..."
emerge \
    app-admin/sudo \
    app-shells/bash-completion \
    app-editors/nano \
    app-editors/vim \
    dev-vcs/git \
    net-misc/curl \
    net-misc/wget \
    sys-apps/man-db \
    sys-apps/man-pages \
    app-arch/unzip \
    app-arch/zip \
    app-arch/p7zip \
    sys-fs/ntfs3g \
    sys-fs/exfatprogs \
    sys-fs/dosfstools \
    sys-power/upower \
    sys-power/acpid \
    app-misc/htop \
    || die "Failed to install base tools"

log_step "Time sync (chrony)..."
emerge net-misc/chrony || die "Failed to install chrony"

# ── 9. Network: NetworkManager ─────────────────────────────────────
log_section "Installing Network Stack"

emerge \
    net-misc/networkmanager \
    net-wireless/wpa_supplicant \
    net-wireless/iwd \
    || die "Failed to install network packages"
log_info "NetworkManager installed"

# ── 10. Bluetooth ──────────────────────────────────────────────────
log_section "Installing Bluetooth Stack"
emerge net-wireless/bluez || die "Failed to install bluez"
log_info "BlueZ installed"

# ── 11. D-Bus + elogind + seatd ────────────────────────────────────
log_section "Installing Session/D-Bus Daemons"
emerge \
    sys-apps/dbus \
    sys-auth/elogind \
    sys-auth/pambase \
    || die "Failed to install dbus/elogind"
log_info "D-Bus + elogind installed"

# ── 12. PipeWire audio stack ───────────────────────────────────────
log_section "Installing PipeWire Audio Stack"
emerge \
    media-video/pipewire \
    media-libs/wireplumber \
    || die "Failed to install PipeWire"
log_info "PipeWire + WirePlumber installed"

# ── 13. KDE Plasma (Wayland) ───────────────────────────────────────
log_section "Installing KDE Plasma (Wayland) — this is the long step"
log_step "Using binary packages from Gentoo binhost where available..."

emerge \
    kde-plasma/plasma-meta \
    x11-misc/sddm \
    kde-plasma/sddm-kcm \
    || die "Failed to install KDE Plasma"

log_step "Installing essential KDE apps..."
emerge \
    kde-apps/konsole \
    kde-apps/dolphin \
    kde-apps/kate \
    kde-apps/ark \
    kde-apps/spectacle \
    kde-apps/gwenview \
    kde-apps/okular \
    xdg-utils/xdg-user-dirs \
    x11-misc/xdg-utils \
    || die "Failed to install KDE apps"

log_step "Fonts..."
emerge \
    media-fonts/noto \
    media-fonts/noto-emoji \
    media-fonts/terminus-font \
    || die "Failed to install fonts"

log_info "KDE Plasma installed"

# ── 14. XDG portal (needed for Flatpak / screen sharing) ──────────
log_section "XDG Desktop Portal"
emerge \
    sys-apps/xdg-desktop-portal \
    sys-apps/xdg-desktop-portal-kde \
    || log_warn "xdg-desktop-portal-kde failed — screen sharing may not work"

# ── 15. GRUB bootloader ────────────────────────────────────────────
log_section "Installing GRUB Bootloader"
emerge sys-boot/grub:2 || die "Failed to install GRUB"

if [[ "$BOOT_MODE" == "uefi" ]]; then
    emerge sys-boot/efibootmgr || die "Failed to install efibootmgr"
    log_step "Installing GRUB (UEFI mode)..."
    grub-install \
        --target=x86_64-efi \
        --efi-directory=/boot/efi \
        --bootloader-id=Gentoo \
        --recheck \
        || die "grub-install (UEFI) failed"
else
    log_step "Installing GRUB (BIOS mode) on ${DISK}..."
    grub-install \
        --target=i386-pc \
        --recheck \
        "${DISK}" \
        || die "grub-install (BIOS) failed"
fi

# Enable os-prober for dual-boot detection
sed -i 's/^#\?GRUB_DISABLE_OS_PROBER.*/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub \
    || echo 'GRUB_DISABLE_OS_PROBER=false' >> /etc/default/grub

grub-mkconfig -o /boot/grub/grub.cfg \
    || die "grub-mkconfig failed"
log_info "GRUB installed and configured"

# ── 16. AMD GPU — special kernel parameters ────────────────────────
if [[ "$GPU_TYPE" == "amd" ]]; then
    log_section "AMD GPU Kernel Parameters"
    # amdgpu.dc=1 enables Display Core (required for newer APUs)
    # amdgpu.sg_display=0 fixes black screen issues on some laptops
    if grep -q 'GRUB_CMDLINE_LINUX_DEFAULT' /etc/default/grub; then
        sed -i 's/\(GRUB_CMDLINE_LINUX_DEFAULT="[^"]*\)"/\1 amdgpu.dc=1 amdgpu.sg_display=0"/' \
            /etc/default/grub
    fi
    grub-mkconfig -o /boot/grub/grub.cfg
    log_info "AMD GPU kernel parameters added"
fi

# ── 17. OpenRC services ────────────────────────────────────────────
log_section "Enabling OpenRC Services"

# boot runlevel
rc-update add hwclock boot        && log_step "hwclock      -> boot"
rc-update add modules boot        && log_step "modules      -> boot"
rc-update add elogind boot        && log_step "elogind      -> boot"
rc-update add udev boot 2>/dev/null || log_warn "udev service not found (built into kernel?)"

# default runlevel
rc-update add dbus default        && log_step "dbus         -> default"
rc-update add NetworkManager default && log_step "NetworkManager -> default"
rc-update add chronyd default     && log_step "chronyd      -> default"
rc-update add bluetooth default   && log_step "bluetoothd   -> default" \
    || log_warn "bluetooth service not found, skipping"
rc-update add sddm default        && log_step "sddm         -> default"
rc-update add acpid default       && log_step "acpid        -> default" \
    || log_warn "acpid service not found, skipping"

# Disable old net.lo that conflicts with NetworkManager
rc-update del net.lo boot 2>/dev/null || true

# SSD: fstrim weekly via cron
if [[ "$DISK_TYPE" == "ssd" ]]; then
    mkdir -p /etc/cron.weekly
    printf '#!/bin/sh\n/sbin/fstrim -av\n' > /etc/cron.weekly/fstrim
    chmod +x /etc/cron.weekly/fstrim
    log_step "Weekly fstrim cron job added (SSD)"
fi

log_info "OpenRC services configured"

# ── 18. Root password ──────────────────────────────────────────────
log_section "Setting Root Password"
echo "root:${ROOT_PASSWORD}" | chpasswd
log_info "Root password set"

# ── 19. User account ───────────────────────────────────────────────
log_section "Creating User: ${USERNAME}"
useradd -m \
    -G wheel,audio,video,usb,plugdev,cdrom,input,dialout,bluetooth,network \
    -s /bin/bash \
    "${USERNAME}"
echo "${USERNAME}:${USER_PASSWORD}" | chpasswd
log_info "User '${USERNAME}' created"

# sudo — wheel group
echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/wheel
chmod 440 /etc/sudoers.d/wheel
log_step "sudo configured for wheel group"

# ── 20. SDDM configuration ─────────────────────────────────────────
log_section "Configuring SDDM"
mkdir -p /etc/sddm.conf.d
cat > /etc/sddm.conf.d/gentoo.conf << 'SDDMEOF'
[Theme]
Current=breeze

[Users]
MaximumUid=60000
MinimumUid=1000

[Wayland]
SessionDir=/usr/share/wayland-sessions
SDDMEOF
log_info "SDDM configured (Breeze theme, Wayland sessions)"

# ── 21. PipeWire autostart ─────────────────────────────────────────
# On OpenRC (no systemd user sessions), we use XDG autostart .desktop files.
# KDE Plasma 6 auto-starts PipeWire via plasma-workspace, but these entries
# serve as an explicit fallback.
log_section "PipeWire Autostart (XDG)"

USER_HOME="/home/${USERNAME}"
AUTOSTART_DIR="${USER_HOME}/.config/autostart"
mkdir -p "$AUTOSTART_DIR"

cat > "${AUTOSTART_DIR}/pipewire.desktop" << 'EOF'
[Desktop Entry]
Type=Application
Name=PipeWire
Exec=pipewire
Hidden=false
X-KDE-autostart-phase=1
X-KDE-autostart-condition=pipewire:General:autostart:true
EOF

cat > "${AUTOSTART_DIR}/wireplumber.desktop" << 'EOF'
[Desktop Entry]
Type=Application
Name=WirePlumber
Exec=wireplumber
Hidden=false
X-KDE-autostart-phase=1
EOF

cat > "${AUTOSTART_DIR}/pipewire-pulse.desktop" << 'EOF'
[Desktop Entry]
Type=Application
Name=PipeWire PulseAudio
Exec=pipewire-pulse
Hidden=false
X-KDE-autostart-phase=1
EOF

chown -R "${USERNAME}:${USERNAME}" "${USER_HOME}/.config"
log_info "PipeWire autostart entries created"

# ── 22. XDG user directories ───────────────────────────────────────
log_section "XDG User Directories"
su -c "xdg-user-dirs-update" "${USERNAME}" 2>/dev/null || true
log_info "XDG dirs created"

# ── 23. Consolefont service ────────────────────────────────────────
rc-update add consolefont boot 2>/dev/null || true

# ── Summary ────────────────────────────────────────────────────────
log_section "Chroot Setup Complete"
echo ""
echo -e "  ${GREEN}System configuration summary:${NC}"
echo "  Hostname  : ${HOSTNAME}"
echo "  User      : ${USERNAME}"
echo "  Timezone  : ${TIMEZONE}"
echo "  Init      : OpenRC + elogind"
echo "  Network   : NetworkManager"
echo "  Desktop   : KDE Plasma (Wayland)"
echo "  Audio     : PipeWire + WirePlumber"
echo "  Boot      : GRUB (${BOOT_MODE})"
echo "  GPU       : ${GPU_TYPE}"
echo "  CPU       : ${CPU_TYPE}"
echo ""
