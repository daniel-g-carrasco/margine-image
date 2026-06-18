# Changelog

All notable changes to the Margine bootc image build are recorded here.
Image tags follow `stable`, `stable.YYYYMMDD`, `YYYYMMDD`.
Semantic versioning (`v0.X.Y`) will start once the first user-facing
stable release is cut.

## [Unreleased]

### Added (2026-06-18)
- **`ujust install-koofr`** (alias `ujust koofr`) — installs the Koofr Desktop
  sync client natively and rootless from upstream's self-updating tarball into
  `~/.koofr-dist` (no Flatpak/RPM/Distrobox; never layered, since it
  auto-updates inside `$HOME`). Autostarts **hidden to the system tray** at
  login via the binary's `-silent` flag, with `silentStart:true` persisted in
  `~/.koofr/config.json` as belt-and-suspenders (guarded so it never clobbers a
  running client); a manual menu launch still opens the window. `remove`
  uninstalls the three artifacts and kills the process.
- **`ujust margine-test-vm`** (+ `margine-test-vm-remove`) — throwaway VM to
  test a Margine ISO on the real secure path: UEFI Secure Boot with Microsoft
  keys pre-enrolled (so MOK enrollment is exercised) + an emulated TPM 2.0 (for
  LUKS auto-unlock). Rootless `qemu:///session`; an ISO arg boots a ready VM,
  no arg defines a clone template.
- **EasyEffects autostarts headless** — system `/etc/xdg/autostart` entry runs
  EasyEffects in `--service-mode` (no window) on login.

### Changed (2026-06-18)
- **Super+arrows now move the focused window** within the o-tiling layout (gaps
  preserved) via `tile-move-*-global`; the GNOME gapless built-ins that used to
  eat the chord are cleared. Focus stays on Super+hjkl.

### Fixed (2026-06-18)
- **Plymouth graphical boot on fresh installs and in VMs.** Two causes: (1) the
  bootc/titanoboa ISO didn't set `rhgb quiet`, so fresh installs booted to a
  text console with the LUKS prompt amid kernel logs — now baked as a kernel arg
  (`/usr/lib/bootc/kargs.d/10-margine-plymouth.toml`). (2) The generic initramfs
  pulled amdgpu/qxl/bochs but not `virtio_gpu`, so a guest with *virtio* video
  had no early DRM device and Plymouth fell back to text — now forced in via
  `/etc/dracut.conf.d/02-margine-vm-gpu.conf` (`add_drivers+=" virtio_gpu "`).
  Diagnosed from an installed VM's journal (only `/dev/dri/card1=virtio_gpu`
  appeared, late; no early `card0`, simpledrm didn't bind). QXL/std-video guests
  were unaffected. The Plymouth theme itself was never at fault.

### Added (2026-06-15)
- **Safe TPM2-unlock + autologin helpers** — `ujust margine-tpm-unlock`
  (status/enable/disable) and `ujust margine-autologin` (status/on/off).
  The TPM helper is lockout-proof by construction: auto-detects the LUKS
  device backing root, refuses to enroll unless a passphrase/recovery
  keyslot survives, only ever wipes the tpm2 slot, confirms + post-verifies.
  Both authored + adversarially reviewed to approval. Documented in the
  handbook (first-boot).
- **/status freshness dashboard producer** — `build-status-json.sh` +
  `publish-status-json.sh` + `status-json.yml` keep the site's Fedora →
  Bluefin → Margine version/health page current after every build / smoke /
  ISO and daily; `org.opencontainers.image.base.digest` label added so the
  page can flag whether Margine is built on the latest Bluefin. Plus
  `ujust margine-status` / `margine-update` + the `/usr/bin/margine-status`
  helper.
- **Soft user-smoke gate** — a warn-only identity probe in the smoke-boot VM
  (kernel is CachyOS/BORE, o-tiling enabled, keybindings present,
  search-light absent, gaming recipe shipped, zz1 gschema applied). Annotates
  the run; never blocks candidate→:stable promotion.
- **AI / local-LLM layer documented + validated** — handbook page +
  homepage card for `ujust margine-ai` (Alpaca); `validate-flatpak-refs.yml`
  checks every recipe Flatpak app ID against Flathub on PRs + weekly.
- **GHCR cleanup** — daily prune of untagged orphan image versions
  (keep-n-untagged), plus host benchmark/diagnostic tools under `tools/bench/`
  (kernel scheduler, gaming FPS, non-HiDPI check).

### Changed (2026-06-15)
- **Site ISO-date bump** now pushes straight to the website's `main`
  (the repo is private/free, so the old PR + auto-merge path silently
  stranded the bump and the site advertised the previous ISO).
- **Renovate** now tracks the o-tiling release pin (no more silent staleness)
  and the config was migrated; `actions/checkout` bumped to v6.

### Fixed (2026-06-08) — ISO MOK enrollment timing
- **Fresh ISO installs** now submit the Margine MOK import request from
  Anaconda before the first post-install reboot, mirroring Bluefin's ISO
  Secure Boot flow so shim can open MOK Manager before the installed
  system boots.
- **Rebase recovery path** remains unchanged: `mok-enroll.service` still
  runs on first Margine boot when the Anaconda path was not available or
  the user missed the firmware MOK prompt.

### Fixed (2026-06-08) — Round-1 blocker audit
- **GNOME extension defaults** now live in the system dconf database
  (`/etc/dconf/db/distro.d/`) instead of a gschema override, so
  extension settings are applied through the backend GNOME Shell
  actually reads at first login.
- **Installer partitioning** is declared in the Anaconda kickstart:
  `zerombr`, `clearpart`, a 4 GiB ESP, a growing btrfs root, and the
  single-disk `ignoredisk` shim for safer fresh installs.
- **bootc-image-builder** in `build-disk.yml` is pinned to an
  `@sha256` digest instead of a moving tag.
- **GNOME branding assets** overwrite Fedora's hard-coded logo pixmaps
  instead of deleting them, so GNOME About renders the Margine logo
  again.
- **sched_ext controls** were rewritten as an opt-in Zenity picker:
  `scx_loader` stays off by default, scheduler changes go through
  `scxctl`/D-Bus/polkit, and tuned profile hooks now gate on active
  service state instead of enabled state.
- **README install guidance** now recommends rebasing from Bluefin DX
  while the fresh-install ISO path is being hardened.
- **Launcher icons** now use a MoreWaita system icon for the scheduler
  app and a custom Margine documentation icon.
- **Documentation launcher** now uses `/usr/bin/margine-docs-open`:
  it opens the live docs when `/healthz` responds and falls back to
  `/usr/share/margine/offline-docs/index.html` offline.

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
