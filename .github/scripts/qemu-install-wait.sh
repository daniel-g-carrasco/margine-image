#!/usr/bin/env bash
# Drive a headless automated Margine install in UEFI QEMU and wait for it to
# finish (forum 12247 install gate). Boots the ISO's extracted kernel+initrd
# with `margine.autoinstall` injected (fires the dormant autoinstall service)
# while -cdrom serves the live squashfs and a blank target disk receives the
# install. With -no-reboot the post-install `reboot` halts the VM, which is
# our success signal; verify-install-disk.sh then inspects the disk offline.
#
#   usage (root): qemu-install-wait.sh --cdrom ISO --disk QCOW \
#       --kernel vmlinuz --initrd initrd.img --log LOG --timeout SEC
set -euo pipefail

CDROM="" DISK="" KERNEL="" INITRD="" LOG="install-serial.log" TIMEOUT=1800
while [[ $# -gt 0 ]]; do
  case "$1" in
    --cdrom) CDROM="$2"; shift 2 ;;
    --disk) DISK="$2"; shift 2 ;;
    --kernel) KERNEL="$2"; shift 2 ;;
    --initrd) INITRD="$2"; shift 2 ;;
    --log) LOG="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
[[ -f "$CDROM" && -f "$DISK" && -f "$KERNEL" && -f "$INITRD" ]] \
  || { echo "usage: --cdrom --disk --kernel --initrd required (files must exist)" >&2; exit 2; }

OVMF_CODE=""
for c in /usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/OVMF/OVMF_CODE.fd; do
  [[ -f "$c" ]] && OVMF_CODE="$c" && break
done
OVMF_VARS_SRC=""
for v in /usr/share/OVMF/OVMF_VARS_4M.fd /usr/share/OVMF/OVMF_VARS.fd; do
  [[ -f "$v" ]] && OVMF_VARS_SRC="$v" && break
done
[[ -n "$OVMF_CODE" && -n "$OVMF_VARS_SRC" ]] || { echo "✗ OVMF not found"; ls -la /usr/share/OVMF/; exit 1; }
cp "$OVMF_VARS_SRC" ovmf_vars_install.fd; chmod 0644 ovmf_vars_install.fd

# margine.autoinstall fires the dormant service; systemd.unit=multi-user.target
# skips GNOME so anaconda --cmdline runs unobstructed; console=ttyS0 for the
# log; the rd.live args + -cdrom provide the live root.
APPEND="root=live:CDLABEL=Margine-Live rd.live.image rd.live.overlay.size=4096 enforcing=0 margine.autoinstall systemd.unit=multi-user.target console=tty0 console=ttyS0,115200n8 systemd.show_status=1"

rm -f qemu-install.pid "$LOG"
qemu-system-x86_64 \
  -enable-kvm -m 6144 -smp 4 -machine q35 \
  -drive "if=pflash,format=raw,readonly=on,file=$OVMF_CODE" \
  -drive if=pflash,format=raw,file=ovmf_vars_install.fd \
  -cdrom "$CDROM" \
  -drive "file=$DISK,format=qcow2,if=virtio" \
  -kernel "$KERNEL" -initrd "$INITRD" -append "$APPEND" \
  -netdev user,id=n0 -device virtio-net-pci,netdev=n0 \
  -serial "file:$LOG" -display none -no-reboot \
  -daemonize -pidfile qemu-install.pid
QPID="$(cat qemu-install.pid)"
echo "install QEMU PID: $QPID (timeout ${TIMEOUT}s)"
cleanup() { kill "$QPID" 2>/dev/null || true; sleep 2; kill -9 "$QPID" 2>/dev/null || true; chmod a+r "$LOG" 2>/dev/null || true; }
trap cleanup EXIT

FAIL_RE='MARGINE-BAKE-FAIL|anaconda: traceback|Pane is dead|Aborting|installation failed|Kickstart error|Could not find a kickstart'
for (( i = 1; i <= TIMEOUT; i++ )); do
  if [[ -f "$LOG" ]] && grep -qE "$FAIL_RE" "$LOG"; then
    echo "✗ install failure marker on serial:"; grep -E "$FAIL_RE" "$LOG" | head -5
    tail -100 "$LOG"; exit 1
  fi
  if ! kill -0 "$QPID" 2>/dev/null; then
    echo "✓ QEMU exited at ~${i}s (post-install reboot under -no-reboot) — install finished"
    grep -E 'MARGINE-BAKE-OK|MARGINE-BAKE-FAIL|Performing post|reboot' "$LOG" | tail -10 || true
    exit 0
  fi
  sleep 1
done
echo "✗ install did NOT finish within ${TIMEOUT}s"; tail -150 "$LOG"; exit 1
