# Changelog

All notable changes to the Margine bootc image build are recorded here.
Image tags follow `stable`, `stable.YYYYMMDD`, `YYYYMMDD`.
Semantic versioning (`v0.X.Y`) will start once the first user-facing
stable release is cut.

## [Unreleased]

### Added (2026-06-07) — `ujust margine-ai` (optional local-AI workflow)
- New `ujust margine-ai` recipe in `build_files/60-custom.just` installs
  [Alpaca](https://flathub.org/apps/com.jeffser.Alpaca) (`com.jeffser.Alpaca`)
  — a Flatpak GUI for local LLMs that bundles its own Ollama backend.
  No host install, no daemon-running, models downloaded on demand.
  Recipe also prints distrobox setup pointer for [RamaLama](https://github.com/containers/ramalama)
  CLI power users. `ujust margine-ai-remove` reverses it.
- README "What you get" gets a `🤖 Optional AI workflow` row.
- Spec yaml (`margine-fedora-atomic/declarations/margine-atomic.yaml`)
  gets a new top-level `ai_workflow:` section documenting the opt-in
  model, recommended starter models (llama3.1:8b / qwen2.5-coder:7b /
  mistral:7b / phi3.5:3.8b), and hardware floor (8 GB VRAM comfort,
  16 GB RAM minimum for CPU-only).

### Added (2026-06-07) — `ujust margine-gaming-native` (RPM-layered gaming)
- New `ujust margine-gaming-native` recipe layers Steam + Lutris +
  RetroArch as native RPMs from RPM Fusion (Heroic / Bottles /
  Protontricks / ProtonPlus stay Flatpak — no official RPM upstream).
  For users needing maximum Proton/Wine compatibility — anti-cheat
  (EAC / BattlEye), VR, Steam Link, NVIDIA proprietary + Mesa-git
  side-by-side. Cost: +30-60s per `bootc upgrade` to re-apply the
  larger layer.
- Default Flatpak `ujust margine-gaming` stays unchanged for
  occasional gamers.
- README Option C section rewritten to document both paths with the
  explicit trade-off. Spec yaml `gaming_runtime.opt_in` now has
  `default:` and `native:` sub-keys.
- Inspired by RakuOS's "Native Gaming. Not Flatpak." stance — same
  trade-off, kept as opt-in second path so the default Margine
  experience stays upgrade-friendly.

### Documentation (2026-06-07) — ADR 0007: Sealed Bootable Container Images tracker
- `margine-fedora-atomic/docs/adr/0007-sealed-bootable-images-tracker.md`:
  long-form ADR tracking Fedora's sealed bootable container images
  direction (systemd-boot + UKI + composefs/fs-verity, Secure-Boot-
  signed end-to-end). Covers 5 action triggers + 9-step migration
  plan for when production stable arrives (~6-12 months).
- `margine-fedora-atomic/scripts/check-upstreams.sh` watchlist gets
  `travier/fedora-atomic-desktops-sealed` so the monthly cron
  flags activity in the test-image repo.
- Tracker issue
  [#32](https://github.com/daniel-g-carrasco/margine-fedora-atomic/issues/32)
  on margine-fedora-atomic with checkbox list of triggers + steps.

### Removed (2026-06-06) — Margine Gaming ISO + OCI variant retired
- **`ghcr.io/.../margine-gaming:stable` OCI image** — no longer built
  or published. The dedicated `build-gaming.yml` workflow, the
  `Containerfile.gaming`, the `build_files/gaming/` directory, and
  `installer/flatpaks-gaming` are all deleted.
- **Gaming Anaconda ISO** — `build-disk.yml` no longer matrixes over
  `margine` + `margine-gaming`; only the single `margine` ISO is
  built and uploaded to Internet Archive. No more
  `margine-gaming-anaconda-iso-YYYYMMDD` items.
- **`Option C — Switch between Margine and Margine Gaming`** install
  section in README — replaced with `Option C — Add the gaming
  layer` (one `ujust margine-gaming` step on top of base Margine).
- Rationale: same gaming stack reachable from base Margine via the
  already-existing `ujust margine-gaming` recipe (rpm-ostree layer +
  Flatpaks). Two parallel paths to the same gaming setup was extra
  surface area to maintain — separate ISO build (60 min CI), separate
  IA upload (~6 GB / build), separate Containerfile, separate
  preinstall list, separate ISO download UI on the site. Keeping
  only the ujust path cuts that whole pipeline. Trade-off: the
  result is a layered (not ostree-canonical) deployment, which is
  the same trade-off the recipe already had before this change.

### Added (2026-06-03)
- **11 GNOME core Flatpaks added to the preinstall set** (Calculator,
  Calendar, clocks, Contacts, Weather, Maps, TextEditor, baobab,
  Characters, Logs, font-viewer). Closes the visible gap "the
  standard GNOME utility set isn't here" against a vanilla Fedora
  Silverblue install — Silverblue ships these as RPM in /usr, Bluefin
  DX intentionally strips them, so we restore the set as Flatpaks
  (atomic-friendly, ~120 MB cumulative thanks to shared
  org.gnome.Platform runtime). `EXPECTED_FLATPAKS` in
  margine-fedora-atomic updated in lockstep.

### Added (2026-06-02, part 2)
- **9 Flatpaks added to the preinstall set** (Thunderbird ESR,
  GNOME Snapshot/Showtime/Papers/Loupe/SoundRecorder, Blanket,
  Fragments, Pinta). The previous list was an incomplete starter
  set — users on a fresh install were surprised to find no
  camera / video player / PDF reader / image viewer / sound
  recorder / mail client (the latter despite being declared as
  the system mail handler in declarations/margine-atomic.yaml).
  The validator's `EXPECTED_FLATPAKS` in margine-fedora-atomic is
  updated in lockstep so the post-boot acceptance test catches
  any regression on this set.

### Added (2026-06-02)
- **Margine Gaming OCI variant** — a separate, signed image at
  `ghcr.io/daniel-g-carrasco/margine-gaming:stable`. Built `FROM`
  the already-validated `margine:stable` and adds the gaming host
  stack (gamescope, MangoHud, vkBasalt, GameMode, goverlay,
  steam-devices, input-remapper, tuned, tuned-ppd, rom-properties-gtk)
  at image-build time plus a Flatpak preinstall list (Steam, Lutris,
  Heroic, Bottles, Protontricks, ProtonUp-Qt, RetroArch). End-user
  switch: `sudo bootc switch ghcr.io/daniel-g-carrasco/margine-gaming:stable`.
  Identifies itself as `VARIANT_ID=gaming`, `PRETTY_NAME="Margine Gaming"`.
  Files: `Containerfile.gaming`, `build_files/gaming/{install.sh,
  stamp-os-release.sh,margine-gaming.preinstall}`.
- **`build-gaming.yml` workflow** — `build_push → sign → promote_to_stable
  → notify`. Triggers on `workflow_dispatch`, `workflow_run` after a
  successful `Smoke-boot published image` (so the variant rebuilds
  automatically when a new base `:stable` is promoted), and weekly
  Sun 05:00 UTC. No MOK secrets needed: the kernel is already signed
  in the base layer. Promotes `:candidate → :stable` immediately
  after signing (the base was smoke-booted; the variant only adds
  RPMs + Flatpak declarations, no boot-path changes that warrant
  a second 25-min QEMU test).
- **`build-disk.yml` matrix on image** — produces 4 disk artifacts
  in parallel (margine + margine-gaming × qcow2 + anaconda-iso) and
  publishes both ISOs to Internet Archive under per-variant
  identifiers (`margine-anaconda-iso-YYYYMMDD`,
  `margine-gaming-anaconda-iso-YYYYMMDD`).
- **RPMFusion enabled in the gaming variant** — the base image strips
  RPMFusion after using it transiently for the CachyOS kernel install;
  the gaming variant re-enables free + nonfree and keeps them, since
  the entire gaming RPM stack lives there and users will need the
  same repo set for `dnf upgrade` / `rpm-ostree upgrade`.
- **Trade-off note in `ujust margine-gaming`** — the existing `ujust`
  recipe (rpm-ostree overlay) now prints, before its confirmation
  prompt, what the layering choice implies (`LayeredPackages` branch,
  slower upgrades, occasional file-conflict rebases) and points users
  to the variant image as the ostree-canonical alternative.

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
- **App folders**: 6 folders (Office / Graphics / Photography / Audio /
  Video / System). The folder set started as Italian-labeled
  (Grafica/Foto/Sistema) and was renamed to English on 2026-06-01
  so existing in-the-wild deployments may briefly show either set
  until `configure-gnome-app-folders` runs again.

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
