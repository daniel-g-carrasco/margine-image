# Architecture

Margine Fedora Atomic must follow Fedora Atomic Desktop's model instead of
forcing the existing Arch/CachyOS model onto a different operating system.

## Base System

The phase 1 target is:

- Fedora Silverblue 44;
- GNOME;
- ostree and rpm-ostree;
- Fedora's Btrfs desktop layout;
- Secure Boot through Fedora's signed boot path;
- LUKS2 with TPM2 automatic unlock as a target boot requirement;
- Flatpak for graphical applications;
- toolbox first, distrobox later if needed;
- rpm-ostree layering only for host-level components that cannot reasonably live
  elsewhere.

Fedora Silverblue is the GNOME member of Fedora Atomic Desktops. It is built
around atomic updates, rollback, Flatpak applications, and integrated development
containers through Toolbx.

## Filesystem Model

Expected host layout:

| Path | Role |
| --- | --- |
| `/` | deployment root |
| `/usr` | operating system content, read-only in normal operation |
| `/etc` | writable host configuration with ostree merge behavior |
| `/var` | writable persistent local state |
| `/home` | normally a symlink to `/var/home` |
| `/opt` | normally a symlink to `/var/opt` |
| `/usr/local` | normally a symlink to `/var/usrlocal` |

Practical rule: do not build tools that expect a mutable root filesystem. Local
state belongs in `/etc`, `/var`, user home, Flatpak state, or development
containers.

## Btrfs

Fedora Desktop has used Btrfs by default since Fedora 33. In phase 1, the
project uses the Fedora installer layout and records what was created.

Validation commands:

```sh
findmnt /
findmnt /var
findmnt /var/home
lsblk -f
```

This project does not define Btrfs snapshot policy in phase 1. System rollback
comes from ostree/rpm-ostree deployments, not from a custom Btrfs snapshot
scheme.

## Software Channels

Keep software channels separate:

| Channel | Intended use | Notes |
| --- | --- | --- |
| Flatpak | graphical applications | Flathub is expected in the lab after baseline |
| toolbox | CLI tools, SDKs, development environments | first choice for development tooling |
| distrobox | alternative container workflow | evaluate after toolbox |
| rpm-ostree install | host packages | use sparingly |
| rpm-ostree override | host package replacement, kernel tests | controlled experiments only |
| user home | XDG dirs, GNOME settings, bookmarks, folder metadata | no root filesystem mutation |

This separation is part of the architecture. Avoid turning rpm-ostree layering
into a general-purpose package installation habit.

## Declarative Control Plane

Margine Fedora Atomic should become declarative, but not by hiding Fedora Atomic
behind a fake mutable package model.

The declaration layer describes desired state. Separate adapters apply or verify
that state through the correct Fedora channel:

| Declared area | Execution or validation channel |
| --- | --- |
| base OS identity | Silverblue/rpm-ostree status |
| host packages | rpm-ostree install or future image build |
| host package replacements | rpm-ostree override or future image build |
| graphics, media, and compute host stack | rpm-ostree layer, base image, and validators |
| gaming host runtime helpers | rpm-ostree layer, future image build, and validators |
| GUI applications | Flatpak |
| development environments | toolbox or distrobox |
| GNOME preferences | dconf/gsettings |
| home layout | user-home provisioner |
| system services | systemd presets or explicit enablement |
| Secure Boot | firmware, shim, MOK, and boot validation |
| TPM2 unlock | LUKS2, systemd-cryptenroll, crypttab, initramfs |
| diagnostics | read-only validators |
| update orchestration | Margine `update-all`; Topgrade only for accessory channels |

Principles:

- declarations are reviewed before they are applied;
- adapters produce a plan before making changes;
- host changes create a new deployment and require an explicit reboot;
- user state is declared separately from operating-system state;
- secrets, recovery keys, TPM2 material, and private tokens are never stored in
  declarations;
- drift detection comes before auto-remediation.

The initial draft lives under `declarations/`. It is a design contract and a
future automation input, not an installer.

## Personal Layer

Fonts, themes, icons, and home organization are a user-facing layer on top of
the stock GNOME baseline. They must not redefine the operating system model.

Rules:

- home layout belongs under `/var/home/$USER`;
- XDG user dirs, GTK bookmarks, and folder icon metadata are user state;
- GNOME settings should be applied through `gsettings` or dconf only after the
  stock session is validated;
- fonts may be layered only when they need to be visible to the host and
  Flatpak applications;
- AUR-only font and icon packages are not Fedora Atomic dependencies;
- Hyprland/Waybar/Walker/Fuzzel theme artifacts are not part of the GNOME
  baseline.

## Hardware and Media Stack

The hardware/media layer is a host capability layer, not an application bundle.
It covers the driver and runtime surfaces that graphical applications consume:

- kernel drivers such as `amdgpu`, `i915`, `xe`, and `virtio_gpu`;
- Mesa OpenGL, EGL, and Vulkan;
- VA-API media acceleration;
- OpenCL through Intel compute runtime, ROCm OpenCL, or Mesa Rusticl;
- PipeWire, PipeWire Pulse compatibility, and WirePlumber;
- diagnostic tools such as `glxinfo`, `vulkaninfo`, `vainfo`, `clinfo`, and
  `rocminfo`.

