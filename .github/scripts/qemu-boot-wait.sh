#!/usr/bin/env bash
# Boot an image in UEFI QEMU and watch its serial console for healthy /
# failure markers. ONE implementation for the two CI boot tests that
# used to carry diverged copies (smoke-boot.yml qcow2 gate, build-disk
# ISO gate) — including the same bug: `kill -9 $!` killed the sudo
# wrapper, not qemu, so an orphaned VM held the step open until the
# job timeout on every failure path (review P2.3). qemu now daemonizes
# with a pidfile and a trap kills the real process.
#
#   usage (run as root):
#     qemu-boot-wait.sh --disk img.qcow2 --log serial.log [--gui-watch]
#     qemu-boot-wait.sh --cdrom live.iso --log iso-serial.log \
#         --ok-regex 'RE' --fail-regex 'RE' --timeout 900
#
# Outputs (when $GITHUB_OUTPUT is set): passed=true|false and, with
# --gui-watch, gui=pass|fail|timeout|none (Layer C verdict, warn-only).
set -euo pipefail

MODE="" IMAGE="" LOG="serial.log" TIMEOUT=1800 GUI_WATCH=0
OK_REGEX='Started.*gdm\.service|Reached target graphical\.target|margine login:'
FAIL_REGEX=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --disk)   MODE=disk;  IMAGE="$2"; shift 2 ;;
    --cdrom)  MODE=cdrom; IMAGE="$2"; shift 2 ;;
    --log)    LOG="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    --ok-regex) OK_REGEX="$2"; shift 2 ;;
    --fail-regex) FAIL_REGEX="$2"; shift 2 ;;
    --gui-watch) GUI_WATCH=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$MODE" && -f "$IMAGE" ]] || { echo "usage: --disk|--cdrom <image> required" >&2; exit 2; }

emit() { [[ -n "${GITHUB_OUTPUT:-}" ]] && echo "$1" >> "$GITHUB_OUTPUT" || true; }

# OVMF firmware discovery — explicit candidates, modern 4M names first
# (Ubuntu 24.04 renamed the files; Secure Boot variants are skipped on
# purpose: SB is exercised on the hardware lab VM, not here).
OVMF_CODE=""
for c in /usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/OVMF/OVMF_CODE.fd; do
  [[ -f "$c" ]] && OVMF_CODE="$c" && break
done
OVMF_VARS_SRC=""
for v in /usr/share/OVMF/OVMF_VARS_4M.fd /usr/share/OVMF/OVMF_VARS.fd; do
  [[ -f "$v" ]] && OVMF_VARS_SRC="$v" && break
done
if [[ -z "$OVMF_CODE" || -z "$OVMF_VARS_SRC" ]]; then
  echo "✗ OVMF firmware not found. Files present:"; ls -la /usr/share/OVMF/; exit 1
fi
cp "$OVMF_VARS_SRC" ovmf_vars.fd
chmod 0644 ovmf_vars.fd
echo "Using OVMF_CODE=$OVMF_CODE OVMF_VARS=$OVMF_VARS_SRC"

MEDIA_ARGS=()
if [[ "$MODE" == "disk" ]]; then
  MEDIA_ARGS=(-drive "file=$IMAGE,format=qcow2,if=virtio")
else
  MEDIA_ARGS=(-cdrom "$IMAGE")
fi

rm -f qemu.pid "$LOG"
qemu-system-x86_64 \
  -enable-kvm \
  -m 4096 -smp 4 \
  -machine q35 \
  -drive "if=pflash,format=raw,readonly=on,file=$OVMF_CODE" \
  -drive if=pflash,format=raw,file=ovmf_vars.fd \
  "${MEDIA_ARGS[@]}" \
  -netdev user,id=n0 -device virtio-net-pci,netdev=n0 \
  -serial "file:$LOG" \
  -display none \
  -no-reboot \
  -daemonize -pidfile qemu.pid
QPID="$(cat qemu.pid)"
echo "QEMU PID: $QPID"
kill_qemu() {
  kill "$QPID" 2>/dev/null || true
  sleep 2
  kill -9 "$QPID" 2>/dev/null || true
}
trap kill_qemu EXIT

BOOT_OK=""
GUI_RESULT=""
GUI_DEADLINE=0
for (( i = 1; i <= TIMEOUT; i++ )); do
  if [[ -z "$BOOT_OK" && -f "$LOG" ]] && grep -qE "$OK_REGEX" "$LOG"; then
    echo "✓ Boot reached usable state at second $i"
    emit "passed=true"
    BOOT_OK=$i
    if (( GUI_WATCH )); then
      # Layer C window: the probe sleeps 150s after graphical, first
      # boot is I/O-heavy — allow 8 more minutes.
      GUI_DEADLINE=$((i + 480))
    else
      break
    fi
  fi
  if [[ -n "$FAIL_REGEX" && -f "$LOG" ]] && grep -qE "$FAIL_REGEX" "$LOG"; then
    echo "✗ Failure marker on serial console:"
    grep -E "$FAIL_REGEX" "$LOG" | head -3
    tail -120 "$LOG"
    emit "passed=false"
    exit 1
  fi
  if [[ -n "$BOOT_OK" ]] && (( GUI_WATCH )); then
    if grep -q "MARGINE-GUI-SMOKE: PASS" "$LOG"; then GUI_RESULT=pass; break; fi
    if grep -q "MARGINE-GUI-SMOKE: FAIL" "$LOG"; then GUI_RESULT=fail; break; fi
    if (( i > GUI_DEADLINE )); then GUI_RESULT=timeout; break; fi
  fi
  sleep 1
done

if [[ -n "$BOOT_OK" ]]; then
  if (( GUI_WATCH )); then
    # ---- Layer C verdict — WARN-ONLY until proven stable ----
    # (flip the warning paths to a hard fail after two green runs)
    grep -E "MARGINE-GUI-SMOKE" "$LOG" || true
    emit "gui=${GUI_RESULT:-none}"
    case "$GUI_RESULT" in
      pass) echo "✓ Layer C GUI probe: PASS" ;;
      fail) echo "::warning::Layer C GUI probe FAILED — graphical session unhealthy (extensions/coredump). See serial log artifact. This will become gating." ;;
      *)    echo "::warning::Layer C GUI probe gave no verdict (injection skipped or probe stuck) — see inject step + serial log." ;;
    esac
  fi
  exit 0
fi

echo "✗ Boot did NOT reach a usable state within ${TIMEOUT}s"
echo "Last 200 lines of serial log:"
tail -200 "$LOG"
echo
echo "=== systemd target progress (Reached vs Failed) ==="
grep -E "Reached target|Failed to start|systemd\[1\]: Starting" "$LOG" | tail -40 || true
echo
echo "=== units still starting (likely culprits) ==="
grep -oE "[a-z0-9_-]+\.service" "$LOG" | sort | uniq -c | sort -rn | head -10 || true
emit "passed=false"
exit 1
