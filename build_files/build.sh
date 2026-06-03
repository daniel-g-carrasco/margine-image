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

# os-release(5) layout: ID names the OS *family* (Fedora). VARIANT_ID is the
# specific spin/variant within that family. Fedora itself does this exactly
# (Workstation/Server/Silverblue/Kinoite all set ID=fedora and a different
# VARIANT_ID). We follow the same pattern:
#
#   * NAME / PRETTY_NAME / VARIANT all say "Margine" — every UI surface that
#     reads os-release (GNOME About panel, hostnamectl, neofetch, the
#     gdm/Plymouth themes) reads NAME or PRETTY_NAME, not ID.
#   * ID=fedora — so distro-tooling that does an exact lookup by ID-VERSION_ID
#     finds a definition for us. The big motivator is bootc-image-builder,
#     which fails the anaconda-iso build with "could not find def file for
#     distro margine-44" if ID=margine (BIB does NOT fall back to ID_LIKE,
#     and there's no --distro CLI override — confirmed against osbuild/images
#     pkg/distro/defs/id.go). Setting ID=fedora makes BIB resolve to fedora-44
#     which is what Bluefin DX is in fact based on.
#   * VARIANT_ID=margine — the discriminator. validate-margine-system in
#     margine-fedora-atomic now checks this instead of ID to identify a
#     Margine install.
OS_RELEASE_CONTENT=$(cat <<EOF
NAME="Margine"
VERSION="${FEDORA_VER} (Margine)"
ID=fedora
ID_LIKE=bluefin
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
# 0.bis Populate /etc/passwd and /etc/group from factory (/usr/lib/*)
# ---------------------------------------------------------------------------
# Bluefin DX (like most modern Fedora-based containers) ships /etc/passwd
# and /etc/group as a near-empty file ("root: only"), expecting systemd-
# sysusers to materialize entries from /usr/lib/sysusers.d/ at first boot.
# That works fine on a stock install — but when rechunk runs over our
# image, it copies /etc/ into /usr/etc/ as the ostree "factory" view.
# That factory then has only "root". On a rebase from Bluefin (where
# /etc/passwd is full because Anaconda populated it), ostree's 3-way
# merge between {old factory ≈ implicit, old /etc, new factory = root-only}
# strips out everything but "root" and the user's own account.
#
# Symptoms on the post-rebase machine: dozens of "Failed to resolve group
# 'audio'/'kvm'/'tty'/..." errors at boot, broken TPM, broken audio
# permissions, etc.
#
# Fix: at build time, copy the canonical factory files into /etc so that
# the post-rechunk /usr/etc/ contains the full list. ostree then knows
# what the "Margine factory" looks like and the rebase merge preserves
# the system users.
if [[ -f /usr/lib/passwd ]] && [[ -f /usr/lib/group ]]; then
  log "Seeding /etc/passwd + /etc/group from /usr/lib/{passwd,group} factory"
  # Preserve any locally-modified entries (e.g. root with a custom shell)
  # by letting our local /etc lines override factory ones for the same name.
  python3 <<'PY'
def load(p):
    try:
        with open(p) as f: return [l.rstrip("\n") for l in f if l.strip()]
    except FileNotFoundError: return []
def by_name(lines):
    return {l.split(":",1)[0]: l for l in lines}
for kind in ("passwd", "group"):
    local   = by_name(load(f"/etc/{kind}"))
    factory = by_name(load(f"/usr/lib/{kind}"))
    merged  = dict(factory); merged.update(local)
    def sort_key(line):
        try:
            uid = int(line.split(":")[2])
            return (uid >= 1000, uid)
        except Exception:
            return (True, 999999)
    import os
    tmp = f"/etc/{kind}.new"
    with open(tmp, "w") as f:
        for l in sorted(merged.values(), key=sort_key):
            f.write(l + "\n")
    os.replace(tmp, f"/etc/{kind}")
    print(f"  /etc/{kind}: was {len(local)} entries, now {len(merged)} (added {len(merged)-len(local)})")
PY
  chmod 0644 /etc/passwd /etc/group
else
  log "WARNING: /usr/lib/passwd or /usr/lib/group missing — skipping factory seed"
fi

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
log "Writing /usr/share/flatpak/preinstall.d/margine-defaults.preinstall"

# Bluefin DX uses the upstream Flatpak `preinstall` API (introduced in
# Flatpak 1.16): /usr/share/flatpak/preinstall.d/*.preinstall files
# are read by `flatpak-preinstall.service` at boot. The older uBlue
# /etc/ublue-os/system-flatpaks.list mechanism is NO LONGER honored
# on current Bluefin DX — files there are silently ignored.
#
# VS Code is intentionally NOT in this list: Bluefin DX preinstalls
# Visual Studio Code from the Microsoft repo with dev container
# tooling already wired up; layering VSCodium would create a
# redundant second editor.
mkdir -p /usr/share/flatpak/preinstall.d
{
  echo "# Margine default applications — installed via flatpak preinstall API."
  echo "# Generated by build.sh; do not edit by hand."
  echo
  # Margine canonical preinstall set. The rule is "what a fresh
  # Margine user expects to find on the desktop after first boot,
  # without having to open Bazaar and remember 9 app names".
  #
  # Three buckets (kept in this order so the file is easy to read):
  #   1. Core productivity (browser, mail, password, office, dev)
  #   2. GNOME standard apps that Bluefin DX strips from upstream
  #      Silverblue/Workstation (Snapshot, Showtime, Papers, Loupe,
  #      Sound Recorder). We add them back so the desktop feels
  #      "complete" out of the box.
  #   3. Creative / utility (GIMP, Inkscape, Pinta, darktable,
  #      Audacity, OBS, Reaper, EasyEffects, Apostrophe, g4music,
  #      Blanket, Fragments).
  #
  # Keep this list in sync with:
  #   - declarations/margine-atomic.yaml flatpak section
  #   - margine-fedora-atomic scripts/validate-margine-system
  #     EXPECTED_FLATPAKS array (which is the authoritative
  #     post-boot acceptance test for "did everything install").
  for app in \
      app.zen_browser.zen \
      org.mozilla.thunderbird_esr \
      com.bitwarden.desktop \
      org.libreoffice.LibreOffice \
      com.mattjakeman.ExtensionManager \
      org.gnome.Snapshot \
      org.gnome.Showtime \
      org.gnome.Papers \
      org.gnome.Loupe \
      org.gnome.SoundRecorder \
      com.github.neithern.g4music \
      com.rafaelmardojai.Blanket \
      de.haeckerfelix.Fragments \
      org.gimp.GIMP \
      org.inkscape.Inkscape \
      com.github.PintaProject.Pinta \
      org.darktable.Darktable \
      org.audacityteam.Audacity \
      com.obsproject.Studio \
      com.github.wwmm.easyeffects \
      fm.reaper.Reaper \
      org.gnome.gitlab.somas.Apostrophe ; do
    # Why each non-obvious entry is here:
    #
    # thunderbird_esr: declared as the system's mail_reader in
    #   declarations/margine-atomic.yaml; configure-default-applications
    #   sets it as MIME handler, so the app actually has to exist.
    #
    # Extension Manager (jakeman): GUI to browse/install/configure
    #   GNOME Shell extensions. Margine has ~10 enabled (o-tiling,
    #   search-light, caffeine, hide-cursor, etc.) and users have no
    #   way to discover/tune them without a dedicated app. GNOME's
    #   own `org.gnome.Extensions` is NOT in Bluefin DX base.
    #
    # Snapshot / Showtime / Papers / Loupe / SoundRecorder:
    #   GNOME's modern "default apps" (camera/webcam, video player,
    #   PDF reader, image viewer, audio recorder). Fedora
    #   Workstation/Silverblue ship them by default; Bluefin DX
    #   intentionally strips them to keep its image lean. We
    #   re-add the modern (-not-deprecated) versions: Snapshot
    #   replaces Cheese, Showtime replaces Totem, Papers replaces
    #   Evince, Loupe replaces Eye of GNOME.
    #
    # Pinta: lightweight image editor (Paint.NET-style). Bluefin's
    #   own Bazaar preinstall list includes it; we lost it via the
    #   "we manage our own preinstall.d" override.
    #
    # Blanket: ambient sound mixer (rain, fireplace, etc.) — a
    #   common "wellness" app that's tiny and beloved.
    #
    # Fragments: GNOME BitTorrent client. Margine publishes its
    #   own ISOs as torrents (see docs/19-iso-distribution.md), so
    #   a working torrent client out of the box is consistent.
    echo "[Flatpak Preinstall $app]"
    echo "Branch=stable"
    echo "IsRuntime=false"
    echo
  done
} > /usr/share/flatpak/preinstall.d/margine-defaults.preinstall
chmod 0644 /usr/share/flatpak/preinstall.d/margine-defaults.preinstall

log "margine-defaults.preinstall now:"
cat /usr/share/flatpak/preinstall.d/margine-defaults.preinstall

# Drop the legacy uBlue file if it exists (left behind by older builds
# or by Bluefin DX itself if it still has one). Prevents confusion.
rm -f /etc/ublue-os/system-flatpaks.list

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
enabled-extensions=['appindicatorsupport@rgcjonas.gmail.com', 'bazaar-integration@kolunmi.github.io', 'blur-my-shell@aunetx', 'dash-to-dock@micxgx.gmail.com', 'gradia-integration@alexandervanhee.github.io', 'gsconnect@andyholmes.github.io', 'search-light@icedman.github.com', 'o-tiling@oliwebd.github.com', 'hide-cursor@elcste.com', 'caffeine@patapon.info']
favorite-apps=['app.zen_browser.zen.desktop', 'org.mozilla.Thunderbird.desktop', 'org.gnome.Nautilus.desktop', 'org.gnome.Ptyxis.desktop', 'code.desktop']

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
# Bluefin remaps Super+d → show-desktop and Super+Tab → switch-apps,
# both of which collide with Margine's Hyprland-style Super+number
# workspace + Super+arrow focus binds applied by configure-gnome-
# keybindings. Reset to the GNOME defaults here so the user-state
# bootstrap can overlay the Hyprland binds cleanly.
show-desktop=@as []
switch-applications=@as []
switch-applications-backward=@as []
switch-windows=@as []
switch-windows-backward=@as []

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
    configure-zen-browser \
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

# Compat symlink: 6 of the 7 configure-* scripts compute
#   YAML = Path(__file__).parent.parent / "declarations" / "margine-atomic.yaml"
# Since the scripts live at /usr/bin/, that resolves to
# /usr/declarations/margine-atomic.yaml. Without this symlink they
# silently can't find the file and bootstrap is broken end-to-end.
# Only configure-home-layout honors MARGINE_DECLARATIONS env var.
# Symlink is cheaper than patching 6 scripts. Keep until the scripts
# are unified to use a canonical lookup (FHS /usr/share/margine/).
mkdir -p /usr/declarations
ln -sf ../share/margine/declarations.yaml /usr/declarations/margine-atomic.yaml
log "Symlink: /usr/declarations/margine-atomic.yaml -> ../share/margine/declarations.yaml"

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
    "${MARGINE_REPO}/${MARGINE_REF}/assets/branding/wallpaper-margine.png" \
    -o /usr/share/backgrounds/margine/margine.png
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
curl --fail --silent --show-error -L \
    "${MARGINE_REPO}/${MARGINE_REF}/assets/branding/start-here-symbolic.svg" \
    -o /usr/share/icons/Adwaita/symbolic/places/start-here-symbolic.svg
chmod 0644 /usr/share/icons/Adwaita/symbolic/places/start-here-symbolic.svg
log "Replaced start-here-symbolic.svg with Margine 'm' glyph"

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
rm -f /usr/bin/bluefin-dx-groups \
      /usr/bin/ublue-bling \
      /usr/bin/ublue-bling-fastfetch \
      /usr/bin/ublue-fastfetch \
      /usr/bin/ublue-motd \
      /usr/bin/ublue-privileged-setup \
      /usr/bin/ublue-system-setup \
      /usr/bin/ublue-user-setup

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
# 5. Margine ujust recipes (gaming layer opt-in)
# ---------------------------------------------------------------------------
# Bluefin's /usr/share/ublue-os/just/00-entry.just hardcodes the list
# of imported recipe files. The ONLY one declared as optional is
# 60-custom.just (via `import?`) — that's the documented extension
# point for downstream distros. Files dropped under any other name
# (e.g. 99-margine.just) are simply ignored by `ujust --list`, even
# if syntactically valid. Use 60-custom.just so our recipes appear.
# (Steam Flatpak + Lutris/Heroic/Bottles + gamescope/mangohud/vkBasalt/
# gamemode/goverlay/steam-devices layered via rpm-ostree).
#
# Modeled after Bazzite's gaming bake, but opt-in: Margine default stays
# minimal; gamers run one command and get a working stack.
log "Installing Margine ujust recipes"
install -Dm0644 /ctx/60-custom.just /usr/share/ublue-os/just/60-custom.just

# ---------------------------------------------------------------------------
# 5b. First-login auto-bootstrap (XDG autostart)
# ---------------------------------------------------------------------------
# When a fresh user logs in for the first time after rebasing to
# Margine, run `ujust margine-bootstrap unattended` once. It's
# idempotent and skips re-running because of the marker file at
# ~/.config/margine/bootstrapped. The user can re-run by deleting
# that file or by invoking `ujust margine-bootstrap` manually.
#
# Without this, the configure-* scripts only ever run if the user
# happens to know they have to type the ujust command — which is
# exactly the "nothing's configured" bug we just fixed.
# ---------------------------------------------------------------------------
# 5c. Mask systemd-remount-fs.service (Bug 8 — composefs noise)
# ---------------------------------------------------------------------------
# The legacy "remount root rw from /etc/fstab" service is incompatible
# with composefs root: the overlay refuses reconfigure and the unit
# always lands in `failed` state. The system works fine — `/` is
# already rw via the overlay upper layer — but `systemctl --failed`
# always shows it and confuses humans. Mask it so the unit never
# starts and `--failed` returns empty on a clean boot.
log "Masking systemd-remount-fs.service (overlay rejects remount; see Bug 8 in lessons-learned)"
ln -sf /dev/null /etc/systemd/system/systemd-remount-fs.service

# /etc/skel default: disable Bluefin MOTD banner at terminal open.
# Bluefin ships /etc/profile.d/ublue-motd.sh which prints the
# "Welcome to Bluefin / ujust --choose / brew help" banner unless
# ~/.config/no-show-user-motd exists. We ship that marker in the
# skeleton so EVERY new user account inherits the off-by-default
# behavior. Existing users get the file via configure-home-layout
# (idempotent), which margine-bootstrap runs at first login.
mkdir -p /etc/skel/.config
touch /etc/skel/.config/no-show-user-motd
log "Installed: /etc/skel/.config/no-show-user-motd (disables Bluefin MOTD for new users)"

# ---------------------------------------------------------------------------
# 5d. Bug 6 v2 — boot-time seed of /etc/passwd + /etc/group
# ---------------------------------------------------------------------------
# Build-time seed (step 0.bis) IS run, Layer A confirms 65 entries in
# /etc/passwd at the end of buildah. But rechunk subsequently strips
# /etc/passwd / /etc/group from /usr/etc/ when it re-commits the image
# as an ostree-canonical tree (verified 2026-05-31 on a fresh-VM
# rebase: Layer A says 65 entries, deployed image has 1). So Bug 6
# returns post-rebase.
#
# Workaround: ship a systemd oneshot that re-applies the seed at
# every boot, before sysinit. Idempotent (only seeds if /etc/passwd
# is below the entry threshold). Doesn't depend on rechunk preserving
# /etc — it doesn't need to.
log "Installing /usr/libexec/margine-seed-etc-passwd + systemd oneshot"
mkdir -p /usr/libexec
cat > /usr/libexec/margine-seed-etc-passwd <<'SEED'
#!/usr/bin/env python3
"""Boot-time seed of /etc/passwd + /etc/group from /usr/lib factory.
Runs only if /etc/passwd has fewer than 20 entries (the post-rebase
stripped state). Otherwise no-op."""
import os, sys
def load(p):
    try:
        with open(p) as f: return [l.rstrip("\n") for l in f if l.strip()]
    except FileNotFoundError: return []
def by_name(lines): return {l.split(":",1)[0]: l for l in lines}
need_seed = False
for kind in ("passwd","group"):
    cur = load(f"/etc/{kind}")
    if len(cur) < 20:
        need_seed = True
        break
if not need_seed:
    print("/etc/passwd + /etc/group look populated, no seeding needed")
    sys.exit(0)
for kind in ("passwd","group"):
    local = by_name(load(f"/etc/{kind}"))
    factory = by_name(load(f"/usr/lib/{kind}"))
    merged = dict(factory); merged.update(local)
    def k(line):
        try:
            u = int(line.split(":")[2]); return (u >= 1000, u)
        except Exception:
            return (True, 999999)
    tmp = f"/etc/{kind}.new"
    with open(tmp,"w") as f:
        for l in sorted(merged.values(), key=k): f.write(l+"\n")
    os.replace(tmp, f"/etc/{kind}")
    print(f"/etc/{kind}: was {len(local)} → now {len(merged)} (+{len(merged)-len(local)} from factory)")
SEED
chmod 0755 /usr/libexec/margine-seed-etc-passwd

cat > /usr/lib/systemd/system/margine-seed-etc-passwd.service <<'UNIT'
[Unit]
Description=Margine: seed /etc/passwd + /etc/group from /usr/lib if stripped
Documentation=https://github.com/daniel-g-carrasco/margine-fedora-atomic/blob/main/docs/lessons-learned/2026-05-28-initramfs-and-bootc-labels.md
DefaultDependencies=no
# Run only AFTER local-fs-pre.target (so /etc exists as the overlay
# upper layer is mounted) and BEFORE systemd-sysusers / systemd-tmpfiles
# (so they see the seeded users). DO NOT add After=local-fs.target: it
# creates an ordering cycle through systemd-tmpfiles-setup-dev.service,
# which systemd resolves by disabling tmpfiles-setup-dev → /dev/disk
# /by-uuid/* never gets populated → boot times out into emergency mode
# (incident 2026-06-01). /usr is part of the immutable ostree commit
# so it's available from the start; we don't need local-fs.target.
After=local-fs-pre.target
Before=systemd-sysusers.service systemd-tmpfiles-setup.service sysinit.target
ConditionFileNotEmpty=/usr/lib/passwd

[Service]
Type=oneshot
ExecStart=/usr/libexec/margine-seed-etc-passwd
RemainAfterExit=yes
# Self-recovery if a previous boot left /etc files mid-write
ProtectSystem=no

[Install]
WantedBy=sysinit.target
UNIT

mkdir -p /usr/lib/systemd/system/sysinit.target.wants
ln -sf ../margine-seed-etc-passwd.service \
   /usr/lib/systemd/system/sysinit.target.wants/margine-seed-etc-passwd.service
log "Wired margine-seed-etc-passwd.service to sysinit.target"

# ---------------------------------------------------------------------------
# Observability helpers: notify the user when (a) the build pipeline goes
# stale (no new :stable on ghcr for >7 days = something broken upstream),
# and (b) when an actual upgrade has just occurred (so the user knows
# their reboot did something).
#
# Both helpers run as user-systemd (no root needed at runtime). They use
# the freedesktop notification API via notify-send, so they integrate
# with GNOME's normal popup stream.
# ---------------------------------------------------------------------------

log "Installing /usr/libexec/margine-staleness-check (staleness watchdog)"
cat > /usr/libexec/margine-staleness-check <<'PYEOF'
#!/usr/bin/env python3
"""Notify user if ghcr.io/.../margine:stable hasn't been refreshed
in >7 days. Either the build pipeline is broken, or upstream has
genuinely paused — either way the user should know."""
import json
import subprocess
import sys
import time

WARN_AGE_DAYS = 7
CRIT_AGE_DAYS = 14

def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=30)

