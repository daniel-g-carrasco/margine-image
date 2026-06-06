#!/usr/bin/env bash
# Margine image build — section: 30-gnome-defaults
# Sub-script of the build.sh orchestrator. Decomposed on 2026-06-06
# (audit §8 rec #22 — split build.sh into per-area install scripts).
# See build_files/00-common.sh + build_files/build.sh.
set -euo pipefail
. /ctx/00-common.sh

# 2. Margine GNOME defaults (gschema override)
# ---------------------------------------------------------------------------
# Write a gschema override that loads AFTER Bluefin's zz0 and overrides
# the few keys we care about. Naming the file zz1-margine-* makes glib
# load it after Bluefin's zz0-bluefin-modifications.
log "Writing zz1-margine.gschema.override"

cat > /usr/share/glib-2.0/schemas/zz1-margine.gschema.override <<'OVERRIDE'
[org.gnome.shell]
# Drop Bluefin's branding extensions from the default enabled set. We
# keep the packages installed so the user can flip them back on per
# session, but they don't auto-load on first boot.
enabled-extensions=['appindicatorsupport@rgcjonas.gmail.com', 'bazaar-integration@kolunmi.github.io', 'blur-my-shell@aunetx', 'dash-to-dock@micxgx.gmail.com', 'gradia-integration@alexandervanhee.github.io', 'gsconnect@andyholmes.github.io', 'search-light@icedman.github.com', 'o-tiling@oliwebd.github.com', 'hide-cursor@elcste.com', 'caffeine@patapon.info']
favorite-apps=['app.zen_browser.zen.desktop', 'org.mozilla.Thunderbird.desktop', 'org.gnome.Nautilus.desktop', 'org.gnome.Ptyxis.desktop', 'code.desktop']

# NOTE — icon-size coherence (overview app-grid / folder / search):
# Tried 2026-06-06 to pin `[org.gnome.shell.app-grid]` keys
# app-grid-icon-size + folder-icon-size to 96 here. Diagnose script on
# the live VM reported "schema-absent" for org.gnome.shell.app-grid:
# the schema does NOT exist in GNOME 47/48 (it was a 3.x-era key set).
# The visible icon-size drift between app-grid (~96px) and folder
# view (~64px) is enforced by gnome-shell's CSS theme, not by dconf.
# Fix is a CSS overlay or a shell-extension monkeypatch — not a
# gschema override. Tracked as a separate cosmetic issue; do not
# re-add a [org.gnome.shell.app-grid] block here.

[org.gnome.desktop.interface]
accent-color='yellow'
# Bluefin's zz0 hard-sets Adwaita Sans (their pick). We leave fonts as
# GNOME default here — daniel hasn't picked a Margine type system yet;
# revisit when there's a documented choice. Removing the keys lets
# GNOME's distro defaults win over Bluefin's, which is what we want
# until we have an opinion.

# Number of dynamic workspaces — Margine binds Super+1..0 (Hyprland
# muscle memory) via the user-level bootstrap, so the base default
# should give us 10 slots ready at first login.
[org.gnome.mutter]
dynamic-workspaces=true

[org.gnome.desktop.wm.preferences]
# Override Bluefin's num-workspaces=4. The Hyprland binding chain in
# margine-fedora-atomic's configure-gnome-keybindings expects 10.
num-workspaces=10

[org.gnome.desktop.wm.keybindings]
# Bluefin remaps Super+d → show-desktop, which collides with
# Margine's Hyprland-style binds. Reset only that single key.
#
# IMPORTANT — do NOT clear switch-applications / switch-
# applications-backward / switch-windows / switch-windows-backward
# here. Earlier versions of zz1 cleared them all to @as [] thinking
# configure-gnome-keybindings would restore them with Hyprland
# semantics. It DOESN'T — the script has an explicit
# "INTENTIONALLY LEFT AT THEIR GNOME DEFAULT" comment. So clearing
# here means Alt+Tab and Super+Tab end up unbound and daniel
# reported (2026-06-05) they don't work. Keep GNOME defaults.
show-desktop=@as []

# Dash-to-Dock by default binds Super+1..9 to launch the matching dash
# slot. That collides with Margine's Super+1..0 workspace navigation
# (the same keys the user expects from Hyprland). Disable Dash-to-Dock's
# own hot-key handler so configure-gnome-keybindings' workspace binds
# win cleanly. NOT cosmetic — this is a keybinding collision fix.
[org.gnome.shell.extensions.dash-to-dock]
# Anti-collision with Margine's Super+1..0 workspace binds.
hot-keys=false
# Cosmetic defaults captured 2026-06-06 from daniel's running VM
# (diagnose-margine-firstboot dconf dump). Promoted to system defaults
# so first-boot users get the same dock the project's lead is using
# without manual tweaking. Mirrors blur-my-shell pattern below.
animation-time=0.15
apply-custom-theme=true
background-color='rgb(40,40,40)'
background-opacity=0.8
custom-background-color=true
custom-theme-shrink=true
customize-alphas=true
disable-overview-on-startup=true
dock-fixed=true
force-straight-corner=false
max-alpha=0.8
min-alpha=0.5
running-indicator-style='DOTS'
transparency-mode='DYNAMIC'

