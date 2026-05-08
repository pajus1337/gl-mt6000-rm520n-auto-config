#!/bin/sh
# Module 05 — LuCI modem status integration
# Sets up the QMI management interface (USB) so LuCI can display
# modem signal, registration, and connection info.
# Data path remains on GbE (module 04); this is monitoring only.

module_luci_modem() {
    log_step "Module 05: LuCI modem status integration"

    # Verify cdc-wdm device is available
    if [ ! -c "$QMI_DEVICE" ]; then
        log_warn "$QMI_DEVICE not found. Trying to detect QMI device..."
        local found
        found="$(ls /dev/cdc-wdm* 2>/dev/null | head -1)"
        if [ -n "$found" ]; then
            QMI_DEVICE="$found"
            log_ok "QMI device: $QMI_DEVICE"
        else
            log_warn "No cdc-wdm device found. LuCI modem status will not be available."
            log_warn "Make sure kmod-usb-wdm and kmod-usb-net-qmi-wwan are loaded."
            return 0
        fi
    fi
    log_ok "QMI device: $QMI_DEVICE"

    # Create QMI management interface in UCI
    # This interface is for monitoring only — it will not carry traffic
    # (data flows through the GbE WAN configured in module 04).
    log_info "Creating LuCI QMI management interface: $QMI_IFACE"

    if ! iface_exists "$QMI_IFACE"; then
        uci set "network.${QMI_IFACE}=interface"
    fi
    uci set "network.${QMI_IFACE}.proto=qmi"
    uci set "network.${QMI_IFACE}.device=$QMI_DEVICE"
    uci set "network.${QMI_IFACE}.apn=${APN:-internet}"
    uci set "network.${QMI_IFACE}.pdptype=ipv4v6"
    uci set "network.${QMI_IFACE}.auth=none"
    # Disable auto-connect — this interface is for status queries only
    uci set "network.${QMI_IFACE}.auto=0"

    uci commit network
    log_ok "QMI management interface configured"

    # Add a hotplug script to log modem signal on WAN connect events
    _install_signal_hotplug

    log_ok "LuCI modem integration complete"
    log_info "Open LuCI → Network → Interfaces to see the $QMI_IFACE status panel"
}

_install_signal_hotplug() {
    local hotplug_dir="/etc/hotplug.d/iface"
    mkdir -p "$hotplug_dir"

    cat > "${hotplug_dir}/99-modem-signal" <<'EOF'
#!/bin/sh
# Log modem signal strength on WAN events
[ "$ACTION" = "ifup" ] && [ "$INTERFACE" = "wan" ] || exit 0
AT_PORT=""
for p in /dev/ttyUSB2 /dev/ttyUSB3 /dev/ttyUSB1; do
    [ -c "$p" ] && AT_PORT="$p" && break
done
[ -n "$AT_PORT" ] || exit 0
printf 'AT+QCSQ\r\n' > "$AT_PORT"
sleep 0.5
logger -t modem-signal "$(timeout 3 head -c 128 < "$AT_PORT" 2>/dev/null)"
EOF

    chmod +x "${hotplug_dir}/99-modem-signal"
    log_ok "Signal logging hotplug script installed"
}
