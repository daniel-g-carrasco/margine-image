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
# 0. OS identity — make the system identify as Margine
# ---------------------------------------------------------------------------
# Override the os-release file so commands like `cat /etc/os-release`,
# `hostnamectl`, GNOME's About panel, and our own validate-atomic-layout
# all see "Margine". We keep ID_LIKE="fedora bluefin" so tools that
# branch on Fedora-derivative behavior still work.
#
# IMPORTANT: we write os-release as a REGULAR FILE at BOTH /etc/os-release
# AND /usr/lib/os-release, not as a symlink. Why:
#
# At early boot, systemd's switch-root path checks for os-release in the
# new root with `openat(fd, "etc/os-release", O_NOFOLLOW)` first, then
# `openat(fd, "usr/lib/os-release", O_NOFOLLOW)`. If /etc/os-release is
# a symlink to /usr/lib/os-release, the first open fails (O_NOFOLLOW on
# a symlink → ELOOP) and falls through to the /usr/lib check.
#
# BUT at switch-root time, /usr isn't yet mounted via composefs in
# bootc-style deployments. The fallback path is therefore inaccessible.
# Without an os-release available pre-composefs, systemd errors with
# "Specified switch root path '/sysroot' does not seem to be an OS
# tree. os-release file is missing." and drops to emergency shell.
#
# Bluefin's image happens to work because their rechunk pipeline
# re-commits everything in an ostree-coherent format where composefs
# is set up by switch-root time. We don't rechunk (yet — that's a
# future architectural change), so we route around the problem by
# making sure /etc/os-release is a standalone file, accessible
# regardless of composefs/usr state.
#
# See docs/lessons-learned/2026-05-28-initramfs-and-bootc-labels.md
# for the full investigation.
log "Stamping os-release files (real files, NOT symlinks) as Margine"

FEDORA_VER="$(rpm -E %fedora)"
BUILD_DATE="$(date -u +%Y%m%d)"

OS_RELEASE_CONTENT=$(cat <<EOF
NAME="Margine"
VERSION="${FEDORA_VER} (Margine)"
ID=margine
ID_LIKE="fedora bluefin"
VERSION_ID=${FEDORA_VER}
VERSION_CODENAME=""
PLATFORM_ID="platform:f${FEDORA_VER}"
PRETTY_NAME="Margine ${FEDORA_VER} (${BUILD_DATE})"
VARIANT="Margine"
VARIANT_ID=margine
ANSI_COLOR="0;38;2;232;186;0"
LOGO=margine-logo
CPE_NAME="cpe:/o:daniel-g-carrasco:margine:${FEDORA_VER}"
HOME_URL="https://github.com/daniel-g-carrasco/margine-image"
DOCUMENTATION_URL="https://github.com/daniel-g-carrasco/margine-fedora-atomic"
SUPPORT_URL="https://github.com/daniel-g-carrasco/margine-image/issues"
BUG_REPORT_URL="https://github.com/daniel-g-carrasco/margine-image/issues"
DEFAULT_HOSTNAME="margine"
EOF
)

# /usr/lib/os-release as a regular file (the canonical location).
printf '%s\n' "$OS_RELEASE_CONTENT" > /usr/lib/os-release
chmod 0644 /usr/lib/os-release

# /etc/os-release as a regular file (NOT a symlink) so systemd's
# switch-root check finds it before composefs/usr is mounted.
rm -f /etc/os-release
printf '%s\n' "$OS_RELEASE_CONTENT" > /etc/os-release
chmod 0644 /etc/os-release

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
    org.gnome.gitlab.somas.Apostrophe ; do
  # NB: VS Code is intentionally NOT installed here. Bluefin DX
  # preinstalls Visual Studio Code from the Microsoft repository with
  # the dev container tooling already wired up (devpod, distrobox
  # integration, etc.); adding VSCodium on top would just create a
  # second, redundant editor.
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
enabled-extensions=['appindicatorsupport@rgcjonas.gmail.com', 'bazaar-integration@kolunmi.github.io', 'blur-my-shell@aunetx', 'dash-to-dock@micxgx.gmail.com', 'gradia-integration@alexandervanhee.github.io', 'gsconnect@andyholmes.github.io', 'search-light@icedman.github.com', 'tilingshell@ferrarodomenico.com']
favorite-apps=['app.zen_browser.zen.desktop', 'org.mozilla.Thunderbird.desktop', 'org.gnome.Nautilus.desktop', 'org.gnome.Ptyxis.desktop', 'code.desktop']

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

# Preflight: confirm we can reach the spec repo before fetching anything.
# Without this, individual silent-skip fallbacks (the previous pattern)
# masked real connectivity / repo-visibility bugs and shipped incomplete
# images. Fail loud + fail early.
log "Preflight: probing spec repo at ${MARGINE_REPO}/${MARGINE_REF}/"
if ! curl --fail --silent --show-error --head -L \
     "${MARGINE_REPO}/${MARGINE_REF}/README.md" >/dev/null; then
  err() { printf '[margine-build] ERROR: %s\n' "$*" >&2; }
  err "cannot reach the Margine spec repo (${MARGINE_REPO}/${MARGINE_REF}/)."
  err "Check that the repo is PUBLIC on GitHub and that the runner has network access."
  exit 1
