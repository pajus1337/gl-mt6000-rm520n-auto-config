#!/bin/sh
# OpenWrt-specific helpers: apk, UCI, netifd, version checks.
# Source this file; do not execute directly.

# apk_install PACKAGE [PACKAGE...] — install one or more packages
apk_install() {
    log_info "Installing: $*"
    apk update -q && apk add "$@" || die "Failed to install packages: $*"
}

# apk_installed PACKAGE — returns 0 if package is installed
apk_installed() {
    apk info -e "$1" >/dev/null 2>&1
}

# apk_ensure PACKAGE [PACKAGE...] — install only what is missing
apk_ensure() {
    local missing=""
    for pkg in "$@"; do
        apk_installed "$pkg" || missing="$missing $pkg"
    done
    [ -z "$missing" ] && return 0
    apk_install $missing
}

# get_openwrt_version — prints MAJOR.MINOR (e.g. "25.12")
get_openwrt_version() {
    if [ -f /etc/openwrt_release ]; then
        . /etc/openwrt_release
        printf '%s' "$DISTRIB_RELEASE"
    else
        printf 'unknown'
    fi
}

# check_min_version MAJOR MINOR — dies if OpenWrt version is too old
check_min_version() {
    local req_major="$1"
    local req_minor="$2"
    local ver
    ver="$(get_openwrt_version)"

    local cur_major cur_minor
    cur_major="$(printf '%s' "$ver" | cut -d. -f1)"
    cur_minor="$(printf '%s' "$ver" | cut -d. -f2)"

    if [ "$cur_major" -lt "$req_major" ] 2>/dev/null; then
        die "OpenWrt $req_major.$req_minor+ required (found $ver)"
    fi
    if [ "$cur_major" -eq "$req_major" ] && [ "$cur_minor" -lt "$req_minor" ] 2>/dev/null; then
        die "OpenWrt $req_major.$req_minor+ required (found $ver)"
    fi
    log_ok "OpenWrt version: $ver"
}

# uci_set OPTION VALUE — set a UCI option (commits immediately)
uci_set() {
    uci set "$1"="$2"
}

# uci_add_list OPTION VALUE
uci_add_list() {
    uci add_list "$1"="$2"
}

# uci_commit_restart CONFIG SERVICE
uci_commit_restart() {
    uci commit "$1"
    service "$2" restart
}

# iface_exists NAME — returns 0 if UCI interface exists
iface_exists() {
    uci get "network.$1" >/dev/null 2>&1
}

# get_free_space_kb PATH — prints available space in KB
get_free_space_kb() {
    df -k "${1:-/overlay}" 2>/dev/null | awk 'NR==2{print $4}'
}

# wan_has_global_ipv6 IFACE — returns 0 if the interface has a global-scope IPv6 address
wan_has_global_ipv6() {
    ip -6 addr show dev "$1" scope global 2>/dev/null | grep -q "inet6"
}

# wait_for_netifd — waits until netifd is ready
wait_for_netifd() {
    local tries=0
    while ! ubus list network.interface >/dev/null 2>&1; do
        sleep 1
        tries=$(( tries + 1 ))
        [ "$tries" -ge 30 ] && die "netifd did not start within 30s"
    done
}
