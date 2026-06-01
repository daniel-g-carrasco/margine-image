<div align="center">

<img src="assets/branding/margine-logo-wide.png" alt="Margine" width="500">

# margine-fedora-atomic

**Il "cosa" di Margine.** Spec dichiarativa, helper di configurazione,
e validator dello stato di sistema per la
[distro Margine](https://github.com/daniel-g-carrasco/margine-image).

<img src="https://raw.githubusercontent.com/daniel-g-carrasco/margine-image/main/docs/screenshots/lock-screen.png" alt="Margine lock screen" width="46%">
&nbsp;
<img src="https://raw.githubusercontent.com/daniel-g-carrasco/margine-image/main/docs/screenshots/activities-search.png" alt="Margine activities" width="46%">

[**📥 Scarica Margine**](https://files.the-empty.place/) ·
[**📖 Documentazione**](docs/README.md) ·
[**📋 Roadmap**](docs/roadmap.md) ·
[**🛠 Build pipeline**](https://github.com/daniel-g-carrasco/margine-image)

</div>

---

> **Cerchi la distro?** [margine-image](https://github.com/daniel-g-carrasco/margine-image)
> è il punto giusto: ha il README con cosa Margine È, e le istruzioni di
> install/download. Questo repo è il *codice sorgente* di tutto quello
> che la distro applica al sistema.

## A cosa serve questo repo

Margine non è "una cartella di dotfile copiati a mano". È una **distro
costruita da una pipeline CI**, e quella pipeline (in
[`margine-image`](https://github.com/daniel-g-carrasco/margine-image))
ha bisogno di sapere:

- **Cosa** vogliamo nel sistema (quali estensioni, app, keybind, app folder,
  default applications, home layout, ecc.)
- **Come** applicarlo (script idempotenti che leggono la spec)
- **Come verificarlo** (validator read-only che dicono "OK" o "drift")

Questo repo è esattamente quel "cosa + come + verifica".

| Cartella | Contenuto |
| --- | --- |
| `declarations/` | La **spec dichiarativa** (`margine-atomic.yaml`). Single source of truth per estensioni GNOME, app folder, keybind, gsettings, app preinstallate, home layout. |
| `scripts/configure-*` | Helper idempotenti che leggono la spec e applicano. Default dry-run; pass `--apply` per agire. Diventano `/usr/bin/margine-configure-*` nell'immagine. |
| `scripts/validate-*` | Validator read-only (atomic layout, kernel CachyOS, hardware/media stack, gaming runtime, acceptance test end-to-end). Diventano `/usr/bin/margine-validate-*`. |
| `scripts/install-user-extensions` | Installa le estensioni GNOME non-RPM (o-tiling, Hide Cursor, Caffeine, Tiling Shell, Search Light) sotto `~/.local/share/gnome-shell/extensions/`. |
| `docs/` | Architettura, ADR, install lab, lessons-learned, runbook validazione, roadmap. |
| `assets/branding/` | Logo, wallpaper, tema Plymouth. |
| `files/margine-fetch/` | Script `margine-fetch` + config fastfetch + ASCII logo. |

## Quick check su un sistema deployato

```sh
margine-validate-atomic-layout          # ostree, mount, Secure Boot, TPM2
margine-validate-cachyos-kernel         # versione, firma, MOK
margine-validate-hardware-media-stack   # Mesa/Vulkan/VA-API/PipeWire
margine-validate-gaming-runtime         # gaming runtime
margine-collect-diagnostics             # snapshot per troubleshooting
```

Plus c'è `scripts/validate-margine-system` (acceptance test end-to-end
con verdetto PASS/FAIL singolo) che è usato sia in CI sia dopo un
`bootc upgrade` manuale.

## Documentazione

Indice completo: [**docs/README.md**](docs/README.md). Per chi inizia:

| Doc | Cosa copre |
| --- | --- |
| [00-goals](docs/00-goals.md) | Obiettivi, non-obiettivi, ipotesi di lavoro |
| [01-architecture](docs/01-architecture.md) | bootc / composefs / rpm-ostree model |
| [04-validation](docs/04-validation.md) | Validator read-only + acceptance test |
| [09-declarative-model](docs/09-declarative-model.md) | Come la spec guida gli helper |
| [18-observability](docs/18-observability.md) | ntfy + staleness + post-upgrade notify |
| [19-iso-distribution](docs/19-iso-distribution.md) | Pipeline ISO via Internet Archive |
| [roadmap](docs/roadmap.md) | Stato attuale delle fasi del progetto |
| [adr/](docs/adr) | Decisioni architetturali |
| [lessons-learned/](docs/lessons-learned) | Postmortem operativi |

## Contribuire

Modificare *cosa* fa Margine = modificare
[`declarations/margine-atomic.yaml`](declarations/margine-atomic.yaml).
PR welcome. Ad ogni run del build pipeline (in `margine-image`) le
nuove versioni di spec e helper vengono raccolte automaticamente.

Modificare *come* lo fa = modificare uno script in `scripts/`.
Tutti sono Python o shell, tutti idempotenti, tutti con `--apply` per
distinguere dry-run da modifica reale.

Modificare *come si verifica* = aggiungere un check a uno dei
`validate-*`, o un nuovo validator se stiamo coprendo una superficie
nuova.

## License

Apache-2.0. See [LICENSE](LICENSE).
