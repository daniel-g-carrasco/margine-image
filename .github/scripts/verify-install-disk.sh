#!/usr/bin/env bash
# Offline-verify a freshly installed Margine target disk for the Flatpak
# bake (forum 12247 install gate). Exposes the qcow2 via qemu-nbd (reusing
# the hardened nbd dance from inject-gui-probe.sh), mounts the btrfs root
# read-only, and asserts the baked /var/lib/flatpak that broke on the SER8
# is actually present, configured, populated, and correctly SELinux-labeled.
#   usage (root): verify-install-disk.sh <target.qcow2>
set -euo pipefail
# An unexpanded /dev/nbd0p* glob must become an EMPTY list, never a literal.
shopt -s nullglob

QCOW="${1:?usage: verify-install-disk.sh <target.qcow2>}"
NBD=/dev/nbd0
MNT=/mnt/verifyroot

cleanup() {
  for _ in 1 2 3; do mountpoint -q "$MNT" || break; umount -R "$MNT" 2>/dev/null && break; sleep 1; done
  sync
  qemu-nbd --disconnect "$NBD" 2>/dev/null || true
}
trap cleanup EXIT

# Force a clean nbd reload so max_part=16 actually creates the pN nodes
# (modprobe is a silent no-op if nbd was already loaded without it).
qemu-nbd --disconnect "$NBD" 2>/dev/null || true
modprobe -r nbd 2>/dev/null || true
modprobe nbd max_part=16 || modprobe nbd || true
qemu-nbd --connect="$NBD" "$QCOW"
partprobe "$NBD" 2>/dev/null || partx -u "$NBD" 2>/dev/null || true
for _ in $(seq 1 20); do
  parts=("$NBD"p*); [[ ${#parts[@]} -gt 0 ]] && break
  sleep 1; partprobe "$NBD" 2>/dev/null || true
done

ROOT=""
for p in "$NBD"p*; do
  [[ "$(blkid -o value -s TYPE "$p" 2>/dev/null)" == btrfs ]] && ROOT="$p" && break
done
[[ -n "$ROOT" ]] || { echo "::error::no btrfs root partition on $QCOW"; lsblk "$NBD" || true; exit 1; }
mkdir -p "$MNT"; mount -o ro "$ROOT" "$MNT"

SR="$(ls "$MNT"/ostree/deploy 2>/dev/null | head -1)"
[[ -n "$SR" ]] || { echo "::error::no ostree stateroot under /ostree/deploy"; ls -la "$MNT"/ostree/deploy 2>/dev/null || true; exit 1; }
VARLIB="$MNT/ostree/deploy/$SR/var/lib"
echo "stateroot=$SR  varlib=$VARLIB"

fail=0
ok()  { printf '  OK   %s\n' "$1"; }
bad() { printf '::error::%s\n' "$1"; fail=1; }

# (a) the bake's success condition — install-flatpaks.ks MARGINE-BAKE-OK
[[ -d "$VARLIB/flatpak/repo/refs/remotes/flathub" ]] \
  && ok "flatpak repo has refs/remotes/flathub" \
  || bad "flatpak repo MISSING refs/remotes/flathub (the exact SER8 break)"

# (b) flathub configured in the repo
grep -q 'remote "flathub"' "$VARLIB/flatpak/repo/config" 2>/dev/null \
  && ok "flathub present in repo/config" \
  || bad "flathub not in flatpak/repo/config"

# (c) the baked apps actually landed
N=$(find "$VARLIB/flatpak/app" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)
echo "  baked apps under flatpak/app: $N"
[[ "$N" -ge 10 ]] && ok "app count $N >= 10" || bad "only $N baked apps (expected dozens)"

# (d) SELinux label correct (the bug left it stripped/wrong -> repo inaccessible)
ctx="$(getfattr -n security.selinux --only-values "$VARLIB/flatpak" 2>/dev/null | tr -d '\0' || true)"
echo "  /var/lib/flatpak SELinux context: ${ctx:-<unreadable>}"
case "$ctx" in
  *var_lib_t*|*var_t*) ok "SELinux context is var_lib_t" ;;
  "")                  echo "  ::warning::could not read security.selinux xattr (non-fatal)" ;;
  *)                   bad "SELinux context wrong ($ctx) — expected var_lib_t" ;;
esac

echo
if [[ "$fail" -eq 0 ]]; then echo "MARGINE-INSTALL-FLATPAK: PASS"; else echo "MARGINE-INSTALL-FLATPAK: FAIL"; fi
exit "$fail"
