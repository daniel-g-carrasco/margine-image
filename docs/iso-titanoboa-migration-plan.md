# ISO build: Anaconda kickstart vs titanoboa hooks

> **Decision (2026-06-06):** **Keep the current Anaconda kickstart path.**
> Audit 2026-06-05 §6.9 + §3.5 originally framed this as
> "DEFERRED → next supervised session". After a concrete benefits-vs-
> cost analysis the conclusion is now: **don't migrate unless a
> concrete reason emerges**. This file documents the evaluation so the
> decision is on record and re-openable when conditions change.
>
> Status: **Evaluated → SKIP** (was: deferred).

## What Margine ships today

- `bootc-image-builder --type anaconda-iso` driven by
  `disk_config/iso-gnome.toml` (Anaconda kickstart embedded inline).
- Custom Bazzite-pattern `installer/` (Containerfile + build.sh +
  flatpaks-{base,gaming}) builds a transient `<flavor>-installer`
  OCI image with Flatpaks pre-baked into `/var/lib/flatpak`. Anaconda
  kickstart `%post --nochroot` rsyncs that into the target.
- `bootc switch --mutate-in-place` in `%post` points the freshly
  installed system at our public registry.
- btrfs `zstd:1` compression set in a second `%post`.

The path works. Last good ISO: `margine-anaconda-iso-20260603` on
Internet Archive, verified bootable in QEMU.

## What titanoboa would change

Bazzite migrated their `installer/` to a 4-piece pattern in mid-2025:

| File | Lines (Bazzite HEAD) | Role |
|---|---|---|
| `installer/iso.yaml` | ~10 | ISO label + grub2 boot entries |
| `installer/Containerfile` | ~17 | Same shape Margine already uses |
| `installer/build.sh` | ~130 | Same shape Margine already uses |
| `installer/titanoboa_hook_preinitramfs.sh` | ~30 | Kernel swap to vanilla for Secure Boot |
| `installer/titanoboa_hook_postrootfs.sh` | ~315 | Embedded Anaconda kickstart + Bitlocker detect + SB QR docs + flatpak-restore-selinux-labels |

The first three Margine **already does today**. The two hook files
are the new surface area.

## Per-feature analysis

| Bazzite feature | Margine concrete value |
|---|---|
| Bitlocker partition GUI prompt with QR docs (qrencode + yad) | **None.** Margine's ICP target is Framework 13 AMD; the Bazzite use case is gamers dual-booting Windows + BitLocker, which Margine isn't optimizing for. |
| Secure Boot key fetch + QR documentation | **Partial.** Margine does not need Bazzite's QR/user-doc prompt, but ISO installs must submit the MOK import request from Anaconda before the first post-install reboot. `mok-enroll.service` remains the rebase and missed-prompt fallback. |
| Kernel swap to vanilla pre-initramfs | **None.** The Margine kernel is already MOK-signed in `margine:stable`; Bazzite needs this because they ship an unsigned vanilla kernel and swap to vanilla for SB compliance. |
| Anaconda profile customization (modifying `/usr/share/anaconda/interactive-defaults.ks` at runtime) | **Cosmetic.** Could let us rename "Bazzite release" → "Margine release", drop irrelevant prompts, etc. Doable inside the current kickstart too. |
| `disable-fedora-flatpak.ks` + `flatpak-restore-selinux-labels.ks` | **None.** Margine uses the BAKE+DEFER Flatpak design (PR D + dedupe PR #45), not Bazzite's `flatpak-add-fedora-repos.service` / restore-labels chain. |

## What titanoboa does NOT remove

Note for the record: titanoboa **does not eliminate Anaconda**. The
Bazzite hook embeds Anaconda via `cat >> /usr/share/anaconda/interactive-
defaults.ks`. The user-visible installer is still the Anaconda
graphical flow. Migration is "Anaconda + hooks" vs "Anaconda +
kickstart" — same Anaconda underneath.

## Cost of migration

- ~80 lines of Margine-specific `titanoboa_hook_postrootfs.sh` (subset
  of Bazzite's 315 lines)
- 1 small `iso.yaml`
- `build-disk.yml` BIB invocation refactor
- New manual ISO smoke test step per iteration (we have no automated
  `qemu-system-x86_64 -drive file=install.iso` in CI today)
- Risk: upstream titanoboa has no canonical public-facing
  documentation. The Bazzite implementation is a moving target.

## Decision

**Keep `disk_config/iso-gnome.toml` Anaconda kickstart.**
Audit §6.9 and §3.5 close as "evaluated → keep current path", not
"DEFERRED, will-do-soon".

## When to re-open

Re-evaluate when **any** of these become true:

1. `osbuild/bootc-image-builder` deprecates `--type anaconda-iso`
   support, OR
2. Bazzite or `ublue-os/main` publishes a canonical titanoboa
   migration guide (reduces design-decision surface from
   "every line is novel" to "follow the recipe"), OR
3. A specific Margine user need that the current Anaconda kickstart
   cannot serve (Bitlocker-class detection, custom GUI prompts,
   per-flavor Anaconda profile branding) becomes part of the
   shipping ICP.

The `scripts/check-upstreams.sh` monthly cron in
`margine-fedora-atomic` already watches `ublue-os/bazzite` for
commits; the workflow opens a tracking issue if there's significant
activity. That's the existing channel for surfacing condition #1
or #2.

## Reference

- Audit 2026-06-05 §6.9 + §3.5
- Audit status delta (2026-06-06): records this evaluation as the
  closure of §6.9 / §3.5
- Bazzite installer: <https://github.com/ublue-os/bazzite/tree/main/installer>
- Original Margine anaconda kickstart: `disk_config/iso-gnome.toml`
