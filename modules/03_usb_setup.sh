#!/bin/sh
# Module 03 — USB interface setup
# Detects modem AT port, configures PCIe/GbE mode via AT commands,
# and sets up the USB management interface for LuCI.

module_usb_setup() {
    log_step "Module 03: USB interface and modem AT configuration"

    # Ensure kernel modules are loaded
    log_info "Loading USB kernel modules..."
    modprobe kmod-usb-serial-option 2>/dev/null || true
    modprobe kmod-usb-net-qmi-wwan 2>/dev/null || true
    modprobe kmod-usb-wdm 2>/dev/null || true

    # Wait for USB device and serial ports to appear
    wait_for_usb_modem 30
    sleep 2

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
