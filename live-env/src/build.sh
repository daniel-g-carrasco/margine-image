#!/usr/bin/env bash
# Margine live-environment bake — runs inside live-env/Containerfile at
# OCI build time (bind-mounted at /src). Turns margine:stable into a
# bootable Live ISO payload for Titanoboa (ADR-0008).
#
# Reference: ublue-os/bazzite installer/build.sh +
# ondrejbudai/bootc-isos bazzite/src/build.sh (copied verbatim under
# live-env/references/bazzite/ at Phase 0). Margine deviations from the
# Bazzite reference are called out inline.
#
# Phase boundaries (ADR-0008 §6) are marked with "=== Phase N ===" so the
# git history (one commit per phase) maps cleanly onto this file.
set -euxo pipefail
{ export PS4='+( ${BASH_SOURCE}:${LINENO} ): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'; } 2>/dev/null

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ADR-0008 §4 invariant: the CachyOS kernel re-signed with the Margine
# MOK must be the ONLY kernel under /usr/lib/modules before Titanoboa
# runs. Titanoboa's build_iso.sh copies /usr/lib/modules/*/{vmlinuz,
# initramfs.img} with "behaviour unspecified" for multiple kernels.
# We deliberately do NOT swap in a vanilla Fedora kernel (Bazzite's
# titanoboa_hook_preinitramfs.sh pattern) — Margine ships CachyOS in
# both live and installed environments (ADR-0008 §3.2). The Secure
# Boot consequence (live boot needs SB disabled until the Margine MOK
# is enrolled) is documented + accepted.
#
# Asserted twice: at the start AND at the very end (after the dnf installs
# of anaconda-live etc., any of which could in principle pull a second
# kernel) — Titanoboa consumes /usr/lib/modules/* at the END state.
assert_single_kernel() {
  local n
  n="$(find /usr/lib/modules -maxdepth 1 -mindepth 1 -type d | wc -l)"
  if [[ "$n" -ne 1 ]]; then
    echo "ERROR: expected exactly 1 kernel under /usr/lib/modules, found $n:" >&2
    find /usr/lib/modules -maxdepth 1 -mindepth 1 -type d >&2
    exit 1
  fi
}

# === Phase 1 — bootable live environment ===

assert_single_kernel
KERNEL="$(find /usr/lib/modules -maxdepth 1 -mindepth 1 -type d -printf '%P\n')"
echo "Margine live kernel: $KERNEL"

# vmlinuz is the load-bearing Titanoboa input; a missing/empty one would
# produce a non-booting ISO with a cryptic failure deep in build_iso.sh.
test -s "/usr/lib/modules/${KERNEL}/vmlinuz" || {
  echo "ERROR: no vmlinuz under /usr/lib/modules/${KERNEL}" >&2
  exit 1
}

# BIOS boot status: the produced ISO is UEFI-ONLY today regardless of
# this directory. Titanoboa @5c457c3 never copies the grub BIOS modules
# (build_iso.sh:32 tests the i386-pc DIRECTORY with `[ -f ]`, always
# false) and its xorriso call has no El Torito BIOS image (-b) anyway —
# confirmed in the 2026-06-09 build-log scan. ADR-0008 §4 already
# treats BIOS as non-gating (all Margine reference hardware is UEFI);
# log the truth so nobody trusts a "hybrid" that isn't there.
if [[ -d /usr/lib/grub/i386-pc ]]; then
  echo "NOTE: /usr/lib/grub/i386-pc present, but current Titanoboa produces a UEFI-only ISO (no BIOS El Torito; upstream build_iso.sh:32 -f-vs-directory bug)"
else
  echo "NOTE: /usr/lib/grub/i386-pc absent — ISO is UEFI-only (per ADR-0008 §4, non-gating)"
fi

