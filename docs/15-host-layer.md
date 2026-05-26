# Host Layer Baseline (legacy — Bluefin-style on stock Silverblue)

> **Status: superseded by [ADR 0005](adr/0005-base-on-bluefin-dx.md).**
>
> Margine's recommended deployment path is now **Bluefin DX rebase + 5
> Margine diffs**, applied via `scripts/apply-margine-on-bluefin`.
> Bluefin already ships the codec replacement, freeworld Mesa, virt
> stack, hardware diagnostics, fonts, GNOME tools, and dconf polish
> that this document was hand-rolling on top of stock Silverblue. We
> stopped maintaining a parallel baseline once the audit showed the
> Margine layer was ~70% a literal copy of Bluefin's image.
>
> This document is preserved for two reasons: (1) the analysis of why
> each Bluefin-style decision matters is the best onboarding material
> for understanding the desktop stack, and (2) someone who wants to
> stay on stock Silverblue can still run `apply-host-layer --apply`
> and get an equivalent result. The script and the
> `host_packages.baseline` section of the YAML are intact.
>
> For new installs, **follow [16-developer-toolbox.md](16-developer-toolbox.md)
> and ADR 0005, not this document**.

---

This document defines the **legacy host layer baseline** of Margine
Fedora Atomic: the set of packages that `scripts/apply-host-layer`
installs on the rpm-ostree deployment so the day-to-day experience
matches what a curated Atomic image like Bluefin already ships.

It was the answer to "I want codec, drivers, virt, hardware tools, and
developer tools ready out of the box, but I do not want to give up
Margine to become Bluefin." The audit in ADR 0005 showed that "not
giving up Margine to become Bluefin" was paying ~3-4 weeks of
maintenance for ~5 actual customisations. We pivoted to Bluefin DX as
base.

## Why this exists

Stock Fedora Silverblue is intentionally minimal. It ships only Fedora-pure
codec (`ffmpeg-free`, no proprietary), default Mesa with no patented codec
paths, no virtualization stack, no hardware diagnostics beyond the basics, no
`gnome-tweaks`. The expectation is that the user picks what they need.

Bluefin solves this by **baking** a richer baseline into an OCI image
(`ghcr.io/ublue-os/bluefin:latest`). Switching to that image gives you the
full set in one rebase.

Margine takes a different shape:

- the host stays **layered on top of stock Silverblue** through rpm-ostree;
- a single declarative model (`declarations/margine-atomic.yaml`) describes
  what the baseline should look like;
- one script (`scripts/apply-host-layer`) reads the declaration and stages a
  new deployment with everything in it.

The end-user effect is similar to Bluefin (codec works, drivers work, virt
works). The architecture is different: Margine remains a layered system and
keeps the option to move to a true image-based variant later (the `bootc`
roadmap is recorded in `declarations.base.image_workflow.future_candidates`).

## What goes into the baseline

All paths below are declared under `host_packages.baseline` in
`declarations/margine-atomic.yaml`. They are installed by
`scripts/apply-host-layer --apply` in a single rpm-ostree transaction (one
new deployment, one reboot).

### Codec replacement (RPMFusion)

Stock Fedora ships codec subsets that exclude patented formats (`ffmpeg-free`,
`mesa-va-drivers` without H.264/H.265 encode). The baseline replaces them
with the freeworld variants from RPMFusion:

| Stock package | Replaced by |
| --- | --- |
| `ffmpeg-free` | `ffmpeg` |
| `mesa-va-drivers` | `mesa-va-drivers-freeworld` |
| `mesa-vdpau-drivers` | `mesa-vdpau-drivers-freeworld` |

Plus added: `gstreamer1-plugins-bad-freeworld`, `gstreamer1-plugins-ugly`.

Two GStreamer symbols are intentionally **not** listed because on Fedora 44
they are virtual provides, which `rpm-ostree override` rejects:
`gstreamer1-libav` (real package is `gstreamer1-plugin-libav`, already in
the base) and `gstreamer1-vaapi` (merged into
`gstreamer1-plugins-bad-{free,freeworld}` in F44+). Both capabilities work
once `gstreamer1-plugins-bad-freeworld` is installed.

