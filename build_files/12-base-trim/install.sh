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
# Flatpak with org.mozilla.firefox as the Flatpak fallback. Daniel's call
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
)

PRESENT=()
for p in "${TRIM_PKGS[@]}"; do
  rpm -q "$p" >/dev/null 2>&1 && PRESENT+=("$p")
done

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
# What the trim must never take with it (present in today's image).
for p in fuse python3-rpm python3-systemd NetworkManager-team; do
  rpm -q "$p" >/dev/null 2>&1 || { err "$p is gone: the trim removed more than it should"; exit 1; }
done
log "base trim complete"