# Live-boot dependencies. dracut-live provides the dmsquash-live dracut
# modules (rd.live.image support); livesys-scripts auto-configures the
# live session at boot; grub2-efi-x64-cdboot provides gcdx64.efi which
# Titanoboa's build_iso.sh copies for the ISO's removable-media EFI
# boot path.
dnf install -y --setopt=install_weak_deps=False \
  dracut-live livesys-scripts grub2-efi-x64-cdboot

# Regenerate the initramfs with the live modules against the EXISTING
# CachyOS kernel (no kernel swap — see invariant above). --no-hostonly
# is mandatory: Fedora defaults to hostonly=yes which strips dmsquash-
# live and the live ISO would kernel-panic looking for a real root.
# DRACUT_NO_XATTR=1 + --reproducible mirror the Bazzite reference.
DRACUT_NO_XATTR=1 dracut -v --force --zstd --reproducible --no-hostonly \
  --add "dmsquash-live dmsquash-live-autooverlay" \
  "/usr/lib/modules/${KERNEL}/initramfs.img" "${KERNEL}"

# livesys: Margine is GNOME-only, so the session is always gnome. The
# config key is `livesys_session` (lowercase) in /etc/sysconfig/livesys
# — verified against the livesys-scripts package + Bazzite reference.
if [[ -f /etc/sysconfig/livesys ]]; then
  sed -i "s/^livesys_session=.*/livesys_session=gnome/" /etc/sysconfig/livesys
else
  echo "livesys_session=gnome" > /etc/sysconfig/livesys
fi
systemctl enable livesys.service livesys-late.service

# Titanoboa's build_iso.sh expects the EFI tree under /boot/efi/EFI.
# margine:stable (bootc) keeps EFI binaries under /usr/lib/efi/; copy
# them where the ISO assembler looks. grub2-efi-x64-cdboot (above)
# provides gcdx64.efi here.
mkdir -p /boot/efi
cp -av /usr/lib/efi/*/*/EFI /boot/efi/
# Guard the glob: if /usr/lib/efi/*/*/EFI didn't expand, the EFI tree is
# absent and Titanoboa (which needs /rootfs/boot/efi/EFI) would fail with
# a cryptic error far downstream. Fail clearly here instead.
test -d /boot/efi/EFI/fedora || {
  echo "ERROR: EFI tree not assembled under /boot/efi/EFI (glob /usr/lib/efi/*/*/EFI did not expand)" >&2
  exit 1
}

# Removable-media fallback bootloader (\EFI\BOOT\fbx64.efi). The grub
# fallback binary is what the firmware loads when there's no NVRAM boot
# entry — i.e. the USB-stick / DVD case. (Bazzite notes: remove this
# line if it breaks the bootloader; kept because the ISO is removable.)
cp -v /boot/efi/EFI/fedora/grubx64.efi /boot/efi/EFI/BOOT/fbx64.efi

# Ship the Margine MOK certificate on the ISO's EFI System Partition
# (ADR-0008 Phase 6). With Secure Boot enabled, the live CachyOS
# kernel fails shim verification ("Security Violation") because the
# firmware doesn't know the Margine key yet — but shim then offers
# MokManager, whose "Enroll key from disk" can only browse simple-fs
# volumes (FAT). Titanoboa packs /boot/efi/EFI verbatim into the
# ISO's efiboot image (build_iso.sh: mcopy -s /work/EFI ::), so the
# cert placed here is reachable as EFI/MOK.der on that volume:
# enroll (passphrase: margine-os) -> reboot -> the live boots with
# Secure Boot ON. Same pattern Bazzite documents for its ISOs.
cp -v /usr/share/cert/MOK.der /boot/efi/EFI/MOK.der

