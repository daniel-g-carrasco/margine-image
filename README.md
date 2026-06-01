<p align="center">
  <img src="assets/branding/margine-logo-wide.png" alt="Margine" width="500">
</p>

<p align="center">
  <strong>Margine</strong> — declarative spec, helpers, and validators for the
  <a href="https://github.com/daniel-g-carrasco/margine-image">Margine bootc image</a>.
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/daniel-g-carrasco/margine-image/main/docs/screenshots/lock-screen.png" alt="Margine lock screen" width="46%">
  &nbsp;
  <img src="https://raw.githubusercontent.com/daniel-g-carrasco/margine-image/main/docs/screenshots/activities-search.png" alt="Margine activities + search" width="46%">
</p>

<p align="center">
  <a href="docs/02-install-lab.md">Install / lab</a> ·
  <a href="docs/04-validation.md">Validate</a> ·
  <a href="docs/README.md">Documentation</a> ·
  <a href="docs/adr">Decisions</a> ·
  <a href="docs/roadmap.md">Roadmap</a>
</p>

---

## What this repo is

The **spec + helpers** repo for Margine. The companion repo
[`margine-image`](https://github.com/daniel-g-carrasco/margine-image)
is the build pipeline (Containerfile + CI). At build time, that
pipeline fetches the contents of this repo and bakes:

- `declarations/margine-atomic.yaml` → `/usr/share/margine/declarations.yaml`
- `scripts/configure-*` → `/usr/bin/margine-configure-*`
- `scripts/validate-*` → `/usr/bin/margine-validate-*`
- `scripts/install-user-extensions` → `/usr/bin/margine-install-user-extensions`
- `scripts/configure-zen-browser` → `/usr/bin/margine-configure-zen-browser`
- `scripts/collect-diagnostics` → `/usr/bin/margine-collect-diagnostics`
- `files/margine-fetch` + fastfetch config → `/usr/bin/margine-fetch`
- `assets/branding/plymouth/` → `/usr/share/plymouth/themes/margine/`
- branding logos / wallpapers under `/usr/share/{pixmaps,backgrounds,...}`

Margine is **live**: pushed as
`ghcr.io/daniel-g-carrasco/margine:stable` (only after a candidate
image passes a QEMU smoke-boot) and distributed as Anaconda ISO +
qcow2 via BitTorrent + Internet Archive mirrors at
<https://files.the-empty.place/>.

## Repo layout

| Path | Contents |
| --- | --- |
| `declarations/` | The single source of truth: `margine-atomic.yaml` describes desired system state (system layer, Flatpak preinstall, GNOME extensions/settings/keybindings/app folders, default applications, home layout, ujust recipes). All `configure-*` helpers read this and apply it. |
| `scripts/configure-*` | Idempotent helpers that apply parts of the declaration. Default to dry-run; pass `--apply` to act. Live as `/usr/bin/margine-configure-*` in the image. |
| `scripts/validate-*` | Read-only validators (atomic layout, CachyOS kernel, hardware/media stack, gaming runtime, end-to-end acceptance test). Live as `/usr/bin/margine-validate-*` in the image. |
| `scripts/install-user-extensions` | Installs the non-RPM GNOME extensions (o-tiling, Hide Cursor, Caffeine, Tiling Shell, Search Light) into `~/.local/share/gnome-shell/extensions/`. |
| `docs/` | Architecture, install/lab procedure, validation runbook, ADRs, roadmap, lessons-learned. |
| `assets/branding/` | Logos, wallpapers, Plymouth theme. |
| `files/margine-fetch/` | `margine-fetch` script + fastfetch config + ASCII logo. |
| `config/topgrade.toml` | Legacy accessory-update profile (Topgrade is no longer used as Margine inherits Bluefin's `uupd.timer` — kept for reference). |

## Quick checks

The validators are read-only and safe to run on any deployed Margine
system:

```sh
margine-validate-atomic-layout          # ostree layout, mounts, Secure Boot, TPM2
margine-validate-cachyos-kernel         # kernel version, module signatures, MOK
margine-validate-hardware-media-stack   # Mesa/Vulkan/VA-API/PipeWire/OpenCL
margine-validate-gaming-runtime         # gaming-relevant runtime bits
margine-collect-diagnostics             # full snapshot for triage
```

Plus there's an end-to-end **acceptance test** (`scripts/validate-margine-system`)
that wraps everything and prints a single PASS/FAIL verdict — used in
the smoke-boot CI step and after every manual `bootc upgrade`. It's
not yet baked into `/usr/bin` (lives in this repo only).

## Documentation

Full index and reading order: [docs/README.md](docs/README.md)

| Document | What it covers |
| --- | --- |
| [Goals](docs/00-goals.md) | What Margine is and isn't, scope boundaries |
| [Architecture](docs/01-architecture.md) | bootc + composefs + rpm-ostree model |
| [Install lab](docs/02-install-lab.md) | VM lab procedure (or use the ISO from `files.the-empty.place`) |
| [Custom partitioning](docs/02a-custom-partitioning.md) | Anaconda guide with LUKS2 + `@data` Btrfs subvolume |
| [Lab VM setup](docs/02b-lab-vm-setup.md) | libvirt VM provisioning for the lab |
| [CachyOS kernel](docs/03-cachyos-kernel.md) | Why CachyOS, MOK signing strategy |
| [Validation](docs/04-validation.md) | Read-only validators + acceptance test |
| [Known risks](docs/05-known-risks.md) | Risks and mitigations for each delta |
| [Secure Boot + TPM2](docs/07-secure-boot-tpm2.md) | Disk encryption + auto-unlock via systemd-cryptenroll |
| [GNOME personal layer](docs/08-gnome-personal-layer.md) | Extensions, keybindings, app folders |
| [Declarative model](docs/09-declarative-model.md) | How declarations drive helpers |
| [Hardware/media stack](docs/10-hardware-media-stack.md) | Mesa, codecs, PipeWire, VA-API, OpenCL |
| [Gaming runtime](docs/11-gaming-runtime.md) | Optional gaming layer (Steam, Lutris, Heroic, …) |
| [Update orchestration](docs/12-update-orchestration.md) | uupd / bootc / Flatpak / Brew daily updates |
| [Expected behaviors](docs/14-expected-behaviors.md) | What "healthy" looks like at runtime |
| [Host layer](docs/15-host-layer.md) | What's baked into the image vs runtime |
| [Developer toolbox](docs/16-developer-toolbox.md) | Toolbox / Distrobox / Brew setup |
| [Keyboard bindings](docs/17-keyboard-bindings.md) | Hyprland-style binds applied on top of GNOME |
| [Roadmap](docs/roadmap.md) | Phases, current status |
| [ADRs](docs/adr/) | Architectural decisions with context and trade-offs |
| [Lessons learned](docs/lessons-learned/) | Postmortems with what changed in CI/spec |

## License

Apache-2.0. See [LICENSE](LICENSE).

---

<p align="center">
  Built on <a href="https://github.com/ublue-os/bluefin">Bluefin DX</a> /
  <a href="https://fedoraproject.org/atomic-desktops/silverblue/">Fedora Silverblue</a>.
  Distribution via <a href="https://files.the-empty.place">files.the-empty.place</a>
  + <a href="https://archive.org">Internet Archive</a>.
</p>
