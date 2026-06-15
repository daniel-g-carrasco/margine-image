#!/usr/bin/env bash
# Margine image build — section: 30-gnome-defaults
# Sub-script of the build.sh orchestrator. Decomposed on 2026-06-06
# (audit §8 rec #22 — split build.sh into per-area install scripts).
# See build_files/00-common.sh + build_files/build.sh.
set -euo pipefail
. /ctx/00-common.sh

# Seahorse — the GNOME keyring/password-manager GUI. Baked so
# `ujust margine-keyring blank` (see /usr/bin/margine-keyring) has a reliable
# way to set the login keyring's master password to empty — the fix for the
# "unlock Login keyring" prompt that fingerprint login / autologin trigger
# (PAM never hands gnome-keyring the password that encrypts the keyring).
# There is no headless API for it; Seahorse provides the change-password
# dialog. Small, and a generally useful desktop tool.
log "Installing seahorse (keyring GUI backing ujust margine-keyring)"
dnf -y install --setopt=install_weak_deps=False seahorse

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
# search-light is intentionally NOT enabled: GNOME's native overview (Super)
# and app-grid (Super+Space) provide search, and search-light's GNOME-50
# crash class isn't worth the dependency. Bluefin's copy stays installed
# (and Margine keeps patching it, see build-margine-extensions.sh) so a user
# can flip it back on; it just doesn't auto-load.
# blur-my-shell is ALSO NOT enabled (dropped 2026-06-16): its dynamic
# per-frame Gaussian blur (sigma=70 at scale 2) made the whole desktop —
# its own transitions AND o-tiling window animations — visibly janky on the
# reference HiDPI iGPU at 120Hz (verified live: "without blur everything runs
# smoother"), and it carries three known unfixed-upstream GNOME-50 defects
# (hotplug black bg #561, overview swipe ghost icons #738/GNOME#2857,
# unreliable dynamic dock blur #574). It stays installed (Bluefin ships it)
# with smooth STATIC defaults (dconf/05-margine-blur-my-shell) so re-enabling
# it doesn't bring the jank back.
enabled-extensions=['appindicatorsupport@rgcjonas.gmail.com', 'bazaar-integration@kolunmi.github.io', 'dash-to-dock@micxgx.gmail.com', 'gradia-integration@alexandervanhee.github.io', 'gsconnect@andyholmes.github.io', 'o-tiling@oliwebd.github.com', 'hide-cursor@elcste.com', 'caffeine@patapon.info', 'smile-extension@mijorus.it']
# Decision (2026-06-07): drop VS Code from the dock favourites and pin
# Bazaar there instead. Reasoning: VS Code is a creator's tool but its
# daily presence in the dock is project-specific (users jump in and
# out by .desktop launch / cli); Bazaar is the entry point for "I want
# a new app" — a verb every user does, so it earns a dock slot. Order
# corresponds to the muscle-memory grid: 1=browser, 2=mail, 3=files,
# 4=apps, 5=terminal.
favorite-apps=['app.zen_browser.zen.desktop', 'org.mozilla.Thunderbird.desktop', 'org.gnome.Nautilus.desktop', 'io.github.kolunmi.Bazaar.desktop', 'org.gnome.Ptyxis.desktop']

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

# Workspaces: a FIXED set of FIVE (Daniel's explicit, standing preference,
# reaffirmed 2026-06-15 — NOT 10). dynamic-workspaces=false makes the count
# fixed; with it true, num-workspaces is ignored and GNOME grows them
# on demand. Super+1..5 switch to the five; the Super+6..0 binds from the
# Hyprland chain are simply inert with only five workspaces (harmless).
[org.gnome.mutter]
dynamic-workspaces=false

[org.gnome.desktop.wm.preferences]
# Override Bluefin's num-workspaces=4 → 5 (Daniel's standing preference).
num-workspaces=5

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

# Terminal default: leave Bluefin's choice (Ptyxis) — do NOT override
# org.gnome.desktop.default-applications.terminal. Users who want a
# different terminal can install one and flip the setting per session.

# Focus follows mouse (sloppy mode) — Hyprland muscle memory.
# `sloppy` keeps focus when the pointer leaves a window (vs `mouse`
# which removes it). auto-raise=false so hover doesn't pop windows
# above each other unexpectedly (only an explicit click raises).
[org.gnome.desktop.wm.preferences]
focus-mode='sloppy'
auto-raise=false
OVERRIDE

# Extension preferences use dconf keyfiles rather than gschema
# overrides. GNOME Shell Extension.getSettings() loads an extension's
# local schemas/ directory ahead of the global schema source, so global
# gschema override defaults for org.gnome.shell.extensions.* can be
# shadowed at runtime. dconf defaults are keyed by path and apply to
# the actual settings backend the extension reads.
log "Installing Margine dconf defaults into /etc/dconf/db/distro.d/"
mkdir -p /etc/dconf/db/distro.d/locks /etc/dconf/profile
install -m 0644 /ctx/30-gnome-defaults/dconf/* /etc/dconf/db/distro.d/

if [[ ! -f /etc/dconf/profile/user ]]; then
  cat > /etc/dconf/profile/user <<'PROFILE'
user-db:user
system-db:local
system-db:site
system-db:distro
PROFILE
elif ! grep -qxF 'system-db:distro' /etc/dconf/profile/user; then
  printf '\nsystem-db:distro\n' >> /etc/dconf/profile/user
fi

if command -v dconf >/dev/null 2>&1; then
  dconf update
fi

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

# Copy every GNOME extension's schema XML from its extension dir to the
# global /usr/share/glib-2.0/schemas/ before compiling. Runtime
# extension defaults live in dconf keyfiles above; this copy remains so
# `gsettings get org.gnome.shell.extensions.* ...` works for diagnostics
# and schema validation tools that only inspect the global schema source.
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
