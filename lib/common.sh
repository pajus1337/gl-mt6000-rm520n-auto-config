#!/bin/sh
# Shared logging, UI helpers, and utility functions.
# Source this file; do not execute directly.

# Terminal colors (disabled if not a TTY)
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    CYAN='\033[1;36m'
    BOLD='\033[1m'
    RESET='\033[0m'
else
    RED='' GREEN='' YELLOW='' CYAN='' BOLD='' RESET=''
fi

LOG_FILE="/tmp/rm520n-install.log"

_log_raw() {
    printf '%s\n' "$1" >> "$LOG_FILE"
}

log_info() {
    printf "${GREEN}[INFO]${RESET}  %s\n" "$1"
    _log_raw "[INFO]  $1"
}

log_warn() {
    printf "${YELLOW}[WARN]${RESET}  %s\n" "$1"
    _log_raw "[WARN]  $1"
}

log_error() {
    printf "${RED}[ERROR]${RESET} %s\n" "$1" >&2
    _log_raw "[ERROR] $1"
}

log_step() {
    printf "\n${BOLD}${CYAN}==> %s${RESET}\n" "$1"
    _log_raw "==> $1"
}

log_ok() {
    printf "${GREEN}[OK]${RESET}    %s\n" "$1"
    _log_raw "[OK]    $1"
}

log_debug() {
    [ "${DEBUG:-0}" = "1" ] || return 0
    printf "${CYAN}[DBG]${RESET}   %s\n" "$1"
    _log_raw "[DBG]   $1"
}

# die MESSAGE [EXIT_CODE]
die() {
    log_error "$1"
    log_error "See full log at: $LOG_FILE"
    exit "${2:-1}"
}

# confirm PROMPT — returns 0 on yes, 1 on no
confirm() {
    local prompt="$1"
    local answer
    printf "${YELLOW}%s [y/N]: ${RESET}" "$prompt"
    read -r answer
    case "$answer" in
        [Yy]|[Yy][Ee][Ss]) return 0 ;;
        *) return 1 ;;
    esac
}

# require_root — exits if not running as root
require_root() {
    [ "$(id -u)" -eq 0 ] || die "This script must be run as root."
}

# wait_with_spinner SECONDS MESSAGE
wait_with_spinner() {
    local secs="$1"
    local msg="$2"
    local i=0
    local spinners='|/-\'
    printf "%s " "$msg"
    while [ "$i" -lt "$secs" ]; do
        local pos=$(( i % 4 ))
        printf '\b%s' "$(printf '%s' "$spinners" | cut -c$(( pos + 1 )))"
        sleep 1
        i=$(( i + 1 ))
    done
    printf '\b \n'
}

# print_banner — show install header
print_banner() {
    printf "\n"
    printf "${BOLD}${CYAN}╔══════════════════════════════════════════════════╗${RESET}\n"
    printf "${BOLD}${CYAN}║  GL-MT6000 + RM520NGL Auto-Config Installer      ║${RESET}\n"
    printf "${BOLD}${CYAN}║  OpenWrt 25.12 / Waveshare 5G M.2 GbE Board     ║${RESET}\n"
    printf "${BOLD}${CYAN}╚══════════════════════════════════════════════════╝${RESET}\n"
    printf "\n"
}

# section_header TITLE
section_header() {
    printf "\n${BOLD}── %s ──${RESET}\n" "$1"
}
