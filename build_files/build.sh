#!/bin/bash
#
# Margine image — main build modifications on top of Bluefin DX.
#
# Runs INSIDE the Bluefin DX layer at image build time. By the time we
# get here, the CachyOS kernel has already replaced the stock kernel
# (see Containerfile and build_files/custom-kernel/install.sh).
#
# What this script does:
#
#   1. Install kitty as a system Flatpak (preinstalled, not a host RPM).
#   2. Stage Margine-specific GNOME defaults that override Bluefin's
#      zz0-bluefin-modifications.gschema.override on the points we care
#      about (default browser = Zen, default terminal = kitty, branding
#      extensions disabled, keybindings nudges).
#   3. Install scripts/configure-gnome-* from margine-fedora-atomic into
#      /usr/bin so users can re-apply on demand.
#
# NO rpm-ostree layered packages at runtime: everything is baked here.
#
set -euo pipefail

log() { printf '[margine-build] %s\n' "$*"; }

# ---------------------------------------------------------------------------
# 1. Margine default Flatpak apps
# ---------------------------------------------------------------------------
# Bluefin ships Flathub already configured. We add the Margine default
# app set to the system Flatpak preinstall list so it ships preinstalled
# and works without per-user setup.
#
# Terminal: we DO NOT preinstall kitty. Bluefin's default terminal
# (Ptyxis) is the chosen one. Users who want a different terminal can
# install it themselves via Flatpak or distrobox.
log "Adding Margine default Flatpaks to /etc/ublue-os/system-flatpaks.list"

mkdir -p /etc/ublue-os
touch /etc/ublue-os/system-flatpaks.list
for app in \
    app.zen_browser.zen \
    com.bitwarden.desktop \
    org.libreoffice.LibreOffice \
    com.github.neithern.g4music \
    org.gimp.GIMP \
    org.inkscape.Inkscape \
    org.darktable.Darktable \
    org.audacityteam.Audacity \
    com.obsproject.Studio \
    com.github.wwmm.easyeffects \
    fm.reaper.Reaper \
    com.vscodium.codium ; do
  grep -qxF "$app" /etc/ublue-os/system-flatpaks.list \
    || echo "$app" >> /etc/ublue-os/system-flatpaks.list
done

log "system-flatpaks.list now:"
cat /etc/ublue-os/system-flatpaks.list

# ---------------------------------------------------------------------------
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
enabled-extensions=['appindicatorsupport@rgcjonas.gmail.com', 'blur-my-shell@aunetx', 'dash-to-dock@micxgx.gmail.com', 'gsconnect@andyholmes.github.io', 'search-light@icedman.github.com', 'tilingshell@ferrarodomenico.com']
favorite-apps=['app.zen_browser.zen.desktop', 'org.mozilla.Thunderbird.desktop', 'org.gnome.Nautilus.desktop', 'org.gnome.Ptyxis.desktop', 'com.vscodium.codium.desktop']

[org.gnome.desktop.interface]
accent-color='yellow'

# Terminal default: leave Bluefin's choice (Ptyxis) — do NOT override
# org.gnome.desktop.default-applications.terminal. Users who want a
# different terminal can install one and flip the setting per session.

[org.gnome.shell.extensions.tilingshell]
enable-autotiling=true
enable-snap-assist=true
enable-window-border=true
inner-gaps=4
outer-gaps=4
OVERRIDE

log "Compiling glib schemas"
glib-compile-schemas /usr/share/glib-2.0/schemas

# ---------------------------------------------------------------------------
# 3. Bundle the configure-gnome-* helpers from margine-fedora-atomic
# ---------------------------------------------------------------------------
# These are user-state helpers. We don't run them at image build time
# (no user yet); we install them so the user can run e.g.
#   margine-configure-keybindings --apply
# from any terminal post-install.
#
# The scripts live in the margine-fedora-atomic repo, fetched at build
# time. Pin a specific commit in CI so the image is reproducible.
log "Fetching Margine configure-* scripts"

MARGINE_REPO="https://raw.githubusercontent.com/daniel-g-carrasco/margine-fedora-atomic"
MARGINE_REF="${MARGINE_REF:-main}"

for s in \
    configure-default-applications \
    configure-gnome-app-folders \
    configure-gnome-appearance \
    configure-gnome-extensions \
    configure-gnome-keybindings \
    install-user-extensions ; do
  if curl --fail --silent --show-error -L \
       "${MARGINE_REPO}/${MARGINE_REF}/scripts/${s}" \
       -o "/usr/bin/margine-${s}"; then
    chmod 0755 "/usr/bin/margine-${s}"
    log "Installed: /usr/bin/margine-${s}"
  else
    log "(skip: could not fetch ${s})"
  fi
done

# Also pull the declarations YAML the scripts read.
mkdir -p /usr/share/margine
if curl --fail --silent --show-error -L \
     "${MARGINE_REPO}/${MARGINE_REF}/declarations/margine-atomic.yaml" \
     -o /usr/share/margine/declarations.yaml; then
  log "Installed: /usr/share/margine/declarations.yaml"
fi

# Set MARGINE_DECLARATIONS env for the scripts to pick up the system copy.
cat > /etc/profile.d/margine.sh <<'EOF'
export MARGINE_DECLARATIONS=/usr/share/margine/declarations.yaml
EOF
chmod 0644 /etc/profile.d/margine.sh

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
log "Margine build modifications complete."
log "Image is ready: Bluefin DX + CachyOS signed kernel + Margine deltas."
