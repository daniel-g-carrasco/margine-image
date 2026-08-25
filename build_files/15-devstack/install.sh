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
DOCKER_CE_FPR="060A61C51B558A7F742B77AAC52FEB6B621E9F35"
# shellcheck disable=SC2034
MICROSOFT_FPR="BC528686B50D79E339D3721CEB3E94ADBE1229CF"

missing() {
  # Print the members of "$@" that are not installed.
  local p
  for p in "$@"; do rpm -q "$p" >/dev/null 2>&1 || echo "$p"; done
}

# --- 1. Virtualisation + container tooling from Fedora's own repos -------
# The list is margine-atomic.yaml host_packages.virtualization plus the
# podman extras DX carried and incus, which the group check expects.
FEDORA_PKGS=(
  libvirt libvirt-nss qemu-kvm virt-manager virt-viewer edk2-ovmf swtpm dnsmasq
  qemu-img qemu-device-display-virtio-gpu qemu-device-display-virtio-vga
  qemu-device-usb-redirect qemu-char-spice
  podman-compose podman-machine
  incus incus-agent
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
# but not because DX ships it: it is a leftover of the GAMING_BAKE
# transaction in custom-kernel (lutris drags in vkBasalt and wine, the
# four gaming packages are removed afterwards, their dependencies stay).
# validate-margine-system counts it as half a gaming layer and warns on
# every image today. The gaming layer is the user's (ujust margine-gaming),
# so it is not backfilled here.
DECLARED_PKGS=(
  mesa-demos vulkan-tools                  # media_diagnostics
  rocminfo rocm-opencl                     # amd_gpu_extras
  lm_sensors powertop powerstat smartmontools  # hardware_diagnostics
  gnome-shell-extension-appindicator       # gnome_tools: enabled by 30-gnome-defaults
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

# --- 2. Docker CE, from Docker's repo, key pinned ------------------------
DOCKER_PKGS=(docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin)
mapfile -t NEED < <(missing "${DOCKER_PKGS[@]}")
if (( ${#NEED[@]} == 0 )); then
  log "docker-ce already in the base"
else
  log "base lacks docker (${NEED[*]}), installing from download.docker.com"
  retry_curl_strict https://download.docker.com/linux/fedora/gpg /run/docker-ce.asc
  verify_key_fpr /run/docker-ce.asc "$DOCKER_CE_FPR" "docker-ce" || exit 1
  rpm --import /run/docker-ce.asc
  retry_curl_strict https://download.docker.com/linux/fedora/docker-ce.repo /etc/yum.repos.d/docker-ce.repo
  retry 3 30 dnf -y install --setopt=install_weak_deps=False "${NEED[@]}"
  rm -f /etc/yum.repos.d/docker-ce.repo /run/docker-ce.asc
  # Same sysctl DX ships: docker networking needs forwarding.
  install -Dm0644 /ctx/system_files/usr/lib/sysctl.d/margine-docker-ce.conf /usr/lib/sysctl.d/margine-docker-ce.conf
fi

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
# Only when the base does not ship its own. On Bluefin DX the bluefin-*
# units exist and stay in charge; ours are present in the image but left
# disabled, so there is exactly one owner of each job.
if [[ -f /usr/lib/systemd/system/bluefin-dx-groups.service ]]; then
  log "bluefin-dx-groups.service present in the base, leaving group setup to it"
else
  log "enabling margine-dev-groups.service (wheel -> docker, incus-admin, libvirt at boot)"
  systemctl enable margine-dev-groups.service
fi
if [[ -f /usr/lib/systemd/system/libvirt-workaround.service ]]; then
  log "libvirt-workaround.service present in the base"
else
  systemctl enable margine-libvirt-workaround.service
  log "enabled margine-libvirt-workaround.service"
fi
if [[ -f /usr/lib/systemd/system/incus-workaround.service ]] || ! rpm -q incus >/dev/null 2>&1; then
  log "incus workaround: base handles it or incus absent"
else
  systemctl enable margine-incus-workaround.service
  log "enabled margine-incus-workaround.service"
fi
for unit in docker.socket podman.socket; do
  if systemctl is-enabled "$unit" >/dev/null 2>&1; then
    log "$unit already enabled"
  elif [[ -f "/usr/lib/systemd/system/$unit" ]]; then
    systemctl enable "$unit"; log "enabled $unit"
  fi
done

# --- 5. Prove it ---------------------------------------------------------
# What this script promises the rest of the image. A base that still lacks
# any of these after the steps above is not something to ship.
for p in libvirt virt-manager qemu-kvm docker-ce code "${DECLARED_PKGS[@]}"; do
  rpm -q "$p" >/dev/null 2>&1 || { err "$p still missing after devstack"; exit 1; }
done
for g in docker libvirt incus-admin; do
  grep -q "^$g:" /usr/lib/group /etc/group 2>/dev/null || { err "group $g missing after devstack"; exit 1; }
done
log "developer stack complete"
