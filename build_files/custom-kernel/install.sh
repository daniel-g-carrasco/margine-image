#!/bin/bash
#
# Install the CachyOS kernel from COPR (bieszczaders/kernel-cachyos),
# sign the vmlinuz and modules with the Margine MOK, build v4l2loopback
# against it, and create a one-shot systemd unit that imports the MOK
# certificate on first boot.
#
# Inspired by Origami Linux's modules/custom-kernel/custom-kernel.sh
# (https://gitlab.com/origami-linux/images), simplified for Margine:
#   - only the kernel-cachyos (mainline) variant — no LTS/RT/LTO choice
#   - no Nvidia codepath (target hardware: Framework 13 AMD 7640U + Intel)
#   - signing is mandatory: this image is meant to boot under Secure Boot
#
# Inputs (BuildKit secrets):
#   /tmp/certs/MOK.key        — RSA private key (PEM)
#   /tmp/certs/MOK.pem        — X509 certificate (PEM)
# (The mokutil enrollment passphrase is public by design and lives as
#  a constant below — see the MOK_PASSWORD comment.)
#
set -euo pipefail

# Shared helpers (retry, retry_curl, FEDORA_VER, ...). log/err are
# re-defined right after to keep this script's [custom-kernel] prefix.
. /ctx/00-common.sh

log() { printf '[custom-kernel] %s\n' "$*"; }
err() { printf '[custom-kernel] ERROR: %s\n' "$*" >&2; }

SIGNING_KEY="/tmp/certs/MOK.key"
SIGNING_CERT="/tmp/certs/MOK.pem"

for f in "$SIGNING_KEY" "$SIGNING_CERT"; do
  [[ -f "$f" ]] || { err "Missing secret: $f"; exit 1; }
done

# The MOK *enrollment passphrase* is PUBLIC BY DESIGN: every installer
# must type it into MokManager, the live-ISO Secure Boot dialog prints
# it, and the install docs spell it out. Only the signing KEY above is
# secret. Until 2026-06-12 this value was plumbed through GHA secrets +
# a BuildKit secret mount — implying a confidentiality that never
# existed (the unit below ships world-readable in the image anyway) and
# inviting a pointless "rotation" that would only break the docs.
# Keep it a simple constant; if it ever changes, update the live-ISO
# dialog (live-env/src/build.sh) and the install docs together.
MOK_PASSWORD="margine-os"

# Validate that key and cert match.
openssl pkey -in "$SIGNING_KEY"  -noout >/dev/null \
  || { err "MOK.key is not a valid private key"; exit 1; }
openssl x509 -in "$SIGNING_CERT" -noout >/dev/null \
  || { err "MOK.pem is not a valid X509 cert"; exit 1; }
_tmp1=$(mktemp); _tmp2=$(mktemp)
openssl pkey -in "$SIGNING_KEY"  -pubout        >"$_tmp1"
openssl x509 -in "$SIGNING_CERT" -pubkey -noout >"$_tmp2"
cmp -s "$_tmp1" "$_tmp2" \
  || { rm -f "$_tmp1" "$_tmp2"; err "MOK.key and MOK.pem don't match"; exit 1; }
rm -f "$_tmp1" "$_tmp2"

COPR_REPO="bieszczaders/kernel-cachyos"
KERNEL_PKG="kernel-cachyos"
KERNEL_DEVEL_PKG="kernel-cachyos-devel-matched"
KERNEL_PACKAGES=(kernel-cachyos kernel-cachyos-core kernel-cachyos-modules "$KERNEL_DEVEL_PKG")
# TRANSIENT packages are installed for build time only and removed at the end.
# sbsigntools provides sbsign/sbverify; akmods is needed for v4l2loopback (best-effort).
TRANSIENT=(akmods sbsigntools "$KERNEL_DEVEL_PKG")

# Install the signing tools up-front so they're available when we sign vmlinuz.
log "Installing sbsigntools (build-time only)"
dnf -y install sbsigntools

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

disable_kernel_install_hooks() {
  for _f in \
      /usr/lib/kernel/install.d/05-rpmostree.install \
      /usr/lib/kernel/install.d/50-dracut.install
  do
    [[ -f "$_f" ]] || continue
    mv "$_f" "$_f.bak"
    printf '#!/bin/sh\nexit 0\n' >"$_f"
    chmod +x "$_f"
  done
}
restore_kernel_install_hooks() {
  for _f in \
      /usr/lib/kernel/install.d/05-rpmostree.install \
      /usr/lib/kernel/install.d/50-dracut.install
  do
    [[ -f "$_f.bak" ]] && mv -f "$_f.bak" "$_f"
  done
}

