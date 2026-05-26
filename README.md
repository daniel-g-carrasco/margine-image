<p align="center">
  <img src="assets/branding/margine-logo-wide.png" alt="Margine" width="500">
</p>

<p align="center">
  <strong>Margine</strong> — a personal Fedora Atomic workstation, shipped as a signed bootc image.
</p>

<p align="center">
  <a href="#install">Install</a> ·
  <a href="docs/04-validation.md">Validate</a> ·
  <a href="docs/README.md">Documentation</a> ·
  <a href="docs/adr">Decisions</a>
</p>

---

Margine is a versioned system definition: declarations describe intent, validators prove the result, and recovery paths are part of the normal workflow — not emergency procedures.

The system ships as a bootc image built from **Bluefin DX (Fedora 44) + CachyOS MOK-signed kernel + Margine deltas**. The image is built by GitHub Actions and published to `ghcr.io/daniel-g-carrasco/margine:stable`. Updates flow through Bluefin's `uupd` daily timer; no custom orchestrator is involved on the host.

> **Status:** the image is shipping. The historical Silverblue-lab phase that produced this spec is recorded in [docs/adr/0005-base-on-bluefin-dx.md](docs/adr/0005-base-on-bluefin-dx.md). This repo is the declarative spec + user-state helpers; the build pipeline lives in [margine-image](https://github.com/daniel-g-carrasco/margine-image).

## What's inside

| Path | Contents |
| --- | --- |
| `declarations/` | Desired system state in YAML (single source of truth) |
| `scripts/` | Read-only validators + user-state configure scripts (baked into the image as `margine-configure-*`) |
| `docs/` | Architecture, procedures, risks, ADRs, roadmap |
| `assets/` | Logo and identity files |

For a **full list of what Margine actually ships** — preinstalled Flatpaks, enabled / disabled GNOME extensions, gschema overrides, user-state helpers, "which channel for what" guide — see the image repo's "What Margine adds on top of Bluefin DX" table: [margine-image / README.md](https://github.com/daniel-g-carrasco/margine-image#what-margine-adds-on-top-of-bluefin-dx).

## Install

On a fresh Bluefin DX or Fedora Atomic install:

```sh
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/daniel-g-carrasco/margine:stable
systemctl reboot
```

On first boot, `mok-enroll.service` opens `mokutil --import` with the Margine MOK. Reboot a second time, confirm enrollment in the MOK Manager, and the CachyOS kernel will boot under Secure Boot. After that, daily updates run automatically via Bluefin's `uupd.timer`.

The on-demand health checks remain available:

```sh
margine-validate-atomic-layout
margine-validate-hardware-media-stack
margine-collect-diagnostics
```

Validators are **read-only** — they observe and report, they never modify the system.

## Documentation

Full index and reading order: [docs/README.md](docs/README.md)

| Document | What it covers |
| --- | --- |
| [Architecture](docs/01-architecture.md) | Fedora Atomic model: ostree, Btrfs, Flatpak, channels |
| [Secure Boot + TPM2](docs/07-secure-boot-tpm2.md) | Disk encryption, MOK signing, auto-unlock via systemd-cryptenroll |
| [Known risks](docs/05-known-risks.md) | Risks and mitigations for each experiment |
| [ADR 0005 · Base on Bluefin DX](docs/adr/0005-base-on-bluefin-dx.md) | Why Margine is a Bluefin DX bootc image plus a small delta |
| [Roadmap](docs/roadmap.md) | Phase plan |

---

<p align="center">
  Built on <a href="https://projectbluefin.io/">Bluefin DX</a> (Fedora 44)
</p>
