<div align="center">

<img src="docs/branding/margine-logo-wide.png" alt="Margine" width="420">

### A polished, immutable Linux desktop that just works.

Built on [Bluefin DX](https://projectbluefin.io/), with a Secure Boot-signed
[CachyOS](https://cachyos.org/) kernel, a tiling-friendly GNOME, every codec
already installed, and a curated set of apps.

[**📥 Download**](https://files.the-empty.place/) ·
[What it is](#what-it-is) ·
[Highlights](#highlights) ·
[Install](#install) ·
[For developers](#for-developers)

</div>

---

## What it is

Margine is a **Linux desktop distribution** in the immutable / atomic
tradition (Fedora Silverblue + Universal Blue). A complete operating
system that installs in one shot, updates safely, and where everything
a regular user needs — audio/video codecs, GPU drivers, a well-tuned
GNOME, apps for office / photo / video / dev — **works from minute
zero**, without opening a terminal.

Built for people who want a Linux that *works for them* instead of
having to be configured for hours. macOS-style "everything in its
place" on top of Fedora foundations.

## Highlights

| ✨ | |
| --- | --- |
| 🎬 **All codecs preinstalled** | H.264, H.265/HEVC, AAC, MP3, Dolby, DTS — full playback and hardware acceleration out of the box. Same media stack as Bluefin (Mesa freeworld + full ffmpeg). |
| ⚡ **CachyOS kernel** | `BORE` scheduler (more responsive than the default), SSD/NVMe I/O tuning, parameters tuned for desktop. Under the hood: the same kernel powering people who squeeze more FPS in gaming and lower latency in DAWs. **Signed by Margine for Secure Boot** (no need to disable anything). |
| 🛡 **Immutable, atomic system** | `/usr` is read-only; every update is a **whole image** (not package-by-package). If something goes wrong, `bootc rollback` brings you back in 5 seconds. No "pacman broke my system", ever. |
| 🪟 **Smart tiling** | GNOME with [o-tiling](https://github.com/oliwebd/o-tiling): binary-tree auto-split à la Hyprland, `Super+Arrow` to move windows, `Super+Shift+Arrow` to switch focus. Tile-style productivity without learning a full window manager. |
| 🎨 **Yellow accent + dark mode** | Autumn leaves wallpaper, clean black Plymouth boot splash, GDM without distro-spam logos. Polished down to the pixel. |
| 📦 **Apps ready to go** | Zen Browser, Bitwarden, LibreOffice, GIMP, Inkscape, darktable, Audacity, OBS Studio, EasyEffects, Reaper, Apostrophe — installed via Flatpak on first boot. No bloatware, no shopping cart. |
| 🔒 **Secure Boot + LUKS2 + TPM2** | Security stack on by default. Encrypted disk, kernel signed with the Margine key, optional TPM2 auto-unlock. |
| 🔄 **Silent, automatic updates** | `bootc upgrade` at night. Flatpak update. No "you must update" pop-ups. The system keeps itself current; if a release would be broken, **you don't get it** (see CI below). |
| 🧪 **Verified build pipeline** | Every image is built, inspected (Layer A guardrails), **booted in QEMU** in CI, and only if it survives does it get promoted to `:stable`. No "compiled but won't boot" releases. |
| 🇮🇹 **Italian app folders** | GNOME activities grid categorized into 6 Italian folders: Office, Grafica, Foto, Audio, Video, Sistema. |

## Why Margine (vs picking something else)

- **What on stock Fedora needs `rpm-fusion` + `dnf install`, here is
  already there.** No more "why doesn't H.265 play?" or "why is Netflix
  capped at 480p?". The media stack is complete from the first boot.
- **What on Arch needs a month of scripting (CachyOS kernel signed
  for Secure Boot, a base system that doesn't break on updates, GNOME
  with tiling configured, disk encryption) is boxed in here.** You
  save that month and keep your machine.
- **Updates that don't break.** Immutable system + CI smoke-boot test
  = the `:stable` you receive has already booted in a test VM. If a
  day ever turns out bad, `bootc rollback` brings you to the previous
  deployment in 5 seconds. **There is no scenario "I'm stuck after the
  update"**.
- **Real performance.** CachyOS BORE scheduler makes the desktop
  visibly more responsive under load (compilation, video editing,
  browsing with 30+ tabs). On laptops, battery life similar to stock
  Fedora but with snappier response.
- **GNOME stays GNOME.** No custom DE to learn. Every GNOME extension
  works; you can add or remove anything from Extensions Manager.
  Margine's choices are *defaults*, not *enforcement*.
- **Privacy-first.** No distro telemetry. Zen Browser as default
  browser. DuckDuckGo as default search engine. Cloudflare DNS-01 for
  the project's own TLS.
- **Not alone underneath.** Below the deltas, this is Bluefin DX
  (actively maintained by Universal Blue, large community), which is
  Fedora Silverblue (Red Hat). All upstream upstream the whole way.

## Screenshots

<div align="center">

<img src="docs/screenshots/activities-search.png" alt="GNOME Activities with search open showing Margine extensions and dock" width="80%">

<br><br>

<img src="docs/screenshots/lock-screen.png" alt="Lock screen with autumn-leaves wallpaper" width="56%">

</div>

## Install

Two routes.

### 🟢 Option A — Margine ISO (recommended)

Single-shot install: download the ISO, install, you're on Margine.

1. Go to <https://files.the-empty.place/>
2. Download via **BitTorrent** (recommended) or **direct HTTP**.
   Same bytes, sha256 cross-checkable; the torrent is more robust
   on flaky connections.
3. Boot the ISO. Anaconda (Fedora's installer) walks you through:
   - **UEFI with Secure Boot enabled**
   - **Encrypted disk (LUKS2)** — strong passphrase, optional TPM2 later
   - **Btrfs** (the default)
4. Reboot, and you're on Margine.
5. **One initial configuration**:
   ```sh
   ujust margine-bootstrap          # applies home layout + GNOME + extensions
   ```
   Log out / log back in to refresh GNOME Shell.

### 🟡 Option B — Rebase from existing Bluefin

If you already have Bluefin (or are about to do a fresh install):

```sh
# From a fresh Bluefin:
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/daniel-g-carrasco/margine:stable
systemctl reboot
```

Then:
1. **First boot after rebase** — `mok-enroll.service` queues the MOK key.
2. **Second reboot** — the **MOK Manager** screen appears (shim's
   blue-and-grey UI). `Enroll MOK` → `Continue` → `Yes` → type the
   MOK password → reboot. From here on the CachyOS kernel boots
   under Secure Boot.
3. **`ujust margine-bootstrap`** as above.

### Post-install check

```sh
mokutil --sb-state                       # SecureBoot enabled
uname -r                                 # 7.0.x-cachyos*.fc44.x86_64
margine-validate-atomic-layout
margine-validate-cachyos-kernel
```

### Gaming layer (opt-in)

Steam + Lutris + Heroic + Bottles + Protontricks + ProtonUp-Qt as
Flatpaks, plus gamescope + MangoHud + vkBasalt + GameMode + goverlay
+ steam-devices as RPM packages. Reversible at any time.

```sh
ujust margine-gaming            # opt in
ujust margine-gaming-remove     # opt out
```

## What's inside (for the curious)

<details>
<summary>Full technical stack</summary>

### Base
- **Bluefin DX (stable)** — Universal Blue's curated developer image
  built on Fedora Silverblue 44
- Codecs / Mesa freeworld / virt stack (libvirt, qemu-kvm, virt-manager,
  swtpm, edk2-ovmf) / container tooling (podman, docker, distrobox,
  toolbox) / VS Code (Microsoft repo) / Cockpit / Tailscale / bpftrace
  / sysprof — all inherited unchanged from Bluefin.

### Kernel
- **CachyOS mainline** from the `bieszczaders/kernel-cachyos` COPR
- Signed by Margine: vmlinuz via `sbsign`, every `.ko*` via `sign-file`
- MOK enrollment at first boot via `mok-enroll.service`

### Enabled GNOME extensions
- AppIndicator Support, Bazaar Integration, Blur My Shell,
  Dash to Dock, Gradia Integration, GSConnect — *from Bluefin*
- Search Light — global search bar
- **o-tiling** — binary-tree tiling auto-split
- **Hide Cursor** — hides the pointer while typing
- **Caffeine** — keep-screen-on toggle in the top bar

### Preinstalled apps (Flatpak)
Zen Browser, Bitwarden, LibreOffice, Gapless (music player),
GIMP, Inkscape, darktable, Audacity, OBS Studio, EasyEffects,
Reaper (DAW), Apostrophe (markdown).

VS Code is already there from Bluefin (no need to install it).

### Security
- Secure Boot enabled (Margine MOK)
- LUKS2 disk encryption
- TPM2 auto-unlock via `systemd-cryptenroll` (optional, manual)
- `cosign` signature on the image pushed to ghcr.io

### Updates
- `bootc upgrade` daily via `uupd.timer` (inherited from Bluefin)
- `flatpak update`, `brew upgrade`, `distrobox upgrade` orchestrated
  by `uupd`
- Rollback via `bootc rollback` (five seconds, always)

### CI / build pipeline
- `build.yml` on a self-hosted runner: publishes `:candidate`
- `smoke-boot.yml`: boots `:candidate` in QEMU; on success, promotes to `:stable`
- `build-disk.yml`: builds ISO + qcow2, publishes via Internet Archive
- Layer A guardrails: `systemd-analyze verify default.target` +
  initramfs sanity + helpers/branding/passwd presence
- ntfy push notifications for build / smoke-boot / disk-build

</details>

## For developers

The spec, configuration, and helpers live in
[`margine-fedora-atomic`](https://github.com/daniel-g-carrasco/margine-fedora-atomic).
This repo (`margine-image`) is just the **build pipeline**: Containerfile,
build.sh, CI workflows.

To change *which* apps Margine preinstalls, *which* extensions it
enables, *which* keybinds it applies, etc. → go to the other repo,
edit `declarations/margine-atomic.yaml`, send a PR. The build pipeline
picks up the new versions of the helpers and the spec on every run.

For architecture discussion: [docs/](https://github.com/daniel-g-carrasco/margine-fedora-atomic/tree/main/docs)
has ADRs, lessons-learned, and the roadmap.

## Credits

- [**Bluefin**](https://projectbluefin.io/) — the base image; Margine
  adds only the few things in the table above. Without Bluefin this
  project wouldn't exist.
- [**Universal Blue**](https://universal-blue.org/) — image-template,
  CI patterns, uupd.
- [**CachyOS**](https://cachyos.org/) — scheduler and kernel patches.
- [**Origami Linux**](https://gitlab.com/origami-linux/images) — reference
  script for MOK-signing the kernel.
- [**MorrOS**](https://github.com/morrolinux/morros) — CI workflow
  inspiration.
- [**hhd-dev/rechunk**](https://github.com/hhd-dev/rechunk) — ostree
  rechunking action.
- [**Internet Archive**](https://archive.org/) — permanent mirror and
  BitTorrent seed for the ISOs.

## License

Apache-2.0.
