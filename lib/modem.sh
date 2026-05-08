#!/bin/sh
# Modem detection, AT command interface, and QMI helpers for RM520NGL.
# Source this file; do not execute directly.

# detect_at_port — finds the AT command serial port and sets AT_PORT
detect_at_port() {
    log_info "Detecting RM520NGL AT command port..."
    local port

    # ttyUSB2 is the standard AT port for RM520NGL in default USB layout:
    # ttyUSB0=DIAG, ttyUSB1=NMEA, ttyUSB2=AT, ttyUSB3=AT(secondary)
    for candidate in /dev/ttyUSB2 /dev/ttyUSB3 /dev/ttyUSB1 /dev/ttyUSB0; do
        [ -c "$candidate" ] || continue
        if _at_probe "$candidate"; then
            AT_PORT="$candidate"
            log_ok "AT port: $AT_PORT"
            return 0
        fi
    done

    die "No responsive AT command port found. Is the modem USB connected?"
}

# _at_probe PORT — sends AT and checks for OK response
_at_probe() {
    local port="$1"
    local resp
    stty -F "$port" "${AT_BAUD:-115200}" raw -echo 2>/dev/null || true
    # Keep port open bidirectionally — avoids race where modem responds before
    # a second open() for reading is issued, causing the reply to be lost.
    exec 3<>"$port"
    printf 'AT\r\n' >&3
    resp="$(timeout 2 head -c 64 <&3 2>/dev/null)"
    exec 3>&-
    printf '%s' "$resp" | grep -q 'OK'
}

# at_cmd COMMAND — sends AT command and prints response
# Uses AT_PORT; call detect_at_port first.
at_cmd() {
    local cmd="$1"
    [ -n "$AT_PORT" ] || die "AT_PORT not set; call detect_at_port first"
    log_debug "AT >> $cmd"
    local resp
    exec 3<>"$AT_PORT"
    printf '%s\r\n' "$cmd" >&3
    resp="$(timeout "${AT_TIMEOUT:-5}" head -c 512 <&3 2>/dev/null)"
    exec 3>&-
    log_debug "AT << $resp"
    printf '%s' "$resp"
}

# at_cmd_expect COMMAND EXPECTED_PATTERN — dies if response doesn't match
at_cmd_expect() {
    local cmd="$1"
    local pattern="$2"
    local resp
    resp="$(at_cmd "$cmd")"
    printf '%s' "$resp" | grep -q "$pattern" || \
        die "AT command '$cmd' failed. Expected '$pattern', got: $resp"
}

# detect_usb_modem — returns 0 if RM520NGL USB device is present
# Uses sysfs (lsusb is not available on vanilla OpenWrt)
detect_usb_modem() {
    local vid pid
    for vid in /sys/bus/usb/devices/*/idVendor; do
        [ -f "$vid" ] || continue
        grep -q "$MODEM_VID" "$vid" 2>/dev/null || continue
        pid="${vid%idVendor}idProduct"
        grep -q "$MODEM_PID" "$pid" 2>/dev/null && return 0
    done
    return 1
}

# _usb_reprobe — unbind/bind modem USB device so newly loaded drivers attach
_usb_reprobe() {
    local devpath
    for devpath in /sys/bus/usb/devices/*/idVendor; do
        [ -f "$devpath" ] || continue
        grep -q "$MODEM_VID" "$devpath" 2>/dev/null || continue
        local dev="${devpath%/idVendor}"
        local devname="${dev##*/}"
        log_debug "Reprobing USB device: $devname"
        echo "$devname" > /sys/bus/usb/drivers/usb/unbind 2>/dev/null || true
        sleep 1
        echo "$devname" > /sys/bus/usb/drivers/usb/bind   2>/dev/null || true
        sleep 2
        return 0
    done
}

# wait_for_usb_modem TIMEOUT_SECS — waits until modem USB device appears
wait_for_usb_modem() {
    local timeout="${1:-30}"
    local elapsed=0
    log_info "Waiting for RM520NGL USB device (${MODEM_VID}:${MODEM_PID})..."
    while ! detect_usb_modem; do
        sleep 1
        elapsed=$(( elapsed + 1 ))
        [ "$elapsed" -ge "$timeout" ] && die "Modem USB device not found after ${timeout}s"
    done
    log_ok "Modem USB device detected"
}

# get_modem_firmware — prints modem firmware version via ATI
get_modem_firmware() {
    [ -n "$AT_PORT" ] || return 1
    at_cmd "ATI" | grep -i "revision" | head -1
}

# get_pcie_mode — prints current pcie/mode value (0 or 1)
get_pcie_mode() {
    at_cmd 'AT+QCFG="pcie/mode"' | grep -o '[0-9]' | head -1
}

# get_eth_driver — prints current eth_driver state
get_eth_driver() {
    at_cmd 'AT+QETH="eth_driver"'
}

# configure_pcie_eth_mode — enables PCIe + RTL8125 GbE mode on modem
# Requires firmware RM520NGLAAR05A01M4G or later.
configure_pcie_eth_mode() {
    log_step "Configuring modem for PCIe/GbE data path"

    local fw_ver
    fw_ver="$(get_modem_firmware)"
    log_info "Modem firmware: $fw_ver"

    log_info "Setting pcie/mode=1..."
    at_cmd_expect 'AT+QCFG="pcie/mode",1' "OK"

    log_info "Loading RTL8125 driver..."
    at_cmd_expect 'AT+QETH="eth_driver","r8125",1' "OK"

    log_info "Enabling auto-connect (QMAPWAC)..."
    at_cmd_expect 'AT+QMAPWAC=1' "OK"

    log_info "Rebooting modem (AT+CFUN=1,1)..."
    at_cmd 'AT+CFUN=1,1'
}

# get_signal — prints a summary of modem signal quality
get_signal() {
    [ -n "$AT_PORT" ] || return 1
    at_cmd "AT+QCSQ"
}

# get_cell_info — prints serving cell details
get_cell_info() {
    [ -n "$AT_PORT" ] || return 1
    at_cmd 'AT+QENG="servingcell"'
}

# detect_wan_eth_iface — finds the ethernet interface connected to Waveshare board
# Looks for DHCP offer in 192.168.225.x from any ethernet interface.
detect_wan_eth_iface() {
    log_info "Detecting Waveshare GbE interface..."
    local iface

    # Check which interfaces have a carrier but are not already configured as WAN
    for iface in $(ls /sys/class/net/); do
        case "$iface" in lo|br-*|wlan*|wwan*) continue ;; esac
        local carrier
        carrier="$(cat /sys/class/net/$iface/carrier 2>/dev/null)"
        [ "$carrier" = "1" ] || continue

        local cur_ip
        cur_ip="$(ip addr show "$iface" 2>/dev/null | awk '/inet /{print $2}' | head -1)"
        # If this interface already has a 192.168.225.x address, it's our interface
        case "$cur_ip" in 192.168.225.*) WAN_ETH_IFACE="$iface"; log_ok "GbE interface: $iface ($cur_ip)"; return 0 ;; esac
    done

    log_warn "Could not auto-detect Waveshare GbE interface."
    log_warn "After modem reboot, re-run this module or set WAN_ETH_IFACE manually."
    WAN_ETH_IFACE=""
    return 1
}
