#!/bin/bash
# lib/detect.sh — hardware detection: CPU arch/microarch, GPU drivers

detect_cpu() {
    log_section "CPU Detection"

    if grep -qi "intel" /proc/cpuinfo; then
        CPU_TYPE="intel"
        CPU_UCODE_PKG="sys-firmware/intel-microcode"

        # Detect generation for -march
        local model_name
        model_name=$(grep -m1 "model name" /proc/cpuinfo | cut -d: -f2)
        if echo "$model_name" | grep -qiE "12th|13th|14th|Alder|Raptor|Meteor"; then
            CPU_MARCH="alderlake"
        else
            CPU_MARCH="native"
        fi
        log_info "Intel CPU detected -> ${CPU_MARCH}"

    elif grep -qi "amd" /proc/cpuinfo; then
        CPU_TYPE="amd"
        # AMD microcode is part of linux-firmware in Gentoo
        CPU_UCODE_PKG="sys-kernel/linux-firmware"

        local family
        family=$(grep -m1 "cpu family" /proc/cpuinfo | awk '{print $NF}')
        case "$family" in
            26) CPU_MARCH="znver4"
                log_info "AMD Zen 4 CPU detected (Ryzen 7000) -> -march=znver4" ;;
            25) CPU_MARCH="znver3"
                log_info "AMD Zen 3 CPU detected (Ryzen 5000/7000U Barcelo) -> -march=znver3" ;;
            23) CPU_MARCH="znver2"
                log_info "AMD Zen 2 CPU detected -> -march=znver2" ;;
            *)  CPU_MARCH="x86-64-v3"
                log_warn "Unknown AMD family $family -> -march=x86-64-v3" ;;
        esac
    else
        CPU_TYPE="generic"
        CPU_UCODE_PKG=""
        CPU_MARCH="x86-64-v2"
        log_warn "Unknown CPU vendor -> generic x86-64-v2"
    fi

    export CPU_TYPE CPU_UCODE_PKG CPU_MARCH
}

detect_gpu() {
    log_section "GPU Detection"

    local gpu_info
    gpu_info=$(lspci 2>/dev/null | grep -iE "VGA compatible|3D controller|Display controller" || true)

    if [[ -z "$gpu_info" ]]; then
        log_warn "No GPU found via lspci, using generic fallback"
        GPU_TYPE="generic"
        VIDEO_CARDS="fbdev vesa"
        GPU_USE_FLAGS=""
        export GPU_TYPE VIDEO_CARDS GPU_USE_FLAGS
        return
    fi

    log_step "Detected GPU(s):"
    echo "$gpu_info"
    echo ""

    # Check hybrid Intel+NVIDIA first (most specific)
    if echo "$gpu_info" | grep -qi "intel" && echo "$gpu_info" | grep -qi "nvidia"; then
        GPU_TYPE="hybrid-nvidia"
        VIDEO_CARDS="intel i965"
        GPU_USE_FLAGS="opencl"
        log_info "Hybrid Intel+NVIDIA -> using Intel (open) + nouveau fallback"
        log_warn "Proprietary NVIDIA on Wayland requires manual setup post-install"

    elif echo "$gpu_info" | grep -qi "nvidia"; then
        GPU_TYPE="nvidia"
        VIDEO_CARDS="nouveau"
        GPU_USE_FLAGS=""
        log_warn "NVIDIA GPU -> nouveau (open-source). Proprietary driver = manual post-install."

    elif echo "$gpu_info" | grep -qi "amd\|radeon\|advanced micro devices"; then
        GPU_TYPE="amd"
        VIDEO_CARDS="amdgpu radeonsi"
        GPU_USE_FLAGS="vaapi vulkan"
        log_info "AMD GPU -> amdgpu + radeonsi (Mesa, open-source)"

    elif echo "$gpu_info" | grep -qi "intel"; then
        GPU_TYPE="intel"
        VIDEO_CARDS="intel i965"
        GPU_USE_FLAGS="vaapi vulkan"
        log_info "Intel GPU -> intel driver (Mesa)"

    else
        GPU_TYPE="generic"
        VIDEO_CARDS="fbdev vesa"
        GPU_USE_FLAGS=""
        log_warn "Unknown GPU -> fbdev/vesa fallback"
    fi

    export GPU_TYPE VIDEO_CARDS GPU_USE_FLAGS
}
