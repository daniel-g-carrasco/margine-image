# Fedora release checklist

The base image tag floats, so a new Fedora arrives on its own. The build
step `11-fedora-release-gate` refuses to build until `expected-release`
matches the base; go through this list first, then bump the number.

## Secrets and login (Fedora 45: gnome-keyring is replaced by oo7)

- Fedora 45 makes **oo7** the Secret Service (`oo7-daemon`, `pam_oo7`,
  `oo7-portal`). GDM's PAM files moved to `/usr/lib/pam.d` and carry
  `pam_oo7`: a password login unlocks the Login keyring.
- oo7 ships no D-Bus activation file; only GNOME's
  `gnome-session-services.target` starts it. Margine ships
  `org.freedesktop.secrets.service` and Lucciola starts it with niri
  (`niri.service.d/50-lucciola-secrets.conf`). Without them a niri session
  has no Secret Service at all.
- oo7 migrates gnome-keyring's encrypted keyring with the login password,
  but not the plaintext one `margine-keyring blank` left on Fedora 44: with
  the password at hand oo7-daemon exits on it ("File header doesn't
  match"), without it oo7 starts an empty Login keyring.
  `keyring-legacy-aside` (ExecStartPre of oo7-daemon) renames the file,
  `keyring-import-legacy` moves its items over (at login, or
  `ujust margine-keyring import`). Only for oo7 0.7.0~beta: upstream
  migrates the plaintext format itself since #579 (2026-09-26), so the
  aside step stands down on any other version. Rehearsed in a `silverblue-main:45`
  container with a real oo7-daemon: text, network and binary items, lookup
  by attribute and by schema, persistence across a daemon restart.
- `margine-keyring` no longer blanks the keyring (oo7 refuses an empty
  password): `tpm` stores the keyring password as a user credential that
  oo7-daemon imports at start (`ImportCredential=oo7.keyring-encryption-password`).
  To test in a VM with a TPM: fingerprint-like login (autologin) opens the
  keyring; a wrong credential shows in `status`.
- **tpm-keyring-unlock** (development laptop since 2026-10) rewrote
  `/etc/pam.d/gdm-{password,fingerprint,autologin,switchable-auth}`. Those
  copies keep shadowing GDM's new `/usr/lib/pam.d` files after the update:
  run `tpm-keyring-unlock-deconfigure` before rebasing, then
  `ujust margine-keyring tpm`.
- Back up `~/.local/share/keyrings` before testing: oo7's migration of a
  legacy login keyring has failed in reports (linux-credentials/oo7#577).

## Release-pinned names in this tree

- `build_files/45-wsf/install.sh`: `WSF_RPM` ends in `fc44`, and
  `.github/workflows/wsf-pin-sha.yml` builds the same name. The fc44 RPM
  installs and runs on Fedora 45 (no Python ABI pin, libinput's getters
  unchanged), so a fc45 WSF release can follow at its own pace.
- `lucciola/Containerfile`: `NOCTALIA_VR` carries no Fedora tag (build.sh
  adds the base's); check that the new release ships the same
  version-release and test-boot Lucciola.
- `build_files/40-spec-scripts/scripts/validate-baseline-packages`:
  `quay.io/fedora/fedora:44`.
- `build_files/40-spec-scripts/declarations/margine-atomic.yaml`: the
  toolbox image `fedora-toolbox:44` and the "validated against fedora:44"
  notes.

## Kernel, drivers, repositories

- CachyOS kernel COPRs for the new release (custom-kernel/install.sh), the
  `scx-scheds` addons COPR, and the MOK-signed kernel build.
- NVIDIA akmods on the new release (build-nvidia.yml) and the stock-kernel
  test build. Fedora 45: NVIDIA's CUDA repository for fedora45 was not
  published on 2026-10-16 (404), and custom-kernel refuses an older
  release's repository on purpose: `:nvidia` stays on its last Fedora 44
  build until NVIDIA publishes, or the variant moves to negativo17's driver.
- Fedora 45 on 2026-10-16: kernel-cachyos 7.2.11 and -lts 6.18.55,
  scx-scheds, ublue-os/packages, Docker CE, negativo17 multimedia and
  RPM Fusion all have fc45 builds.
- RPM Fusion, Docker CE, VS Code, Tailscale repositories: release-specific
  URLs resolve.
- ROCm: `rocm-opencl` still builds darktable's kernels
  (`ujust margine-darktable-opencl status`), and whether Mesa's rusticl works
  again (then the ROCm shim could go).

## Desktop and apps

- GNOME major version: extensions built in `build-margine-extensions.sh`
  (o-tiling, hide-cursor, gradia-integration) declare the new shell version;
  dconf keys in 30-gnome-defaults still exist. GNOME 51: o-tiling v2.12.01,
  hide-cursor v15, the Gradia and Bazaar companions at their 2026-10-16
  commits list 51. Smile has no 51 build and GNOME 51 removed the
  Clutter call its paste uses: the step patches both (proposed upstream,
  mijorus/smile-gnome-extension#23), tested on a headless GNOME Shell 51.0
  and 50.5 with the CopiedEmoji signal. Fedora's Caffeine 60 does not load
  on 51 (OUT_OF_DATE, seen in a VM session): the build swaps in EGO's v61
  while Fedora's package lags (dist-git PR 6 updates it), and now fails if
  any enabled extension does not declare the running GNOME.
- Flatpak: the GL runtime branch the preinstalled apps use, and the
  `org.gnome.Platform` versions.
- `validate-margine-system`, smoke-boot and the install gate pass on the
  new release; `ujust margine-update` from the previous release works
  (gaming layer included, see the update-path gate).

## Last

- Site and docs version strings, CHANGELOG entry.
- Set `build_files/11-fedora-release-gate/expected-release`.
