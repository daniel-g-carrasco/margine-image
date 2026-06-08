# Margine interactive-defaults additions (Titanoboa / ADR-0008).
# build.sh APPENDS this to anaconda-live's base
# /usr/share/anaconda/interactive-defaults.ks (Aurora/Bazzite pattern —
# the base ships liveinst integration we must preserve).
#
# Partitioning is the PR #80 contract ported VERBATIM (ADR §4 invariant):
# single-disk autodetect via %pre, then ESP 4 GiB + single btrfs / --grow.
# Anaconda has no profile key for ESP size, so the explicit `part` here is
# the only way to override the 600 MB default — hence kickstart-driven
# partitioning rather than the WebUI profile's default_partitioning.

# --- PR #80 single-disk autodetect -----------------------------------
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

%include /tmp/part-include.ks
zerombr
clearpart --all --initlabel --disklabel=gpt
part /boot/efi --fstype=efi --size=4096 --label=ESP
part / --fstype=btrfs --grow --label=margine_root
bootloader --timeout=1

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

# --- Post-install (order matters: switch origin, tune fs, bake apps) ---
%include /usr/share/anaconda/post-scripts/bootc-switch.ks
%include /usr/share/anaconda/post-scripts/zstd-compress.ks
%include /usr/share/anaconda/post-scripts/install-flatpaks.ks
