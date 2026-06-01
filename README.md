<div align="center">

<img src="docs/branding/margine-logo-wide.png" alt="Margine" width="420">

### An immutable Linux desktop distribution.

Built on [Bluefin DX](https://projectbluefin.io/), with a Secure Boot-signed
[CachyOS](https://cachyos.org/) kernel, GNOME configured for tiling workflows,
a complete media stack, and a curated set of preinstalled applications.

[**Download**](https://files.the-empty.place/) ·
[What it is](#what-it-is) ·
[What you get](#what-you-get) ·
[Install](#install) ·
[For developers](#for-developers)

</div>

---

## What it is

Margine is a desktop Linux distribution that follows the immutable /
atomic model: the operating system is shipped as a versioned OCI image,
`/usr` is mounted read-only, and updates are applied by switching to a
new image rather than by modifying files in place. The same model used
by Fedora Silverblue and the Universal Blue images
(Bluefin, Bazzite, Aurora).

It targets users who want a complete, ready-to-use desktop without
configuring the media stack, the kernel, the disk-encryption pipeline,
or the GNOME defaults themselves. The trade-off is the standard one of
immutable distributions: package installation goes through Flatpak,
Toolbox, Distrobox or Homebrew rather than a system package manager;
in exchange, atomic upgrades and atomic rollbacks are first-class
operations.

## What you get

### A complete media stack from first boot
The base image includes Mesa with the freeworld codecs (proprietary
codecs not shipped in Fedora's stock Mesa for licensing reasons),
hardware video acceleration via VA-API/VDPAU, full ffmpeg with H.264 /
H.265/HEVC / AAC / MP3 / AC3 / DTS, and the GStreamer plugin set. DRM
content in Firefox/Chromium-based browsers works without additional
setup.

### CachyOS kernel, signed for Secure Boot
Mainline kernel from the
[`bieszczaders/kernel-cachyos`](https://copr.fedorainfracloud.org/coprs/bieszczaders/kernel-cachyos/) COPR,
which includes the BORE scheduler (lower-latency desktop response under
load) and several upstream-pending performance patches. Margine signs
the kernel image and every kernel module at build time with its own
MOK, so Secure Boot stays enabled. The first boot after install enrolls
the public key into shim's MOK store via a one-shot service; from
then on the kernel chain of trust is verified at every boot.

### Immutable filesystem and atomic upgrades
The `/usr` tree is part of the bootc deployment and is mounted
read-only. Software updates pull a new OCI image from the registry
and stage it as a new deployment; the previous deployment is kept
on disk. After reboot the new deployment becomes active; if it fails
to boot or otherwise misbehaves, `bootc rollback` switches back to
the previous one at the next reboot. Daily updates are orchestrated
in the background by Bluefin's `uupd.timer`.

### GNOME with a tiling workflow
Stock GNOME Shell, configured with the
[o-tiling](https://github.com/oliwebd/o-tiling) extension
(binary-tree auto-split inspired by Hyprland) and a Hyprland-style
keybinding set: `Super+1..0` for workspaces, `Super+Arrow` to move
the focused window, `Super+Shift+Arrow` to move focus, `Super+Return`
for the terminal, `Super+E` for Files. Hide Cursor, Caffeine, and
Search Light are added to the default Bluefin extension set; LogoMenu
is disabled. None of this is enforced — the Extensions Manager
remains fully functional and any choice is reversible.

### Curated application set
Installed automatically on first boot via the systemd
`/usr/share/flatpak/preinstall.d/` API: Zen Browser, Bitwarden,
LibreOffice, Gapless, GIMP, Inkscape, darktable, Audacity, OBS Studio,
EasyEffects, Reaper, Apostrophe. Visual Studio Code is inherited from
Bluefin DX (Microsoft repo). Optional categories (gaming, retro,
content creation extras) are documented in the spec and can be added
with one command.

### Disk encryption and TPM2
Anaconda installs default to LUKS2 with a strong passphrase. After
install you can enroll TPM2 unlock with `systemd-cryptenroll`, keeping
the passphrase as recovery. Documented in
[`docs/07-secure-boot-tpm2.md`](https://github.com/daniel-g-carrasco/margine-fedora-atomic/blob/main/docs/07-secure-boot-tpm2.md).

### Verified build pipeline
Every published image is exercised through three CI gates before users
can pull it:

1. **Layer A guardrails** — static inspection of the built image
   without booting: initramfs presence and size, presence of
   `ostree-prepare-root`, critical kernel features
   (`dm-crypt`, `btrfs`, `virtio_blk`), MOK certificate, Plymouth
   theme, helpers under `/usr/bin`, `/etc/passwd` not stripped by
   rechunk, branding assets, and `systemd-analyze verify
   default.target` to detect ordering cycles.
2. **OCI archive verification** — the image is serialized to an OCI
   archive with double sha256 check before being copied into the
   destination storage, to defend against silent corruption on the
   builder.
3. **Smoke boot in QEMU** — the candidate image is converted to a
   qcow2 with `bootc-image-builder` and booted under QEMU/KVM. Only
   if the boot reaches a usable state (one of: `gdm.service` started,
   `graphical.target` reached, or the `margine login:` getty banner)
   is the candidate digest promoted to `:stable` with
   `skopeo copy --preserve-digests`.

The `:stable` tag therefore points, by construction, to an image that
has booted to a usable state in a controlled environment. A failed
candidate does not advance `:stable`.

### Localized application folders
GNOME's activities grid is organized into six folders with Italian
labels: Office, Grafica, Foto, Audio, Video, Sistema. Editable in the
declarative spec; English / other-language sets can be added.

## Screenshots

<div align="center">

<img src="docs/screenshots/activities-search.png" alt="GNOME Activities with search open showing Margine extensions and dock" width="48%">
&nbsp;
<img src="docs/screenshots/lock-screen.png" alt="Lock screen with autumn-leaves wallpaper" width="48%">

</div>

## Install

Two install paths are supported.

### Option A — Margine ISO

The recommended path. Downloads in one step, installs Margine
directly.

1. Open <https://files.the-empty.place/> and download the Anaconda
   installer ISO. Available as a BitTorrent magnet/`.torrent` and as
   a direct HTTP mirror (Internet Archive). The same bytes are
   served by both; `SHA256SUMS` is published alongside.
2. Boot the ISO. Anaconda's standard installation flow applies:
   recommended UEFI with Secure Boot enabled, LUKS2 on the root disk,
   Btrfs filesystem (the default).
3. Reboot. The first boot is already on Margine; the installer's
   `%post` kickstart has set the ostree origin to
   `ghcr.io/daniel-g-carrasco/margine:stable`, so subsequent
   `bootc upgrade` calls follow the same channel.
4. Apply the user-state once:
   ```sh
   ujust margine-bootstrap
   ```
   This runs the idempotent `margine-configure-*` helpers in
   sequence: home layout, GNOME extensions, keybindings, appearance,
   default applications, app folders. Log out and back in to refresh
   GNOME Shell.

### Option B — Rebase from an existing Bluefin install

Useful if you already have a Bluefin DX installation and don't want
to reinstall from ISO.

```sh
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/daniel-g-carrasco/margine:stable
systemctl reboot
```

After the reboot, two more one-time steps:

1. **MOK enrollment.** The first boot after the rebase queues the
   Margine MOK key for shim to enroll. On the next reboot the
   firmware presents the **MOK Manager** screen (shim's blue/grey
   UI). Choose `Enroll MOK` → `Continue` → `Yes`, type the MOK
   password, reboot. From this point on the CachyOS kernel boots
   under Secure Boot.
2. **`ujust margine-bootstrap`**, as in Option A.

### Post-install verification

```sh
mokutil --sb-state                       # SecureBoot enabled
uname -r                                 # 7.0.x-cachyos*.fc44.x86_64
margine-validate-atomic-layout
margine-validate-cachyos-kernel
```

### Optional gaming layer

A separate `ujust` recipe installs Steam, Lutris, Heroic, Bottles,
Protontricks, and ProtonUp-Qt as Flatpaks, plus gamescope, MangoHud,
vkBasalt, GameMode, goverlay, and steam-devices as RPM packages
(rpm-ostree layer; requires reboot). Fully reversible.

```sh
ujust margine-gaming            # install
ujust margine-gaming-remove     # remove
```

## What's inside (technical reference)

<details>
<summary>Full stack summary</summary>

**Base image**: Bluefin DX (stable), Universal Blue's developer-oriented
Bluefin variant. Built on Fedora Silverblue 44. Includes Mesa freeworld,
the full virt stack (libvirt, qemu-kvm, virt-manager, swtpm, edk2-ovmf),
container tooling (podman, docker, distrobox, toolbox), Visual Studio
Code, Cockpit, Tailscale, bpftrace, sysprof. Inherited unchanged by
Margine.

**Kernel**: CachyOS mainline from
[`bieszczaders/kernel-cachyos`](https://copr.fedorainfracloud.org/coprs/bieszczaders/kernel-cachyos/).
vmlinuz signed with `sbsign`; every `.ko*` module signed with
`sign-file`. MOK enrollment via `mok-enroll.service` on first boot
after install/rebase.

**Enabled GNOME extensions**: AppIndicator Support, Bazaar Integration,
Blur My Shell, Dash to Dock, Gradia Integration, GSConnect (all from
Bluefin); Search Light, o-tiling, Hide Cursor, Caffeine (added by
Margine).

**Preinstalled Flatpak apps**: Zen Browser, Bitwarden, LibreOffice,
Gapless, GIMP, Inkscape, darktable, Audacity, OBS Studio,
EasyEffects, Reaper, Apostrophe.

**Security**: Secure Boot via the Margine MOK; LUKS2 disk encryption;
optional TPM2 auto-unlock via `systemd-cryptenroll`; `cosign`
signature on the registry image.

**Update orchestration**: `bootc upgrade` daily via `uupd.timer`
(inherited from Bluefin); `flatpak update`, `brew upgrade`,
`distrobox upgrade` also orchestrated by `uupd`. Rollback via
`bootc rollback`.

**CI workflows** (under `.github/workflows/`):
- `build.yml` — builds the image, runs Layer A guardrails, publishes
  `:candidate`.
- `smoke-boot.yml` — boots the candidate in QEMU; on success, promotes
  to `:stable`.
- `build-disk.yml` — builds ISO and qcow2, uploads to Internet
  Archive (BitTorrent + HTTP mirrors), publishes an HTML index at
  `files.the-empty.place`.

</details>

## For developers

The declarative spec, configuration helpers, and validators live in
[`margine-fedora-atomic`](https://github.com/daniel-g-carrasco/margine-fedora-atomic).
This repo (`margine-image`) is only the build pipeline: Containerfile,
build scripts, CI workflows. To change *what* Margine ships — which
apps, which extensions, which keybindings — edit
`declarations/margine-atomic.yaml` in the spec repo. The build picks
up the new versions automatically.

Architectural decisions, postmortems, and the roadmap are documented
under [`docs/`](https://github.com/daniel-g-carrasco/margine-fedora-atomic/tree/main/docs)
in the spec repo.

## Credits

- [**Bluefin**](https://projectbluefin.io/) — base image and source
  of most of what Margine ships.
- [**Universal Blue**](https://universal-blue.org/) — image-template,
  CI patterns, `uupd`.
- [**CachyOS**](https://cachyos.org/) — scheduler and kernel patches.
- [**Origami Linux**](https://gitlab.com/origami-linux/images) — reference
  for the MOK-signing kernel script.
- [**MorrOS**](https://github.com/morrolinux/morros) — CI workflow
  patterns.
- [**hhd-dev/rechunk**](https://github.com/hhd-dev/rechunk) — ostree
  rechunking action.
- [**Internet Archive**](https://archive.org/) — permanent mirror
  and BitTorrent seed for the ISOs.

## License

Apache-2.0.
