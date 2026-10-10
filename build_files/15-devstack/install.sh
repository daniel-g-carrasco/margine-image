#!/usr/bin/env bash
# Backfill the developer stack Bluefin DX used to ship, when the base lacks it.
#
# WHY THIS EXISTS (2026-08-25)
#
# Margine is FROM Bluefin DX because DX carried the virtualisation and
# container tooling Margine relies on: libvirt, qemu, virt-manager,
# docker, incus, VS Code, and a boot-time service that puts wheel users in
# the docker/incus-admin/libvirt groups. Universal Blue has announced the
# end of the -dx images: developer tooling moves to userspace ("ujust
# devmode"), and the Fedora DX variants are "Soon" on the migration list.
#
# This script makes the base swappable. On today's Bluefin DX every check
# below finds the package already present and does nothing, so the image
# is byte-for-byte what it was. On a base without DX (ghcr.io/projectbluefin/
# bluefin, or plain Bluefin) it installs exactly the pieces Margine's
# declarations (margine-atomic.yaml) and validators (group membership)
# depend on. Two classes: the virtualisation/container/IDE stack (sections
# 1-4), and the host packages margine-atomic.yaml declares that were only
# ever present because DX shipped them (section 1b: diagnostics, fonts,
# the tray extension the dconf defaults enable, tmux, rocminfo...). Found
# by diffing a build on the plain base against today's image (2026-08-25:
# 418 packages present today and absent there; 17 of them declared).
# Nothing more: DX also ships cockpit, bpf tooling, the rest of rocm,
# qemu for a dozen foreign architectures and others that Margine never
# asked for, and this is not the place to start.
#
# Third-party repos are handled the way custom-kernel handles RPMFusion
# and NVIDIA (#363): fetch the key, verify its fingerprint, only then let
# dnf use the repo, and remove the repo file afterwards so the image ships
# no third-party repo enabled.
set -euo pipefail
. /ctx/00-common.sh
log() { printf '[devstack] %s\n' "$*"; }
err() { printf '[devstack] ERROR: %s\n' "$*" >&2; }

# Verified 2026-08-25 against https://download.docker.com/linux/fedora/gpg
# and https://packages.microsoft.com/keys/microsoft.asc. A rotation fails
# this build loudly, which is the point.
# shellcheck disable=SC2034  # read indirectly by verify_key_fpr callers below
# shellcheck disable=SC2034
MICROSOFT_FPR="BC528686B50D79E339D3721CEB3E94ADBE1229CF"

missing() {
  # Print the members of "$@" that are not installed.
  local p
  for p in "$@"; do rpm -q "$p" >/dev/null 2>&1 || echo "$p"; done
}

