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
set -euo pipefail

QCOW="${1:?usage: inject-gui-probe.sh <image.qcow2>}"
SMOKE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../smoke" && pwd)"
[[ -f "$SMOKE_DIR/gui-probe.sh" && -f "$SMOKE_DIR/margine-gui-smoke.service" ]] \
  || { echo "::warning::Layer C: payloads missing under $SMOKE_DIR"; exit 1; }

# Trap installed BEFORE qemu-nbd connects, covering BOTH mountpoints:
# a mid-injection failure must not disconnect nbd under a mounted rw
# boot partition (dirty journal on the very qcow2 Layer B then boots —
# review finding A5).
trap 'umount -R /mnt/smokeboot 2>/dev/null || true; umount -R /mnt/smoke 2>/dev/null || true; qemu-nbd --disconnect /dev/nbd0 2>/dev/null || true' EXIT
modprobe nbd max_part=16
qemu-nbd --connect=/dev/nbd0 "$QCOW"
udevadm settle || sleep 2

# Root = the btrfs partition (BIB --rootfs btrfs).
ROOTPART=""
for part in /dev/nbd0p*; do
  [[ "$(blkid -s TYPE -o value "$part")" == "btrfs" ]] && ROOTPART="$part"
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

# 4. Injected files carry no SELinux labels — run this boot permissive
#    (test VM only; the gating Layer B boot semantics are unaffected).
#    BLS entries live on the separate /boot partition, mounted on its
#    own.
BOOTPART=""
for part in /dev/nbd0p*; do
  T="$(blkid -s TYPE -o value "$part")"
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
    grep -q 'enforcing=0' "$bls" || sed -i 's/^options \(.*\)$/options \1 enforcing=0/' "$bls"
    echo "kargs: enforcing=0 -> $bls"
  done
  umount /mnt/smokeboot
else
  echo "::warning::Layer C: BLS entries not found — probe files may be blocked by SELinux this run"
fi

umount -R /mnt/smoke
qemu-nbd --disconnect /dev/nbd0
trap - EXIT
echo "Layer C injection complete"