This is the same pattern Bluefin uses (`build_files/base/04-packages.sh`)
and unlocks: GPU-accelerated H.264/H.265/AV1 decode + encode in browsers,
OBS, darktable, Reaper export, etc.

### Media diagnostics + audio baseline

| Group | Packages |
| --- | --- |
| Diagnostics | `mesa-demos`, `mesa-libGLU`, `vulkan-tools`, `libva-utils`, `clinfo` |
| Audio | `pipewire-utils`, `pipewire-pulseaudio`, `pipewire-alsa`, `wireplumber`, `alsa-utils` |

Most audio packages are already present on Silverblue stock; including them
in the baseline guarantees the set is consistent and prevents surprises.

### Virtualization

| Packages |
| --- |
| `libvirt`, `libvirt-nss`, `qemu-kvm`, `virt-manager`, `virt-viewer`, `edk2-ovmf`, `swtpm`, `dnsmasq` |

Same set Bluefin DX installs. Enables `virt-manager` to launch VMs with UEFI
(`edk2-ovmf`) and virtual TPM 2.0 (`swtpm`) — the same hardware profile we
use to validate Margine itself in the VM lab.

### Hardware diagnostics

| Packages |
| --- |
| `lm_sensors`, `powertop`, `powerstat`, `fwupd`, `ddcutil`, `usbutils`, `pciutils`, `smartmontools` |

Sensor reading, battery profiling, firmware updates (Framework 13, etc.),
DDC/CI monitor control (brightness from terminal), disk SMART.

### GNOME tools

| Packages |
| --- |
| `gnome-tweaks`, `libappindicator-gtk3`, `gnome-shell-extension-appindicator`, `gnome-shell-extension-workspace-indicator`, `adw-gtk3-theme`, `showtime` |

`gnome-tweaks` for the settings GNOME core hides; AppIndicator for legacy
tray-icon apps (Bitwarden, Steam, etc. running in the background);
`adw-gtk3-theme` so GTK3 apps inherit the libadwaita look; `showtime` as
the GNOME-native video player ("Riproduttore video" / Videos), the
default since GNOME 48 (Loupe is the matching image viewer and is
already in the Silverblue base).

### Creative apps (host-layered, not Flatpak)

| Packages |
| --- |
| `darktable` |

`darktable` is intentionally layered on the host instead of installed as
a Flatpak. The Flatpak does not see the host OpenCL ICD by default, so
the GPU-accelerated raw processing path is off. The host install sees
ROCm (`rocm-opencl`) or `intel-compute-runtime` directly when those are
added via `optional_after_validation.{amd,intel}_gpu_extras`.

GIMP, Inkscape, OBS, Audacity, EasyEffects, Reaper, and the rest of the
creative tooling stay as Flatpak — they don't need host-level OpenCL.

### Fonts

Curated set: JetBrains Mono, IBM Plex (sans/mono/serif), Cascadia Code, Adobe
Source (code/sans/serif), Atkinson Hyperlegible Next/Mono, Carlito + Caladea
(MS Office compat), Liberation, Noto color emoji, Noto CJK.

Covers UI, code, document, multilingual, emoji, accessibility. Bluefin
installs a similar set plus Nerd Fonts from `copr che/nerd-fonts`; we keep
the Fedora-native set and let users add Nerd Fonts via `~/.local/share/fonts`
if they need terminal icons.

## What stays optional (not in apply-host-layer)

| Group | Why |
| --- | --- |
| Intel GPU extras (`intel-compute-runtime`, `intel-vpl-gpu-rt`) | Specific to Intel iGPU; AMD-only machines don't need them |
| AMD GPU extras (`rocm-opencl`, `rocminfo`, `radeontop`) | Heavy ROCm stack; install only when actually doing OpenCL/HIP work |
| Framework 13 EasyEffects layer | Hardware-gated by DMI |
| Gaming runtime helpers (`gamescope`, `mangohud`, `vkBasalt`, `gamemode`) | Phase 2 |
| Tailscale | Network mesh — install only when used |

These remain under `host_packages.optional_after_validation` and have to be
installed explicitly with `rpm-ostree install` when needed.

## What we explicitly do not take from Bluefin

