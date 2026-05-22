# Update Orchestration

Margine Fedora Atomic needs a new update model. The old Arch/CachyOS
`update-all` is not portable because it owns pacman, AUR, Snapper/ZFS, Limine,
UKIs, and Secure Boot refresh paths that do not exist in the same form on
Fedora Atomic.

The new model keeps the useful idea: one canonical maintenance command that
orders the work and makes failure boundaries visible.

## Decision

Use `scripts/update-all` as the Margine orchestrator.

Use Topgrade only for accessory channels.

Do not let Topgrade own:

- `rpm-ostree upgrade`;
- `bootc update`;
- firmware updates;
- Secure Boot or TPM2 policy;
- kernel fallback decisions;
- rollback instructions;
- diagnostics and validation.

## Why Not Topgrade Alone

Topgrade is good at broad user-space maintenance. It can update Flatpaks,
containers, language ecosystems, editor plugins, and many package-manager
families. It also has configuration switches for Fedora Atomic paths such as
`rpm_ostree` and `bootc`.

That is exactly why Margine should constrain it. On this project, the base OS
update is not just another package-manager step. It creates a deployment, may
stage a new kernel, requires reboot judgment, and must remain compatible with
Secure Boot, TPM2 unlock, rollback, the CachyOS kernel experiment, and future
image work.

## Phase Order

The Atomic `update-all` phase order is:

1. preflight;
2. pre-update validators;
3. pre-update diagnostics;
4. `rpm-ostree upgrade`;
5. accessory updates through Topgrade or direct Flatpak fallback;
6. toolbox/distrobox status;
7. post-update validators;
8. post-update diagnostics;
9. summary and reboot instruction.

Hard failures:

- missing `rpm-ostree` when system updates are enabled;
- failed `rpm-ostree upgrade`;
- failed `rpm-ostree status`;
- failed atomic layout validation.

Soft failures:

- Topgrade failure;
- Flatpak fallback failure;
- hardware/media or gaming validator warnings;
- diagnostics collection failure;
- toolbox/distrobox inspection failure.

The script exits with:

- `0` when all phases pass;
- `1` on hard failure;
- `2` when the base path completed but soft failures occurred.

## Topgrade Profile

The reference config is:

```text
config/topgrade.toml
```

It intentionally disables:

```toml
[misc]
disable = [
  "system",
  "firmware",
]

[linux]
rpm_ostree = false
bootc = false
```

This keeps Topgrade in the accessory role even if it supports those features.

In the VM lab, install the profile manually if Topgrade should use it as the
user config:

```sh
mkdir -p ~/.config
cp config/topgrade.toml ~/.config/topgrade.toml
```

Even with a user config, `scripts/update-all` still calls Topgrade with:

```sh
topgrade --disable system firmware
```

The command-line guard is deliberate because a local user config may drift.

## Direct Flatpak Fallback

If Topgrade is not installed, `scripts/update-all` falls back to:

```sh
flatpak update
```

This is a soft phase. A Flatpak failure should be visible, but it should not be
treated like a broken base deployment.

## Toolbox and Distrobox

Phase 1 only records:

```sh
toolbox list
distrobox list
```

Do not auto-update every toolbox or distrobox until containers are declared. A
future implementation can update only named containers from the declaration.

## Firmware

Firmware is not updated by this script in phase 1.

Reason:

- firmware can affect Secure Boot, TPM2, devices, and recovery;
- firmware update behavior differs by machine;
- the lab needs an explicit firmware runbook before it becomes routine
  automation.

## bootc

bootc means bootable containers.

In practical terms, a bootc system gets the operating system from an OCI
container image that is bootable. The image contains the OS content needed to
boot, including kernel-related content. Updates are transactional and are
applied as image updates with rollback semantics.

For Margine, bootc is the likely future path when the profile becomes stable:

- host packages move from client-side rpm-ostree layering into a Containerfile;
- gaming helpers, media runtimes, fonts, and host services become image content;
- the VM installs or switches to the built image;
- updates become "build a new image, publish it, update the host".

What bootc is not:

- not a replacement for the phase 1 Silverblue lab;
- not a Flatpak/toolbox replacement;
- not a way to hide unvalidated host changes;
- not where TPM2 secrets, recovery keys, or private tokens belong.

Current policy:

- `scripts/update-all` does not run `bootc update`;
- `config/topgrade.toml` keeps `bootc = false`;
- bootc remains phase 4 image work, after manual Silverblue validation.

## Commands

Dry run:

```sh
scripts/update-all --dry-run
```

Full routine on the Silverblue VM:

```sh
scripts/update-all
```

Skip accessory updates:

```sh
scripts/update-all --no-topgrade --no-flatpak-fallback
```

Update only accessory channels after a known-good deployment:

```sh
scripts/update-all --no-system
```

## References

- Topgrade repository and example config: https://github.com/topgrade-rs/topgrade
- Topgrade `config.example.toml`: https://github.com/topgrade-rs/topgrade/blob/main/config.example.toml
- rpm-ostree administrator handbook: https://coreos.github.io/rpm-ostree/administrator-handbook/
- Fedora/CentOS bootc docs: https://fedora.gitlab.io/bootc/docs/bootc/
- bootc project: https://bootc.dev/
