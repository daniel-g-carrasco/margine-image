# CachyOS Kernel Experiment

The CachyOS kernel from COPR is experimental in this project. It is not part of
the Fedora Silverblue base and must not be treated as a safe default until
rollback has been tested. It also must not be treated as compatible with the
target Secure Boot requirement until that boot path is validated explicitly.

## Upstream Inputs

The CachyOS Fedora packaging repository documents:

- COPR repository `bieszczaders/kernel-cachyos`;
- `kernel-cachyos` and related variants;
- CPU requirements for some builds;
- Fedora Silverblue/Kinoite-specific instructions.

Reference: https://github.com/CachyOS/copr-linux-cachyos

## Pre-Flight

Start from an updated VM:

```sh
rpm-ostree status
sudo rpm-ostree upgrade
sudo systemctl reboot
```

After reboot:

```sh
rpm-ostree status
sudo ostree admin pin 0
```

Check CPU support. The CachyOS Fedora instructions state that the main kernels
require at least `x86-64-v3`, while LTS/server variants have different
requirements.

```sh
/lib64/ld-linux-x86-64.so.2 --help | grep "(supported, searched)"
```

For the first lab:

- Secure Boot may be disabled only for a clearly marked VM exception if the
  CachyOS kernel cannot boot through Fedora's trusted boot path;
- NVIDIA is not installed;
- akmods are not installed;
- ZFS is not installed;
- CachyOS addon packages are not installed;
- no script is installed to force CachyOS as the permanent default kernel.

For a target-compliant result:

- the stock Fedora kernel must already boot with Secure Boot enabled;
- disabling Secure Boot cannot be the long-term solution;
- any CachyOS kernel path must use a documented signing, MOK, or custom trust
  model before it can move beyond the lab;
- TPM2 unlock must be retested after any kernel, initramfs, bootloader, or PCR
  policy change.

## Add the COPR Repository on Silverblue

COPR can be enabled with DNF on mutable Fedora systems. On Silverblue, use the
repository file under `/etc/yum.repos.d/`, matching the CachyOS Silverblue/Kinoite
instructions.

```sh
releasever="$(rpm -E %fedora)"
sudo curl --fail --location \
  --output "/etc/yum.repos.d/bieszczaders-kernel-cachyos-fedora-${releasever}.repo" \
  "https://copr.fedorainfracloud.org/coprs/bieszczaders/kernel-cachyos/repo/fedora-${releasever}/bieszczaders-kernel-cachyos-fedora-${releasever}.repo"
```

Inspect the repo file before using it:

```sh
cat "/etc/yum.repos.d/bieszczaders-kernel-cachyos-fedora-${releasever}.repo"
```

## Stage the CachyOS Kernel Deployment

The published Silverblue/Kinoite path replaces the Fedora kernel packages in the
new deployment and installs `kernel-cachyos`:

```sh
sudo rpm-ostree override remove \
  kernel kernel-core kernel-modules kernel-modules-core kernel-modules-extra \
  --install kernel-cachyos
sudo systemctl reboot
```

This creates a new deployment. It should not destroy the previous Fedora
deployment, especially if the current deployment was pinned first.

## Post-Reboot Validation

```sh
rpm-ostree status
uname -a
rpm -qa | grep -i cachy
systemctl --failed
journalctl -b -p warning..alert --no-pager
```

Then run:

```sh
scripts/validate-cachyos-kernel
scripts/collect-diagnostics
```

## Rollback

Immediate rollback to the previous deployment:

```sh
sudo rpm-ostree rollback --reboot
```

To remove the CachyOS experiment from a future deployment, inspect the state:

```sh
rpm-ostree status -v
```

Then reset only what is actually active:

```sh
sudo rpm-ostree uninstall kernel-cachyos
sudo rpm-ostree override reset \
  kernel kernel-core kernel-modules kernel-modules-core kernel-modules-extra
sudo systemctl reboot
```

If rpm-ostree reports that an override is inactive or absent, do not force the
command blindly. Re-read `rpm-ostree status -v` and adjust the package list to
the actual deployment.

## Success Criteria

- The system boots into the new deployment.
- `uname -a` identifies a CachyOS kernel.
- CachyOS kernel RPMs are visible through `rpm -qa`.
- GNOME and GDM still work.
- If this run claims Secure Boot support, `mokutil --sb-state` reports enabled
  while booted into the CachyOS deployment.
- No critical kernel, initramfs, bootloader, or Btrfs errors appear.
- Rollback to the Fedora kernel has been tested.

## Stop Criteria

Stop the experiment and return to the Fedora kernel if any of these appear:

- kernel panic;
- boot failure;
- recurring freezes;
- Btrfs errors;
- initramfs or bootloader errors;
- GDM/GNOME regressions;
- unexplained SELinux failures;
- need for NVIDIA, ZFS, VirtualBox, or other out-of-tree modules.
