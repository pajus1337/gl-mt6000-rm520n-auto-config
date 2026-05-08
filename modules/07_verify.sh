#!/bin/sh
# Module 07 — Post-install verification
# Runs a series of health checks and prints a summary.

module_verify() {
    log_step "Module 07: Post-install verification"

    local ok=0
    local fail=0

    _check() {
        local label="$1"
        local result="$2"
        if [ "$result" = "ok" ]; then
            log_ok "$label"
            ok=$(( ok + 1 ))
        else
            log_error "$label — $result"
            fail=$(( fail + 1 ))
        fi
    }

    # 1. WAN interface has an IP
    local wan_ip
    wan_ip="$(ip addr show "$WAN_ETH_IFACE" 2>/dev/null | awk '/inet /{print $2}' | head -1)"
    if printf '%s' "$wan_ip" | grep -q "192.168.225."; then
        _check "WAN IP ($wan_ip on $WAN_ETH_IFACE)" "ok"
    else
        _check "WAN IP on $WAN_ETH_IFACE" "no IP in 192.168.225.x range (got: ${wan_ip:-none})"
    fi

    # 2. Default route via modem
    local gw
    gw="$(ip route show default 2>/dev/null | awk '{print $3}' | head -1)"
    if [ "$gw" = "$MODEM_GW_IP" ]; then
        _check "Default route via $MODEM_GW_IP" "ok"
    else
        _check "Default route" "expected $MODEM_GW_IP, got ${gw:-none}"
    fi

    # 3. Ping modem gateway
    if ping -c 2 -W 3 "$MODEM_GW_IP" >/dev/null 2>&1; then
        _check "Ping modem ($MODEM_GW_IP)" "ok"
    else
        _check "Ping modem ($MODEM_GW_IP)" "no response"
    fi

    # 4. Ping internet
    if ping -c 2 -W 5 8.8.8.8 >/dev/null 2>&1; then
        _check "Ping internet (8.8.8.8)" "ok"
    else
        _check "Ping internet (8.8.8.8)" "failed"
    fi

    # 5. DNS resolution
    if nslookup openwrt.org >/dev/null 2>&1; then
        _check "DNS resolution (openwrt.org)" "ok"
    else
        _check "DNS resolution" "failed"
    fi

    # 6. USB modem device still present
    if detect_usb_modem; then
        _check "USB modem device (${MODEM_VID}:${MODEM_PID})" "ok"
    else
        _check "USB modem device" "not found"
    fi

    # 7. AT port responsive
    if [ -n "$AT_PORT" ] && _at_probe "$AT_PORT"; then
        _check "AT command port ($AT_PORT)" "ok"
    else
        _check "AT command port" "not responding"
    fi

    # 8. QMI device present
    if [ -c "$QMI_DEVICE" ]; then
        _check "QMI device ($QMI_DEVICE)" "ok"
    else
        _check "QMI device ($QMI_DEVICE)" "not found"
    fi

    # Signal info — parse +QCSQ: "tech",rssi,rsrp,sinr,rsrq
    if [ -n "$AT_PORT" ]; then
        section_header "Modem Signal Info"
        local sig
        sig="$(get_signal)"
        if [ -n "$sig" ]; then
            local tech rssi rsrp sinr rsrq
            tech="$(printf '%s' "$sig" | cut -d, -f1 | tr -d '+QCSQ: "')"
            rssi="$(printf '%s' "$sig" | cut -d, -f2)"
            rsrp="$(printf '%s' "$sig" | cut -d, -f3)"
            sinr="$(printf '%s' "$sig" | cut -d, -f4)"
            rsrq="$(printf '%s' "$sig" | cut -d, -f5)"
            printf "  Technology : %s\n"   "$tech"
            printf "  RSSI       : %s dBm\n" "$rssi"
            printf "  RSRP       : %s dBm\n" "$rsrp"
            printf "  SINR       : %s dB\n"  "$sinr"
            printf "  RSRQ       : %s dB\n"  "$rsrq"
        else
            printf "  Signal info unavailable\n"
        fi
        local cell
        cell="$(get_cell_info)"
        [ -n "$cell" ] && printf "  Cell info  : %s\n" "$cell"
        printf '\n'
    fi

    # Summary
    printf '\n'
    section_header "Verification Summary"
    printf "  ${GREEN}Passed:${RESET} %d\n" "$ok"
    [ "$fail" -gt 0 ] && printf "  ${RED}Failed:${RESET} %d\n" "$fail"
    printf '\n'

    if [ "$fail" -gt 0 ]; then
        log_warn "Some checks failed. See log at $LOG_FILE for details."
        return 1
    else
        log_ok "All checks passed. Setup complete!"
    fi
}
