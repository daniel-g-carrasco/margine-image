# Goals

Margine is a versioned system definition: manifests describe intent, validators
prove the result, and recovery paths stay part of the normal workflow. This
repository is the Fedora Atomic branch of that project family.

This document defines what this branch is trying to accomplish and the gates
that must pass before each phase advances. For architectural decisions, see
[docs/adr/](adr/). For the phase plan, see [docs/roadmap.md](roadmap.md).

This project explores a Fedora Atomic variant of Margine OS without reusing the
existing Arch/CachyOS architecture as a hidden default.

The first deliverable is not a bootable Margine image. The first deliverable is
a verified lab model: what Fedora Silverblue provides, what must remain local
state, how Btrfs is laid out, how host-level changes are staged, and how rollback
works after replacing the kernel. The second deliverable is a declarative source
of truth that describes the desired system without pretending that every channel
is managed the same way.

## Primary Goal

Build an experimental Margine base on Fedora Silverblue with GNOME, Btrfs,
rpm-ostree, Secure Boot, TPM2 automatic disk unlock, and an optional CachyOS
kernel from COPR, starting from a manual VM lab.

## Technical Goals

- Use Fedora Silverblue as the actual base system.
- Keep GNOME stock during phase 1.
- Validate the ostree filesystem model:
  - root and `/usr` come from the deployment;
  - `/etc` is writable host configuration;
  - `/var` is writable persistent host state;
  - `/home` is expected to resolve through `/var/home`.
- Validate Fedora's Btrfs layout instead of designing storage from memory.
- Validate Secure Boot with the stock Fedora Silverblue boot path before any
  third-party kernel work.
- Validate TPM2-based automatic unlock for the encrypted system while keeping a
  passphrase or recovery-key fallback.
- Rebuild the personal layer for GNOME: home layout, XDG dirs, fonts, icons,
  and theme settings.
- Rebuild the hardware/media layer for Fedora Atomic: Intel and AMD open
  drivers, Mesa, VA-API, Vulkan, OpenCL, Rusticl, ROCm, PipeWire, WirePlumber,
  and media diagnostics.
- Integrate a desktop gaming runtime inspired by Margine Personal and Bazzite,
  while keeping launchers, host runtime helpers, Game Mode, and kernel policy as
  separate layers.
- Define a declarative profile for the system after the manual lab has produced
  real evidence.
- Keep Flatpak, toolbox/distrobox, and rpm-ostree layering as separate channels.
- Test the CachyOS kernel from COPR only as a reversible lab experiment.
- Keep a Fedora kernel deployment available as the fallback path.
- Provide a Fedora Atomic `update-all` that coordinates rpm-ostree, validators,
  diagnostics, and accessory updates without hiding reboot or rollback state.
- Record diagnostics before and after the kernel experiment.

## Non-Goals

- No edits to `/home/daniel/dev/margine-os`.
- No edits to `/home/daniel/dev/margine-os-personal`.
- No Arch, pacman, AUR, or CachyOS distribution assumptions.
- No root-on-ZFS logic.
- No Hyprland, Waybar, Walker, or Lua configuration in phase 1.
- No NVIDIA support as an initial default.
- No proprietary or out-of-tree driver stack as a phase 1 default.
- No RPM Fusion codec replacement as a hidden baseline decision.
- No DaVinci Resolve support claim in the baseline.
- No hidden gaming sysctl policy such as implicit `kernel.split_lock_mitigate=0`.
- No Steam Gaming Mode or Bazzite rebase as the first GNOME phase.
- No Topgrade ownership of rpm-ostree, bootc, firmware, Secure Boot, TPM2, or
  rollback policy.
- No copied Arch/Limine/sbctl Secure Boot or TPM2 flow.
- No custom Secure Boot key hierarchy until the stock Fedora path has been
  validated.
- No AUR font, icon, or theme packages as phase 1 dependencies.
- No Hyprland/Waybar/Walker/Fuzzel theme artifacts in the GNOME baseline.
- No NixOS-style promise of full-system convergence in phase 1.
- No custom declaration language before YAML/TOML plus validation proves
  insufficient.
- No native ostree compose, bootc image, or installer automation before the VM
  lab is understood.

## Working Hypotheses

- Fedora Silverblue already provides the atomic desktop base needed for the
  first experiment.
- Fedora's default Btrfs desktop layout is good enough for phase 1 unless the
  lab proves otherwise.
- Fedora's signed shim, bootloader, and kernel path should provide the initial
  Secure Boot baseline.
- TPM2 auto-unlock can be added through LUKS2, `systemd-cryptenroll`, and
  `/etc/crypttab`, but the rpm-ostree initramfs path must be verified in the VM
  before it becomes a hardware procedure.
- The CachyOS COPR kernel can be evaluated with rpm-ostree while keeping a
  Fedora deployment available for rollback, but it is not target-compliant if
  Secure Boot must be disabled permanently.
- Most user-facing applications should be installed as Flatpaks.
- Development tools should usually live in toolbox or distrobox.
- rpm-ostree layering should be rare and reserved for host-level requirements.
- Host graphics, VA-API, Vulkan, and OpenCL components still need host-level
  validation because Flatpak applications depend on the exposed host driver
  stack.
- Bazzite is a useful Fedora Atomic gaming reference, but Margine should borrow
  its image-first/runtime ideas rather than inherit all of its image policy by
  default.
- Topgrade can update accessory channels, but Margine still needs a local
  orchestrator for the base OS update boundary and post-update validation.
- A useful declarative model can be built as desired-state files plus
  channel-specific adapters instead of a single universal installer script.

## Decision Gates

Do not move to image work until all of these are true:

- A Fedora Silverblue VM has been installed from official media.
- The VM has been updated and rebooted into the updated deployment.
- `scripts/validate-atomic-layout` has been run and reviewed.
- A baseline diagnostic bundle has been collected.
- The stock Fedora deployment has been validated with Secure Boot enabled.
- TPM2 auto-unlock has been tested with manual passphrase recovery still
  available.
- The draft declaration under `declarations/` matches the observed lab
  decisions.
- The CachyOS kernel test has been performed or explicitly deferred.
- Rollback to a Fedora kernel deployment has been tested.
- Observed risks are documented in `docs/05-known-risks.md`.

## Initial Decision

Start with Fedora Silverblue 44 on x86_64 in a UEFI VM, using the installer
defaults for GNOME and storage unless the lab produces a concrete reason to
change them.