# Get current booted image reference
r = run(["bootc", "status", "--json"])
if r.returncode != 0:
    sys.exit(0)  # no bootc, no-op
booted = json.loads(r.stdout)["status"]["booted"]
image_ref = booted["image"]["image"]["image"]  # e.g. ghcr.io/daniel-g-carrasco/margine:stable

# Inspect upstream :stable to find its creation timestamp
r = run(["skopeo", "inspect", "--no-tags", f"docker://{image_ref}"])
if r.returncode != 0:
    sys.exit(0)  # network down? skip silently this round
created = json.loads(r.stdout)["Created"]  # ISO 8601

created_ts = time.mktime(time.strptime(created.split(".")[0], "%Y-%m-%dT%H:%M:%S"))
age_days = (time.time() - created_ts) / 86400

if age_days < WARN_AGE_DAYS:
    sys.exit(0)

urgency = "critical" if age_days >= CRIT_AGE_DAYS else "normal"
title = "Margine: upstream stale"
body  = f"Latest :stable is {age_days:.0f} days old. Build pipeline may be broken."
subprocess.run([
    "notify-send", "-u", urgency, "-a", "Margine",
    "-i", "system-software-update", title, body,
])
PYEOF
chmod 0755 /usr/libexec/margine-staleness-check

log "Installing /usr/libexec/margine-upgrade-notify (post-upgrade notification)"
cat > /usr/libexec/margine-upgrade-notify <<'PYEOF'
#!/usr/bin/env python3
"""On first graphical login after a reboot, if the booted deployment's
image digest differs from the one recorded at last run, raise a
notification telling the user *which version they just upgraded to*.
Reassures them that the reboot actually did something."""
import json
import os
import pathlib
import subprocess
import sys

