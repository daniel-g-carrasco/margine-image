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

Plus added: `gstreamer1-plugins-bad-freeworld`, `gstreamer1-plugins-ugly`,
`gstreamer1-vaapi`, `libavif`, `libheif`. (`gstreamer1-libav` is not added
explicitly — the real Fedora 44 package is `gstreamer1-plugin-libav` and is
already in the base; `gstreamer1-libav` is just a virtual provides that
`rpm-ostree override` rejects.)

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
`gstreamer1-vaapi` and `mesa-va-drivers-freeworld` are present.

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

## Relationship to phase 2 (bootc)

The host layer baseline is the **layered** path. The phase 2 roadmap
(`base.image_workflow.future_candidates`) points at `bootc` — moving the
same baseline into a Margine-published OCI image so installations rebase
to it instead of running `apply-host-layer`. The package set in this doc
becomes the recipe for that image.

Same content, different delivery. Layered for now, image-based later.
