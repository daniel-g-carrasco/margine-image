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
#   /tmp/certs/mok-password   — single-line password for mokutil enrollment
#
set -euo pipefail

log() { printf '[custom-kernel] %s\n' "$*"; }
err() { printf '[custom-kernel] ERROR: %s\n' "$*" >&2; }

SIGNING_KEY="/tmp/certs/MOK.key"
SIGNING_CERT="/tmp/certs/MOK.pem"
MOK_PASSWORD_FILE="/tmp/certs/mok-password"

for f in "$SIGNING_KEY" "$SIGNING_CERT" "$MOK_PASSWORD_FILE"; do
  [[ -f "$f" ]] || { err "Missing secret: $f"; exit 1; }
done

MOK_PASSWORD="$(tr -d '[:space:]' < "$MOK_PASSWORD_FILE")"
[[ -n "$MOK_PASSWORD" ]] || { err "MOK password is empty"; exit 1; }

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
KERNEL_PACKAGES="kernel-cachyos kernel-cachyos-core kernel-cachyos-modules kernel-cachyos-devel-matched"
TRANSIENT="akmods $KERNEL_DEVEL_PKG"

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
ExecStart=/bin/sh -c '(echo "${MOK_PASSWORD}"; echo "${MOK_PASSWORD}") | mokutil --import "${_mok_cert}"'
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

log "Installing CachyOS kernel: $KERNEL_PACKAGES"
# shellcheck disable=SC2086
dnf -y install $KERNEL_PACKAGES akmods

KERNEL_VERSION="$(rpm -q "$KERNEL_PKG" --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')"
log "Installed kernel: $KERNEL_VERSION"

log "Restoring kernel install hooks"
restore_kernel_install_hooks

log "Removing COPR repo file (kept only at build time)"
rm -f /etc/yum.repos.d/*copr*

# ---------------------------------------------------------------------------
# v4l2loopback against the CachyOS kernel
# ---------------------------------------------------------------------------
log "Building v4l2loopback against $KERNEL_VERSION"
disable_akmodsbuild

dnf -y install \
    "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm"
dnf install -y --setopt=install_weak_deps=False --setopt=tsflags=noscripts \
    akmod-v4l2loopback
TRANSIENT="$TRANSIENT akmod-v4l2loopback"

akmods --force --verbose --kernels "$KERNEL_VERSION" --kmod v4l2loopback

# akmods always returns 0; check for *.failed.log explicitly
for _f in /var/cache/akmods/v4l2loopback/*-for-"$KERNEL_VERSION".failed.log; do
  if [[ -f "$_f" ]]; then
    err "v4l2loopback akmod build failed:"
    cat "$_f"
    restore_akmodsbuild
    exit 1
  fi
done

dnf -y remove rpmfusion-free-release
rm -f /etc/yum.repos.d/rpmfusion-free*.repo
restore_akmodsbuild

# Install built kmod RPM
_kmod_rpm="$(find /var/cache/akmods/v4l2loopback/ -name "kmod-v4l2loopback-*$KERNEL_VERSION*.rpm" -print -quit)"
if [[ -n "${_kmod_rpm:-}" && -f "$_kmod_rpm" ]]; then
  dnf -y install "$_kmod_rpm"
  TRANSIENT="$TRANSIENT kmod-v4l2loopback"
else
  log "(no built kmod-v4l2loopback rpm to install; skipping)"
fi

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
log "Removing transient build-only packages: $TRANSIENT"
# shellcheck disable=SC2086
dnf -y remove $TRANSIENT || true

# Regenerate initramfs against the new kernel
log "Regenerating initramfs for $KERNEL_VERSION"
/usr/lib/dracut/dracut-install --kver "$KERNEL_VERSION" || true
dracut --force --kver "$KERNEL_VERSION" --regenerate-all || true

log "custom-kernel install complete: $KERNEL_VERSION"
