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
#     rocm-device-libs, hipcc and the rocm -devel packages): see below.
set -euo pipefail
. /ctx/00-common.sh
log() { printf '[base-trim] %s\n' "$*"; }
err() { printf '[base-trim] ERROR: %s\n' "$*" >&2; }

TRIM_PKGS=(
  anaconda-core anaconda-live anaconda-tui anaconda-webui  # the installer
  livesys-scripts dracut-live isomd5sum                     # live-boot plumbing
  cockpit-ws                                                # Anaconda WebUI transport
  qt6-qtwebengine                                           # 277 MiB, required by nothing
  firefox mozilla-openh264                                  # spec: no system Firefox RPM
  fluid-soundfont-gm fluid-soundfont-gs fluid-soundfont-lite-patches wildmidi-libs  # MIDI soundfonts, orphans
  python3-boto3 python3-botocore python3-s3transfer         # AWS SDK, orphans
  gnome-user-docs yelp yelp-libs yelp-xsl                   # GNOME help: Margine ships offline docs
  # Developer stack on demand (see the header): dnf also takes the
  # packages that require these, e.g. docker-ce-rootless-extras,
  # gcc-plugin-annobin, python3-bcc, systemtap-devel.
  docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  bcc bpftrace bpftop clang21-libs llvm21-libs libomp21 compiler-rt21
  sysprof sysprof-cli libsysprof-capture igt-gpu-tools
  gcc gcc-c++ cpp glibc-devel libstdc++-devel kernel-headers kernel-cachyos-devel
  tailscale incus incus-agent rclone restic borgbackup
)

# What the x86 VMs keep: the x86 system emulator with its UEFI firmware,
# the image tools, the plugins every qemu-system build requires, and the
# three user-mode emulators containers-common pulls for multi-arch podman.
QEMU_KEEP='^(qemu-system-x86(-core)?|qemu-kvm(-core)?|qemu-img|qemu-common|qemu-tools|qemu-pr-helper|qemu-guest-agent|qemu-user-static-(aarch64|arm|x86)|edk2-ovmf|qemu-(ui|device|char|audio|block)-.*)$'

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
  dnf -y remove --setopt=clean_requirements_on_remove=False "${PRESENT[@]}"
fi

# --- ROCm: keep OpenCL and the HIP runtime, drop the HIP compiler -----------
# rocm-hip requires hipcc, and rocm-device-libs requires rocm-llvm-static
# (1963 MB), by packaging, not at run time: with all of them gone,
# rocm-opencl still builds every one of darktable's 42 kernels and
# libamdhip64 and libamdocl64 resolve (tested in a fedora:44 container,
# 2026-10-10). dnf would cascade the removal up to rocm-hip, so these go
# through rpm alone. That leaves rocm-hip requiring a name nothing
# provides, and rpm-ostree re-solves every installed package when it
# layers: the first image built this way failed the smoke test's
# gaming-native dry run (2026-10-10). So a package of Margine's own,
# margine-rocm-hip-runtime, provides the name `hipcc` and nothing else,
# and the prove-it below asks dnf for every unmet dependency.
ROCM_DEV=(hipcc rocm-device-libs rocm-llvm-static rocm-clang rocm-llvm rocm-lld
          rocm-clang-devel rocm-llvm-devel rocm-libc++-devel rocm-clang-runtime-devel rocm-runtime-devel)
ROCM_PRESENT=()
for p in "${ROCM_DEV[@]}"; do
  rpm -q "$p" >/dev/null 2>&1 && ROCM_PRESENT+=("$p")