# --- 1. Virtualisation + container tooling from Fedora's own repos -------
# The list is margine-atomic.yaml host_packages.virtualization plus the
# podman extras DX carried. podman-docker answers to `docker` for scripts:
# Margine ships Podman only (2026-10-10), Docker CE is `ujust margine-docker`.
FEDORA_PKGS=(
  libvirt libvirt-nss qemu-kvm virt-manager virt-viewer edk2-ovmf swtpm dnsmasq
  qemu-img qemu-device-display-virtio-gpu qemu-device-display-virtio-vga
  qemu-device-usb-redirect qemu-char-spice
  podman-compose podman-machine podman-docker
)
mapfile -t NEED < <(missing "${FEDORA_PKGS[@]}")
if (( ${#NEED[@]} == 0 )); then
  log "virtualisation + container tooling already in the base (${#FEDORA_PKGS[@]} packages present)"
else
  log "base lacks ${#NEED[@]} packages, installing: ${NEED[*]}"
  retry 3 30 dnf -y install --setopt=install_weak_deps=False "${NEED[@]}"
fi

# --- 1b. Host packages the declaration promises, that only DX carried ----
# Each of these is listed in margine-atomic.yaml (section in the comment)
# and is present in today's image only because Bluefin DX ships it; the
# plain Bluefin base has none of them (trial build of 2026-08-25). Same
# rule: install only what is missing, so today's base sees no change.
# google-noto-sans-cjk-fonts is deliberately absent: the plain base ships
# its successor google-noto-sans-cjk-vf-fonts, and 14-fonts (separate PR
# from main) moves the declaration and today's image to the vf package. dash-to-dock is not an RPM on any base:
# Bluefin bakes it from upstream as an unpackaged extension (#379 fixed
# the declaration that listed the Fedora package).
# vkBasalt is declared (desktop_host_helpers) and present in today's image,
# but not because DX ships it: it was a leftover of the GAMING_BAKE
# transaction in custom-kernel (lutris dragged in vkBasalt and wine as
# weak dependencies, the four gaming packages were removed afterwards,
# their dependencies stayed). Since 2026-10-10 the bake installs without
# weak dependencies and 12-base-trim removes the wine family, so it no
# longer lingers. The gaming layer is the user's (ujust margine-gaming),
# so it is not backfilled here.
DECLARED_PKGS=(
  mesa-demos vulkan-tools                  # media_diagnostics
  rocminfo rocm-opencl                     # amd_gpu_extras
  lm_sensors powertop powerstat smartmontools  # hardware_diagnostics
  gnome-shell-extension-appindicator       # gnome_tools: enabled by 30-gnome-defaults
  nautilus-python                          # gnome_tools: Files extensions (Spola's sync emblems);
                                           # today in the image only as a dependency of gsconnect
  jetbrains-mono-fonts cascadia-code-fonts # fonts
  tmux glow                                # core_cli
  podman-tui                               # container_tooling
  python3-pip                              # build_essentials
  virt-install                             # not declared: the margine-vm just recipes call it
)
mapfile -t NEED < <(missing "${DECLARED_PKGS[@]}")
if (( ${#NEED[@]} == 0 )); then
  log "declared host packages already in the base (${#DECLARED_PKGS[@]} present)"
else
  log "base lacks ${#NEED[@]} declared host packages, installing: ${NEED[*]}"
  retry 3 30 dnf -y install --setopt=install_weak_deps=False "${NEED[@]}"
fi

# --- 2. Docker CE: not in the image since 2026-10-10 ---------------------
# 12-base-trim removes what a base ships; `ujust margine-docker` layers it
# from Docker's repository (key pinned by fingerprint, same as the key
# check here used to do) for the few tools wired to Docker's own daemon.

# --- 3. VS Code, from Microsoft's repo, key pinned ------------------------
# Kept for parity with what DX shipped and what the reference host uses.
# Upstream's new answer is a brew cask in userspace; if Margine follows,
# this block goes and nothing else changes.
if rpm -q code >/dev/null 2>&1; then
  log "code (VS Code) already in the base"
else
  log "base lacks VS Code, installing from packages.microsoft.com"
  retry_curl_strict https://packages.microsoft.com/keys/microsoft.asc /run/microsoft.asc
  verify_key_fpr /run/microsoft.asc "$MICROSOFT_FPR" "microsoft" || exit 1
  rpm --import /run/microsoft.asc
  cat > /etc/yum.repos.d/vscode.repo <<'REPO'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
REPO
  retry 3 30 dnf -y install --setopt=install_weak_deps=False code
  rm -f /etc/yum.repos.d/vscode.repo /run/microsoft.asc
fi

# --- 4. Boot-time services DX provided ------------------------------------
# Group membership is Margine's job on every base (2026-10-10): the base's
# bluefin-dx-groups expects the docker and incus-admin groups, which left
# the image with Docker CE and incus, and it restarts every 30 s when
# usermod fails. margine-dev-groups adds wheel users to the groups that
# exist (libvirt, and docker after `ujust margine-docker`), every boot.
if [[ -f /usr/lib/systemd/system/bluefin-dx-groups.service ]]; then
  systemctl mask bluefin-dx-groups.service
  log "masked the base's bluefin-dx-groups.service (its groups are gone)"
fi
systemctl enable margine-dev-groups.service
log "enabled margine-dev-groups.service (wheel -> libvirt, docker when present, at boot)"
if [[ -f /usr/lib/systemd/system/libvirt-workaround.service ]]; then
  log "libvirt-workaround.service present in the base"
else
  systemctl enable margine-libvirt-workaround.service
  log "enabled margine-libvirt-workaround.service"
fi
if systemctl is-enabled podman.socket >/dev/null 2>&1; then
  log "podman.socket already enabled"
else
  systemctl enable podman.socket; log "enabled podman.socket"
fi

# --- 5. Prove it ---------------------------------------------------------
# What this script promises the rest of the image. A base that still lacks
# any of these after the steps above is not something to ship.
for p in libvirt virt-manager qemu-kvm podman-docker code "${DECLARED_PKGS[@]}"; do
  rpm -q "$p" >/dev/null 2>&1 || { err "$p still missing after devstack"; exit 1; }
done
grep -q "^libvirt:" /usr/lib/group /etc/group 2>/dev/null || { err "group libvirt missing after devstack"; exit 1; }
if rpm -q docker-ce >/dev/null 2>&1 || rpm -q incus >/dev/null 2>&1; then
  err "docker-ce or incus still in the image after base-trim"; exit 1
fi
log "developer stack complete"
