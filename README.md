# GL-MT6000 + RM520NGL Auto-Config

> One-command installer that automatically configures a **Quectel RM520NGL 5G modem** on a **GL-iNet GL-MT6000 (Flint 2)** router running vanilla **OpenWrt 25.12**.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![OpenWrt](https://img.shields.io/badge/OpenWrt-25.12-blue.svg)](https://openwrt.org)

---

## Overview

This project solves the tedious manual process of setting up a 5G modem on a fresh OpenWrt installation. It handles everything — package installation, modem AT configuration, WAN interface setup, firewall rules, and post-install verification — in a single modular script.

**Hardware this was built and tested on:**

| Component | Model |
|---|---|
| Router | GL-iNet GL-MT6000 (Flint 2) |
| Modem | Quectel RM520NGL (5G Sub-6GHz) |
| Carrier board | Waveshare 5G M.2 to Gigabit Ethernet Converter |

---

## How It Works

The Waveshare carrier board exposes two interfaces to the router:

```
┌─────────────────────────────────────┐
│         RM520NGL modem              │
│  5G radio ──► Qualcomm X62 chipset  │
│                   │                 │
│              PCIe │                 │
│                   ▼                 │
│              RTL8125 chip           │
└───────┬───────────────────┬─────────┘
        │ GbE cable         │ USB 3.1 cable
        ▼                   ▼
  [GL-MT6000 WAN]    [GL-MT6000 USB]
  Data path          Management path
  (192.168.225.x)    (AT commands / QMI)
```

- **GbE port** → router WAN — modem acts as DHCP server (`192.168.225.1`), router gets an IP in `192.168.225.x/22` range. This is your internet data path.
- **USB 3.1 port** → router USB — exposes AT command ports (`/dev/ttyUSBx`) and QMI device (`/dev/cdc-wdm0`) for modem monitoring in LuCI.

Your devices on the LAN still connect as usual through `192.168.1.1` — nothing changes for them.

---

## Requirements

**Router:**
- GL-iNet GL-MT6000 running **OpenWrt 25.12** (vanilla, not GL stock firmware)
- Internet access during installation (for package download)
- SSH access

**Hardware connections:**
- Waveshare GbE port → router WAN/LAN ethernet port
- Waveshare USB 3.1 port → router USB port

**Modem firmware:**
- `RM520NGLAAR03A01M4G` or later (tested)
- `RM520NGLAAR05A01M4G`+ recommended for full PCIe/GbE throughput

---

## Quick Install

**Option A — One-liner (curl):**
```sh
curl -fsSL https://raw.githubusercontent.com/pajus1337/gl-mt6000-rm520n-auto-config/master/install.sh | sh
```

**Option B — Clone and run locally:**
```sh
cd /root
git clone https://github.com/pajus1337/gl-mt6000-rm520n-auto-config.git
cd gl-mt6000-rm520n-auto-config
./install.sh
```

The installer will guide you through the process interactively.

---

## What the Installer Does

The installation is split into independent modules that run in sequence:

| Module | Description |
|---|---|
| `01_preflight` | Validates OpenWrt version, free space, USB modem presence, internet |
| `02_packages` | Installs required packages via `apk` |
| `03_usb_setup` | Detects AT port, configures modem PCIe/GbE mode, sets APN |
| `04_wan_eth` | Configures WAN interface (DHCP on GbE port from modem) |
| `05_luci_modem` | Sets up QMI management interface + signal hotplug logger |
| `06_firewall` | Configures fw4/nftables: WAN zone, masquerade, MSS clamping |
| `07_verify` | Health checks: ping, DNS, signal info, interface status |

**Installed packages:**

```
kmod-usb-serial-option   — AT command serial ports (ttyUSBx)
kmod-usb-net-qmi-wwan    — QMI WWAN kernel driver
kmod-usb-wdm             — USB device management (cdc-wdm)
uqmi                     — QMI userspace tools
luci-proto-qmi           — LuCI QMI protocol integration
```

---

## Options

```
./install.sh [options]

  --dry-run    Show what would be done without making changes
  --debug      Verbose output including AT command I/O
  --usb-only   USB-only mode — data + management via USB (TODO)
  --help       Show help
```

---

## Configuration

Default values are in `config/defaults.conf`. Override any setting by creating `config/user.conf`:

```sh
# config/user.conf
APN="your.apn.here"
WAN_IFACE="wan"
MODEM_REBOOT_WAIT="25"
```

The APN is also asked interactively during installation if not pre-configured.

---

## After Installation

Once complete, the installer reports:

```
── Modem Signal Info ──
  Technology : LTE
  RSSI       : -72 dBm
  RSRP       : -111 dBm
  SINR       : -3 dB
  RSRQ       : -19 dB

── Verification Summary ──
  Passed: 8

[OK] All checks passed. Setup complete!
```

**LuCI:** Go to Network → Interfaces. You will see the `wan` interface with a `192.168.225.x` address and a `wwan_mgmt` QMI interface for modem status.

**For full modem management** (signal dashboard, band locking, APN control), install the companion LuCI app:
👉 [luci-app-rm520n](https://github.com/pajus1337/luci-app-rm520n)

---

## Project Structure

```
gl-mt6000-rm520n-auto-config/
├── install.sh          Main entry point
├── config/
│   └── defaults.conf   Default configuration values
├── lib/
│   ├── common.sh       Logging, UI helpers
│   ├── openwrt.sh      OpenWrt/apk helpers, UCI wrappers
│   └── modem.sh        AT commands, modem detection, PCIe setup
├── modules/
│   ├── 01_preflight.sh
│   ├── 02_packages.sh
│   ├── 03_usb_setup.sh
│   ├── 04_wan_eth.sh
│   ├── 05_luci_modem.sh
│   ├── 06_firewall.sh
│   └── 07_verify.sh
└── optional/
    └── usb_only_mode.sh   USB-only mode (TODO)
```

---

## Troubleshooting

**Modem not detected (`2c7c:0801` missing):**
```sh
cat /sys/bus/usb/devices/*/idVendor
# Check that the USB cable from Waveshare is connected to the router USB port
```

**No AT command response:**
```sh
# Test manually
exec 3<>/dev/ttyUSB2; dd <&3 of=/tmp/at_test bs=1 count=128 2>/dev/null & \
dpid=$!; printf 'AT\r\n' >&3; sleep 2; kill $dpid; wait $dpid; exec 3>&-; cat /tmp/at_test
```

**Low speed on GbE path:**
Firmware `RM520NGLAAR03A01M4G` (A03) may not activate the full PCIe→RTL8125 path.
Update to A05+ firmware for best throughput.

**Full install log:**
```sh
cat /tmp/rm520n-install.log
```

---

## Compatibility

| Component | Tested version |
|---|---|
| OpenWrt | 25.12.3 |
| Kernel | 6.12.85 |
| BusyBox | 1.37.0 |
| Modem firmware | RM520NGLAAR03A01M4G |

> **Note:** This installer uses `apk` (not `opkg`) and requires OpenWrt **25.12 or later**.
> It will not work on 24.10 or older releases.

---

## Related Projects

- [luci-app-rm520n](https://github.com/pajus1337/luci-app-rm520n) — LuCI modem management panel (signal, band locking, APN, diagnostics)

---

## License

[MIT](LICENSE) © 2026 pajus1337
