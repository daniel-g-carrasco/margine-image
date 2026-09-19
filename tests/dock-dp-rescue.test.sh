#!/usr/bin/env bash
# Gate tests for /usr/libexec/margine/dock-dp-rescue against a fake sysfs.
# No hardware, no root: the helper reads everything under
# MARGINE_DOCK_RESCUE_ROOT and the slow or privileged commands are stubbed.
set -euo pipefail
HELPER="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/build_files/system_files/usr/libexec/margine/dock-dp-rescue"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fails=0

mkdir -p "$T/bin"
printf '#!/bin/sh\nshift 2 2>/dev/null\necho "$*" >> "$LOGFILE"\n' > "$T/bin/logger"
printf '#!/bin/sh\nexit 0\n' > "$T/bin/sleep"
printf '#!/bin/sh\ncat "$LSUSB_OUT" 2>/dev/null\n' > "$T/bin/lsusb"
chmod +x "$T/bin/"*

# new_root <name>: a Framework 13 AMD with no DisplayPort connected
new_root() {
  R="$T/$1"; rm -rf "$R"
  mkdir -p "$R/sys/class/dmi/id" "$R/sys/class/drm/card1-DP-1" "$R/sys/class/typec" \
           "$R/sys/bus/usb/devices" "$R/sys/bus/platform/drivers/ucsi_acpi" "$R/run" "$R/etc"
  echo "Framework" > "$R/sys/class/dmi/id/sys_vendor"
  echo "Laptop 13 (AMD Ryzen 7040Series)" > "$R/sys/class/dmi/id/product_name"
  echo "disconnected" > "$R/sys/class/drm/card1-DP-1/status"
  : > "$R/sys/bus/platform/drivers/ucsi_acpi/unbind"
  : > "$R/sys/bus/platform/drivers/ucsi_acpi/bind"
  : > "$R/sys/bus/platform/drivers/ucsi_acpi/USBC000:00"
  # a root hub, like every machine has
  mkdir -p "$R/sys/bus/usb/devices/usb1"; echo 09 > "$R/sys/bus/usb/devices/usb1/bDeviceClass"; echo unknown > "$R/sys/bus/usb/devices/usb1/removable"
}
partner() { mkdir -p "$R/sys/class/typec/$1-partner"; echo "$2" > "$R/sys/class/typec/$1-partner/supports_usb_power_delivery"; }
hub()     { mkdir -p "$R/sys/bus/usb/devices/5-1"; echo 09 > "$R/sys/bus/usb/devices/5-1/bDeviceClass"; echo removable > "$R/sys/bus/usb/devices/5-1/removable"; }
billboard() {
  mkdir -p "$R/sys/bus/usb/devices/5-1.3/5-1.3:1.0"
  echo 00 > "$R/sys/bus/usb/devices/5-1.3/bDeviceClass"
  echo 14b0 > "$R/sys/bus/usb/devices/5-1.3/idVendor"; echo 016c > "$R/sys/bus/usb/devices/5-1.3/idProduct"
  echo 11 > "$R/sys/bus/usb/devices/5-1.3/5-1.3:1.0/bInterfaceClass"
  case "$1" in
    failed) printf '      Alternate Mode 0 : Alternate Mode configuration not attempted\n        wSVID[0]      0xFF01\n' > "$R/lsusb.out" ;;
    ok)     printf '      Alternate Mode 0 : Alternate Mode configuration successful\n        wSVID[0]      0xFF01\n' > "$R/lsusb.out" ;;
    mute)   : > "$R/lsusb.out" ;;
  esac
}

# run_case <name> <expect: rebind|quiet>
run_case() {
  local name="$1" expect="$2" err rebound
  : > "$R/log"
  err="$(MARGINE_DOCK_RESCUE_ROOT="$R" LOGFILE="$R/log" LSUSB_OUT="$R/lsusb.out" PATH="$T/bin:$PATH" bash "$HELPER" 2>&1 >/dev/null)" || true
  rebound=no; [ -s "$R/sys/bus/platform/drivers/ucsi_acpi/unbind" ] && rebound=yes
  local ok=1
  [ -z "$err" ] || { ok=0; echo "  stderr not empty: $err"; }
  case "$expect" in
    rebind) [ "$rebound" = yes ] || { ok=0; echo "  expected a rebind, none happened"; } ;;
    quiet)  [ "$rebound" = no ]  || { ok=0; echo "  REBIND on something that is not a failed dock"; } ;;
  esac
  if (( ok )); then echo "ok   $name"; else echo "FAIL $name"; fails=$((fails+1)); sed 's/^/  log: /' "$R/log"; fi
}

new_root a; run_case "no partner, no switch file: silent, no stderr" quiet
new_root b; partner port2 no;  run_case "empty HDMI expansion card (no PD): no rebind, no stderr" quiet
[ -s "$R/log" ] && { echo "FAIL non-PD partner must not even log"; fails=$((fails+1)); }
new_root c; partner port3 yes; run_case "charger (PD, no billboard, no hub) on a known-broken model: no rebind" quiet
new_root d; partner port0 yes; hub; billboard failed; run_case "dock whose billboard says DisplayPort failed: rebind" rebind
new_root e; partner port0 yes; hub; billboard ok;     run_case "dock whose billboard says DisplayPort is fine: left alone" quiet
new_root f; partner port0 yes; hub; billboard mute;   run_case "dock with an unreadable billboard on a known-broken model: fallback rebind" rebind
new_root g; partner port0 yes; hub;                   run_case "dock with no billboard at all on a known-broken model: fallback rebind" rebind
new_root h; partner port0 yes; hub; billboard failed; mkdir -p "$R/etc/margine"; echo off > "$R/etc/margine/dock-dp-rescue"; run_case "switch off beats a failed dock" quiet

if (( fails )); then echo "$fails case(s) failed"; exit 1; fi
echo "all dock-dp-rescue gate cases passed"
