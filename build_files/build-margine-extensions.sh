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
# all 11 UUIDs in [org.gnome.shell] enabled-extensions, so once the
# files land here the extensions are active on first GDM login. No
# per-user install, no autostart, no race.
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
OTILING_VERSION="v2.8.17"
OTILING_URL="https://github.com/oliwebd/o-tiling/releases/download/${OTILING_VERSION}/o-tiling@oliwebd.github.com-${OTILING_VERSION}.zip"
OTILING_SHA256="03293a9dfd14a513f8f05e4efc0c7d3ac4fb863245d2d83f77c72e128c52124e"

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
  curl -fL --retry 5 --retry-delay 10 -o /tmp/otiling.zip "${OTILING_URL}"
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
  curl -fL --retry 5 --retry-delay 10 \
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
#   search-light  panel button            search-symbolic
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
  [search-symbolic]=system-search-symbolic        # search-light magnifier
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
  curl -fL --retry 5 --retry-delay 10 \
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

# ---------------------------------------------------------------------------
# Downstream patch #2: search-light press-gesture SIGABRT (2026-06-13).
#
# Clicking the panel button crashes the whole shell under GNOME 50:
#   Clutter:ERROR:clutter-gesture.c:544:set_state:
#     assertion failed: (new_state == CLUTTER_GESTURE_STATE_POSSIBLE)
#   #  clutter_press_gesture_point_began -> clutter_gesture_handle_event
# The 'button-press-event' handler calls _toggle_search_light() -> show()
# SYNCHRONOUSLY inside the Clutter 18 press gesture; show() reparents the
# entry/search actors, grabs key focus and connects global stage events,
# which corrupts the in-flight gesture's state machine. The next gesture
# point event then asserts and SIGABRTs. On Wayland that kills the session
# and, after a couple of crashes, GNOME trips safe-mode (all extensions
# off). Reproduced on the reference host (coredump 2026-06-13 14:28,
# journal-verified). This is the "show-path" sibling of patch #1 above,
# which only covered the app-launch (_release_ui) path.
#
# Mitigation: defer the toggle out of the gesture's call stack with
# GLib.idle_add (GLib + Clutter are already imported), so the press
# gesture finishes cleanly before any actor surgery runs. Imperceptible
# (one idle tick). Same hard-fail-if-pattern-missing contract as #1: this
# crash is load-bearing (it ends the session), so a future upstream rename
# must stop the build, not ship a crasher. Layer A asserts the marker too.
if [[ -f "$SEARCH_LIGHT_EXT" ]]; then
  if grep -q 'margine: defer the toggle out of the' "$SEARCH_LIGHT_EXT"; then
    log "search-light press-gesture patch already present"
  elif python3 - "$SEARCH_LIGHT_EXT" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p).read()
old = """    this._indicator.connectObject(
      'button-press-event',
      this._toggle_search_light.bind(this),
      this,
    );"""
new = """    this._indicator.connectObject(
      'button-press-event',
      () => {
        // margine: defer the toggle out of the Clutter 18 press-gesture
        // handler. Running show()/actor-reparent synchronously here
        // corrupts the gesture state machine and SIGABRTs the session.
        GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, () => {
          this._toggle_search_light();
          return GLib.SOURCE_REMOVE;
        });
        return Clutter.EVENT_STOP;
      },
      this,
    );"""
if old not in s:
    sys.exit(1)
open(p, "w").write(s.replace(old, new, 1))
PYEOF
  then
    log "search-light: applied press-gesture mitigation (deferred button-press toggle)"
  else
    log "ERROR: search-light button-press connectObject pattern not found (upstream changed?) — refusing to ship unpatched"
    exit 1
  fi
else
  log "ERROR: search-light extension.js not found — the patch target is gone, refusing to guess"
  exit 1
fi

# ---------------------------------------------------------------------------
# Downstream patch #3: search-light hide() re-entrancy SIGABRT (2026-06-13).
#
# Pressing the search shortcut (e.g. Super+Space) crashes the whole shell:
#   clutter_actor_set_mapped: assertion '!CLUTTER_ACTOR_IN_MAP_UNMAP' failed
#   Clutter:ERROR clutter-actor.c:1989:clutter_actor_real_unrealize:
#     assertion failed: (!clutter_actor_is_mapped (self))
#   JS: _release_ui -> hide -> _release_ui (re-entrant)
# Root cause (coredump JS stack, 2026-06-13 19:00): hide() -> _release_ui()
# -> this._entry.hide() (added by patch #1) flips the stage key-focus, which
# fires _onKeyFocusChanged -> this.hide() AGAIN, re-entering _release_ui()
# while the first teardown is still mid-unmap -> remove_child on an actor in
# the MAP_UNMAP state aborts. This is a DISTINCT crash from #1 (detach order)
# and #2 (press gesture); it is reached from the keyboard accelerator path,
# which #2's button-press deferral does not cover.
#
# Fix: a re-entrancy guard on hide() so the recursive hide() (from the
# focus change during _release_ui) is a no-op and teardown runs exactly
# once. The guard is cleared right after the synchronous teardown so a
# later real hide() still works and an exception in the async fade can't
# wedge it. Load-bearing (the crash ends the session) -> hard-fail if the
# upstream shape changed; Layer A asserts the marker on the final image.
if [[ -f "$SEARCH_LIGHT_EXT" ]]; then
  if grep -q 'margine: re-entrancy guard' "$SEARCH_LIGHT_EXT"; then
    log "search-light hide() re-entrancy guard already present"
  elif python3 - "$SEARCH_LIGHT_EXT" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p).read()
