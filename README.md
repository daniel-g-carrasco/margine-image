<div align="center">

<img src="docs/screenshots/lock-screen.png" alt="Margine" width="700">

# Margine

**Un desktop Linux pronto all'uso, immutabile, veloce, e finalmente *bello*.**

Basato su [Bluefin DX](https://projectbluefin.io/), con kernel
[CachyOS](https://cachyos.org/) firmato per Secure Boot, GNOME tiling-friendly,
codec già installati e app curate.

[**📥 Scarica**](https://files.the-empty.place/) ·
[Cos'è](#cosè-margine) ·
[Caratteristiche](#caratteristiche) ·
[Installa](#install) ·
[Per gli sviluppatori](#per-gli-sviluppatori)

</div>

---

## Cos'è Margine

Margine è una **distribuzione Linux desktop**, in linea con la tradizione
*atomic / immutable* di Fedora Silverblue + Universal Blue. È un sistema
operativo completo che si installa, fa upgrade in modo sicuro, e dove tutto
quello che serve a un utente normale — codec audio/video, driver, GNOME ben
configurato, app preinstallate per ufficio / foto / video / sviluppo —
**funziona da subito**, senza terminale.

Pensata per chi vuole un Linux *che lavori per lui* invece di doverlo
configurare per ore. Tradizione macOS-style "tutto al suo posto" sopra
fondamenta Fedora.

## Caratteristiche

| ✨ | |
| --- | --- |
| 🎬 **Tutti i codec preinstallati** | H.264, H.265/HEVC, AAC, MP3, Dolby, DTS — riproduzione e accelerazione hardware fuori dalla scatola. Stesso stack di Bluefin (Mesa freeworld + ffmpeg full). |
| ⚡ **Kernel CachyOS** | Scheduler `BORE` (più reattivo del default), tuning I/O per SSD/NVMe, parametri ottimizzati per desktop. Sotto cofano: stesso kernel di chi tira fuori più FPS in gaming e meno latenza nelle DAW. Firmato Margine per **Secure Boot** (non serve disabilitare nulla). |
| 🛡 **Sistema immutabile + atomic** | `/usr` è in sola lettura; ogni aggiornamento è un'**immagine intera** (non pacchetto-per-pacchetto). Se qualcosa va male, `bootc rollback` ti riporta indietro in 5 secondi. Niente "ha rotto pacman", mai. |
| 🪟 **Tiling intelligente** | GNOME con [o-tiling](https://github.com/oliwebd/o-tiling): auto-split binario alla Hyprland, `Super+frecce` per spostare le finestre, `Super+Shift+frecce` per cambiare focus. Productivity tile-style senza dover imparare un window manager intero. |
| 🎨 **GNOME accent giallo + dark mode** | Wallpaper foglie d'autunno, Plymouth boot splash nero pulito, GDM senza loghi distro spammosi. Curato fino al pixel. |
| 📦 **App già pronte** | Zen Browser, Bitwarden, LibreOffice, GIMP, Inkscape, darktable, Audacity, OBS Studio, EasyEffects, Reaper, Apostrophe — installate via Flatpak al primo boot. Niente bloatware, niente shopping cart. |
| 🔒 **Secure Boot + LUKS2 + TPM2** | Stack di sicurezza di default. Disco cifrato, kernel firmato con la chiave Margine, possibile auto-unlock via TPM2. |
| 🔄 **Update automatici, silenziosi** | `bootc upgrade` di notte. Flatpak update. Niente notifiche "ti devi aggiornare", niente popup. Il sistema si tiene aggiornato da solo, e se mai un update fosse rotto **non te lo dà** (vedi sotto). |
| 🧪 **Pipeline build verificata** | Ogni immagine viene buildata, ispezionata (Layer A guardrails), **bootata in QEMU** in CI, e solo se sopravvive arriva a `:stable`. Niente release "compila ma non boota". |
| 🇮🇹 **App folder in italiano** | Categorizzazione delle app del menu GNOME in 6 cartelle italiane: Office, Grafica, Foto, Audio, Video, Sistema. |

## Galleria

<div align="center">

<img src="docs/screenshots/lock-screen.png" alt="Lock screen con wallpaper foglie d'autunno" width="48%">
&nbsp;
<img src="docs/screenshots/activities-search.png" alt="GNOME activities con search aperta" width="48%">

</div>

## Vantaggi pratici (perché Margine, non un'altra)

- **Quello che su Fedora vanilla richiede `rpm-fusion` + `dnf install`,
  qui è già lì.** Niente "perché H.265 non parte?" o "perché Netflix
  mi dà 480p?". Lo stack media è completo dal primo boot.
- **Quello che su Arch richiede un mese di scripting (kernel CachyOS
  firmato per Secure Boot, sistema base che non si rompe agli
  aggiornamenti, GNOME con tiling configurato, sicurezza disco)
  qui è inscatolato.** Risparmi quel mese e ti tieni la macchina.
- **Aggiornamenti che non rompono.** Sistema immutabile + smoke-test
  in CI = la `:stable` che ricevi ha già bootato in una VM di test.
  Se mai fosse comunque un giorno no, `bootc rollback` ti riporta al
  deployment precedente in 5 secondi. **Non esiste lo scenario "sono
  rimasto bloccato dopo l'update"**.
- **Performance reali.** CachyOS scheduler BORE rende il desktop
  visibilmente più reattivo sotto carico (compilation, video editing,
  navigazione con 30+ tab). Su laptop, autonomia simile a Fedora di
  default ma con risposta migliore.
- **GNOME comunque GNOME.** Niente DE custom da imparare. Tutte le
  estensioni GNOME funzionano, ognuno può togliere o aggiungere
  liberamente dal Extensions Manager. Le scelte di Margine sono
  *default*, non *imposizione*.
- **Privacy-first.** Niente telemetria distro. Zen Browser come browser
  default. DuckDuckGo come motore di ricerca default. Cloudflare DNS-01
  per i certificati propri.
- **Non da soli.** Sotto, è Bluefin DX (manutenuto attivamente da
  Universal Blue, community grande), che è Fedora Silverblue (Red Hat).
  Tutto l'upstream upstream sotto.

## Install

Due strade.

### 🟢 Opzione A — ISO Margine (consigliata)

Installazione "single shot": scarichi l'ISO, installi, sei su Margine.

1. Vai su <https://files.the-empty.place/>
2. Scarica via **torrent** (raccomandato) o **HTTP diretto**.
   Sono bytes identici, sha256 cross-checkable; il torrent è più
   robusto su connessioni instabili.
3. Boota l'ISO. Anaconda (l'installer Fedora) ti guida:
   - **UEFI con Secure Boot attivo**
   - **Disco cifrato (LUKS2)** — passphrase forte, opzionale TPM2 dopo
   - **Btrfs** (default)
4. Riavvia, al primo boot sei su Margine.
5. **Una sola configurazione iniziale**:
   ```sh
   ujust margine-bootstrap          # applica home layout + GNOME + estensioni
   ```
   Logout / login per rinfrescare GNOME Shell.

### 🟡 Opzione B — Rebase da Bluefin esistente

Se hai già Bluefin (o ne hai un'installazione vergine da fare):

```sh
# Da Bluefin appena installato:
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/daniel-g-carrasco/margine:stable
systemctl reboot
```

Poi:
1. **Primo boot dopo rebase** — `mok-enroll.service` queue la chiave MOK.
2. **Secondo riavvio** — appare il **MOK Manager** (schermata blu/grigia
   di shim). `Enroll MOK` → `Continue` → `Yes` → digita la MOK
   password → riavvia. Da qui in poi il kernel CachyOS boota sotto
   Secure Boot.
3. **`ujust margine-bootstrap`** come sopra.

### Verifica post-install

```sh
mokutil --sb-state          # SecureBoot enabled
uname -r                    # 7.0.x-cachyos*.fc44.x86_64
margine-validate-atomic-layout
margine-validate-cachyos-kernel
```

### Layer Gaming (opt-in)

Steam + Lutris + Heroic + Bottles + Protontricks + ProtonUp-Qt come
Flatpak, plus gamescope + MangoHud + vkBasalt + GameMode + goverlay
+ steam-devices come pacchetti RPM. Disinstallabile in qualsiasi
momento.

```sh
ujust margine-gaming            # opt-in
ujust margine-gaming-remove     # opt-out
```

## Cosa c'è dentro (per i curiosi)

<details>
<summary>Stack tecnico completo</summary>

### Base
- **Bluefin DX (stable)** — Universal Blue's curated developer image
  basato su Fedora Silverblue 44
- Codec / Mesa freeworld / virt stack (libvirt, qemu-kvm, virt-manager,
  swtpm, edk2-ovmf) / container tooling (podman, docker, distrobox,
  toolbox) / VS Code (Microsoft repo) / Cockpit / Tailscale / bpftrace
  / sysprof — tutto inherited unchanged da Bluefin.

### Kernel
- **CachyOS mainline** dal COPR `bieszczaders/kernel-cachyos`
- Firmato da Margine: vmlinuz via `sbsign`, ogni `.ko*` via `sign-file`
- Enrollment MOK al primo boot tramite `mok-enroll.service`

### Estensioni GNOME abilitate
- AppIndicator Support, Bazaar Integration, Blur My Shell,
  Dash to Dock, Gradia Integration, GSConnect — *da Bluefin*
- Search Light — search bar globale
- **o-tiling** — tiling auto-split binario
- **Hide Cursor** — nasconde puntatore mentre scrivi
- **Caffeine** — keep-screen-on toggle nel top bar

### App preinstallate (Flatpak)
Zen Browser, Bitwarden, LibreOffice, Gapless (music player),
GIMP, Inkscape, darktable, Audacity, OBS Studio, EasyEffects,
Reaper (DAW), Apostrophe (markdown).

VS Code è già lì da Bluefin (non serve installarlo).

### Sicurezza
- Secure Boot abilitato (MOK Margine)
- LUKS2 disco cifrato
- TPM2 auto-unlock via `systemd-cryptenroll` (opzionale, manuale)
- `cosign` signature sull'immagine pushata su ghcr.io

### Aggiornamenti
- `bootc upgrade` daily via `uupd.timer` (inherited da Bluefin)
- `flatpak update`, `brew upgrade`, `distrobox upgrade` orchestrati
  da `uupd`
- Rollback con `bootc rollback` (cinque secondi, sempre)

### CI / build pipeline
- `build.yml` su self-hosted runner: produce `:candidate`
- `smoke-boot.yml`: boota `:candidate` in QEMU, se OK promuove a `:stable`
- `build-disk.yml`: produce ISO + qcow2, pubblica via Internet Archive
- Layer A guardrails: `systemd-analyze verify default.target` +
  initramfs sanity + helpers/branding/passwd presence
- ntfy push notifications per build / smoke-boot / disk-build

</details>

## Per gli sviluppatori

Spec, configurazioni e helpers vivono in
[`margine-fedora-atomic`](https://github.com/daniel-g-carrasco/margine-fedora-atomic).
Questo repo (`margine-image`) è solo il **build pipeline**: Containerfile,
build.sh, CI workflows.

Per modificare *quali* app Margine preinstalla, *quali* estensioni
abilita, *quali* keybinds applica, ecc. → vai sull'altro repo, modifica
`declarations/margine-atomic.yaml`, manda PR. Il build pipeline raccoglie
automaticamente le nuove versioni dei helpers e della spec ad ogni run.

Per discutere architettura: [docs/](https://github.com/daniel-g-carrasco/margine-fedora-atomic/tree/main/docs)
contiene ADR, lessons-learned, e roadmap.

## Credits

- [**Bluefin**](https://projectbluefin.io/) — base image, su cui Margine
  aggiunge poche cose (le 10 nella tabella sopra). Senza Bluefin questo
  progetto non esisterebbe.
- [**Universal Blue**](https://universal-blue.org/) — image-template,
  CI patterns, uupd.
- [**CachyOS**](https://cachyos.org/) — scheduler + kernel patches.
- [**Origami Linux**](https://gitlab.com/origami-linux/images) — script
  di reference per la sign-MOK del kernel.
- [**MorrOS**](https://github.com/morrolinux/morros) — pattern di
  workflow CI.
- [**hhd-dev/rechunk**](https://github.com/hhd-dev/rechunk) — ostree
  rechunking action.
- [**Internet Archive**](https://archive.org/) — mirror permanente e
  seed BitTorrent per le ISO.

## License

Apache-2.0.
