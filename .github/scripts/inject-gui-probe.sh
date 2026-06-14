#!/usr/bin/env bash
# Layer C — offline-inject the GUI smoke probe into a freshly built
# qcow2 (smoke user + GDM autologin + the gui-probe oneshot + a
# permissive-SELinux karg for this throwaway boot).
#
#   usage: sudo .github/scripts/inject-gui-probe.sh <image.qcow2>
#
# Extracted from smoke-boot.yml's inline run: block (2026-06-12
# review, phase 3); the probe script and unit it installs live as real
# files under .github/smoke/ where shellcheck and reviewers see them.
#
# Exit 1 + a ::warning:: means "couldn't inject" — the caller runs
# this step with continue-on-error so an injection failure never
# blocks the Layer B gate.
#
# 2026-06-13 hardening (run 27471537033 recurring "no btrfs partition
# found"): the recurring failure was NOT a missing partition but
# MISSING partition NODES. `modprobe nbd max_part=16` is a silent
# no-op when nbd is already loaded (the ubuntu-24.04 runner / qemu
# tooling often loads it first without max_part), so the kernel kept
# max_part=0 and created only the whole-disk /dev/nbd0 with NO
# /dev/nbd0pN nodes. The detection glob then ran with nullglob OFF and
# fed the LITERAL string '/dev/nbd0p*' to blkid -> empty -> exit 1
# every run. Fixes here: force a fresh nbd load so max_part takes
# effect, re-read the partition table (partprobe/partx), actively WAIT
# for the nodes, and use nullglob + explicit existence checks so blkid
# can never run on a literal glob. Needs qemu-utils (qemu-nbd), parted
# (partprobe) and util-linux (partx) — see smoke-boot.yml install step.
set -euo pipefail
# An unexpanded /dev/nbd0p* glob must become an EMPTY list, never a
# literal arg passed to blkid/mount — this is half the root-cause bug.
shopt -s nullglob

QCOW="${1:?usage: inject-gui-probe.sh <image.qcow2>}"
SMOKE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../smoke" && pwd)"
[[ -f "$SMOKE_DIR/gui-probe.sh" && -f "$SMOKE_DIR/margine-gui-smoke.service" ]] \
  || { echo "::warning::Layer C: payloads missing under $SMOKE_DIR"; exit 1; }

NBD=/dev/nbd0

# Trap installed BEFORE qemu-nbd connects, covering BOTH mountpoints:
# a mid-injection failure must not disconnect nbd under a mounted rw
# boot partition (dirty journal on the very qcow2 Layer B then boots —
# review finding A5). `sync` before the disconnect flushes any pending
# writes; the umounts are retried since a busy umount would otherwise
# leave nbd detached under a live mount.
cleanup() {
  for mp in /mnt/smokeboot /mnt/smoke; do
    for _ in 1 2 3; do
      mountpoint -q "$mp" || break
      umount -R "$mp" 2>/dev/null && break
      sleep 1
    done
  done
  sync
  qemu-nbd --disconnect "$NBD" 2>/dev/null || true
}
trap cleanup EXIT

# --- Reliable nbd partition exposure -----------------------------------
# modprobe on an ALREADY-loaded module is a silent no-op and would keep
# whatever max_part the prior load used (default 0 -> no /dev/nbd0pN
# nodes ever appear). Disconnect any stale device from a previous step,
# then force a clean reload so max_part=16 actually applies. If the
# module is busy (can't be removed) we proceed and lean on
# partprobe/partx below to create the nodes.
qemu-nbd --disconnect "$NBD" 2>/dev/null || true
modprobe -r nbd 2>/dev/null || true
modprobe nbd max_part=16 || modprobe nbd || true

qemu-nbd --connect="$NBD" "$QCOW"

# NBD devices are not reliably made partitionable by the kernel at
# connect time; force a partition-table re-read so the kernel emits the
# p1/p2 uevents even if max_part was already 0 on a busy module.
partprobe "$NBD" 2>/dev/null || partx -a "$NBD" 2>/dev/null || true

