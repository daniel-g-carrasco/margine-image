# Validation

Validation records the real system state. If the VM differs from the expected
model, update the documentation instead of hiding the difference.

> **The validators are the single source of truth (2026-06-12).** The image
> ships **seven** `margine-validate-*` programs — `margine-system`,
> `declared-state`, `atomic-layout`, `cachyos-kernel`, `branding`,
> `hardware-media-stack`, `gaming-runtime` (plus `validate-staged-deployment`
> and `collect-diagnostics` as dev-side tools). They are listed in
> `declarations/margine-atomic.yaml` `updates.validators_on_demand` and run
> three ways from the same code: `ujust margine-doctor` on a booted system,
> the Layer C GUI probe inside the smoke-boot VM, and **in the build container
> in CI** via `MARGINE_VALIDATE_CONTEXT=image` (`podman run $IMG
> margine-validate-…`) — which replaces the old duplicated grep sentinels.
> `MARGINE_VALIDATE_CONTEXT` values: `install` (default, booted-from-ISO),
> `smoke-boot`/`qcow2` (VM, no Anaconda %post), `image` (build container —
> filesystem checks only, runtime checks skipped). The commands below remain
> valid for manual on-host inspection.

## Minimum Commands

Run these during baseline and after the kernel experiment:

```sh
rpm-ostree status
findmnt /
findmnt /var
findmnt /var/home
lsblk -f
uname -a
rpm -qa | grep -i cachy
systemctl --failed
journalctl -b -p warning..alert --no-pager
flatpak list
mokutil --sb-state
cat /etc/crypttab
systemd-cryptenroll --tpm2-device=list
lspci -k
lsmod | grep -E 'amdgpu|i915|xe|nvidia|nouveau|virtio_gpu|snd|snd_hda|snd_sof|kvm' || true
systemctl --user status pipewire.service pipewire-pulse.service wireplumber.service --no-pager
ffmpeg -hide_banner -hwaccels
glxinfo -B 2>/dev/null || true
vulkaninfo --summary 2>/dev/null || true
vainfo 2>/dev/null | sed -n '1,120p'
clinfo 2>/dev/null | sed -n '1,160p'
flatpak list | grep -Ei 'Steam|Lutris|Heroic|Bottles|Proton' || true
cat /proc/sys/kernel/split_lock_mitigate 2>/dev/null || true
```

Before the CachyOS experiment, `rpm -qa | grep -i cachy` may return no output.
After the experiment, it should show the expected CachyOS kernel packages.

## Atomic Layout Validation

Script:

```sh
scripts/validate-atomic-layout
```

It checks:

- `rpm-ostree` availability;
- Fedora/Silverblue identity when detectable;
- deployment status;
- mounts for `/`, `/usr`, `/var`, `/var/home`, and `/sysroot`;
- `/home` relationship to `/var/home`;
- Btrfs presence on expected backing mounts;
- Secure Boot state when `mokutil` is available;
- `/etc/crypttab` TPM2 auto-unlock configuration when present;
- TPM2 device discovery when `systemd-cryptenroll` is available;
- failed systemd units.

A warning is not automatically a project failure. It is a prompt to inspect the
system and document what was observed.

## CachyOS Kernel Validation

Script:

```sh
scripts/validate-cachyos-kernel
```

It checks:

- running kernel string;
- installed CachyOS-related RPMs;
- CachyOS COPR repo file presence;
- rpm-ostree status;
- ostree admin status;
- Secure Boot state when `mokutil` is available;
- common out-of-tree module packages;
- failed systemd units.

The script exits non-zero if it cannot detect a CachyOS kernel or CachyOS
packages in the current deployment.

## Hardware and Media Stack Validation

Script:

```sh
scripts/validate-hardware-media-stack
```

It checks:

- graphics and audio PCI device binding;
- relevant kernel modules such as `amdgpu`, `i915`, `xe`, `virtio_gpu`, and
  sound modules;
- relevant host RPMs for Mesa, Vulkan, VA-API, Intel compute, ROCm, OpenCL,
  PipeWire, GStreamer, FFmpeg, and EasyEffects;
- PipeWire, PipeWire Pulse compatibility, and WirePlumber user services;
- PulseAudio compatibility state through `pactl`;
- WirePlumber state through `wpctl`;
- OpenGL/EGL through `glxinfo` and `eglinfo`;
- Vulkan through `vulkaninfo --summary`;
- VA-API through `vainfo`;
- FFmpeg hardware acceleration exposure;
- GStreamer VA plugin exposure;
- OpenCL and ROCm through `clinfo` and `rocminfo`;
- darktable OpenCL exposure if `darktable-cltest` exists;
- relevant kernel and media journal lines.

Manual commands:

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

The hardware/media stack is acceptable when:

- the expected kernel driver is bound to the actual GPU;
- GNOME remains stable on the Fedora deployment;
- PipeWire, PipeWire Pulse compatibility, and WirePlumber are alive;
- OpenGL/EGL, Vulkan, and VA-API expose the expected host paths;
- OpenCL is visible through the intended Intel, ROCm, or Rusticl path when that
  path is declared;
- missing acceleration in a VM is documented as a VM limitation rather than
  hidden as a generic pass;
- NVIDIA, RPM Fusion codec replacement, and Resolve are not implied by this
  baseline.

## Gaming Runtime Validation

Script:

```sh
scripts/validate-gaming-runtime
```

It checks:

- declared Flatpak gaming applications;
- Steam Flatpak permissions when Steam is installed;
- relevant host RPMs such as Gamescope, MangoHud, vkBasalt, GameMode,
  controller rules, and OBS capture helpers;
- core gaming commands;
- Gamescope, MangoHud, vkBasalt, and GameMode basic command behavior;
- Vulkan baseline and Vulkan layer files;
- controller/input hints;
- split-lock mitigation runtime and persistent state;
- rpm-ostree status for layered package visibility.

The gaming runtime is acceptable when:

- the hardware/media validator has already passed or documented limitations;
- Steam and launchers are installed through the declared channel;
- Vulkan works before gaming apps are debugged;
- Gamescope is available only when the active profile declares it;
- MangoHud/vkBasalt injection state is visible;
- GameMode is not mixed with another process-priority system without a test;
- `kernel.split_lock_mitigate=0` is not active by default;
- no gaming package blocks upgrade, rollback, Secure Boot, or TPM2 validation.

## Diagnostics

Script:

```sh
scripts/collect-diagnostics
```

It creates:

- `diagnostics/<timestamp>/`;
- `diagnostics/<timestamp>.tar.gz`.

The bundle may contain hostnames, usernames, local paths, enabled repositories,
package names, and journal excerpts. Treat it as local diagnostic data, not as an
anonymized public artifact.

## Baseline Pass Criteria

The baseline is acceptable when:

- `rpm-ostree status` shows a healthy Atomic deployment (Margine bootc image, Bluefin DX, or stock Silverblue depending on path);
- Secure Boot is enabled on the stock Fedora deployment;
- `/usr` follows the read-only ostree model;
- `/etc` and `/var` are available as local state;
- `/home` points to `/var/home` or an equivalent layout is documented;
- Btrfs appears in the expected backing layout;
- no critical failed services are present;
- Flatpak works and can list installed applications or runtimes.

## TPM2 Pass Criteria

TPM2 auto-unlock is acceptable only when:

- the encrypted system unlocks automatically with TPM2;
- manual passphrase or recovery-key unlock remains available;
- Secure Boot remains enabled;
- `/etc/crypttab` records the TPM2 unlock configuration;
- one Fedora update and one rpm-ostree rollback have been tested;
- no critical LUKS, initramfs, bootloader, or kernel errors appear.

## GNOME Personal Layer Validation

After applying any user-level home, font, theme, or icon policy:

```sh
gsettings get org.gnome.desktop.interface color-scheme
gsettings get org.gnome.desktop.interface accent-color
gsettings get org.gnome.desktop.interface font-name
gsettings get org.gnome.desktop.interface monospace-font-name
gsettings get org.gnome.desktop.interface gtk-theme
gsettings get org.gnome.desktop.interface icon-theme
cat ~/.config/user-dirs.dirs
sed -n '1,120p' ~/.config/gtk-3.0/bookmarks
sed -n '1,120p' ~/.config/gtk-4.0/bookmarks
gio info -a metadata::custom-icon ~/data ~/data/library ~/data/work ~/data/media ~/dev ~/scratch
fc-match "IBM Plex Sans"
fc-match "Atkinson Hyperlegible Next"
fc-match "JetBrains Mono"
```

The personal layer is acceptable only when:

- GNOME remains the shell, lock screen, settings, and portal owner;
- XDG directories point into `~/data`, `~/dev`, and `~/scratch`;
- GTK/Nautilus bookmarks are compact and correct;
- folder icon metadata points only to existing scalable icons or is absent;
- fonts resolve from Fedora packages or reviewed user fonts;
- no Hyprland, Waybar, Walker, Fuzzel, or AUR package is needed.

## CachyOS Pass Criteria

The CachyOS experiment is acceptable only when:

- the system boots into the CachyOS deployment;
- `uname -a` identifies the CachyOS kernel;
- CachyOS kernel packages are installed;
- Secure Boot remains enabled if the experiment is claiming target compliance;
- GNOME/GDM still works;
- no critical storage, boot, or kernel errors appear;
- rollback to the Fedora deployment has been tested.
