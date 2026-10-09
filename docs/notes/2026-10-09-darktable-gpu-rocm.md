# darktable on the GPU through ROCm, 2026-10-09

Why darktable lost its GPU, how `ujust margine-darktable-opencl` brings it back
through the host's ROCm, and why it sets 5% of RAM and advantage 4. Measured
on a Framework Laptop 13 (Ryzen 5 7640U, Radeon 760M gfx1103, 32 GB in one
DDR5-5600 module, BIOS 3.18), darktable 5.6.2 Flatpak, on Fujifilm X-T50
(X-Trans, 40 MP) and Olympus/OM System (Bayer, 20 MP) RAWs with real edits.

## What broke

darktable's Flatpak does its GPU work through OpenCL, and the OpenCL in the
Flatpak runtime is Mesa's rusticl. Mesa 26.2 (GL.default 26.08 and 25.08 are
both on 26.2.2) aborts compilation when a NIR shader is not fully linked, and
with LLVM 22's upstream libclc the OpenCL math builtins `pow`, `sin`, `cos`,
`atan2`, `hypot` and `cbrt` stay unresolved. So 7 of darktable's 42 kernel
files fail ("Internal compilation error: nir_shader not fully linked"), among
them `basic.cl`, and darktable drops the device and runs on the CPU without
saying so; after a few failures it also turns its `opencl` preference off.
Fedora 44's own Mesa 26.2.3 with libclc 22.1.8 fails the same way (tested in
a container). Mesa wants its patched libclc fork for LLVM 22; until the
runtimes ship it there is no rusticl to go back to, and the 26.08 branch never
had a Mesa 26.1 build to pin.

## The fix: the host's ROCm

Margine's host ships ROCm (`rocm-opencl` 7.1), which supports the 7040-series
iGPU (gfx1103) natively, builds all of darktable's kernels, and logged no
amdgpu fault in any of the runs below. The Flatpak has `filesystems=host`, so
the host's `/usr` is at `/run/host/usr` inside it:

- `build_files/46-rocm-flatpak` builds `/usr/lib64/margine/rocm-flatpak/`,
  relative symlinks to only the ROCm family and libnuma (never the whole
  `/usr/lib64`, see the [Blender note](2026-07-06-blender-rocm-hip-shim.md)),
  and an OpenCL ICD in `/usr/share/margine/rocm-flatpak/vendors/` naming an
  unversioned `libamdocl64.so`. Built from the image's own libraries, so a
  ROCm bump keeps it right.
- `ujust margine-darktable-opencl` points the Flatpak at it
  (`LD_LIBRARY_PATH`, `OCL_ICD_VENDORS`), turns OpenCL and darktable's AMD
  platform on (`clplatform_amdacceleratedparallelprocessing` ships off), and
  tunes the device line.

Two traps on the way: the Flatpak has a private `/tmp`, so a throwaway
darktable profile for a test must live under the home; and a fresh profile has
the AMD platform disabled, so a test on it reports no device.

## Why 5% and advantage 4

On this iGPU the X-Trans demosaic (Markesteijn 3-pass) is several times slower
than on the CPU (5.3 s against 1.3 s): it moves a lot of data and little
arithmetic, and the GPU shares one memory channel with the CPU without its
large caches. The compute-heavy modules (diffuse or sharpen, color equalizer,
color balance rgb) are much faster on the GPU. darktable has no per-module
device choice, but it sends to the CPU a module that does not fit in the GPU's
memory share and cannot be tiled, which is the case of the demosaic: with
`unified_fraction` 0.05 (1.5 GB of 31 GB) the demosaic runs on the CPU and
the rest on the GPU. `advantage` 4 sends to the CPU the modules that would
otherwise be split into slow GPU tiles in full-size exports. 0.05 is also the
lowest share darktable accepts.

Pipeline medians (s), mains power, performance profile, BIOS iGPU memory Auto:

| photo | test | CPU only | GPU 40% | GPU 5% + advantage 4 |
|---|---|---|---|---|
| X-T50, light edit | open (2560 px) | 2.02 | 5.08 | **1.75** |
| | export | 7.63 | 7.45 | **5.97** |
| X-T50, heavy edit | open | 5.49 | 5.34 | **3.30** |
| | export | 48.4 | **26.3** | 29.9 |
| OM-1 II | open | 0.58 | **0.44** | 0.51 |
| | export | 2.15 | **1.28** | 1.93 |
| E-M1 II | export | 11.2 | **6.6** | 6.8 |

5% + advantage 4 is the only setting never slower than the CPU alone. With
Bayer cameras only, 40% without advantage is the better choice.

Also measured: on battery the GPU loses much of its lead; `micro_nap` makes no
difference; a larger share (`UMA_GAME_OPTIMIZED`, 4 GB reserved in the BIOS)
does not help and costs 4 GB of RAM, since ROCm on these APUs allocates from
system memory anyway (AMD recommends a small reservation, 0.5 GB).

## Measuring on your own photos

`ujust margine-darktable-bench [quick|full] [RAW...]` repeats this on your
photos (by default the most edited one per RAW format in Pictures/raw). It
waits for a quiet, cool machine before every run, measures the CPU and GPU
time used by other programs during it (from `/proc`, GPU engine time from
amdgpu's per-client fdinfo) and repeats disturbed runs, runs a suspend
interrupted, or runs with a kernel GPU fault; it blocks sleep and lid suspend
while it runs and never writes to the user's darktable profile.
