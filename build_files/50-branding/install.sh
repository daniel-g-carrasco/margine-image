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

# (a) Logo PNG → /usr/share/pixmaps/ so /etc/os-release's LOGO=margine-logo
#     resolves and GNOME About panel shows it.
mkdir -p /usr/share/pixmaps
retry_curl "${MARGINE_REPO}/${MARGINE_REF}/assets/branding/margine-logo.png" /usr/share/pixmaps/margine-logo.png
chmod 0644 /usr/share/pixmaps/margine-logo.png
log "Installed: /usr/share/pixmaps/margine-logo.png"

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
  dconf update || log "(warning: dconf update failed)"
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

cat > /usr/share/fastfetch/margine.jsonc <<'EOF'
{
  "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
  "logo": {
    "source": "/usr/share/margine/ascii-logo.txt",
    "type": "file",
    "color": { "1": "yellow" },
    "padding": { "right": 2 }
  },
  "display": {
    "separator": " · "
  },
  "modules": [
    "title",
    "separator",
    "os",
    "kernel",
    "uptime",
    "packages",
    "shell",
    "wm",
    "terminal",
    "cpu",
    "gpu",
    "memory",
    "swap",
    "disk",
    "localip",
    "battery",
    "locale",
    "break",
    "colors"
  ]
}
EOF
chmod 0644 /usr/share/fastfetch/margine.jsonc

cat > /usr/bin/margine-fetch <<'EOF'
#!/usr/bin/sh
# margine-fetch: fastfetch with Margine ASCII logo + module set.
exec fastfetch --config /usr/share/fastfetch/margine.jsonc "$@"
EOF
chmod 0755 /usr/bin/margine-fetch

# (f.bis) System-wide fastfetch default config.
# Without this, vanilla `fastfetch` (no --config) walks its own search
# path: $XDG_CONFIG_HOME/fastfetch/config.jsonc (user, empty on a fresh
# install) → /etc/fastfetch/config.jsonc (we own this slot) →
# built-in default (= Fedora ASCII logo). Daniel noticed `fastfetch`
# was showing Fedora art instead of Margine even though
# /usr/share/margine/ascii-logo.txt was correctly installed.
# Pointing /etc/fastfetch/config.jsonc at our margine.jsonc fixes
# the default invocation; margine-fetch still works as before.
mkdir -p /etc/fastfetch
cp /usr/share/fastfetch/margine.jsonc /etc/fastfetch/config.jsonc
chmod 0644 /etc/fastfetch/config.jsonc
log "Installed: /etc/fastfetch/config.jsonc (default config → Margine ASCII)"

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
# Margine's spec repo + rename.
# `system-update.desktop` says "Update Bluefin, Flatpaks, …" → keep
# the underlying uupd flow (Margine uses it too) but rebrand.
rm -f /usr/share/applications/discourse.desktop

cat > /usr/share/applications/margine-documentation.desktop <<'EOF'
[Desktop Entry]
Type=Application
NoDisplay=false
Terminal=false
Exec=xdg-open https://github.com/daniel-g-carrasco/margine-fedora-atomic
Icon=help-browser
Name=Margine documentation
Comment=Spec + architecture for Margine OS (margine-fedora-atomic on GitHub)
Categories=System;Documentation;
EOF
rm -f /usr/share/applications/documentation.desktop

cat > /usr/share/applications/margine-system-update.desktop <<'EOF'
[Desktop Entry]
Type=Application
NoDisplay=false
Terminal=true
Exec=ujust update
Icon=system-software-update
Name=Margine system update
Comment=Run Margine's full system update (bootc + flatpak + distrobox via uupd)
Categories=ConsoleOnly;System;
EOF
rm -f /usr/share/applications/system-update.desktop

# (b) Icons that only served the deleted/rebrand entries.
rm -f /usr/share/icons/hicolor/scalable/places/ublue-discourse.svg \
      /usr/share/icons/hicolor/scalable/places/ublue-docs.svg \
      /usr/share/icons/hicolor/scalable/places/ublue-update.svg \
      /usr/share/icons/hicolor/scalable/actions/ublue-logo-symbolic.svg

# (b.bis) gnome-initial-setup's welcome page (first screen, language
# picker) renders <GtkImage icon_name='start-here-symbolic' pixel_size=96>
# as a 96px header above the locale list. Bluefin DX has overridden
# /usr/share/icons/Adwaita/symbolic/places/start-here-symbolic.svg
# with a velociraptor footprint (their mascot) — daniel saw that
# 'dinosaur' on the Benvenuti page of a fresh Margine install.
# Replace it with the Margine wordmark 'm' glyph (pixel art SVG,
# same source as the favicon). Tracked in
# margine-fedora-atomic assets/branding/start-here-symbolic.svg.
retry_curl_strict "${MARGINE_REPO}/${MARGINE_REF}/assets/branding/start-here-symbolic.svg" /usr/share/icons/Adwaita/symbolic/places/start-here-symbolic.svg
chmod 0644 /usr/share/icons/Adwaita/symbolic/places/start-here-symbolic.svg
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
  dconf update 2>/dev/null || true
fi

# Update the icon-theme cache so removed SVGs disappear from icon
# lookups immediately at first boot.
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache --force --quiet /usr/share/icons/hicolor 2>/dev/null || true
fi

log "Bluefin branding stripped"

# ---------------------------------------------------------------------------
