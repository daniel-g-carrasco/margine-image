# Margine Fedora Atomic

Margine Fedora Atomic is an experimental Margine OS variant based on Fedora
Atomic Desktop, starting with Fedora Silverblue and GNOME.

This repository is intentionally separate from the existing Arch/CachyOS work.
It does not depend on, import from, or modify:

- `/home/daniel/dev/margine-os`
- `/home/daniel/dev/margine-os-personal`

## Current Phase

Phase 1 is a manual VM lab.

The goal is not to build an installable image yet. The goal is to understand and
validate Fedora Atomic Desktop as it actually behaves: rpm-ostree deployments,
the writable state model, Btrfs layout, Secure Boot, TPM2-based disk unlock,
Flatpak/toolbox workflows, and rollback after an experimental kernel change.

As of 2026-05-22, the current Fedora Silverblue target is Fedora Silverblue 44,
released on 2026-04-28.

## Design Principles

- Fedora Silverblue is the base, not Arch with different tooling.
- GNOME stays stock in the first phase.
- Root and `/usr` are owned by ostree/rpm-ostree.
- `/etc` and `/var` are the writable host state.
- `/home` is normally exposed through `/var/home`.
- Btrfs must be validated in the Fedora layout, not treated like Margine's
  previous root-on-ZFS work.
- Secure Boot and TPM2 automatic disk unlock are target requirements, but they
  must be implemented through Fedora-native boot, LUKS2, systemd, and rpm-ostree
  mechanisms.
- Intel and AMD graphics, audio, video, VA-API, Vulkan, OpenCL, Rusticl, and
  ROCm support are Fedora-native host/media layers, not copied Arch package
  manifests.
- The CachyOS kernel from COPR is experimental and must have a Fedora kernel
  fallback through rpm-ostree rollback.
- NVIDIA, ZFS, akmods, and other out-of-tree modules are explicit risks, not
  defaults.
- Flatpak/Flathub, toolbox/distrobox, and rpm-ostree layering are separate
  software channels.
- The project should become declarative, but channel-aware: declarations are the
  source of truth, while rpm-ostree, Flatpak, toolbox, dconf, systemd, and home
  provisioners remain separate execution adapters.
- Routine updates go through a Margine orchestrator. Topgrade is allowed only as
  an accessory updater, not as the owner of rpm-ostree, bootc, firmware, Secure
  Boot, TPM2, or rollback policy.
- Hyprland, Lua, Waybar, and Walker are out of scope for phase 1.

## Initial Roadmap

1. Install Fedora Silverblue in a VM with the Fedora-provided layout.
2. Record a clean baseline before third-party repositories.
3. Validate the atomic filesystem model and Btrfs backing layout.
4. Validate the stock Fedora Secure Boot path.
5. Validate TPM2 automatic unlock while keeping passphrase recovery.
6. Convert observed decisions into declarative profile files.
7. Enable the CachyOS COPR only in the lab.
8. Test a CachyOS kernel deployment with a pinned Fedora fallback.
9. Prove rollback to the Fedora kernel.
10. Only then evaluate a native atomic image, bootc image, or automation layer.

## Repository Layout

- [docs/00-goals.md](docs/00-goals.md): goals, non-goals, and decision gates.
- [docs/01-architecture.md](docs/01-architecture.md): Fedora Atomic model.
- [docs/02-install-lab.md](docs/02-install-lab.md): manual VM lab flow.
- [docs/03-cachyos-kernel.md](docs/03-cachyos-kernel.md): CachyOS COPR test plan.
- [docs/04-validation.md](docs/04-validation.md): validation commands and pass criteria.
- [docs/05-known-risks.md](docs/05-known-risks.md): known risks and mitigations.
- [docs/06-personal-migration-assessment.md](docs/06-personal-migration-assessment.md): what can be carried over from Margine Personal.
- [docs/07-secure-boot-tpm2.md](docs/07-secure-boot-tpm2.md): Secure Boot and TPM2 auto-unlock plan.
- [docs/08-gnome-personal-layer.md](docs/08-gnome-personal-layer.md): fonts, themes, icons, and home layout plan.
- [docs/09-declarative-model.md](docs/09-declarative-model.md): declarative operating model.
- [docs/10-hardware-media-stack.md](docs/10-hardware-media-stack.md): drivers, audio, video, VA-API, Vulkan, OpenCL, Rusticl, and ROCm plan.
- [docs/11-gaming-runtime.md](docs/11-gaming-runtime.md): desktop gaming runtime, Bazzite lessons, Gamescope, launchers, and validation.
- [docs/12-update-orchestration.md](docs/12-update-orchestration.md): Atomic `update-all`, Topgrade, and bootc position.
- [docs/13-ai-validation-prompt.md](docs/13-ai-validation-prompt.md): reusable AI audit prompt for all Margine repos.
- [config/topgrade.toml](config/topgrade.toml): Topgrade accessory-update profile.
- [declarations/](declarations/): draft desired-state declarations, not yet applied automatically.
- [scripts/update-all](scripts/update-all): Fedora Atomic update orchestrator.
- [scripts/validate-atomic-layout](scripts/validate-atomic-layout): read-only host layout checks.
- [scripts/validate-cachyos-kernel](scripts/validate-cachyos-kernel): CachyOS kernel checks.
- [scripts/validate-hardware-media-stack](scripts/validate-hardware-media-stack): read-only hardware, media, and compute checks.
- [scripts/validate-gaming-runtime](scripts/validate-gaming-runtime): read-only gaming runtime checks.
- [scripts/collect-diagnostics](scripts/collect-diagnostics): local diagnostic bundle.

