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
# Wait specifically for the BTRFS root partition to appear AND be
# blkid-identifiable. Partition nodes settle asynchronously after qemu-nbd
# connect; a previous version broke out as soon as ANY nbd0p* node existed and
# then probed for btrfs ONCE — racing the (last-to-appear) btrfs partition and
# false-failing with "no btrfs root partition" even though the install was fine.
ROOT=""
for _ in $(seq 1 20); do
  partprobe "$NBD" 2>/dev/null || partx -u "$NBD" 2>/dev/null || true
  for p in "$NBD"p*; do
    [[ -b "$p" ]] || continue
    if [[ "$(blkid -o value -s TYPE "$p" 2>/dev/null)" == "btrfs" ]]; then ROOT="$p"; break 2; fi
  done
  sleep 1
done
if [[ -z "$ROOT" ]]; then
  set +x; echo "::error::no btrfs root partition on $QCOW"; lsblk "$NBD" 2>/dev/null || true; blkid "$NBD"p* 2>/dev/null || true; exit 1
fi
mkdir -p "$MNT"
# Mount the btrfs TOP (subvolid 5) so EVERY subvol is traversable in one mount.
# install-flatpaks.ks bakes into the per-deployment stateroot var CHECKOUT
# (ostree/deploy/$sr/deploy/$commit.0/var/lib) — upstream Bluefin/Aurora parity,
# NOT the bare dedicated /var subvol (empty until first boot). The VARLIB
# resolution below locates the baked repo wherever it landed.
mount -o ro,subvolid=5 "$ROOT" "$MNT" 2>/dev/null \
  || mount -o ro "$ROOT" "$MNT" 2>/dev/null \
  || { set +x; echo "::error::could not mount btrfs root $ROOT"; exit 1; }

# VARLIB = the var/lib dir that actually contains the baked flatpak/ repo.
#
# CRITICAL (2026-06-28, take 2): install-flatpaks.ks now bakes into the
# per-deployment stateroot var checkout (ostree/deploy/$sr/deploy/$commit.0/
# var/lib), EXACTLY like upstream Bluefin/Aurora — NOT the bare dedicated
# /var btrfs subvol. On a freshly-installed-but-never-booted disk the bake
# therefore lives under .../deploy/*.0/var/lib/flatpak; the dedicated /var
# subvol is still empty (ostree seeds it on first boot). The previous
# version of this gate asserted the bake at the bare /var subvol and so
# FALSE-PASSED the broken layout — locate the repo by where it actually is,
# preferring the deploy checkout and requiring a POPULATED flathub repo.
VARLIB=""
# 1) the ostree deployment checkout where the bake lands (require flathub).
#    Handle both a top-level ostree/ (subvols flat under subvolid=5) and a
#    nested root subvol ($MNT/<rootsubvol>/ostree/...).
for d in "$MNT"/ostree/deploy/*/deploy/*.0/var/lib \
         "$MNT"/*/ostree/deploy/*/deploy/*.0/var/lib; do
  if [[ -d "$d/flatpak/repo/refs/remotes/flathub" ]]; then VARLIB="$d"; break; fi
done
# 2) fallback: any var/lib whose flatpak repo has a flathub remote. The
#    deploy-checkout path is deep (~13 levels under a nested root subvol),
#    so keep maxdepth generous.
if [[ -z "$VARLIB" ]]; then
  fp="$(find "$MNT" -maxdepth 15 -type d -path '*/var/lib/flatpak/repo/refs/remotes/flathub' 2>/dev/null | head -1)"
  [[ -n "$fp" ]] && VARLIB="${fp%/flatpak/repo/refs/remotes/flathub}"
fi
# 3) last resort: any var/lib/flatpak at all (so we report WHERE the broken
#    bake landed instead of a bare "not found")
if [[ -z "$VARLIB" ]]; then
  fp="$(find "$MNT" -maxdepth 12 -type d -path '*/var/lib/flatpak' 2>/dev/null | head -1)"
  [[ -n "$fp" ]] && VARLIB="${fp%/flatpak}"
