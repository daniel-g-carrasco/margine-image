#!/usr/bin/env bash
# Margine image build — section: 50-branding
# Sub-script of the build.sh orchestrator. Decomposed on 2026-06-06
# (audit §8 rec #22 — split build.sh into per-area install scripts).
# See build_files/00-common.sh + build_files/build.sh.
set -euo pipefail
. /ctx/00-common.sh

# 4. Margine visual branding (logo, wallpaper, Plymouth, /etc/issue, fastfetch)
# ---------------------------------------------------------------------------
# Fetch the branding assets from margine-fedora-atomic and install them in
# the standard system locations so user-facing surfaces (About panel,
# desktop wallpaper, login screen, boot splash, console, fastfetch) all
# show Margine identity instead of inheriting Bluefin's.
log "Installing Margine visual branding"

# (a) Logo → /etc/os-release's LOGO=margine-logo. GNOME 47/48 About
# panel uses GTK4 gtk_icon_theme_lookup_icon("margine-logo") with the
# GTK_ICON_LOOKUP_FORCE_REGULAR flag, which means the lookup is
# RESTRICTED to icon themes (hicolor/Adwaita) and does NOT fall back
# to /usr/share/pixmaps/. Until 2026-06-07 we shipped the asset only
# in pixmaps, so the About panel rendered nothing (verified live on
# daniel's VM via QGA).
#
# Install in both places:
#   /usr/share/icons/hicolor/scalable/apps/margine-logo.svg    (primary
#       — what GNOME About actually consumes)
#   /usr/share/pixmaps/margine-logo.png                        (fallback
#       — other consumers like systemd-logo, /etc/issue tooling)
# Both use the square margine-m source asset.
mkdir -p /usr/share/icons/hicolor/scalable/apps /usr/share/pixmaps
retry_curl_strict "${MARGINE_REPO}/${MARGINE_REF}/assets/branding/margine-logo-square.svg" /usr/share/icons/hicolor/scalable/apps/margine-logo.svg
chmod 0644 /usr/share/icons/hicolor/scalable/apps/margine-logo.svg
retry_curl_strict "${MARGINE_REPO}/${MARGINE_REF}/assets/branding/margine-logo-square.png" /usr/share/pixmaps/margine-logo.png
chmod 0644 /usr/share/pixmaps/margine-logo.png
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache --force --quiet /usr/share/icons/hicolor 2>/dev/null || true
fi
log "Installed margine-logo: hicolor/scalable/apps SVG + pixmaps PNG (About panel can now resolve it via GTK4 icon-theme lookup)"

# (b) Wallpaper → /usr/share/backgrounds/margine/ + dconf override so it's
#     the default desktop background (light + dark).
mkdir -p /usr/share/backgrounds/margine
retry_curl "${MARGINE_REPO}/${MARGINE_REF}/assets/branding/wallpaper-margine.png" /usr/share/backgrounds/margine/margine.png
chmod 0644 /usr/share/backgrounds/margine/margine.png
# Backwards-compat shim: pre-2026-05-30 images shipped this file as
# `autumn-leaves.png` and users' dconf may still point there. Keep a
# symlink so existing sessions keep rendering the new image rather
# than dropping to the fallback solid color after `bootc upgrade`.
# Remove in a few months once it's safe to assume everyone has run
# `gsettings reset org.gnome.desktop.background picture-uri` at least
# once.
ln -sf margine.png /usr/share/backgrounds/margine/autumn-leaves.png
log "Installed: /usr/share/backgrounds/margine/margine.png (+ autumn-leaves.png compat symlink)"

# Desktop background gschema override — set on the existing zz1 file so
# it loads after Bluefin's zz0.
cat >> /usr/share/glib-2.0/schemas/zz1-margine.gschema.override <<'OVERRIDE'

[org.gnome.desktop.background]
picture-uri='file:///usr/share/backgrounds/margine/margine.png'
picture-uri-dark='file:///usr/share/backgrounds/margine/margine.png'
picture-options='zoom'
primary-color='#000000'
secondary-color='#000000'