# Live-session branding (ADR-0008 Phase 6 debug findings, 2026-06-11):
# - liveinst.desktop ("Install to Hard Drive" in the dock) declares
#   Icon=org.fedoraproject.AnacondaInstaller, shipped only by the
#   absent fedora-logos package -> broken dock icon. Provide it as the
#   Margine mark.
# - anaconda-live's fedora-welcome dialog + its autostart entry keep
#   the untranslated Name=Welcome to Fedora (the dialog TITLE reads
#   os-release NAME, but the alt-tab/overview entry doesn't).
# The fedora-logo-icon the dialog hardcodes is already provided by
# build_files/50-branding/install.sh in the base image.
install -Dm0644 /usr/share/icons/hicolor/scalable/apps/margine-logo.svg \
  /usr/share/icons/hicolor/scalable/apps/org.fedoraproject.AnacondaInstaller.svg
gtk-update-icon-cache --force --quiet /usr/share/icons/hicolor 2>/dev/null || true
WELCOME_DESKTOP=/usr/share/anaconda/gnome/org.fedoraproject.welcome-screen.desktop
test -f "$WELCOME_DESKTOP" || { echo "ERROR: anaconda-live welcome .desktop missing — did the anaconda-live install change?" >&2; exit 1; }
sed -i 's/^Name=Welcome to Fedora$/Name=Welcome to Margine/' "$WELCOME_DESKTOP"
grep -q '^Name=Welcome to Margine$' "$WELCOME_DESKTOP" || { echo "ERROR: welcome .desktop rebrand did not apply" >&2; exit 1; }

# / in a booted live ISO is an overlayfs whose upperdir is under /run
# (a small tmpfs). Anaconda's ostree install needs lots of scratch in
# /var/tmp, which would otherwise land on that small tmpfs. Mount a
# larger tmpfs at /var/tmp at live-boot time. (Bazzite reference.)
rm -rf /var/tmp
mkdir /var/tmp
cat >/etc/systemd/system/var-tmp.mount <<'EOF'
[Unit]
Description=Larger tmpfs for /var/tmp on the Margine live system

[Mount]
What=tmpfs
Where=/var/tmp
Type=tmpfs
Options=size=50%%,nr_inodes=1m

[Install]
WantedBy=local-fs.target
EOF
systemctl enable var-tmp.mount

# Live session timezone (cosmetic; the installed system's tz is chosen
# at install / first boot).
rm -f /etc/localtime
systemd-firstboot --timezone UTC || true

# Titanoboa requires /usr/lib/bootc-image-builder/iso.yaml (build_iso.sh
# exits 1 if missing). It defines the ISO label + GRUB boot entries.
mkdir -p /usr/lib/bootc-image-builder
cp "$SRC_DIR/iso.yaml" /usr/lib/bootc-image-builder/iso.yaml

# === Phase 2 — BAKE Flatpaks into the live env ===
# The ~38 Margine "fundamentals" are installed into /var/lib/flatpak of
# the live image at build time, then rsync'd into the target at install
# time (install-flatpaks.ks). This is the Bazzite installer-image pattern
# Margine already uses for BIB (installer/build.sh) — the user lands on a
# fully-populated desktop with no first-boot download wait.

# bwrap (used by flatpak apply_extra for binary blobs) needs a writable
# /proc/sys and a real /root. Same prep as installer/build.sh.
mkdir -p "$(realpath /root)"
mount -o remount,rw /proc/sys

flatpak remote-add --if-not-exists --system flathub \
  https://dl.flathub.org/repo/flathub.flatpakrepo

# Strip whole-line + inline comments and surrounding whitespace, exactly
# like installer/build.sh (an un-stripped "id  # note" would be passed to
# flatpak as a literal id and fail with "Name can't start with #").
APPS="$(grep -vE '^[[:space:]]*#|^[[:space:]]*$' "$SRC_DIR/flatpaks" \
        | sed -E 's/[[:space:]]*#.*$//; s/^[[:space:]]+//; s/[[:space:]]+$//' \
        | grep -v '^$')"
echo "=== Installing $(echo "$APPS" | wc -l) Flatpaks into the live env ==="
echo "$APPS"
# shellcheck disable=SC2086 # word-splitting of the app list is intended
flatpak install --system --noninteractive --or-update flathub $APPS
flatpak list --system --app --columns=application | sort
du -sh /var/lib/flatpak 2>/dev/null || true

