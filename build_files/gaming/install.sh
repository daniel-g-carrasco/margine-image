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
  mangohud
  vkBasalt
  goverlay
  steam-devices
  # scx-scheds: user-space loaders for the sched_ext BPF schedulers
  # (scx_lavd, scx_bpfland, scx_rusty, scx_central, scx_simple). Lets
  # the user A/B-test alternative schedulers per session without
  # touching the kernel — runtime swap, no reboot. The base Margine
  # kernel is CachyOS+BORE, which is the right default for desktop;
  # this is an opt-in upgrade path. The package ships from CachyOS's
  # own addons COPR which we already pull elsewhere; see ujust
  # `margine-scheduler-*` recipes for the runtime knobs.
  scx-scheds
)

log "Installing ${#GAMING_RPMS[@]} gaming RPMs into the base image"
log "(gamemode, input-remapper, tuned, tuned-ppd inherited from base)"

# scx-scheds lives in the CachyOS addons COPR (same source as the
# kernel we already use). Enable just for the duration of this install,
# then disable so the repo doesn't sit in /etc/yum.repos.d/ on user
# systems and surface random updates outside of Margine's own pipeline.
log "Enabling kernel-cachyos-addons COPR for scx-scheds"
dnf5 -y copr enable bieszczaders/kernel-cachyos-addons

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

# Disable the kernel-cachyos-addons COPR — we only needed it for the
# scx-scheds install above. Leaving it enabled on user systems would
# pull in random kernel-related updates outside Margine's own image
# pipeline.
log "Disabling kernel-cachyos-addons COPR (install complete)"
dnf5 -y copr disable bieszczaders/kernel-cachyos-addons || true
rm -f /etc/yum.repos.d/_copr*kernel-cachyos-addons*.repo

# Enable tuned by default — gives the user a profile they can actually
# see in GNOME's Power panel (via tuned-ppd) immediately on first boot.
# Idempotent: systemctl preset will not re-enable a unit explicitly
# disabled by the admin.
log "Enabling tuned.service via preset"
systemctl enable tuned.service || true

# Final sanity: bootc lint runs later in the Containerfile; we just
# verify the gaming binaries landed where expected.
log "Gaming layer install summary:"
for bin in gamescope mangohud gamemoded goverlay tuned-adm scx_lavd scx_bpfland; do
  if command -v "$bin" >/dev/null 2>&1; then
    printf '  ✓ %-12s → %s\n' "$bin" "$(command -v "$bin")"
  else
    printf '  ✗ %-12s NOT found\n' "$bin"
    exit 1
  fi
done
