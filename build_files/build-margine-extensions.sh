#!/usr/bin/env bash
# Install GNOME Shell extensions that are NOT shipped by Bluefin DX
# directly into /usr/share/gnome-shell/extensions/, system-wide.
#
# Why this script exists (history note 2026-06-03):
#   Margine used to install o-tiling, hide-cursor (and search-light)
#   per-user at first login via margine-fedora-atomic's
#   scripts/install-user-extensions. That had three failure modes that
#   bit hard on fresh VM installs tested 2026-06-03:
#
#     1. Race: GDM autostart fired before flatpak-preinstall.service
#        had network priority, install-user-extensions sometimes never
#        ran or ran with a broken EGO/DNS query.
#     2. Shadow: search-light user-side install masked Bluefin's
#        already-shipped system version (`gnome-shell[…]: Extension
#        search-light@icedman.github.com already installed in
#        ~/.local/…, /usr/share/… will not be loaded`). The user-side
#        version was older than what the running GNOME Shell needed.
#     3. Silent failure: when one extension's metadata.json/shell-version
#        didn't match the running shell, GNOME silently disabled the
#        whole loader for that uuid, with no UI affordance for the user
#        to notice.
#
#   Bluefin and Bazzite solve this by baking every non-Fedora-repo
#   extension into /usr/share/gnome-shell/extensions/ at build time
#   (ublue-os/bluefin: build_files/shared/build-gnome-extensions.sh,
#   ublue-os/bazzite: build_files/build-gnome-extensions). This file
#   replicates that pattern.
#
# What we install here:
#   * o-tiling@oliwebd.github.com — auto-tiling, binary-tree split.
#     Margine's default tiling engine. Not on EGO; we pull the
#     versioned release zip from GitHub. Bluefin does not ship this.
#   * hide-cursor@elcste.com — Wayland-native auto-hide of the mouse
#     cursor on inactivity. EGO id 6727. Bluefin does not ship this.
#
# What we do NOT install here:
#   * search-light@icedman.github.com — Bluefin's
#     build-gnome-extensions.sh already installs it system-wide from
#     git master (newer than EGO release, supports GNOME 50). Adding
#     a second copy here would re-trigger the "shadow" bug.
#   * appindicator / bazaar / blur-my-shell / dash-to-dock /
#     gradia-integration / gsconnect / caffeine — all baked by Bluefin.
#
# Enablement: zz1-margine.gschema.override (in build.sh) already lists
# all 10 UUIDs in [org.gnome.shell] enabled-extensions, so once the
# files land here the extensions are active on first GDM login. No
# per-user install, no autostart, no race.
set -euo pipefail

log() { printf '[margine-extensions] %s\n' "$*"; }

EXT_DIR=/usr/share/gnome-shell/extensions

# Versions are pinned. Bumps go through a PR so the change is reviewable.
OTILING_VERSION="v2.8.8"
OTILING_URL="https://github.com/oliwebd/o-tiling/releases/download/${OTILING_VERSION}/o-tiling@oliwebd.github.com-${OTILING_VERSION}.zip"

# Hide Cursor is hosted only on EGO. We query its info endpoint to get
# the latest version_tag compatible with the GNOME Shell version that
# the BASE Bluefin DX layer ships — by the time this script runs,
# `gnome-shell --version` reflects the booted shell of that layer.
HIDECURSOR_UUID="hide-cursor@elcste.com"
HIDECURSOR_EGO_ID=6727

log "Installing transient deps (unzip + jq)"
# Important post-2026-06-03 lesson: glib-compile-schemas is in the
# glib2 RPM (always installed in Bluefin DX), NOT in glib2-devel.
# Earlier version of this script installed glib2-devel and then ran
# `dnf5 autoremove` to clean up. autoremove walked the dependency
# graph and found scx-scheds, kernel-cachyos and friends marked as
# orphans because their source COPR (bieszczaders/kernel-cachyos +
# kernel-cachyos-addons) was disabled and removed earlier in the
# build by custom-kernel/install.sh:283-286. autoremove dutifully
# stripped scx_lavd / scx_bpfland / etc, breaking gaming/install.sh's
# sanity check (`command -v scx_lavd → not found` → exit 1).
#
# Two fixes: (1) DON'T install glib2-devel — we don't need it. (2)
# DON'T autoremove — never. The base image is curated, we don't get
# to second-guess what's needed.
#
# curl: always present in Bluefin DX, no install.
# unzip + jq: not guaranteed, install transiently and remove with an
#   explicit `dnf5 remove`, never `autoremove`.
dnf5 -y install --setopt=install_weak_deps=False unzip jq

