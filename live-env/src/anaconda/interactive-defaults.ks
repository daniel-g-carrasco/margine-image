# Margine interactive-defaults additions (Titanoboa / ADR-0008).
# build.sh APPENDS this to anaconda-live's base
# /usr/share/anaconda/interactive-defaults.ks (Aurora/Bazzite pattern —
# the base ships liveinst integration we must preserve).
#
# PARTITIONING IS PROFILE-DRIVEN (margine.conf [Storage] default_partitioning
# + default_scheme=BTRFS), NOT explicit kickstart `part` directives.
# Why: anaconda-webui 44-68 (Fedora 44 ships 68) has a bug — any `part`
# command makes Anaconda select the CUSTOM partitioning method, which never
# publishes the Storage.Partitioning.Automatic DBus interface; the WebUI
# then queries that interface unconditionally and crashes with
# "Reading information about the computer failed" (InvalidArgs). Fixed
# upstream in anaconda-webui 69 (commit 135c87881, 2026-03-18), not yet in
# F44. So we drop the explicit partitioning and let the profile drive the
# AUTOMATIC flow, exactly like Aurora/Bazzite.
#
# CONSEQUENCE: the ESP stays at Anaconda's default (~600 MiB, hardcoded in
# platform.py EFI._bootloader_partition — no profile key can enlarge it on
# the AUTOMATIC path). The PR #80 4 GiB ESP is DEFERRED until F44 ships
# anaconda-webui >= 69, at which point the explicit `part /boot/efi
# --size=4096` block can be restored. ~600 MiB holds several UKIs, so it is
# acceptable for v1 Sealed-Boot work (ADR-0007). See ADR-0008.
#
# The %pre single-disk autodetect below is KEPT — it only ever emits
# `ignoredisk --only-use=<dev>`, which does NOT select CUSTOM, so it is
# WebUI-safe and just pre-narrows disk selection for the AUTOMATIC flow.

# --- single-disk autodetect (WebUI-safe: emits only ignoredisk) ------
%pre --erroronfail --log=/tmp/margine-disk-detect.log
#!/bin/bash
set -euo pipefail

part_include=/tmp/part-include.ks
: > "$part_include"

mapfile -t install_disks < <(
  for sysdev in /sys/block/*; do
    dev=$(basename "$sysdev")
    case "$dev" in
      loop*|ram*|zram*|sr*|fd*|md*|dm-*)
        continue
        ;;
    esac
    [[ -b "/dev/$dev" ]] || continue
    [[ -r "$sysdev/ro" && "$(cat "$sysdev/ro")" == "1" ]] && continue
    [[ -r "$sysdev/removable" && "$(cat "$sysdev/removable")" == "1" ]] && continue
    printf '%s\n' "$dev"
  done | sort
)

if [[ "${#install_disks[@]}" -eq 1 ]]; then
  printf 'ignoredisk --only-use=%s\n' "${install_disks[0]}" > "$part_include"
  echo "single install disk detected: ${install_disks[0]}"
else
  printf '# %s installable disks detected; require explicit Anaconda disk selection\n' "${#install_disks[@]}" > "$part_include"
  printf 'installable disks: %s\n' "${install_disks[*]:-none}"
fi
%end

# ignoredisk (single-disk case) narrows the disk set for the WebUI's
# AUTOMATIC partitioning. No zerombr/clearpart/part here — those would
# select CUSTOM and crash anaconda-webui 68 (see header). The actual
# layout comes from margine.conf [Storage] default_partitioning.
%include /tmp/part-include.ks

# --- Install source ---------------------------------------------------
# ADR-0008 §7 OPEN DECISION (v1 choice = registry transport):
# ostreecontainer fetches margine:stable from the registry at install
# time. This keeps the ISO under the 10 GB §4 invariant (the offline
# alternative — pre-pulling margine:stable into the live image's
# containers-storage with --transport=containers-storage — adds ~5-6 GB
# and pushes the ISO over 10 GB). CONSEQUENCE: the install needs network.
# Margine's current BIB ISO is offline-capable, so this is a v1 UX
# regression flagged as the #1 revisit item. To switch to offline:
# pre-pull in build.sh + change the line below to
#   --transport=containers-storage
ostreecontainer --url=ghcr.io/daniel-g-carrasco/margine:stable --transport=registry --no-signature-verification

# --- Post-install (order matters: switch origin, tune fs, stage MOK,
#     bake apps) ---
%include /usr/share/anaconda/post-scripts/bootc-switch.ks
%include /usr/share/anaconda/post-scripts/zstd-compress.ks
%include /usr/share/anaconda/post-scripts/secureboot-enroll-key.ks
%include /usr/share/anaconda/post-scripts/disable-fedora-flatpak.ks
%include /usr/share/anaconda/post-scripts/install-flatpaks.ks
%include /usr/share/anaconda/post-scripts/flatpak-restore-selinux-labels.ks
