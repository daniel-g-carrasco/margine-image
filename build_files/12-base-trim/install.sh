#!/usr/bin/env bash
# Remove what the base ships and Margine does not want in an installed system.
#
# WHY THIS EXISTS (2026-08-25)
#
# The new Bluefin (ghcr.io/projectbluefin/bluefin) is built as a
# "container-native ISO": the image itself boots as a live system and
# carries the installer. So it ships anaconda (core, live, tui, webui),
# livesys-scripts, dracut-live, isomd5sum, cockpit-ws for the Anaconda
# WebUI, qt6-qtwebengine (277 MiB, required by nothing) and a Firefox RPM
# for the live session's favourites. Bluefin DX, today's base, ships none
# of that.
#
# Margine builds its ISO differently: live-env/src/build.sh layers
# dracut-live, livesys-scripts, anaconda-live and anaconda-webui on top
# of the finished image at ISO time, with Margine's own Anaconda profile.
# An installed Margine has never carried an installer, and the spec
# (docs/spec/06, "do not use the system Firefox RPM") ships Zen as a
# Flatpak with org.mozilla.firefox as the Flatpak fallback. Decision
# (2026-08-25): strip both on any base that brings them.
#
# Measured inside the trial image on the plain base: an explicit remove
# of the list below takes 12 packages and 583 MiB (the two extra ones
# are dependents: qt6-qtwebview, slitherer). Orphan cleanup
# (clean_requirements_on_remove) would take 68 packages and 656 MiB but
# also fuse (FUSE 2, AppImages), python3-rpm, python3-systemd and
# NetworkManager-team, all present in today's image; so it stays off and
# the ~70 MiB of orphaned libraries are left alone on purpose.
#
# On today's base every package below is absent and this is a no-op.
#
# LEFTOVERS AND UNWANTED FAMILIES (2026-10-10)
#
# A package audit of lucciola.20261009 by originating layer found 3.6 GB
# that nothing needs:
#   - qemu for every architecture but x86 (Bluefin DX installs the `qemu`
#     meta package): 57 packages, 1088 MB. Margine's VMs
#     (margine-test-vm, virt-manager, podman-machine) are x86 only.
#   - wine and mingw64, 1.9 GB: weak dependencies of lutris left behind by
#     the gaming bake in custom-kernel. The bake no longer installs weak
#     dependencies; this is the guard.
#   - fluid soundfonts and wildmidi (330 MB), python3-boto3/botocore
#     (130 MB), gnome-user-docs and yelp (65 MB; Margine ships its own
#     offline docs and Bluefin itself excludes yelp): orphans.
# The families are matched by name pattern, so they are removed whatever
# the base's version of them; the prove-it block then checks that
# everything the x86 VMs need is still there.
set -euo pipefail
. /ctx/00-common.sh
log() { printf '[base-trim] %s\n' "$*"; }
err() { printf '[base-trim] ERROR: %s\n' "$*" >&2; }

TRIM_PKGS=(
  anaconda-core anaconda-live anaconda-tui anaconda-webui  # the installer
  livesys-scripts dracut-live isomd5sum                     # live-boot plumbing
  cockpit-ws                                                # Anaconda WebUI transport
  qt6-qtwebengine                                           # 277 MiB, required by nothing
  firefox mozilla-openh264                                  # spec: no system Firefox RPM
  fluid-soundfont-gm fluid-soundfont-gs fluid-soundfont-lite-patches wildmidi-libs  # MIDI soundfonts, orphans
  python3-boto3 python3-botocore python3-s3transfer         # AWS SDK, orphans
  gnome-user-docs yelp yelp-libs yelp-xsl                   # GNOME help: Margine ships offline docs
)

# What the x86 VMs keep: the x86 system emulator with its UEFI firmware,
# the image tools, the plugins every qemu-system build requires, and the
# three user-mode emulators containers-common pulls for multi-arch podman.
QEMU_KEEP='^(qemu-system-x86(-core)?|qemu-kvm(-core)?|qemu-img|qemu-common|qemu-tools|qemu-pr-helper|qemu-guest-agent|qemu-user-static-(aarch64|arm|x86)|edk2-ovmf|qemu-(ui|device|char|audio|block)-.*)$'

PRESENT=()
for p in "${TRIM_PKGS[@]}"; do
  rpm -q "$p" >/dev/null 2>&1 && PRESENT+=("$p")
done
# Everything qemu/edk2 that is not in the keep list (other architectures,
# the `qemu` and `qemu-user-static` meta packages, qemu-user).
while read -r p; do
  [[ -n "$p" ]] && PRESENT+=("$p")
done < <(rpm -qa --qf '%{NAME}\n' | grep -E '^(qemu|edk2)' | grep -v -E "$QEMU_KEEP" || true)
# The wine family, whatever is left of it.
while read -r p; do
  [[ -n "$p" ]] && PRESENT+=("$p")
done < <(rpm -qa --qf '%{NAME}\n' | grep -E '^(wine|mingw)' || true)

if (( ${#PRESENT[@]} == 0 )); then
  log "base ships none of the ${#TRIM_PKGS[@]} trim candidates, nothing to do"
else
  log "base ships ${#PRESENT[@]} packages Margine does not install, removing: ${PRESENT[*]}"
  dnf -y remove --setopt=clean_requirements_on_remove=False "${PRESENT[@]}"
fi

# --- Prove it -------------------------------------------------------------
for p in "${TRIM_PKGS[@]}"; do
  if rpm -q "$p" >/dev/null 2>&1; then err "$p still present after base-trim"; exit 1; fi
done
if rpm -qa --qf '%{NAME}\n' | grep -E '^(qemu|edk2)' | grep -v -E "$QEMU_KEEP" | grep -q .; then
  err "qemu packages outside the keep list survived base-trim"; exit 1
fi
if rpm -qa --qf '%{NAME}\n' | grep -E '^(wine|mingw)' | grep -q .; then
  err "the wine family survived base-trim"; exit 1
fi
# What the trim must never take with it (present in today's image).
for p in fuse python3-rpm python3-systemd NetworkManager-team \
         qemu-kvm qemu-system-x86-core qemu-img qemu-common edk2-ovmf virtiofsd libvirt-daemon-driver-qemu; do
  rpm -q "$p" >/dev/null 2>&1 || { err "$p is gone: the trim removed more than it should"; exit 1; }
done
log "base trim complete"
