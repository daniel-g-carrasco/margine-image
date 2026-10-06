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

MODE="" IMAGE="" LOG="serial.log" TIMEOUT=1800 GUI_WATCH=0 MEM=4096
SB_VARS="" TPM=0 SEC_WATCH=0 ALLOW_REBOOT=0
KERNEL="" INITRD="" APPEND=""
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
    --mem) MEM="$2"; shift 2 ;;
    --kernel) KERNEL="$2"; shift 2 ;;
    --initrd) INITRD="$2"; shift 2 ;;
    --append) APPEND="$2"; shift 2 ;;
    --gui-watch) GUI_WATCH=1; shift ;;
    # Secure Boot enforcing with the given variable store (Microsoft keys
    # plus the Margine key in MokList, prepared by the caller).
    --secure-boot) SB_VARS="$2"; shift 2 ;;
    --tpm) TPM=1; shift ;;
    # Gate on the security probe's MARGINE-SEC-SMOKE verdict.
    --sec-watch) SEC_WATCH=1; shift ;;
    # Let the guest reboot instead of exiting QEMU on reset. Needed with a
    # TPM: on a disk with no boot entry yet, shim runs fallback, which
    # creates the entry and then RESETS when a TPM is present (so the PCRs
    # are measured on a normal boot path); without a TPM it starts the OS
    # directly, which is why plain smoke boots never showed it. The entry
    # lands in this VM's variable store, so the second boot goes shim ->
    # GRUB -> kernel like a real first boot. A panic loop still ends in
    # the overall timeout.
    --allow-reboot) ALLOW_REBOOT=1; shift ;;
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
MACHINE=q35
SB_ARGS=()
if [[ -n "$SB_VARS" ]]; then
  # Secure Boot (2026-10-07): until now SB was "exercised on the hardware
  # lab VM", i.e. never in CI, and a kernel signature no device could boot
  # would have been promoted. SB firmware needs SMM and a secure flash.
  # kernel-irqchip=split: with the default in-kernel irqchip the guest
  # stalled at the GRUB countdown under SB firmware on an AMD host
  # (local harness, 2026-10-04).
  OVMF_CODE=""
  for c in /usr/share/OVMF/OVMF_CODE_4M.secboot.fd /usr/share/OVMF/OVMF_CODE.secboot.fd; do
    [[ -f "$c" ]] && OVMF_CODE="$c" && break
  done
  [[ -n "$OVMF_CODE" && -f "$SB_VARS" ]] || { echo "✗ Secure Boot firmware or vars missing"; ls -la /usr/share/OVMF/; exit 1; }
  cp "$SB_VARS" ovmf_vars.fd
  MACHINE="q35,smm=on,kernel-irqchip=split"
  SB_ARGS=(-global "driver=cfi.pflash01,property=secure,value=on")
fi
chmod 0644 ovmf_vars.fd
echo "Using OVMF_CODE=$OVMF_CODE vars=${SB_VARS:-$OVMF_VARS_SRC}"
TPM_ARGS=()
if (( TPM )); then
  TPMDIR="$(mktemp -d)"
  swtpm socket --tpm2 --terminate --tpmstate dir="$TPMDIR" --ctrl type=unixio,path="$TPMDIR/sock" --daemon \
    || { echo "✗ swtpm failed to start"; exit 1; }
  TPM_ARGS=(-chardev "socket,id=chrtpm,path=$TPMDIR/sock" -tpmdev "emulator,id=tpm0,chardev=chrtpm" -device "tpm-tis,tpmdev=tpm0")
fi

MEDIA_ARGS=()
if [[ "$MODE" == "disk" ]]; then
  MEDIA_ARGS=(-drive "file=$IMAGE,format=qcow2,if=virtio")
else
  MEDIA_ARGS=(-cdrom "$IMAGE")
fi

# Direct-kernel boot (CI serial injection). The shipped live ISO no longer
# bakes console=ttyS0 (it stalls phantom-UART mini-PCs — see
# live-env/src/iso.yaml). To keep the ISO boot-test observable over serial,
# the caller extracts the ISO's kernel+initrd and passes them here with a
# custom --append that adds console=ttyS0; QEMU/OVMF boots them directly
# while the -cdrom still provides the live squashfs (root=live:CDLABEL=...).
DIRECT_ARGS=()
if [[ -n "$KERNEL" ]]; then
  DIRECT_ARGS=(-kernel "$KERNEL" -initrd "$INITRD" -append "$APPEND")
fi

REBOOT_ARGS=(-no-reboot)
if (( ALLOW_REBOOT )); then REBOOT_ARGS=(); fi
rm -f qemu.pid "$LOG"
qemu-system-x86_64 \
  -enable-kvm \
  -m "$MEM" -smp 4 \
  -machine "$MACHINE" \
  "${SB_ARGS[@]}" \
  "${TPM_ARGS[@]}" \
  -drive "if=pflash,format=raw,readonly=on,file=$OVMF_CODE" \
  -drive if=pflash,format=raw,file=ovmf_vars.fd \
  "${MEDIA_ARGS[@]}" \
  "${DIRECT_ARGS[@]}" \
  -netdev user,id=n0 -device virtio-net-pci,netdev=n0 \
  -serial "file:$LOG" \
  -display none \
  "${REBOOT_ARGS[@]}" \
  -daemonize -pidfile qemu.pid