done
if (( ${#ROCM_PRESENT[@]} )); then
  log "removing the HIP compiler and ROCm development packages: ${ROCM_PRESENT[*]}"
  rpm -e --nodeps "${ROCM_PRESENT[@]}"
fi
if rpm -q rocm-hip >/dev/null 2>&1 && ! rpm -q hipcc >/dev/null 2>&1; then
  # rpm-build is not in the image (custom-kernel removes it with the other
  # build-only packages): borrow it for one rpmbuild and take back exactly
  # what the borrowing added.
  before="$(rpm -qa --qf '%{NAME}\n' | sort)"
  dnf -y install --setopt=install_weak_deps=False rpm-build
  mapfile -t borrowed < <(comm -13 <(echo "$before") <(rpm -qa --qf '%{NAME}\n' | sort))
  stub=/run/margine-rocm-hip-runtime
  mkdir -p "$stub"
  cat > "$stub/margine-rocm-hip-runtime.spec" <<'SPEC'
Name:           margine-rocm-hip-runtime
Version:        1
Release:        1
Summary:        The ROCm HIP runtime without the HIP compiler
License:        MIT
BuildArch:      noarch
# rocm-hip requires hipcc by name; the compiler and its 2 GB of LLVM are
# not in the Margine image (build_files/12-base-trim/install.sh). This
# package satisfies the name so the rpm database stays consistent and
# rpm-ostree can layer packages. It compiles nothing: `rpm-ostree install
# hipcc` brings the real compiler, next to this package.
Provides:       hipcc

%description
Satisfies rocm-hip's packaging requirement on hipcc in an image that
ships the HIP runtime (for Blender) but not the HIP compiler.

%files

%changelog
* Fri Oct 10 2026 Margine - 1-1
- rocm-hip without hipcc: the requirement, not the compiler
SPEC
  rpmbuild --quiet --define "_topdir $stub/top" -bb "$stub/margine-rocm-hip-runtime.spec"
  rpm -i "$stub"/top/RPMS/noarch/margine-rocm-hip-runtime-*.noarch.rpm
  rm -rf "$stub"
  if (( ${#borrowed[@]} )); then
    dnf -y remove --setopt=clean_requirements_on_remove=False "${borrowed[@]}"
  fi
  log "margine-rocm-hip-runtime provides hipcc: rocm-hip's requirement is met without the compiler"
fi

# --- Prove it -------------------------------------------------------------
for p in "${TRIM_PKGS[@]}" "${ROCM_DEV[@]}"; do
  if rpm -q "$p" >/dev/null 2>&1; then err "$p still present after base-trim"; exit 1; fi
done
if rpm -qa --qf '%{NAME}\n' | grep -E '^(qemu|edk2)' | grep -v -E "$QEMU_KEEP" | grep -q .; then
  err "qemu packages outside the keep list survived base-trim"; exit 1
fi
if rpm -qa --qf '%{NAME}\n' | grep -E '^(wine|mingw|cockpit)' | grep -q .; then
  err "the wine family or cockpit survived base-trim"; exit 1
fi
for lib in /usr/lib64/libamdhip64.so.* /usr/lib64/libamdocl64.so.*; do
  [[ -e "$lib" ]] || continue
  if ldd "$lib" | grep -q 'not found'; then err "$lib no longer resolves after the ROCm trim"; exit 1; fi
done
# Every installed package must still have what it requires: rpm-ostree
# re-solves the whole set on each layering, so one dangling requirement
# breaks every `rpm-ostree install` (the gaming layer first).
if ! unmet="$(dnf check --dependencies 2>&1)"; then
  err "unmet dependencies after base-trim:"; echo "$unmet" >&2; exit 1
fi
# What the trim must never take with it (present in today's image).
for p in fuse python3-rpm python3-systemd NetworkManager-team \
         qemu-kvm qemu-system-x86-core qemu-img qemu-common edk2-ovmf virtiofsd libvirt-daemon-driver-qemu \
         podman podman-compose podman-machine distrobox rocm-opencl rocm-hip rocm-comgr rocm-runtime rocminfo; do
  rpm -q "$p" >/dev/null 2>&1 || { err "$p is gone: the trim removed more than it should"; exit 1; }
done
log "base trim complete"
