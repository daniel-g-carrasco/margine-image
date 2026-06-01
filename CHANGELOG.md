# Changelog

All notable changes to the Margine bootc image build are recorded here.
Image tags follow `stable`, `stable.YYYYMMDD`, `YYYYMMDD`.
Semantic versioning (`v0.X.Y`) will start once the first user-facing
stable release is cut.

## [Unreleased]

### Added (2026-06-01)
- **Candidate → stable promotion model**: `build.yml` now publishes
  only `:candidate` + `:candidate.YYYYMMDD`; `smoke-boot.yml` boots
  that candidate in QEMU and only on success `skopeo copy
  --preserve-digests` to `:stable` + `:stable.YYYYMMDD` + `:YYYYMMDD`.
  Eliminates the class of "build green, boot red" leaks.
- **Layer A `systemd-analyze verify default.target`**: ordering-cycle
  detection at build time, catches regressions like the one that put
  a deployment into emergency.target on 2026-06-01.
- **Pre-build GHCR login**: authenticated base-image pull
  (5000 req/h instead of 100/h anonymous), fixes intermittent 403
  on bluefin-dx:stable after cache reset.
- **OCI archive intermediate** for the move-to-root-storage step
  (replaces the `podman save | sudo podman load` pipe which corrupted
  blobs under memory pressure on the degraded-ZFS host).
- **`build-disk.yml`**: ISO + qcow2 builder, publishes via Internet
  Archive (torrent + 3 HTTP mirrors, seeded forever) + HTML index on
  `files.the-empty.place`. No origin upload bandwidth for binaries.
- **ntfy push notifications**: build/smoke-boot/disk-build outcomes
  + click-to-open-run URL. Topic via `NTFY_TOPIC_URL` secret.
- **`margine-staleness.timer`** + **`margine-upgrade-notify.service`**:
  client-side awareness of stale upstream and post-upgrade events,
  installed via `/etc/skel` user-systemd.
- **`margine-configure-zen-browser`**: per-profile `user.js` setting
  DuckDuckGo as default search engine.
- **GNOME extensions added**: o-tiling (binary-tree auto-split, replaces
  Tiling Shell as default tiling), Hide Cursor, Caffeine.
- `build_files/build.sh` now stamps `/usr/lib/os-release` with Margine
  identity (`NAME=Margine`, `ID=margine`, `VARIANT_ID=margine`,
  `ID_LIKE="fedora bluefin"`). This makes `cat /etc/os-release`,
  `hostnamectl`, and GNOME About all report "Margine", and lets
  `margine-validate-atomic-layout` succeed on the actual deployment.

### Changed (2026-06-01)
- **System-wide Flatpak preinstall** moved from
  `/etc/ublue-os/system-flatpaks.list` (legacy uBlue path, no longer
  honored by Bluefin) to
  `/usr/share/flatpak/preinstall.d/margine-defaults.preinstall`
  (systemd's standard preinstall API).
- **`configure-gnome-extensions` is now replace-style** rather than
  additive: builds the full enabled-extensions list from the
  declaration and writes it directly via `gsettings set`, dropping
  anything no longer declared (e.g. `tilingshell` after the switch
  to `o-tiling`). Uses an on-disk presence check rather than
  `gnome-extensions list` (which only reflects the running shell).
- **`margine-seed-etc-passwd.service` ordering**: `After=local-fs-pre.
  target` (was `local-fs.target` → ordering cycle → emergency.target).
- **Plymouth + boot fallback colors**: pure black `#000000`
  background everywhere (was warm brown).
- **GDM logo**: empty string (was a 2400x700 banner image that got
  upscaled fullscreen by GNOME 50 greeter).
- **App folders**: 6 folders (Office / Grafica / Foto / Audio /
  Video / Sistema), Italian names.

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
