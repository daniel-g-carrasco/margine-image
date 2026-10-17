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

# Same SOURCE_DATE_EPOCH as 00-common.sh (this script does not source it):
# the dnf transaction below must record the same install time as the
# other steps, or the rpmdb differs between identical builds.
if [[ -z "${SOURCE_DATE_EPOCH:-}" ]]; then
  SOURCE_DATE_EPOCH="$(rpm -qa --qf '%{INSTALLTIME}\n' 2>/dev/null | sort -n | tail -n1)"
  [[ "$SOURCE_DATE_EPOCH" =~ ^[0-9]+$ ]] && export SOURCE_DATE_EPOCH || unset SOURCE_DATE_EPOCH
fi

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
# 2.11.03 (2026-09-11) carries the upstream answer to the unlock
# workspace shift: the BSP reconstruction now skips maximized and
# fullscreen windows (oliwebd/o-tiling#89). Every Margine patch below
# still applies cleanly; the session-modes one stays until the upstream
# fix has been proven on real lock/unlock cycles.
OTILING_VERSION="v2.12.01"
OTILING_URL="https://github.com/oliwebd/o-tiling/releases/download/${OTILING_VERSION}/o-tiling@oliwebd.github.com-${OTILING_VERSION}.zip"
OTILING_SHA256="4bc13ee298ac8be6b3ff22e961b1f0948998bb10f1ddae5c3dead45aff4875a0"

# Hide Cursor is hosted only on EGO. version_tag pinned for the GNOME
# Shell major of the current base (51). When the base bumps GNOME, the
# metadata shell-version guard below fails the build with instructions
# instead of shipping an incompatible extension.
HIDECURSOR_UUID="hide-cursor@elcste.com"
HIDECURSOR_VERSION_TAG="75517"   # GNOME 51 (v15); resolved 2026-10-16 for the Fedora 45 base
HIDECURSOR_SHA256="6c0e2013a52ce42bd0cd49a566c6feadc10a1b7bdf5c973bf717832007cbe808"

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
# Caffeine comes from Fedora (15-devstack installs the package). When
# Fedora's build lags the GNOME major of the base (Fedora 45 shipped 60,
# GNOME 45-50, while upstream 61 handles 51's scroll and menu changes),
# install_caffeine_fallback swaps in this EGO build; once Fedora's package
# declares the running GNOME, the package stays and this pin goes unused.
CAFFEINE_UUID="caffeine@patapon.info"
CAFFEINE_VERSION_TAG="76057"   # v61, GNOME 45-51; resolved 2026-10-17
CAFFEINE_SHA256="3ec59c6d1a62c26ba5c45128b084b62ef4e112fa66008768b5094df940e6a164"
# Gradia Capture (annotate screenshots with Gradia) and Bazaar Companion
# (Bazaar from an app's right-click menu): Bluefin built both from git
# submodules, a base without Bluefin has neither. Built here from pinned
# commits (neither project tags releases); the tarball hashes are the pins.
GRADIA_EXT_UUID="gradia-integration@alexandervanhee.github.io"
GRADIA_EXT_COMMIT="0b7e47e1e5c1e68e234e4d2d24b307e1da1d18a9"   # 2026-10-16, shell-version 49,50,51
GRADIA_EXT_SHA256="59e999ed0845ee384d29371095d2e935ad0411dd2bed526c924351fec53f0974"
BAZAAR_EXT_UUID="bazaar-integration@kolunmi.github.io"
BAZAAR_EXT_COMMIT="551ab812fda96e76fecc29a06f2adc993dd4e041"   # 2026-10-16, shell-version 49,50,51
BAZAAR_EXT_SHA256="1c5260b146fdb9175ab1659dec29d8f16b2914df6718c9a85f6d501ab491b743"

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
  # margine: survive the lock screen (2026-08-29). Without "session-modes"
  # GNOME Shell disables every extension when the screen locks and re-enables
  # it on unlock; o-tiling then tears its tiling forest down and rebuilds it
  # from the live windows, and that rebuild re-assigns windows to workspaces:
  # with a fullscreen window on the active workspace the others slid down one
  # workspace at every unlock (journal: "o-tiling: [INFO] disable" at lock,
  # "enable" at unlock, then the re-attach). Declaring user + unlock-dialog
  # keeps it loaded through the lock screen, the pattern GNOME's review
  # guidelines prescribe for exactly this. pop-shell issues #957 and #217.
  python3 - "${target}/metadata.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["session-modes"] = ["user", "unlock-dialog"]
