<div align="center">

<img src="assets/branding/margine-logo-wide.png" alt="Margine" width="420">

### The *what* of Margine.

Declarative spec, configuration helpers, and system-state validators for
the [Margine distribution](https://github.com/daniel-g-carrasco/margine-image).

[**📥 Download Margine**](https://margine.the-empty.place/#install) ·
[**📖 Documentation**](docs/README.md) ·
[**📋 Roadmap**](docs/roadmap.md) ·
[**🛠 Build pipeline**](https://github.com/daniel-g-carrasco/margine-image)

</div>

---

> **Looking for the distro itself?** Go to
> [margine-image](https://github.com/daniel-g-carrasco/margine-image)
> — that repo's README has *what Margine is*, screenshots, the two
> flavours (base **Margine** and **Margine Gaming** variant), and
> the download/install instructions (ISO, `rpm-ostree rebase`,
> `bootc switch` between flavours). This repo is the *source code*
> of everything the distro applies to the system.

## What this repo is for

Margine isn't "a folder of dotfiles copied by hand". It's a **distribution
built by a CI pipeline**, and that pipeline (in
[`margine-image`](https://github.com/daniel-g-carrasco/margine-image))
needs to know:

- **What** we want on the system (which extensions, apps, keybinds,
  app folders, default applications, home layout, …)
- **How** to apply it (idempotent scripts that read the spec)
- **How to verify it** (read-only validators that report "OK" or "drift")

This repo is exactly that "what + how + verify".

| Directory | Contents |
| --- | --- |
| `declarations/` | The **declarative spec** (`margine-atomic.yaml`). Single source of truth for GNOME extensions, app folders, keybinds, gsettings, preinstalled apps, home layout. |
| `scripts/configure-*` | Idempotent helpers that read the spec and apply. Default to dry-run; pass `--apply` to act. Become `/usr/bin/margine-configure-*` in the image. |
| `scripts/validate-*` | Read-only validators (atomic layout, CachyOS kernel, hardware/media stack, gaming runtime, end-to-end acceptance test). Become `/usr/bin/margine-validate-*`. |
| `scripts/install-user-extensions` | Installs the non-RPM GNOME extensions (o-tiling, Hide Cursor, Search Light) under `~/.local/share/gnome-shell/extensions/`. Also prunes anything listed under `removed_user_install` in the spec (Tiling Shell, dropped 2026-06-02 in favour of o-tiling). |
| `docs/` | Architecture, ADRs, install lab, lessons-learned, validation runbook, roadmap. |
| `assets/branding/` | Logos, wallpaper, Plymouth theme. |
| `files/margine-fetch/` | `margine-fetch` script + fastfetch config + ASCII logo. |

## Quick check on a deployed system

```sh
margine-validate-atomic-layout          # ostree, mounts, Secure Boot, TPM2
margine-validate-cachyos-kernel         # version, signature, MOK
margine-validate-hardware-media-stack   # Mesa/Vulkan/VA-API/PipeWire
margine-validate-gaming-runtime         # gaming runtime
margine-collect-diagnostics             # snapshot for troubleshooting
```

Plus there's `scripts/validate-margine-system` (end-to-end acceptance
test with a single PASS/FAIL verdict line) used both in CI and after a
manual `bootc upgrade`.

## Documentation

Full index: [**docs/README.md**](docs/README.md). To get started:

| Doc | What it covers |
| --- | --- |
| [00-goals](docs/00-goals.md) | Goals, non-goals, working hypotheses |
| [01-architecture](docs/01-architecture.md) | bootc / composefs / rpm-ostree model |
| [04-validation](docs/04-validation.md) | Read-only validators + acceptance test |
| [09-declarative-model](docs/09-declarative-model.md) | How the spec drives the helpers |
| [18-observability](docs/18-observability.md) | ntfy + staleness check + post-upgrade notify |
| [19-iso-distribution](docs/19-iso-distribution.md) | ISO pipeline via Internet Archive |
| [roadmap](docs/roadmap.md) | Current state of the project phases |
| [adr/](docs/adr) | Architectural decisions |
| [lessons-learned/](docs/lessons-learned) | Operational postmortems |

## Contributing

To change *what* Margine does = edit
[`declarations/margine-atomic.yaml`](declarations/margine-atomic.yaml).
PR welcome. On every run of the build pipeline (in `margine-image`),
the new versions of spec and helpers are picked up automatically.

To change *how* it does it = edit a script in `scripts/`. All are
Python or shell, all idempotent, all with `--apply` to distinguish
dry-run from actual change.

To change *how it's verified* = add a check to one of the `validate-*`,
or a new validator if we're covering new surface area.

## License

Apache-2.0. See [LICENSE](LICENSE).
