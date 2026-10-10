# Fedora release checklist

The base image tag floats, so a new Fedora arrives on its own. The build
step `11-fedora-release-gate` refuses to build until `expected-release`
matches the base; go through this list first, then bump the number.

## Secrets and login (Fedora 45: gnome-keyring is replaced by oo7)

- Fedora 45 makes **oo7** the Secret Service (`oo7-daemon`, `pam_oo7`,
  `oo7-portal`). The login keyring is then unlocked by `pam_oo7` with the
  login password, not by `pam_gnome_keyring`.
- `ujust margine-keyring` (blank keyring password for fingerprint and
  autologin users) assumes gnome-keyring's file format and `pam_gnome_keyring`:
  retest, and check whether oo7's credential-store unlock
  (`systemd-creds`, TPM-bound, no authentication) or a TPM PAM module is the
  better answer.
- **tpm-keyring-unlock** (the TPM keyring unlock used on the development
  laptop since 2026-10) feeds `pam_gnome_keyring`: with oo7 the PAM lines
  differ. Check upstream for oo7 support before keeping or shipping it.
- Back up `~/.local/share/keyrings` before testing: oo7's migration of a
  legacy login keyring has failed in reports (linux-credentials/oo7#577).

## Release-pinned names in this tree

- `build_files/45-wsf/install.sh`: `WSF_RPM` ends in `fc44`, and
  `.github/workflows/wsf-pin-sha.yml` builds the same name.
- `lucciola/Containerfile`: `NOCTALIA_EVR=...fc44`; check the Noctalia
  version Fedora ships on the new release and test-boot Lucciola.
- `build_files/40-spec-scripts/scripts/validate-baseline-packages`:
  `quay.io/fedora/fedora:44`.
- `build_files/40-spec-scripts/declarations/margine-atomic.yaml`: the
  toolbox image `fedora-toolbox:44` and the "validated against fedora:44"
  notes.

## Kernel, drivers, repositories

- CachyOS kernel COPRs for the new release (custom-kernel/install.sh), the
  `scx-scheds` addons COPR, and the MOK-signed kernel build.
- NVIDIA akmods on the new release (build-nvidia.yml) and the stock-kernel
  test build.
- RPM Fusion, Docker CE, VS Code, Tailscale repositories: release-specific
  URLs resolve.
- ROCm: `rocm-opencl` still builds darktable's kernels
  (`ujust margine-darktable-opencl status`), and whether Mesa's rusticl works
  again (then the ROCm shim could go).

## Desktop and apps

- GNOME major version: extensions built in `build-margine-extensions.sh`
  (o-tiling, hide-cursor, gradia-integration) declare the new shell version;
  dconf keys in 30-gnome-defaults still exist.
- Flatpak: the GL runtime branch the preinstalled apps use, and the
  `org.gnome.Platform` versions.
- `validate-margine-system`, smoke-boot and the install gate pass on the
  new release; `ujust margine-update` from the previous release works
  (gaming layer included, see the update-path gate).

## Last

- Site and docs version strings, CHANGELOG entry.
- Set `build_files/11-fedora-release-gate/expected-release`.
