# Margine Personal Migration Assessment

This document reviews `/home/daniel/dev/margine-os-personal` from the point of
view of the new Fedora Atomic architecture.

The conclusion is deliberately conservative: the new system should carry over
selected policies, user-facing assets, and workflow ideas. It should not carry
over the Arch/CachyOS installation model, package manifests, AUR assumptions,
Hyprland desktop layer, or root-on-ZFS boot/recovery stack.

## Inputs Reviewed

Primary local sources:

- `README.md`
- `products/margine-cachyos.toml`
- `manifests/packages/*.txt`
- `manifests/aur/*.txt`
- `manifests/flatpaks/apps.txt`
- `docs/adr/0024-versioned-application-config-layer.md`
- `docs/adr/0027-photography-and-color-management-baseline.md`
- `docs/adr/0028-browser-and-mail-defaults.md`
- `docs/adr/0029-coding-and-admin-tooling-baseline.md`
- `docs/adr/0030-remote-access-and-firewall-baseline.md`
- `docs/adr/0031-printing-and-scanning-baseline.md`
- `docs/adr/0032-virtualization-and-container-baseline.md`
- `docs/adr/0035-framework13-power-baseline.md`
- `docs/adr/0043-home-organization-baseline.md`
- `docs/adr/0019-framework13-speaker-preset-provisioning.md`
- `docs/learning/20-perche-il-preset-audio-va-risolto-a-runtime.md`
- `docs/learning/43-what-cachyos-adds-beyond-kernel-and-repos.md`
- `docs/learning/44-davinci-resolve-on-linux-drivers-and-runtime-requirements.md`
- `docs/learning/45-gaming-stack-layering-and-split-lock-mitigation.md`
- `docs/learning/50-what-bazzite-is-really-made-of-and-what-margine-should-or-should-not-import.md`
- selected provisioners under `scripts/`
- selected payloads under `files/`

Current availability was also checked with:

- `flatpak remote-ls flathub --app` against Flathub;
- `dnf repoquery` inside a clean `fedora:44` container.

Those checks are evidence for the initial assessment, not a substitute for the
Silverblue VM lab.

## Architectural Rule

Do not translate Arch package layers into Fedora package layers.

For Fedora Atomic, every migrated item must first answer:

1. Is this already part of Fedora Silverblue or the GNOME suite?
2. Is it a graphical application that should be Flatpak?
3. Is it a CLI/development tool that should live in toolbox or distrobox?
4. Is it a true host component that requires rpm-ostree layering?
5. Is it an operating-system behavior that conflicts with ostree rollback?

Only the fourth category belongs in the host image by default.

## Carry Over Now

These are worth carrying into the Fedora Atomic design, with adaptation.

### Home Organization Model

Carry over the `~/data`, `~/dev`, `~/scratch` model and the XDG user directory
mapping.

Why it fits:

- it is distribution-agnostic;
- it works well with `/var/home`;
- it improves GNOME Files, GTK file pickers, backups, and project organization;
- it does not require a mutable root filesystem.

Required changes:

- treat `/home` as Silverblue's `/var/home` surface;
- keep all writes under the user home;
- avoid assuming Arch package paths;
- make folder icon metadata best-effort because it is user session state.

Recommended phase:

- phase 1 lab: document and test manually;
- phase 2: add a Fedora-native home organization provisioner.

Detailed GNOME/Fedora policy lives in
`docs/08-gnome-personal-layer.md`.

### Fonts, Themes, and Folder Icons

Carry over the visual direction, not the Arch package list.

What fits:

- GNOME/Adwaita-first visual baseline;
- dark color scheme;
- GNOME accent preference, starting with yellow if supported;
- compact home bookmarks in Nautilus and GTK file pickers;
- GIO folder icon metadata as user-session state;
- a small Margine icon overlay for Margine-specific launchers;
- curated fonts for Unicode coverage, code, accessibility, and Office document
  compatibility.

What must change:

- use Fedora font package names, not Arch names;
- do not use AUR-only font or icon packages as a baseline;
- do not force Hyprland/Waybar/Walker/Fuzzel theme artifacts into GNOME;
- do not make Rewaita/GTK4 CSS generation part of the first GNOME baseline;
- do not require `hyprqt6engine`, `qt5ct`, or `qt6ct` for a stock GNOME session.

Initial Fedora candidates:

- `adobe-source-code-pro-fonts`
- `adobe-source-sans-pro-fonts`
- `adobe-source-serif-pro-fonts`
- `atkinson-hyperlegible-next-fonts`
- `atkinson-hyperlegible-mono-fonts`
- `ibm-plex-sans-fonts`
- `ibm-plex-mono-fonts`
- `ibm-plex-serif-fonts`
- `google-carlito-fonts`
- `google-crosextra-caladea-fonts`
- `liberation-sans-fonts`
- `liberation-serif-fonts`
- `liberation-mono-fonts`
- `google-noto-color-emoji-fonts`
- `google-noto-sans-cjk-fonts`
- `jetbrains-mono-fonts`

Reject as defaults:

- `ttf-ioskeley-mono`;
- old Iosevka package names from Arch;
- `ttf-ms-fonts`;
- `adwaita-colors-icon-theme`;
- `morewaita-icon-theme`;
- `Margine-Adwaita` as a full app-icon takeover before it is rebuilt for
  Fedora.

If Ioskeley, Iosevka, colored Adwaita folders, or MoreWaita remain desirable,
treat them as later user-font/user-icon assets or custom packages with license
review and reproducible source, not as phase 1 dependencies.

### MIME Defaults and App Defaults

Carry over the concept of versioned MIME defaults, but regenerate desktop IDs
from the Fedora/Flatpak reality.

Good defaults from the old model:

- Firefox for web;
- Thunderbird for mail;
- GNOME Papers for PDFs;
- GNOME Loupe for images;
- GNOME Showtime for video;
- GNOME Decibels or Gapless for audio;
- GNOME Text Editor for text.

Required changes:

- Flatpak desktop IDs may differ from RPM desktop IDs;
- GNOME apps may already exist in the base image;
- do not assume Arch desktop files;
- validate with `gio mime` and actual `.desktop` files in the Silverblue VM.

### Browser Policy Idea

Carry over the policy idea, not blindly the file path.

The old Firefox policy is moderate and useful:

- disable telemetry and studies;
- remove Pocket and sponsored suggestions;
- avoid default-browser prompts;
- set DuckDuckGo;
- install uBlock Origin.

Required decision:

- if Firefox remains the Fedora/Silverblue RPM/base browser, `/etc/firefox/policies/policies.json`
  is a reasonable host policy path;
- if Firefox is Flatpak, policy handling must be revalidated for the Flatpak
  deployment model before enforcing it.

Do not migrate browser profiles.

### Photography and Color Management Assets

Carry over the photography intent and validated ICC profiles.

What fits:

- darktable workflow;
- ArgyllCMS/DisplayCAL for calibration workflows;
- `colord` as the system color service;
- validated ICC assets for the Framework 13 panel and Dell P2415Q.

Atomic changes:

- prefer user ICC assets under `~/.local/share/icc/margine`;
- for shared local assets, prefer `/usr/local/share/margine/icc` because
  `/usr/local` maps to writable local state on Silverblue;
- do not install to `/usr/share/margine` in phase 1;
- do not carry Hyprland compositor ICC rules into GNOME.

GNOME should own display color assignment through Settings/colord first.

### Printing and Scanning Policy

Carry over the driverless-first policy.

The concept still fits:

- CUPS for printing;
- Avahi/mDNS for discovery;
- `ipp-usb` for modern USB printer/MFP devices;
- SANE and `sane-airscan` for scanning;
- GNOME Document Scanner or `simple-scan` for the UI.

Atomic changes:

- layer only missing host services after the VM baseline shows what Silverblue
  already ships;
- do not overwrite `/etc/nsswitch.conf` blindly;
- prefer a small idempotent validator before a provisioner.

### Virtualization Model, Optional

Carry over the separation between VM support and container support, but make it
optional.

Host-layer candidates:

- `libvirt`
- `qemu-kvm` or Fedora's equivalent QEMU host packages;
- `edk2-ovmf`
- `swtpm`
- `dnsmasq`
- `virt-manager` or `virt-viewer` if Flatpak is insufficient.

Atomic changes:

- this is an rpm-ostree layer because libvirt/QEMU host integration is not just
  an app;
- enablement should remain explicit, not always-on at first boot;
- Podman/toolbox are already part of the Atomic workflow and should not be
  reinvented from the old repo.

### Framework 13 Power Policy, Narrowly

Carry over the policy intent, not the Waybar/Hyprland integration.

What fits:

- `power-profiles-daemon` remains the power profile engine;
- balanced profile by default;
- conservative handling of `amdgpu_panel_power` because it may affect color;
- explicit logind lid/power-button policy if validated on the real machine.

What does not fit:

- Waybar refresh hooks;
- Hyprland refresh-rate user services;
- anything that duplicates GNOME power UI without a clear reason.

### Hardware, Audio, Video, and Compute Stack

Carry over the open-driver intent, not the Arch package names.

What fits:

- Mesa as the default open graphics stack for Intel and AMD;
- Intel media, Vulkan, and OpenCL validation;
- AMD Mesa, VA-API, Vulkan, ROCm OpenCL, and Rusticl validation;
- PipeWire, PipeWire Pulse compatibility, and WirePlumber health checks;
- `clinfo`, `rocminfo`, `vulkaninfo`, `vainfo`, `glxinfo`, and FFmpeg/GStreamer
  exposure checks;
- Framework 13 EasyEffects preset logic, but only as hardware-gated user
  session provisioning.

What must change:

- map every package through Fedora names and Fedora repositories;
- inspect what Silverblue already ships before adding rpm-ostree layers;
- prefer Flatpak for creative GUI apps such as darktable, GIMP, Audacity, OBS,
  EasyEffects, and Reaper;
- keep host packages for host drivers, ICDs, services, diagnostics, and media
  runtimes only;
- treat OpenCL as an application-visible runtime, not just an installed package;
- keep RPM Fusion codec replacement as a separate documented decision;
- keep Resolve as a future vendor-aware exception, not baseline support.

Initial Fedora candidates:

- diagnostics: `mesa-demos`, `vulkan-tools`, `libva-utils`, `clinfo`;
- Mesa/OpenCL: `mesa-dri-drivers`, `mesa-vulkan-drivers`, `mesa-va-drivers`,
  `mesa-libOpenCL`;
- Intel: `libva-intel-media-driver`, `intel-compute-runtime`, `intel-opencl`,
  `igt-gpu-tools`, `intel-vpl-gpu-rt`;
- AMD: `rocm-opencl`, `rocminfo`, `radeontop`;
- audio: `pipewire-utils`, `pipewire-pulseaudio`, `pipewire-alsa`,
  `wireplumber`, `alsa-utils`;
- media: `ffmpeg-free`, `gstreamer1-plugin-libav`,
  `gstreamer1-plugin-openh264`, `gstreamer1-plugins-base`,
  `gstreamer1-plugins-good`, `gstreamer1-plugins-bad-free`,
  `gstreamer1-plugins-ugly-free`, `gstreamer1-vaapi`.

Reject as defaults:

- proprietary NVIDIA and akmods;
- `libva-intel-driver` unless old hardware proves it needs the legacy driver;
- CachyOS gaming metapackages;
- implicit `kernel.split_lock_mitigate=0`;
- AUR Resolve packages and Arch compatibility stacks.

Detailed policy lives in `docs/10-hardware-media-stack.md`.

### Gaming Runtime

Carry over the layer split and the kernel-policy discipline.

What fits:

- a real gaming runtime in the target profile;
- separation between runtime compatibility and launcher/overlay tools;
- Steam as the primary runtime entry point;
- Protontricks/ProtonUp-Qt for Proton helper workflows;
- Gamescope, MangoHud, vkBasalt, and GameMode as explicit runtime helpers;
- validation of Vulkan layer visibility and split-lock policy;
- Bazzite as a Fedora Atomic reference for a future image-based gaming profile.

What must change:

- no AUR `proton-ge-custom-bin`;
- no CachyOS `proton-cachyos-slr` or `wine-cachyos-opt`;
- no Arch `lib32-*` package names;
- no CachyOS gaming metapackages;
- no Waybar split-lock indicator in the GNOME baseline;
- no Steam Gaming Mode as a phase 1 GNOME autostart.

Initial Fedora Atomic shape:

- Flatpak apps: Steam, Lutris, Heroic, Bottles, Protontricks, ProtonUp-Qt;
- optional Flatpak apps: RetroArch, RetroDECK, Cartridges;
- host helper candidates after hardware validation: `gamescope`, `mangohud`,
  `vkBasalt`, `gamemode`, `goverlay`, `steam-devices`;
- future image/session work: Steam Gaming Mode, gamescope-session, controller
  session integration, and Bazzite-style update ergonomics.

Reject as defaults:

- implicit `kernel.split_lock_mitigate=0`;
- NVIDIA gaming images;
- handheld-specific services;
- Bazzite rebase as the Margine base;
- permanent rpm-ostree app launcher accumulation.

Detailed policy lives in `docs/11-gaming-runtime.md`.

### Secure Boot and TPM2 Intent

Carry over the requirement, not the Arch implementation.