| Bluefin choice | Margine choice | Reason |
| --- | --- | --- |
| Remove `gnome-software` and ship `bazaar` | Keep `gnome-software` | It's the standard surface on Silverblue; users discover Flatpak apps through it |
| `uupd` as update orchestrator | inherited — Margine now uses Bluefin's `uupd.timer` directly (see ADR 0004 amendment) |
| Custom signed kernel from `ublue-os/akmods` | Stock Fedora kernel (CachyOS lab option) | Different trust model; keeps the Fedora signing chain intact |
| Bluefin wallpapers, faces, custom GNOME schema overrides | None | Branding noise outside this project's scope |
| Cockpit (DX variant) | Not installed by default | Web admin not used here; can be added per-host |
| Docker CE from docker.com | Podman (already on Silverblue) + `podman-compose` in toolbox | Avoids the docker daemon, keeps containers rootless by default |
| VS Code from Microsoft repo | VSCodium via Flatpak | Preference for open-source build |

## Developer tooling (toolbox, not host)

Bluefin DX layers a long list of developer packages onto the host
(`gcc`, `make`, `podman-compose`, `flatpak-builder`, `qemu-system-x86`,
`bcc`, `bpftrace`, etc.).

Margine keeps this **out of the host** and puts it in the toolbox container.
Rationale: dev tools change fast and shouldn't require reboots to update.
The expanded toolbox set is in `toolbox.default.packages` (see
`declarations/margine-atomic.yaml`):

- **core_cli**: git + extras, ripgrep, fd, jq, bat, eza, btop, neovim,
  fastfetch, just, glow, gum
- **build_essentials**: gcc/g++, make, pkgconf, python3-pip, nodejs, npm
- **container_tooling**: podman-compose, podman-tui, distrobox
- **shells_optional**: fish, zsh

User-layer additions (no host, no container — directly under `~`):

- **Homebrew on Linux** at `~/.linuxbrew` — for tools that move faster than
  Fedora repos (starship, zellij, lazygit, etc.)
- **starship** as `~/.local/bin/starship` (or via brew)

## How to apply

```sh
# Recommended: validate every baseline package against a clean
# Fedora 44 + RPMFusion container before touching the host. Requires
# podman; runs on any distro. Catches naming drift early.
scripts/validate-baseline-packages

# Dry-run: see what will be installed
scripts/apply-host-layer

# Stage the new deployment
scripts/apply-host-layer --apply

# Reboot via GNOME menu (Power → Restart) to enter the new deployment

# After reboot: register the default MIME and URL scheme handlers
# (browser, mail, video, image, music, pdf, text editor, archive)
scripts/configure-default-applications              # dry-run
scripts/configure-default-applications --apply      # write ~/.config/mimeapps.list
```

`configure-default-applications` reads `gnome.default_applications` from
the YAML and writes the defaults via `xdg-mime` and `xdg-settings`. This
is what "GNOME Settings → Default Applications" shows. Without this step,
the top-row entries can end up wrong (e.g. Web=Firefox even though Zen
is installed, or Email=Zen because no mailer is explicitly registered
for the `mailto` scheme). The script makes the mapping deterministic.

The current mapping:

| Role | Application |
| --- | --- |
| Web browser | Zen Browser |
| Mail reader | Thunderbird |
| Calendar | GNOME Calendar |
| Music player | Gapless (g4music) |
| Video player | GNOME Showtime |
| Image viewer | GNOME Loupe |
| PDF viewer | GNOME Papers |
| Text editor | GNOME Text Editor |
| Archive manager | File Roller |

The script runs four sequential rpm-ostree transactions:

1. install RPMFusion release RPMs;
2. override-remove the stock codec packages and install the freeworld
   replacements;
3. install media diagnostics + audio + virtualization;
4. install hardware diagnostics + GNOME tools + fonts.

It reads the package lists directly from the YAML, so editing the
declaration is enough to change what is installed.

## Validation after reboot

```sh
rpm-ostree status
ffmpeg -version | head -1                    # should be RPMFusion ffmpeg
vainfo                                       # should report VAEntrypointEncSlice for H.264 / H.265
fc-list | grep -i 'jetbrains\|ibm plex' | head
virt-manager --version
lm_sensors --version
gnome-tweaks --version
```

If any of these fail, check `rpm-ostree status -v` for transaction errors
and `journalctl -b -p warning..alert` for boot-time complaints.

## Using the baseline

