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

# NO transient dnf installs. Lesson learned the hard way 2026-06-04
# (build #26918323253 + #26913265617):
#
# Earlier versions of this script did:
#   dnf5 -y install unzip jq glib2-devel
#   ...
#   dnf5 -y remove unzip jq glib2-devel
#   dnf5 -y autoremove                  # PR #20 — removed scx-scheds
#
# Three independent ways this broke scx-scheds:
#  1. autoremove (PR #20) — fixed by PR #22, removed the autoremove call.
#  2. `dnf5 remove jq` (PR #22 attempt) — STILL broke things, because
#     scx-tools-git (installed as a sibling of scx-scheds by the
#     kernel-cachyos-addons COPR) declares `Requires: jq`. So removing
#     jq cascades through scx-tools-git → scx-scheds → 16 packages.
#  3. unzip: smaller blast radius but same class of problem.
#
# Robust fix: don't add or remove dnf packages here at all. Use
# Python stdlib (always present) for JSON parsing + zip extraction.
# Schema compilation uses glib-compile-schemas (from glib2, always
# present). curl is always present. Zero dnf operations in this
# script.
log "No dnf installs — script uses only python3 + glib-compile-schemas + curl (all stock)"

GNOME_SHELL_MAJOR="$(gnome-shell --version | awk '{print $3}' | cut -d. -f1)"
log "Running GNOME Shell major version: ${GNOME_SHELL_MAJOR}"

extract_zip() {
  # python3 zipfile is in stdlib — always present, no dnf install.
  local zipfile="$1" target="$2"
  python3 -c "
import zipfile, sys
zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])
" "$zipfile" "$target"
}

install_otiling() {
  local target="${EXT_DIR}/o-tiling@oliwebd.github.com"
  log "o-tiling ${OTILING_VERSION} → ${target}"
  rm -rf "${target}"
  mkdir -p "${target}"
  curl -fL --retry 5 --retry-delay 10 -o /tmp/otiling.zip "${OTILING_URL}"
  extract_zip /tmp/otiling.zip "${target}"
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

  local version_tag
  version_tag="$(curl -fsSL --retry 5 --retry-delay 10 \
    "https://extensions.gnome.org/extension-info/?uuid=${HIDECURSOR_UUID}&shell_version=${GNOME_SHELL_MAJOR}" \
    | python3 -c 'import json,sys; d=json.loads(sys.stdin.read()); print(d.get("version_tag",""))')"
  if [[ -z "${version_tag}" ]]; then
    log "ERROR: no EGO release of ${HIDECURSOR_UUID} for GNOME ${GNOME_SHELL_MAJOR}"
    exit 1
  fi
  log "hide-cursor resolved to version_tag=${version_tag}"

  rm -rf "${target}"
  mkdir -p "${target}"
  curl -fL --retry 5 --retry-delay 10 \
    -o /tmp/hidecursor.zip \
    "https://extensions.gnome.org/download-extension/${HIDECURSOR_UUID}.shell-extension.zip?version_tag=${version_tag}"
  extract_zip /tmp/hidecursor.zip "${target}"
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

log "metadata.json for the two we just added:"
for uuid in o-tiling@oliwebd.github.com hide-cursor@elcste.com; do
  if [[ -f "${EXT_DIR}/${uuid}/metadata.json" ]]; then
    printf '  %s: ' "${uuid}"
    python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
print(f'name={d.get(\"name\",\"?\")} shell-version={\",\".join(map(str, d.get(\"shell-version\", [])))}')
" "${EXT_DIR}/${uuid}/metadata.json"
  else
    printf '  %s: MISSING\n' "${uuid}"
    exit 1
  fi
done

log "Done. No dnf operations to clean up — script never installed anything."

# ---------------------------------------------------------------------------
# Downstream patch: search-light unrealize-while-mapped crash (2026-06-10).
#
# search-light v101 (baked by the Bluefin base, git master) crashes the
# whole shell with SIGABRT when an app is launched from the search
# overlay under GNOME 50:
#   Clutter:ERROR:clutter-actor.c:1989:clutter_actor_real_unrealize:
#     assertion failed: (!clutter_actor_is_mapped (self))
#   JS stack: extension.js:755 (_release_ui) -> 495 (hide) -> 1012
# _release_ui() remove_child()s the entry while the overlay is still
# mapped; Clutter 18's stricter unrealize asserts abort. Reproduced on
# the reference host (coredump 2026-06-10 22:31, journal-verified); on
# Wayland this kills the session and trips GNOME's crash protection
# (disable-user-extensions=true). Upstream has similar open reports
# (icedman/search-light #82, #133) and no fix as of v101.
#
# One-line mitigation: hide() (= unmap) the entry before detaching it,
# so the remove_child never runs on a mapped actor. Visually
# imperceptible (one frame before the fade). Idempotent + soft-fail:
# if Bluefin bumps search-light and the code changes, we log and move
# on rather than failing the build — the patch is a mitigation, not a
# load-bearing feature.
SEARCH_LIGHT_EXT="${EXT_DIR}/search-light@icedman.github.com/extension.js"
if [[ -f "$SEARCH_LIGHT_EXT" ]]; then
  if grep -q 'this._entry.hide(); // margine: unmap before detach' "$SEARCH_LIGHT_EXT"; then
    log "search-light unrealize patch already present"
  elif python3 - "$SEARCH_LIGHT_EXT" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p).read()
# Only the _release_ui() occurrence (the crash site), NOT the show-path one.
old = """  _release_ui() {
    if (this._entry) {
      if (this._entry.get_parent()) {
        this._entry.get_parent().remove_child(this._entry);"""
new = """  _release_ui() {
    if (this._entry) {
      if (this._entry.get_parent()) {
        this._entry.hide(); // margine: unmap before detach (Clutter 18 unrealize assert)
        this._entry.get_parent().remove_child(this._entry);"""
if old not in s:
    sys.exit(1)
open(p, "w").write(s.replace(old, new, 1))
PYEOF
  then
    log "search-light: applied unrealize-while-mapped mitigation (_release_ui)"
  else
    # HARD FAIL (was a soft WARN until 2026-06-12). The mitigation is
    # load-bearing: without it, launching an app from the overlay
    # SIGABRTs the whole shell (Wayland = session gone). A soft-fail
    # here means shipping a crasher and finding out from a user — if
    # upstream changes the code, the build must stop until the patch
    # is re-evaluated. Belt+braces: build.yml Layer A also asserts the
    # patch marker on the final image.
    log "ERROR: search-light _release_ui pattern not found (upstream changed?) — refusing to ship unpatched"
    exit 1
  fi
else
  log "ERROR: search-light extension.js not found — the patch target is gone, refusing to guess"
  exit 1
fi
