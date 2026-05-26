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

1. **CachyOS mainline kernel** from
   [`bieszczaders/kernel-cachyos`](https://copr.fedorainfracloud.org/coprs/bieszczaders/kernel-cachyos/),
   replacing Bluefin's signed kernel.
2. **MOK-signed kernel + modules** so the image boots cleanly under
   Secure Boot (one-time MOK enrollment on first boot via
   `mok-enroll.service`).
3. **kitty** preinstalled as a system Flatpak.
4. **Bluefin branding extensions disabled** by default
   (`bazaar-integration`, `gradia-integration`, `logomenu`). Packages
   stay installed and can be flipped back on per session.
5. **Margine GNOME defaults** (yellow accent, Zen as default browser,
   Tiling Shell as the tiling extension, autotiling on, etc.) layered
   via a `zz1-margine.gschema.override` that loads after Bluefin's
   `zz0-bluefin-modifications`.

Everything else — codec / Mesa freeworld / GNOME blur / dash-to-dock /
gsconnect / virt stack / podman+distrobox / fonts / hardware
diagnostics — is inherited unchanged from Bluefin DX.

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