The baseline doesn't just put packages on disk — each group unlocks
something practical. This section is a usage cookbook grouped by area.

### Multimedia: full codec + hardware-accelerated video

After `apply-host-layer`, `ffmpeg` is the full RPMFusion build and
`mesa-va-drivers-freeworld` exposes the patented codec entrypoints.

Confirm the upgrade took:

```sh
ffmpeg -version | head -1            # expect "ffmpeg version N.N" without "free"
vainfo | grep -i 'h264\|hevc\|av1'   # expect VAEntrypointEncSlice / VLD entries
```

Hardware-accelerated video encode (AMD example, H.264):

```sh
ffmpeg -hwaccel vaapi -vaapi_device /dev/dri/renderD128 \
       -i input.mov \
       -vf 'format=nv12|vaapi,hwupload' \
       -c:v h264_vaapi -b:v 5M output.mp4
```

Hardware decode in browsers happens automatically once
`mesa-va-drivers-freeworld` is present (Firefox/Zen → check
`about:support` → "Compositing"; YouTube → playback stats → "Codecs").

OBS Studio: enable VA-API output via `Settings → Output → Encoder`
(pick `H.264 VA-API`). The encoder appears in the list because
`gstreamer1-plugins-bad-freeworld` (which now bundles the VA-API plugin
on F44+) and `mesa-va-drivers-freeworld` are present.

darktable / GIMP / Reaper: standard CPU codec paths work end-to-end
because `ffmpeg` and `gstreamer1-plugins-bad-freeworld` cover the
patented formats they need.

### Virtualization: virt-manager and friends

The host stack matches what we use to validate Margine itself in VMs.

First-time setup (one-time):

```sh
# Add yourself to the libvirt group so virsh / virt-manager work without sudo
sudo usermod -aG libvirt "$USER"
# Log out / log back in for group change to take effect

# Start the libvirtd socket
sudo systemctl enable --now libvirtd.socket

# Bring up the default NAT network if not already
sudo virsh net-autostart default
sudo virsh net-start default
```

Launch the GUI:

```sh
virt-manager
```

Create a VM with UEFI + virtual TPM 2.0 (same profile as the Margine
lab VM):

- New VM → Local install media → ISO path
- Choose memory / disk
- **Customize configuration before install** → Overview
  - Firmware: `UEFI x86_64: /usr/share/edk2/ovmf/OVMF_CODE.fd`
- Add Hardware → TPM
  - Type: `Emulated`, Model: `TIS`, Version: `2.0`
- Begin Installation

Useful `virsh` commands:

```sh
virsh list --all                              # list all domains
virsh start <name>                            # start a VM
virsh shutdown <name>                         # graceful shutdown
virsh destroy <name>                          # hard stop
virsh snapshot-create-as <name> snap1         # take snapshot
virsh snapshot-revert <name> snap1            # revert
virsh net-list                                # list networks
virsh net-dhcp-leases default                 # see VM IPs on default net
```

Storage pool under `~/data` (separate from default
`/var/lib/libvirt/images`):

```sh
sudo virsh pool-define-as data-vms dir --target /var/home/<user>/data/vms
sudo virsh pool-autostart data-vms
sudo virsh pool-start data-vms
```

### Hardware diagnostics

#### Sensors (temperature, fan, voltage)

```sh
sudo sensors-detect            # first time only; answer YES to safe probes
sensors                        # current readings
watch -n 1 sensors             # live monitor
```

#### Power profiling

```sh
sudo powertop                  # interactive TUI; Tab to navigate
sudo powerstat -d 5 -t 10      # 5s delay, 10 readings
```

`powertop` "Tunables" tab shows what's running at non-default power
levels; "Calibrate" mode (run once on a battery) refines estimates.

#### Firmware updates (Framework 13, laptops, NVMe firmware)

```sh
fwupdmgr refresh               # refresh metadata
fwupdmgr get-devices           # see what fwupd can update
fwupdmgr get-updates           # what's available
fwupdmgr update                # apply (reboot often required)
```

Framework 13: BIOS / EC firmware ship via LVFS, so this is the standard
update path. Same goes for NVMe firmware where the vendor publishes
through LVFS.

#### Monitor control via DDC/CI