json.dump(d, open(p, "w"), indent=4)
PY
  log "o-tiling: metadata.json session-modes = user, unlock-dialog (stays loaded across the lock screen)"
  assert_shell_compat "${target}"

  # HOTFIX (2026-07-04, pending upstream in oliwebd/o-tiling): v2.9.5's
  # _show_skip_taskbar_windows() calls global.log() in its two WARNING
  # branches — an API GNOME removed. On GNOME 50 the guarded internals are
  # gone, so a WARNING branch is ALWAYS taken → TypeError → the handler
  # aborts mid-monkey-patch on EVERY skip-taskbar window event. During a
  # live install (Anaconda spawns exactly such windows while flooding
  # GSettings via localed) this fired seconds before a gnome-shell SIGSEGV
  # that killed the whole session (coredump: update_clock →
  # g_settings_get_enum use-after-free; see docs/notes 2026-07-04).
  # console.log() is the GNOME 45+ replacement. The post-check makes a
  # future version bump fail LOUDLY here instead of silently shipping
  # broken calls again.
  local n_globallog
  n_globallog="$(grep -c 'global\.log(' "${target}/extension.js" || true)"
  if [[ "${n_globallog}" -gt 0 ]]; then
    sed -i 's/global\.log(/console.log(/g' "${target}/extension.js"
    log "o-tiling: patched ${n_globallog} global.log() call(s) → console.log()"
  else
    log "o-tiling: no global.log() left upstream — drop this hotfix block"
  fi
  if grep -q 'global\.log(' "${target}/extension.js"; then
    log "ERROR: global.log() still present in o-tiling after patch"
    exit 1
  fi

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
install_gradia_ext() {
  local target="${EXT_DIR}/${GRADIA_EXT_UUID}" src=/tmp/gradia-ext
  log "gradia-integration ${GRADIA_EXT_COMMIT:0:7} → ${target}"
  rm -rf "${target}" "${src}"
  mkdir -p "${target}" "${src}"
  curl -fL --retry 5 --retry-all-errors --retry-delay 10 -o /tmp/gradia-ext.tar.gz \
    "https://github.com/AlexanderVanhee/gradia-capture/archive/${GRADIA_EXT_COMMIT}.tar.gz"
  verify_sha256 /tmp/gradia-ext.tar.gz "${GRADIA_EXT_SHA256}"
  tar -xzf /tmp/gradia-ext.tar.gz -C "${src}" --strip-components=1
  # Upstream's build.sh packs src/ with the icons and the schema through
  # gnome-extensions pack (part of gnome-shell, present at build time).
  (cd "${src}" && bash build.sh >/dev/null)
  extract_zip "${src}/${GRADIA_EXT_UUID}.shell-extension.zip" "${target}"
  rm -rf /tmp/gradia-ext.tar.gz "${src}"
  [[ -f "${target}/metadata.json" ]] || { log "ERROR: ${target}/metadata.json missing after packing"; exit 1; }
  assert_shell_compat "${target}"
  glib-compile-schemas --strict "${target}/schemas"
}

install_bazaar_ext() {
  local target="${EXT_DIR}/${BAZAAR_EXT_UUID}" src=/tmp/bazaar-ext
  log "bazaar-integration ${BAZAAR_EXT_COMMIT:0:7} → ${target}"
  rm -rf "${target}" "${src}"
  mkdir -p "${target}" "${src}"
  curl -fL --retry 5 --retry-all-errors --retry-delay 10 -o /tmp/bazaar-ext.tar.gz \
    "https://github.com/bazaar-org/bazaar-companion/archive/${BAZAAR_EXT_COMMIT}.tar.gz"
  verify_sha256 /tmp/bazaar-ext.tar.gz "${BAZAAR_EXT_SHA256}"
  tar -xzf /tmp/bazaar-ext.tar.gz -C "${src}" --strip-components=1
  # The extension is src/ as is (no schemas), which is also what Bluefin ships.
  cp -a "${src}/src/." "${target}/"
  rm -rf /tmp/bazaar-ext.tar.gz "${src}"
  [[ -f "${target}/metadata.json" ]] || { log "ERROR: ${target}/metadata.json missing"; exit 1; }
  assert_shell_compat "${target}"
}