[org.gnome.desktop.screensaver]
picture-uri='file:///usr/share/backgrounds/margine/margine.png'
picture-options='zoom'
primary-color='#000000'
OVERRIDE

# (c) Plymouth theme → /usr/share/plymouth/themes/margine/
# Our theme is script-based, which needs /usr/lib64/plymouth/script.so.
# Bluefin DX ships Plymouth core but not the script plugin (their own
# theme uses other plugins). Layer plymouth-plugin-script so the
# plymouth-set-default-theme call below resolves the backend.
log "Installing plymouth-plugin-script (required by our script-based theme)"
dnf -y install plymouth-plugin-script

mkdir -p /usr/share/plymouth/themes/margine
for f in margine.plymouth margine.script watermark.png ; do
  retry_curl "${MARGINE_REPO}/${MARGINE_REF}/assets/branding/plymouth/${f}" "/usr/share/plymouth/themes/margine/${f}"
done
chmod 0644 /usr/share/plymouth/themes/margine/*
log "Installed: /usr/share/plymouth/themes/margine/"

# Set Margine as the default Plymouth theme. The `-R` flag would
# regenerate the initramfs, but in a bootc build context we'd rather
# trigger that explicitly at the end of the kernel install path. Here we
# just point the config; dracut --regenerate-all (run below) picks it
# up because the symlink set by plymouth-set-default-theme is in
# /etc/plymouth/plymouthd.conf.
if command -v plymouth-set-default-theme >/dev/null 2>&1; then
  plymouth-set-default-theme margine
  log "Set Plymouth default theme: margine"
fi
# Regenerate initramfs so the new Plymouth theme is embedded for the
# boot splash. Output goes to /usr/lib/modules/<KVER>/initramfs.img,
# the bootc/ostree-expected path. --add ostree explicitly includes the
# ostree dracut module (without which switch-root fails — see comment
# in custom-kernel/install.sh).
if command -v dracut >/dev/null 2>&1; then
  for kver_dir in /usr/lib/modules/*/; do
    kver=$(basename "$kver_dir")
    dracut --force --no-hostonly --no-hostonly-cmdline \
        --add "ostree" \
        --kver "$kver" \
        "${kver_dir}initramfs.img"
  done
fi

# (d) GDM login screen background — system dconf override.
mkdir -p /etc/dconf/db/gdm.d /etc/dconf/profile
cat > /etc/dconf/profile/gdm <<'EOF'
user-db:user
system-db:gdm
file-db:/usr/share/gdm/greeter-dconf-defaults
EOF
cat > /etc/dconf/db/gdm.d/01-margine-background <<'EOF'
[org/gnome/desktop/background]
picture-uri='file:///usr/share/backgrounds/margine/margine.png'
picture-uri-dark='file:///usr/share/backgrounds/margine/margine.png'
picture-options='zoom'
primary-color='#000000'
EOF
# (d.ter) Replace Bluefin's "F"-logo SVG with a fully transparent one.
# Bluefin DX drops its own logo into
# /usr/share/icons/hicolor/scalable/places/fedora-logo-sprite.svg (the
# file is not owned by any RPM — it's overlaid by Bluefin's build).
# GNOME greeter / about widgets that look up "fedora-logo-sprite" by
# icon name therefore render the Bluefin "F" in our images too.
# Overwrite with a 296×296 empty SVG so any consumer of that icon
# name renders nothing.
SPRITE=/usr/share/icons/hicolor/scalable/places/fedora-logo-sprite.svg
if [[ -f "$SPRITE" ]]; then
  cat > "$SPRITE" <<'SVG'
<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="296" height="296" viewBox="0 0 296 296"/>
SVG
  if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache /usr/share/icons/hicolor || true
  fi
  log "Replaced Bluefin's fedora-logo-sprite.svg with transparent placeholder"