```sh
ddcutil detect                                    # list DDC-capable monitors
ddcutil getvcp 10                                 # current brightness
ddcutil setvcp 10 50                              # set brightness to 50%
ddcutil setvcp 12 70                              # set contrast
ddcutil capabilities | less                       # what the monitor supports
```

VCP code 10 is brightness, 12 is contrast, 14 is color preset. Useful
on external monitors that don't expose hardware buttons or for
scripted brightness switching.

#### SMART drive health

```sh
sudo smartctl -a /dev/nvme0n1                     # full attribute dump
sudo smartctl -t short /dev/nvme0n1               # run short self-test
sudo smartctl -l selftest /dev/nvme0n1            # results
```

#### Hardware enumeration

```sh
lsusb -t                                          # USB tree
lspci -nnk                                        # PCI with kernel module
lscpu                                             # CPU details
lsblk -f                                          # block devices + filesystems
```

### GNOME Tweaks and AppIndicator

```sh
gnome-tweaks                  # launches the GUI
```

What you'll typically configure first:

- **Appearance** → Legacy Applications: pick `adw-gtk3-dark` so GTK3
  apps inherit the libadwaita dark look
- **Fonts** → Interface / Document / Monospace: pick from the curated
  font set (e.g. `IBM Plex Sans 10`, `JetBrains Mono 11`)
- **Keyboard & Mouse** → Additional Layout Options: compose key, caps
  remap, etc.
- **Top Bar**: enable Battery Percentage, Weekday, Date
- **Window Titlebars**: enable Maximize / Minimize buttons if the
  GNOME default of close-only is not your preference

AppIndicator support is provided by `gnome-shell-extension-appindicator`
+ `libappindicator-gtk3`. Legacy tray apps (Bitwarden, Steam in tray,
Slack desktop, etc.) appear in the top bar without extra setup. If a
new extension is needed, install `gnome-extensions-app` later from
Flatpak or use the Extensions Manager Flatpak (`com.mattjakeman.ExtensionManager`).

### Fonts: applying the curated set

The baseline installs Cascadia Code, IBM Plex (sans/mono/serif),
JetBrains Mono, Adobe Source (code/sans/serif), Atkinson Hyperlegible
Next/Mono, Carlito + Caladea (MS Office compatibility), Liberation
family, Noto color emoji, Noto CJK.

Pick them through `gnome-tweaks` → Fonts, or via `gsettings`:

```sh
gsettings set org.gnome.desktop.interface font-name           'IBM Plex Sans 10'
gsettings set org.gnome.desktop.interface document-font-name  'IBM Plex Serif 11'
gsettings set org.gnome.desktop.interface monospace-font-name 'JetBrains Mono 11'
```

Query what fontconfig actually resolves:

```sh
fc-match 'IBM Plex Sans'                          # what gets used as fallback
fc-list | grep -i 'jetbrains' | head              # which JetBrains weights are installed
pango-view --font='JetBrains Mono 12' --text='Mg 1l0 → ✓'    # render preview
```

For accessibility:

```sh
gsettings set org.gnome.desktop.interface font-name 'Atkinson Hyperlegible Next 11'
```

User-added fonts (Nerd Fonts, custom families) go under
`~/.local/share/fonts/margine/` and become visible after
`fc-cache -fv ~/.local/share/fonts`.

## Compatibility with creative apps: what's covered and what isn't

The "Bluefin-style" baseline covers the **general multimedia stack** (codec
replacement, Mesa freeworld for VA-API/VDPAU, GStreamer with patented
codecs). That's enough for browsers, OBS, generic video playback, and
simple ffmpeg pipelines. It is **not** automatically the right baseline
for every creative app.

### Inkscape — fully covered

Vector graphics. No codec, no GPU compute (beyond standard 2D rendering).
The Flatpak (`org.inkscape.Inkscape`, in `flatpaks.default_apps`) is the
correct delivery channel. The host layer adds nothing specific here.

### darktable — partially covered

darktable has three runtime dependencies; only one is in the baseline:

| Dependency | In baseline? | Why it matters |
| --- | --- | --- |
| Video codec for export (H.264/H.265) | ✅ `ffmpeg` + freeworld | Slideshow / video export to MP4 works |
| VA-API / VDPAU for preview pipeline | ✅ `mesa-va-drivers-freeworld` | Smooth preview of imported video clips |
| OpenCL runtime for GPU-accelerated processing | ❌ **not in baseline** | 5–20× faster raw → JPEG; tone mapping; denoise |

