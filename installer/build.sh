#!/usr/bin/env bash
# Margine installer image build.sh — runs inside the installer
# Containerfile RUN at OCI build time. Single job: install the
# Margine BAKE Flatpaks system-wide so they end up in
# /var/lib/flatpak of the installer rootfs.
#
# This file is bind-mounted at /src during the Containerfile RUN.
# $FLATPAK_LIST_FILE selects which Flatpak list to install
# (passed as build-arg by build-disk.yml workflow):
#   flatpaks-base    — base Margine (22 apps)
#   flatpaks-gaming  — base Margine + 5 gaming launchers (27 apps)
#
# After this script completes, /var/lib/flatpak has all the apps
# pre-installed. BIB anaconda-iso packs this entire image into
# the live installer rootfs. Kickstart in disk_config/iso-gnome.toml
# rsyncs that /var/lib/flatpak into the target system's
# /var/lib/flatpak — done.
set -eux -o pipefail

# Environment prep for bwrap / flatpak install in podman build context.
# Copied straight from Bazzite's installer/build.sh — without these the
# apply_extra step (used by Reaper, Steam, openh264 for binary blobs)
# fails with:
#   F: Unable to provide a temporary home directory in the sandbox:
#      Unable to open path "/var/roothome": No such file or directory
#   bwrap: cannot open /proc/sys/user/max_user_namespaces:
#      Read-only file system
mkdir -p "$(realpath /root)"
mount -o remount,rw /proc/sys

FLATPAK_LIST_FILE="${FLATPAK_LIST_FILE:-flatpaks-base}"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIST_PATH="${SRC_DIR}/${FLATPAK_LIST_FILE}"

if [[ ! -f "$LIST_PATH" ]]; then
  echo "ERROR: flatpaks list file not found: $LIST_PATH"
  ls -la "$SRC_DIR"
  exit 1
fi

# Configure Flathub remote (in case base image doesn't have it,
# though Bluefin DX does).
flatpak remote-add --if-not-exists --system flathub \
  https://dl.flathub.org/repo/flathub.flatpakrepo

echo "=== Installing $(grep -cv '^#\|^$' "$LIST_PATH") Flatpaks from $FLATPAK_LIST_FILE ==="
grep -v '^#\|^$' "$LIST_PATH"

# Install all apps in the list. --or-update tolerates already-installed
# entries (Bluefin DX's bazaar.preinstall may have pre-baked Bazaar at
# its own build time, into a different installation path — but if the
# install path collides, --or-update handles it). --noninteractive
# returns 0 even on partial failure; flatpak install logs the failures
# to stderr so the build log captures them, and the resulting
# /var/lib/flatpak has whatever did install.
flatpak install --system --noninteractive --or-update flathub \
  $(grep -v '^#\|^$' "$LIST_PATH")

echo "=== Installed app refs ==="
flatpak list --system --app --columns=application | sort
echo "=== /var/lib/flatpak size ==="
du -sh /var/lib/flatpak 2>/dev/null || true