fi

# (d.bis-pre) Nuke Fedora/Bluefin logo fallbacks GNOME might resolve by
# icon name, but keep the two Fedora pixmap paths that Fedora's
# gnome-control-center build hard-codes for the About panel:
#
#   /usr/share/pixmaps/fedora_logo_med.png
#   /usr/share/pixmaps/fedora_whitelogo_med.png
#
# Those are not lookup fallbacks; they are compile-time filenames in
# Fedora's gnome-control-center.spec. Deleting them makes the About
# panel show no distributor logo, so overwrite them with Margine art
# instead.
#
# Confirmed on 2026-06-06 diagnose dump (daniel margine VM):
#   /usr/share/pixmaps/fedora-gdm-logo.png        (5.6 KB,  150×61)
#   /usr/share/pixmaps/fedora-logo-icon.png       (336 KB,  733×501)
#   /usr/share/pixmaps/fedora_logo_med.png        (10 KB,   250×102)
#   /usr/share/pixmaps/fedora-logo.png            (41 KB,   256×256)
#   /usr/share/pixmaps/fedora-logo-small.png      (3.3 KB,  48×48)
#   /usr/share/pixmaps/fedora-logo-sprite.png     (32 KB,   400×400)
#   /usr/share/pixmaps/fedora-logo-sprite.svg     (243 KB,  scalable)
#   /usr/share/pixmaps/fedora_whitelogo_med.png   (11 KB,   250×102)
#   /usr/share/pixmaps/system-logo-white.png      (41 KB,   256×256)
#   /usr/share/icons/hicolor/scalable/apps/fedora-logo-icon.svg
#   /usr/share/icons/hicolor/scalable/apps/fedora-logo-sprite.svg
# Plus /usr/share/icons/hicolor/scalable/places/fedora-logo-sprite.svg
# which we already blank at (d.ter) below — leave that alone.
rm -f /usr/share/pixmaps/fedora-gdm-logo.png \
      /usr/share/pixmaps/fedora-logo.png \
      /usr/share/pixmaps/fedora-logo-small.png \
      /usr/share/pixmaps/fedora-logo-sprite.png \
      /usr/share/pixmaps/fedora-logo-sprite.svg \
      /usr/share/pixmaps/system-logo-white.png \
      /usr/share/icons/hicolor/scalable/apps/fedora-logo-sprite.svg

# fedora-logo-icon is NOT deleted but REPLACED with the Margine mark
# (Bluefin pattern: keep Fedora icon NAMES, swap content). The name is
# HARDCODED in components we cannot rebuild: anaconda-live's
# fedora-welcome dialog (Adw.StatusPage iconName) + its autostart
# .desktop on the live ISO, and gnome-initial-setup's language page
# (maps os-release ID=fedora -> fedora-logo-icon). Deleting it (as we
# did before) renders the image-missing placeholder on both welcomes.
cp /usr/share/icons/hicolor/scalable/apps/margine-logo.svg \
   /usr/share/icons/hicolor/scalable/apps/fedora-logo-icon.svg
cp /usr/share/pixmaps/margine-logo.png /usr/share/pixmaps/fedora-logo-icon.png
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache --force --quiet /usr/share/icons/hicolor 2>/dev/null || true
fi
log "fedora-logo-icon now carries the Margine mark (fedora-welcome + gnome-initial-setup hardcode this name)"
# About-panel distributor logo = the Margine WORDMARK, not the square "m".
# fedora_logo_med.png is shown on LIGHT backgrounds (so a dark-text
# wordmark); fedora_whitelogo_med.png on DARK backgrounds (white-text
# wordmark). gnome-control-center renders these with GtkPicture
# can-shrink=false: intrinsic pixel size == logical size, so the assets
# are 256×64 (Fedora's originals are 250×102) — 1200×300 rendered 5×
# oversized and blurry at 200% scale.
retry_curl_strict "${MARGINE_REPO}/${MARGINE_REF}/assets/branding/margine-wordmark-dark.png"  /usr/share/pixmaps/fedora_logo_med.png
retry_curl_strict "${MARGINE_REPO}/${MARGINE_REF}/assets/branding/margine-wordmark-light.png" /usr/share/pixmaps/fedora_whitelogo_med.png
chmod 0644 /usr/share/pixmaps/fedora_logo_med.png /usr/share/pixmaps/fedora_whitelogo_med.png
log "About-panel distributor logo set to the Margine wordmark (dark=light-theme, white=dark-theme)"