OpenCL packages are in `host_packages.optional_after_validation.amd_gpu_extras`
(`rocm-opencl`) and `intel_gpu_extras` (`intel-compute-runtime`,
`intel-opencl`). They are not in the baseline because they're heavy and
hardware-specific (installing the wrong one wastes ~1 GB of disk).

There is also a Flatpak-specific issue: **`org.darktable.Darktable` from
Flathub does not see the host OpenCL ICD by default**. The sandbox blocks
`/etc/OpenCL/vendors/*.icd`. Options:

- Install darktable via `rpm-ostree install darktable` (not Flatpak) — sees
  ROCm / Intel compute natively. Cost: one more layered package, one more
  reboot per upgrade.
- Keep darktable Flatpak and add a permission override:
  ```sh
  flatpak --user override --filesystem=/etc/OpenCL --device=dri org.darktable.Darktable
  ```
  Then re-launch. darktable's "darktable preferences → Processing → OpenCL"
  should now list a GPU device.
- Skip OpenCL: darktable falls back to CPU. Fine for occasional use,
  painful for batch raw work.

The decision belongs at the hardware-install stage, not at the generic
baseline level. Recommendation: when installing on the Framework 13 (AMD
Ryzen 7640), add `amd_gpu_extras` to the host layer manually:

```sh
sudo rpm-ostree install rocm-opencl rocminfo radeontop
```

### DaVinci Resolve — not covered, on purpose

Resolve is in `rejected_phase1.hardware_media` as `davinci-resolve-default`.
The reasons are not about preference, they are structural:

- BMD ships Resolve as a `.deb`/`.rpm` Linux installer (no Flatpak),
  designed for Rocky/Ubuntu; on Fedora atomic it needs heavy lifting
- It expects CUDA or AMD AMF for hardware encode — not VA-API
- The Free Edition cannot import H.264 / H.265 from `.mp4` / `.mov`
  containers (BMD's licensing). Resolve Studio (paid) does. Either way,
  it doesn't rely on the host codec layer the way generic players do
- It wants its own audio path (PipeWire bridge at 48 kHz, JACK-like
  routing)
- The Universal Blue community has Resolve work but only as a manual,
  break-prone integration

If you need Resolve eventually, the realistic options are (best to worst
in terms of cleanliness):

1. **Distrobox Ubuntu 22.04** — `distrobox create --image ubuntu:22.04
   --name resolve` then install the BMD `.deb` inside. GUI export to host.
   Resolve sees the GPU via render node passthrough. Host stays clean.
2. **rpm-ostree layer** of the BMD `.rpm` + dependency chain (libcrypto
   versions, librsvg, etc.). Doable, but the host gets a long tail of
   layered packages that need maintenance through every Fedora upgrade.
3. **Stick with Kdenlive / Reaper** — atomic-friendly, in the default
   Flatpak set, covers most non-color-grading video work.

The Margine baseline deliberately does not solve this so the project stays
predictable on update; Resolve remains a manual decision per machine.

### Quick reference

| App | Default channel | Host extras needed |
| --- | --- | --- |
| Inkscape | Flatpak | none |
| GIMP | Flatpak | none (uses host codec via Flatpak runtime) |
| darktable | Flatpak (default) or rpm-ostree (for OpenCL) | OpenCL stack per GPU vendor |
| Audacity | Flatpak | none |
| OBS Studio | Flatpak | VA-API plugin (already pulled in by codec replacement) |
| Reaper | Flatpak | none |
| Kdenlive (alternative video editor) | Flatpak | host codec replacement (already in baseline) |
| DaVinci Resolve | distrobox Ubuntu (recommended) | full BMD dependency chain — not in baseline |

## Relationship to phase 2 (bootc)

The host layer baseline is the **layered** path. The phase 2 roadmap
(`base.image_workflow.future_candidates`) points at `bootc` — moving the
same baseline into a Margine-published OCI image so installations rebase
to it instead of running `apply-host-layer`. The package set in this doc
becomes the recipe for that image.

Same content, different delivery. Layered for now, image-based later.
