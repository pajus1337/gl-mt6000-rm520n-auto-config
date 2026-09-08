#!/bin/sh
# Module 06 — Firewall configuration
# Ensures the WAN interface is in the wan zone and masquerade is on.
# Uses fw4 (nftables) UCI config — do NOT mix raw iptables/nft rules.

module_firewall() {
    log_step "Module 06: Firewall configuration"

    # Verify fw4 is the active firewall
    if ! command -v fw4 >/dev/null 2>&1; then
        log_warn "fw4 not found — skipping firewall module"
        log_warn "Configure firewall manually via LuCI → Network → Firewall"
        return 0
    fi

    # Check if WAN zone exists
    local wan_zone
    wan_zone="$(uci show firewall | grep "=zone" | while read -r line; do
        local name
        name="$(uci get "${line%=zone}.name" 2>/dev/null)"
        [ "$name" = "wan" ] && printf '%s' "${line%=zone}" && break
    done)"

    if [ -z "$wan_zone" ]; then
        log_warn "No 'wan' firewall zone found. Creating one..."
        local new_zone
        new_zone="$(uci add firewall zone)"
        uci set "firewall.${new_zone}.name=wan"
        uci set "firewall.${new_zone}.input=DROP"
        uci set "firewall.${new_zone}.output=ACCEPT"
        uci set "firewall.${new_zone}.forward=DROP"
        uci set "firewall.${new_zone}.masq=1"
        uci set "firewall.${new_zone}.mtu_fix=1"
        uci add_list "firewall.${new_zone}.network=${WAN_IFACE}"
        wan_zone="firewall.${new_zone}"
        log_ok "WAN zone created"
    else
        # Ensure WAN interface is listed in the zone
        local zone_nets
        zone_nets="$(uci get "${wan_zone}.network" 2>/dev/null)"
        if ! printf '%s' "$zone_nets" | grep -qw "$WAN_IFACE"; then
            uci add_list "${wan_zone}.network=${WAN_IFACE}"
            log_ok "Added $WAN_IFACE to wan zone"
        else
            log_ok "$WAN_IFACE already in wan zone"
        fi

        # Ensure masquerade is enabled
        uci set "${wan_zone}.masq=1"
        uci set "${wan_zone}.mtu_fix=1"
    fi

    # MSS clamping for the WAN interface (important for 5G/PPP-over-GbE path):
    # fw4 clamps MSS to path MTU natively via the zone's mtu_fix option — already
    # set above. There is no "TCPMSS" rule target under fw4/nftables; a custom
    # `config rule` using it is rejected outright by the schema, so no separate
    # rule is created here.

    uci commit firewall
    service firewall reload
    log_ok "Firewall configuration applied"
}
