#!/bin/sh
# Module 02 — Package installation
# Installs all required OpenWrt packages via apk.

module_packages() {
    log_step "Module 02: Installing packages"

    log_info "Updating package index..."
    apk update -q || die "apk update failed. Check internet connectivity."

    log_info "Installing USB modem support packages..."
    for pkg in $PACKAGES_USB; do
        if apk_installed "$pkg"; then
            log_ok "Already installed: $pkg"
        else
            log_info "Installing: $pkg"
            apk add "$pkg" || die "Failed to install $pkg"
            log_ok "Installed: $pkg"
        fi
    done

    # Verify all packages are present
    local missing=""
    for pkg in $PACKAGES_USB; do
        apk_installed "$pkg" || missing="$missing $pkg"
    done

    if [ -n "$missing" ]; then
        die "The following packages failed to install:$missing"
    fi

    log_ok "All packages installed successfully"
}