# (d.bis) GDM greeter logo — explicitly DISABLED.
# The default org.gnome.login-screen.logo points at
# /usr/share/pixmaps/fedora-gdm-logo.png which on Bluefin DX is
# physically replaced with Bluefin's logo file. Pointing it at
# /usr/share/pixmaps/margine-logo.png produced a horrible result:
# our logo asset is a 2400×700 horizontal banner sized for headers,
# and GDM scales it to nearly fullscreen behind the password field.
# Cleanest fix: empty-string the key so GDM renders no logo at all.
cat > /etc/dconf/db/gdm.d/02-margine-logo <<'EOF'
[org/gnome/login-screen]
logo=''
EOF
mkdir -p /etc/dconf/db/gdm.d/locks
cat > /etc/dconf/db/gdm.d/locks/02-margine-logo <<'EOF'
/org/gnome/login-screen/logo
EOF
# Compile the gdm dconf db (best-effort; safe to skip if dconf is absent).
if command -v dconf >/dev/null 2>&1; then
  dconf update || { log "ERROR: dconf update failed — distro defaults database would ship stale/absent"; exit 1; }
fi
log "Installed: GDM background + greeter logo overrides"

# (e) /etc/issue — text-mode banner shown on console (e.g. emergency shell)
cat > /etc/issue <<'EOF'
Margine \r (\m) — Bluefin DX + CachyOS signed kernel
\d \t

EOF
chmod 0644 /etc/issue
log "Installed: /etc/issue"

# (f) Fastfetch config + margine-fetch wrapper.
# Fetch the ASCII logo and use it as fastfetch's --logo source.
mkdir -p /usr/share/fastfetch /usr/share/margine
retry_curl "${MARGINE_REPO}/${MARGINE_REF}/assets/branding/ascii-logo.txt" /usr/share/margine/ascii-logo.txt
chmod 0644 /usr/share/margine/ascii-logo.txt

# margine.jsonc + the margine-fetch wrapper ship as tracked files via
# system_files (migrated out of heredocs 2026-06-12 so linters and
# reviewers actually see them).

# (f.bis) System-wide fastfetch default config.
# Without this, vanilla `fastfetch` (no --config) walks its own search
# path: $XDG_CONFIG_HOME/fastfetch/config.jsonc (user, empty on a fresh
# install) → /etc/fastfetch/config.jsonc (we own this slot) →
# built-in default (= Fedora ASCII logo). Daniel noticed `fastfetch`
# was showing Fedora art instead of Margine even though
# /usr/share/margine/ascii-logo.txt was correctly installed.
# /etc/fastfetch/config.jsonc is a system_files symlink to
# margine.jsonc (was a build-time copy — one less divergence point).
log "fastfetch default config: system_files symlink /etc/fastfetch/config.jsonc → margine.jsonc"

# Recompile glib schemas so the appended background override takes effect.
glib-compile-schemas /usr/share/glib-2.0/schemas

