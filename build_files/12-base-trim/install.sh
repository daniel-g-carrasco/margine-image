#!/usr/bin/env bash
# Remove what the base ships and Margine does not want in an installed system.
#
# WHY THIS EXISTS (2026-08-25)
#
# The new Bluefin (ghcr.io/projectbluefin/bluefin) is built as a
# "container-native ISO": the image itself boots as a live system and
# carries the installer. So it ships anaconda (core, live, tui, webui),
# livesys-scripts, dracut-live, isomd5sum, cockpit-ws for the Anaconda
# WebUI, qt6-qtwebengine (277 MiB, required by nothing) and a Firefox RPM
# for the live session's favourites. Bluefin DX, today's base, ships none
# of that.
#
# Margine builds its ISO differently: live-env/src/build.sh layers
# dracut-live, livesys-scripts, anaconda-live and anaconda-webui on top
# of the finished image at ISO time, with Margine's own Anaconda profile.
# An installed Margine has never carried an installer, and the spec
# (docs/spec/06, "do not use the system Firefox RPM") ships Zen as a
# Flatpak with org.mozilla.firefox as the Flatpak fallback. Decision
# (2026-08-25): strip both on any base that brings them.
#
# Measured inside the trial image on the plain base: an explicit remove
# of the list below takes 12 packages and 583 MiB (the two extra ones
# are dependents: qt6-qtwebview, slitherer). Orphan cleanup
# (clean_requirements_on_remove) would take 68 packages and 656 MiB but
# also fuse (FUSE 2, AppImages), python3-rpm, python3-systemd and
# NetworkManager-team, all present in today's image; so it stays off and
# the ~70 MiB of orphaned libraries are left alone on purpose.
#
# On today's base every package below is absent and this is a no-op.
#
# LEFTOVERS AND UNWANTED FAMILIES (2026-10-10)
#
# A package audit of lucciola.20261009 by originating layer found 3.6 GB
# that nothing needs:
#   - qemu for every architecture but x86 (Bluefin DX installs the `qemu`
#     meta package): 57 packages, 1088 MB. Margine's VMs
#     (margine-test-vm, virt-manager, podman-machine) are x86 only.
#   - wine and mingw64, 1.9 GB: weak dependencies of lutris left behind by
#     the gaming bake in custom-kernel. The bake no longer installs weak
#     dependencies; this is the guard.
#   - fluid soundfonts and wildmidi (330 MB), python3-boto3/botocore
#     (130 MB), gnome-user-docs and yelp (65 MB; Margine ships its own
#     offline docs and Bluefin itself excludes yelp): orphans.
# The families are matched by name pattern, so they are removed whatever
# the base's version of them; the prove-it block then checks that
# everything the x86 VMs need is still there.
#
# DEVELOPER STACK ON DEMAND (2026-10-10)
#
# Bluefin DX ships a developer stack most installs never open. What stays
# is what Margine's recipes and validators use: the x86 virt stack, Podman
# (with podman-docker answering to `docker`), ROCm OpenCL and the HIP
# runtime. What goes, and comes back with one ujust command:
#   - Docker CE (409 MB): `ujust margine-docker`
#   - cockpit, eBPF tracing (bcc, bpftrace, bpftop and their LLVM 21),
#     sysprof, igt-gpu-tools, the host toolchain (gcc, g++, glibc-devel,
#     kernel-devel): `ujust margine-devtools`; distrobox is the everyday
#     way to build things
#   - tailscale (72 MB and a daemon with an open UDP port on every install,
#     docs/SECURITY-CLAIMS.md D4): `ujust margine-tailscale`
#   - incus and incus-agent, rclone, restic, borgbackup: layer them or
#     `brew install` them
#   - the HIP compiler and its 2 GB of static LLVM (rocm-llvm-static,
#     rocm-device-libs, hipcc and the rocm -devel packages): removed in
#     15-devstack, right after the step that installs rocm-hip.
# THE CASCADE (2026-10-12)
#
# `dnf remove` takes the packages that require what it removes, and
# clean_requirements_on_remove=False does not change that: it only keeps
# the orphans. On silverblue-main the negativo17 build of
# gstreamer1-plugins-bad links libWildMidi, gtk4 requires that plugin
# set, and removing wildmidi-libs (or the soundfont patches it requires,
# which the first rehearsal of this fix tried) took 65 dependents: gtk4,
# libadwaita, GNOME Shell, GDM, Nautilus, Ptyxis, the GNOME portal, the
# Bluetooth panel, the System Monitor, the VPN plugins, the GTK 4 input
# method. Later build steps pulled the Shell and GDM back as dependencies
# of what they install; Files, Ptyxis and the rest did not come back, and
# the images of 2026-10-11 shipped without them. Neither the keep list
# nor `dnf check` saw it: the result was consistent, only smaller. Since
# then the trim compares the package set before and after the removal and
# fails the build when dnf took anything the list does not name, the
# desktop's own packages are in the keep list, and the system validator
# checks that the desktop is whole (section 1b).
set -euo pipefail
. /ctx/00-common.sh
log() { printf '[base-trim] %s\n' "$*"; }
err() { printf '[base-trim] ERROR: %s\n' "$*" >&2; }

