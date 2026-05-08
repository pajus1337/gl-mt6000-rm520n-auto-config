#!/bin/sh
# Module 01 — Preflight checks
# Validates system requirements before any changes are made.

module_preflight() {
    log_step "Module 01: Preflight checks"

    require_root

    # OpenWrt version
    check_min_version "$MIN_OPENWRT_MAJOR" "$MIN_OPENWRT_MINOR"

    # Check apk is available
    if ! command -v apk >/dev/null 2>&1; then
        die "apk package manager not found. This installer requires OpenWrt 25.12+."
    fi
    log_ok "Package manager: apk"

    # Check available overlay space (need at least 8 MB free)
    local free_kb
    free_kb="$(get_free_space_kb /overlay)"
    if [ -n "$free_kb" ] && [ "$free_kb" -lt 8192 ]; then
        die "Insufficient overlay space: ${free_kb}KB free, 8192KB required."
    fi
    log_ok "Overlay space: ${free_kb}KB free"

    # Check USB modem is connected
    if ! detect_usb_modem; then
        log_warn "RM520NGL USB device (${MODEM_VID}:${MODEM_PID}) not detected."
        log_warn "Make sure the Waveshare USB3.1 cable is plugged into the router."
        if ! confirm "Continue anyway?"; then
            die "Aborted by user."
        fi
    else
        log_ok "RM520NGL USB device detected"
    fi

    # Check internet connectivity for apk update
    if ! ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
        log_warn "No internet connectivity detected."
        log_warn "Package installation may fail without internet access."
        confirm "Continue without internet?" || die "Aborted by user."
    else
        log_ok "Internet connectivity OK"
    fi

    # Check UCI / uci binary
    command -v uci >/dev/null 2>&1 || die "uci not found — is this really OpenWrt?"
    log_ok "UCI available"

    log_ok "Preflight checks passed"
}
