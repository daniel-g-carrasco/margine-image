# ADR 0003 — Fedora-native boot security path

**Date:** 2026-05-22
**Status:** Accepted

## Context

Margine Personal (the existing CachyOS product) uses:

- **Limine** as the bootloader
- **sbctl** for Secure Boot key management
- **mkinitcpio** for initramfs generation
- **root-on-ZFS** as the storage layout

These components are tightly integrated. Porting them to Fedora Atomic would
require replacing or working around rpm-ostree's own initramfs management,
the Fedora-signed shim chain, and the ostree boot entry model. That path is
incompatible with the Fedora Atomic model by design.

The alternative is to accept the Fedora-native boot security path as the
starting point for this branch.

## Decision

Use the **Fedora-native Secure Boot and disk unlock path**:

- Fedora signed shim → Fedora signed GRUB → Fedora signed kernel
- LUKS2 for full-disk encryption
- `systemd-cryptenroll` for TPM2 auto-unlock enrollment
- `/etc/crypttab` with `tpm2-device=auto` option
- rpm-ostree-managed initramfs (not manual `dracut -f`)
- Passphrase or recovery key kept as a fallback alongside TPM2

Do not use Limine, sbctl, custom MOK keys, or manual mkinitcpio invocations
during phase 1.

## Rationale

**Limine and sbctl are incompatible with the ostree boot model.** The ostree
boot process manages its own boot entries, initramfs images, and kernel
arguments. Replacing GRUB with Limine or managing the shim chain with sbctl
would require working outside the rpm-ostree update path, making system
updates unsafe and rollback unreliable.

**rpm-ostree owns the initramfs.** Running `dracut -f` manually can produce an
initramfs that diverges from what rpm-ostree expects. When rpm-ostree generates
a new deployment, it manages the initramfs itself. Manual regeneration breaks
that invariant.

**The Fedora-signed chain is already validated.** Fedora's shim, GRUB, and
kernel binaries are signed by Fedora's key, which is trusted by most UEFI
firmware through the Microsoft UEFI CA. No custom key enrollment is needed for
the baseline. Custom key hierarchies are a future phase concern.

**`systemd-cryptenroll` integrates correctly with rpm-ostree.** Because
systemd-cryptenroll uses the TPM2 to bind a LUKS2 slot to the current boot
state, and because rpm-ostree regenerates initramfs on deployment, the
enrollment path must account for initramfs changes. This is documented in
Fedora guides and is a known-good procedure — unlike a custom initramfs flow.

**The Arch patterns do not transfer.** Margine Personal's Limine + sbctl +
root-on-ZFS + mkinitcpio configuration exists because those tools fit the
Arch/CachyOS update model. Importing that configuration to Fedora Atomic would
produce a system that can no longer use rpm-ostree safely.

## Consequences

- Limine, sbctl, mkinitcpio, and root-on-ZFS are explicitly rejected for
  phase 1 and documented in `docs/00-goals.md` and `docs/05-known-risks.md`.
- Custom MOK key enrollment is deferred to a future phase if needed.
- The initramfs is always managed by rpm-ostree; `dracut -f` is not run manually.
- TPM2 PCR policy is observed in the lab before being locked in; it is not
  assumed from the Arch experience.
- Rolling back a deployment must leave the TPM2 enrollment in a state that
  can still unlock the disk; this is tested before it becomes a hardware
  procedure.