QPID="$(cat qemu.pid)"
echo "QEMU PID: $QPID"
cleanup() {
  kill "$QPID" 2>/dev/null || true
  sleep 2
  kill -9 "$QPID" 2>/dev/null || true
  # The script runs as root, so qemu writes the serial log root-owned;
  # the (non-root) upload-artifact step then EACCESed on it and failed
  # an otherwise fully green run (27443157244 — the one where Layer C
  # produced its first real PASS). Hand the log back to the runner.
  chmod a+r "$LOG" 2>/dev/null || true
}
trap cleanup EXIT

BOOT_OK=""
SEC_RESULT=""
GUI_RESULT=""
GAMING_RESULT=""
GUI_DEADLINE=0
for (( i = 1; i <= TIMEOUT; i++ )); do
  if [[ -z "$BOOT_OK" && -f "$LOG" ]] && grep -qE "$OK_REGEX" "$LOG"; then
    echo "✓ Boot reached usable state at second $i"
    emit "passed=true"
    BOOT_OK=$i
    if (( GUI_WATCH )); then
      # Layer C window for BOTH verdicts. Worst case from graphical:
      # the unit's ExecStartPre sleep (~150s) + the gnome-shell wait
      # (up to 300s) + the bounded extension poll (~60s) + branding,
      # while the gaming dry-run (≤240s + rpm-ostreed wait) runs in the
      # background. First boot is I/O-heavy, so allow 15 minutes; the
      # outer --timeout (1800) and the 40-min job timeout still bound it.
      GUI_DEADLINE=$((i + 900))
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
    # Two independent warn-only verdicts share one window: the Layer C
    # GUI probe and the gaming-native dry-run. Break only once BOTH are
    # decided (or the deadline passes) so neither masks the other.
    [[ -z "$GUI_RESULT" ]] && grep -q "MARGINE-GUI-SMOKE: PASS" "$LOG" && GUI_RESULT=pass
    [[ -z "$GUI_RESULT" ]] && grep -q "MARGINE-GUI-SMOKE: FAIL" "$LOG" && GUI_RESULT=fail
    [[ -z "$GAMING_RESULT" ]] && grep -q "MARGINE-GAMING-NATIVE: PASS" "$LOG" && GAMING_RESULT=pass
    [[ -z "$GAMING_RESULT" ]] && grep -q "MARGINE-GAMING-NATIVE: FAIL" "$LOG" && GAMING_RESULT=fail
    [[ -z "$GAMING_RESULT" ]] && grep -q "MARGINE-GAMING-NATIVE: SKIP" "$LOG" && GAMING_RESULT=skip
    if (( SEC_WATCH )); then
      [[ -z "$SEC_RESULT" ]] && grep -q "MARGINE-SEC-SMOKE: PASS" "$LOG" && SEC_RESULT=pass
      [[ -z "$SEC_RESULT" ]] && grep -q "MARGINE-SEC-SMOKE: FAIL" "$LOG" && SEC_RESULT=fail
    else
      SEC_RESULT=off
    fi
    if [[ -n "$GUI_RESULT" && -n "$GAMING_RESULT" && -n "$SEC_RESULT" ]]; then break; fi
    if (( i > GUI_DEADLINE )); then
      [[ -z "$GUI_RESULT" ]] && GUI_RESULT=timeout
      [[ -z "$GAMING_RESULT" ]] && GAMING_RESULT=timeout
      [[ -z "$SEC_RESULT" ]] && SEC_RESULT=timeout
      break
    fi
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

    # ---- Security probe verdict: GATING, including "no verdict" ----
    # (2026-10-07) A security gate that passes when its probe never ran
    # protects nothing, so timeout and missing verdicts fail too.
    if (( SEC_WATCH )); then
      grep -E "MARGINE-SEC" "$LOG" | sed 's/^.*MARGINE-SEC/MARGINE-SEC/' | sort -u || true
      emit "sec=${SEC_RESULT:-none}"
      if [[ "$SEC_RESULT" != pass ]]; then
        echo "::error::Security smoke probe: ${SEC_RESULT:-no verdict}. GATING: not promoting. Each MARGINE-SEC FAIL line above names the broken promise."
        emit "passed=false"
        exit 1
      fi
      echo "✓ Security smoke probe: PASS"
    fi

    # ---- Gaming-native dry-run verdict — GATING on FAIL ----
    # (2026-09-02, after the RetroArch/retroarch depsolve broke
    # updates for gaming-native users while this was warn-only: "questo
    # tipo di cose NON deve ricapitare". A FAIL now blocks promotion;
    # skip/timeout stay warnings so a stuck probe cannot wedge releases.)
    grep -E "MARGINE-GAMING-NATIVE" "$LOG" || true
    emit "gaming=${GAMING_RESULT:-none}"
    case "$GAMING_RESULT" in
      pass) echo "✓ Gaming-native layer resolves (rpm-ostree dry-run)" ;;
      fail)
        echo "::error::Gaming-native layer does NOT resolve — every gaming-native rpm-ostree upgrade (and ujust margine-gaming-native) would fail to depsolve. GATING: not promoting. See serial log artifact."
        emit "passed=false"
        exit 1 ;;
      skip) echo "::warning::Gaming-native check skipped (package list missing/empty in image)." ;;
      *)    echo "::warning::Gaming-native check gave no verdict (probe skipped or stuck) — see inject step + serial log." ;;
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