# Mount /var/lib/flatpak read-only in the LIVE session so the user can't
# taint the baked set before it's rsync'd to the target. (Bazzite pattern.)
cat >/etc/systemd/system/var-lib-flatpak.mount <<'EOF'
[Unit]
Description=Read-only bind of /var/lib/flatpak for the Margine live system

[Mount]
What=/var/lib/flatpak
Where=/var/lib/flatpak
Type=none
Options=bind,ro

[Install]
WantedBy=multi-user.target
EOF
systemctl enable var-lib-flatpak.mount

# Stage the install-time kickstart fragment that rsyncs the baked
# Flatpaks into the target deployment. It is %included by
# interactive-defaults.ks (Phase 3). Harmless to ship before Anaconda
# is installed — it's just a file under post-scripts/.
mkdir -p /usr/share/anaconda/post-scripts
cp "$SRC_DIR/anaconda/post-scripts/install-flatpaks.ks" \
   /usr/share/anaconda/post-scripts/install-flatpaks.ks

# === Phase 3 — Anaconda WebUI installer ===
# WebUI engine (ADR-0008 §3.3), matching Bluefin/Bazzite production.
dnf install -y --enable-repo=fedora-cisco-openh264 --allowerasing \
  firefox anaconda-live anaconda-webui \
  libblockdev-btrfs libblockdev-lvm libblockdev-dm
mkdir -p /var/lib/rpm-state  # Anaconda WebUI requires it

# Margine Anaconda profile (WebUI + BTRFS/zstd defaults, variant_id
# detection). See live-env/src/anaconda/profile.d/margine.conf.
install -Dm0644 "$SRC_DIR/anaconda/profile.d/margine.conf" \
  /etc/anaconda/profile.d/margine.conf

# Install-time kickstart fragments. Re-copies install-flatpaks.ks
# (same content as the Phase 2 line above) plus bootc-switch + zstd.
cp "$SRC_DIR"/anaconda/post-scripts/*.ks /usr/share/anaconda/post-scripts/

# Append Margine partitioning + ostreecontainer + %includes to the base
# interactive-defaults.ks anaconda-live ships (preserve the base).
cat "$SRC_DIR/anaconda/interactive-defaults.ks" \
  >> /usr/share/anaconda/interactive-defaults.ks

# Recompile schemas in case the profile/installer added overrides.
glib-compile-schemas /usr/share/glib-2.0/schemas || true

# Disable services that must not run inside the LIVE session. Margine is
# Bluefin-DX-based, so it carries the ublue/brew/flatpak-preinstall units
# plus rpm-ostree timers — all of which are meaningless (or harmful) in a
# throwaway live env. Defensive: only disable units that exist (Bazzite
# pattern), so this never fails the build on a renamed/absent unit.
(
  set +e
  for unit in \
    rpm-ostree-countme.service \
    rpm-ostreed-automatic.timer \
    bootloader-update.service \
    flatpak-preinstall.service \
    brew-setup.service \
    brew-upgrade.timer \
    brew-update.timer \
    uupd.timer \
    ublue-system-setup.service \
    tailscaled.service; do
    if systemctl list-unit-files "$unit" >/dev/null 2>&1; then
      systemctl disable "$unit"
    fi
  done
  for gunit in \
    podman-auto-update.timer \
    ublue-user-setup.service \
    bazaar.service; do
    if systemctl --global list-unit-files "$gunit" >/dev/null 2>&1; then
      systemctl --global disable "$gunit"
    fi
  done
)

# Re-assert the single-kernel invariant at the END state — this is what
# Titanoboa actually consumes. Any of the dnf installs above could in
# principle have pulled a second kernel; fail the build if so.
assert_single_kernel

# Reclaim build-layer space.
dnf clean all