The starting assumption is that Fedora Silverblue already provides a working
GNOME desktop, Mesa baseline, and PipeWire session. The lab should inspect that
baseline before layering packages.

Channel rules:

- host drivers and ICDs belong to Fedora base, rpm-ostree layers, or a future
  image build;
- GUI apps such as darktable, GIMP, Audacity, OBS, EasyEffects, Reaper, and
  Steam should prefer Flatpak unless a host reason is proven;
- creative and gaming apps do not get to change kernel policy silently;
- NVIDIA, akmods, RPM Fusion codec replacement, and Resolve are separate future
  exception layers.

The detailed plan is in `docs/10-hardware-media-stack.md`.

## Gaming Runtime

Gaming is a target capability, but it is not allowed to blur the channel model.

The architecture separates:

- desktop runtime applications such as Steam, Lutris, Heroic, Bottles,
  Protontricks, and ProtonUp-Qt;
- host runtime helpers such as Gamescope, MangoHud, vkBasalt, GameMode,
  controller udev rules, and Vulkan layer files;
- full Steam Gaming Mode or gamescope-session support;
- kernel and sysctl policy.

Phase 1 uses GNOME as the normal desktop session. Steam Gaming Mode is future
image work, not a GNOME autostart. Bazzite is a reference for a mature Fedora
Atomic gaming image, but Margine Fedora Atomic should not silently become a
Bazzite rebase.

Rules:

- Flatpak is the first channel for game launchers in the manual lab;
- host helpers can be layered only after the hardware/media stack is validated;
- repeated host helpers should later move into a native image or bootc build;
- `kernel.split_lock_mitigate=0` is never enabled by installing a gaming
  runtime;
- NVIDIA and handheld-specific services stay outside the default profile.

The detailed plan is in `docs/11-gaming-runtime.md`.

## Kernel Strategy

The Fedora kernel is the stable baseline. The CachyOS kernel from COPR is an
experimental replacement tested in a separate deployment.

Phase 1 does not depend on:

- NVIDIA;
- akmods;
- ZFS;
- VirtualBox host modules;
- other out-of-tree modules;
- scripts that force the CachyOS kernel to remain the default forever.

The required fallback is a previous Fedora deployment, ideally pinned before the
kernel experiment.

Because Secure Boot is a target requirement, the Fedora kernel deployment is the
only compliant baseline until the CachyOS kernel boot path is proven under
Secure Boot. Disabling Secure Boot is allowed only as a clearly marked VM lab
exception, not as the product target.

## Boot Security

The target boot model is Fedora-native:

| Layer | Phase 1 position |
| --- | --- |
| UEFI Secure Boot | enabled for the stock Fedora baseline |
| Boot chain | Fedora shim, bootloader, and kernel first |
| Disk encryption | installer-created LUKS2 volume |
| Auto-unlock | `systemd-cryptenroll` TPM2 enrollment |
| Persistent config | `/etc/crypttab` and local initramfs policy as validated |
| Recovery | passphrase or recovery key remains enrolled |

Do not copy the Arch/CachyOS Margine Secure Boot stack. In particular, do not
start this project from Limine, `sbctl`, custom UKIs, or root-on-ZFS unlock
logic. Those ideas can be re-evaluated later only if Fedora's stock path fails a
specific requirement.

The TPM2 procedure must be staged after a successful encrypted Silverblue
install. rpm-ostree controls initramfs generation, so any dracut configuration
needed for TPM2 unlock must be validated through `rpm-ostree initramfs` rather
than by assuming a mutable Fedora Workstation `dracut -f` workflow.

## Update Orchestration

Routine updates use `scripts/update-all`.

The Atomic update boundary is different from the Arch/CachyOS one:

- no pacman;
- no AUR;
- no Snapper/ZFS boot environment creation;
- no Limine or UKI refresh path;
- no `sbctl` trust refresh.

The phase 1 order is:

1. validators;
2. diagnostics;
3. `rpm-ostree upgrade`;
4. Topgrade accessory updates or Flatpak fallback;
5. toolbox/distrobox status;
6. validators and diagnostics again;
7. explicit reboot guidance.

Topgrade is intentionally constrained. It may update accessory channels such as
Flatpak, containers, language toolchains, or editor plugins, but it must not own
`rpm-ostree`, `bootc`, firmware, Secure Boot, TPM2, or rollback policy.

The detailed plan is in `docs/12-update-orchestration.md`.

## bootc Position

bootc is relevant later because it supports transactional operating system
updates through bootable OCI container images. It is not the starting point.

Before bootc work, this project needs:

- a validated manual Silverblue lab;
- a minimal list of truly required host layers;
- a tested kernel strategy;
- a rollback model that has actually been used;
- a decision about registry, signing, build, and update workflow.

## Repository Boundaries

This repository is standalone. It must not import scripts, assumptions, or
configuration from:

- `/home/daniel/dev/margine-os`
- `/home/daniel/dev/margine-os-personal`

Ideas can be re-evaluated later, but they must be redesigned for Fedora Atomic
instead of copied over.
