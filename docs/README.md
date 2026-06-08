# Documentation Map

Start here if you are new to this repository. Documents are ordered by reading
priority. You do not need to read all of them before running the VM lab; the
install guide is self-contained.

## Start here

| Document | What it covers |
| --- | --- |
| [00-goals.md](00-goals.md) | Primary goal, technical goals, non-goals, working hypotheses, decision gates |
| [01-architecture.md](01-architecture.md) | Fedora Atomic model: ostree, rpm-ostree, Btrfs, Flatpak, toolbox, channels |
| [02-install-lab.md](02-install-lab.md) | Current Bluefin DX rebase install note plus the legacy Silverblue VM lab procedure |
| [02a-custom-partitioning.md](02a-custom-partitioning.md) | Custom Anaconda partitioning with LUKS2 and a dedicated `@data` Btrfs subvolume |
| [02b-lab-vm-setup.md](02b-lab-vm-setup.md) | Operational guide: libvirt + virt-install + virt-viewer for spinning up a Margine smoke-test VM with UEFI + Secure Boot + vTPM 2.0 (Arch-host friendly prereqs) |
| [upstream-inspirations.md](upstream-inspirations.md) | Attribution and provenance: which upstream projects Margine derives from (Origami's custom-kernel script, MorrOS's image-template pattern, Bluefin DX as `FROM`, rechunk action, …), with file-level pointers and a quarterly review mechanism via `scripts/check-upstreams.sh` |

## Boot security and storage

| Document | What it covers |
| --- | --- |
| [07-secure-boot-tpm2.md](07-secure-boot-tpm2.md) | Secure Boot and TPM2 auto-unlock plan using Fedora-native mechanisms |
| [05-known-risks.md](05-known-risks.md) | Known risks with explicit mitigations; read before the CachyOS experiment |

## Experimental kernel

| Document | What it covers |
| --- | --- |
| [03-cachyos-kernel.md](03-cachyos-kernel.md) | CachyOS COPR kernel experiment: pre-flight, deployment, validation, rollback |

## Validation reference

| Document | What it covers |
| --- | --- |
| [04-validation.md](04-validation.md) | Validation commands and pass criteria for each phase |
| `scripts/validate-margine-system` | Runtime acceptance test: photographs the booted system and compares against canonical Margine state (kernel, GNOME settings, Flatpaks, users/groups, extension schemas, BAKE presence). 11 sections. Single PASS/FAIL verdict. |
| `scripts/validate-declared-state` | Spec-drift detector: reads `declarations/margine-atomic.yaml` and diffs against the running system (RPMs, Flatpaks, GNOME extensions). Makes the spec load-bearing — an item added/removed from the spec without a corresponding system change is surfaced. Audit §4.1 + rec #18. |

## Personal and hardware layers

