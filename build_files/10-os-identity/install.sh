#!/usr/bin/env bash
# Margine image build — section: 10-os-identity
# Sub-script of the build.sh orchestrator. Decomposed on 2026-06-06
# (audit §8 rec #22 — split build.sh into per-area install scripts).
# See build_files/00-common.sh + build_files/build.sh.
set -euo pipefail
. /ctx/00-common.sh

# 0. OS identity — make the system identify as Margine
# ---------------------------------------------------------------------------
# Override the os-release file so `cat /etc/os-release`, `hostnamectl`,
# GNOME's About panel, and our own validate-atomic-layout all see
# "Margine". ID=fedora (see below) keeps distro-tooling that branches
# on Fedora behaviour working; ID_LIKE=bluefin records the actual
# parent for anything Bluefin-aware. (This comment used to claim
# ID_LIKE=fedora while the code shipped ID_LIKE=bluefin — fixed
# 2026-06-12.)
#
# Layout: /usr/lib/os-release is the canonical file (writable here at
# build time), /etc/os-release is a symlink to the relative path
# `../usr/lib/os-release`. This is the standard Fedora/Bluefin layout
# and the only thing modern systemd recognises as "an OS tree".
#
# Historical note: an earlier Margine build (May 2026) shipped both as
# regular files because our switch-root was failing with "os-release
# file is missing". Root cause was that /usr wasn't yet mounted via
# composefs at switch-root time, so the symlink couldn't be followed.
# Routed around it by writing both as regular files (Fix A). The proper
# fix (Fix B) was wiring rechunk into the CI pipeline so the published
# image is ostree-canonical and composefs is up by the time
# switch-root needs to read os-release. With rechunk in build.yml since
# 2026-06-01 the workaround is no longer needed — restored the symlink
# to the canonical Fedora layout.
#
# See docs/lessons-learned/2026-05-28-initramfs-and-bootc-labels.md
# for the full investigation, and docs/lessons-learned/2026-06-03-
# rechunk-and-fixb.md for the wind-down.
log "Stamping os-release as Margine (canonical Fedora layout: /etc → /usr/lib symlink)"

# (var defined in 00-common.sh)
# (var defined in 00-common.sh)

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

# /usr/lib/os-release — the canonical location written as a regular file.
printf '%s\n' "$OS_RELEASE_CONTENT" > /usr/lib/os-release
chmod 0644 /usr/lib/os-release

# /etc/os-release — relative symlink to the canonical location.
# Relative (not absolute) so the link resolves correctly inside any
# chroot / mount namespace, the same way upstream Fedora ships it.
ln -sf ../usr/lib/os-release /etc/os-release

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
  # Same merge the boot-time oneshot uses — ONE implementation, two
  # callers (build with --force, boot guarded). Until 2026-06-12 this
  # was a hand-synced python-heredoc copy of the seeder. Called from
  # /ctx because system_files hasn't been copied into the rootfs yet
  # at this point in the build.
  python3 /ctx/system_files/usr/libexec/margine-seed-etc-passwd --force
  chmod 0644 /etc/passwd /etc/group
else
  log "WARNING: /usr/lib/passwd or /usr/lib/group missing — skipping factory seed"
fi

# ---------------------------------------------------------------------------
# 0.ter Copy build_files/system_files/ into the rootfs (Bluefin pattern)
# ---------------------------------------------------------------------------
# As of PR E (first-boot notification, 2026-06-04) we ship static
# system files (autostart .desktop entries, /usr/libexec scripts,
# systemd unit files, etc.) under build_files/system_files/. The
# whole tree gets rsync'd into the rootfs at "/" so file paths in
# the repo mirror their final installed location. Same pattern as
# Bluefin's system_files/shared/.
if [[ -d /ctx/system_files ]]; then
  log "Copying /ctx/system_files/ → / (overlaying base rootfs)"
  cp -a /ctx/system_files/. /
  # Set executable bit on libexec scripts (cp -a preserves mode but
  # git may have flagged them differently across platforms).
  find /usr/libexec /usr/bin -type f \( \
      -path '*/margine-*' -o \
      -path '/usr/libexec/margine/*' \
    \) -exec chmod 0755 {} \;
fi

# ---------------------------------------------------------------------------
