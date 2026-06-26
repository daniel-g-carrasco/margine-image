#!/usr/bin/env bash
# Offline-verify a freshly installed Margine target disk for the Flatpak
# bake (forum 12247 install gate). Exposes the qcow2 via qemu-nbd (reusing
# the hardened nbd dance from inject-gui-probe.sh), mounts the btrfs root
# read-only, and asserts the baked /var/lib/flatpak that broke on the SER8
# is present, configured, populated, and correctly SELinux-labeled.
#   usage (root): verify-install-disk.sh <target.qcow2>
#
# NB: deliberately NOT `set -e` — a verify script must run ALL checks and
# report, not die on the first non-zero. Critical setup steps check
# explicitly; assertions accumulate into $fail.
set -uo pipefail
shopt -s nullglob

QCOW="${1:?usage: verify-install-disk.sh <target.qcow2>}"
NBD=/dev/nbd0
MNT=/mnt/verifyroot
set -x  # trace: pinpoint any setup failure in CI logs

cleanup() {
  set +x
  for _ in 1 2 3; do mountpoint -q "$MNT" || break; umount -R "$MNT" 2>/dev/null && break; sleep 1; done
  sync
  qemu-nbd --disconnect "$NBD" >/dev/null 2>&1 || true
}
trap cleanup EXIT

qemu-nbd --disconnect "$NBD" >/dev/null 2>&1 || true
modprobe -r nbd 2>/dev/null || true
modprobe nbd max_part=16 2>/dev/null || modprobe nbd 2>/dev/null || true
[[ -e /dev/nbd0 ]] || { set +x; echo "::error::nbd module unavailable (/dev/nbd0 missing)"; exit 1; }

if ! qemu-nbd --connect="$NBD" "$QCOW"; then
  set +x; echo "::error::qemu-nbd --connect failed for $QCOW"; exit 1
fi
partprobe "$NBD" 2>/dev/null || partx -u "$NBD" 2>/dev/null || true
parts=()
for _ in $(seq 1 20); do
  parts=("$NBD"p*)
  if [[ ${#parts[@]} -gt 0 ]]; then break; fi
  sleep 1
  partprobe "$NBD" 2>/dev/null || true
done

ROOT=""
for p in "$NBD"p*; do
  if [[ "$(blkid -o value -s TYPE "$p" 2>/dev/null)" == "btrfs" ]]; then ROOT="$p"; break; fi
done
if [[ -z "$ROOT" ]]; then
  set +x; echo "::error::no btrfs root partition on $QCOW"; lsblk "$NBD" 2>/dev/null || true; blkid "$NBD"p* 2>/dev/null || true; exit 1
fi
mkdir -p "$MNT"
# Mount the btrfs TOP (subvolid 5) so EVERY subvol is traversable in one mount.
# CRITICAL (review wzskaqvwo, confirmed on this bootc host): Margine's
# margine.conf default_partitioning gives /var its OWN btrfs subvol, and
# install-flatpaks.ks bakes into THAT dedicated /var (/mnt/sysimage/var/lib) —
# NOT the per-deployment stateroot var (/ostree/deploy/$sr/var), which is just
# an empty .ostree-selabeled stub. At the btrfs top the bake therefore lives at
# $MNT/var/lib/flatpak. Reading the stateroot stub would FALSE-FAIL every check.
mount -o ro,subvolid=5 "$ROOT" "$MNT" 2>/dev/null \
  || mount -o ro "$ROOT" "$MNT" 2>/dev/null \
  || { set +x; echo "::error::could not mount btrfs root $ROOT"; exit 1; }

# VARLIB = the lib/ dir that actually contains the baked flatpak/ (the dedicated
# /var subvol), located robustly across subvol layouts.
VARLIB=""
for cand in "$MNT/var/lib" "$MNT/root/var/lib"; do
  if [[ -d "$cand/flatpak" ]]; then VARLIB="$cand"; break; fi
done
if [[ -z "$VARLIB" ]]; then
  fp="$(find "$MNT" -maxdepth 6 -type d -path '*/var/lib/flatpak' 2>/dev/null | head -1)"
  [[ -n "$fp" ]] && VARLIB="$(dirname "$fp")"
fi
if [[ -z "$VARLIB" ]]; then
  # last resort: mount the dedicated var subvol explicitly
  umount -R "$MNT" 2>/dev/null
  if mount -o ro,subvol=var "$ROOT" "$MNT" 2>/dev/null && [[ -d "$MNT/lib/flatpak" ]]; then VARLIB="$MNT/lib"; fi
fi
set +x
if [[ -z "$VARLIB" ]]; then
  echo "::error::no var/lib/flatpak on installed disk — bake missing or unexpected subvol layout"
  ls -laR "$MNT" 2>/dev/null | head -80 || true
  exit 1
fi
echo "varlib=$VARLIB (dedicated /var btrfs subvol)"
ls -la "$VARLIB/flatpak" 2>/dev/null | head -20 || true

fail=0
ok()  { printf '  OK   %s\n' "$1"; }
bad() { printf '::error::%s\n' "$1"; fail=1; }

[[ -d "$VARLIB/flatpak/repo/refs/remotes/flathub" ]] \
  && ok "flatpak repo has refs/remotes/flathub" \
  || bad "flatpak repo MISSING refs/remotes/flathub (the exact SER8 break)"

grep -q 'remote "flathub"' "$VARLIB/flatpak/repo/config" 2>/dev/null \
  && ok "flathub present in repo/config" \
  || bad "flathub not in flatpak/repo/config"

N=$(find "$VARLIB/flatpak/app" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)
echo "  baked apps under flatpak/app: $N"
[[ "$N" -ge 10 ]] && ok "app count $N >= 10" || bad "only $N baked apps (expected dozens)"

ctx="$(getfattr -n security.selinux --only-values "$VARLIB/flatpak" 2>/dev/null | tr -d '\0' || true)"
echo "  /var/lib/flatpak SELinux context: ${ctx:-<unreadable>}"
case "$ctx" in
  *var_lib_t*) ok "SELinux context is var_lib_t" ;;
  "")          echo "  ::warning::could not read security.selinux xattr (non-fatal)" ;;
  *)           bad "SELinux context '$ctx' wrong — /var/lib/flatpak must be var_lib_t (var_t is NOT enough)" ;;
esac

echo
if [[ "$fail" -eq 0 ]]; then echo "MARGINE-INSTALL-FLATPAK: PASS"; else echo "MARGINE-INSTALL-FLATPAK: FAIL"; fi
exit "$fail"