GNOME_SHELL_MAJOR="$(gnome-shell --version | awk '{print $3}' | cut -d. -f1)"
log "Running GNOME Shell major version: ${GNOME_SHELL_MAJOR}"

install_otiling() {
  local target="${EXT_DIR}/o-tiling@oliwebd.github.com"
  log "o-tiling ${OTILING_VERSION} → ${target}"
  rm -rf "${target}"
  mkdir -p "${target}"
  curl -fL --retry 5 --retry-delay 10 -o /tmp/otiling.zip "${OTILING_URL}"
  unzip -q -o /tmp/otiling.zip -d "${target}"
  rm -f /tmp/otiling.zip
  if [[ ! -f "${target}/metadata.json" ]]; then
    log "ERROR: ${target}/metadata.json missing after extraction"
    ls -la "${target}"
    exit 1
  fi
  if [[ -d "${target}/schemas" ]] && compgen -G "${target}/schemas/*.xml" > /dev/null; then
    glib-compile-schemas --strict "${target}/schemas"
  fi
}

install_hidecursor() {
  local target="${EXT_DIR}/${HIDECURSOR_UUID}"
  log "hide-cursor (EGO id ${HIDECURSOR_EGO_ID}) for shell ${GNOME_SHELL_MAJOR} → ${target}"

  local meta
  meta="$(curl -fsSL --retry 5 --retry-delay 10 \
    "https://extensions.gnome.org/extension-info/?uuid=${HIDECURSOR_UUID}&shell_version=${GNOME_SHELL_MAJOR}")"

  local version_tag
  version_tag="$(printf '%s' "${meta}" | jq -r '.version_tag // empty')"
  if [[ -z "${version_tag}" ]]; then
    log "ERROR: no EGO release of ${HIDECURSOR_UUID} for GNOME ${GNOME_SHELL_MAJOR}"
    log "EGO metadata reply: ${meta}"
    exit 1
  fi
  log "hide-cursor resolved to version_tag=${version_tag}"

  rm -rf "${target}"
  mkdir -p "${target}"
  curl -fL --retry 5 --retry-delay 10 \
    -o /tmp/hidecursor.zip \
    "https://extensions.gnome.org/download-extension/${HIDECURSOR_UUID}.shell-extension.zip?version_tag=${version_tag}"
  unzip -q -o /tmp/hidecursor.zip -d "${target}"
  rm -f /tmp/hidecursor.zip
  if [[ ! -f "${target}/metadata.json" ]]; then
    log "ERROR: ${target}/metadata.json missing after extraction"
    ls -la "${target}"
    exit 1
  fi
  if [[ -d "${target}/schemas" ]] && compgen -G "${target}/schemas/*.xml" > /dev/null; then
    glib-compile-schemas --strict "${target}/schemas"
  fi
}

install_otiling
install_hidecursor

log "Recompiling /usr/share/glib-2.0/schemas to pick up new extension schemas"
glib-compile-schemas /usr/share/glib-2.0/schemas

log "Final extension inventory under ${EXT_DIR}:"
ls -la "${EXT_DIR}/" | grep -v '^total' | awk '{print "  " $NF}' | sort

log "metadata.json for the two we just added (verify before stripping jq):"
for uuid in o-tiling@oliwebd.github.com hide-cursor@elcste.com; do
  if [[ -f "${EXT_DIR}/${uuid}/metadata.json" ]]; then
    printf '  %s: ' "${uuid}"
    jq -r '"name=\(.name) shell-version=\(.["shell-version"] | join(","))"' \
      "${EXT_DIR}/${uuid}/metadata.json" 2>/dev/null || cat "${EXT_DIR}/${uuid}/metadata.json"
  else
    printf '  %s: MISSING\n' "${uuid}"
    exit 1
  fi
done

log "Removing transient deps (only unzip + jq, NEVER autoremove)"
# NO `dnf5 -y autoremove` here. autoremove walks the dependency
# graph and "orphans" packages whose declared source repo is gone.
# Our base build disables the kernel-cachyos / kernel-cachyos-addons
# COPRs after install (see custom-kernel/install.sh end-of-script).
# autoremove would happily strip kernel-cachyos / scx-scheds / etc
# — exactly what bit us in build #26913265617 (gaming sanity check:
# `command -v scx_lavd → not found`). Just remove the names we
# installed, nothing more.
dnf5 -y remove jq unzip || true
