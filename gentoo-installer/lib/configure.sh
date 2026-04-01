#!/bin/bash
# lib/configure.sh — bind-mounts, config transfer, chroot invocation

_mount_pseudo_fs() {
    log_step "Mounting pseudo-filesystems for chroot..."
    mount -t proc    none              "${MOUNTPOINT}/proc"
    mount --rbind    /sys              "${MOUNTPOINT}/sys"
    mount --make-rslave               "${MOUNTPOINT}/sys"
    mount --rbind    /dev              "${MOUNTPOINT}/dev"
    mount --make-rslave               "${MOUNTPOINT}/dev"
    # /run is needed by udev/dbus inside chroot
    if [[ -d /run ]]; then
        mount --bind /run             "${MOUNTPOINT}/run"
        mount --make-slave            "${MOUNTPOINT}/run"
    fi
}

run_chroot_config() {
    log_section "Configuring Installed System (chroot)"

    _mount_pseudo_fs

    # Write config variables for chroot-setup.sh
    log_step "Writing install-config.sh..."
    cat > "${MOUNTPOINT}/root/install-config.sh" << EOF
HOSTNAME="${HOSTNAME}"
USERNAME="${USERNAME}"
TIMEZONE="${TIMEZONE}"
BOOT_MODE="${BOOT_MODE}"
DISK="${DISK}"
DISK_TYPE="${DISK_TYPE}"
GPU_TYPE="${GPU_TYPE}"
CPU_TYPE="${CPU_TYPE}"
CPU_UCODE_PKG="${CPU_UCODE_PKG:-}"
EOF

    # Passwords in separate files so special chars can't break heredocs
    printf '%s' "$ROOT_PASSWORD" > "${MOUNTPOINT}/root/.rootpw"
    printf '%s' "$USER_PASSWORD" > "${MOUNTPOINT}/root/.userpw"
    chmod 600 "${MOUNTPOINT}/root/.rootpw" "${MOUNTPOINT}/root/.userpw"

    # Copy chroot script into /mnt/gentoo
    local chroot_script="${SCRIPT_DIR}/lib/chroot-setup.sh"
    [[ -f "$chroot_script" ]] || die "chroot-setup.sh not found: $chroot_script"
    cp "$chroot_script" "${MOUNTPOINT}/root/chroot-setup.sh"
    chmod +x "${MOUNTPOINT}/root/chroot-setup.sh"

    log_step "Entering chroot and running setup (this will take a while)..."
    chroot "${MOUNTPOINT}" /bin/bash -c \
        "source /etc/profile && export PS1='(chroot) \u@\h \w # ' && /root/chroot-setup.sh" \
        || die "chroot configuration failed"

    # Cleanup sensitive files
    rm -f "${MOUNTPOINT}/root/install-config.sh"
    rm -f "${MOUNTPOINT}/root/chroot-setup.sh"
    rm -f "${MOUNTPOINT}/root/.rootpw"
    rm -f "${MOUNTPOINT}/root/.userpw"

    log_info "Chroot configuration complete"
}
