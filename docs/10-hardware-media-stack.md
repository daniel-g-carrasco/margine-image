# Hardware and Media Stack

This document defines how Margine Fedora Atomic should handle drivers, audio,
video, media acceleration, and GPU compute.

The rule is simple: keep the Fedora Atomic base honest. Do not port the
Arch/CachyOS package manifests one-to-one. Carry over the validated intent from
Margine Personal, then remap it through Fedora, rpm-ostree, Flatpak, and GNOME.

## Scope

Phase 1 includes:

- stock Fedora Silverblue GNOME as the desktop owner;
- open Intel and AMD graphics paths;
- Mesa OpenGL, EGL, Vulkan, VA-API, and OpenCL/Rusticl validation;
- Intel media and compute runtime validation;
- AMD Mesa, ROCm OpenCL, and Rusticl validation;
- PipeWire, PipeWire Pulse compatibility, and WirePlumber validation;
- Framework 13 speaker processing as a later hardware-gated EasyEffects layer;
- codec and creative-app handling through channel-specific policy.

Phase 1 does not include:

- proprietary NVIDIA as a default;
- out-of-tree driver stacks as a baseline;
- Resolve as a supported default;
- hidden gaming kernel policy;
- CachyOS gaming metapackages;
- AUR packages or Arch package names.

## What Carries Over From Margine Personal

The old Margine Personal design is useful because it separates concerns:

| Old area | Carry over | Fedora Atomic change |
| --- | --- | --- |
| Mesa fallback layer | Yes | Use Fedora Mesa packages and validate what Silverblue already contains |
| Intel graphics layer | Yes | Map to Fedora Intel media, compute, and diagnostic packages |
| AMD graphics layer | Yes | Map to Fedora Mesa, ROCm, Rusticl, and diagnostic packages |
| PipeWire/WirePlumber validation | Yes | Keep as GNOME user-session validation |
| Framework 13 EasyEffects preset | Yes, later | Rebuild as a Fedora/GNOME user layer with DMI and sink detection |
| Photo/audio/video app list | Partly | Prefer Flatpak for GUI apps, host packages only for drivers/services |
| Gaming runtime | Optional later | Use Flatpak first; keep kernel sysctl policy separate |
| Resolve notes | Yes | Keep as a future vendor-aware exception, not baseline support |

The important lesson is not the old package list. The important lesson is that
desktop graphics, media acceleration, audio routing, GPU compute, and commercial
media compatibility are different layers and must be validated separately.

## Channel Policy

| Channel | Use for this stack |
| --- | --- |
| Fedora Silverblue base | GNOME session, Mesa baseline, PipeWire baseline, core drivers |
| rpm-ostree layering | Missing host drivers, media runtimes, diagnostics, firmware-adjacent tools |
| Flatpak | GUI applications such as darktable, GIMP, Audacity, OBS, EasyEffects, Reaper, Steam |
| toolbox/distrobox | Development tools, codec experiments, SDKs, packaging tests |
| Manual exception | Resolve, NVIDIA, RPM Fusion codec replacement, vendor runtimes |

Do not layer GUI applications just because they existed as Arch packages.
Conversely, do not expect Flatpak to provide host kernel drivers, VA-API
drivers, Vulkan ICDs, or OpenCL ICDs. Those must be present on the host and
visible to applications.

## Fedora Package Mapping

These are Fedora 44 package candidates checked against Fedora repositories. They
are candidates for lab validation, not a mandate to layer everything.

| Margine Personal package | Fedora direction |
| --- | --- |
| `mesa` | Fedora base; inspect before layering `mesa-dri-drivers` |
| `mesa-utils` | `mesa-demos` |
| `vulkan-intel`, `vulkan-radeon`, `vulkan-nouveau` | `mesa-vulkan-drivers` |
| `vulkan-tools` | `vulkan-tools` |
| `vulkan-mesa-layers` | `vulkan-validation-layers` only if needed for diagnostics |
| `libva-utils` | `libva-utils` |
| `intel-media-driver` | `libva-intel-media-driver` |
| `libva-intel-driver` | no default; legacy Intel path only if old hardware proves it needs it |
| `intel-compute-runtime` | `intel-compute-runtime` plus `intel-opencl` as provided by Fedora |
| `intel-gpu-tools` | `igt-gpu-tools` |
| `vpl-gpu-rt` | `intel-vpl-gpu-rt`, `libvpl`, and `libvpl-tools` if VPL is needed |
| `rocm-opencl-runtime` | `rocm-opencl` |
| `rocminfo` | `rocminfo` |
| `radeontop` | `radeontop` |
| `clinfo` | `clinfo` |
| `opencl-icd-loader` | `OpenCL-ICD-Loader` |
| Rusticl path | `mesa-libOpenCL`, validated with `clinfo` and app tests |

