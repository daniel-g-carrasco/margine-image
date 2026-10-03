#!/usr/bin/env bash
# Margine image build — final build-residue sweep, chained right before
# `bootc container lint` (see Containerfile). Runs AFTER every other
# build step, including build-margine-extensions.sh (the last dnf user).
#
# bootc treats image /var strictly as a first-boot seed: anything the
# build leaves there is dead weight on installed systems and trips the
# lint `var-tmpfiles` warning. What we remove and why:
#
#  - /var/lib/dnf — repo state, countme cookies and the system-repo
#    lock from the build's dnf transactions (kernel + extensions).
#    Installed systems manage the OS with bootc, not dnf, and any
#    containerized dnf recreates all of it. Appeared when dnf5 moved
#    this state out of /var/cache (which IS a cache mount here) into
#    /var/lib. Removing the countme cookies does NOT affect the /status
#    device chart: that counts via the rpm-ostree/bootc countme service
#    (VARIANT_ID=margine), not dnf's per-repo cookies.
#  - /var/lib/rpm-state — kernel scriptlet state (kernel-cachyos), only
#    meaningful inside the rpm transaction that already finished.
#  - /var/lib/authselect/checksum — dropped by authselect scriptlets
#    during the build's package transactions; nothing at boot reads it,
#    and a deployed system regenerates its own at install time (the
#    reference host's copy is dated install day, not build day).
#
# The `sysusers` lint warnings are NOT ours to fix: Fedora/Bluefin base
# packages (cockpit, dhcpcd, moby-engine, avahi, ...) create their users
# imperatively in scriptlets instead of shipping sysusers.d fragments.
set -euo pipefail

rm -rf /var/lib/dnf /var/lib/rpm-state
rm -f /var/lib/authselect/checksum
rmdir /var/lib/authselect 2>/dev/null || true

# Build state that changed on every rebuild and moved whole layers with
# it (2026-10-03, measured file by file between two builds of the same
# tree; the chunking step also prunes /run as a whole):
#  - /run: the build's GPG home, COPR key copies, akmods and dnf locks.
#    /run is a tmpfs on every booted system, so none of it is ever seen.
#  - /var/roothome/.android: adb's key pair, generated when 70-phone-cam
#    smoke-tests scrcpy. 70-phone-cam now removes it; this is the net.
#  - libdnf5's transaction history: timestamps of the build's own dnf
#    runs. Installed systems are managed by bootc, and dnf recreates the
#    file when it needs one.
#  - rpmdb.sqlite-shm: replaced by a fresh one at the very end, after the
#    last rpm call of this script (see below).
rm -rf /run/margine-gnupg /run/akmods /run/dnf /run/copr-*.gpg
rm -rf /var/roothome/.android
rm -f /usr/lib/sysimage/libdnf5/transaction_history.sqlite \
      /usr/lib/sysimage/libdnf5/transaction_history.sqlite-shm \
      /usr/lib/sysimage/libdnf5/transaction_history.sqlite-wal

# Make what's left visible in the build log, so a future regression
# (a new step parking state in /var) is easy to spot next to the lint.
echo "Remaining /var content after build-residue cleanup:"
find /var -mindepth 1 -maxdepth 3 | sort

# SELinux: /home is the alias, /var/home the real path (2026-10-03).
#
# rpm-ostree's compose rewrites file_contexts.subs_dist so that /home maps
# to /var/home (postprocess_subs_dist in rpm-ostree composepost.rs). The dx
# layer of our base pulls a newer selinux-policy-targeted, whose RPM puts
# the stock "/var/home /home" line back. With it, every lookup under the
# real home path is rewritten to /home, where file_contexts.homedirs has no
# rules, and comes back default_t: matchpathcon ~/.ssh says default_t, so
# the first restorecon on a home breaks SSH key login (sshd_session_t
# cannot read authorized_keys). Reported as ublue-os/bluefin#4976, fix
# pending in #4979. Reapplied here, after the last package transaction,
# with the same edit rpm-ostree makes; a no-op once the base is fixed.
SUBS=/etc/selinux/targeted/contexts/files/file_contexts.subs_dist
if [[ -f "$SUBS" ]]; then
  sed -i -E 's|^(/var/home[[:space:]].*)$|# \1|' "$SUBS"
  grep -qxE '/home[[:space:]]+/var/home' "$SUBS" || echo '/home /var/home' >> "$SUBS"
fi