| Document | What it covers |
| --- | --- |
| [06-personal-migration-assessment.md](06-personal-migration-assessment.md) | What carries over from Margine Personal; what must be redesigned for Atomic |
| [08-gnome-personal-layer.md](08-gnome-personal-layer.md) | Home layout, fonts, icons, GNOME theme, folder metadata |
| [10-hardware-media-stack.md](10-hardware-media-stack.md) | Intel/AMD drivers, Mesa, VA-API, Vulkan, OpenCL, PipeWire, codecs |
| [11-gaming-runtime.md](11-gaming-runtime.md) | Desktop gaming runtime: Flatpak launchers, host helpers, Gamescope, split-lock |
| [15-host-layer.md](15-host-layer.md) | **Legacy** Bluefin-style host baseline for stock Silverblue (superseded by ADR 0005 — Margine now rebases to Bluefin DX). Preserved for audit / fallback path. |
| [16-developer-toolbox.md](16-developer-toolbox.md) | Daily-use guide for the developer surfaces: toolbox tools (just, glow, gum, fastfetch), distrobox for non-Fedora distros, Homebrew on Linux, starship prompt, GNOME app folders, daily workflow |
| [17-keyboard-bindings.md](17-keyboard-bindings.md) | Hyprland-style keyboard layout for GNOME: dynamic workspaces, Fedora Workspace Indicator, custom app launchers (Ptyxis terminal, SUPER+E Nautilus), o-tiling actions (`Super+Arrow` move / `Super+Shift+Arrow` focus); full Hyprland→GNOME mapping |
| [18-observability.md](18-observability.md) | Three independent notification mechanisms: ntfy push on every build/smoke-boot/ISO outcome, `margine-staleness.timer` (warn if `:stable` hasn't refreshed in >7 days), `margine-upgrade-notify` (notify-send after a reboot picks up a new deployment) |
| [19-iso-distribution.md](19-iso-distribution.md) | ISO + qcow2 publishing pipeline: builder → Internet Archive (torrent + 3 HTTP mirrors, seeded forever) + `files.the-empty.place` HTML index + sha256sums + 7-day local fallback. Why torrent-first instead of direct Caddy hosting. |

## System design

| Document | What it covers |
| --- | --- |
| [09-declarative-model.md](09-declarative-model.md) | Declarative desired-state model; channel-aware adapters; phase plan |
| [roadmap.md](roadmap.md) | Phase plan with objectives and decision gates |

Updates are orchestrated by **Bluefin's `uupd.timer`** (inherited from the base image); see [01-architecture.md § Update Orchestration](01-architecture.md#update-orchestration).

## Architecture decisions

| Document | What it covers |
| --- | --- |
| [adr/0001-why-silverblue-not-kinoite.md](adr/0001-why-silverblue-not-kinoite.md) | Why Fedora Silverblue (GNOME) over Kinoite (KDE) for phase 1 |
| [adr/0002-gnome-in-phase-1.md](adr/0002-gnome-in-phase-1.md) | Why GNOME stock in phase 1 and not Hyprland |
| [adr/0003-fedora-native-boot-security.md](adr/0003-fedora-native-boot-security.md) | Why Fedora shim/systemd-cryptenroll and not Arch/Limine/sbctl patterns |
| [adr/0004-rpm-ostree-base-boundary.md](adr/0004-rpm-ostree-base-boundary.md) | Why the base-OS update step owns pre/post validation, reboot judgment, and rollback (superseded — implementation moved to Bluefin `uupd`) |
| [adr/0005-base-on-bluefin-dx.md](adr/0005-base-on-bluefin-dx.md) | Why Margine deploys as Bluefin DX rebase + 5 diffs, not as stock Silverblue + layer |
| [adr/0006-kernel-cachyos-decision.md](adr/0006-kernel-cachyos-decision.md) | Why Margine stays on `kernel-cachyos` (bieszczaders COPR), not OGC, not ublue-akmods — BORE + ThinLTO + HZ=1000 + creator-first identity |

## Reference

| Document | What it covers |
| --- | --- |
| [14-expected-behaviors.md](14-expected-behaviors.md) | Behaviors that look like errors but are normal on Silverblue; observed in the VM lab |

## Meta

| Document | What it covers |
| --- | --- |
| [13-ai-validation-prompt.md](13-ai-validation-prompt.md) | Reusable AI audit prompt for structured validation of this repository |

## Lessons learned (postmortems)

| Document | What it covers |
| --- | --- |
| [lessons-learned/2026-05-28-initramfs-and-bootc-labels.md](lessons-learned/2026-05-28-initramfs-and-bootc-labels.md) | First bring-up of the bootc image: initramfs path, ostree labels, why we rechunk |
| [lessons-learned/2026-06-01-systemd-ordering-cycle-and-rechunk-storage.md](lessons-learned/2026-06-01-systemd-ordering-cycle-and-rechunk-storage.md) | Emergency-mode boot from an `After=local-fs.target` ordering cycle; introduction of the `:candidate → :stable` smoke-boot-gated promotion model |