install_caffeine_fallback() {
  local target="${EXT_DIR}/${CAFFEINE_UUID}"
  if [[ -f "${target}/metadata.json" ]] && ( assert_shell_compat "${target}" ) >/dev/null 2>&1; then
    log "caffeine: $(rpm -q gnome-shell-extension-caffeine 2>/dev/null || echo 'the installed build') declares GNOME ${GNOME_SHELL_MAJOR}, kept"
    return 0
  fi
  log "caffeine: $(rpm -q gnome-shell-extension-caffeine 2>/dev/null || echo 'no package') does not declare GNOME ${GNOME_SHELL_MAJOR}; EGO version_tag ${CAFFEINE_VERSION_TAG} instead"
  if rpm -q gnome-shell-extension-caffeine >/dev/null 2>&1; then
    # A leaf: nothing requires it (checked), so rpm alone takes it out; the
    # no-dnf rule of this script is about cascades, and there is none here.
    if rpm -q --whatrequires gnome-shell-extension-caffeine >/dev/null 2>&1; then
      log "ERROR: something requires gnome-shell-extension-caffeine: $(rpm -q --whatrequires gnome-shell-extension-caffeine)"
      exit 1
    fi
    rpm -e --nodeps gnome-shell-extension-caffeine
  fi
  rm -rf "${target}"
  mkdir -p "${target}"
  curl -fL --retry 5 --retry-all-errors --retry-delay 10 \
    -o /tmp/caffeine.zip \
    "https://extensions.gnome.org/download-extension/${CAFFEINE_UUID}.shell-extension.zip?version_tag=${CAFFEINE_VERSION_TAG}"
  verify_sha256 /tmp/caffeine.zip "${CAFFEINE_SHA256}"
  extract_zip /tmp/caffeine.zip "${target}"
  rm -f /tmp/caffeine.zip
  [[ -f "${target}/metadata.json" ]] || { log "ERROR: ${target}/metadata.json missing after extraction"; exit 1; }
  assert_shell_compat "${target}"
  glib-compile-schemas --strict "${target}/schemas"
}