# Caffeine — keep-awake helper for video playback / long renders.
# Indicator stays near system tray (max position), CLI toggle off.
[org.gnome.shell.extensions.caffeine]
cli-toggle=false
indicator-position-max=2

# Terminal default: leave Bluefin's choice (Ptyxis) — do NOT override
# org.gnome.desktop.default-applications.terminal. Users who want a
# different terminal can install one and flip the setting per session.

# Default tiling engine for Margine — o-tiling@oliwebd.github.com
# (binary-tree auto-split, Hyprland/pop-shell-style). Was tilingshell
# until 2026-05-31. The UUID was wrong in zz1 historically
# (the relocatable schema path was right but the enabled-extensions
# list had 'tilingshell' instead of o-tiling); margine-bootstrap
# applied the correct UUID at user-level, so daniel's session worked,
# but a freshly-rebased VM that doesn't run the bootstrap would see
# tilingshell as default. Fixed in enabled-extensions above.
[org.gnome.shell.extensions.o-tiling]
active-hint=true
active-hint-border-radius=14
active-hint-border-width=4
gap-inner=4
gap-outer=4
mouse-cursor-follows-active-window=true
skip-overview=false
# Auto-tile new windows by default — the whole point of running
# o-tiling on Margine. Captured 2026-06-06 from daniel's VM.
tile-by-default=true

[org.gnome.shell.extensions.tilingshell]
# Tiling Shell is installed but disabled by default — flip back via
# Extension Manager if o-tiling doesn't suit a particular workflow.
# Keep these prefs sensible so the experience is consistent if the
# user re-enables it:
enable-autotiling=true
enable-snap-assist=true
enable-window-border=false   # ghost-border bug at v18, see lessons
inner-gaps=4
outer-gaps=4

# Focus follows mouse (sloppy mode) — Hyprland muscle memory.
# `sloppy` keeps focus when the pointer leaves a window (vs `mouse`
# which removes it). auto-raise=false so hover doesn't pop windows
# above each other unexpectedly (only an explicit click raises).
[org.gnome.desktop.wm.preferences]
focus-mode='sloppy'
auto-raise=false

# ---------------------------------------------------------------------------
# Blur My Shell + Search Light — cosmetic-only defaults
# ---------------------------------------------------------------------------
# Captured 2026-06-02 from daniel's running VM via `dconf dump
# /org/gnome/shell/extensions/<ext>/`, narrowed 2026-06-03 to the
# COSMETIC surface only (blur radius / brightness, background
# transparency, pipeline assignment per surface). All other captured
# keys were dropped intentionally to avoid freezing dynamic /
# accessibility behaviour we want to keep responsive:
#
#   * blur-my-shell.hidetopbar.compatibility — toggle for another
#     extension's behaviour, not cosmetic.
#   * blur-my-shell internal state (`pipelines` dict, rounded-blur-found,
#     settings-version) — managed by the extension itself.
#   * search-light scale-width / scale-height / popup-at-cursor-monitor /
#     preferred-monitor / monitor-count / entry-font-size /
#     animation-speed / border-radius / show-panel-icon — popup sizing
#     and monitor selection that should adapt to the user's hardware
#     and accessibility settings.
#   * search-light shortcut-search — belongs in keybindings, not here.
#   * dash-to-dock hot-keys=false — anti-collision with Margine's
#     Super+1..0 workspace binds, lives in the keybindings section
#     above (not a cosmetic default).
#
# Anything we don't override falls back to the extension's own
# defaults, which is the desired behaviour.

# Blur My Shell — per-surface blur tuning
[org.gnome.shell.extensions.blur-my-shell.appfolder]
brightness=0.4
sigma=70

[org.gnome.shell.extensions.blur-my-shell.applications]
pipeline='pipeline_default'

[org.gnome.shell.extensions.blur-my-shell.coverflow-alt-tab]
pipeline='pipeline_default'

[org.gnome.shell.extensions.blur-my-shell.dash-to-dock]
blur=true
brightness=0.4
pipeline='pipeline_default_rounded'
sigma=70
static-blur=true
style-dash-to-dock=0
unblur-in-overview=true

[org.gnome.shell.extensions.blur-my-shell.dash-to-panel]
blur-original-panel=true

[org.gnome.shell.extensions.blur-my-shell.lockscreen]
pipeline='pipeline_default'

[org.gnome.shell.extensions.blur-my-shell.overview]
pipeline='pipeline_default'

[org.gnome.shell.extensions.blur-my-shell.panel]
brightness=0.4
corner-radius=0
override-background=true
pipeline='pipeline_default'
sigma=70
static-blur=false
unblur-in-overview=true

[org.gnome.shell.extensions.blur-my-shell.screenshot]
pipeline='pipeline_default'

[org.gnome.shell.extensions.blur-my-shell.window-list]
brightness=0.4
sigma=70

