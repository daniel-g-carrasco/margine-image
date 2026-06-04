#!/usr/bin/env bash
# Install the Margine gaming RPM stack at image-build time. Mirrors the
# package set of `ujust margine-gaming` in 60-custom.just but bakes it
# into the OCI image so the deployed system is ostree-canonical
# (no LayeredPackages on the user's `rpm-ostree status`).
set -ouex pipefail

log() { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*"; }

# Verified 2026-06-03 against ghcr.io/ublue-os/bluefin-dx:stable:
# gamemode, input-remapper, tuned, tuned-ppd are ALREADY in the
# Bluefin DX base (and therefore in margine:stable) — listing them
# again makes dnf5 fail with "Package already installed".
# rom-properties-gtk does NOT exist in Fedora 44 / RPMFusion (no
# matches found in dnf search); the upstream rom-properties project
# ships a COPR (eyalroz/rom-properties) but it's a separate decision
# whether we want a third repo just for ROM metadata. Dropped for now.
GAMING_RPMS=(
  gamescope
  vkBasalt
  # NOTE: scx-scheds, mangohud, goverlay, steam-devices used to be
  # in this list. All promoted to the BASE image:
  #   - scx-scheds (2026-06-03) — pro-audio creators use scx_central
  #   - mangohud + goverlay (2026-06-05) — useful for monitoring
  #     CPU/GPU during render-heavy work (DaVinci export, Blender
  #     cycles, BricsCAD modelling, OBS recording, ffmpeg encode).
  #     LD_PRELOAD opt-in, zero footprint when not used.
  #   - steam-devices (2026-06-05) — pure udev rules for USB
  #     controllers. Useful for creators using controllers as
  #     jog wheels / foot pedals / generic input devices.
  # Gaming variant inherits all of the above from base.
)

log "Installing ${#GAMING_RPMS[@]} gaming-only RPMs (gamescope + vkBasalt)"
log "Inherited from base: mangohud, goverlay, steam-devices, gamemode,"
log "                     input-remapper, tuned, tuned-ppd, scx-scheds."

# RPMFusion is REQUIRED for most of the gaming RPM stack (gamescope,
# mangohud, vkBasalt, gamemode, goverlay, steam-devices) — Bluefin
# DX intentionally ships without it, and Margine's base also strips
# it after using it transiently for the CachyOS kernel install (see
# custom-kernel/install.sh:254-255 which removes rpmfusion-free-release
# at end-of-build). For the gaming variant we KEEP RPMFusion enabled
# in the final image because:
#   1. Users will run `dnf upgrade` (via rpm-ostree update / topgrade)
#      and need the same repo set the original install came from.
#   2. The whole point of the gaming variant is to make Vulkan layer
#      tooling + controller drivers easy — that ecosystem lives in
#      RPMFusion. Hiding it post-install would be a footgun.
log "Enabling RPMFusion (free + nonfree) — required for gaming stack"
FEDORA_VER=$(rpm -E %fedora)
dnf -y install \
  "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VER}.noarch.rpm" \
  "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VER}.noarch.rpm"

# Retry loop — Fedora/RPMFusion mirrors occasionally time out and we
# don't want a transient repo blip to cost a 25-min rebuild. Same
# pattern as custom-kernel/install.sh (COPR retry from 2026-06-01).
attempt=1
max_attempts=5
while :; do
  if dnf -y install --refresh "${GAMING_RPMS[@]}"; then
    log "Gaming RPM install OK on attempt $attempt"
    break
  fi
  if (( attempt >= max_attempts )); then
    log "Gaming RPM install failed after $max_attempts attempts; aborting"
    exit 1
  fi
  backoff=$(( attempt * 30 ))
  log "Install attempt $attempt failed; sleeping ${backoff}s before retry"
  sleep "$backoff"
  dnf -y clean metadata || true
  attempt=$(( attempt + 1 ))
done

# Enable tuned by default — gives the user a profile they can actually
# see in GNOME's Power panel (via tuned-ppd) immediately on first boot.
# Idempotent: systemctl preset will not re-enable a unit explicitly
# disabled by the admin.
log "Enabling tuned.service via preset"
systemctl enable tuned.service || true

# ---------------------------------------------------------------------------
# Gaming "fundamentals" Flatpak BAKE list (PR D, 2026-06-04)
# ---------------------------------------------------------------------------
# Per the hybrid-Flatpak design in build_files/build.sh, gaming-critical
# launchers (Steam + the four big launchers a player reaches for
# immediately) are baked into the freshly-installed system by the
# Anaconda kickstart in disk_config/iso-gnome.toml. The kickstart
# reads BOTH installer-flatpaks-base AND installer-flatpaks-gaming;
# the gaming-only file exists ONLY on margine-gaming images, so the
# base ISO ignores it (the kickstart skips missing files).
#
# Protontricks + RetroArch stay in margine-gaming.preinstall (first-
# boot deferred) — they are utilities/emu, not the launcher the
# player opens 30 seconds after first login.
log "Writing /usr/share/margine/installer-flatpaks-gaming (BAKE: kickstart-installed)"
mkdir -p /usr/share/margine
cat > /usr/share/margine/installer-flatpaks-gaming <<'BAKE_LIST'
# Margine Gaming "fundamentals" — baked into the freshly installed
# system by the Anaconda kickstart in disk_config/iso-gnome.toml.
# A gamer who installs Margine Gaming and opens Activities for the
# first time finds Steam already there.
com.valvesoftware.Steam
net.lutris.Lutris
com.heroicgameslauncher.hgl
com.usebottles.bottles
net.davidotek.pupgui2
BAKE_LIST
chmod 0644 /usr/share/margine/installer-flatpaks-gaming
log "Gaming BAKE list — $(grep -cv '^#\|^$' /usr/share/margine/installer-flatpaks-gaming) apps"

# Final sanity: bootc lint runs later in the Containerfile; we just
# verify the gaming binaries landed where expected. NOTE: scx_lavd /
# scx_bpfland are inherited from the BASE layer (see
# margine-image PR #18 — scx-scheds promotion to base), they are
# NOT installed by this gaming-layer install.sh. We still smoke-check
# them here because if base is broken (e.g. autoremove nukes
# scx-scheds — PR #22) we'd rather fail the gaming build loudly here
# than ship a gaming ISO whose `ujust margine-scheduler` is broken.
log "Gaming layer install summary:"
for bin in gamescope mangohud gamemoded goverlay tuned-adm scx_lavd scx_bpfland; do
  if command -v "$bin" >/dev/null 2>&1; then
    printf '  ✓ %-12s → %s\n' "$bin" "$(command -v "$bin")"
  else
    printf '  ✗ %-12s NOT found\n' "$bin"
    exit 1
  fi
done
