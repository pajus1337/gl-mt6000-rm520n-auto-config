#!/bin/sh
# [TODO] Optional mode: USB-only (data + communication via USB, no GbE)
#
# This module configures the RM520NGL to use QMI over USB for both
# data and management — no GbE port required.
#
# Use case: simpler setups where the Waveshare GbE port is not used,
# or USB tethering is preferred.
#
# Status: NOT YET IMPLEMENTED
# See: https://github.com/pajus1337/gl-mt6000-rm520n-auto-config

module_usb_only_mode() {
    log_warn "[TODO] USB-only mode is not yet implemented."
    log_warn "Planned steps:"
    log_warn "  1. Set AT+QCFG=\"usbnet\",0  (QMI mode)"
    log_warn "  2. Reboot modem"
    log_warn "  3. Install QMI packages (same as module 02)"
    log_warn "  4. Configure WAN interface with proto=qmi on /dev/cdc-wdm0"
    log_warn "  5. Configure firewall"
    log_warn ""
    log_warn "To enable: run modules 01, 02 (packages), then implement this module."
    return 1
}
