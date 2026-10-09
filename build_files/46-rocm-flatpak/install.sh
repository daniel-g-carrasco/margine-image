#!/usr/bin/env bash
# Margine image build — section: 46-rocm-flatpak
# A library shim that lets Flatpak apps use the host's ROCm (OpenCL, HIP) on
# AMD GPUs, built here so it always matches this image's ROCm.
#
# Why (2026-10-09): darktable's Flatpak does its GPU work through OpenCL. The
# OpenCL in the Flatpak runtime is Mesa's rusticl, and Mesa 26.2 built with
# LLVM 22's upstream libclc can no longer build 7 of darktable's 42 kernels
# ("Internal compilation error: nir_shader not fully linked": pow, sin, cos,
# atan2, hypot and cbrt stay unresolved), so darktable silently falls back
# to the CPU. The host's ROCm OpenCL builds all of them and supports the
# Radeon 7040 iGPU (gfx1103) natively. Details and measurements:
# docs/notes/2026-10-09-darktable-gpu-rocm.md.
#
# Layout. In a sandbox with filesystems=host the host's /usr is /run/host/usr:
#   /usr/lib64/margine/rocm-flatpak/
#       relative symlinks to ONLY the ROCm family and libnuma, under every
#       name the host has for them (sonames included), plus an unversioned
#       libamdocl64.so. Never the whole host /usr/lib64: on an app's
#       LD_LIBRARY_PATH that shadows the runtime's own libraries and breaks
#       the GUI (docs/notes/2026-07-06-blender-rocm-hip-shim.md).
#   /usr/share/margine/rocm-flatpak/vendors/amdocl64.icd
#       an OpenCL ICD for OCL_ICD_VENDORS, naming that unversioned link.
# Relative links resolve the same on the host and under /run/host, and the
# names come from this image's libraries, so a ROCm bump in the base keeps
# the shim right with no change to the user's override, which points only at
# these fixed paths. Nothing on the host uses it.
# `ujust margine-darktable-opencl enable` points the darktable Flatpak here.
set -euo pipefail
. /ctx/00-common.sh

LIB=/usr/lib64
SHIM=$LIB/margine/rocm-flatpak
VENDORS=/usr/share/margine/rocm-flatpak/vendors
ICD=/etc/OpenCL/vendors/amdocl64.icd

if [[ ! -f "$ICD" ]]; then
  log "46-rocm-flatpak: no ROCm OpenCL ($ICD missing), shim not built"
  exit 0
fi
OCL="$(tr -d '[:space:]' < "$ICD")"   # e.g. libamdocl64.so.7.1
[[ -e "$LIB/$OCL" ]] || { err "46-rocm-flatpak: $ICD names $OCL, not found in $LIB"; exit 1; }

install -d "$SHIM" "$VENDORS"
shopt -s nullglob
for so in "$LIB"/lib{amdocl64,hsa-runtime64,amd_comgr,amdhip64,hsakmt,rocm_smi64,numa}.so*; do
  ln -sfn "../../$(basename "$so")" "$SHIM/$(basename "$so")"
done
ln -sfn "../../$OCL" "$SHIM/libamdocl64.so"
printf '%s\n' "/run/host$SHIM/libamdocl64.so" > "$VENDORS/amdocl64.icd"

# Every link must resolve, and the OpenCL library's ROCm dependencies must
# be in the shim (the rest, libdrm, libelf, zlib, libstdc++, come from the
# Flatpak runtime).
for link in "$SHIM"/*; do
  [[ -e "$link" ]] || { err "46-rocm-flatpak: dangling $link -> $(readlink "$link")"; exit 1; }
done
for dep in libhsa-runtime64.so.1 libnuma.so.1; do
  [[ -e "$SHIM/$dep" ]] || { err "46-rocm-flatpak: $dep missing from the shim"; exit 1; }
done
ls "$SHIM"/libamd_comgr.so.* >/dev/null 2>&1 || { err "46-rocm-flatpak: libamd_comgr missing (OpenCL builds kernels with it)"; exit 1; }
log "46-rocm-flatpak: $(ls "$SHIM" | wc -l) links in $SHIM, OpenCL $OCL"