# Actively WAIT for the first partition node — a one-shot `udevadm
# settle` only drains already-queued uevents and returns before the
# nodes the kernel never emitted could appear. Re-run partprobe a few
# times in case the connect was still settling.
for t in $(seq 1 30); do
  udevadm settle 2>/dev/null || true
  [[ -b "${NBD}p1" ]] && break
  (( t % 6 == 0 )) && { partprobe "$NBD" 2>/dev/null || partx -a "$NBD" 2>/dev/null || true; }
  sleep 1
done

# Explicit existence check — with nullglob a missing node yields an
# empty glob, so without this guard the script would fall through to a
# misleading "no btrfs partition" rather than the real diagnosis.
if ! compgen -G "${NBD}p*" >/dev/null; then
  echo "::warning::Layer C: no partition nodes under ${NBD} after reload+partprobe+30s wait"
  echo "DEBUG: nbd max_part=$(cat /sys/module/nbd/parameters/max_part 2>/dev/null || echo '?')"
  echo "DEBUG: lsblk ${NBD}:"; lsblk -o NAME,FSTYPE,SIZE,LABEL "$NBD" 2>/dev/null || true
  exit 1
fi

# Debuggability: show what the kernel actually exposed and the fstype
# of every node before we pick one.
echo "DEBUG: nbd max_part=$(cat /sys/module/nbd/parameters/max_part 2>/dev/null || echo '?')"
echo "DEBUG: partitions under ${NBD}:"
lsblk -o NAME,FSTYPE,SIZE,LABEL "$NBD" 2>/dev/null || true
for part in "${NBD}"p*; do
  echo "DEBUG:   $part -> $(blkid -s TYPE -o value "$part" 2>/dev/null || echo '?')"
done

# Root = the btrfs partition (BIB --rootfs btrfs).
ROOTPART=""
for part in "${NBD}"p*; do
  [[ "$(blkid -s TYPE -o value "$part" 2>/dev/null)" == "btrfs" ]] && ROOTPART="$part"
done
[[ -n "$ROOTPART" ]] || { echo "::warning::Layer C: no btrfs partition found, skipping injection"; exit 1; }
mkdir -p /mnt/smoke
mount "$ROOTPART" /mnt/smoke
R=/mnt/smoke
if [[ ! -d "$R/ostree" ]]; then
  # content may live in a 'root' subvolume
  umount /mnt/smoke
  mount -o subvol=root "$ROOTPART" /mnt/smoke
fi
[[ -d "$R/ostree" ]] || { echo "::warning::Layer C: ostree root not found on $ROOTPART"; exit 1; }

DEP=$(sh -c 'ls -d '"$R"'/ostree/deploy/*/deploy/*.0' | head -1)
ETC="$DEP/etc"
VAR=$(dirname "$(dirname "$DEP")")/var
[[ -d "$ETC" && -d "$VAR" ]] || { echo "::warning::Layer C: deployment etc/var not found"; exit 1; }
echo "deployment: $DEP"

# 1. Test user (uid/gid 1010), offline useradd. Password locked — GDM
#    autologin doesn't need one.
tee -a "$ETC/passwd" >/dev/null <<<'smoke:x:1010:1010:GUI smoke:/var/home/smoke:/bin/bash'
tee -a "$ETC/group"  >/dev/null <<<'smoke:x:1010:'
tee -a "$ETC/shadow" >/dev/null <<<'smoke:!:20000:0:99999:7:::'
tee -a "$ETC/gshadow" >/dev/null <<<'smoke:!::'
mkdir -p "$VAR/home/smoke/.config"
touch "$VAR/home/smoke/.config/gnome-initial-setup-done"
chown -R 1010:1010 "$VAR/home/smoke"

# 2. GDM autologin
tee "$ETC/gdm/custom.conf" >/dev/null <<'GDMEOF'
[daemon]
AutomaticLoginEnable=True
AutomaticLogin=smoke
GDMEOF