fi
set +x
if [[ -z "$VARLIB" ]]; then
  echo "::error::no var/lib/flatpak on installed disk — bake missing or unexpected subvol layout"
  ls -laR "$MNT"/ostree/deploy "$MNT"/*/ostree/deploy 2>/dev/null | head -120 \
    || ls -laR "$MNT" 2>/dev/null | head -120 || true
  exit 1
fi
echo "varlib=$VARLIB (per-deployment stateroot var checkout)"
ls -la "$VARLIB/flatpak" 2>/dev/null | head -20 || true

fail=0
ok()  { printf '  OK   %s\n' "$1"; }
bad() { printf '::error::%s\n' "$1"; fail=1; }

# NOTE: we deliberately do NOT assert WHERE the repo sits. Depending on the
# partitioning (dedicated /var btrfs subvol vs plain autopart) and how ostree
# presents the per-deployment .0/var, at subvolid=5 the baked repo legitimately
# appears either under ostree/deploy/*/deploy/*.0/var/lib OR directly at
# $MNT/var/lib. Offline we cannot tell which /var the BOOTED system actually
# reads — that needs a boot test (tracked follow-up). The meaningful, layout-
# independent assertions are below: repo present, populated, flathub, labeled.
echo "  info: baked repo resolved at $VARLIB"

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

# TRUNCATED-INSTALL sensor (2026-07-04 incident). Anaconda copies its logs to
# the target's var/log/anaconda as one of its LAST acts — so "anaconda logs
# present AND our bake script logged MARGINE-BAKE-OK inside them" proves the
# install ran to completion. On the 2026-07-04 VM install, gnome-shell
# segfaulted, the WebUI viewer died with the session, anaconda (which by
# design stops when its viewer disappears) was cut mid-bake-rsync: app/
# present, repo/ empty, NO var/log/anaconda — and this gate would still have
# PASSED, because the headless gate never runs a GNOME session at all. This
# assertion detects the truncation CLASS regardless of cause. Search rather
# than hardcode: the log path follows the same var-layout variance as VARLIB.
ANALOG="$(find "$MNT" -maxdepth 7 -type d -name anaconda -path '*/var/log/*' 2>/dev/null | head -1)"
if [[ -n "$ANALOG" ]] && compgen -G "$ANALOG/ks-script-*.log" > /dev/null; then
  ok "anaconda logs present on target ($ANALOG) — install ran to completion"
  # The bake script logs to its OWN file (%post --log=/mnt/sysimage/var/log/
  # anaconda-post-flatpak-bake.log), NOT to ks-script-*.log — the first
  # version of this sensor grepped only ks-script logs and FALSE-FAILED a
  # perfectly good install (run 28735501082: 37 apps on disk, marker present
  # in the dedicated log). Check the dedicated log first, ks-script as a
  # fallback in case the --log redirection ever goes away.
  BAKELOG="${ANALOG%/anaconda}/anaconda-post-flatpak-bake.log"
  if grep -hq "MARGINE-BAKE-OK" "$BAKELOG" "$ANALOG"/ks-script-*.log 2>/dev/null; then
    ok "MARGINE-BAKE-OK found ($(grep -lh "MARGINE-BAKE-OK" "$BAKELOG" "$ANALOG"/ks-script-*.log 2>/dev/null | head -1)) — bake completed and self-verified"
  else
    bad "no MARGINE-BAKE-OK in $BAKELOG nor $ANALOG/ks-script-*.log — bake script died or never ran"
  fi
else
  bad "no var/log/anaconda with ks-script logs on the installed disk — anaconda was cut short (truncated install)"
fi

echo
if [[ "$fail" -eq 0 ]]; then echo "MARGINE-INSTALL-FLATPAK: PASS"; else echo "MARGINE-INSTALL-FLATPAK: FAIL"; fi
exit "$fail"
