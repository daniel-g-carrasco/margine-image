# Manual Lab Installation

This document defines the phase 1 VM lab. The lab is intentionally manual so the
project can observe Fedora Silverblue before automating anything.

## VM Requirements

Recommended VM profile:

- UEFI firmware;
- Secure Boot enabled for the stock Fedora baseline;
- virtual TPM 2.0 if the hypervisor supports it;
- 4 vCPUs;
- 8 GiB RAM;
- 64 GiB disk or larger;
- NAT networking;
- standard virtual graphics;
- no GPU passthrough;
- hypervisor snapshot before kernel experiments.

GNOME Boxes, virt-manager, libvirt, or another equivalent hypervisor is fine.
Repeatability matters more than performance.

## Installation Media

Download Fedora Silverblue 44 from the Fedora Project:

https://fedoraproject.org/atomic-desktops/silverblue/download/

Verify checksum and signature using Fedora's instructions. Do not use respins,
unofficial images, or derivatives for the first lab.

## Installer Flow

1. Boot the VM from the Fedora Silverblue ISO.
2. Install the default GNOME-based Silverblue system.
3. Enable full-disk encryption in the installer.
4. Use the Fedora-provided storage defaults.
5. Keep Btrfs if the installer selects it by default.
6. Keep the installer-created LUKS2 layout.
7. Do not create custom subvolumes in the first install.
8. Do not add third-party repositories during installation.
9. Do not install proprietary drivers during installation.
10. Reboot into the installed system.

If manual partitioning is unavoidable, preserve Fedora's expected behavior:

- EFI System Partition for UEFI;
- separate `/boot`;
- LUKS2 for the encrypted system volume;
- Btrfs-backed system layout;
- home layout compatible with Silverblue, then validate `/home` and `/var/home`
  after first boot.

## First Boot

Record the initial state:

```sh
rpm-ostree status
uname -a
findmnt /
findmnt /var
findmnt /var/home
lsblk -f
```

Update before any experiment:

```sh
sudo rpm-ostree upgrade
sudo systemctl reboot
```

After reboot:

```sh
rpm-ostree status
uname -a
systemctl --failed
```

## Stock Secure Boot Baseline

Before TPM2 enrollment or kernel replacement, validate the unmodified Fedora
boot path:

```sh
mokutil --sb-state
bootctl status
rpm-ostree status
uname -a
systemctl --failed
journalctl -b -p warning..alert --no-pager
```

Expected result:

- Secure Boot is enabled;
- the running deployment is the stock Fedora Silverblue deployment;
- the running kernel is Fedora's kernel;
- there are no bootloader, initramfs, LUKS, or kernel failures.

If the VM cannot provide Secure Boot or TPM2, keep using it for filesystem and
rpm-ostree learning, but do not mark the boot-security requirement as validated.

## Baseline Validation

Clone or copy this repository into the VM:

```sh
cd ~/dev/margine-fedora-atomic
scripts/validate-atomic-layout
scripts/collect-diagnostics
```

Keep the diagnostic bundle as the pre-COPR baseline.

## Flatpak and Flathub

Flatpak is the preferred channel for graphical applications. Enable Flathub only
after recording the clean host baseline:

```sh
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
flatpak remotes
flatpak list
```

## Toolbox

Toolbox is the preferred channel for command-line tools, SDKs, compilers, and
development dependencies:

```sh
toolbox create
toolbox enter
```

Install development tools inside the toolbox with DNF. Exit with:

```sh
exit
```

Distrobox is not a phase 1 default. Evaluate it only if toolbox is insufficient.

## Host Layering

Do not layer host packages in the baseline unless the lab explicitly requires
one.

When a host package is justified:

```sh
sudo rpm-ostree install <package>
sudo systemctl reboot
```

Record the reason. Host layering is acceptable for drivers, virtualization host
support, kernel experiments, or similar host-level requirements. It is not the
default path for ordinary GUI applications.

## TPM2 Auto-Unlock Lab

Run this only after the encrypted stock Fedora deployment has booted once with
Secure Boot enabled and a manual passphrase.

Discovery commands:

```sh
systemd-cryptenroll --tpm2-device=list
lsblk -f
cat /etc/crypttab
rpm-ostree status
```

The Fedora Workstation TPM2 guides use `systemd-cryptenroll`, `/etc/crypttab`,
dracut modules, and initramfs regeneration. On Silverblue, do not run `dracut -f`
as the assumed final step. rpm-ostree owns deployment construction and initramfs
handling, so the lab must verify the equivalent `rpm-ostree initramfs` workflow
before documenting a hardware procedure.

High-level sequence:

1. Identify the LUKS2 block device that backs the encrypted system.
2. Confirm a manual passphrase or recovery key can unlock it.
3. Add the TPM2 dracut support required by the validated Fedora release.
4. Enable rpm-ostree-managed local initramfs regeneration if required.
5. Reboot once and confirm the manual unlock path still works.
6. Enroll TPM2 with `systemd-cryptenroll`.
7. Add the matching `tpm2-device=auto` options to `/etc/crypttab`.
8. Rebuild the next deployment through rpm-ostree, reboot, and confirm automatic
   unlock.
9. Test one Fedora update and one rollback with TPM2 unlock still configured.

Do not wipe the original passphrase slot during phase 1.

## Preparing for the Kernel Experiment

Before enabling the CachyOS COPR:

```sh
rpm-ostree status
sudo ostree admin pin 0
rpm-ostree status
```

The pinned deployment preserves a known Fedora fallback in the boot menu. Also
take a hypervisor snapshot.