# 3. Probe script + oneshot unit. The wants-symlink MUST live in
#    graphical.target.wants: the unit is After=graphical.target, and
#    hooking it into multi-user.target.wants (as the first deployment
#    did) creates an ordering cycle that makes systemd skip the unit
#    entirely — the silent no-verdict failure of run 27438544775.
mkdir -p "$ETC/margine-smoke" "$ETC/systemd/system/graphical.target.wants"
install -m 0755 "$SMOKE_DIR/gui-probe.sh" "$ETC/margine-smoke/gui-probe.sh"
install -m 0644 "$SMOKE_DIR/margine-gui-smoke.service" "$ETC/systemd/system/margine-gui-smoke.service"
ln -sf ../margine-gui-smoke.service "$ETC/systemd/system/graphical.target.wants/margine-gui-smoke.service"

# 3b. User-smoke SOFT identity probe (warn-only, promotion never blocked).
#     Guarded: if its payloads are absent, warn and skip — the Layer C GUI
#     injection above is unaffected. The wants-symlink goes in
#     graphical.target.wants too (same After=graphical.target ordering rule;
#     multi-user.target.wants would re-create the ordering-cycle skip bug).
if [[ -f "$SMOKE_DIR/user-smoke-probe.sh" && -f "$SMOKE_DIR/margine-user-smoke.service" ]]; then
  install -m 0755 "$SMOKE_DIR/user-smoke-probe.sh" "$ETC/margine-smoke/user-smoke-probe.sh"
  install -m 0644 "$SMOKE_DIR/margine-user-smoke.service" "$ETC/systemd/system/margine-user-smoke.service"
  ln -sf ../margine-user-smoke.service "$ETC/systemd/system/graphical.target.wants/margine-user-smoke.service"
  echo "Layer C: user-smoke soft-gate probe injected"
else
  echo "::warning::Layer C: user-smoke payloads missing under $SMOKE_DIR — soft gate skipped (GUI probe unaffected)"
fi

# 4. Injected files carry no SELinux labels — run this boot permissive
#    (test VM only; the gating Layer B boot semantics are unaffected).
#    BLS entries live on the separate /boot partition, mounted on its
#    own. We also force console=ttyS0 onto the cmdline: the probe writes
#    its verdict to /dev/console, and the watcher reads -serial; if a
#    BLS entry only carries a graphics console the markers would go to
#    tty0 (the GPU, -display none) and never reach serial.log -> a
#    spurious gui=timeout (audit finding). Same loop handles both kargs.
BOOTPART=""
for part in "${NBD}"p*; do
  T="$(blkid -s TYPE -o value "$part" 2>/dev/null)"
  if [[ "$T" == "ext4" || "$T" == "xfs" ]]; then
    mkdir -p /mnt/smokeboot
    if mount -o ro "$part" /mnt/smokeboot 2>/dev/null; then
      if compgen -G '/mnt/smokeboot/loader/entries/*.conf' >/dev/null; then
        BOOTPART="$part"
        mount -o remount,rw /mnt/smokeboot
        break
      fi
      umount /mnt/smokeboot
    fi
  fi
done
if [[ -n "$BOOTPART" ]]; then
  for bls in /mnt/smokeboot/loader/entries/*.conf; do
    # Append each karg robustly: if an `options` line exists, extend it
    # (only when the karg isn't already present); otherwise add a fresh
    # `options` line so an entry with no options still gets the karg.
    add_karg() {
      local karg="$1" file="$2"
      grep -qE "(^|[[:space:]])${karg}([[:space:]]|\$)" "$file" && return 0
      if grep -q '^options ' "$file"; then
        sed -i "s|^options \(.*\)\$|options \1 ${karg}|" "$file"
      else
        printf 'options %s\n' "$karg" >> "$file"
      fi
    }
    add_karg "enforcing=0" "$bls"
    add_karg "console=ttyS0,115200" "$bls"
    echo "kargs: enforcing=0 console=ttyS0,115200 -> $bls"
  done
  umount /mnt/smokeboot
else
  echo "::warning::Layer C: BLS entries not found — probe files may be blocked by SELinux this run"
fi

# Explicit success-path teardown, then let the trap also run idempotently
# (cleanup is safe to invoke twice). sync flushes the btrfs before the
# nbd device is detached so the qcow2 Layer B boots is clean.
sync
umount -R /mnt/smoke
sync
qemu-nbd --disconnect "$NBD" 2>/dev/null || true
trap - EXIT
echo "Layer C injection complete"