# ADR 0007 — Sealed Bootable Container Images: tracking + migration plan

**Status:** Watching (no action yet — Fedora upstream test phase)
**Date:** 2026-06-07
**Supersedes:** none. Coexists with [ADR 0003 (Fedora-native boot security)](0003-fedora-native-boot-security.md) and [ADR 0006 (kernel CachyOS via COPR)](0006-kernel-cachyos-decision.md) — both will need revision when Sealed Images go production stable.

## Context

In April 2026 Fedora and the bootc team announced **Sealed Bootable
Container Images** — the most fundamental change to Fedora Atomic
Desktops since they replaced rpm-ostree-based deployments with OCI
bootable containers. Bluefin's Spring 2026 announcement called it
"the most fundamental change to Bluefin in its 5-year history".

The technology stack:

- **`systemd-boot`** replaces GRUB as the bootloader.
- **UKI (Unified Kernel Image)** — kernel + initrd + kernel cmdline
  bundled into a single signed EFI binary. No more separate vmlinuz +
  initramfs.img on the ESP.
- **`composefs` + `fs-verity`** — the OS root filesystem becomes
  cryptographically verified at read time. Every page-read of any
  `/usr` file is checked against an fs-verity Merkle tree whose root
  hash is signed by the image vendor.
- **Both systemd-boot and the UKI are Secure-Boot-signed.** Combined
  with composefs fs-verity, this delivers a **fully verified boot
  chain** from firmware to userspace.
- **TPM2 passwordless disk unlock becomes "reasonably secure by
  default"** — because the chain measured into TPM PCRs is no longer
  trivially mutable (the previous problem was that initramfs and
  kernel command line on the ESP were too easy to swap), so sealing
  a LUKS key to PCR 7 + PCR 11 is meaningful.

Status as of 2026-06-07:
- **Test images** published at `github.com/travier/fedora-atomic-desktops-sealed`
- Test images use unsigned-by-Fedora keys (sign yourself or accept dev keys)
- Documented at <https://tim.siosm.fr/blog/2026/04/28/sealed-atomic-desktops-test-images/>
- Bluefin discussion on adoption: <https://github.com/ublue-os/bluefin/discussions/4607>
- `bootc-dev/bootc` composefs-native backend tracked at
  <https://github.com/bootc-dev/bootc/issues/1190>

## What this means for Margine

Margine's current `custom-kernel/install.sh` (derived from Origami
Linux, see [`docs/upstream-inspirations.md`](../upstream-inspirations.md))
does the following at OCI build time:

