#!/bin/sh
# GL-MT6000 + RM520NGL Auto-Config Installer
#
# Usage (local):  sh install.sh [options]
# Usage (remote): curl -fsSL https://raw.githubusercontent.com/pajus1337/gl-mt6000-rm520n-auto-config/main/install.sh | sh
#
# Options:
#   --dry-run    Show what would be done without making changes
#   --debug      Enable verbose AT command and debug output
#   --usb-only   Use USB-only mode (data + mgmt via USB, no GbE) [TODO]
#   --help       Show this help

set -e

# ── Script location detection (local vs piped) ──────────────────────────────
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
    # Running piped or from unknown location — download files
    printf ''
}

INSTALL_DIR="$(_detect_install_dir)"
REMOTE_MODE=0

if [ -z "$INSTALL_DIR" ]; then
    REMOTE_MODE=1
    INSTALL_DIR="/tmp/rm520n-setup-$$"
    mkdir -p "$INSTALL_DIR"
fi

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

# ── Remote mode: download all files ─────────────────────────────────────────
_download_files() {
    local base_url="$1"
    local dir="$2"

    mkdir -p "$dir/config" "$dir/lib" "$dir/modules" "$dir/optional"

    printf 'Downloading installer files from GitHub...\n'

    for f in \
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
        if ! wget -qO "${dir}/${f}" "${base_url}/${f}"; then
            printf 'ERROR: Failed to download %s\n' "$f" >&2
            exit 1
        fi
        printf '  Downloaded: %s\n' "$f"
    done
    printf 'Download complete.\n\n'
}

# ── Bootstrap ────────────────────────────────────────────────────────────────

# Load defaults first so REPO_URL is available
. "${INSTALL_DIR}/config/defaults.conf" 2>/dev/null || {
    if [ "$REMOTE_MODE" = "1" ]; then
        # Minimal defaults for download phase
        REPO_URL="https://raw.githubusercontent.com/pajus1337/gl-mt6000-rm520n-auto-config/main"
        _download_files "$REPO_URL" "$INSTALL_DIR"
        . "${INSTALL_DIR}/config/defaults.conf"
    else
        printf 'ERROR: config/defaults.conf not found.\n' >&2
        exit 1
    fi
}

if [ "$REMOTE_MODE" = "1" ]; then
    _download_files "$REPO_URL" "$INSTALL_DIR"
    . "${INSTALL_DIR}/config/defaults.conf"
fi

# Override defaults with user config if it exists
[ -f "${INSTALL_DIR}/config/user.conf" ] && . "${INSTALL_DIR}/config/user.conf"

# Load libraries
. "${INSTALL_DIR}/lib/common.sh"
. "${INSTALL_DIR}/lib/openwrt.sh"
. "${INSTALL_DIR}/lib/modem.sh"

# Load modules
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