old = """  hide() {
    if (this._isDraggingIcon()) {
      return;
    }

    this._release_ui();
    this._remove_events();"""
new = """  hide() {
    if (this._isDraggingIcon()) {
      return;
    }
    // margine: re-entrancy guard. _release_ui() hides the entry, which
    // flips stage key-focus -> _onKeyFocusChanged -> hide() again, re-
    // entering teardown mid-unmap -> Clutter unrealize-while-mapped
    // SIGABRT (clutter_actor_real_unrealize). Make the re-entrant hide()
    // a no-op so teardown runs exactly once.
    if (this._hiding) {
      return;
    }
    this._hiding = true;

    this._release_ui();
    this._remove_events();
    this._hiding = false;"""
if old not in s:
    sys.exit(1)
open(p, "w").write(s.replace(old, new, 1))
PYEOF
  then
    log "search-light: applied hide() re-entrancy guard"
  else
    log "ERROR: search-light hide() pattern not found (upstream changed?) — refusing to ship unpatched"
    exit 1
  fi
else
  log "ERROR: search-light extension.js not found — the patch target is gone, refusing to guess"
  exit 1
fi

# ---------------------------------------------------------------------------
# Downstream patch #4: defer ALL show/hide triggers off input/gesture context
# (holistic fix for the GNOME 50 / Clutter 18 session crashes, 2026-06-14).
#
# Patches #1/#2/#3 fixed three specific crash paths, but a FOURTH remained:
# the keyboard shortcut (Super+Space) runs _toggle_search_light -> show()/
# _acquire_ui() which reparents (add_child/remove_child) and grabs key focus
# SYNCHRONOUSLY while a Clutter press gesture is in flight on the stage:
#   clutter-gesture.c:544 set_state: assertion (new_state == POSSIBLE)
#   clutter_press_gesture_point_began <- clutter_stage_process_event
# Root theme across all four coredumps: search-light mutates the actor tree
# synchronously inside event/gesture/signal handlers, from many triggers
# (panel button [deferred by #2], the two keyboard accelerators, and the
# notify::key-focus / Escape / in-fullscreen-changed hide handlers).
#
# Holistic fix: defer every EVENT-CONTEXT entry into show()/hide() by ONE
# GLib idle tick, so the actor surgery runs off the gesture FSM and outside
# input dispatch — neither set_state nor unrealize-while-mapped can fire.
# show()/hide()/_toggle_search_light/_visible are left BYTE-FOR-BYTE unchanged
# (no new state machine -> the overlay can never get stuck shown/hidden);
# only the five callers are wrapped. Load-bearing (each crash ends the
# session) -> hard-fail if any of the five 'old' strings is missing; Layer A
# asserts the marker on the final image.
if [[ -f "$SEARCH_LIGHT_EXT" ]]; then
  if grep -q 'margine: defer off input/gesture context' "$SEARCH_LIGHT_EXT"; then
    log "search-light input-context deferral already present"
  elif python3 - "$SEARCH_LIGHT_EXT" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p).read()
M = "// margine: defer off input/gesture context (Clutter 18 set_state / unrealize)"
subs = [
    ("      this.accel.listenFor(shortcut, this._toggle_search_light.bind(this));",
     "      this.accel.listenFor(shortcut, () => {\n        %s\n        GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, () => {\n          this._toggle_search_light();\n          return GLib.SOURCE_REMOVE;\n        });\n      });" % M),
    ("      this.accel2.listenFor(shortcut, this._toggle_search_light.bind(this));",
     "      this.accel2.listenFor(shortcut, () => {\n        %s\n        GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, () => {\n          this._toggle_search_light();\n          return GLib.SOURCE_REMOVE;\n        });\n      });" % M),
    ("        this._hidePopups();\n      }\n\n      this.hide();",
     "        this._hidePopups();\n      }\n\n      %s\n      GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, () => {\n        this.hide();\n        return GLib.SOURCE_REMOVE;\n      });" % M),
    ("      if (evt.get_key_symbol() === Clutter.KEY_Escape) {\n        this.hide();\n        return Clutter.EVENT_STOP;",
     "      if (evt.get_key_symbol() === Clutter.KEY_Escape) {\n        %s\n        GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, () => {\n          this.hide();\n          return GLib.SOURCE_REMOVE;\n        });\n        return Clutter.EVENT_STOP;" % M),
    ("  _onFullScreen() {\n    this.hide();\n  }",
     "  _onFullScreen() {\n    %s\n    GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, () => {\n      this.hide();\n      return GLib.SOURCE_REMOVE;\n    });\n  }" % M),
]
for old, new in subs:
    if old not in s:
        sys.exit(1)
    s = s.replace(old, new, 1)
open(p, "w").write(s)
PYEOF
  then
    log "search-light: deferred all show/hide triggers off input/gesture context"
  else
    log "ERROR: search-light trigger patterns not found (upstream changed?) — refusing to ship unpatched"
    exit 1
  fi
else
  log "ERROR: search-light extension.js not found — the patch target is gone, refusing to guess"
  exit 1
fi

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
# chord floats/tiles for the current session with no dconf drift. Same hard-
# fail-if-pattern-missing contract as the search-light patches above —
# o-tiling is a core Margine feature, so a future upstream rename must STOP
# the build for re-evaluation, never silently ship the foot-gun.
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
