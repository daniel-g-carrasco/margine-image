# Blender GPU (HIP) on AMD via a host-ROCm shim, 2026-07-06

How `ujust margine-blender-gpu` (build_files/60-custom.just) makes Cycles
render on an AMD GPU inside the `org.blender.Blender` Flatpak, and the two
non-obvious traps that shaped the final mechanism. Verified end to end on a
Radeon 760M (gfx1103, integrated RDNA3).

## The situation

- The Blender Flatpak ships **no** ROCm/HIP runtime: `HIPEW initialization
  failed: Error opening HIP dynamic library`. Cycles then finds no GPU and
  silently falls back to CPU (a render still "completes", which is how a
  blind recipe would look like it worked while doing nothing).
- Margine's host **does** ship ROCm (Bluefin DX brings `libamdhip64.so.7`,
  ROCm 7.x) and the Blender Flatpak already has `filesystems=host`.

So the fix is to put the host's ROCm libraries on Blender's library path.
The details are where it gets sharp.

## Trap 1: do NOT expose all of host `/usr/lib64`

The first version set `LD_LIBRARY_PATH=…:/run/host/usr/lib64`. HIP loads and
renders, but the whole host lib dir on the path **shadows the runtime's own
libraries** (ALSA, GL) with host versions. Result: the GUI would not open,
logging `Cannot open shared library … /run/host/usr/lib64/alsa-lib/…`.
`LD_LIBRARY_PATH` is searched before the runtime's default libs, so *any*
lib present in both gets the host copy, even with the host dir listed last.

Fix: symlink **only** the ROCm family into a dedicated shim dir and put just
that on the path. The set that resolves all of `libamdhip64`'s deps on
Margine: `libamdhip64`, `libhsa-runtime64`, `libamd_comgr`, `librocm_smi64`,
and `libnuma` (the one general dep the Flatpak lacks). Nothing the GUI needs
is on the path, so it launches clean.

## Trap 2: `filesystems=host` maps two different roots

- The host's **`/usr`** appears in the sandbox at **`/run/host/usr`** (this
  is where the ROCm libs are, so symlink targets point there).
- The host **home** appears at its **real path** (`/var/home/<user>/…`),
  **not** under `/run/host`. The shim dir lives in the home, so it must be
  referenced at the real path. Referencing it as `/run/host/$HOME/…` gives a
  dir that looks present but whose entries don't resolve, and HIP stays
  broken in a confusing way.

So: shim dir at `~/.local/share/margine/blender-rocm` (real path on
`LD_LIBRARY_PATH`); its symlinks target `/run/host/usr/lib64/<lib>`.

## Trap 3: no `HSA_OVERRIDE_GFX_VERSION` for gfx1103

`HSA_OVERRIDE_GFX_VERSION=11.0.0` (the usual "treat this APU as gfx1100"
trick) makes the render abort with `HSA_STATUS_ERROR_INVALID_ISA`: the
kernel is built for gfx1100 but the silicon is gfx1103. ROCm 7.x supports
gfx1103 **natively**, so the recipe uses **no override**.

## Why a shim and not a policy/rebuild

No writable path inside the read-only Flatpak; rebuilding the Flatpak with
ROCm is heavy and would need re-doing on every upstream bump. The shim is
per-user, reverts cleanly (`disable` removes the dir + the override), and
rides whatever ROCm the host currently has. The `margine-darktable-opencl`
recipe (Mesa rusticl) is the sibling pattern for the same "GPU compute in a
Flatpak" problem.
