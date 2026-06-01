# Changelog

All notable changes to the Margine declarative spec are recorded here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
The spec is currently unreleased; once the first stable image ships under a
versioned tag, semantic versioning (`v0.X.Y`) will start.

## [Unreleased]

### Added (2026-06-01)
- `scripts/validate-margine-system`: end-to-end acceptance test that
  wraps the individual `validate-*` checks plus a verdict-line summary.
  Used in the smoke-boot CI step and after every manual `bootc upgrade`.
- `scripts/configure-zen-browser`: writes a per-profile `user.js` that
  sets Zen Browser's default search to DuckDuckGo.
- `docs/18-observability.md`: ntfy push + `margine-staleness.timer` +
  `margine-upgrade-notify.service` (three independent notification
  layers for build pipeline + deployed systems).
- `docs/19-iso-distribution.md`: torrent-first ISO/qcow2 publishing
  via Internet Archive + Caddy index on `files.the-empty.place`.
- `docs/lessons-learned/2026-06-01-systemd-ordering-cycle-and-rechunk-storage.md`:
  postmortem of the emergency-mode boot caused by a unit's
  `After=local-fs.target` + the architectural shift to the
  `:candidate → :stable` smoke-boot-gated promotion.
- Extensions: `o-tiling@oliwebd.github.com` (binary-tree auto-split,
  closer to Hyprland muscle memory), `hide-cursor@elcste.com` (hide
  pointer while typing), `caffeine@patapon.info` (keep-screen-on
  toggle).

### Changed (2026-06-01)
- `scripts/configure-gnome-extensions` is now replace-style and uses
  an on-disk presence check instead of `gnome-extensions list`. The
  enabled-extensions list is written via `gsettings set` in one
  shot from the declaration, dropping anything no longer declared.
- Tiling extension: `tilingshell` is now installed-but-not-enabled,
  superseded by `o-tiling` as the default tiling experience.
- App folders: 6 English-named folders (Office / Graphics /
  Photography / Audio / Video / System) curated from Flatpak metadata.
  Renamed from Italian (Grafica/Foto/Sistema) on 2026-06-01;
  `validate-margine-system` accepts both name sets during the
  transition window until existing deployments are re-bootstrapped.

### Changed
- **System identity**: declarations now describe Margine as a published
  bootc image (`ghcr.io/daniel-g-carrasco/margine:stable`) derived from
  Bluefin DX, not as "Silverblue + apply-host-layer". `base.variant` is
  now `margine`; `derives_from: bluefin-dx`.
- **Update orchestration**: dropped in favor of Bluefin's `uupd.timer`
  (inherited from the base image). Margine no longer ships an
  `update-all` script or a Topgrade config.
- **Kernel**: `kernel.shipped` records the CachyOS kernel as the default
  (signed with the Margine MOK at image-build time, Secure Boot
  compliant). Runtime layered installation is documented under
  `legacy_layered_path_for_reference` only.
- **Secure Boot**: `security.secure_boot.custom_signing` now describes
  the MOK signing pipeline (vmlinuz via `sbsign`, modules via
  `sign-file`, first-boot enrollment via `mok-enroll.service`).
- **Default terminal**: dropped the `kitty` delta; Bluefin's Ptyxis stays
  as the default. Keybindings updated to use `ptyxis` / `ptyxis -- btop`.
- **Tiling extension**: switched from Forge (unmaintained) to Tiling
  Shell (`tilingshell@ferrarodomenico.com`).

### Removed
- `scripts/update-all` (replaced by Bluefin `uupd`).
- `config/topgrade.toml` (Bluefin's `uupd` orchestrates accessory channels).
- `docs/12-update-orchestration.md` (replaced by §
  *Update Orchestration* in `docs/01-architecture.md`).
- `gnome-shell-extension-just-perfection` from `host_packages.baseline`
  (was layered but never enabled).
- `workspaces-bar@fthx` from `gnome.extensions.user_install` (upstream
  dead, max GNOME Shell version 42).

### Deprecated (kept as fallback / audit material)
- `scripts/apply-host-layer` — for stock Silverblue path only; not for
  Margine bootc deployments.
- `scripts/apply-margine-on-bluefin` — for users who stay on upstream
  Bluefin DX without rebasing to the published Margine image.

### Fixed
- `scripts/validate-atomic-layout` now accepts `margine`, `silverblue`,
  `bluefin`, and `bluefin-dx` as valid `VARIANT_ID` values.

### Added
- ADR 0005 amendment recording the pivot from "Bluefin DX + adapter" to
  "published bootc image" and dropping the kitty delta.
- ADR 0004 superseded banner — the principle that the base-OS update
  step must own pre/post validation, reboot, and rollback is preserved;
  the implementation moved from Margine's own `update-all` to Bluefin's
  `uupd`.
- `docs/07-secure-boot-tpm2.md § MOK signing for the CachyOS kernel`.

## [Phase 0 — Silverblue lab]

Initial Silverblue 44 lab work: see `docs/adr/0005-base-on-bluefin-dx.md`
"What stays valid from phase 1 lab" and `docs/15-host-layer.md` for the
artifacts produced.