# Deterministic mtimes for chunkah (2026-09-01).
#
# chunkah writes every tar entry with mtime = min(real mtime, clamp of
# the component). For rpm-owned files the clamp is the package build
# time, so those entries never move. For everything else (bigfiles,
# unclaimed files, and the ancestor directories written into EVERY
# layer) the clamp is the image's own Created time, i.e. the build
# time, so the real mtime wins. Measured on candidate.20260831 vs
# candidate.20260901: 32 of 127 layers differed, and a same-size pair
# (bigfiles/libvulkan_intel_hasvk.so) had identical files and differed
# only in the mtimes of "usr" and "usr/lib64", touched by that day's
# package updates. Directories and files created during the build get
# mtime 0 here, so those entries stop depending on when we built.
# rpm-owned files are left alone (their mtimes are already stable, and
# changing them would move every layer once). The installed system is
# unaffected: ostree stores content with mtime 0 anyway.
# --source-date-epoch would also do it, but it changes the image
# Created (stale-image-alarm reads it) and chunkah's stability model
# (coreos/chunkah#160).
#
# 2026-10-03: "newer than this script" missed every file COPYed from the
# repo (system_files, assets): they carry the checkout time, which is
# also this script's mtime, so -newer never matched them and 88 of them
# (unit files, margine scripts, desktop files) changed mtime on every
# build, moving the 184 MiB layer of unpackaged files each time. Every
# path no rpm owns now gets mtime 0 too; rpm-owned files keep theirs.
# The rpm query runs FIRST: opening the rpmdb touches /usr/share/rpm, and
# when it ran after the directory pass that one directory mtime moved the
# 184 MiB layer between two builds of the same tree (2026-10-03, second
# measurement). Every step below that writes into a directory is followed
# by one last directory pass at the end of the script.
rpm -qa --qf '[%{FILENAMES}\n]' 2>/dev/null | LC_ALL=C sort -u > /tmp/margine-owned
echo "Normalising mtimes of directories and build-created files"
find / -xdev \( -type d -o -newer /ctx/99-cleanup.sh \) -exec touch -h -d @0 {} + 2>/dev/null || true
find / -xdev ! -type d -print 2>/dev/null | LC_ALL=C sort > /tmp/margine-all
LC_ALL=C comm -23 /tmp/margine-all /tmp/margine-owned > /tmp/margine-unowned
echo "Normalising mtimes of $(wc -l < /tmp/margine-unowned) files no package owns"
tr '\n' '\0' < /tmp/margine-unowned | xargs -0 -r touch -h -d @0 2>/dev/null || true
rm -f /tmp/margine-owned /tmp/margine-all /tmp/margine-unowned

# Fontconfig caches record the mtime of each font directory they index,
# so the ones written earlier in the build (14-fonts) held build-time
# directory mtimes: 68 cache files differed between two builds. Rebuilt
# here, after every directory is at mtime 0, they are identical from one
# build to the next (checked twice on Fedora 44) and also match the
# mtimes ostree gives directories on installed systems. -s: system
# caches only, nothing under root's home; -r: drop caches of directories
# that no longer exist instead of keeping them from the base.
echo "Rebuilding the system fontconfig cache against the normalised mtimes"
fc-cache -s -r >/dev/null 2>&1 || true
find /usr/lib/fontconfig/cache -xdev -exec touch -h -d @0 {} + 2>/dev/null || true

# Last: the rpmdb's SQLite shared-memory index (rpmdb.sqlite-shm). The
# one left by the build's dnf transactions differs on every build, but the
# file itself is REQUIRED: the rpmdb is in WAL mode and cannot be opened
# read-only without it (removing it made chunkah fail with "unable to open
# database file" on the read-only image mount, and `rpm -qa` would fail
# the same way on installed systems, where /usr is read-only). So it is
# replaced, not removed: drop the stale one (only when there is no -wal to
# replay, so no rpmdb content can be lost), let a read-only query create a
# fresh one, which is identical from build to build (measured), and pin
# its mtime. Then one more directory pass for everything written above.
# No rpm call may follow this point.
SHM=/usr/share/rpm/rpmdb.sqlite-shm
if [[ ! -s /usr/share/rpm/rpmdb.sqlite-wal ]]; then
  rm -f "$SHM"
  rpm -q rpm >/dev/null
fi
[[ -e "$SHM" ]] && touch -h -d @0 "$SHM"
find / -xdev -type d -exec touch -h -d @0 {} + 2>/dev/null || true
