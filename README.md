# Margine

**A bootc image: Bluefin DX (Fedora 44) + CachyOS signed kernel + Margine deltas.**

Built nightly by GitHub Actions, pushed to
`ghcr.io/daniel-g-carrasco/margine:stable`.

This is the **image** repo. The companion repo
[`margine-fedora-atomic`](https://github.com/daniel-g-carrasco/margine-fedora-atomic)
holds the declarative spec (`declarations/margine-atomic.yaml`), ADRs,
lab docs, and the `configure-gnome-*` helpers. The image bakes the
helpers into `/usr/bin/margine-configure-*` and the YAML into
`/usr/share/margine/declarations.yaml`.

## What Margine adds on top of Bluefin DX

Margine's deltas are intentionally small. Everything not listed below
(codec replacement, Mesa freeworld, virt stack, container tooling, fonts,
hardware diagnostics, daily updates via `uupd.timer`, Homebrew support,
toolbox/distrobox, …) is **inherited unchanged** from Bluefin DX.

### 1 · System layer (baked into the image at build time)

| Item | Mechanism | Why |
| --- | --- | --- |
| **CachyOS mainline kernel** | replaces Bluefin's signed kernel; built from [`bieszczaders/kernel-cachyos`](https://copr.fedorainfracloud.org/coprs/bieszczaders/kernel-cachyos/) COPR | scheduler & I/O tuning; better laptop performance |
| **MOK signing of vmlinuz + modules** | `sbsign` (vmlinuz) + `sign-file` (every `.ko*`) | makes CachyOS bootable under Secure Boot |
| **First-boot MOK enrollment** | `mok-enroll.service` (oneshot) pipes the MOK password into `mokutil --import /usr/share/cert/MOK.der`, marker at `/var/.mok-enrolled` | one-time confirm in MOK Manager → CachyOS boots under Secure Boot |
| **`v4l2loopback`** kmod | akmod build at image time (best-effort; skipped if it fails to build) | virtual camera (OBS, etc.) |
| **Margine `/etc/os-release`** | overrides `NAME`, `ID`, `VARIANT_ID`, `PRETTY_NAME`, etc. | system identifies as Margine in `hostnamectl`, GNOME About, `os-release` consumers |

### 2 · Preinstalled Flatpak applications

System-wide via `/etc/ublue-os/system-flatpaks.list` (Universal Blue's
reconciliation mechanism). Installed on first boot from Flathub.

| Application | Flatpak ID | Category |
| --- | --- | --- |
| Zen Browser | `app.zen_browser.zen` | web browser |
| Bitwarden | `com.bitwarden.desktop` | password manager |
| LibreOffice | `org.libreoffice.LibreOffice` | office suite |
| Gapless | `com.github.neithern.g4music` | music player |
| GIMP | `org.gimp.GIMP` | raster graphics |
| Inkscape | `org.inkscape.Inkscape` | vector graphics |
| darktable | `org.darktable.Darktable` | photography RAW |
| Audacity | `org.audacityteam.Audacity` | audio editor |
| OBS Studio | `com.obsproject.Studio` | screen recording / streaming |
| EasyEffects | `com.github.wwmm.easyeffects` | PipeWire audio effects |
| Reaper | `fm.reaper.Reaper` | DAW |
| VSCodium | `com.vscodium.codium` | code editor |

> Optional / not preinstalled (declared as such in
> [`declarations/margine-atomic.yaml`](https://github.com/daniel-g-carrasco/margine-fedora-atomic/blob/main/declarations/margine-atomic.yaml)
> `flatpaks.optional_apps`, install manually with `flatpak install`):
> Steam, Lutris, Heroic, Bottles, Protontricks, ProtonUp-Qt, RetroArch,
> RetroDECK, Cartridges.

### 3 · GNOME Shell extensions

| Extension | Source | Status vs Bluefin |
| --- | --- | --- |
| AppIndicator Support | host RPM (inherited from Bluefin) | **enabled** by Margine |
| Bazaar Integration | host RPM (inherited from Bluefin) | **enabled** by Margine — shell hooks for [Bazaar](https://github.com/kolunmi/bazaar), Bluefin's GTK4 Flathub-first software center |
| Blur My Shell | host RPM (inherited from Bluefin) | **enabled** by Margine |
| Dash to Dock | host RPM (inherited from Bluefin) | **enabled** by Margine |
| Gradia Integration | host RPM (inherited from Bluefin) | **enabled** by Margine — adds an "Open in Gradia" action to the screenshot flow ([Gradia](https://github.com/AlexanderVanhee/Gradia) is a screenshot beautifier) |
| GSConnect | host RPM (inherited from Bluefin) | **enabled** by Margine |
| Search Light | git clone of [`icedman/search-light`](https://github.com/icedman/search-light) (user-installed) | **added** by Margine |
| Tiling Shell | [EGO 7065](https://extensions.gnome.org/extension/7065/tiling-shell/) (user-installed via `margine-install-user-extensions`) | **added** by Margine — replaces the unmaintained Forge |
| LogoMenu | host RPM (Bluefin default) | **disabled** by Margine — replaces the "Activities" text button with a distro-logo dropdown; pure branding (package stays installed) |

### 4 · GNOME defaults (via `zz1-margine.gschema.override`)

Loaded **after** Bluefin's `zz0-bluefin-modifications.gschema.override`,
so the keys below win.

| Setting | Value |
| --- | --- |
| `org.gnome.desktop.interface accent-color` | `yellow` |
| `org.gnome.shell favorite-apps` | Zen, Thunderbird, Nautilus, Ptyxis, VSCodium |
| `org.gnome.shell enabled-extensions` | the 6 enabled extensions above |
| Tiling Shell auto-tiling | `enable-autotiling=true`, `enable-snap-assist=true`, gaps=4 |
| Default terminal | inherits Bluefin's **Ptyxis** (no override) |
| Default web browser | Zen (set by `margine-configure-default-applications`) |

### 5 · User-state helpers (in `/usr/bin`)

Fetched at image build time from
[`margine-fedora-atomic`](https://github.com/daniel-g-carrasco/margine-fedora-atomic).
Read the declarative spec at `/usr/share/margine/declarations.yaml`.
All are idempotent and default to dry-run; use `--apply` to act.

| Command | Purpose |
| --- | --- |
| `margine-configure-default-applications` | Set MIME / `xdg-settings` handlers (browser, mail, terminal, image viewer, …) per Margine defaults |
| `margine-configure-gnome-appearance` | Apply `gsettings` values from the declarative spec (theme, fonts, dconf for extensions) |
| `margine-configure-gnome-extensions` | Enable / disable extensions per Margine policy |
| `margine-configure-gnome-keybindings` | Apply the Hyprland-style keybindings (`SUPER+1..0` workspaces, `SUPER+RETURN` Ptyxis, `SUPER+E` Nautilus, Tiling Shell directional binds, …) |
| `margine-configure-gnome-app-folders` | Group apps in the Activities grid by category (Internet / Productivity / Graphics / …) |
| `margine-configure-home-layout` | Create `~/data`, `~/dev`, `~/scratch` and their declared subdirs; rewrite `~/.config/user-dirs.dirs` and `~/.config/gtk-{3,4}.0/bookmarks` to match the spec (XDG remap + Nautilus sidebar) |
| `margine-install-user-extensions` | Install Tiling Shell + Search Light into `~/.local/share/gnome-shell/extensions/` |
| `margine-collect-diagnostics` | Read-only system snapshot for troubleshooting |
| `margine-validate-atomic-layout` | Read-only health check (ostree layout, mounts, Secure Boot, TPM2) |
| `margine-validate-cachyos-kernel` | Read-only kernel-related health check |
| `margine-validate-hardware-media-stack` | Read-only Mesa / Vulkan / VA-API / PipeWire / OpenCL check |
| `margine-validate-gaming-runtime` | Read-only gaming runtime check |

### 6 · What channel does what (user-facing summary)

| Want to install / change | Channel | How |
| --- | --- | --- |
| **GUI application** | **Flatpak** (preferred) | `flatpak install <id>` from Flathub. Already-shipped apps in §2 above. |
| **CLI tool that moves faster than Fedora** | **Homebrew on Linux** | `brew install <tool>` (e.g. `starship`, `lazygit`, `zellij`). Auto-updated daily by `uupd.timer`. |
| **Dev environment / SDK** | **Toolbox** (Fedora 44 default image) | `toolbox enter` then `dnf install …`. Inherits Bluefin's container tooling. |
| **Non-Fedora-distro tool** | **Distrobox** | `distrobox-create --image archlinux:latest` etc. |
| **System-wide package** | rpm-ostree layer (last resort) | `rpm-ostree install <pkg>`. Re-evaluate first whether Flatpak / Toolbox / Brew fits — they survive rebases for free. |
| **GUI app launcher (Activities grid)** | Folder layout in [`declarations/margine-atomic.yaml`](https://github.com/daniel-g-carrasco/margine-fedora-atomic/blob/main/declarations/margine-atomic.yaml) | Edit YAML → `margine-configure-gnome-app-folders --apply`. |
| **Keybinding** | `gnome.keybindings.*` in the YAML | Edit YAML → `margine-configure-gnome-keybindings --apply`. |
| **GNOME setting** | `gnome.settings.*` in the YAML | Edit YAML → `margine-configure-gnome-appearance --apply`. |
| **System updates** | **Inherited from Bluefin** | `uupd.timer` runs daily; orchestrates `bootc upgrade` + `flatpak update` + `brew upgrade` + `distrobox upgrade`. No user intervention. |

## Install

On a fresh Bluefin DX (or Fedora Atomic) install:

```sh
# Rebase to Margine
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/daniel-g-carrasco/margine:stable

# Reboot
systemctl reboot
```

On first boot:
- `mok-enroll.service` opens `mokutil --import` with the Margine MOK.
  Reboot again, the MOK manager will prompt for the password set at
  build time (see repo secrets).
- After MOK enrollment, the CachyOS kernel boots under Secure Boot.

## Build

Triggered automatically by GitHub Actions on push to `main` and nightly
at 10:05 UTC. The pipeline:

1. Stages MOK private key, certificate, and password from repo secrets
   (`MOK_KEY`, `MOK_CERT`, `MOK_PASSWORD`) into `/tmp/margine-secrets/`.
2. Runs `buildah build` with the secrets mounted to
   `/tmp/certs/MOK.{key,pem}` and `/tmp/certs/mok-password` so
   `custom-kernel/install.sh` can sign vmlinuz and the modules.
3. Pushes the image to `ghcr.io/<owner>/margine:stable` (plus dated
   tags).
4. Signs the published image with `cosign` using `COSIGN_PRIVATE_KEY`
   from repo secrets.

Required GitHub repo secrets:

| Name | Source | What it is |
| --- | --- | --- |
| `MOK_KEY` | `secrets/MOK.key` (local) | RSA private key for kernel signing |
| `MOK_CERT` | `secrets/MOK.pem` (local) | X509 certificate matching `MOK_KEY` |
| `MOK_PASSWORD` | `secrets/mok-password` (chosen by user) | Password for `mokutil --import` |
| `COSIGN_PRIVATE_KEY` | `secrets/cosign.key` (local) | cosign signing key |

The `secrets/` directory in this repo holds the **public** counterparts
(`MOK.pem`, `MOK.der`, `cosign.pub`) which are safe to commit and are
referenced by the image. The **private** keys are gitignored and must
be uploaded as GitHub Actions secrets.

## Source repo layout

```
.
├── Containerfile               # bootc image recipe
├── build_files/
│   ├── build.sh                # Margine deltas (kitty Flatpak,
│   │                             gschema override, fetch configure-*
│   │                             scripts from margine-fedora-atomic)
│   └── custom-kernel/
│       ├── install.sh          # CachyOS kernel install + MOK sign
│       └── origami-upstream.sh # Origami's reference script (kept for
│                                 attribution + future merges)
├── disk_config/                # ISO/disk metadata (unused for plain rebase)
├── secrets/
│   ├── MOK.pem                 # PUBLIC X509 cert (commit OK)
│   ├── MOK.der                 # PUBLIC DER cert (commit OK)
│   └── cosign.pub              # PUBLIC cosign key (commit OK)
├── .github/workflows/build.yml # CI: build + sign + push + cosign
└── README.md
```

## Credits

- The `custom-kernel/install.sh` script is derived from
  [Origami Linux's `modules/custom-kernel/custom-kernel.sh`](https://gitlab.com/origami-linux/images)
  ([mirror](https://github.com/john-holt4/Origami-Linux/blob/main/modules/custom-kernel/custom-kernel.sh)),
  simplified for Margine (single kernel variant, no Nvidia path).
- The Containerfile/CI structure follows the
  [Universal Blue image-template](https://github.com/ublue-os/image-template).
- The base image is
  [Bluefin DX (stable)](https://github.com/ublue-os/bluefin), built on
  Fedora 44.
- Inspired in workflow by
  [MorrOS](https://github.com/morrolinux/morros).

## License

Apache-2.0.
