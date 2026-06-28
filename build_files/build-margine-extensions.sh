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
#     Margine's default tiling engine. Now also on EGO (pk 9875; it was
#     NOT when this script was first written, ~2026-06-03), but we keep
#     pulling the versioned release zip from GitHub on purpose: it lets
#     us pin an EXACT upstream release + verify its sha256. Upstream ships
#     the release on GitHub first, whereas EGO serves "latest approved for
#     your shell", which lags review and changes over time. (We could
#     switch to EGO's download-extension API with a pinned version_tag, as
#     hide-cursor/smile below do — same pin+sha guarantee — but there's no
#     gain; GitHub gives the exact upstream version we patch downstream.)
#     Bluefin does not ship this.
#   * hide-cursor@elcste.com — Wayland-native auto-hide of the mouse
#     cursor on inactivity. EGO id 6727. Bluefin does not ship this.
#
# What we do NOT install here (baked by Bluefin's build-gnome-extensions.sh):
#   * appindicator / bazaar / dash-to-dock / gradia-integration / gsconnect /
#     caffeine — kept, enabled via the zz1 override.
#   * search-light / blur-my-shell / logomenu — REMOVED below (the "remove
#     Bluefin-baked extensions Margine doesn't ship" block): GNOME-50 crash
#     class, 120Hz-iGPU blur jank, and unused branding respectively.
#
# Enablement: zz1-margine.gschema.override (in 30-gnome-defaults) lists the
# enabled UUIDs in [org.gnome.shell] enabled-extensions, so once the files
# land here the extensions are active on first GDM login. No per-user install,
# no autostart, no race.
set -euo pipefail

log() { printf '[margine-extensions] %s\n' "$*"; }

EXT_DIR=/usr/share/gnome-shell/extensions

# Versions are pinned AND checksummed. Bumps go through a PR so the
# change is reviewable; a re-tagged release or a tampered download
# fails the sha256 check instead of shipping silently (review P2.4 —
# hide-cursor used to resolve "latest from EGO" at every build, and
# neither zip was verified).
# v2.8.8 → v2.8.17 (2026-06-14): 2.8.8 had a GNOME-50 re-entrancy bug
# (oliwebd/o-tiling#15) where toggling auto-tiling off programmatically
# re-fired the "Enable extension" switch callback → ext_soft_disable() →
# stripped its own keybindings, so the toggle worked once then went dead
# (switch moved, top-bar icon + windows frozen). Fixed in 2.8.11 via an
# _indicator_updating guard; 2.8.17 is the current release. Schema keys
# Margine overrides in 03-margine-o-tiling are unchanged in 2.8.17.
OTILING_VERSION="v2.9.5"
OTILING_URL="https://github.com/oliwebd/o-tiling/releases/download/${OTILING_VERSION}/o-tiling@oliwebd.github.com-${OTILING_VERSION}.zip"
OTILING_SHA256="0c4066f7e9af46e71c4db8105df0b8689c50d20d381466a76a3f469a2da0af7d"

# Hide Cursor is hosted only on EGO. version_tag pinned for the GNOME
# Shell major of the current base (50). When Bluefin bumps GNOME, the
# metadata shell-version guard below fails the build with instructions
# instead of shipping an incompatible extension.
HIDECURSOR_UUID="hide-cursor@elcste.com"
HIDECURSOR_VERSION_TAG="69559"   # GNOME 50; resolved 2026-06-12
HIDECURSOR_SHA256="2fd9ffdaf176d2fba6f998c453ce91908d7e134b841a8e25d35389b60c7b1379"

# Smile's companion GNOME Shell extension — the piece that makes the Smile
# emoji picker (the it.mijorus.smile Flatpak, already preinstalled and bound to
# <Super>period) auto-INSERT the chosen emoji into the focused field on Wayland
# (Windows Win+. behaviour). On Wayland the Flatpak signals this extension over
# D-Bus and the extension synthesises Ctrl+V via a Clutter virtual keyboard —
# no ydotool/uinput, no extra socket. Hosted only on EGO; version_tag pinned
# for GNOME 50 (the metadata shell-version guard below fails the build on a
# GNOME bump instead of shipping an incompatible extension).
SMILE_EXT_UUID="smile-extension@mijorus.it"
SMILE_EXT_VERSION_TAG="70078"   # EGO v13, GNOME 50; resolved 2026-06-14
SMILE_EXT_SHA256="e23cf17f1216c099215c6b458e96913f277a371bc770759ca56b858d98651b42"

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

