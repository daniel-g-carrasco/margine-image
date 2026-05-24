# Host Layer Baseline (Bluefin-style)

This document defines the **host layer baseline** of Margine Fedora Atomic:
the set of packages that `scripts/apply-host-layer` installs on the rpm-ostree
deployment so the day-to-day experience matches what a curated Atomic image
like Bluefin already ships.

It is the answer to "I want codec, drivers, virt, hardware tools, and
developer tools ready out of the box, but I do not want to give up Margine to
become Bluefin."

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

Plus added: `gstreamer1-libav`, `gstreamer1-plugins-bad-freeworld`,
`gstreamer1-plugins-ugly`, `gstreamer1-vaapi`, `libavif`, `libheif`.

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
| `gnome-tweaks`, `libappindicator-gtk3`, `gnome-shell-extension-appindicator`, `adw-gtk3-theme` |

`gnome-tweaks` for the settings GNOME core hides; AppIndicator for legacy
tray-icon apps (Bitwarden, Steam, etc. running in the background);
`adw-gtk3-theme` so GTK3 apps inherit the libadwaita look.

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
| `uupd` as update orchestrator | `scripts/update-all` + Topgrade | ADR 0004 — rpm-ostree owns the OS boundary, Topgrade only orchestrates the accessory layer |
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
# Dry-run: see what will be installed
scripts/apply-host-layer

# Stage the new deployment
scripts/apply-host-layer --apply

# Reboot via GNOME menu (Power → Restart) to enter the new deployment
```

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

## Relationship to phase 2 (bootc)

The host layer baseline is the **layered** path. The phase 2 roadmap
(`base.image_workflow.future_candidates`) points at `bootc` — moving the
same baseline into a Margine-published OCI image so installations rebase
to it instead of running `apply-host-layer`. The package set in this doc
becomes the recipe for that image.

Same content, different delivery. Layered for now, image-based later.