# Every extension Margine enables must declare the running GNOME: one that
# does not loads as OUT_OF_DATE and quietly drops out of the session, with
# every other check green (Caffeine 60 on Fedora 45, found in a VM on
# 2026-10-17). The enabled set is the zz1 override 30-gnome-defaults wrote.
assert_enabled_extensions_compat() {
  local override=/usr/share/glib-2.0/schemas/zz1-margine.gschema.override uuid bad=()
  [[ -f "$override" ]] || { log "ERROR: $override missing, cannot check the enabled extensions"; exit 1; }
  for uuid in $(sed -n "s/^enabled-extensions=\[\(.*\)\]$/\1/p" "$override" | tr -d "' " | tr ',' ' '); do
    if [[ ! -f "${EXT_DIR}/${uuid}/metadata.json" ]]; then
      bad+=("${uuid} (missing)")
    elif ! ( assert_shell_compat "${EXT_DIR}/${uuid}" ) >/dev/null 2>&1; then
      bad+=("${uuid} (no GNOME ${GNOME_SHELL_MAJOR})")
    fi
  done
  if (( ${#bad[@]} )); then
    log "ERROR: enabled extensions that would not load on GNOME ${GNOME_SHELL_MAJOR}: ${bad[*]}"
    exit 1
  fi
  log "every enabled extension declares GNOME ${GNOME_SHELL_MAJOR}"
}

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
  # margine: GNOME 51 (2026-10-16). EGO has no Smile build for GNOME 51 yet
  # (version_tag 70078 lists 45-50). GNOME 51 removed
  # Clutter.get_default_backend(), which Smile calls for the virtual keyboard
  # that pastes the emoji: with 51 only added to shell-version the extension
  # loads but every paste throws a TypeError. Margine takes the seat from
  # global.stage.context's backend (what GNOME Shell 51's keyboard.js does)
  # and adds 51, the change proposed upstream in
  # mijorus/smile-gnome-extension#23. Tested on a headless GNOME Shell 51.0
  # and 50.5: ACTIVE, the CopiedEmoji signal pastes without a JS error. Tied
  # to this version_tag: the EGO pin check's bump to a real 51 build turns it
  # off on its own.
  if [[ "${GNOME_SHELL_MAJOR}" == "51" && "${SMILE_EXT_VERSION_TAG}" == "70078" ]]; then
    python3 - "${target}" <<'PY' || { log "ERROR: smile GNOME 51 patch did not apply"; exit 1; }
import json, sys
d = sys.argv[1]
js = f"{d}/extension.js"
src = open(js).read()
old = "this.virtualKeyboard = Clutter.get_default_backend().get_default_seat().create_virtual_device(deviceType);"
new = ("const backend = global.stage.context?.get_backend?.() ?? Clutter.get_default_backend();\n"
       "        this.virtualKeyboard = backend.get_default_seat().create_virtual_device(deviceType);")
if old not in src:
    sys.exit("extension.js no longer has the get_default_backend() call")
open(js, "w").write(src.replace(old, new, 1))
md_path = f"{d}/metadata.json"
md = json.load(open(md_path))
if "51" not in [str(v) for v in md.get("shell-version", [])]:
    md["shell-version"].append("51")
json.dump(md, open(md_path, "w"), indent=2)
PY
    log "smile: GNOME 51 backend call and shell-version (mijorus/smile-gnome-extension#23)"
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
install_gradia_ext
install_bazaar_ext
install_caffeine_fallback
install_legacy_icon_shims
assert_enabled_extensions_compat

log "Recompiling /usr/share/glib-2.0/schemas to pick up new extension schemas"
glib-compile-schemas /usr/share/glib-2.0/schemas

log "Final extension inventory under ${EXT_DIR}:"
for d in "${EXT_DIR}"/*/; do echo "  $(basename "$d")"; done | sort

log "metadata.json for the ones we just added:"
for uuid in o-tiling@oliwebd.github.com hide-cursor@elcste.com smile-extension@mijorus.it "${GRADIA_EXT_UUID}" "${BAZAAR_EXT_UUID}"; do
  if [[ -f "${EXT_DIR}/${uuid}/metadata.json" ]]; then
    printf '  %s: ' "${uuid}"
    python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
print(f'name={d.get(\"name\",\"?\")} shell-version={\",\".join(map(str, d.get(\"shell-version\", [])))} session-modes={\",\".join(d.get(\"session-modes\", [])) or \"-\"}')
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
# o-tiling: keep its UI off the lock screen (2026-08-30).
# ---------------------------------------------------------------------------
# install_otiling declares session-modes user + unlock-dialog so the tiling
# forest survives lock/unlock (windows used to slide a workspace at every
# unlock, #388). The price: GNOME keeps the extension loaded on the lock
# screen, and its panel button, its workspace-number switcher and its Quick
# Settings toggle stayed visible and clickable there (reported on
# 2026-08-30). The stock unlock-dialog panel is empty on the left and shows
# only a11y/keyboard/quickSettings on the right; an extension that lives
# through the lock screen must hide what it adds. This patch hides the three
# while sessionMode.isLocked, leaves any interactive tiling mode, and restores
# them on unlock. Anchored on two exact lines of enable()/disable(): an
# upstream rewrite must STOP the build, never ship a lock screen with our UI.
if [[ -f "$OTILING_EXT" ]]; then
  if grep -q 'margine: lock-screen hygiene' "$OTILING_EXT"; then
    log "o-tiling lock-screen UI patch already present"
  elif python3 - "$OTILING_EXT" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p).read()
a = "        _toggle_quick_settings_indicator(ext.settings.quick_settings_toggle());\n"
d = "        delete globalThis.oTilingExtension;\n"
if s.count(a) != 1 or s.count(d) != 1:
    sys.exit(1)
add = """        // margine: lock-screen hygiene. session-modes keeps this extension loaded
        // through the lock screen (so the tiling forest survives lock/unlock);
        // nothing of its UI may be usable there: hide the panel button, the
        // workspace-number switcher and the Quick Settings toggle while locked,
        // leave any interactive mode, and restore them on unlock.
        if (!ext._margine_lock_ui_signal) {
            const applyLockState = () => {
                const locked = sessionMode.isLocked;
                if (indicator?.button)
                    indicator.button.visible = !locked && !ext.settings.hide_panel_icon();
                if (workspace_number_indicator?.button)
                    workspace_number_indicator.button.visible = !locked;
                if (quick_settings_indicator) {
                    quick_settings_indicator.visible = !locked;
                    for (const item of quick_settings_indicator.quickSettingsItems ?? [])
                        item.visible = !locked;
                }
                // The panel-transparency stylesheet paints #panel with !important
                // in every mode, lock screen included: pull it while locked.
                if (locked) {
                    ext.exit_modes();
                    ext.panel_transparency_handler?.disable();
                } else {
                    ext.panel_transparency_handler?.enable();
                }
            };
            ext._margine_lock_ui_signal = sessionMode.connect('updated', applyLockState);
            applyLockState();
        }
"""
dadd = """        if (ext?._margine_lock_ui_signal) {
            sessionMode.disconnect(ext._margine_lock_ui_signal);
            ext._margine_lock_ui_signal = 0;
        }
"""
s = s.replace(a, a + add, 1).replace(d, dadd + d, 1)
open(p, "w").write(s)
PYEOF
  then
    log "o-tiling: panel button, workspace switcher and Quick Settings toggle hidden while the screen is locked"
  else
    log "ERROR: o-tiling enable()/disable() anchors for the lock-screen patch not found (upstream changed?), refusing to ship its UI on the lock screen"
    exit 1
  fi
fi

# The panel-transparency CSS o-tiling injects also targets #panel.login-screen
# and #panel.unlock-screen, so the lock screen got a dark band across the top
# where GNOME draws a transparent panel (2026-08-30, after the first
# lock-screen patch). Drop the two selectors; the user-session panel keeps
# its transparency setting.
OTILING_PT="${EXT_DIR}/o-tiling@oliwebd.github.com/ui/panel_transparency.js"
if [[ -f "$OTILING_PT" ]]; then
  if grep -q 'margine: lock-screen hygiene' "$OTILING_PT"; then
    log "o-tiling panel CSS lock-screen patch already present"
  elif python3 - "$OTILING_PT" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p).read()
old = """#panel,
#panel.solid,
#panel:overview,
#panel.login-screen,
#panel.unlock-screen {
"""
new = """/* margine: lock-screen hygiene. GNOME draws the login and unlock panels
   transparent; do not paint a dark band over the lock screen. */
#panel,
#panel.solid,
#panel:overview {
"""
if s.count(old) != 1:
    sys.exit(1)
open(p, "w").write(s.replace(old, new, 1))
PYEOF
  then
    log "o-tiling: panel transparency CSS no longer touches the login and unlock panels"
  else
    log "ERROR: o-tiling panel_transparency.js selector block not found (upstream changed?), refusing to paint the lock screen"
    exit 1
  fi
else
  log "ERROR: o-tiling ui/panel_transparency.js not found, the patch target is gone"
  exit 1
fi

# ---------------------------------------------------------------------------
# o-tiling: Smile (the emoji picker, Super+.) floats by default (2026-08-30),
# and so does Live Captions (2026-09-22).
# ---------------------------------------------------------------------------
# Smile is a small picker that is meant to pop over the text you are typing
# into; tiled, it takes half the workspace and shoves the editor aside.
# o-tiling floats windows that match its DEFAULT_FLOAT_RULES (class/title
# regexes) or the user's ~/.config/o-tiling/config.json. Add Smile to the
# baked defaults: GTK4 under Wayland reports the application id as the
# window class, and its window is titled "Smile". Placement stays centred
# on the current monitor (mutter center-new-windows): Wayland gives no
# caret position to third-party apps, so "next to the input" is not a
# thing any picker can do.
#
# Live Captions (net.sapples.LiveCaptions) is a subtitle strip for any
# audio playing on the machine: a thin window you park over the video or
# the call, and it already asks to stay on top (keep-on-top defaults to
# true). Tiled, it became half a workspace of captions and could not be
# moved at all. Same identity rules as Smile: class = application id,
# window titled "Live Captions".
# WHICH FILE: o-tiling 2.11.x moved the rules the extension actually reads
# into system/config.js (extension.js does `import * as Config from
# './system/config.js'`), leaving a second, now dialog-only copy in
# floating_exceptions/config.js. Patching that copy alone is what made
# both Smile and Live Captions stay tiled on the images built between
# 2026-09-20 and 2026-09-23: the list looked right in the exceptions
# dialog and meant nothing at runtime. So patch EVERY file that defines
# DEFAULT_FLOAT_RULES, then verify the runtime one really carries the
# rules, and fail the build if it does not.
OTILING_DIR="${EXT_DIR}/o-tiling@oliwebd.github.com"
OTILING_RUNTIME_CONF="${OTILING_DIR}/$(sed -n "s#^import \\* as Config from '\\./\\(.*\\)';#\\1#p" "${OTILING_DIR}/extension.js" | head -1)"
mapfile -t OTILING_RULE_FILES < <(grep -rl 'DEFAULT_FLOAT_RULES = \[' "${OTILING_DIR}" || true)
if (( ${#OTILING_RULE_FILES[@]} == 0 )); then
  log "ERROR: no file in o-tiling defines DEFAULT_FLOAT_RULES (upstream changed?), refusing to guess"
  exit 1
fi
for f in "${OTILING_RULE_FILES[@]}"; do
  if grep -q "net.sapples.LiveCaptions" "$f"; then
    log "o-tiling: $(basename "$(dirname "$f")")/$(basename "$f") already carries the Margine float rules"
    continue
  fi
  python3 - "$f" <<'PYEOF' || { log "ERROR: o-tiling DEFAULT_FLOAT_RULES anchor not found in $f (upstream changed?), refusing to guess"; exit 1; }
import sys
p = sys.argv[1]
s = open(p).read()
old = "    { class: 'Solaar' },\n"
if s.count(old) != 1:
    sys.exit(1)
new = (old
       + "    { class: 'it.mijorus.smile' }, // margine: Smile emoji picker floats (Super+.)\n    { title: '^Smile$' },\n"
       + "    { class: 'net.sapples.LiveCaptions' }, // margine: Live Captions is an overlay you place freely\n    { title: '^Live Captions$' },\n")
open(p, "w").write(s.replace(old, new, 1))
PYEOF
  log "o-tiling: float rules added to $(basename "$(dirname "$f")")/$(basename "$f")"
done

# The one that counts: the module extension.js imports as its config.
if [[ ! -f "$OTILING_RUNTIME_CONF" ]]; then
  log "ERROR: cannot tell which config module o-tiling loads (looked for the Config import in extension.js)"
  exit 1
fi
for needle in "it.mijorus.smile" "net.sapples.LiveCaptions"; do
  grep -q "$needle" "$OTILING_RUNTIME_CONF" \
    || { log "ERROR: ${OTILING_RUNTIME_CONF#"$EXT_DIR"/} does not carry the $needle float rule — the rules would be dead at runtime"; exit 1; }
done
log "o-tiling: runtime config ${OTILING_RUNTIME_CONF#"$EXT_DIR"/} verified to carry the Margine float rules"

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
for uuid in o-tiling@oliwebd.github.com hide-cursor@elcste.com smile-extension@mijorus.it "${GRADIA_EXT_UUID}" "${CAFFEINE_UUID}"; do
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
