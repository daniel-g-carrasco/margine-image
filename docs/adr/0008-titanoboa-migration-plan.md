# ADR 0008 — Titanoboa migration plan

**Status:** Proposed
**Date:** 2026-06-08
**Supersedes:** the deferred Titanoboa investigation from the 2026-06-08 morning 8-blocker audit (ADR-style note in `margine-image`).
**Coexists with:** [ADR 0006 (kernel CachyOS via COPR)](0006-kernel-cachyos-decision.md), [ADR 0007 (Sealed Bootable Container Images: watching)](0007-sealed-bootable-images-tracker.md).

This ADR consolidates two parallel research efforts (Codex CLI and Claude multi-agent workflow) drafted on 2026-06-08. Both converged on ~85% of the substance independently. The 4 trade-off divergences were resolved by the project lead; this final document records those decisions inline and supersedes both research drafts (PR #40 and #41 closed by this PR).

## 1. Context — Why we are migrating

The current ISO build path (`osbuild/bootc-image-builder-action` with `--type anaconda-iso`) has been hardened over multiple iterations (PR #80 added partitioning kickstart, PR #88 added pre-first-reboot MOK enrollment, PR #85 added baked offline docs) but it is reaching architectural ceiling:

- `disk_config/iso-gnome.toml` is now ~303 lines covering partitioning, bootc switch, fstab zstd patching, BAKE Flatpak rsync, MOK enrollment, and Anaconda module selection. Every addition strains BIB's narrow contract.
- `bootc-image-builder` is in maintenance-mode upstream: Universal Blue retired it in March 2025 (ublue-os/main#468 — "We are no longer going to attempt to use bootc-image-builder"). Fedora's December 2025 introduction of the `bootc` kickstart verb is the long-term replacement, but is too new and adds a partitioning model Margine would have to relearn.
- The project lead reports concrete production pain: Anaconda spoke does not pre-select single disks, default ESP is 600 MB (we want 4 GiB), MOK Manager screen never appeared on first install on Framework 13 (vs Bluefin which did show it on the same hardware), and custom partitioning errors mid-install.
- Titanoboa is the path Universal Blue's broader ecosystem has committed to. Bluefin's ISO repo (`projectbluefin/iso`) explicitly states it builds with Anaconda + Titanoboa. Aurora's iso repo (`get-aurora-dev/iso`) ships a green Titanoboa pipeline today.

The goal is **not** to try Titanoboa as a vague replacement. The goal is to move Margine's ISO build to a Titanoboa-based pipeline while preserving the entire installer behaviour, Secure Boot/MOK enrollment, BAKE Flatpak injection, fstab compression tuning, and `ghcr.io/daniel-g-carrasco/margine:stable` bootc origin.

## 2. Titanoboa today — Verified upstream behaviour

Research date: 2026-06-08. Sources inspected by two independent investigators (Codex CLI + Claude multi-agent workflow), 4 of 4 key facts independently spot-verified via `gh api` against commit SHAs.

### What Titanoboa is

A ~150-line bash ISO assembler distributed as a GitHub composite action and an OCI builder image (`ghcr.io/ublue-os/titanoboa:latest`). It implements the **Container-native ISO contract v0.1.0** specified at <https://github.com/ondrejbudai/bootc-isos> — the upstream spec Titanoboa implements; understanding this spec is the key to predicting what Titanoboa will and will not do in the future.

The action does almost nothing: `mksquashfs /rootfs → /LiveOS/squashfs.img` (zstd -Xcompression-level 19), copy `/rootfs/usr/lib/modules/*/{vmlinuz,initramfs.img}` to `/images/pxeboot/`, copy `/rootfs/boot/efi/EFI/$VENDOR` and `/rootfs/usr/lib/grub/{i386-pc,arm64-efi}`, generate `grub.cfg` from `/usr/lib/bootc-image-builder/iso.yaml` (**REQUIRED — `build_iso.sh` exits 1 if missing**), build 100 MB FAT32 `uefi.img`, `xorriso -as mkisofs` with hybrid GPT/MBR.

ALL live-environment customisation (Anaconda profile, BAKE Flatpaks, dracut-live initramfs, livesys-scripts, EFI binaries, `iso.yaml`, GRUB entries) must be baked into the input container image **before** Titanoboa runs. Titanoboa itself adds nothing.

### API contract (post-#138, current upstream HEAD)

action.yml at `ublue-os/titanoboa@5c457c3d` has exactly two inputs and one output:

| Name | Kind | Required | Default | Description |
|------|------|----------|---------|-------------|
| `image-ref` | input | yes | — | OCI reference to the bootc container image |
| `iso-dest` | input | no | `${{ github.workspace }}/output.iso` | Output ISO path |
| `iso-dest` | output | n/a | — | Output ISO path |

Pre-#138 the action had 12 inputs (`livesys`, `compression`, `hook-post-rootfs`, `hook-pre-initramfs`, `iso-dest`, `flatpaks-list`, `container-image`, `add-polkit`, `kargs`, `builder-distro`). **ALL ten extras were silently dropped** by PR #138 — current consumers passing them get `##[warning]Unexpected input(s)` and the action proceeds anyway, producing a broken ISO. This is the root cause of Bluefin's broken CI (see §2.5).

### Live-env image requirements

The OCI image fed to Titanoboa must, before Titanoboa is invoked, perform (verified against `examples/bazzite/src/build.sh` + `installer/build.sh` + `installer/titanoboa_hook_postrootfs.sh` in `ublue-os/bazzite`):

1. `dnf install dracut-live` + `dracut --no-hostonly --add 'dmsquash-live dmsquash-live-autooverlay' /usr/lib/modules/$kver/initramfs.img $kver` — **mandatory** because Fedora defaults to `hostonly=yes` which precludes dmsquash-live. Skipping gives a kernel-panics-on-boot live ISO.
2. `dnf install livesys-scripts`, set `livesys_session=gnome` in `/etc/sysconfig/livesys`, enable `livesys.service` + `livesys-late.service`.
3. `dnf install grub2-efi-x64-cdboot` for `gcdx64.efi`.
4. `cp -av /usr/lib/efi/*/*/EFI /boot/efi/`.
5. `cp /boot/efi/EFI/fedora/grubx64.efi /boot/efi/EFI/BOOT/fbx64.efi` (fallback EFI).
6. `dnf install anaconda-live libblockdev-{btrfs,lvm,dm} firefox`.
7. Write `/etc/anaconda/profile.d/margine.conf`.
8. Write `/usr/share/anaconda/interactive-defaults.ks` + `/usr/share/anaconda/post-scripts/*.ks`.
9. Write `/usr/lib/bootc-image-builder/iso.yaml` with `label`, `grub2.default`, `grub2.timeout`, `grub2.entries`.

### Installer choice — Anaconda WebUI

Anaconda is the right v1 installer for Margine. Both production references (Bluefin + Bazzite) ship Anaconda-live via Titanoboa, both write `/etc/anaconda/profile.d/<distro>.conf` + `/usr/share/anaconda/interactive-defaults.ks`. **Both use WebUI** (`webui_web_engine = slitherer`); Margine's BIB anaconda-iso currently uses traditional GTK.

**WebUI is the chosen direction for v1** (matches production references). Fallback to traditional GTK is a 1-line profile change (`webui_web_engine = none`) if hardware testing in Phase 6 exposes regressions.

Calamares is not phase-1: distribution-independent installer framework, no bootc integration. Readymade (FyraLabs, used by Ultramarine + tauOS) merged bootc support in PR #50 (2025-04-16) and is being evaluated by Bluefin (ublue-os/titanoboa#66) but is not production-ready for Margine in 2026-06.

### Bluefin status — broken on `@main` since 2026-05-19

`projectbluefin/iso` pins `ublue-os/titanoboa@main` and still passes `flatpaks-list`, `hook-post-rootfs`, `kargs`, `builder-distro` to the action — all silently dropped by #138. Every scheduled run since 2026-05-19 has failed.

- Last green Bluefin Stable build: **2026-05-11** (release tag `26.05.7-stable`).
- 2026-06-08 LTS-HWE Testing run: failed.
- Several 2026-06-01 runs: failed.
- No public PR currently tracks the fix.

Bluefin is therefore **not** a usable reference workflow today. Its Anaconda configuration (`iso_files/configure_iso_anaconda.sh`) remains valuable as reference content; its CI workflow YAML does not.

### The other reference: `get-aurora-dev/iso`

Aurora ships a green Titanoboa pipeline today, pinned pre-#138 at `840217d97bd0bc9a52466508c54d8dda5c5ba2fd` (2026-01-04). Their `iso_files/configure_iso_anaconda.sh` is the same shape as Bluefin's but the workflow is current and verified-in-production. **This ADR pins post-#138 (decision §3), so Aurora's workflow YAML is not directly copyable — but Aurora's Anaconda configuration content remains the best reference.**

### Bazzite — only production-grade post-#138 consumer

Bazzite (`ublue-os/bazzite`) is the only consumer running on post-#138 Titanoboa shape, but pins to `Zeglius/titanoboa@revamp-pr` (a personal fork by the author of #138). Their `installer/Containerfile` + `installer/build.sh` + `installer/titanoboa_hook_postrootfs.sh` are the canonical post-#138 reference for the live-env image. Their workflow YAML can be adapted to pin `ublue-os/titanoboa@5c457c3d` instead of the fork.

### Breaking-change timeline

| PR | Merged | Title | Impact |
|----|--------|-------|--------|
| #38 | 2025-03-25 | `feat!: pass hooks as script paths` | Hooks moved from env vars to file paths |
| #138 | 2026-05-19 | `feat!: Only use container images as the only source of truth` | API collapsed 12 → 2 inputs; deleted Justfile, flatpaks list, hook scripts, polkit rules |
| #141 | **OPEN** | hardcoded podman pull regression | Affects local + PR builds against unpushed images — requires workaround for Margine CI |

### Known Titanoboa bugs/limitations

- **Issue #141 (OPEN)**: `main.sh` hardcodes `podman pull` of the input image, breaking local builds + PR builds that haven't pushed the image to a registry. Workaround: push `margine-live` to `ghcr.io/daniel-g-carrasco/margine-live:ci-run-${{github.run_id}}` (transient tag) before invoking titanoboa with that ref. Margine already uses this pattern for `margine-installer`.
- **No `implantisomd5`**: Titanoboa's `build_iso.sh` does not run `implantisomd5`, so the ISO has no `rd.live.check` integrity media check at boot. Trivial to add as a one-line post-titanoboa step.

## 3. Decision

Migrate Margine's ISO pipeline to Titanoboa using a **dedicated `margine-live` OCI layer** that extends `ghcr.io/daniel-g-carrasco/margine:stable` with the live-environment requirements (dracut-live, livesys-scripts, grub2-efi-x64-cdboot, anaconda-live, BAKE Flatpaks pre-installed, Anaconda profile + post-scripts, `iso.yaml`). The GitHub workflow builds `margine-live`, pushes it to a transient ghcr tag, then calls `ublue-os/titanoboa` with `image-ref` pointing to that tag.

**Project-lead decisions** (the four trade-offs identified in the parallel research, resolved 2026-06-08):

1. **Pin Titanoboa to current upstream HEAD `5c457c3d0518bd17e754be0fd98a60d29d26abb4`** (post-#138, 2026-05-19). Rationale: align with the upstream-current 2-input API; accept that no production-grade consumer is shipping green on canonical `ublue-os/titanoboa@<that SHA>` yet (Bazzite uses a fork). Risk mitigated by Bazzite's content reference + Phase 1 smoke + Phase 6 hardware test before promoting to default. Renovate must be configured to NOT auto-bump the pin. Migration to a newer SHA requires explicit follow-up ADR.

2. **Keep CachyOS kernel in both live and installed environments.** Do NOT copy Bazzite's `titanoboa_hook_preinitramfs.sh` vanilla-kernel-swap. Rationale: Margine's identity is the CachyOS BORE-scheduler kernel; the live ISO is "try-before-install", which implies the live env must behave identically to what the user will install. The Secure Boot chicken-and-egg (live boot under SB requires pre-enrolled Margine MOK) is solved by documenting + accepting the supported flow: disable SB → boot live ISO → install → reboot, mok-enroll.service stages enrollment → reboot, MokManager prompts → re-enable SB → CachyOS kernel boots.

3. **Adopt Anaconda WebUI** (`webui_web_engine = slitherer`) to match Bluefin/Bazzite production. Hide WebUI pages not relevant to Margine via `hidden_webui_pages`. Fall back to traditional GTK Anaconda (1-line profile change) if hardware testing in Phase 6 exposes regressions.

4. **8-phase migration plan** (Phase 0 through Phase 7, ~11.5 days total). Independently completable phases so the migration can pause between phases without breaking anything.

## 4. Rules and constraints — invariants the migration MUST NOT break

- **Use the pinned Titanoboa SHA only — never `@main`.** Renovate disabled for this pin.
  *Rationale:* #138 silently dropped 10 of 12 action inputs with `##[warning]Unexpected input(s)` and no hard error. Bluefin's CI has been red for 3+ weeks because of this. Pin = stability anchor.

- **CachyOS kernel re-signed with the Margine MOK MUST be present in both live ISO and installed system at `/usr/lib/modules/<kver>/vmlinuz`, and MUST be the ONLY kernel under `/usr/lib/modules/` in the `margine-live` OCI layer before Titanoboa is invoked.**
  *Rationale:* Titanoboa's `build_iso.sh` hard-codes copying `/rootfs/usr/lib/modules/*/{vmlinuz,initramfs.img}` with explicit "behavior unspecified" if multiple kernels exist. The CachyOS kernel is Margine's defining feature. A build-time assertion `test $(ls /usr/lib/modules | wc -l) -eq 1` is mandatory in `live-env/src/build.sh`.

- **MOK enrollment via `mokutil --import` MUST continue to be staged from the installer post-script (preserving PR #88 semantics).** The `mok-enroll.service` first-boot fallback unit in `margine:stable` MUST be preserved unchanged.
  *Rationale:* Two-tier MOK enrollment is the documented Margine UX. Anaconda %post stages the request, MokManager prompts on next reboot. The first-boot fallback exists specifically because users sometimes miss MokManager and is non-negotiable.

- **BAKE Flatpaks (38-app set in `installer/flatpaks-base`, ~5 GB) MUST be pre-installed into `/var/lib/flatpak` of the `margine-live` OCI image at build time, AND MUST land in the installed system's `/var/lib/flatpak` via the install-time rsync from a kickstart post-script.** The `/usr/share/flatpak/preinstall.d/margine-defaults.preinstall` belt-and-suspenders fallback in `margine:stable` MUST be preserved.
  *Rationale:* ostree+bootc reset `/var` per-deployment on install, so the only way Flatpaks survive the first boot is the rsync. Bazzite and Bluefin both validate this pattern. The preinstall fallback covers silent rsync failures (disk full, xattr loss).

- **SELinux xattrs and labels on `/var/lib/flatpak` MUST be preserved through the rsync** using `rsync -aAXUHKP --filter='-x security.selinux' /var/lib/flatpak $target/var/lib/` (Bluefin pattern: preserves POSIX xattrs but strips SELinux labels which ostree-finalize restores).
  *Rationale:* Flatpak directories have `system_data_t` / `flatpak_t` labels; if dropped or wrong, Flatpaks fail to launch with AVC denials.

- **Anaconda profile MUST set BTRFS as default filesystem with `btrfs_compression=zstd:1`; default partitioning MUST preserve PR #80 semantics** (ESP 4 GiB + btrfs root + ignoredisk single-disk shim via `%pre`).
  *Rationale:* PR #80 was a hard-won fix; the partition shape is part of Margine's installed-system identity. The `%pre` disk-autodetect must port verbatim from `disk_config/iso-gnome.toml:34-63` into `/usr/share/anaconda/interactive-defaults.ks`.

- **fstab btrfs `compress=zstd:1` patching (PR #88's `%post` python3 inline) MUST run during install** and produce `/etc/fstab` with `compress=zstd:1` on all btrfs mounts. The implementation ports the current BIB kickstart verbatim — a chroot `%post` patching the target's `/etc/fstab` (under ostree this is the deployment's `usr/etc/fstab`). Verify with `mount | grep compress=zstd` on the installed system in Phase 6 hardware testing.
  *Rationale:* Margine ships zstd:1 compression as a documented default for SSD lifespan + install footprint.

- **Live ISO MUST be UEFI-bootable on amd64.** BIOS support is provided by Titanoboa's `xorriso` invocation at zero cost; verify presence of `/usr/lib/grub/i386-pc` in `margine:stable` but do not gate the migration on legacy BIOS.

- **GNOME defaults (dconf + gschema overrides + ujust recipes) MUST NOT be touched during migration.** They live in `margine:stable` and flow through to live env and installed system unchanged.
  *Rationale:* Out of scope — this is an ISO-pipeline change, not an image change. Protected by `FROM ghcr.io/daniel-g-carrasco/margine:stable` inheritance.

- **ISO size MUST stay under 10 GB.** Current BIB output ~9 GB. Titanoboa projection 8-10 GB.

- **Keep BIB anaconda-iso pipeline alive as fallback through at least one successful hardware-tested Titanoboa release** (Phase 7).

## 5. Margine-specific blockers and resolutions

| Blocker | Resolution | Effort | Phase |
|---------|------------|--------|-------|
| CachyOS kernel + SB chicken-and-egg on live boot | Document + accept the disable-SB / install / enroll-MOK / re-enable-SB flow. Reject Bazzite's vanilla-kernel-swap (decision §3.2). | S | 4 |
| BAKE Flatpaks must move from BIB kickstart `%post --nochroot` into `install-flatpaks.ks` under `/usr/share/anaconda/post-scripts/` | Reuse existing `installer/build.sh` logic verbatim. Bluefin's `rsync -aAXUHKP --filter='-x security.selinux'` is the verified-in-production incantation. | M | 2 |
| MOK enrollment %post relocate | Port `disk_config/iso-gnome.toml:80-137` verbatim into `live-env/src/post-scripts/secureboot-enroll-key.ks`. Structurally identical to Bazzite's `secureboot-enroll-key.ks`. Keep `mok-enroll.service` unchanged. | S | 4 |
| PR #80 ignoredisk shim has no Anaconda profile equivalent | Keep the `%pre` script verbatim, embed in `interactive-defaults.ks`. Anaconda processes `%pre` identically regardless of source. | S | 3 |
| fstab compress=zstd:1 patching (PR #88 inline python3) doesn't fit profile config | Port to `live-env/src/post-scripts/zstd-compress.ks`. Anaconda `%post --nochroot` with `/mnt/sysimage` paths works identically under Titanoboa-launched Anaconda. | S | 3 |
| **Titanoboa issue #141 (OPEN)**: hardcoded podman pull breaks local + PR builds against unpushed images | Push `margine-live` to `ghcr.io/daniel-g-carrasco/margine-live:ci-run-${{github.run_id}}` (transient) before invoking titanoboa. Same pattern as `margine-installer` today. | S | 1 |
| ISO label / volid: BIB used Fedora-S-dvd; Titanoboa derives from `iso.yaml.label` | Set `label: 'Margine-Live'` in `iso.yaml`. Rename output to `margine-${DATE_TAG}.iso` via `mv` post-titanoboa. | S | 1 |
| Two-image GHCR strategy: `margine` + transient `margine-live:ci-run-<id>` | Reuse existing `margine-installer` retention policy (newest 3 ci-run tags retained, rest pruned). | S | 5 |
| Anaconda WebUI vs traditional GTK | Adopt WebUI (decision §3.3). Fall back to GTK in 1 line if Phase 6 hardware exposes issues. | S | 3 |
| ISO size growth risk (BIB 9 GB → Titanoboa projection 8-10 GB) | Measure at each phase. zstd-19 is already Titanoboa default. Fallback: `--transport=registry` to drop pre-pulled payload (network-required install), or thin BAKE list. | M | reactive |
| **`implantisomd5` missing from Titanoboa** | Add `implantisomd5 ${ISO_PATH}` as one-line post-titanoboa step. | S | 5 |
| **Zero production-green consumer on canonical `ublue-os/titanoboa@5c457c3d`** | Mitigated by: (a) using Bazzite's well-tested content patterns ported to our pin, (b) Phase 1 smoke + Phase 6 hardware test before promoting to default, (c) BIB fallback through Phase 7. | M | 1+ |

## 6. Migration phases — 8-phase plan (~11.5 days)

Phase boundaries are independently completable so the migration can pause between phases without breaking anything.

### Phase 0 — Pin Titanoboa SHA, scaffold from working references (0.5 days)
**Description:** Add `ublue-os/titanoboa@5c457c3d0518bd17e754be0fd98a60d29d26abb4` (current main HEAD, post-#138) as a Renovate-disabled pin comment in `.github/workflows/build-disk.yml`. Clone `ublue-os/bazzite/installer/build.sh` + `installer/titanoboa_hook_postrootfs.sh` + `get-aurora-dev/iso/iso_files/configure_iso_anaconda.sh` into `margine-image/live-env/references/` with provenance comments. Update Renovate config to ignore the titanoboa pin.
**Acceptance:** SHA pinned (commented out, not active yet). Reference scripts copied. Renovate config updated. README addition noting "Titanoboa pin lives at SHA 5c457c3d, see ADR-0008".

### Phase 1 — Build no-op `margine-live` OCI layer; smoke a bootable empty ISO (2 days)
**Description:** Create `margine-image/live-env/Containerfile` (`FROM ghcr.io/daniel-g-carrasco/margine:stable`) + `live-env/src/build.sh` (minimal — install livesys-scripts, dracut-live, regenerate initramfs with `--no-hostonly --add 'dmsquash-live dmsquash-live-autooverlay'` against the existing CachyOS kernel, install grub2-efi-x64-cdboot, write `iso.yaml` with label `Margine-Live`). Build via a new side-job in `build-disk.yml` that pushes `margine-live:ci-run-${{github.run_id}}` then invokes titanoboa@5c457c3d.
**Acceptance:** QEMU UEFI boot of produced ISO reaches GNOME desktop in live mode. ISO size < 6 GB (no Flatpaks, no install payload). Pipeline green on amd64. Single-kernel assertion passes (`test $(ls /usr/lib/modules | wc -l) -eq 1`). ISO label is `Margine-Live`.

### Phase 2 — Port BAKE Flatpaks into `margine-live` (2 days)
**Description:** Move `installer/flatpaks-base` (38 apps) into `live-env/src/flatpaks`. In `build.sh` add `curl -Lo /etc/flatpak/remotes.d/flathub.flatpakrepo https://dl.flathub.org/repo/flathub.flatpakrepo` + `xargs -r flatpak install -y --noninteractive < /src/flatpaks` (Bazzite pattern with `apply_extra` prep via bwrap if needed). Write `install-flatpaks.ks` to `/usr/share/anaconda/post-scripts/` that does `rsync -aAXUHKP --filter='-x security.selinux' /var/lib/flatpak $target/var/lib/`.
**Acceptance:** ISO size grows to ~8-9 GB (matches current BIB). `flatpak list --system` in live env shows all 38 BAKE apps. Build time < 25 min cached, < 40 min uncached.

### Phase 3 — Embed Anaconda + Margine profile + kickstart (2.5 days)
**Description:** `dnf install -qy --enable-repo=fedora-cisco-openh264 --allowerasing firefox anaconda-live libblockdev-{btrfs,lvm,dm}`. Write `/etc/anaconda/profile.d/margine.conf` (sections: `[Profile]` profile_id=margine; `[Profile Detection]`; `[Storage]` default_scheme=BTRFS, default_partitioning, btrfs_compression=zstd:1; `[UserInterface]` webui_web_engine=slitherer, hidden_webui_pages, hidden_spokes). Write `/usr/share/anaconda/interactive-defaults.ks` containing the PR #80 `%pre` disk-autodetect verbatim. Write `post-scripts/{bootc-switch,zstd-compress,install-flatpaks}.ks`.
**Acceptance:** Anaconda WebUI launches with margine profile. Disk autodetect `%pre` selects single available disk. Partitioning shows ESP 4 GiB + btrfs root + zstd:1. Install completes to bootable installed system on QEMU.

### Phase 4 — Port MOK enrollment %post; validate CachyOS kernel full pipeline (2 days)
**Description:** Write `post-scripts/secureboot-enroll-key.ks` containing the MOK enrollment block from `disk_config/iso-gnome.toml:80-137` verbatim (`mokutil --timeout -1` + `printf 'margine-os\nmargine-os\n' | mokutil --import /mnt/sysimage/usr/share/cert/MOK.der` with EFI gate). Document the supported "disable SB → install → enroll → re-enable SB" flow in `/docs/install` for users.
**Acceptance:** Install completes on QEMU UEFI with SB disabled. After install: first reboot triggers `mok-enroll.service` or Anaconda %post enrollment shows up as pending MokManager request. Second reboot shows MokManager. CachyOS kernel boots on installed system after enrollment.

### Phase 5 — Replace BIB anaconda-iso pipeline; retain BIB qcow2 path (1 day)
**Description:** Modify `.github/workflows/build-disk.yml`: remove anaconda-iso matrix entry from BIB. Keep qcow2 (BIB unchanged — useful for raw disk artifact + QEMU smoke). Promote margine-live + titanoboa side-job to primary `iso` job in matrix. Add `implantisomd5 ${ISO_PATH}` post-titanoboa step. Wire `publish_ia` + release upload paths to consume new ISO path.
**Acceptance:** `build-disk.yml` matrix produces qcow2 (via BIB) + ISO (via margine-live + titanoboa). `publish_ia` + release upload paths green. `smoke-boot.yml` green against new ISO. Rollback documented.

### Phase 6 — Hardware install on Framework 13 + at least one SB box (1.5 days)
**Description:** Burn produced ISO to USB. Install on (a) Framework 13 (Margine reference, AMD Ryzen) with SB disabled — verify full install flow, post-install reboot, BAKE Flatpaks present, GNOME defaults applied, ujust recipes work. (b) Repeat on a second SB-capable box — disable SB, install, re-enable SB, verify MokManager flow.
**Acceptance:** Two clean installs (Framework 13 + one other). Post-install validation: `bootc status` shows `margine:stable`, `flatpak list --system` shows all 38 BAKE apps, `mount` shows btrfs with `compress=zstd:1` on /, MokManager prompts on second reboot, CachyOS kernel boots after MOK enrollment.

### Phase 7 — Delete BIB anaconda-iso; document; cut release (0.5 days)
**Description:** Delete `disk_config/iso-gnome.toml` (move to `disk_config/legacy/` initially). Delete BIB anaconda-iso matrix entry. Update README + ADR-0008 to reflect final state. Commit ADR-0009 stub for "Titanoboa pin bump (revisit when Bazzite or another consumer ships green on canonical `ublue-os/titanoboa` post-#138)".
**Acceptance:** BIB anaconda-iso fully removed. Release published with Titanoboa ISO. ADR-0009 stub committed.

## 7. Open decisions — to confirm during implementation

These are not gating but should be confirmed before the relevant phase starts:

- **Repository location for `live-env/`:** keep inside `margine-image/live-env/` (single-repo, matches Bazzite's `installer/`) vs split into new `margine-iso` repo. Recommendation: single-repo for v1.
- **Phase-5 qcow2 retention:** keep BIB qcow2 vs retire alongside anaconda-iso. Recommendation: keep for now (cheap, useful for smoke tests).
- **Offline install support:** pre-pull `margine:stable` into containers-storage at margine-live build (~3-4 GB ISO bloat, install works without network) vs `--transport=registry` (smaller ISO, network-required install). Recommendation: pre-pull (offline install is documented Margine UX).
- **MOK enrollment password `margine-os`:** keep as-is (documented, memorable, Bazzite uses `universalblue` same shape).
- **Live env GNOME session:** stock livesys-scripts gnome session vs custom Margine liveuser autostart. Recommendation: stock for v1; Margine-specific welcome dialog can be phase-8+ polish.
- **Phase-6 second SB test hardware:** any modern Intel UEFI laptop. Identify before Phase 6 starts.
- **Installer choice longevity:** stay on Anaconda forever vs commit to Readymade migration as ADR-0010 in Q4 2026. Recommendation: Anaconda for v1, re-evaluate Readymade in Q4 2026.

## Consequences

**Positive:**
- Margine aligns with Universal Blue's current ISO direction (Titanoboa) instead of the deprecating BIB anaconda-iso path.
- Kickstart logic (300+ lines in `iso-gnome.toml`) becomes properly organised in `/usr/share/anaconda/post-scripts/` with clear separation of concerns.
- BAKE Flatpaks move from install-time `%post --nochroot` rsync risk into pre-baked + rsync-from-baked pattern (Bluefin verified).
- MOK enrollment migrates without changing the user-visible flow (PR #88 logic preserved).
- The migration is independently completable in 8 phases; each phase can pause without breaking anything.
- BIB qcow2 path retained for VM smoke tests.
- Aligned with upstream-current 2-input API; sets us up for cleaner future upgrades.

**Negative:**
- 8 phases / 11.5 days of focused work.
- Two-image GHCR strategy (`margine` + transient `margine-live:ci-run-<id>`) increases storage + retention complexity (mitigated by existing `margine-installer` retention policy).
- Live ISO under Secure Boot requires the documented disable-enroll-reenable flow (decision §3.2 rejected the kernel-swap workaround in favour of try-before-install UX parity).
- Anaconda WebUI is newer than the traditional GTK installer; possible hardware regressions in Phase 6 (mitigated by 1-line fallback).
- Zero production-grade consumer is shipping green on canonical `ublue-os/titanoboa@5c457c3d` today (Bazzite uses a fork). Mitigated by Phase 1 smoke + Phase 6 hardware test + BIB fallback.

**Risk controls:**
- BIB anaconda-iso pipeline retained as manual fallback through at least one successful hardware-tested Titanoboa release (Phase 7).
- Pin Titanoboa by SHA `5c457c3d`; Renovate disabled.
- Bazzite content patterns are the primary reference (well-tested, just adapted to use canonical upstream pin instead of fork).
- Aurora's Anaconda profile is the secondary content reference (production-validated, pre-#138 workflow shape).
- Phase 1 smoke test catches any silent regression from pinning to canonical Titanoboa vs Bazzite's fork before downstream phases are blocked.

## 8. Research provenance

This ADR was produced by reconciling two independent investigations on 2026-06-08:

- **Codex CLI investigation** (PR #40) — line-numbered citations at commit SHAs `5c457c3d` (Titanoboa), `a4e89e2a` (Bluefin), `c8e3f5e9` (Bazzite). Strongest on detailed structural quote-and-cite.
- **Claude multi-agent workflow** (PR #41) — 17 agents (8 research investigators + 8 adversarial verifiers + 1 synthesizer), 1M+ tokens, 33 min, 7/8 findings accepted by independent verifier. Strongest on cross-reference discovery (Aurora reference, issue #141, implantisomd5, ondrejbudai spec).

Both PRs are closed by this consolidated ADR. The project lead resolved the 4 trade-off divergences inline in §3 (decisions 1-4); the 6 unique findings from the Claude workflow are integrated as constraint rows in §5 and rule items in §4.

## 9. References

### Titanoboa
- <https://github.com/ublue-os/titanoboa> — main branch, sha 5c457c3d
- <https://github.com/ublue-os/titanoboa/blob/main/action.yml> — post-#138 2-input API
- <https://github.com/ublue-os/titanoboa/blob/main/build_iso.sh> — ~100-line ISO assembler
- <https://github.com/ublue-os/titanoboa/blob/main/main.sh>
- <https://github.com/ublue-os/titanoboa/blob/main/Containerfile> — 22-line builder image
- <https://github.com/ublue-os/titanoboa/pull/138> — BREAKING merge, 2026-05-19
- <https://github.com/ublue-os/titanoboa/pull/38> — earlier breaking change, 2025-03-25
- <https://github.com/ublue-os/titanoboa/issues/141> — hardcoded podman pull, OPEN
- <https://github.com/ublue-os/titanoboa/issues/66> — Bluefin Readymade migration attempt
- <https://github.com/ublue-os/titanoboa/tree/main/examples/bazzite> — canonical post-#138 example

### Upstream spec
- <https://github.com/ondrejbudai/bootc-isos> — Container-native ISO contract v0.1.0

### Reference consumers
- <https://github.com/ublue-os/bazzite/blob/main/installer/Containerfile> — installer-image pattern (PRIMARY reference for post-#138 content)
- <https://github.com/ublue-os/bazzite/blob/main/installer/build.sh> — live-env builder
- <https://github.com/ublue-os/bazzite/blob/main/installer/titanoboa_hook_postrootfs.sh> — Anaconda profile + secureboot-enroll-key.ks
- <https://github.com/ublue-os/bazzite/blob/main/.github/workflows/build_iso.yml> — workflow shape (uses `Zeglius/titanoboa@revamp-pr` fork; we adapt to pin canonical `ublue-os/titanoboa@5c457c3d`)
- <https://github.com/get-aurora-dev/iso/blob/main/iso_files/configure_iso_anaconda.sh> — Anaconda profile + MOK + Flatpak preservation (secondary content reference, pre-#138 workflow shape not directly applicable)
- <https://github.com/projectbluefin/iso> — Bluefin pipeline (broken on `@main` since 2026-05-19; Anaconda content still valuable as reference)
- <https://github.com/projectbluefin/iso/blob/main/iso_files/configure_iso_anaconda.sh>

### Future-installer candidates (post-Phase 7)
- <https://github.com/FyraLabs/readymade> — Fyra Labs installer, bootc support PR #50 merged 2025-04-16
- <https://github.com/FyraLabs/readymade/pull/50>

### Margine current state
- `/home/daniel/dev/margine-image/disk_config/iso-gnome.toml` — 303-line BIB kickstart
- `/home/daniel/dev/margine-image/build_files/custom-kernel/install.sh` — CachyOS + MOK signing
- `/home/daniel/dev/margine-image/installer/flatpaks-base` — 38-app BAKE list
- `/home/daniel/dev/margine-image/.github/workflows/build-disk.yml` — current BIB workflow