For codecs and GStreamer:

| Intent | Fedora candidate |
| --- | --- |
| FFmpeg baseline from Fedora repos | `ffmpeg-free` |
| GStreamer libav bridge | `gstreamer1-plugin-libav` |
| OpenH264 plugin | `gstreamer1-plugin-openh264` |
| GStreamer base/good/bad free plugins | `gstreamer1-plugins-base`, `gstreamer1-plugins-good`, `gstreamer1-plugins-bad-free` |
| GStreamer ugly free plugins | `gstreamer1-plugins-ugly-free` |
| VA-API GStreamer path | `gstreamer1-vaapi` |
| AV1/HEIF support | `aom`, `dav1d`, `libavif`, `libheif` |

**Policy update (Bluefin-style baseline).** Full patent-encumbered multimedia
support is now part of the Margine host layer baseline. RPM Fusion (free +
nonfree) is enabled by `scripts/apply-host-layer`, and the stock Fedora
codec packages are replaced with the freeworld variants:

| Stock | Replaced by |
| --- | --- |
| `ffmpeg-free` | `ffmpeg` |
| `mesa-va-drivers` | `mesa-va-drivers-freeworld` |
| `mesa-vdpau-drivers` | `mesa-vdpau-drivers-freeworld` |

Plus added: `gstreamer1-plugins-bad-freeworld`, `gstreamer1-plugins-ugly`,
`gstreamer1-vaapi`, `libavif`, `libheif`. (`gstreamer1-libav` is intentionally
not added — `gstreamer1-plugin-libav` already provides the same capability
from the Fedora base.)

The replacement is the same pattern Bluefin/Bazzite use and is required for
GPU-accelerated H.264 / H.265 / AV1 in browsers, OBS, darktable, Reaper, etc.

The full rationale, including what we do not adopt from Bluefin, lives in
[15-host-layer.md](15-host-layer.md).

## Intel Path

Intel validation has four separate questions:

- which kernel driver is bound: `i915` or `xe`;
- whether Mesa exposes OpenGL/EGL and Vulkan;
- whether VA-API uses the expected Intel media driver;
- whether OpenCL is exposed through Intel compute runtime or Rusticl.

Initial host candidates:

```text
libva-intel-media-driver
intel-compute-runtime
intel-opencl
igt-gpu-tools
mesa-demos
mesa-vulkan-drivers
vulkan-tools
libva-utils
clinfo
```

Do not force old `libva-intel-driver` unless the real hardware is old enough to
require the legacy driver.

## AMD Path

AMD validation also has separate layers:

- kernel driver: `amdgpu`;
- Mesa OpenGL/EGL;
- Mesa Vulkan through RADV;
- VA-API through Mesa VA drivers;
- OpenCL through Rusticl and/or ROCm OpenCL;
- application-specific compute exposure.

Initial host candidates:

```text
mesa-demos
mesa-vulkan-drivers
mesa-va-drivers
mesa-libOpenCL
vulkan-tools
libva-utils
clinfo
rocminfo
rocm-opencl
radeontop
```

ROCm is not a universal "AMD works" switch. It must be validated on the exact GPU
and workload. Rusticl is attractive because it is in Mesa, but Mesa documents it
as an OpenCL implementation over Gallium drivers and notes that device exposure
can be controlled by driver and runtime policy. Therefore `mesa-libOpenCL`
presence is not enough; `clinfo` and application tests decide whether it works.

## Audio Stack

Fedora GNOME should start from PipeWire and WirePlumber.

Validate first:

```sh
systemctl --user status pipewire.service pipewire-pulse.service wireplumber.service --no-pager
pactl info
wpctl status
```

Host candidates only if missing:

```text
pipewire-utils
pipewire-pulseaudio
pipewire-alsa
wireplumber
alsa-utils
```

EasyEffects is not a generic host requirement. It is useful for the Framework 13
speaker preset, but that layer must keep the Margine Personal guardrails:

- version the preset and IR assets;
- apply only on detected Framework Laptop 13 hardware;
- resolve the real PipeWire sink at runtime;
- target internal speakers only;
- do not require legacy `audio` group membership;
- no global preset for headphones, HDMI, or unrelated machines.

Whether EasyEffects is installed as Flatpak or RPM must be validated before the
Framework preset provisioner is ported, because the preset path, service mode,
and PipeWire access model differ by channel.

## Video and Codec Stack

The baseline goal is hardware acceleration visibility, not "every codec works
everywhere".

Validate:

```sh
ffmpeg -hide_banner -hwaccels
gst-inspect-1.0 va
vainfo
```

Fedora free codecs are the acceptable *fallback*; the Bluefin-style codec
replacement (`scripts/apply-host-layer`) is the *default*. The trade-off is
deliberate: adding RPM Fusion couples upgrades to a third-party repository,
but it is the same trade-off Bluefin/Bazzite ship and is what makes
GPU-accelerated video playback in browsers and editors work out of the box.
See [15-host-layer.md](15-host-layer.md) for the full rationale and
[09-declarative-model.md](09-declarative-model.md) for the underlying
declarative model. Flatpak applications from Flathub may carry their own
runtime codec support, but host VA-API and Vulkan still need to be visible
from the host.

## GPU Compute

OpenCL must be treated as a runtime surface, not as a package checkbox.

Validate:

```sh
clinfo
rocminfo
darktable-cltest
```

Pass criteria depend on the target:

- darktable needs an OpenCL device it can actually enable;
- Resolve needs a vendor-compatible compute stack and runtime libraries;
- general diagnostics need only prove platform and device exposure.

Do not claim Resolve support from `glxinfo`, `vulkaninfo`, `vainfo`, or
successful desktop rendering. Resolve needs a separate vendor-aware validation
path.

## NVIDIA Position

NVIDIA is not a default.

Reasons:

- proprietary or out-of-tree modules interact badly with Secure Boot if signing
  is not designed;
- akmods and kernel replacement increase rpm-ostree update risk;
- the CachyOS kernel experiment already changes the most sensitive host layer;
- GNOME/Silverblue baseline quality must be known before adding NVIDIA.

Future NVIDIA support must be its own layer with Secure Boot, akmods, rollback,
and driver update validation.

## Gaming Policy

Gaming is part of the target profile after the hardware/media layer is
validated.

This document owns the driver and media prerequisites. `docs/11-gaming-runtime.md`
owns the launchers, Gamescope, MangoHud, vkBasalt, GameMode, and Steam Gaming
Mode plan.

Flatpaks are the first channel for the desktop runtime:

```text
com.valvesoftware.Steam
net.lutris.Lutris
com.heroicgameslauncher.hgl
com.usebottles.bottles
com.github.Matoking.protontricks
net.davidotek.pupgui2
```

Kernel policy remains separate. In particular, `kernel.split_lock_mitigate=0`
must never be enabled implicitly by installing a gaming bundle. If a future
gaming layer needs that tradeoff, it gets a visible opt-in validator and
rollback path.

## Validation Commands

Run these after any host graphics, media, audio, kernel, or codec change:

```sh
lspci -k | sed -n '/VGA compatible controller/,+6p;/3D controller/,+6p;/Display controller/,+6p;/Audio device/,+6p'
lsmod | grep -E 'amdgpu|i915|xe|nvidia|nouveau|virtio_gpu|snd|snd_hda|snd_sof|kvm' || true
systemctl --user status pipewire.service pipewire-pulse.service wireplumber.service --no-pager
pactl info
wpctl status
ffmpeg -hide_banner -hwaccels
gst-inspect-1.0 va
glxinfo -B 2>/dev/null || true
eglinfo -B 2>/dev/null || true
vulkaninfo --summary 2>/dev/null || true
vainfo 2>/dev/null | sed -n '1,120p'
clinfo 2>/dev/null | sed -n '1,160p'
rocminfo 2>/dev/null | sed -n '1,160p'
darktable-cltest 2>/dev/null | sed -n '1,160p'
journalctl -b --no-pager | grep -Ei 'drm|gpu|amdgpu|i915|xe|virtio_gpu|pipewire|wireplumber|snd_hda|snd_sof' || true
```

Repository helper:

```sh
scripts/validate-hardware-media-stack
```

## References

- Mesa Rusticl documentation: https://docs.mesa3d.org/rusticl.html
- Fedora `mesa-libOpenCL`: https://packages.fedoraproject.org/pkgs/mesa/mesa-libOpenCL/index.html
- Fedora `libva-intel-media-driver`: https://packages.fedoraproject.org/pkgs/intel-media-driver-free/libva-intel-media-driver/
- Fedora `intel-compute-runtime`: https://packages.fedoraproject.org/pkgs/intel-compute-runtime/intel-compute-runtime/fedora-44.html
- Fedora `rocminfo`: https://packages.fedoraproject.org/pkgs/rocminfo/rocminfo/index.html
- Fedora `pipewire`: https://packages.fedoraproject.org/pkgs/pipewire/pipewire/
- Fedora `wireplumber`: https://packages.fedoraproject.org/pkgs/wireplumber/wireplumber/