What fits:

- Secure Boot as a real hardware target;
- automatic unlock with TPM2 for the encrypted system;
- explicit manual passphrase or recovery-key fallback;
- validation after updates and rollbacks.

What must change:

- use Fedora's signed shim, bootloader, and kernel path first;
- use LUKS2, `systemd-cryptenroll`, `/etc/crypttab`, and a validated
  rpm-ostree initramfs workflow;
- do not start from Limine, `sbctl`, Arch UKI generation, mkinitcpio, or the old
  root-on-ZFS unlock design;
- do not seal the TPM2 policy against a temporary non-Secure-Boot lab state.

Recommended phase:

- phase 1 lab: stock encrypted Silverblue with Secure Boot enabled;
- phase 1.5 lab: TPM2 auto-unlock on the Fedora kernel;
- later: CachyOS kernel only if Secure Boot and TPM2 behavior remain understood.

### Selected Local Helpers

Some helper ideas are worth redesigning:

- host health validation;
- diagnostics collection;
- SSH enable/disable helpers;
- libvirt enable/disable helpers;
- home organization audit.

They must be rewritten for:

- rpm-ostree status;
- Flatpak state;
- toolbox/distrobox state;
- firewalld rather than UFW unless UFW is deliberately layered;
- Silverblue mount layout.

## Use Flatpak First

Many old Arch package choices are better as Flatpaks on Fedora Atomic.

Confirmed Flathub candidates during this review:

| Purpose | Flatpak ID |
| --- | --- |
| Bitwarden | `com.bitwarden.desktop` |
| Firefox | `org.mozilla.firefox` |
| Thunderbird | `org.mozilla.Thunderbird` / `org.mozilla.thunderbird` |
| LibreOffice | `org.libreoffice.LibreOffice` |
| darktable | `org.darktable.Darktable` |
| GIMP | `org.gimp.GIMP` |
| Audacity | `org.audacityteam.Audacity` |
| OBS Studio | `com.obsproject.Studio` |
| Easy Effects | `com.github.wwmm.easyeffects` |
| Gapless | `com.github.neithern.g4music` |
| Blanket | `com.rafaelmardojai.Blanket` |
| Reaper | `fm.reaper.Reaper` |
| Steam | `com.valvesoftware.Steam` |
| Lutris | `net.lutris.Lutris` |
| Heroic | `com.heroicgameslauncher.hgl` |
| Bottles | `com.usebottles.bottles` |
| Protontricks | `com.github.Matoking.protontricks` |
| ProtonUp-Qt | `net.davidotek.pupgui2` |
| RetroArch | `org.libretro.RetroArch` |
| RetroDECK | `net.retrodeck.retrodeck` |
| Cartridges | `page.kramo.Cartridges` |
| Chromium | `org.chromium.Chromium` |
| DisplayCAL | `net.displaycal.DisplayCAL` |

Initial recommendation:

- default Flatpaks: Bitwarden, Thunderbird, LibreOffice, Gapless;
- photography optional Flatpaks: darktable, GIMP, DisplayCAL;
- media optional Flatpaks: Audacity, OBS Studio, Easy Effects, Reaper;
- gaming optional Flatpaks: Steam, Lutris, Heroic, Bottles, Protontricks,
  ProtonUp-Qt, RetroArch, RetroDECK, Cartridges.

Firefox needs a channel decision because Fedora Silverblue may already include a
browser and the policy path differs between RPM/base and Flatpak.

## Use Toolbox or Distrobox First

The old `coding-system-tools` layer should not become an rpm-ostree layer by
default.

Good toolbox candidates:

- `neovim`
- LazyVim configuration;
- `tmux`
- `gh`
- `ripgrep`
- `fd-find`
- `jq`
- `eza`
- `bat`
- `btop`
- `htop`
- `ncdu`
- `mtr`
- `strace`
- `lsof`
- `smartmontools` for inspection where permitted;
- language SDKs and build tools.

Host-layer only when there is a host reason:

- `openssh-server` if the machine must accept SSH;
- `smartmontools` if SMART checks are part of host diagnostics;
- `rclone` only if host mounts/services are required;
- `git`/`gh` only if the host workflow truly needs them outside toolbox.

## Host Layer Candidates

These can justify rpm-ostree layering after the lab baseline proves they are
missing or needed:

| Area | Candidate host packages or services | Reason |
| --- | --- | --- |
| Kernel test | CachyOS COPR repo + `kernel-cachyos` | host kernel replacement |
| Printing/scanning | `cups`, `ipp-usb`, `sane-airscan`, `avahi`, `nss-mdns` | system services and device discovery |
| Virtualization | `libvirt`, QEMU/KVM packages, `edk2-ovmf`, `swtpm`, `dnsmasq` | host virtualization stack |
| Remote access | `openssh-server` | host daemon |
| Firewall | Fedora `firewalld` policy | Fedora-native firewall baseline |
| Color | `colord`, `argyllcms` if missing | host color service/calibration tooling |
| Fingerprint | `fprintd`, `libfprint` if missing | device service |
| VPN | `NetworkManager-openvpn`, `wireguard-tools` | host network integration |
| Hardware/media diagnostics | `mesa-demos`, `vulkan-tools`, `libva-utils`, `clinfo`, `rocminfo` | host driver and compute validation |
| Intel/AMD media runtime | Intel media/compute packages, Mesa VA/Vulkan/OpenCL packages, ROCm OpenCL packages | host driver surfaces consumed by apps |
| Gaming host helpers | `gamescope`, `mangohud`, `vkBasalt`, `gamemode`, `goverlay`, `steam-devices` | host runtime and Vulkan/input integration |

Do not layer these just because they existed in Arch manifests. Layer them only
when the VM validation shows a host-level need.

## Keep Out of Phase 1

These should not be ported to the Fedora Atomic baseline.

### Arch and AUR Machinery

Reject:

- `pacman`
- `yay`
- AUR manifests;
- `install-aur-packages`;
- local PKGBUILD/package repository machinery;
- Arch/CachyOS repository bootstrap scripts.

Replacement model:

- Fedora base image and rpm-ostree;
- Fedora repositories;
- Flathub;
- toolbox/distrobox;
- vendor/manual exception documents for anything still missing.

### Hyprland Desktop Layer

Reject for phase 1:

- Hyprland;
- Waybar;
- Walker;
- Fuzzel;
- SwayNC;
- SwayOSD;
- greetd/tuigreet;
- Hyprlock/Hypridle/Hyprpaper;
- Hyprland Lua work;
- `xdg-desktop-portal-hyprland`;
- Hyprland ICC compositor rules.

Reason:

- the new system starts with GNOME;
- GNOME already owns shell, lock screen, settings, notifications, portals, and
  core app integration;
- importing the Hyprland layer would make the first Atomic phase impossible to
  evaluate cleanly.

### Root-on-ZFS and Boot Chain

Reject the old implementation for Fedora Atomic:

- root-on-ZFS storage provisioning;
- ZFS boot environments;
- Sanoid/Snapper root rollback logic;
- Limine boot chain generation;
- mkinitcpio;
- Arch UKI generation;
- `sbctl` bootstrap;
- the old TPM2 auto-unlock rollout;
- live ISO/chroot installer flow.

Replacement model:

- Fedora installer layout;
- Btrfs validation only;
- ostree/rpm-ostree rollback;
- Fedora-native Secure Boot;
- LUKS2 plus TPM2 unlock through systemd tooling;
- future bootc only after the manual lab.

### CachyOS Runtime Extras

Reject as defaults:

- `chwd`;
- `cachyos-hello`;
- `cachyos-kernel-manager`;
- `ananicy-cpp`;
- `cachyos-ananicy-rules`;
- `cachyos-settings`;
- `cachyos-hooks`;
- CachyOS gaming metapackages.

Reason:

- on Fedora they are COPR/third-party concerns;
- several overlap with host policy ownership;
- phase 1 only tests the kernel replacement, not a CachyOS personality layer.

Possible future:

- evaluate `kernel-cachyos-addons` separately after kernel rollback is proven.

### UFW Baseline

Do not carry UFW by default.

Fedora uses firewalld as the native firewall path. A Fedora Atomic baseline
should start from firewalld and only choose UFW if there is a specific reason to
diverge.

### Connectivity Backend Overrides

Do not force NetworkManager to use iwd in phase 1.

Carry over only the principle:

- NetworkManager owns host networking;
- VPN support can be layered if needed;
- regulatory domain changes must be explicit and hardware-tested.

The old `impala`/`bluetui` terminal-first idea can be revisited in toolbox or as
optional host tools, not as a GNOME baseline.

### Old Gaming Runtime Implementation

Do not preinstall the old Arch/CachyOS gaming stack as-is.

Reason:

- Steam/Lutris/Heroic/Bottles are available as Flatpaks;
- Fedora Atomic gaming behavior should not begin with kernel mitigation changes;
- `split_lock_mitigate` must stay opt-in if ever implemented;
- Bazzite-style ideas should be studied as Fedora Atomic image policy, not
  copied wholesale;
- stable host helpers should eventually move into image composition rather than
  remain ad-hoc client-side layers.

Recommended position:

- gaming runtime is part of the target profile after hardware/media validation;
- launchers are Flatpak-first;
- host helpers are explicit and validated;
- Steam Gaming Mode is future image/session work.

### DaVinci Resolve

Do not make Resolve a baseline item.

Reason:

- no AUR;
- official Linux support targets a different platform family;
- GPU compute/runtime compatibility is the real problem;
- it requires a separate vendor-aware validation path.

Future path:

- document as a manual/vendor exception, likely distrobox/toolbox or dedicated
  host exception depending on GPU requirements.

## Redesign Required

These old concepts are valuable but need a Fedora Atomic implementation.

### Manifest Model

Replace Arch package layers with channel-specific manifests:

```text
manifests/host-layer/*.txt
manifests/flatpaks/*.txt
manifests/toolbox/*.txt
manifests/manual-exceptions/*.md
manifests/rejected/*.md
```

Do not keep a single "packages" layer that hides the channel decision.

### Update Helper

The old `update-all` is not portable.

A future Atomic update helper should understand:

- `rpm-ostree upgrade`;
- reboot-required deployment state;
- `flatpak update`;
- Topgrade as an accessory updater only;
- toolbox/distrobox update checks;
- diagnostics before and after upgrades;
- rollback instructions.

It must not use pacman, Snapper, ZFS boot environments, or Limine.

Initial implementation:

- `scripts/update-all`;
- `config/topgrade.toml`;
- `docs/12-update-orchestration.md`.

Topgrade is deliberately constrained. It must not own `rpm-ostree`, `bootc`,
firmware, Secure Boot, TPM2, or rollback semantics.

### Branding

Carry over only neutral Margine assets after the lab:

- logo files;
- wallpaper;
- optional fastfetch/ascii branding.

Do not carry over:

- Plymouth assumptions;
- boot splash deployment;
- Limine entries;
- Hyprland theme rendering;
- Waybar/Walker/SwayNC theme outputs.

### Application Config Layer

Split the old application config layer:

- GNOME-compatible: MIME defaults, user dirs, Firefox policy if channel allows,
  Thunderbird default, selected darktable defaults, ICC assets, selected font
  policy, and GNOME settings;
- terminal/toolbox: Neovim/LazyVim, shell/dev tools;
- rejected for GNOME baseline: Kitty default, Qt theme forcing, generated GTK4
  theme CSS, Hyprland-related launchers, Waybar menus.

## Proposed Initial Fedora Atomic Personal Profile

Phase 1 should stay lean:

### Host

- Fedora Silverblue stock base;
- Secure Boot and encrypted LUKS2 install as target baseline;
- TPM2 auto-unlock after the stock Fedora boot path is validated;
- optional Fedora font layer after the stock GNOME baseline is recorded;
- optional `adw-gtk3-theme` only if legacy GTK3 apps need it;
- CachyOS kernel COPR only during the controlled kernel experiment;
- no extra host layers until baseline validation is complete.

### Flatpak

Start with:

- Bitwarden;
- Thunderbird;
- LibreOffice;
- Gapless;
- optional darktable/GIMP only if the lab is also validating photo workflow.

### Toolbox

Create a development toolbox with:

- Neovim/LazyVim;
- `git`, `gh`, `tmux`, `ripgrep`, `fd-find`, `jq`, `bat`, `eza`, `btop`;
- language/toolchain packages as needed.

### User State

Manually validate:

- `~/data`, `~/dev`, `~/scratch`;
- XDG user dirs;
- GTK/Nautilus bookmarks;
- folder icon metadata;
- GNOME dark/accent/font settings;
- MIME defaults;
- ICC asset placement.

## Final Assessment

What survives from Margine Personal is not the distribution stack. What survives
is the discipline:

- explicit defaults;
- validated recovery;
- selective app config;
- home organization;
- careful hardware policy;
- diagnostics before automation.

What does not survive is the implementation substrate:

- Arch package layers;
- AUR;
- CachyOS repository identity;
- Hyprland desktop ownership;
- root-on-ZFS recovery ownership;
- Limine/UKI/mkinitcpio boot ownership.

The Fedora Atomic project should start smaller than Margine Personal, not larger.
Once the VM lab proves the base, selected pieces can come back through the right
channel.
