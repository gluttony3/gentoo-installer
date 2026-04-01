#!/bin/bash
# lib/common.sh — shared colors, logging, and helper functions

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

MOUNTPOINT="/mnt/gentoo"

log_info()    { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[!!]${NC} $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_step()    { echo -e "  ${CYAN}-->${NC} $*"; }
log_section() {
    echo ""
    echo -e "${BOLD}${BLUE}============================================${NC}"
    echo -e "${BOLD}${BLUE}  $*${NC}"
    echo -e "${BOLD}${BLUE}============================================${NC}"
}

die() {
    log_error "$*"
    exit 1
}

check_root() {
    [[ $EUID -eq 0 ]] || die "Run this script as root"
}

check_deps() {
    log_section "Checking Prerequisites"
    local missing=()
    for cmd in curl wget parted mkfs.fat mkfs.ext4 mkswap lspci lsblk sgdisk wipefs tar sha256sum; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    if (( ${#missing[@]} > 0 )); then
        die "Missing required tools: ${missing[*]}"
    fi
    log_step "Checking internet connectivity..."
    if ! curl -sf --max-time 10 https://distfiles.gentoo.org > /dev/null; then
        die "No internet connection — cannot download stage3"
    fi
    log_info "All prerequisites satisfied"
}

detect_boot_mode() {
    if [[ -d /sys/firmware/efi/efivars ]]; then
        BOOT_MODE="uefi"
        log_info "Boot mode: UEFI"
    else
        BOOT_MODE="bios"
        log_info "Boot mode: BIOS/Legacy"
    fi
    export BOOT_MODE
}

# ask_input VAR "Prompt" "default"
ask_input() {
    local varname="$1"
    local prompt="$2"
    local default="${3:-}"
    if [[ -n "$default" ]]; then
        echo -ne "${CYAN}${prompt}${NC} [${BOLD}${default}${NC}]: "
    else
        echo -ne "${CYAN}${prompt}${NC}: "
    fi
    read -r value
    printf -v "$varname" '%s' "${value:-$default}"
}

confirm() {
    local prompt="${1:-Continue?}"
    echo -ne "\n${YELLOW}${prompt} [y/N]: ${NC}"
    read -r ans
    [[ "${ans,,}" =~ ^y(es)?$ ]]
}
