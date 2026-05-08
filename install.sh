#!/bin/sh
# GL-MT6000 + RM520NGL Auto-Config Installer
#
# Usage (local):  sh install.sh [options]
# Usage (remote): wget -qO- https://raw.githubusercontent.com/pajus1337/gl-mt6000-rm520n-auto-config/master/install.sh | sh
#
# Options:
#   --dry-run    Show what would be done without making changes
#   --debug      Enable verbose AT command and debug output
#   --usb-only   Use USB-only mode (data + mgmt via USB, no GbE) [TODO]
#   --help       Show this help

set -e

REPO_URL="https://raw.githubusercontent.com/pajus1337/gl-mt6000-rm520n-auto-config/master"

# ── Script location detection ────────────────────────────────────────────────
# Returns local dir if running from a real checkout, or empty string.
_detect_install_dir() {
    case "$0" in
        *install.sh)
            local dir
            dir="$(cd "$(dirname "$0")" 2>/dev/null && pwd -P)"
            if [ -d "${dir}/modules" ] && [ -d "${dir}/lib" ]; then
                printf '%s' "$dir"
                return 0
            fi
            ;;
    esac
    printf ''
}

INSTALL_DIR="$(_detect_install_dir)"

if [ -z "$INSTALL_DIR" ]; then
    # Running piped (wget URL | sh) — stdin is the pipe, not a terminal.
    # Download all files, then re-exec from disk with /dev/tty so interactive
    # prompts work correctly.
    TMP_SETUP="/tmp/rm520n-setup-$$"
    mkdir -p "$TMP_SETUP/config" "$TMP_SETUP/lib" "$TMP_SETUP/modules" "$TMP_SETUP/optional"

    printf 'Downloading installer from GitHub...\n'
    for f in \
        install.sh \
        config/defaults.conf \
        lib/common.sh \
        lib/openwrt.sh \
        lib/modem.sh \
        modules/01_preflight.sh \
        modules/02_packages.sh \
        modules/03_usb_setup.sh \
        modules/04_wan_eth.sh \
        modules/05_luci_modem.sh \
        modules/06_firewall.sh \
        modules/07_verify.sh \
        optional/usb_only_mode.sh
    do
        if ! wget -qO "${TMP_SETUP}/${f}" "${REPO_URL}/${f}"; then
            printf 'ERROR: Failed to download %s\n' "$f" >&2
            rm -rf "$TMP_SETUP"
            exit 1
        fi
        printf '  %s\n' "$f"
    done
    printf '\n'

    chmod +x "${TMP_SETUP}/install.sh"
    exec sh "${TMP_SETUP}/install.sh" "$@" </dev/tty
    # exec replaces this process — nothing below runs in piped mode
fi

# ── From here: always running from a real directory with stdin = terminal ────

# Detect temp dir so we can clean up at the end
REMOTE_MODE=0
case "$INSTALL_DIR" in /tmp/rm520n-setup-*) REMOTE_MODE=1 ;; esac

# ── Parse arguments ──────────────────────────────────────────────────────────
DRY_RUN=0
DEBUG=0
USB_ONLY=0

for arg in "$@"; do
    case "$arg" in
        --dry-run)  DRY_RUN=1 ;;
        --debug)    DEBUG=1 ;;
        --usb-only) USB_ONLY=1 ;;
        --help|-h)
            cat <<EOF
GL-MT6000 + RM520NGL Auto-Config Installer

USAGE:
  sh install.sh [options]

OPTIONS:
  --dry-run    Show planned steps without making changes
  --debug      Verbose output including AT command I/O
  --usb-only   USB-only mode (TODO — not yet implemented)
  --help       Show this help

REQUIREMENTS:
  - OpenWrt 25.12+ on GL-MT6000
  - Waveshare 5G M.2 GbE board with RM520NGL
  - USB3.1 cable from board to router USB port
  - GbE cable from board to router WAN/LAN port
  - Internet access for package installation

EOF
            exit 0
            ;;
        *) printf 'Unknown option: %s\n' "$arg" >&2; exit 1 ;;
    esac
done

export DEBUG DRY_RUN

# ── Load config, libraries, modules ─────────────────────────────────────────
if [ ! -f "${INSTALL_DIR}/config/defaults.conf" ]; then
    printf 'ERROR: config/defaults.conf not found in %s\n' "$INSTALL_DIR" >&2
    exit 1
fi

. "${INSTALL_DIR}/config/defaults.conf"
[ -f "${INSTALL_DIR}/config/user.conf" ] && . "${INSTALL_DIR}/config/user.conf"

. "${INSTALL_DIR}/lib/common.sh"
. "${INSTALL_DIR}/lib/openwrt.sh"
. "${INSTALL_DIR}/lib/modem.sh"

. "${INSTALL_DIR}/modules/01_preflight.sh"
. "${INSTALL_DIR}/modules/02_packages.sh"
. "${INSTALL_DIR}/modules/03_usb_setup.sh"
. "${INSTALL_DIR}/modules/04_wan_eth.sh"
. "${INSTALL_DIR}/modules/05_luci_modem.sh"
. "${INSTALL_DIR}/modules/06_firewall.sh"
. "${INSTALL_DIR}/modules/07_verify.sh"

if [ "$USB_ONLY" = "1" ]; then
    . "${INSTALL_DIR}/optional/usb_only_mode.sh"
fi

# ── Main ─────────────────────────────────────────────────────────────────────
main() {
    print_banner

    if [ "$DRY_RUN" = "1" ]; then
        log_warn "DRY RUN mode — no changes will be made"
    fi

    log_info "Install directory: $INSTALL_DIR"
    log_info "Log file: $LOG_FILE"

    if [ "$USB_ONLY" = "1" ]; then
        module_preflight
        module_packages
        module_usb_only_mode
        return $?
    fi

    module_preflight
    module_packages
    module_usb_setup
    module_wan_eth
    module_luci_modem
    module_firewall
    module_verify

    printf '\n'
    log_ok "Installation finished. Full log: $LOG_FILE"

    if [ "$REMOTE_MODE" = "1" ]; then
        log_info "Cleaning up temporary files..."
        rm -rf "$INSTALL_DIR"
    fi
}

main "$@"