# Search Light — Margine baseline captured 2026-06-03 from daniel's VM
# after his tuning pass:
#   * Slightly darker background scrim (alpha 0.75 vs 0.74)
#   * Fast animation (100ms) with animations on by default
#   * Super+Space toggle (kept here rather than in a separate keybind
#     block — search-light handles its own shortcut binding internally
#     and reading/writing it via this key is the supported surface)
#   * Default GNOME corner-radius (border-radius is deliberately NOT
#     declared so the popup adopts the system default and adapts to
#     theme changes)
# Blur keys are NOT declared — blur-background stays off because
# search-light's blur implementation has rendering glitches we want
# to avoid; the related blur-sigma / blur-brightness are operational
# no-ops while blur-background=false.
[org.gnome.shell.extensions.search-light]
animation-speed=100.0
background-color=(0.0, 0.0, 0.0, 0.75)
blur-background=false
shortcut-search=['<Super>space']
use-animations=true
window-effect=0
# Rounded corners at the schema maximum — daniel asked 2026-06-06 to
# ship "rounded corners di searchlight al massimo come default". The
# search-light gschema declares border-radius as a double in [0, 30],
# so 30.0 is the documented ceiling. Anything above 30 gets clamped
# by the extension at apply time; values below produce sharper edges
# than what daniel ran with on his daily VM.
border-radius=30.0
OVERRIDE

# ---------------------------------------------------------------------------
# Surgical icon fix: replace ONE low-res Adwaita Legacy PNG
# ---------------------------------------------------------------------------
# Verified 2026-06-05: margine-system-update.desktop's `Icon=system-
# software-update` rendered as a blurry low-res sprite because the
# only system-software-update icon in Bluefin DX's image is the
# AdwaitaLegacy 48×48 PNG. Earlier attempt (PR #32) installed the
# whole MoreWaita icon theme + set it as system default — daniel
# rejected that as overkill ("anziché scaricare svg dell'icona e
# applicare quello, imposti MOREWAITA SU TUTTO IL SISTEMA?").
#
# Surgical fix: download just the ONE high-res SVG from MoreWaita
# and place it as Adwaita's scalable override for the icon name
# `system-software-update`. Adwaita's scalable/ entries win over
# its legacy PNGs at any rendering size, so the launcher draws
# crisp at any DPI without touching the user's icon theme. No
# tar download, no theme switch, no behaviour change anywhere
# else in the desktop.
MOREWAITA_RAW="https://raw.githubusercontent.com/somepaulo/MoreWaita/main/scalable/legacy/system-software-update.svg"
SYSUPDATE_TARGET="/usr/share/icons/Adwaita/scalable/apps/system-software-update.svg"
log "Downloading high-res system-software-update.svg from MoreWaita → $SYSUPDATE_TARGET"
mkdir -p "$(dirname "$SYSUPDATE_TARGET")"
if curl -fL --retry 5 --retry-delay 10 -sS -o "$SYSUPDATE_TARGET" "$MOREWAITA_RAW"; then
  chmod 0644 "$SYSUPDATE_TARGET"
  # Refresh Adwaita icon cache so gtk apps see the new SVG.
  gtk-update-icon-cache -q -t -f /usr/share/icons/Adwaita || true
  log "system-software-update.svg installed ($(stat -c %s "$SYSUPDATE_TARGET") bytes)"
else
  log "WARN: failed to download system-software-update.svg — launcher icon stays blurry"
fi

# Copy every GNOME extension's schema XML from its extension dir to
# the global /usr/share/glib-2.0/schemas/ before compiling. Bluefin's
# build-gnome-extensions.sh installs extensions but only compiles
# their schemas IN the per-extension dir (sufficient for GNOME Shell
# to load), NOT in the global dir. Result: `gsettings`, `dconf` and
# our own zz1-margine.gschema.override CAN'T see the extension's
# schema, so extension keybindings/preferences silently fall back to
# extension defaults. Verified 2026-06-04 on fresh install:
# search-light loaded but `gsettings get
# org.gnome.shell.extensions.search-light shortcut-search` returned
# "Schema inesistente" → our zz1 override of shortcut-search=<Super>space
# never applied → Super+Space did nothing → daniel said "non funziona".
#
# Copy each extension's *.gschema.xml into the global dir so the
# subsequent glib-compile-schemas call below picks them all up,
# making gsettings/dconf/override able to reach them.
log "Copying GNOME extension gschema files to /usr/share/glib-2.0/schemas/"
for ext_dir in /usr/share/gnome-shell/extensions/*/; do
  ext_schemas="${ext_dir}schemas"
  [[ -d "$ext_schemas" ]] || continue
  for xml in "$ext_schemas"/*.gschema.xml; do
    [[ -f "$xml" ]] || continue
    base=$(basename "$xml")
    if [[ ! -f "/usr/share/glib-2.0/schemas/$base" ]]; then
      cp "$xml" "/usr/share/glib-2.0/schemas/$base"
      echo "  copied $base from $(basename "$(dirname "$ext_schemas")")"
    fi
  done
done

log "Compiling glib schemas"
glib-compile-schemas /usr/share/glib-2.0/schemas

# ---------------------------------------------------------------------------