verify_sha256() {
  local file="$1" expected="$2"
  echo "${expected}  ${file}" | sha256sum -c - >/dev/null \
    || { log "ERROR: sha256 mismatch for ${file} (expected ${expected}) — upstream re-tagged or download corrupted; verify manually and bump the pin"; exit 1; }
  log "sha256 OK: ${file}"
}

assert_shell_compat() {
  # The pinned zip must declare support for the base image's GNOME
  # Shell major, or the extension would silently never load.
  local target="$1"
  python3 -c '
import json, sys
md = json.load(open(sys.argv[1]))
want = sys.argv[2]
vers = [str(v).split(".")[0] for v in md.get("shell-version", [])]
sys.exit(0 if want in vers else 1)
' "${target}/metadata.json" "${GNOME_SHELL_MAJOR}" \
    || { log "ERROR: ${target} pinned version does not list GNOME ${GNOME_SHELL_MAJOR} in shell-version — base bumped GNOME; bump the extension pin"; exit 1; }
}

install_otiling() {
  local target="${EXT_DIR}/o-tiling@oliwebd.github.com"
  log "o-tiling ${OTILING_VERSION} → ${target}"
  rm -rf "${target}"
  mkdir -p "${target}"
  curl -fL --retry 5 --retry-all-errors --retry-delay 10 -o /tmp/otiling.zip "${OTILING_URL}"
  verify_sha256 /tmp/otiling.zip "${OTILING_SHA256}"
  extract_zip /tmp/otiling.zip "${target}"
  rm -f /tmp/otiling.zip
  if [[ ! -f "${target}/metadata.json" ]]; then
    log "ERROR: ${target}/metadata.json missing after extraction"
    ls -la "${target}"
    exit 1
  fi
  assert_shell_compat "${target}"
  if [[ -d "${target}/schemas" ]] && compgen -G "${target}/schemas/*.xml" > /dev/null; then
    glib-compile-schemas --strict "${target}/schemas"
  fi
}

install_hidecursor() {
  local target="${EXT_DIR}/${HIDECURSOR_UUID}"
  log "hide-cursor (pinned version_tag ${HIDECURSOR_VERSION_TAG}) for shell ${GNOME_SHELL_MAJOR} → ${target}"

  rm -rf "${target}"
  mkdir -p "${target}"
  curl -fL --retry 5 --retry-all-errors --retry-delay 10 \
    -o /tmp/hidecursor.zip \
    "https://extensions.gnome.org/download-extension/${HIDECURSOR_UUID}.shell-extension.zip?version_tag=${HIDECURSOR_VERSION_TAG}"
  verify_sha256 /tmp/hidecursor.zip "${HIDECURSOR_SHA256}"
  extract_zip /tmp/hidecursor.zip "${target}"
  rm -f /tmp/hidecursor.zip
  if [[ ! -f "${target}/metadata.json" ]]; then
    log "ERROR: ${target}/metadata.json missing after extraction"
    ls -la "${target}"
    exit 1
  fi
  assert_shell_compat "${target}"
  if [[ -d "${target}/schemas" ]] && compgen -G "${target}/schemas/*.xml" > /dev/null; then
    glib-compile-schemas --strict "${target}/schemas"
  fi
}