# ---------------------------------------------------------------------------
# 4.bis Strip residual Bluefin/ublue branding from the inherited image
# ---------------------------------------------------------------------------
# Bluefin DX ships a pile of assets that bleed through into Margine's
# user-facing surfaces: app menu entries pointing at projectbluefin.io,
# a "/usr/share/backgrounds/bluefin/" wallpaper collection that shows
# up in Settings → Background, /usr/share/ublue-os/bluefin-logos/
# (chicken.png, dolly.png, karl.png mascots etc.), and a Firefox
# distribution config that injects Bluefin homepage/bookmarks.
#
# We can't avoid pulling them at build time (they're in the upstream
# RPMs), but we can scrub them after install. The dirs we DO keep
# under /usr/share/ublue-os/ are the functional ones: etc/ (akmods
# repos + certs), homebrew/, bling/, just/ — they're behavior, not
# branding.
log "Stripping Bluefin/ublue branding leftover from /usr/share + /usr/share/applications"

# (a) Visible app-menu entries that point at Bluefin docs/community.
# `discourse.desktop` opens github.com/ublue-os/bluefin/discussions →
# not a Margine resource at all → delete.
# `documentation.desktop` opens docs.projectbluefin.io → repoint at
# Margine's docs launcher + rename.
# `system-update.desktop` says "Update Bluefin, Flatpaks, …" → keep
# the underlying uupd flow (Margine uses it too) but rebrand.
rm -f /usr/share/applications/discourse.desktop

SCHEDULER_ICON="/usr/share/icons/hicolor/scalable/apps/margine-scheduler.svg"
DOCS_ICON="/usr/share/icons/hicolor/scalable/apps/margine-documentation.svg"
OFFLINE_DOCS_DIR="/usr/share/margine/offline-docs"
MARGINE_DOCS_BASE_URL="${MARGINE_DOCS_BASE_URL:-https://margine.the-empty.place}"

# Lightning-bolt app icon for the CPU scheduler — ties to Margine's perf /
# "snappier under load" theme, shipped locally instead of a generic MoreWaita
# system glyph.
cat >"$SCHEDULER_ICON" <<'SCHEDULER_ICON_SVG'
<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128">
  <defs>
    <linearGradient id="m-sched-bg" x1="64" y1="8" x2="64" y2="120" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#2b2018"/>
      <stop offset="1" stop-color="#171210"/>
    </linearGradient>
    <linearGradient id="m-sched-bolt" x1="64" y1="20" x2="64" y2="108" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#ffc06a"/>
      <stop offset="0.55" stop-color="#f97316"/>
      <stop offset="1" stop-color="#d9480f"/>
    </linearGradient>
  </defs>
  <rect x="8" y="8" width="112" height="112" rx="28" fill="url(#m-sched-bg)"/>
  <rect x="8.5" y="8.5" width="111" height="111" rx="27.5" fill="none" stroke="#ffffff" stroke-opacity="0.06"/>
  <path d="M74 18 L36 70 H58 L54 110 L92 58 H70 Z" fill="url(#m-sched-bolt)" stroke="#ffe0b0" stroke-opacity="0.5" stroke-width="2" stroke-linejoin="round"/>
</svg>
SCHEDULER_ICON_SVG
retry_curl_strict "${MARGINE_REPO}/${MARGINE_REF}/assets/branding/icons/margine-documentation.svg" "$DOCS_ICON"
# Ship the offline-docs builder in the image so the runtime refresh
# service (margine-docs-refresh.timer -> /usr/libexec/margine/docs-refresh)
# can rebuild the mirror into /var/lib/margine/offline-docs with the
# exact same fetch/rewrite logic that bakes this /usr seed.
install -Dm0755 /ctx/50-branding/build-offline-docs.py /usr/libexec/margine/build-offline-docs
python3 /usr/libexec/margine/build-offline-docs \
  --base-url "$MARGINE_DOCS_BASE_URL" \
  --output-dir "$OFFLINE_DOCS_DIR"
chmod 0644 "$SCHEDULER_ICON" "$DOCS_ICON"
chmod -R a+rX "$OFFLINE_DOCS_DIR"

# Offline-first docs enablement symlinks + the two rebranded app-menu
# entries (margine-documentation / margine-system-update) ship as
# tracked system_files now; only the Bluefin originals get removed here.
rm -f /usr/share/applications/documentation.desktop
rm -f /usr/share/applications/system-update.desktop