fi
log "Preflight OK"

for s in \
    configure-default-applications \
    configure-gnome-app-folders \
    configure-gnome-appearance \
    configure-gnome-extensions \
    configure-gnome-keybindings \
    configure-home-layout \
    install-user-extensions \
    validate-atomic-layout \
    validate-cachyos-kernel \
    validate-hardware-media-stack \
    validate-gaming-runtime \
    collect-diagnostics ; do
  curl --fail --silent --show-error -L \
       "${MARGINE_REPO}/${MARGINE_REF}/scripts/${s}" \
       -o "/usr/bin/margine-${s}"
  chmod 0755 "/usr/bin/margine-${s}"
  log "Installed: /usr/bin/margine-${s}"
done

# Also pull the declarations YAML the scripts read.
mkdir -p /usr/share/margine
curl --fail --silent --show-error -L \
     "${MARGINE_REPO}/${MARGINE_REF}/declarations/margine-atomic.yaml" \
     -o /usr/share/margine/declarations.yaml
log "Installed: /usr/share/margine/declarations.yaml"

# Set MARGINE_DECLARATIONS env for the scripts to pick up the system copy.
cat > /etc/profile.d/margine.sh <<'EOF'
export MARGINE_DECLARATIONS=/usr/share/margine/declarations.yaml
EOF
chmod 0644 /etc/profile.d/margine.sh

# ---------------------------------------------------------------------------
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
curl --fail --silent --show-error -L \
    "${MARGINE_REPO}/${MARGINE_REF}/assets/branding/margine-logo.png" \
    -o /usr/share/pixmaps/margine-logo.png
chmod 0644 /usr/share/pixmaps/margine-logo.png
log "Installed: /usr/share/pixmaps/margine-logo.png"

# (b) Wallpaper → /usr/share/backgrounds/margine/ + dconf override so it's
#     the default desktop background (light + dark).
mkdir -p /usr/share/backgrounds/margine
curl --fail --silent --show-error -L \
    "${MARGINE_REPO}/${MARGINE_REF}/assets/branding/wallpaper-autumn-leaves.png" \
    -o /usr/share/backgrounds/margine/autumn-leaves.png
chmod 0644 /usr/share/backgrounds/margine/autumn-leaves.png
log "Installed: /usr/share/backgrounds/margine/autumn-leaves.png"

# Desktop background gschema override — set on the existing zz1 file so
# it loads after Bluefin's zz0.
cat >> /usr/share/glib-2.0/schemas/zz1-margine.gschema.override <<'OVERRIDE'

[org.gnome.desktop.background]
picture-uri='file:///usr/share/backgrounds/margine/autumn-leaves.png'
picture-uri-dark='file:///usr/share/backgrounds/margine/autumn-leaves.png'
picture-options='zoom'
primary-color='#2C1810'
secondary-color='#1A0E08'

[org.gnome.desktop.screensaver]
picture-uri='file:///usr/share/backgrounds/margine/autumn-leaves.png'
picture-options='zoom'
primary-color='#2C1810'
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
  curl --fail --silent --show-error -L \
      "${MARGINE_REPO}/${MARGINE_REF}/assets/branding/plymouth/${f}" \
      -o "/usr/share/plymouth/themes/margine/${f}"
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
picture-uri='file:///usr/share/backgrounds/margine/autumn-leaves.png'
picture-uri-dark='file:///usr/share/backgrounds/margine/autumn-leaves.png'
picture-options='zoom'
primary-color='#2C1810'
EOF
# Compile the gdm dconf db (best-effort; safe to skip if dconf is absent).
if command -v dconf >/dev/null 2>&1; then
  dconf update || log "(warning: dconf update failed)"
fi
log "Installed: GDM background override"

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
curl --fail --silent --show-error -L \
    "${MARGINE_REPO}/${MARGINE_REF}/assets/branding/ascii-logo.txt" \
    -o /usr/share/margine/ascii-logo.txt
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
log "Installed: /usr/share/fastfetch/margine.jsonc + /usr/bin/margine-fetch"

# Recompile glib schemas so the appended background override takes effect.
glib-compile-schemas /usr/share/glib-2.0/schemas

# ---------------------------------------------------------------------------
# 5. Margine ujust recipes (gaming layer opt-in)
# ---------------------------------------------------------------------------
# Bluefin ships a `ujust` wrapper that loads recipe files from
# /usr/share/ublue-os/just/. Drop our 99-margine.just there so the user
# can run `ujust margine-gaming` to opt into the gaming layer
# (Steam Flatpak + Lutris/Heroic/Bottles + gamescope/mangohud/vkBasalt/
# gamemode/goverlay/steam-devices layered via rpm-ostree).
#
# Modeled after Bazzite's gaming bake, but opt-in: Margine default stays
# minimal; gamers run one command and get a working stack.
log "Installing Margine ujust recipes"
install -Dm0644 /ctx/99-margine.just /usr/share/ublue-os/just/99-margine.just

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
log "Margine build modifications complete."
log "Image is ready: Bluefin DX + CachyOS signed kernel + Margine deltas."