TRIM_PKGS=(
  anaconda-core anaconda-live anaconda-tui anaconda-webui  # the installer
  livesys-scripts dracut-live isomd5sum                     # live-boot plumbing
  cockpit-ws                                                # Anaconda WebUI transport
  qt6-qtwebengine qt6-qtwebview slitherer                   # 277 MiB, required by nothing but these two
  firefox firefox-langpacks mozilla-openh264                # spec: no system Firefox RPM
  fluid-soundfont-gm fluid-soundfont-gs                     # MIDI soundfonts, orphans when a base ships them
  # Not wildmidi-libs, nor fluid-soundfont-lite-patches which it requires:
  # negativo17's gstreamer1-plugins-bad (custom-kernel's codec swap) links
  # libWildMidi and gtk4 requires that package (THE CASCADE above).
  python3-boto3 python3-botocore python3-s3transfer         # AWS SDK, orphans
  gnome-user-docs yelp yelp-libs yelp-xsl                   # GNOME help: Margine ships offline docs
  # Two packages the new base brings and no Margine ever shipped (Bluefin
  # excluded both): GNOME Software, because Bazaar is the store and GNOME
  # Software would check, stage and announce OS and firmware updates on
  # its own, outside uupd and margine-update; and Fedora's desktop
  # watermark extension, which Margine's enabled set never lists.
  gnome-software gnome-software-rpm-ostree
  gnome-shell-extension-background-logo
  # Developer stack on demand (see the header). The packages that require
  # these are listed too: dnf takes them anyway, and the guard below
  # accepts only what the list names.
  docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras
  bcc python3-bcc bpftrace bpftop clang21-libs llvm21-libs libomp21 compiler-rt21
  sysprof sysprof-cli libsysprof-capture igt-gpu-tools
  gcc gcc-c++ cpp gcc-plugin-annobin glibc-devel libstdc++-devel kernel-headers kernel-cachyos-devel systemtap-devel
  tailscale incus incus-agent rclone restic borgbackup
  code                                                      # VS Code RPM: the Flatpak is preinstalled, `ujust margine-vscode` layers the RPM
)

# What the x86 VMs keep: the x86 system emulator with its UEFI firmware,
# the image tools, the plugins every qemu-system build requires, and the
# three user-mode emulators containers-common pulls for multi-arch podman.
QEMU_KEEP='^(qemu-system-x86(-core)?|qemu-kvm(-core)?|qemu-img|qemu-common|qemu-tools|qemu-pr-helper|qemu-guest-agent|qemu-user-static-(aarch64|arm|x86)|edk2-ovmf|qemu-(ui|device|char|audio|block)-.*)$'

# What the trim must never take with it. Checked against what was there
# BEFORE the trim: a base that never had one of these (silverblue-main
# has no python3-rpm, the kernel step's akmods tooling brings and removes
# it) is not the trim's doing, and must not fail the build here.
KEEP_PKGS=(fuse python3-rpm python3-systemd NetworkManager-team
           qemu-kvm qemu-system-x86-core qemu-img qemu-common edk2-ovmf virtiofsd libvirt-daemon-driver-qemu
           podman podman-compose podman-machine distrobox rocm-opencl rocm-hip rocm-comgr rocm-runtime rocminfo
           # the desktop: what gtk4 took with it on 2026-10-11 (THE CASCADE)
           gtk4 libadwaita gstreamer1-plugins-bad gnome-shell gdm mutter gnome-session gnome-settings-daemon
           gnome-control-center nautilus ptyxis vte291-gtk4 gnome-system-monitor gnome-bluetooth
           xdg-desktop-portal-gnome xdg-desktop-portal-gtk ibus-gtk4)
