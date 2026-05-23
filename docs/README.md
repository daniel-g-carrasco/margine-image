# Documentation Map

Start here if you are new to this repository. Documents are ordered by reading
priority. You do not need to read all of them before running the VM lab; the
install guide is self-contained.

## Start here

| Document | What it covers |
| --- | --- |
| [00-goals.md](00-goals.md) | Primary goal, technical goals, non-goals, working hypotheses, decision gates |
| [01-architecture.md](01-architecture.md) | Fedora Atomic model: ostree, rpm-ostree, Btrfs, Flatpak, toolbox, channels |
| [02-install-lab.md](02-install-lab.md) | VM lab procedure from ISO download through first update and baseline capture |
| [02a-custom-partitioning.md](02a-custom-partitioning.md) | Custom Anaconda partitioning with LUKS2 and a dedicated `@data` Btrfs subvolume |

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

## Personal and hardware layers

| Document | What it covers |
| --- | --- |
| [06-personal-migration-assessment.md](06-personal-migration-assessment.md) | What carries over from Margine Personal; what must be redesigned for Atomic |
| [08-gnome-personal-layer.md](08-gnome-personal-layer.md) | Home layout, fonts, icons, GNOME theme, folder metadata |
| [10-hardware-media-stack.md](10-hardware-media-stack.md) | Intel/AMD drivers, Mesa, VA-API, Vulkan, OpenCL, PipeWire, codecs |
| [11-gaming-runtime.md](11-gaming-runtime.md) | Desktop gaming runtime: Flatpak launchers, host helpers, Gamescope, split-lock |

## System design

| Document | What it covers |
| --- | --- |
| [09-declarative-model.md](09-declarative-model.md) | Declarative desired-state model; channel-aware adapters; phase plan |
| [12-update-orchestration.md](12-update-orchestration.md) | `update-all` orchestration; hard rpm-ostree boundary; Topgrade constraints |
| [roadmap.md](roadmap.md) | Phase plan with objectives and decision gates |

## Architecture decisions

| Document | What it covers |
| --- | --- |
| [adr/0001-why-silverblue-not-kinoite.md](adr/0001-why-silverblue-not-kinoite.md) | Why Fedora Silverblue (GNOME) over Kinoite (KDE) for phase 1 |
| [adr/0002-gnome-in-phase-1.md](adr/0002-gnome-in-phase-1.md) | Why GNOME stock in phase 1 and not Hyprland |
| [adr/0003-fedora-native-boot-security.md](adr/0003-fedora-native-boot-security.md) | Why Fedora shim/systemd-cryptenroll and not Arch/Limine/sbctl patterns |
| [adr/0004-rpm-ostree-base-boundary.md](adr/0004-rpm-ostree-base-boundary.md) | Why rpm-ostree owns the base OS boundary and Topgrade is accessory-only |

## Meta

| Document | What it covers |
| --- | --- |
| [13-ai-validation-prompt.md](13-ai-validation-prompt.md) | Reusable AI audit prompt for structured validation of this repository |