# (b) Icons that only served the deleted/rebrand entries.
rm -f /usr/share/icons/hicolor/scalable/places/ublue-discourse.svg \
      /usr/share/icons/hicolor/scalable/places/ublue-docs.svg \
      /usr/share/icons/hicolor/scalable/places/ublue-update.svg \
      /usr/share/icons/hicolor/scalable/actions/ublue-logo-symbolic.svg

# (b.bis) gnome-initial-setup's Language page renders
# <GtkImage icon_name='start-here-symbolic' pixel_size=96> as a 96px
# header above the locale list. Bluefin DX overrides this Adwaita icon
# with its mascot glyph. Replace it with a real path-based symbolic
# Margine glyph; GTK4 symbolic icons do not accept embedded raster
# <image> nodes.
retry_curl_strict "${MARGINE_REPO}/${MARGINE_REF}/assets/branding/start-here-symbolic.svg" /usr/share/icons/Adwaita/symbolic/places/start-here-symbolic.svg
chmod 0644 /usr/share/icons/Adwaita/symbolic/places/start-here-symbolic.svg
if grep -Eiq '<image[[:space:]>]|data:image/' /usr/share/icons/Adwaita/symbolic/places/start-here-symbolic.svg; then
  log "FATAL: start-here-symbolic.svg contains an embedded raster image; GTK4 symbolic icons require path/circle/rect primitives"
  exit 1
fi
log "Replaced start-here-symbolic.svg with Margine 'm' glyph ($(stat -c %s /usr/share/icons/Adwaita/symbolic/places/start-here-symbolic.svg) bytes)"

# (c) Bluefin wallpaper collection (Settings → Background spam).
rm -rf /usr/share/backgrounds/bluefin

# (d) Bluefin mascot logos (chicken.png, dolly.png, karl.png, bluefin.png)
# referenced by some Bluefin custom fastfetch configs / banner scripts
# that we override anyway. Safe to remove.
rm -rf /usr/share/ublue-os/bluefin-logos

# (e) Bluefin Firefox distribution config (bookmarks + start page injection).
# Margine ships Zen Browser via Flatpak; the Bluefin Firefox config is
# noise.
rm -rf /usr/share/ublue-os/firefox-config

# (f) Bluefin's fastfetch config (we ship our own at /etc/fastfetch/
# and /usr/share/fastfetch/margine.jsonc).
rm -f /usr/share/ublue-os/fastfetch.jsonc

# (g) Bluefin docs in /usr/share/doc/ — non-functional, just clutter.
rm -rf /usr/share/doc/bluefin

