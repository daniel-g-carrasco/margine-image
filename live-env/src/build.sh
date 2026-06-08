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

# === Phase 1 — bootable live environment ===

# ADR-0008 §4 invariant: the CachyOS kernel re-signed with the Margine
# MOK must be the ONLY kernel under /usr/lib/modules before Titanoboa
# runs. Titanoboa's build_iso.sh copies /usr/lib/modules/*/{vmlinuz,
# initramfs.img} with "behaviour unspecified" for multiple kernels.
# We deliberately do NOT swap in a vanilla Fedora kernel (Bazzite's
# titanoboa_hook_preinitramfs.sh pattern) — Margine ships CachyOS in
# both live and installed environments (ADR-0008 §3.2). The Secure
# Boot consequence (live boot needs SB disabled until the Margine MOK
# is enrolled) is documented + accepted.
kernel_count="$(find /usr/lib/modules -maxdepth 1 -mindepth 1 -type d | wc -l)"
if [[ "$kernel_count" -ne 1 ]]; then
  echo "ERROR: expected exactly 1 kernel under /usr/lib/modules, found $kernel_count:" >&2
  find /usr/lib/modules -maxdepth 1 -mindepth 1 -type d >&2
  exit 1
fi
KERNEL="$(find /usr/lib/modules -maxdepth 1 -mindepth 1 -type d -printf '%P\n')"
echo "Margine live kernel: $KERNEL"

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

# Removable-media fallback bootloader (\EFI\BOOT\fbx64.efi). The grub
# fallback binary is what the firmware loads when there's no NVRAM boot
# entry — i.e. the USB-stick / DVD case. (Bazzite notes: remove this
# line if it breaks the bootloader; kept because the ISO is removable.)
cp -v /boot/efi/EFI/fedora/grubx64.efi /boot/efi/EFI/BOOT/fbx64.efi

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
Options=size=50%,nr_inodes=1m

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

# Reclaim build-layer space.
dnf clean all
