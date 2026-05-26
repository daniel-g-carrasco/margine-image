# Changelog

All notable changes to the Margine bootc image build are recorded here.
Image tags follow `stable`, `stable.YYYYMMDD`, `YYYYMMDD`.
Semantic versioning (`v0.X.Y`) will start once the first user-facing
stable release is cut.

## [Unreleased]

### Added
- `build_files/build.sh` now stamps `/usr/lib/os-release` with Margine
  identity (`NAME=Margine`, `ID=margine`, `VARIANT_ID=margine`,
  `ID_LIKE="fedora bluefin"`). This makes `cat /etc/os-release`,
  `hostnamectl`, and GNOME About all report "Margine", and lets
  `margine-validate-atomic-layout` succeed on the actual deployment.

### Changed
- Dropped the `kitty` Flatpak preinstall (build.sh) and the kitty
  default-terminal gschema override. Bluefin's Ptyxis stays as default.
- gschema `favorite-apps` updated to `org.gnome.Ptyxis.desktop`.

### Notes (carried over from prior unreleased state)
- `custom-kernel/install.sh` installs `sbsigntools` up-front so `sbsign`
  is available when signing vmlinuz (fixed exit 127).
- v4l2loopback is built best-effort; failures do not block the image
  (Universal Blue cache-mount limitation, documented inline).
- `mok-enroll.service` is written + enabled; runs once at first boot,
  marks completion with `/var/.mok-enrolled`. Recovery procedure for a
  missed MOK Manager confirmation is documented in
  `margine-fedora-atomic/docs/07-secure-boot-tpm2.md`.

## [Phase 1 — initial publish]

First successful build pushed to `ghcr.io/daniel-g-carrasco/margine:stable`
(commit `74449fc`, build 2026-05-26): Bluefin DX + MOK-signed CachyOS
kernel + Margine Flatpak preinstalls + Margine GNOME defaults.