# akmodsbuild on bootc images skips signing if /var isn't writable; patch
# it out so akmods proceeds inside the container build.
disable_akmodsbuild() {
  _ak="/usr/sbin/akmodsbuild"
  [[ -f "$_ak" ]] || return 1
  cp -p "$_ak" "$_ak.backup"
  sed '/if \[\[ -w \/var \]\] ; then/,/fi/d' "$_ak" > "$_ak.tmp"
  mv "$_ak.tmp" "$_ak"
  chmod +x "$_ak"
}
restore_akmodsbuild() {
  [[ -f /usr/sbin/akmodsbuild.backup ]] \
    && mv -f /usr/sbin/akmodsbuild.backup /usr/sbin/akmodsbuild
}

sign_kernel() {
  _vmlinuz="/usr/lib/modules/${KERNEL_VERSION}/vmlinuz"
  [[ -f "$_vmlinuz" ]] || { err "vmlinuz not found at $_vmlinuz"; return 1; }
  _tmp=$(mktemp)
  sbsign --key "$SIGNING_KEY" --cert "$SIGNING_CERT" --output "$_tmp" "$_vmlinuz"
  sbverify --cert "$SIGNING_CERT" "$_tmp" \
    || { rm -f "$_tmp"; err "sbverify failed on signed kernel"; return 1; }
  cp "$_tmp" "$_vmlinuz"
  chmod 0644 "$_vmlinuz"
  rm -f "$_tmp"
  # Stamp for the end-of-script integrity check (back-ported from the
  # Origami reference script): if any later step — akmods, dracut,
  # cleanup — rewrites vmlinuz after signing, the build must fail
  # rather than ship an unsigned kernel that Secure Boot rejects.
  sha256sum "$_vmlinuz" > /tmp/vmlinuz.sha
}

sign_kernel_modules() {
  _module_root="/usr/lib/modules/${KERNEL_VERSION}"
  _sign_file="${_module_root}/build/scripts/sign-file"
  [[ -x "$_sign_file" ]] || { err "sign-file missing: $_sign_file"; return 1; }
  find "$_module_root" -type f \( \
      -name "*.ko" -o -name "*.ko.xz" -o -name "*.ko.zst" -o -name "*.ko.gz" \
    \) | while IFS= read -r _mod; do
    case "$_mod" in
      *.ko)
        "$_sign_file" sha256 "$SIGNING_KEY" "$SIGNING_CERT" "$_mod" ;;
      *.ko.xz)
        _raw="${_mod%.xz}"
        xz -d -q "$_mod"
        "$_sign_file" sha256 "$SIGNING_KEY" "$SIGNING_CERT" "$_raw"
        xz -z -q "$_raw" ;;
      *.ko.zst)
        _raw="${_mod%.zst}"
        zstd -d -q --rm "$_mod"
        "$_sign_file" sha256 "$SIGNING_KEY" "$SIGNING_CERT" "$_raw"
        zstd -q "$_raw" ;;
      *.ko.gz)
        _raw="${_mod%.gz}"
        gunzip -q "$_mod"
        "$_sign_file" sha256 "$SIGNING_KEY" "$SIGNING_CERT" "$_raw"
        gzip -q "$_raw" ;;
    esac
  done
}

create_mok_enroll_unit() {
  _mok_cert="/usr/share/cert/MOK.der"
  _unit_file="/usr/lib/systemd/system/mok-enroll.service"
  mkdir -p "$(dirname "$_mok_cert")"
  openssl x509 -in "$SIGNING_CERT" -outform DER -out "$_mok_cert"
  chmod 0644 "$_mok_cert"
  mkdir -p "$(dirname "$_unit_file")"
  cat > "$_unit_file" <<EOF
[Unit]
Description=Enroll Margine MOK on first boot
ConditionPathExists=${_mok_cert}
ConditionPathExists=!/var/.mok-enrolled

[Service]
Type=oneshot
# Skip the import (and thus the redundant MokManager prompt at next reboot) when
# it's pointless: Secure Boot off → nothing to enroll; or the Margine MOK is
# already enrolled (e.g. the user enrolled it from the ISO with 'Enroll key from
# disk' before installing). Only when SB is on AND the key is absent do we stage
# the import. ExecStartPost still stamps /var/.mok-enrolled so this never re-runs.
ExecStart=/bin/sh -c 'if mokutil --sb-state 2>/dev/null | grep -qi disabled; then echo "Secure Boot off — no MOK enrollment needed"; elif mokutil --list-enrolled 2>/dev/null | grep -q "Margine MOK Signing Key"; then echo "Margine MOK already enrolled — skipping"; else (echo "${MOK_PASSWORD}"; echo "${MOK_PASSWORD}") | mokutil --import "${_mok_cert}"; fi'
ExecStartPost=/usr/bin/touch /var/.mok-enrolled
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
  chmod 0644 "$_unit_file"
  systemctl -f enable mok-enroll.service
  log "MOK enroll unit installed and enabled"
}