# (h) Bazaar app-store carousel wallpapers from Bluefin (16 .jxl files
# in /usr/etc/bazaar/, named NN-bluefin-{day,night}.jxl). They show up
# in Bazaar's spotlight banner / promo carousel. Replaced at build
# time with nothing — Bazaar falls back to its own placeholders. If
# we ever want Margine-branded promo art in Bazaar, drop matching
# 01-margine-{day,night}.jxl into /usr/etc/bazaar/ here.
rm -f /usr/etc/bazaar/*-bluefin-*.jxl /etc/bazaar/*-bluefin-*.jxl

# (i) Bluefin/ublue custom helper binaries that were dropped into
# /usr/bin by image-build scripts (not RPM-owned, so rpm verify
# misses them). Most are no-ops on Margine because the surrounding
# Bluefin infrastructure isn't here. Keep the ublue-image-info.sh +
# ublue-rollback-helper which integrate with bootc/ostree (functional);
# drop the rest. ublue-motd in particular spawns Bluefin's tipline at
# every shell login, very visible regression for a Margine user.
#
# IMPORTANT — bluefin-dx-groups KEPT (un-deleted 2026-06-04 after
# debugging fresh install): the Bluefin DX `bluefin-dx-groups.service`
# unit (inherited too) calls /usr/bin/bluefin-dx-groups at boot to add
# every wheel user to docker, incus-admin, libvirt groups. Useful for
# Margine too (same use case: admin user runs `docker ps`, `incus
# launch`, `virsh list` without sudo). When we deleted the binary the
# unit kept retrying with status=203/EXEC (Restart=on-failure
# RestartSec=30 forever) and daniel ended up only in `wheel`, not in
# docker/incus-admin/libvirt. Now both the binary AND the unit stay.
#
# For the ones we DO delete (ublue-system-setup, ublue-user-setup,
# etc.): also delete their systemd .service units so we don't hit the
# same 203/EXEC retry-loop. See "(j.bis)" block below.
rm -f /usr/bin/ublue-bling \
      /usr/bin/ublue-bling-fastfetch \
      /usr/bin/ublue-fastfetch \
      /usr/bin/ublue-motd \
      /usr/bin/ublue-privileged-setup \
      /usr/bin/ublue-system-setup \
      /usr/bin/ublue-user-setup

# (i.bis) Service units that ExecStart= the binaries we just deleted.
# Without removing these, systemd retries the failing service every
# 30s forever (Restart=on-failure StartLimitInterval=0). Observed on
# the 2026-06-04 fresh install: ublue-system-setup.service stuck in
# activating/failed loop.
for unit in ublue-system-setup.service ublue-user-setup.service; do
  rm -f "/usr/lib/systemd/system/$unit" \
        "/etc/systemd/system/$unit" \
        "/usr/lib/systemd/user/$unit" \
        "/etc/systemd/user/$unit"
  # Also remove from preset enable list (so systemctl preset doesn't
  # re-enable a now-missing unit).
  sed -i "/^enable $unit/d" /usr/lib/systemd/system-preset/*.preset 2>/dev/null || true
  sed -i "/^enable $unit/d" /usr/lib/systemd/user-preset/*.preset 2>/dev/null || true
done

# (j) /etc/profile.d/ Bluefin shell init.
# - ublue-fastfetch.sh sets   alias fastfetch=ublue-fastfetch (which we
#   just deleted), making vanilla `fastfetch` crash with "command not
#   found". Same for neofetch/neowofetch aliases.
# - ublue-motd.sh calls ublue-motd (deleted) at every shell login →
#   prints "ublue-motd: command not found" before the prompt.
# - 91-bluefin-aliases.sh ships `alias rl=ramalama`. Branding, not
#   functional for Margine.
# - 90-bluefin-starship.sh wires up Bluefin's starship theme; Margine
#   doesn't ship starship by default so the file is a no-op, but the
#   'bluefin' in the name is misleading.
# All four also live in /usr/etc/profile.d/ (ostree factory). We
# strip both copies so the 3-way merge at user-boot doesn't restore
# them.
rm -f /etc/profile.d/ublue-fastfetch.sh \
      /etc/profile.d/ublue-motd.sh \
      /etc/profile.d/91-bluefin-aliases.sh \
      /etc/profile.d/90-bluefin-starship.sh \
      /usr/etc/profile.d/ublue-fastfetch.sh \
      /usr/etc/profile.d/ublue-motd.sh \
      /usr/etc/profile.d/91-bluefin-aliases.sh \
      /usr/etc/profile.d/90-bluefin-starship.sh

# (k) /etc/dconf/db/distro.d/ — Bluefin dconf overrides for app folder
# layout, keybindings, Ptyxis colour palette, and extension prefs.
# Several actively conflict with Margine intent:
# - 02-bluefin-keybindings: Bluefin window-manager binds collide with
#   the Hyprland-style ones margine-bootstrap applies (Super+1..0
#   workspaces, Super+arrow focus, Super+return terminal).
# - 03-bluefin-ptyxis-palette: Bluefin terminal colours — Margine
#   should pick its own palette (yellow accent, autumn-warm) later.
# - 04-bluefin-logomenu-extension: logo-menu prefs that point at the
#   Bluefin LogoMenu icon — extension is in zz0's enabled-extensions
#   but our zz1 overrides remove it from enabled set anyway.
# - 05-bluefin-searchlight-extension: search-light prefs, partially
#   useful but tinted with Bluefin defaults.
# - 01-bluefin-folders: Gaming/Utilities/Games app folder layout.
#   Margine has its own folder layout via configure-gnome-folders
#   (margine-fedora-atomic).
# - locks/01-bluefin-locked-settings: dconf locks that prevent the
#   user from overriding any of the above. With the overrides gone,
#   the locks reference non-existent keys.
# Plus the /usr/etc/ factory copies (same 3-way-merge concern as
# profile.d above).
rm -f /etc/dconf/db/distro.d/*bluefin* \
      /etc/dconf/db/distro.d/locks/*bluefin* \
      /usr/etc/dconf/db/distro.d/*bluefin* \
      /usr/etc/dconf/db/distro.d/locks/*bluefin*
# Rebuild dconf db so removed overrides don't keep being compiled.
if command -v dconf >/dev/null 2>&1; then
  dconf update || { log "ERROR: dconf update failed (final pass)"; exit 1; }
fi

# Update the icon-theme cache so removed SVGs disappear from icon
# lookups immediately at first boot.
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache --force --quiet /usr/share/icons/hicolor 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# HiDPI GRUB: bake a large console font for the boot menu.
# ---------------------------------------------------------------------------
# GRUB has no DPI scaling, and the old gfxmode-low trick is firmware-dependent
# (the GOP/VBE must expose the chosen mode or GRUB falls back to native ->
# tiny glyphs again — which is why every gfxmode iteration was a no-op). A
# baked LARGE .pf2 is resolution-independent. Generate it from **Noto Sans
# Mono** (present in the base image: google-noto-sans-mono-vf-fonts) with an
# explicit family name so the embedded font name is the stable "Margine
# Regular 36" that 05_margine-gfxmode.cfg selects via gfxterm_font.
# IMPORTANT — why Noto, not Liberation Mono: GRUB's gfxterm menu border is drawn
# with box-drawing glyphs (U+2500 block). Liberation Mono LACKS that block, so a
# font baked from it rendered the menu border as rows of missing-glyph boxes
# (┌┐└┘─│ → "?"). Noto Sans Mono ships the full U+2500-25FF range, fixing the
# border. Place the font under the bootupd static tree: a FRESH install's
# `bootupctl install --with-static-configs` ships it to /boot automatically;
# EXISTING installs pull it via the margine-grub-hidpi service / ujust recipe
# (bootupd does NOT re-render the static grub.cfg on `bootc upgrade`).
log "Baking HiDPI GRUB font (margine.pf2)"
# Variable-font filename carries an axis suffix (NotoSansMono[wght].ttf); glob it.
_grub_ttf="$(ls /usr/share/fonts/google-noto-vf/NotoSansMono*.ttf 2>/dev/null | head -1)"
[[ -n "$_grub_ttf" && -f "$_grub_ttf" ]] || { log "ERROR: Noto Sans Mono TTF not found under /usr/share/fonts/google-noto-vf/ — cannot bake GRUB font"; exit 1; }
command -v grub2-mkfont >/dev/null 2>&1 || { log "ERROR: grub2-mkfont missing — cannot bake GRUB font"; exit 1; }
install -d -m0755 /usr/lib/bootupd/grub2-static/fonts
grub2-mkfont -s 36 -n "Margine" \
  -o /usr/lib/bootupd/grub2-static/fonts/margine.pf2 "$_grub_ttf" \
  || { log "ERROR: grub2-mkfont failed"; exit 1; }
log "GRUB font baked: $(stat -c %s /usr/lib/bootupd/grub2-static/fonts/margine.pf2) bytes (name 'Margine Regular 36')"

log "Bluefin branding stripped"

# ---------------------------------------------------------------------------
