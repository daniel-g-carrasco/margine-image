<p align="center">
  <img src="assets/branding/margine-logo-wide.png" alt="Margine" width="500">
</p>

<p align="center">
  <strong>Margine on Fedora Silverblue</strong> — a personal workstation built on validated Fedora Atomic foundations.
</p>

<p align="center">
  <a href="docs/02-install-lab.md">Install</a> ·
  <a href="docs/04-validation.md">Validate</a> ·
  <a href="docs/README.md">Documentation</a> ·
  <a href="docs/adr">Decisions</a>
</p>

---

Margine is a versioned system definition: declarations describe intent, validators prove the result, and recovery paths are part of the normal workflow — not emergency procedures.

This repository is the **Fedora Atomic branch** of that project. It explores whether the same reproducible, recoverable approach works on Fedora Silverblue using only Fedora-native mechanisms: rpm-ostree, LUKS2, systemd-cryptenroll, Btrfs, Flatpak, toolbox.

> **Phase 1 · Manual VM lab · Fedora Silverblue 44**
> Validating the Atomic model before building anything on top of it.

## What's inside

| Path | Contents |
| --- | --- |
| `declarations/` | Desired system state in YAML |
| `scripts/` | Read-only validators and update orchestrator |
| `docs/` | Architecture, procedures, risks, ADRs, roadmap |
| `config/` | Topgrade accessory-update profile |
| `files/` | Margine terminal branding (`margine-fetch`, fastfetch config) |
| `assets/` | Logo and identity files |

## Quick start

Clone into the Fedora Silverblue VM and run the baseline validators:

```sh
git clone https://github.com/daniel-g-carrasco/margine-fedora-atomic ~/dev/margine-fedora-atomic
cd ~/dev/margine-fedora-atomic

scripts/validate-atomic-layout
scripts/validate-hardware-media-stack
scripts/collect-diagnostics
scripts/update-all --dry-run
```

Validators are **read-only** — they observe and report, they never modify the system.

## Documentation

Full index and reading order: [docs/README.md](docs/README.md)

| Document | What it covers |
| --- | --- |
| [Architecture](docs/01-architecture.md) | Fedora Atomic model: ostree, rpm-ostree, Btrfs, Flatpak, channels |
| [Install lab](docs/02-install-lab.md) | VM lab procedure from ISO through first update |
| [Custom partitioning](docs/02a-custom-partitioning.md) | Anaconda guide with LUKS2 and `@data` Btrfs subvolume |
| [Secure Boot + TPM2](docs/07-secure-boot-tpm2.md) | Disk encryption and auto-unlock via systemd-cryptenroll |
| [Known risks](docs/05-known-risks.md) | Risks and mitigations for each experiment |
| [Roadmap](docs/roadmap.md) | Four phases from VM lab to native image |

---

<p align="center">
  Built on <a href="https://fedoraproject.org/atomic-desktops/silverblue/">Fedora Silverblue</a>
</p>