KEEP_BEFORE=()
for p in "${KEEP_PKGS[@]}"; do
  rpm -q "$p" >/dev/null 2>&1 && KEEP_BEFORE+=("$p")
done

PRESENT=()
for p in "${TRIM_PKGS[@]}"; do
  rpm -q "$p" >/dev/null 2>&1 && PRESENT+=("$p")
done
# Everything qemu/edk2 that is not in the keep list (other architectures,
# the `qemu` and `qemu-user-static` meta packages, qemu-user).
while read -r p; do
  [[ -n "$p" ]] && PRESENT+=("$p")
done < <(rpm -qa --qf '%{NAME}\n' | grep -E '^(qemu|edk2)' | grep -v -E "$QEMU_KEEP" || true)
# The wine family, whatever is left of it, and every cockpit piece.
while read -r p; do
  [[ -n "$p" ]] && PRESENT+=("$p")
done < <(rpm -qa --qf '%{NAME}\n' | grep -E '^(wine|mingw|cockpit)' || true)

if (( ${#PRESENT[@]} == 0 )); then
  log "base ships none of the ${#TRIM_PKGS[@]} trim candidates, nothing to do"
else
  log "base ships ${#PRESENT[@]} packages Margine does not install, removing: ${PRESENT[*]}"
  rpm -qa --qf '%{NAME}\n' | sort -u > /tmp/base-trim.before
  dnf -y remove --setopt=clean_requirements_on_remove=False "${PRESENT[@]}"
  rpm -qa --qf '%{NAME}\n' | sort -u > /tmp/base-trim.after
  # dnf takes the packages that require what it removes. Everything it
  # took must be in the list: a dependent outside it means the list names
  # something the desktop stands on (THE CASCADE), and the build stops
  # here instead of shipping a smaller system that still looks consistent.
  mapfile -t taken < <(comm -23 /tmp/base-trim.before /tmp/base-trim.after)
  unlisted=()
  if (( ${#taken[@]} )); then
    mapfile -t unlisted < <(comm -23 <(printf '%s\n' "${taken[@]}") <(printf '%s\n' "${PRESENT[@]}" | sort -u))
  fi
  rm -f /tmp/base-trim.before /tmp/base-trim.after
  if (( ${#unlisted[@]} )); then
    err "dnf removed ${#unlisted[@]} packages the trim list does not name: ${unlisted[*]}"
    err "they require something the list names: find it with 'rpm -q --whatrequires <name>' on the base, then drop that entry or list its dependents on purpose"
    exit 1
  fi
  log "removed ${#taken[@]} packages, every one of them listed"
fi

# --- Prove it -------------------------------------------------------------
for p in "${TRIM_PKGS[@]}"; do
  if rpm -q "$p" >/dev/null 2>&1; then err "$p still present after base-trim"; exit 1; fi
done
if rpm -qa --qf '%{NAME}\n' | grep -E '^(qemu|edk2)' | grep -v -E "$QEMU_KEEP" | grep -q .; then
  err "qemu packages outside the keep list survived base-trim"; exit 1
fi
if rpm -qa --qf '%{NAME}\n' | grep -E '^(wine|mingw|cockpit)' | grep -q .; then
  err "the wine family or cockpit survived base-trim"; exit 1
fi
# Every installed package must still have what it requires: rpm-ostree
# re-solves the whole set on each layering, so one dangling requirement
# breaks every `rpm-ostree install` (the gaming layer first).
if ! unmet="$(dnf check --dependencies 2>&1)"; then
  err "unmet dependencies after base-trim:"; echo "$unmet" >&2; exit 1
fi
# What the trim must never take with it, among what the base had.
for p in "${KEEP_BEFORE[@]}"; do
  rpm -q "$p" >/dev/null 2>&1 || { err "$p is gone: the trim removed more than it should"; exit 1; }
done
log "base trim complete"