# ---------------------------------------------------------------------------
# Main flow
# ---------------------------------------------------------------------------

log "Disabling kernel install hooks for the duration of the swap"
disable_kernel_install_hooks

log "Removing the stock kernel packages"
dnf -y remove \
    kernel kernel-core kernel-modules kernel-modules-core kernel-modules-extra \
    kernel-devel kernel-devel-matched || true
rm -rf /usr/lib/modules/* || true

log "Enabling COPR: $COPR_REPO"
dnf -y copr enable "$COPR_REPO"

# On self-hosted runners, /var/cache is a persistent BuildKit cache
# mount. A previous failed download (e.g. a partial RPM with bad
# SHA256) gets stored there and dnf will keep re-using it, failing
# every subsequent build with "Payload SHA256 ALT digest: BAD".
# Clean packages + metadata before install so each kernel pull is fresh.
log "Cleaning dnf packages + metadata to avoid cache poisoning on persistent runners"
dnf -y clean packages metadata

log "Installing CachyOS kernel: ${KERNEL_PACKAGES[*]}"
# COPR (copr.fedorainfracloud.org) is occasionally slow or returns 5xx
# / curl timeouts for several minutes — observed 2026-06-02 with run
# #26838562527 dying at "Curl error (28): Timeout was reached" after
# 5 internal librepo retries. Outer retry (shared helper) with backoff
# so transient COPR brownouts don't sink the whole 28-min image build.
# Each attempt cleans metadata first to dodge the bad-metadata-cached
# failure mode (see comment above).
retry 5 30 bash -c 'dnf -y clean metadata >/dev/null 2>&1 || true; exec dnf -y install --refresh "$@"' _ "${KERNEL_PACKAGES[@]}" akmods \
  || { err "CachyOS kernel install FAILED after 5 attempts (COPR likely down)"; exit 1; }

KERNEL_VERSION="$(rpm -q "$KERNEL_PKG" --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')"
log "Installed kernel: $KERNEL_VERSION"

log "Restoring kernel install hooks"
restore_kernel_install_hooks

log "Removing COPR repo file (kept only at build time)"
rm -f /etc/yum.repos.d/*copr*

# Refresh GPU firmware + microcode to match the (newer) CachyOS kernel.
# The CachyOS kernel can be newer than the base image's linux-firmware
# snapshot (the CachyOS spec only Recommends: it), so a kernel that
# references amdgpu blobs absent from the base would fail the GPU probe /
# black-screen before GDM on bare metal — invisible to the virtio-gpu CI
# gate. Upgrade ONLY the firmware packages actually installed (so an
# unknown-package name can't abort the transaction), from the always-on
# Fedora repos; never block the build on it.
FW_PKGS="$(rpm -qa --qf '%{NAME}\n' 'linux-firmware*' 'amd-gpu-firmware*' 'amd-ucode*' 2>/dev/null | sort -u | tr '\n' ' ')"
if [[ -n "${FW_PKGS// /}" ]]; then
  log "Refreshing firmware/microcode for $KERNEL_VERSION: $FW_PKGS"
  # shellcheck disable=SC2086 # intentional word-split of the package list
  dnf -y upgrade --refresh $FW_PKGS \
    || log "WARN: firmware/microcode refresh non-fatal failure (continuing)"
fi

# ---------------------------------------------------------------------------
# v4l2loopback against the CachyOS kernel (OPTIONAL — skip on build error)
# ---------------------------------------------------------------------------
# Building akmod-v4l2loopback in BuildKit currently fails with "ERROR:
# Could create tempdir" because akmodsbuild expects writable /var
# state that isn't available in a build cache mount. Origami works
# around it with their own build environment. For Margine v1 we mark
# v4l2loopback as best-effort: if the build fails, we log and continue
# without it. Users who need virtual camera support can install
# v4l2loopback later as a one-off layer or via Flatpak (OBS has its
# own GStreamer pipeline that doesn't need this module).
log "Building v4l2loopback against $KERNEL_VERSION (best-effort)"
V4L2_OK=0
if disable_akmodsbuild; then
  if dnf -y install \
        "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
     && dnf install -y --setopt=install_weak_deps=False --setopt=tsflags=noscripts \
        akmod-v4l2loopback; then
    if akmods --force --verbose --kernels "$KERNEL_VERSION" --kmod v4l2loopback; then
      # akmods always returns 0; check for *.failed.log explicitly
      V4L2_FAILED=0
      for _f in /var/cache/akmods/v4l2loopback/*-for-"$KERNEL_VERSION".failed.log; do
        [[ -f "$_f" ]] && V4L2_FAILED=1 && break
      done
      if (( V4L2_FAILED == 0 )); then
        V4L2_OK=1
      fi
    fi
    dnf -y remove rpmfusion-free-release
    rm -f /etc/yum.repos.d/rpmfusion-free*.repo
  fi
  restore_akmodsbuild
fi

if (( V4L2_OK )); then
  log "v4l2loopback built OK"
  TRANSIENT+=(akmod-v4l2loopback)
  _kmod_rpm="$(find /var/cache/akmods/v4l2loopback/ -name "kmod-v4l2loopback-*$KERNEL_VERSION*.rpm" -print -quit 2>/dev/null || true)"
  if [[ -n "${_kmod_rpm:-}" && -f "$_kmod_rpm" ]]; then
    dnf -y install "$_kmod_rpm"
    TRANSIENT+=(kmod-v4l2loopback)
  fi
else
  log "v4l2loopback build skipped/failed — not blocking; image continues without virtual camera kmod"
fi

# ---------------------------------------------------------------------------
# NVIDIA driver against the CachyOS kernel — UPSTREAM via DKMS  [ADR 0009 v1]
# ---------------------------------------------------------------------------
# Gated by ENABLE_NVIDIA (build-arg → env, default 0): only the :*-nvidia
# variant builds this; the base build skips the whole block. v1 (2026-06-15)
# pulls NVIDIA's UPSTREAM driver (kmod-nvidia-open-dkms from NVIDIA's own CUDA
# repo) and DKMS-builds it against THIS image's kernel tree — replacing the v0
# RPMFusion akmod, whose nvidia cadence drifts from the CachyOS kernel cadence
# (the CachyOS COPR itself dropped prebuilt nvidia over that skew). This is
# what RakuOS runs in production + what coreos/fedora-bootc-nvidia documents.
# DKMS drops the .ko under /usr/lib/modules/$KERNEL_VERSION/extra/ — INSIDE the
# tree sign_kernel_modules() walks below — so the SAME Margine MOK that signs
# vmlinuz signs the nvidia modules: one key, one enrollment, Secure Boot stays
# ON. (coreos leaves its modules self-signed and tells you to "maintain a
# custom signing key, enroll it with MOK" — that is exactly Margine's loop.)
# EXPERIMENTAL: no NVIDIA GPU in CI → validated only as "builds + signs";
# real-GPU runtime must be confirmed on hardware before :stable-nvidia. Hard-
# fail: a -nvidia image with no nvidia kmod must never ship.
if [[ "${ENABLE_NVIDIA:-0}" == "1" ]]; then
  NVIDIA_KMOD="${NVIDIA_KMOD:-nvidia-open}"   # nvidia-open (Turing+/Blackwell), Margine default
  _arch="$(uname -m)"
  log "NVIDIA variant: DKMS-building upstream ${NVIDIA_KMOD} against $KERNEL_VERSION (hard-fail)"

  # kernel-cachyos-devel-matched (TRANSIENT, already installed) provides the
  # build tree at /usr/lib/modules/$KERNEL_VERSION/build. Add only the DKMS
  # toolchain (build-only → TRANSIENT). No binutils-gold: deprecated/absent on
  # F44 and nvidia-open does not need it.
  dnf -y install --setopt=install_weak_deps=False dkms make gcc elfutils-libelf-devel \
    || { err "DKMS toolchain install failed"; exit 1; }

  # NVIDIA's own CUDA repo, keyed to the base Fedora release. kABI correctness
  # comes from the -k flag below (not the repo's Fedora version); if NVIDIA has
  # not published the exact %fedora repo yet, hard-fail rather than cross-grade
  # to an older Fedora's userland (glibc/dep skew).
  _verid="$(rpm -E %fedora)"
  _repo_url="https://developer.download.nvidia.com/compute/cuda/repos/fedora${_verid}/${_arch}/cuda-fedora${_verid}.repo"
  curl -fsSL --retry 5 --retry-delay 10 -o /etc/yum.repos.d/nvidia.repo "$_repo_url" \
    || { err "no NVIDIA CUDA repo for fedora${_verid}/${_arch} (or fetch failed)"; exit 1; }

  # kmod source + matching userland from the SINGLE NVIDIA repo, one
  # transaction → no kmod/userland version skew. The RPM %post runs a dkms
  # autoinstall against the HOST kernel that fails harmlessly (no host
  # kernel-devel in the build); coreos relies on the same, and we rebuild
  # explicitly with -k below. (If a future package makes that %post fatal to
  # the dnf transaction, add --setopt=tsflags=noscripts here AND an explicit
  # `dkms add -m nvidia -v "$DRIVER_VERSION"` before the build.)
  dnf -y install --no-docs --best --setopt=install_weak_deps=False \
    kmod-nvidia-open-dkms nvidia-driver nvidia-driver-libs nvidia-driver-cuda nvidia-persistenced nvidia-modprobe \
    || { err "nvidia upstream kmod + userland install failed"; exit 1; }

  DRIVER_VERSION="$(rpm -q --qf '%{VERSION}' kmod-nvidia-open-dkms 2>/dev/null)"
  [[ -n "${DRIVER_VERSION:-}" ]] || { err "could not determine kmod-nvidia-open-dkms version"; exit 1; }
  log "NVIDIA upstream driver version: $DRIVER_VERSION"

  # -k "$KERNEL_VERSION" is load-bearing: build against
  # /usr/lib/modules/$KERNEL_VERSION/build (the CachyOS -devel-matched tree),
  # NOT $(uname -r) (the build-host kernel). dkms install drops the .ko under
  # .../extra/ and runs depmod.
  dkms build   -m nvidia -v "$DRIVER_VERSION" -k "$KERNEL_VERSION" --verbose \
    || { err "dkms build of nvidia $DRIVER_VERSION against $KERNEL_VERSION FAILED"; exit 1; }
  dkms install -m nvidia -v "$DRIVER_VERSION" -k "$KERNEL_VERSION" --force --verbose \
    || { err "dkms install of nvidia $DRIVER_VERSION against $KERNEL_VERSION FAILED"; exit 1; }

  _nv_ko="$(find /usr/lib/modules/"$KERNEL_VERSION"/extra -name 'nvidia.ko*' -print -quit 2>/dev/null || true)"
  [[ -n "${_nv_ko:-}" ]] || { err "nvidia DKMS module not under /usr/lib/modules/$KERNEL_VERSION/extra after install"; exit 1; }

  rm -f /etc/yum.repos.d/nvidia.repo       # scrub repo (image convention)
  rm -rf /var/lib/dkms /usr/src/nvidia-*   # build-time DKMS state only; the signed .ko stays
  TRANSIENT+=(dkms make gcc elfutils-libelf-devel)

  # nvidia-drm modeset (+ fbdev for the Wayland/Plymouth handoff) + blacklist nouveau.
  mkdir -p /usr/lib/bootc/kargs.d
  cat > /usr/lib/bootc/kargs.d/30-margine-nvidia.toml <<'KARG'
kargs = ["nvidia-drm.modeset=1", "nvidia-drm.fbdev=1", "rd.driver.blacklist=nouveau", "modprobe.blacklist=nouveau"]
KARG
  # Pull the (about-to-be-MOK-signed) nvidia modules into the initramfs dracut
  # regenerates later in this script (after the signing loop).
  mkdir -p /etc/dracut.conf.d
  printf 'add_drivers+=" nvidia nvidia_modeset nvidia_uvm nvidia_drm "\n' \
    > /etc/dracut.conf.d/90-margine-nvidia.conf
  log "NVIDIA variant: upstream ${NVIDIA_KMOD} $DRIVER_VERSION in place ($_nv_ko) — MOK-signed by the module loop below"
fi

# ---------------------------------------------------------------------------
# scx-scheds — sched_ext BPF schedulers managed by scx_loader/scxctl
# (current shipped names come from `scxctl list`). Ships in the same
# CachyOS addons COPR as the kernel itself, lives in the base image so the
# `ujust margine-scheduler` recipe is available on every Margine
# install — gaming variant inherits it without re-adding. Enable the
# COPR just for the install, then disable + scrub the repo file so user
# systems don't pull random updates from it outside our pipeline.
log "Enabling kernel-cachyos-addons COPR for scx-scheds"
dnf -y copr enable bieszczaders/kernel-cachyos-addons
# Same COPR host as the kernel (copr.fedorainfracloud.org), same 5xx /
# Curl-timeout brownouts — same shared retry helper.
retry 5 30 bash -c 'dnf -y clean metadata >/dev/null 2>&1 || true; exec dnf -y install --refresh scx-scheds' \
  || { err "scx-scheds install FAILED after 5 attempts (kernel-cachyos-addons COPR likely down)"; exit 1; }
dnf -y copr disable bieszczaders/kernel-cachyos-addons || true
rm -f /etc/yum.repos.d/_copr*kernel-cachyos-addons*.repo
log "scx-scheds installed:"
ls /usr/bin/scx_* 2>/dev/null | sed 's|^/usr/bin/||' | sort

# scx_loader is opt-in (Bazzite pattern + audit §6.7). Disabling it
# here is idempotent — if the package preset is already 'disabled' the
# call is a no-op. Users opt in via `ujust margine-scheduler` or the
# margine-scheduler.desktop GUI; tuned profiles ({balanced,powersave,
# throughput-performance}-margine) flip mode via scxctl when the
# service is active. Default-on burned battery without an obvious
# win on a creator workstation.
log "Disabling scx_loader.service by default (opt-in via margine-scheduler)"
systemctl disable scx_loader.service 2>/dev/null || true

# ---------------------------------------------------------------------------
# Gaming-tier userland tools that ALSO benefit creators (promoted 2026-06-05)
# ---------------------------------------------------------------------------
# These three RPMs used to live in the gaming variant only. Moved
# to the base image because their utility is broader than gaming:
#
#   * mangohud      — Vulkan/OpenGL overlay (FPS, CPU, GPU, RAM,
#                     temp, power, frametime). Activated per-app
#                     via `MANGOHUD=1` env var or LD_PRELOAD.
#                     Zero overhead when not used. Creators:
#                     monitor GPU/CPU/RAM during DaVinci/Blender
#                     renders, OBS recording, ffmpeg encoding,
#                     BricsCAD modelling.
#   * goverlay      — Qt GUI to configure MangoHud + vkBasalt
#                     without hand-editing ~/.config/MangoHud/
#                     MangoHud.conf. Pairs with MangoHud.
#   * steam-devices — udev rules for USB game controllers
#                     (Steam, Xbox, PS, generic gamepads).
#                     Zero footprint when no controller plugged
#                     in. Useful for creators using controllers
#                     as jog wheels / foot pedals / generic input.
#
# RPMFusion is REQUIRED for these (the gaming-variant install.sh
# pulls RPMFusion separately + keeps it post-install). For the
# base image we transiently enable RPMFusion ONLY for this install,
# then disable and remove the .repo file so the base stays clean
# of third-party repos (same pattern as kernel-cachyos COPR above).
log "Enabling RPMFusion transiently for mangohud + goverlay + steam-devices"
FEDORA_VER=$(rpm -E %fedora)
dnf -y install \
  "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VER}.noarch.rpm" \
  "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VER}.noarch.rpm"

# gstreamer1-plugins-{bad,ugly} complete the codec swap the declarations
# YAML specifies (host_packages.baseline.codec_replacement.install) —
# ffmpeg full already comes from the base. BOTH resolve from negativo17
# (the base's own multimedia family), NOT from the transient RPMFusion
# enablement above: RPMFusion's bad-freeworld links libx265.so.215 while
# negativo17 ships x265 4.2 (.216) — since 2026-07-04 the two can no
# longer coexist and the build died here for 5 straight retries.
# negativo17's gstreamer1-plugins-bad (epoch 1) is a superset of the
# freeworld build (verified: bundles libgstx265.so, libgstva.so,
# nvcodec/msdk/qsv, fdkaac), so the handbook's codec promises hold.
# RPMFusion stays enabled ONLY for mangohud/goverlay/steam-devices.
retry 5 30 bash -c 'dnf -y clean metadata >/dev/null 2>&1 || true; exec dnf -y install --refresh mangohud goverlay steam-devices gstreamer1-plugins-bad gstreamer1-plugins-ugly' \
  || { err "creator-tier RPM install failed after 5 attempts; aborting"; exit 1; }

# ---------------------------------------------------------------------------
# Native-gaming 32-bit dependency closure — baked + version-locked
# ---------------------------------------------------------------------------
# `ujust margine-gaming-native` layers steam, whose 32-bit (i686) deps pull
# a deep multilib chain: mesa/llvm, SDL3, gtk3, gdk-pixbuf2, glycin, libheif,
# libde265, libdecor, ... Multilib demands every i686 lib match its x86_64
# twin EXACTLY. Layered at RUNTIME against a frozen base, the i686 libs come
# from whatever the live repos offer, and the moment any one drifts past the
# baked x86_64 version the whole transaction fails to depsolve — the repeated
# 2026-06-13 breakages (first mesa/llvm, then SDL3/libheif/libde265/...).
#
# Fix (Bazzite's approach): install the full native-gaming app set HERE so
# dnf resolves the entire i686+x86_64 closure in ONE transaction (version-
# locked to this build), then remove ONLY the apps with --no-autoremove so
# their whole dependency closure stays baked in the base. The opt-in gaming-
# native layer then re-adds the apps against deps already satisfied by
# @System — no runtime i686 fetch, no skew, ever. RPMFusion is still enabled
# here (scrubbed just below), which is where steam resolves at build time.
#
# vkBasalt is intentionally NOT in this set: it already ships in the base, so
# install would be a no-op and remove would strip a base package. Keep this
# list in sync with build_files/60-ujust-services/gaming-native-packages.txt
# (minus vkBasalt). Hard-fail on any error: a build that cannot bake the
# closure must stop, never promote a :stable where margine-gaming-native is
# broken. The smoke-boot dry-run guard (.github/smoke/gui-probe.sh) then
# re-verifies the full recipe set resolves on the booted image.
GAMING_BAKE=(steam lutris retroarch gamescope)
log "Baking native-gaming 32-bit dependency closure: ${GAMING_BAKE[*]}"
retry 5 30 bash -c 'dnf -y clean metadata >/dev/null 2>&1 || true; exec dnf -y install --refresh "$@"' _ "${GAMING_BAKE[@]}" \
  || { err "native-gaming closure install failed after 5 attempts (repo down or unresolvable multilib at build?); aborting"; exit 1; }
dnf -y remove --no-autoremove "${GAMING_BAKE[@]}" \
  || { err "failed to strip gaming apps while keeping their deps; aborting"; exit 1; }
log "Native-gaming 32-bit closure baked (apps removed, deps version-locked in base)"

# Scrub RPMFusion from the base image — gaming variant will re-add
# it (and keep it) for the gamescope+vkBasalt install. Base stays
# clean of third-party repos. NB: we deliberately do NOT
# `dnf autoremove` here (see margine-image PR #26 — autoremove
# strips the kernel-cachyos chain whose COPR was just disabled).
log "Removing RPMFusion .repo files from base"
dnf -y remove rpmfusion-free-release rpmfusion-nonfree-release || true
rm -f /etc/yum.repos.d/rpmfusion-*.repo
log "Base now ships: mangohud + goverlay + steam-devices + gstreamer freeworld/ugly codecs"

# ---------------------------------------------------------------------------
# Signing
# ---------------------------------------------------------------------------
log "Signing kernel image with MOK"
sign_kernel

log "Signing kernel modules with MOK"
sign_kernel_modules

log "Creating MOK enroll unit for first-boot import"
create_mok_enroll_unit

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------
log "Removing transient build-only packages: ${TRANSIENT[*]}"
dnf -y remove "${TRANSIENT[@]}" || true

# Drop a dracut config to disable host-only mode for every subsequent
# dracut invocation in this image (build.sh's Plymouth regeneration too,
# and any user-triggered `rpm-ostree initramfs` post-install). Without
# this, dracut runs in the build container — where there's no LUKS,
# no btrfs root, no virtio-net — and bakes an initramfs that boots only
# on hardware exactly like the build container. End users with LUKS
# encryption (every real install) get a kernel panic at early boot:
#   VFS: Cannot open root device "UUID=..."
# because the crypto/dm/btrfs modules are not in the initramfs.
mkdir -p /etc/dracut.conf.d
cat > /etc/dracut.conf.d/01-margine-no-hostonly.conf <<'CONF'
# Required for bootc / OCI image builds: the build environment is not
# the deployment environment, so initramfs must be generic.
hostonly="no"
hostonly_cmdline="no"
CONF

# NB: we deliberately do NOT force virtio_gpu into the initramfs. It proved
# UNNECESSARY — Plymouth renders fine in UEFI VMs via the EFI framebuffer
# (efifb, built-in) once it isn't deferred by a serial console (handled by
# plymouth.ignore-serial-consoles in 10-margine-plymouth.toml). It was also
# unlandable here: `dracut --add-drivers virtio_gpu` includes the module on a
# host but the build container's dracut silently skipped it (the 2026-06-19
# builds failed an assertion proving it never made the initramfs). The brief
# efifb->virtio_gpu mode switch mid-boot is handled by the theme re-centering on
# resize (margine.script refresh_callback). On bare metal the real GPU driver
# (e.g. amdgpu) is already in the generic set. So: no virtio_gpu drop-in.

# Regenerate initramfs at the **bootc/ostree-expected path**:
#   /usr/lib/modules/<KVER>/initramfs.img
# Bluefin DX (and every Universal Blue image) puts initramfs there.
# bootc/ostree picks it up at deployment time from that exact path.
# Dracut's default output is /boot/initramfs-<KVER>.img — the traditional
# Anaconda/non-ostree location — which ostree IGNORES, falling back to
# auto-generating a host-only initramfs (no crypto/btrfs/virtio_blk
# modules → kernel panic on real installs with LUKS).
#
# We pass the output path as a positional argument so dracut writes
# exactly where ostree expects.
# Suppress the dracut-install ERROR: installing '/root' / FAILED warnings
# that have been showing up in every build for months. Source: dracut's
# 95ssh-client module-setup.sh probes for /root/.ssh/known_hosts +
# /root/.ssh/config; even though the `[[ -f ... ]]` guards skip them when
# absent, dracut-install still tries to mkdir the parent dir /root/.ssh/
# inside the staging tree, and barfs if /root doesn't exist as an actual
# directory in the build sysroot. Creating /root as a vacant chmod-700
# dir satisfies the dracut-install parent-mkdir path; the `-f` guard in
# the ssh-client module still skips the keyfiles themselves (they're not
# there in a bootc image-build environment).
#
# Pure cosmetic fix — image semantics unchanged. The alternative
# (`omit_dracutmodules+=" ssh-client "`) would silence the warnings but
# also lose the dracut-side hook used for remote LUKS unlock via dropbear,
# which is unrelated baggage.
ROOT_HOME="$(realpath -m /root)"
mkdir -p "$ROOT_HOME"
chmod 700 "$ROOT_HOME"

log "Regenerating initramfs for all installed kernels (generic, bootc-path, ostree)"
# --add ostree: ESSENTIAL for bootc/ostree systems. Without it the
# initramfs doesn't include ostree-prepare-root, which is what pivots
# /sysroot from the raw btrfs root (where there's no /etc/os-release
# at the top level — just home/root/var subvolumes) to the actual
# deployment content under /ostree/deploy/.../.../. Without this,
# systemd's switch-root check `openat(fd, "etc/os-release",
# O_NOFOLLOW)` fails because /sysroot is the wrong filesystem view.
# Symptom: "Failed to switch root: ... os-release file is missing"
# even when the deployment is fully present on disk.
# Verified missing 2026-05-30: `lsinitrd <initramfs> | grep ostree`
# returned ZERO lines on our published image. `--no-hostonly` alone
# is insufficient; ostree dracut module must be EXPLICITLY requested.
# The initramfs MUST be zstd-compressed (today this only works by
# inheriting Bluefin's 10-compression.conf; nothing pins it). Pass --zstd
# explicitly AND fail loudly if the tool is missing, so dracut can never
# silently fall back to gzip (slower boot, bigger initramfs).
command -v zstd >/dev/null || { err "zstd binary missing — dracut would silently gzip the initramfs"; exit 1; }
export DRACUT_NO_XATTR=1
for kver_dir in /usr/lib/modules/*/; do
  kver=$(basename "$kver_dir")
  dracut --force --zstd --no-hostonly --no-hostonly-cmdline \
      --add "ostree" \
      --kver "$kver" \
      "${kver_dir}initramfs.img"
  log "Wrote ${kver_dir}initramfs.img ($(du -h "${kver_dir}initramfs.img" | cut -f1))"
done

# Final integrity check (Origami pattern): vmlinuz must still be the
# exact bytes sign_kernel produced — a post-signing rewrite would ship
# a kernel Secure Boot rejects with the cryptic "bad shim signature".
sha256sum -c /tmp/vmlinuz.sha >/dev/null \
  || { err "vmlinuz was modified AFTER signing — refusing to ship"; exit 1; }
rm -f /tmp/vmlinuz.sha
log "vmlinuz signature integrity verified end-of-build"

log "custom-kernel install complete: $KERNEL_VERSION"