1. `dnf install kernel-cachyos kernel-cachyos-core ...` from COPR
2. `sbsign` the `vmlinuz` with the Margine MOK
3. `sign-file` every `*.ko` module (gz/xz/zst-compressed too)
4. Write `mok-enroll.service` (one-shot first-boot service that
   imports MOK.der into shim's MOK store)
5. Regenerate initramfs with `dracut --add ostree`

Under sealed images this pipeline **does not work** as-is:

- **vmlinuz + .ko separate signing is replaced by signing the UKI
  binary.** The UKI bundles a particular kernel + a particular
  initramfs + a particular cmdline; signing happens on the bundle,
  not on the components. We need `sbsign` on the UKI output of
  `ukify` (systemd tool that builds UKIs).
- **Per-module sign-file is no longer the relevant trust path.**
  Modules are loaded via the same kernel that the UKI signed for,
  and module loading policy is enforced by the kernel's `module.sig_enforce`
  + the keys baked into the kernel image at build time.
- **The MOK enrollment dance disappears.** Sealed images use keys
  shipped in shim's vendor DB, signed by Fedora upstream. No more
  MOK Manager screen on first boot. (For custom kernels from non-
  Fedora COPRs, we'll either piggyback on Fedora's signing pipeline
  or run our own UKI signing with a CA enrolled in shim — TBD.)
- **GRUB is gone.** Our current image inherits GRUB config from
  Bluefin DX; this changes to `systemd-boot` entries (Boot Loader
  Spec format). Plymouth integration changes (BLS entries vs GRUB
  menu).
- **`/etc` overlay model.** Sealed images keep `/etc` writable at
  runtime, but `/usr` is fs-verity-verified. Any current Margine
  step that writes into `/usr` at OCI build time keeps working
  (build time is pre-seal), but runtime `/usr` modification (which
  rpm-ostree layered packages do today) gets more invasive — the
  composefs layer above the sealed `/usr` has to be re-verified,
  and `bootc upgrade` re-seal logic changes.

The opt-in gaming layer (`ujust margine-gaming`,
`ujust margine-gaming-native`) is the most affected end-user feature
because it adds rpm-ostree layered packages — exactly the workflow
that becomes more friction under sealed images. We may need to:
- Bake the gaming RPM set into a second OCI variant (re-introducing
  what we retired 2026-06-06 in [`feat/gaming-iso-and-variant-kill`](../audits/2026-06-05-margine-stack-audit.md)), or
- Document the trade-off ("layering is supported but re-seals on
  every upgrade, adding 60-120s") so users on sealed Margine know.

## Action triggers — what to watch for

When any of these fires, **revisit this ADR and start scoping work**:

1. **Bluefin/Bazzite/Aurora ships a sealed-image branch as the
   default `:stable` tag.** Today they're test images; this is the
   one signal that says "the rest of Universal Blue is moving."
   Watch: <https://github.com/ublue-os/bluefin/discussions/4607> and
   `git log` of `ublue-os/bluefin`. The
   `scripts/check-upstreams.sh` cron flags Bluefin activity monthly.
2. **Fedora 45 release stable with sealed Atomic Desktop variants**
   as a supported flavour. Track:
   <https://fedoraproject.org/wiki/Releases/45/Schedule> +
   discussion.fedoraproject.org.
3. **bootc 2.0 release** with composefs-native backend stable.
   Track: <https://github.com/bootc-dev/bootc/releases>.
4. **`travier/fedora-atomic-desktops-sealed` repo moves from
   "test" to "production":** the README drops the "test only"
   warning + signing keys move from dev to Fedora-official. Watch:
   <https://github.com/travier/fedora-atomic-desktops-sealed>
   (added to `scripts/check-upstreams.sh` watchlist in this ADR's
   companion commit).
5. **CachyOS upstream publishes UKI signing recipes** or the
   `bieszczaders/kernel-cachyos` COPR adds `*-uki` packages —
   makes our migration ~10× easier.

## Migration plan sketch (to be expanded when triggers fire)

When two of the five triggers above have fired, allocate ~2 weeks
for the migration:

1. **Inventory current signing surface** (`custom-kernel/install.sh`
   + `mok-enroll.service` + GRUB config + initrd hooks).
2. **Prototype a Margine sealed-image Containerfile** alongside the
   current one. Use Bluefin's sealed test image as the new `FROM`.
3. **Replace the per-module signing block with `ukify build` +
   `sbsign`** on the resulting UKI binary, using the Margine MOK
   as the signing key.
4. **Drop `mok-enroll.service`.** First-boot UX no longer has the
   MOK Manager screen (good — saves the "passphrase margine-os"
   workflow). Document the change in `/docs/first-boot` on the
   site (currently the central place we teach the MOK step).
5. **Replace GRUB config with systemd-boot loader entries.**
   Inherit Bluefin's systemd-boot integration where possible.
6. **Validate TPM2 auto-unlock as default.** Drop the
   "manual systemd-cryptenroll post-install" procedure currently in
   `docs/07-secure-boot-tpm2.md`; replace with "it just works".
7. **Re-test the `ujust margine-gaming{,-native}` recipes** on a
   sealed deployment — measure the re-seal cost on
   `bootc upgrade` and document.
8. **Smoke-test the new ISO + LUKS + TPM2 flow** end-to-end in a
   fresh VM.
9. **Cut a new stable promotion** when CI smoke-boot passes.

## What we are NOT doing now

- Switching to sealed images today. The test images use unsigned-by-
  Fedora keys; running them on a production install is not
  responsible.
- Pre-emptively rewriting `custom-kernel/install.sh` for UKI. The
  test images may change shape before stable; rewriting now risks
  having to redo it.
- Disabling MOK enrollment. The current chain works under stock
  Fedora 44 sealed-NOT environment; until sealed is the default,
  MOK is the right answer.

## Periodic review

- **Monthly**: the auto-cron `scripts/check-upstreams.sh` issue (see
  [`docs/upstream-inspirations.md`](../upstream-inspirations.md))
  will surface activity in the sealed-images repo.
- **Quarterly**: re-read this ADR. If any "Action trigger" has
  fired, write a follow-up "Migration in progress" ADR (0008)
  and link it here.

## References

- Bluefin Spring 2026 announcement: <https://docs.projectbluefin.io/blog/bluefin-spring-2026/>
- Siosm's blog: <https://tim.siosm.fr/blog/2026/04/28/sealed-atomic-desktops-test-images/>
- Fedora Magazine: <https://fedoramagazine.org/sealed-atomic-desktops-test-images/>
- bootc composefs backend: <https://github.com/bootc-dev/bootc/issues/1190>
- Test image repo: <https://github.com/travier/fedora-atomic-desktops-sealed>
- Bluefin discussion: <https://github.com/ublue-os/bluefin/discussions/4607>
