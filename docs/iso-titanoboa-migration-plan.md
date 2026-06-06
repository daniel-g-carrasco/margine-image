# ISO build modernization plan — titanoboa hooks

> **Status (2026-06-06):** Margine ships its ISO via
> `bootc-image-builder --type anaconda-iso` + an Anaconda kickstart
> embedded in `disk_config/iso-gnome.toml`. This is the **historical
> Bazzite pattern**. Bazzite themselves moved off it in mid-2025 to
> their own
> [`installer/titanoboa_hook_*.sh`](https://github.com/ublue-os/bazzite/tree/main/installer)
> pattern + `installer/iso.yaml`. Audit 2026-06-05 §6.9 + §3.5 flagged
> Margine's anaconda-iso path as ~12 months behind upstream.
>
> This file describes the migration plan. It is not active yet — see
> "Why this is deferred" below.

## Goal

Replace `disk_config/iso-gnome.toml` (Anaconda kickstart) with:

1. `installer/iso.yaml` — ~10 lines, describes ISO label + grub2 boot
   entries.
2. `installer/titanoboa_hook_preinitramfs.sh` — Bazzite version (~30
   lines) swaps the kernel back to vanilla for Secure Boot. **Margine
   does NOT need this** (our kernel is already MOK-signed in
   `margine:stable`), so the hook is either a no-op or omitted.
3. `installer/titanoboa_hook_postrootfs.sh` — Bazzite version is 315
   lines and embeds an Anaconda kickstart + Bitlocker detection +
   Secure Boot QR documentation + Bazzite-specific flatpak-restore-
   selinux-labels.ks. Margine needs a much smaller variant:
   - `bootc switch --mutate-in-place` to our public registry (already
     done by current kickstart)
   - btrfs `zstd:1` compression (already done)
   - NO Bitlocker prompt (Margine's ICP is Framework 13, no Windows
     coexistence by default)
   - NO Secure Boot QR (handled by `mok-enroll.service` at first
     boot)
   - NO flatpak-restore-selinux-labels (Margine uses BAKE+DEFER, not
     install-time flatpak)

   Resulting hook ~50-80 lines.
4. **`build-disk.yml` change**: replace
   `bootc-image-builder-action` ISO config-file from
   `./disk_config/iso-gnome.toml` to invoking `bootc-image-builder`
   with `installer/iso.yaml` + the titanoboa hooks at appropriate
   stages. May require a different invocation pattern than the action
   currently uses.

## What stays unchanged

- `installer/Containerfile` — already mirrors Bazzite verbatim.
- `installer/build.sh` — already mirrors Bazzite verbatim (including
  the `mkdir -p "$(realpath /root)"` + `mount -o remount,rw /proc/sys`
  workarounds that audit §6.4 confirmed are still Bazzite-current).
- `installer/flatpaks-base` + `installer/flatpaks-gaming` — single
  source of truth, already deduplicated (PR #45).
- `bootc switch --enforce-container-sigpolicy` and the cosign
  verification chain.

## Why this is deferred

1. **Upstream titanoboa is still WIP**. There is no canonical
   public-facing documentation; the only reference implementation is
   Bazzite itself, and that's 315 lines of Bazzite-specific logic
   that's been iterated on across many in-flight changes.

2. **ISO build path is high-risk**. The smoke-boot QEMU gate covers
   `:stable` boot, but the *ISO* path is exercised only manually (no
   `qemu-system-x86_64 -drive file=install.iso` step in any
   workflow). A botched titanoboa migration could ship a broken ISO
   that takes hours to diagnose because the ISO build is end-of-pipe.

3. **No urgency in absolute terms**. The current Anaconda kickstart
   path works — last ISO build (run #27025256721) produced a
   functional install ISO published to Internet Archive
   (`margine-anaconda-iso-20260603`). Bazzite themselves did this
   migration after 12+ months of stable anaconda-iso shipping; it's a
   "spring cleaning", not a fire drill.

4. **Cost-of-failure asymmetry**. A clean session focused on this
   migration with end-to-end QEMU boot of the resulting ISO is the
   right shape. An overnight autonomous attempt risks landing a
   subtly-broken hook chain that shows up only when a real user
   downloads the next ISO.

## When to do it

Either:

- **Next dedicated 3-4h session** with daniel watching the
  intermediate QEMU boots, OR
- **When Bazzite or ublue-os/main publishes a migration guide** —
  reducing the design-decision count from "every line is novel" to
  "follow the recipe".

Tracker: audit
[2026-06-05-margine-stack-audit-status-delta.md](../../../../margine-fedora-atomic/docs/audits/2026-06-05-margine-stack-audit-status-delta.md)
under "Open follow-ups", item #6.

## Reference URLs

- Bazzite `installer/` HEAD: <https://github.com/ublue-os/bazzite/tree/main/installer>
- `iso.yaml` example: <https://github.com/ublue-os/bazzite/blob/main/installer/iso.yaml>
- `titanoboa_hook_preinitramfs.sh`: <https://github.com/ublue-os/bazzite/blob/main/installer/titanoboa_hook_preinitramfs.sh>
- `titanoboa_hook_postrootfs.sh`: <https://github.com/ublue-os/bazzite/blob/main/installer/titanoboa_hook_postrootfs.sh>
- `ondrejbudai/bootc-isos` original reference: <https://github.com/ondrejbudai/bootc-isos>
- bootc-image-builder issue on titanoboa adoption: <https://github.com/osbuild/bootc-image-builder/issues>
