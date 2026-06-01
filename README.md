# Margine

**A bootc image: Bluefin DX (Fedora 44) + CachyOS signed kernel + Margine deltas.**

<p align="center">
  <img src="docs/screenshots/lock-screen.png" alt="Margine lock screen with autumn-leaves wallpaper" width="46%">
  &nbsp;
  <img src="docs/screenshots/activities-search.png" alt="Margine GNOME activities + search with Margine extensions and dock" width="46%">
</p>

Built by GitHub Actions on push (and on demand), pushed to
`ghcr.io/daniel-g-carrasco/margine:stable` **only** after a candidate
image survives an end-to-end QEMU boot smoke-test (see [Build](#build)
below). Installable ISOs and qcow2 are published over BitTorrent +
HTTP mirror via Internet Archive, with the magnet/HTTP index served
at <https://files.the-empty.place/>.

This is the **image** repo. The companion repo
[`margine-fedora-atomic`](https://github.com/daniel-g-carrasco/margine-fedora-atomic)
holds the declarative spec (`declarations/margine-atomic.yaml`), ADRs,
lab docs, and the `configure-gnome-*` / `validate-*` helpers. The
image bakes the helpers into `/usr/bin/margine-configure-*` and the
YAML into `/usr/share/margine/declarations.yaml`.

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
| **Margine logo** | `/usr/share/pixmaps/margine-logo.png` (the file referenced by `LOGO=margine-logo` in os-release) | GNOME "About this system" shows the Margine logo |
| **Plymouth boot splash** | `/usr/share/plymouth/themes/margine/` (script-based theme: dark warm background + centered logo); set as default via `plymouth-set-default-theme margine`; initramfs regenerated | boot screen shows Margine instead of Fedora/Bluefin |
| **Desktop wallpaper** | `/usr/share/backgrounds/margine/autumn-leaves.png` (flat-color stylized autumn leaves on warm-brown background); set as default via gschema override on `org.gnome.desktop.background.picture-uri{,-dark}` | default desktop background on first login |
| **GDM login background** | dconf system database in `/etc/dconf/db/gdm.d/01-margine-background` pointing to the same wallpaper | login screen matches the desktop |
| **`/etc/issue`** | rewritten to `Margine \r (\m) — Bluefin DX + CachyOS signed kernel` | console / emergency shell shows Margine |
| **`margine-fetch`** + fastfetch config | `/usr/bin/margine-fetch` wraps `fastfetch --config /usr/share/fastfetch/margine.jsonc`; the config uses the ASCII logo from `/usr/share/margine/ascii-logo.txt` | `margine-fetch` in a terminal prints a Margine summary with the ASCII art logo |

### 2 · Preinstalled Flatpak applications

System-wide via `/usr/share/flatpak/preinstall.d/margine-defaults.preinstall`
(systemd's standard preinstall API, picked up by Bluefin/Universal Blue at
first boot — replaced the legacy `/etc/ublue-os/system-flatpaks.list`
which Bluefin no longer honors). Installed on first boot from Flathub.

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
| Apostrophe | `org.gnome.gitlab.somas.Apostrophe` | GTK 4 markdown viewer/editor |

> VS Code is **not** installed by Margine — Bluefin DX already
> preinstalls Visual Studio Code (Microsoft repo) with dev container
> tooling already configured. Margine keeps that.

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
| **o-tiling** | [oliwebd/o-tiling](https://github.com/oliwebd/o-tiling) (zip release v2.8.8, user-installed via `margine-install-user-extensions`) | **added** by Margine — binary-tree auto-split (Hyprland-style muscle memory). Replaced Tiling Shell mid-2026 after its v18 ghost-border bug. |
| **Hide Cursor** | [EGO 7252](https://extensions.gnome.org/extension/7252/hide-cursor/) (user-installed) | **added** by Margine — hides the mouse cursor when typing |
| **Caffeine** | [EGO 517](https://extensions.gnome.org/extension/517/caffeine/) (user-installed) | **added** by Margine — keep-screen-on toggle in the top bar |
| Tiling Shell | [EGO 7065](https://extensions.gnome.org/extension/7065/tiling-shell/) (still user-installed) | **installed but disabled** by Margine — kept around so you can switch back from Extensions Manager if you don't like o-tiling. |
| LogoMenu | host RPM (Bluefin default) | **disabled** by Margine — replaces the "Activities" text button with a distro-logo dropdown; pure branding (package stays installed) |

### 4 · GNOME defaults (via `zz1-margine.gschema.override`)

Loaded **after** Bluefin's `zz0-bluefin-modifications.gschema.override`,
so the keys below win.

| Setting | Value |
| --- | --- |
| `org.gnome.desktop.interface accent-color` | `yellow` |
| `org.gnome.desktop.interface color-scheme` | `prefer-dark` |
| `org.gnome.shell favorite-apps` | Zen, Thunderbird, Nautilus, Ptyxis, VS Code |
| `org.gnome.shell enabled-extensions` | the 10 enabled extensions above (canonical list, **replace-style** — `tilingshell` is removed if found in the existing list) |
| App folders | 6 folders: Office / Grafica / Foto / Audio / Video / Sistema |
| o-tiling | binary-tree auto-split active by default, `Super+Arrow` = move, `Super+Shift+Arrow` = focus |
| Default terminal | inherits Bluefin's **Ptyxis** (no override) |
| Default web browser | Zen (set by `margine-configure-default-applications`) |
| Zen Browser default search | DuckDuckGo via per-profile `user.js` (set by `margine-configure-zen-browser`) |

### 5 · User-state helpers (in `/usr/bin`)

Fetched at image build time from
[`margine-fedora-atomic`](https://github.com/daniel-g-carrasco/margine-fedora-atomic).
Read the declarative spec at `/usr/share/margine/declarations.yaml`.
All are idempotent and default to dry-run; use `--apply` to act.

| Command | Purpose |
| --- | --- |
| `margine-configure-default-applications` | Set MIME / `xdg-settings` handlers (browser, mail, terminal, image viewer, …) per Margine defaults |
| `margine-configure-gnome-appearance` | Apply `gsettings` values from the declarative spec (theme, fonts, dconf for extensions) |
| `margine-configure-gnome-extensions` | Enable extensions present on disk and **replace** `enabled-extensions` with the canonical Margine list (drops anything no longer declared, e.g. `tilingshell`) |
| `margine-configure-gnome-keybindings` | Apply the Hyprland-style keybindings (`SUPER+1..0` workspaces, `SUPER+RETURN` Ptyxis, `SUPER+E` Nautilus, o-tiling directional binds — `Super+Arrow` move / `Super+Shift+Arrow` focus, …) |
| `margine-configure-gnome-app-folders` | Group apps in the Activities grid into 6 folders (Office, Grafica, Foto, Audio, Video, Sistema) |
| `margine-configure-home-layout` | Create `~/data`, `~/dev`, `~/scratch` and their declared subdirs; rewrite `~/.config/user-dirs.dirs` and `~/.config/gtk-{3,4}.0/bookmarks` to match the spec (XDG remap + Nautilus sidebar) |
| `margine-configure-zen-browser` | Write a per-profile `user.js` that sets Zen Browser's default search engine to DuckDuckGo |
| `margine-install-user-extensions` | Install o-tiling, Hide Cursor, Caffeine, Tiling Shell, Search Light into `~/.local/share/gnome-shell/extensions/` (zip + git sources) |
| `margine-fetch` | Run `fastfetch` with Margine's ASCII logo and curated module set (os, kernel, packages, shell, GPU, memory, …) |
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
| **Gaming layer** (opt-in) | **`ujust margine-gaming`** | Installs Steam + Lutris + Heroic + Bottles + Protontricks + ProtonUp-Qt as system Flatpaks AND layers gamescope + MangoHud + vkBasalt + GameMode + goverlay + steam-devices via rpm-ostree. Reboot needed for the RPM layer; Flatpaks are immediate. Roll back with `ujust margine-gaming-remove`. Inspired by Bazzite but opt-in (default image stays lean). |

### 7 · ujust recipes added by Margine

Bluefin ships [`ujust`](https://github.com/casey/just) (the `just` wrapper)
with its own recipes for common tasks. Margine adds three more, available
from any terminal as `ujust <recipe>`:

| Recipe | Group | What it does |
| --- | --- | --- |
| `ujust margine-bootstrap` | Margine | Run all `margine-configure-*` helpers in sequence to apply the Margine user-state on a fresh login (idempotent, re-runnable). Optional flag `unattended` for non-interactive use (autostart). |
| `ujust margine-gaming` | Gaming | Opt into the gaming layer (see row above) |
| `ujust margine-gaming-remove` | Gaming | Roll back what `margine-gaming` installed |

Run `ujust` with no argument to see the full list (Bluefin's recipes + Margine's).

## Install

You have two paths.

- **Option A — Rebase from Bluefin.** The well-trodden path. Install a
  standard Bluefin from ISO, then `rpm-ostree rebase` to Margine. Steps
  1-4 below.
- **Option B — Margine ISO (single install).** Skip the Bluefin step
  entirely: download the Margine Anaconda ISO, install, done. See
  [Margine ISO](#option-b--install-from-margine-iso) at the end of this
  section.

### Option A — rebase from Bluefin

#### Step 1 · Install Bluefin from ISO

> **Important — there is no "Bluefin DX" ISO.** Universal Blue does not
> publish a separate DX (Developer Experience) installation image. DX is
> a *post-install runtime toggle* enabled via `ujust devmode` on a regular
> Bluefin install. **For Margine you don't need to enable devmode** —
> Margine's image is `FROM ghcr.io/ublue-os/bluefin-dx:stable`, so the
> entire DX package set (libvirt, qemu-kvm, virt-manager, swtpm,
> edk2-ovmf, podman-compose, distrobox, VS Code, Cockpit, Tailscale,
> bpftrace, sysprof, …) is **already baked into Margine** by the time
> you rebase. Skip `ujust devmode`.

Download the regular Bluefin stable ISO:

```sh
curl -L -o ~/Downloads/bluefin-stable-x86_64.iso \
  https://download.projectbluefin.io/bluefin-stable-x86_64.iso

# (optional but recommended) verify
curl -sL https://download.projectbluefin.io/bluefin-stable-x86_64.iso-CHECKSUM \
  | sha256sum -c - --ignore-missing
```

Install it. Recommended choices in Anaconda:
- UEFI firmware with **Secure Boot enabled** (BIOS-side setting before booting the ISO)
- **Full-disk encryption** (LUKS2 — set a strong passphrase, you can add TPM2 later)
- Btrfs (Anaconda default — keep it)
- Standard partitioning (we don't need custom Btrfs subvolumes for the smoke test)

#### Step 2 · Rebase to Margine

After Bluefin is installed and you're at the desktop:

```sh
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/daniel-g-carrasco/margine:stable
systemctl reboot
```

#### Step 3 · Enroll the Margine MOK (one-time)

- **First boot after rebase** — `mok-enroll.service` runs once and queues
  the Margine MOK certificate for import.
- **Reboot a second time** — the firmware shows the **MOK Manager**
  screen (shim's blue-and-grey UI). Choose `Enroll MOK` → `Continue` →
  `Yes` → type the MOK password (set at image build time; in the repo's
  GH Actions secret `MOK_PASSWORD`) → reboot.
- After this, the CachyOS kernel boots under Secure Boot. Verify:

  ```sh
  mokutil --sb-state          # SecureBoot enabled
  mokutil --list-enrolled     # see the Margine cert
  uname -r                    # 7.0.x-cachyos*.fc44.x86_64
  ```

#### Step 4 · Apply user-state (one-time)

```sh
ujust margine-bootstrap
```

This runs all 7 `margine-configure-*` helpers in sequence and applies
the Margine user-state declaration: `~/data` / `~/dev` / `~/scratch` +
XDG remap + Nautilus bookmarks + Tiling Shell + GNOME extensions +
keybindings + appearance + default applications + app folders.
Idempotent. Re-runnable after upgrades.

Log out and back in to refresh GNOME Shell.

#### (Optional) Step 5 · Opt into the gaming layer

```sh
ujust margine-gaming
```

See §6 ("Channel cheat sheet") and §1 ("System layer") above for what
each layer brings in.

### Option B · Install from Margine ISO

Skip the Bluefin step. Download the Margine Anaconda installer ISO and
install in one go.

Two equivalent sources (same bytes, sha256 cross-checkable):

- **BitTorrent (recommended)** — magnet link + `.torrent` file from
  <https://files.the-empty.place/>. Hosted by Internet Archive,
  seeded for as long as IA is up, distributed peer-to-peer.
- **Direct HTTP** — same URL, link to the IA mirror, also linked to the
  `.iso` copy on `files.the-empty.place` for the first ~7 days after
  each release (faster local fetch while IA propagation is fresh).

Installation flow:

1. Boot the ISO. Anaconda installer comes up.
2. Standard install, Btrfs default, LUKS2 strongly recommended.
3. On first boot you're already on Margine — no rebase step needed.
4. Steps 3 (MOK enrollment) and 4 (`ujust margine-bootstrap`) above
   still apply.

Behind the scenes the ISO carries a `bootc switch
ghcr.io/daniel-g-carrasco/margine:stable` in its kickstart `%post`, so
`bootc upgrade` from then on follows the same `:stable` tag as
Option A installs.

## Build

Triggered by GitHub Actions on every push to `main`. The pipeline runs
on a **self-hosted runner** (Proxmox VM `margine-builder`) and follows
a **candidate → stable** promotion model so a broken image can never
reach `:stable`:

1. **Stage MOK secrets** — `MOK_KEY` / `MOK_CERT` / `MOK_PASSWORD`
   from repo secrets into `/tmp/margine-secrets/` (wiped at end of job).
2. **Pre-build login to GHCR** — `podman login ghcr.io` with the
   workflow `GITHUB_TOKEN` so the base-image pull of
   `ghcr.io/ublue-os/bluefin-dx:stable` is authenticated (rate limit
   5000 req/h instead of 100 req/h for anonymous IP).
3. **Build image** — `buildah build` with MOK secrets mounted, runs
   `custom-kernel/install.sh` to install + sign vmlinuz / modules.
4. **Layer A guardrails** (`Verify image internals`) — inspect the
   freshly built image without booting: initramfs presence + sanity
   size, ostree-prepare-root in initramfs, kernel features
   (dm-crypt, btrfs, virtio_blk), MOK certificate, Plymouth theme,
   `/etc/passwd` not stripped post-rechunk, helpers under `/usr/bin`,
   bootstrap effects, branding assets, and a `systemd-analyze verify
   default.target` to catch any ordering-cycle regression
   before push.
5. **Move built image to root storage** — `podman save --format
   oci-archive` into `/var/tmp/margine.oci.tar` with sha256
   verify-twice, then `sudo skopeo copy oci-archive: containers-storage:`.
   The roundtrip via the OCI archive avoids the silent corruption
   that affected an in-memory `podman save | sudo podman load` pipe
   on the degraded-ZFS host.
6. **ReChunk** (`hhd-dev/rechunk@v1.2.4`) — re-commits the image to
   ostree-canonical form with composefs-friendly layering.
7. **Push to `:candidate` + `:candidate.YYYYMMDD`** — NOT to
   `:stable`. Only the candidate tag is updated by this workflow.
8. **Cosign sign** — signs the candidate digest with
   `COSIGN_PRIVATE_KEY`.
9. **Notify ntfy** — push notification to the maintainer's phone
   with the build outcome (success/failure) and a click-through to
   the run URL.

A separate workflow, **`smoke-boot.yml`**, is triggered by
`workflow_run` of the build above. It:

1. Pulls `ghcr.io/.../margine:candidate`.
2. Builds a qcow2 with `bootc-image-builder`.
3. Boots the qcow2 in QEMU + KVM on a GHA-hosted runner.
4. Watches the serial console for any of three signals that mean the
   boot reached a usable state: `gdm.service` started, or
   `graphical.target` reached, or `margine login:` getty banner.
5. **Only if that succeeds**, `skopeo copy --preserve-digests` promotes
   the candidate digest to `:stable` + `:stable.YYYYMMDD` + `:YYYYMMDD`.

So `:stable` is, by construction, an image that booted to a usable
state inside QEMU. If smoke-boot ever fails, `:stable` is not touched
and the maintainer gets a high-priority ntfy push to investigate.

A third workflow, **`build-disk.yml`**, runs on demand to produce
qcow2 + Anaconda ISO from the current `:stable`, uploads them to
Internet Archive (which auto-generates torrent + 3 HTTP mirrors), and
publishes a small HTML index page on `files.the-empty.place` with the
download links. Origin upload bandwidth stays free because the big
binaries are seeded by IA.

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
├── Containerfile                       # bootc image recipe
├── build_files/
│   ├── build.sh                        # Margine deltas (Flatpak preinstall,
│   │                                     gschema override, /etc/os-release
│   │                                     branding, Plymouth, MOTD suppression,
│   │                                     /etc/passwd seed unit, /etc/skel
│   │                                     systemd-user units, fetch configure-*
│   │                                     + validate-* helpers from
│   │                                     margine-fedora-atomic)
│   ├── 60-custom.just                  # ujust recipes (margine-bootstrap,
│   │                                     margine-gaming, margine-gaming-remove)
│   └── custom-kernel/
│       ├── install.sh                  # CachyOS kernel install + MOK sign
│       └── origami-upstream.sh         # Origami's reference script (kept
│                                         for attribution + future merges)
├── disk_config/                        # bootc-image-builder configs
│   ├── disk.toml                       # qcow2 disk image
│   └── iso-gnome.toml                  # Anaconda installer ISO (does the
│                                         `bootc switch` in %post)
├── docs/screenshots/                   # README images (lock + activities)
├── secrets/
│   ├── MOK.pem                         # PUBLIC X509 cert (commit OK)
│   ├── MOK.der                         # PUBLIC DER cert (commit OK)
│   └── cosign.pub                      # PUBLIC cosign key (commit OK)
├── .github/workflows/
│   ├── build.yml                       # main CI: build + sign + push :candidate
│   ├── smoke-boot.yml                  # QEMU boot test + promote → :stable
│   └── build-disk.yml                  # ISO + qcow2 + Internet Archive upload
├── CHANGELOG.md
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