state_dir = pathlib.Path(os.environ["HOME"]) / ".cache" / "margine"
state_dir.mkdir(parents=True, exist_ok=True)
state_file = state_dir / "last-booted-digest"

r = subprocess.run(["bootc", "status", "--json"], capture_output=True, text=True, timeout=15)
if r.returncode != 0:
    sys.exit(0)
booted = json.loads(r.stdout)["status"]["booted"]
digest  = booted["image"].get("imageDigest", "?")
version = booted["image"].get("version", "?")

previous = state_file.read_text().strip() if state_file.exists() else ""

if previous and previous != digest:
    title = "Margine updated"
    body  = f"Now running: {version}\nDigest: {digest[:23]}…"
    subprocess.run([
        "notify-send", "-u", "normal", "-a", "Margine",
        "-i", "system-software-update", title, body,
    ])

state_file.write_text(digest)
PYEOF
chmod 0755 /usr/libexec/margine-upgrade-notify

# User systemd units live in /etc/skel so every NEW user account picks
# them up on first login. Existing accounts get them through the bootstrap
# helper (configure-home-layout, idempotent).
mkdir -p /etc/skel/.config/systemd/user/timers.target.wants \
         /etc/skel/.config/systemd/user/default.target.wants

# Staleness watchdog: timer every 12h after boot.
cat > /etc/skel/.config/systemd/user/margine-staleness.service <<'UNIT'
[Unit]
Description=Margine: check ghcr.io/:stable staleness
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/libexec/margine-staleness-check
UNIT