# ---------------------------------------------------------------------------
# Legacy icon-name compat shims for the baked extensions (2026-06-13).
#
# adwaita-icon-theme 50 dropped several long-standing symbolic icon names
# that third-party extensions still reference BY NAME. On Margine the
# affected menu/panel items render as the broken-image placeholder.
# Reported (icons confirmed absent from Adwaita 50):
#   o-tiling      "Tile This Workspace"  view-quilt-symbolic (on)
#                                         view-compact-symbolic (off)
#   o-tiling      "Border Width"          border-all-symbolic
#
# Rather than sed-patch each extension's JS (fragile across upstream bumps,
# and it would only fix OUR baked set), provide the removed names as compat
# aliases in the theme-agnostic hicolor fallback path, each copied from the
# closest existing Adwaita symbolic. Because they are byte-for-byte real
# Adwaita symbolics under a legacy name, they recolor exactly like native
# ones, and ANY app/extension referencing these names is fixed — not just
# o-tiling/search-light. Cosmetic: a vanished source warns and skips
# rather than failing the build.
declare -A ICON_SHIMS=(
  [view-quilt-symbolic]=view-grid-symbolic        # tiling ON  (tiled grid)
  [view-compact-symbolic]=view-restore-symbolic   # tiling OFF (floating/overlap)
  [border-all-symbolic]=checkbox-symbolic         # border width (bordered box)
  [view-column-symbolic]=view-dual-symbolic       # o-tiling "Columns" preset (absent from Adwaita 50)
)
install_legacy_icon_shims() {
  local dst=/usr/share/icons/hicolor/scalable/actions
  mkdir -p "$dst"
  local missing src srcpath
  for missing in "${!ICON_SHIMS[@]}"; do
    src="${ICON_SHIMS[$missing]}"
    srcpath="$(find /usr/share/icons/Adwaita -name "${src}.svg" 2>/dev/null | head -1)"
    if [[ -z "$srcpath" ]]; then
      log "WARN: icon-shim source ${src}.svg absent from Adwaita — ${missing} stays a placeholder"
      continue
    fi
    install -m 0644 "$srcpath" "${dst}/${missing}.svg"
    log "icon-shim: ${missing} <- ${src} ($(basename "$(dirname "$srcpath")"))"
  done
  gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor 2>/dev/null || true
}

install_smile_ext() {
  local target="${EXT_DIR}/${SMILE_EXT_UUID}"
  log "smile complementary extension (pinned version_tag ${SMILE_EXT_VERSION_TAG}) for shell ${GNOME_SHELL_MAJOR} → ${target}"

  rm -rf "${target}"
  mkdir -p "${target}"
  curl -fL --retry 5 --retry-all-errors --retry-delay 10 \
    -o /tmp/smile-ext.zip \
    "https://extensions.gnome.org/download-extension/${SMILE_EXT_UUID}.shell-extension.zip?version_tag=${SMILE_EXT_VERSION_TAG}"
  verify_sha256 /tmp/smile-ext.zip "${SMILE_EXT_SHA256}"
  extract_zip /tmp/smile-ext.zip "${target}"
  rm -f /tmp/smile-ext.zip
  if [[ ! -f "${target}/metadata.json" ]]; then
    log "ERROR: ${target}/metadata.json missing after extraction"
    ls -la "${target}"
    exit 1
  fi
  assert_shell_compat "${target}"
  if [[ -d "${target}/schemas" ]] && compgen -G "${target}/schemas/*.xml" > /dev/null; then
    glib-compile-schemas --strict "${target}/schemas"
  fi
}

# ---------------------------------------------------------------------------
# Remove Bluefin-baked extensions Margine does not ship (2026-06-16).
# ---------------------------------------------------------------------------
# Bluefin's build-gnome-extensions.sh bakes these into the base image as plain
# dirs under EXT_DIR (not RPM-owned). Margine doesn't enable them and no longer
# ships them at all: blur-my-shell (per-frame dynamic blur janks the 120Hz
# HiDPI iGPU + unfixed GNOME-50 bugs), search-light (GNOME-50 crash class;
# GNOME-native overview/app-grid search replaces it), logomenu (branding we
# don't use). Removing the dirs is the clean fix — their dconf defaults,
# downstream patches, icon shims and validator/smoke references are all dropped
# alongside this. A user who wants one back installs it from extensions.gnome.org.
for _unwanted in blur-my-shell@aunetx logomenu@aryan_k search-light@icedman.github.com; do
  if [[ -d "${EXT_DIR}/${_unwanted}" ]]; then
    rm -rf "${EXT_DIR:?}/${_unwanted}"
    log "removed Bluefin-baked extension Margine doesn't ship: ${_unwanted}"
  fi
done

install_otiling
install_hidecursor
install_smile_ext
install_legacy_icon_shims

log "Recompiling /usr/share/glib-2.0/schemas to pick up new extension schemas"
glib-compile-schemas /usr/share/glib-2.0/schemas