## Lab Usage

Inside the Fedora Silverblue VM:

```sh
git clone <this-repo> ~/dev/margine-fedora-atomic
cd ~/dev/margine-fedora-atomic

scripts/validate-atomic-layout
scripts/validate-hardware-media-stack
scripts/validate-gaming-runtime
scripts/collect-diagnostics
scripts/update-all --dry-run
```

After the CachyOS kernel test:

```sh
scripts/validate-cachyos-kernel
scripts/collect-diagnostics
```

The scripts are observational. They do not install packages, change boot
configuration, or modify rpm-ostree deployments. `collect-diagnostics` writes
local output under `diagnostics/`, which is ignored by Git.

## Primary References

- Fedora Atomic Desktops: https://fedoraproject.org/atomic-desktops/
- Fedora Silverblue: https://fedoraproject.org/atomic-desktops/silverblue/
- Fedora Silverblue 44 download: https://fedoraproject.org/atomic-desktops/silverblue/download/
- Fedora Silverblue technical information: https://docs.fedoraproject.org/en-US/fedora-silverblue/technical-information/
- Fedora Silverblue getting started: https://docs.fedoraproject.org/en-US/fedora-silverblue/getting-started/
- Fedora Silverblue updates and rollbacks: https://docs.fedoraproject.org/en-US/fedora-silverblue/updates-upgrades-rollbacks/
- rpm-ostree: https://coreos.github.io/rpm-ostree/
- rpm-ostree administrator handbook: https://coreos.github.io/rpm-ostree/administrator-handbook/
- Fedora Btrfs wiki: https://fedoraproject.org/wiki/Btrfs
- Fedora Btrfs by default change: https://fedoraproject.org/wiki/Changes/BtrfsByDefault
- Fedora Secure Boot: https://fedoraproject.org/wiki/Secureboot
- systemd-cryptenroll manual: https://www.freedesktop.org/software/systemd/man/latest/systemd-cryptenroll.html
- crypttab manual: https://www.freedesktop.org/software/systemd/man/latest/crypttab.html
- Fedora Magazine TPM2/systemd-cryptenroll guide: https://fedoramagazine.org/use-systemd-cryptenroll-with-fido-u2f-or-tpm2-to-decrypt-your-disk/
- Mesa Rusticl documentation: https://docs.mesa3d.org/rusticl.html
- Fedora `mesa-libOpenCL`: https://packages.fedoraproject.org/pkgs/mesa/mesa-libOpenCL/index.html
- Fedora `libva-intel-media-driver`: https://packages.fedoraproject.org/pkgs/intel-media-driver-free/libva-intel-media-driver/
- Fedora `intel-compute-runtime`: https://packages.fedoraproject.org/pkgs/intel-compute-runtime/intel-compute-runtime/fedora-44.html
- Fedora `rocminfo`: https://packages.fedoraproject.org/pkgs/rocminfo/rocminfo/index.html
- Fedora `pipewire`: https://packages.fedoraproject.org/pkgs/pipewire/pipewire/
- Fedora `wireplumber`: https://packages.fedoraproject.org/pkgs/wireplumber/wireplumber/
- Bazzite and Fedora Atomic comparison: https://docs.bazzite.gg/General/Fedora_Atomic_Comparison/
- Bazzite package layering guidance: https://docs.bazzite.gg/Installing_and_Managing_Software/rpm-ostree/
- Bazzite Steam Gaming Mode overview: https://docs.bazzite.gg/Handheld_and_HTPC_edition/Steam_Gaming_Mode/
- Bazzite repository: https://github.com/ublue-os/bazzite
- Fedora Gamescope documentation: https://docs.fedoraproject.org/en-US/gaming/gamescope/
- Topgrade repository and example config: https://github.com/topgrade-rs/topgrade
- Fedora/CentOS bootc docs: https://fedora.gitlab.io/bootc/docs/bootc/
- bootc project: https://bootc.dev/
- COPR docs: https://docs.copr.fedorainfracloud.org/
- COPR enable docs: https://docs.pagure.org/copr.copr/how_to_enable_repo.html
- CachyOS Fedora COPR packaging: https://github.com/CachyOS/copr-linux-cachyos
- CachyOS kernel docs: https://wiki.cachyos.org/features/kernel/
