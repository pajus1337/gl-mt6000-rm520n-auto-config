#!/bin/sh
# Module 03 — USB interface setup
# Detects modem AT port, configures PCIe/GbE mode via AT commands,
# and sets up the USB management interface for LuCI.

module_usb_setup() {
    log_step "Module 03: USB interface and modem AT configuration"

    # Load kernel modules (actual module names differ from apk package names)
    log_info "Loading USB kernel modules..."
    modprobe option    2>/dev/null || true   # kmod-usb-serial-option
    modprobe qmi_wwan  2>/dev/null || true   # kmod-usb-net-qmi-wwan
    modprobe cdc_wdm   2>/dev/null || true   # kmod-usb-wdm

    # Force kernel to re-probe the modem USB device so drivers bind
    _usb_reprobe

    # Wait for ttyUSB devices to appear
    log_info "Waiting for /dev/ttyUSB* ports..."
    local wait=0
    while [ ! -c /dev/ttyUSB0 ] && [ "$wait" -lt 15 ]; do
        sleep 1
        wait=$(( wait + 1 ))
    done
    [ -c /dev/ttyUSB0 ] || log_warn "ttyUSB ports not found — AT detection may fail"

    # Find AT command port
    detect_at_port

    # Show firmware version
    log_info "Modem firmware: $(get_modem_firmware)"

    # Check current PCIe mode
    local cur_pcie
    cur_pcie="$(get_pcie_mode)"
    log_info "Current pcie/mode: ${cur_pcie:-unknown}"

    if [ "$cur_pcie" = "1" ]; then
        log_ok "Modem already in PCIe/GbE mode — skipping AT reconfiguration"
    else
        log_info "Switching modem to PCIe/GbE mode (requires reboot)..."
        configure_pcie_eth_mode
        log_info "Waiting ${MODEM_REBOOT_WAIT}s for modem to reboot..."
        wait_with_spinner "$MODEM_REBOOT_WAIT" "Modem rebooting"
        wait_for_usb_modem 30
        sleep 2
        detect_at_port
        log_ok "Modem rebooted and USB port is back"
    fi

    # Verify PCIe mode is now active
    cur_pcie="$(get_pcie_mode)"
    [ "$cur_pcie" = "1" ] || die "Modem did not switch to PCIe mode (pcie/mode=$cur_pcie)"
    log_ok "Modem in PCIe/GbE mode"

    # AT+QMAPWAC=1 enables WWAN auto-connect in PCIe/GbE mode. It is a
    # persistent NVM setting but resets to 0 after a firmware upgrade, so
    # check its state and apply only when needed — avoids touching the
    # modem when everything is already working correctly.
    local wac
    wac="$(at_cmd 'AT+QMAPWAC?' | grep -oE '[01]' | head -1)"
    if [ "$wac" = "1" ]; then
        log_ok "WWAN auto-connect already enabled"
    else
        log_info "Enabling WWAN auto-connect (QMAPWAC)..."
        at_cmd_expect 'AT+QMAPWAC=1' "OK"
        log_ok "WWAN auto-connect enabled"
    fi

    # Configure APN if not already set
    _configure_apn

    log_ok "USB setup complete"
}

_configure_apn() {
    # If APN not set in config, ask user
    if [ -z "$APN" ]; then
        printf "${YELLOW}Enter your APN (e.g. internet, broadband): ${RESET}"
        read -r APN
        [ -n "$APN" ] || die "APN cannot be empty"

        # Save to user.conf for future runs
        mkdir -p "$(dirname "$INSTALL_DIR/config/user.conf")"
        printf 'APN="%s"\n' "$APN" >> "$INSTALL_DIR/config/user.conf"
    fi

    log_info "Setting APN: $APN"
    at_cmd_expect "AT+CGDCONT=1,\"${PDP_TYPE}\",\"${APN}\"" "OK"
    log_ok "APN configured: $APN"
}