log "Final extension inventory under ${EXT_DIR}:"
for d in "${EXT_DIR}"/*/; do echo "  $(basename "$d")"; done | sort

log "metadata.json for the three we just added:"
for uuid in o-tiling@oliwebd.github.com hide-cursor@elcste.com smile-extension@mijorus.it; do
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
# Downstream patch: o-tiling toggle is SESSION-ONLY (2026-06-15).
#
# o-tiling's toggle-tiling keybinding (Super+Shift+t -> ext.toggle_tiling())
# calls auto_tile_off()/auto_tile_on() with the default save_setting=TRUE, so
# every keypress WRITES tile-by-default into the USER dconf layer. That value
# then MASKS Margine's distro default (30-gnome-defaults/dconf/03-margine-o-
# tiling sets tile-by-default=true) permanently: once a user toggles off,
# tiling stays off across every future login, and any later change to the
# Margine default silently never applies. Confirmed on the reference host
# 2026-06-15 — live `dconf read /org/gnome/shell/extensions/o-tiling/tile-by-
# default` was `false`, masking the distro `true`. (This is why the recurring
# "toggle doesn't switch" report survived the 2.8.8->2.8.17 bump AND the
# schema-registration fix: a stale USER-LEVEL copy under
# ~/.local/share/gnome-shell/extensions/ shadows this system copy, so none of
# our system-side fixes ever loaded. The prune for that lives in
# scripts/install-user-extensions, removed_user_install.)
#
# o-tiling already ships the no-persist overloads auto_tile_off(false)/
# auto_tile_on(false) — it uses them itself on its own enable path
# (extension.js:2574-2575). Point the keybinding at them so the toggle is
# SESSION-ONLY: every login starts at the Margine default (tiled), and the
# chord floats/tiles for the current session with no dconf drift. Hard-fails
# the build if the upstream pattern changes — o-tiling is a core Margine
# feature, so a future upstream rename must STOP the build for re-evaluation,
# never silently ship the foot-gun.
OTILING_EXT="${EXT_DIR}/o-tiling@oliwebd.github.com/extension.js"
if [[ -f "$OTILING_EXT" ]]; then
  if grep -q 'margine: session-only toggle' "$OTILING_EXT"; then
    log "o-tiling session-only toggle patch already present"
  elif python3 - "$OTILING_EXT" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p).read()
old = """    toggle_tiling() {
        if (this.auto_tiler !== null) {
            this.auto_tile_off();
        }
        else {
            this.auto_tile_on();
        }
    }"""
new = """    toggle_tiling() {
        // margine: session-only toggle — pass save_setting=false so the chord
        // never persists tile-by-default into the user dconf layer (which
        // would mask Margine's distro default permanently). Login state always
        // follows the distro default; the toggle floats/tiles for this session.
        if (this.auto_tiler !== null) {
            this.auto_tile_off(false);
        }
        else {
            this.auto_tile_on(false);
        }
    }"""
if old not in s:
    sys.exit(1)
open(p, "w").write(s.replace(old, new, 1))
PYEOF
  then
    log "o-tiling: toggle is now session-only (no tile-by-default dconf persistence)"
  else
    log "ERROR: o-tiling toggle_tiling pattern not found (upstream changed?) — refusing to ship unpatched"
    exit 1
  fi
else
  log "ERROR: o-tiling extension.js not found — the patch target is gone, refusing to guess"
  exit 1
fi

# ---------------------------------------------------------------------------
# Register our extensions' gschemas into the GLOBAL schema set.
# ---------------------------------------------------------------------------
# build.sh's 30-gnome-defaults stage copies + compiles the global schema set,
# but it runs BEFORE this script (Containerfile order: build.sh, then this),
# so the schemas of the extensions WE install here (o-tiling, hide-cursor,
# smile) never reach /usr/share/glib-2.0/schemas/. Without that the schema is
# not registered system-wide and `gsettings get/set
# org.gnome.shell.extensions.<ext> ...` fails — the extension still reads its
# own local compiled schema at runtime, but the user bootstrap + diagnostics
# that go through gsettings cannot. Copy ours over now and recompile.
# (Found 2026-06-15: o-tiling schema unregistered on a live host.)
log "Registering Margine extension gschemas into the global schema set"
shopt -s nullglob
for uuid in o-tiling@oliwebd.github.com hide-cursor@elcste.com smile-extension@mijorus.it; do
  for xml in "/usr/share/gnome-shell/extensions/${uuid}/schemas/"*.gschema.xml; do
    base="$(basename "$xml")"
    if [[ ! -f "/usr/share/glib-2.0/schemas/${base}" ]]; then
      install -m 0644 "$xml" "/usr/share/glib-2.0/schemas/${base}"
      log "  copied ${base} (from ${uuid})"
    fi
  done
done
glib-compile-schemas /usr/share/glib-2.0/schemas
log "Global gschema recompile done"
