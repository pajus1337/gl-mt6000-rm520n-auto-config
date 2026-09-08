#!/bin/sh
# Module 04 — WAN via Ethernet (Waveshare GbE bridge)
# Configures the router's WAN interface to use the GbE port
# connected to the Waveshare board. Modem acts as DHCP server
# at 192.168.225.1; router becomes a DHCP client on that subnet.

module_wan_eth() {
    log_step "Module 04: WAN Ethernet configuration"

    # Prompt user to connect the GbE cable before we start polling
    printf "\n"
    printf "${BOLD}  ACTION REQUIRED${RESET}\n"
    printf "  Connect the Waveshare board GbE port to the router WAN/LAN port now.\n"
    printf "  The modem will assign an IP in the %s range.\n" "$MODEM_SUBNET"
    printf "\n"
    printf "${YELLOW}  Press Enter when the cable is connected...${RESET}"
    read -r _dummy

    local attempts=0
    WAN_ETH_IFACE=""

    log_info "Waiting for Waveshare GbE interface to get DHCP from modem..."
    while [ -z "$WAN_ETH_IFACE" ] && [ "$attempts" -lt 12 ]; do
        detect_wan_eth_iface && break
        sleep 5
        attempts=$(( attempts + 1 ))
    done

    if [ -z "$WAN_ETH_IFACE" ]; then
        log_warn "Auto-detection failed. Available network interfaces:"
        ip link show | awk -F': ' '/^[0-9]+:/{print "  " $2}'
        printf "${YELLOW}Enter the ethernet interface connected to Waveshare board: ${RESET}"
        read -r WAN_ETH_IFACE
        [ -n "$WAN_ETH_IFACE" ] || die "Interface name cannot be empty"
    fi

    log_info "Configuring $WAN_ETH_IFACE as WAN (DHCP)..."

    # Back up existing WAN config
    local existing_device
    existing_device="$(uci get "network.${WAN_IFACE}.device" 2>/dev/null)"
    if [ -n "$existing_device" ] && [ "$existing_device" != "$WAN_ETH_IFACE" ]; then
        log_warn "Replacing existing WAN device: $existing_device → $WAN_ETH_IFACE"
        uci set "network.${WAN_IFACE}_backup=interface"
        uci set "network.${WAN_IFACE}_backup.device=$existing_device"
        uci set "network.${WAN_IFACE}_backup.proto=dhcp"
        uci set "network.${WAN_IFACE}_backup.auto=0"
    fi

    # Create or update WAN interface
    if ! iface_exists "$WAN_IFACE"; then
        uci set "network.${WAN_IFACE}=interface"
    fi
    uci set "network.${WAN_IFACE}.device=$WAN_ETH_IFACE"
    uci set "network.${WAN_IFACE}.proto=dhcp"
    # Remove any stale static-IP options that would conflict with DHCP
    uci delete "network.${WAN_IFACE}.ipaddr"   2>/dev/null || true
    uci delete "network.${WAN_IFACE}.netmask"  2>/dev/null || true
    uci delete "network.${WAN_IFACE}.gateway"  2>/dev/null || true
    uci delete "network.${WAN_IFACE}.ip6addr"  2>/dev/null || true
    uci delete "network.${WAN_IFACE}.ip6gw"    2>/dev/null || true

    # Commit and restart network
    uci commit network
    log_info "Restarting network..."
    service network restart

    # Wait for interface to come up — use ip addr (ubus may block after network restart)
    log_info "Waiting for WAN DHCP lease from modem..."
    local elapsed=0
    while [ "$elapsed" -lt 30 ]; do
        local ip
        ip="$(ip addr show "$WAN_ETH_IFACE" 2>/dev/null | awk '/inet /{print $2}' | head -1)"
        case "$ip" in
            192.168.22[0-9].*|192.168.2[0-2][0-9].*)
                log_ok "WAN interface $WAN_ETH_IFACE got IP: $ip"
                log_ok "Modem gateway: $MODEM_GW_IP"
                configure_lan_ipv6_fallback
                return 0
                ;;
        esac
        sleep 2
        elapsed=$(( elapsed + 2 ))
    done

    log_warn "WAN did not get a DHCP lease within 30s."
    log_warn "Check that the GbE cable is connected to the Waveshare board."
}

# The modem hands out IPv4-only DHCP on its private GbE subnet — no delegated
# IPv6 prefix ever reaches the LAN this way. Left alone, odhcpd still emits RAs
# with ra_lifetime=0 for that reason (harmless log noise, but clients that try
# IPv6-first can see a brief happy-eyeballs delay). Since there is no IPv6 on
# WAN in this setup, disable RA/DHCPv6/NDP on LAN — but only when the WAN
# interface truly has no global IPv6 address, so this self-corrects if a future
# firmware/APN ever does provide one.
configure_lan_ipv6_fallback() {
    uci -q get dhcp.lan >/dev/null 2>&1 || return 0

    if wan_has_global_ipv6 "$WAN_ETH_IFACE"; then
        log_ok "Global IPv6 present on WAN — leaving LAN IPv6 services untouched"
        return 0
    fi

    log_info "No global IPv6 on WAN — disabling LAN RA/DHCPv6/NDP to avoid odhcpd fallback delays"
    uci set dhcp.lan.ra='disabled'
    uci set dhcp.lan.dhcpv6='disabled'
    uci set dhcp.lan.ndp='disabled'
    uci commit dhcp
    service odhcpd restart 2>/dev/null || true
    log_ok "LAN IPv6 RA/DHCPv6/NDP disabled"
}