cat > /etc/skel/.config/systemd/user/margine-staleness.timer <<'UNIT'
[Unit]
Description=Margine: schedule staleness check every 12h

[Timer]
OnBootSec=10min
OnUnitActiveSec=12h
AccuracySec=10min
Persistent=true

[Install]
WantedBy=timers.target
UNIT
ln -sf ../margine-staleness.timer \
   /etc/skel/.config/systemd/user/timers.target.wants/margine-staleness.timer

# Upgrade notify: oneshot, fires on every graphical login.
cat > /etc/skel/.config/systemd/user/margine-upgrade-notify.service <<'UNIT'
[Unit]
Description=Margine: notify if booted deployment changed since last login
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=oneshot
ExecStart=/usr/libexec/margine-upgrade-notify

[Install]
WantedBy=default.target
UNIT
ln -sf ../margine-upgrade-notify.service \
   /etc/skel/.config/systemd/user/default.target.wants/margine-upgrade-notify.service

log "Wired observability user units (staleness 12h + upgrade-notify) into /etc/skel"

log "Installing /etc/xdg/autostart/margine-first-boot.desktop"
mkdir -p /etc/xdg/autostart
cat > /etc/xdg/autostart/margine-first-boot.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Margine first-login user-state bootstrap
Comment=Apply Margine home layout, GNOME extensions, keybindings, defaults
Exec=/usr/bin/bash -c 'mkdir -p "$HOME/.config/margine" && { test -f "$HOME/.config/margine/bootstrapped" || ujust margine-bootstrap unattended > "$HOME/.config/margine/bootstrap.log" 2>&1; }'
NoDisplay=true
OnlyShowIn=GNOME;
X-GNOME-Autostart-enabled=true
EOF
# NOTE: do NOT add X-GNOME-Autostart-Phase=Applications. GNOME 50+
# dropped session-phase management; gnome-session-service warns
# "App ... sets X-GNOME-Autostart-Phase, but gnome-session no longer
# manages session services" and SKIPS the entire entry, so the
# bootstrap never runs at login. The other keys above (Type/Exec/
# OnlyShowIn/Autostart-enabled) are sufficient for standard autostart.
chmod 0644 /etc/xdg/autostart/margine-first-boot.desktop

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
log "Margine build modifications complete."
log "Image is ready: Bluefin DX + CachyOS signed kernel + Margine deltas."
