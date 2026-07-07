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

# Make what's left visible in the build log, so a future regression
# (a new step parking state in /var) is easy to spot next to the lint.
echo "Remaining /var content after build-residue cleanup:"
find /var -mindepth 1 -maxdepth 3 | sort
