# Secure Boot and TPM2 Auto-Unlock

Secure Boot and TPM2 automatic disk unlock are target requirements for Margine
Fedora Atomic. They are not optional polish and they are not copied from the old
Arch/CachyOS boot design.

The phase 1 rule is conservative: prove the stock Fedora Silverblue path first,
then add TPM2 unlock, then test third-party kernels.

## Target Model

| Component | Decision |
| --- | --- |
| Firmware | UEFI with Secure Boot enabled |
| Baseline boot chain | Fedora shim, bootloader, and Fedora kernel |
| Disk encryption | installer-created LUKS2 system encryption |
| Auto-unlock | `systemd-cryptenroll` TPM2 enrollment |
| Persistent config | `/etc/crypttab` plus validated rpm-ostree initramfs handling |
| Recovery | keep passphrase or recovery key enrolled |
| Third-party kernel | lab-only until Secure Boot behavior is proven |

Do not start this project from Limine, `sbctl`, Arch UKI generation, mkinitcpio,
or root-on-ZFS unlock logic. Fedora Atomic has a different boot and deployment
model.

## Lab Order

1. Install Fedora Silverblue with encryption and Secure Boot enabled.
2. Update and reboot into the updated stock Fedora deployment.
3. Validate Secure Boot, LUKS2, Btrfs, and rpm-ostree state.
4. Add TPM2 unlock while preserving passphrase recovery.
5. Test one update and one rollback with TPM2 unlock configured.
6. Only then test the CachyOS kernel experiment.

The CachyOS kernel is not part of the compliant baseline unless it can boot
under the intended Secure Boot trust model.

## Stock Baseline Checks

Run on the encrypted stock Fedora deployment:

```sh
rpm-ostree status
uname -a
mokutil --sb-state
bootctl status
findmnt /
findmnt /var
findmnt /var/home
lsblk -f
cat /etc/crypttab
systemctl --failed
journalctl -b -p warning..alert --no-pager
```

Expected result:

- Secure Boot is enabled;
- `uname -a` reports a Fedora kernel;
- the encrypted system boots with a manual passphrase;
- `/home` resolves through the Silverblue `/var/home` model;
- no bootloader, LUKS, initramfs, Btrfs, or kernel errors appear.

## TPM2 Discovery

Before enrolling anything:

```sh
systemd-cryptenroll --tpm2-device=list
lsblk -f
cat /etc/crypttab
rpm-ostree status -v
```

Identify the LUKS2 block device that backs the encrypted system. Do not enroll
against an unstable temporary name without also recording the stable
`/dev/disk/by-uuid/...` path.

## Initramfs Handling on Silverblue

Most Fedora Workstation TPM2 examples end with `dracut -f`. That is not the
starting assumption for Silverblue.

rpm-ostree owns deployment construction and initramfs generation. If TPM2 unlock
requires adding dracut configuration or including updated `/etc/crypttab` state
in the initramfs, validate the rpm-ostree-managed path in the VM. The relevant
concept is local initramfs regeneration through `rpm-ostree initramfs`, not a
mutable-root `dracut -f` habit.

The lab must record:

```sh
rpm-ostree initramfs
rpm-ostree status -v
ls /etc/dracut.conf.d
cat /etc/crypttab
```

Only document exact commands after the Fedora 44 VM proves them.

## Enrollment Shape

The final procedure will use this shape, with the real device and PCR policy
chosen after lab observation:

```sh
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=<pcr-policy> /dev/disk/by-uuid/<luks-uuid>
```

Then configure the matching `/etc/crypttab` option, for example:

```text
tpm2-device=auto
```

If PCRs are explicitly selected during enrollment, record the matching
`tpm2-pcrs=` value in `/etc/crypttab`.

Do not wipe the original passphrase slot in phase 1. A recovery path is part of
the design, not a temporary crutch.

## PCR Policy

Do not choose the final PCR set from the old Arch system.

For the first Fedora Atomic lab:

- start from the systemd/Fedora documented TPM2 path;
- observe what changes across a normal Fedora update;
- observe what changes across `rpm-ostree rollback`;
- avoid sealing to a temporary state where Secure Boot was disabled;
- document the exact PCR policy only after those tests.

PCR 7 is commonly relevant to Secure Boot state. More restrictive policies may
be desirable later, but they must not make routine Fedora updates unrecoverable.

## Validation After Enrollment

After TPM2 enrollment and reboot:

```sh
rpm-ostree status
uname -a
mokutil --sb-state
cat /etc/crypttab
systemd-cryptenroll --tpm2-device=list
systemctl --failed
journalctl -b -p warning..alert --no-pager
```

Pass criteria:

- the machine unlocks automatically using TPM2;
- manual passphrase unlock still works when TPM2 is unavailable or enrollment is
  cleared in the VM;
- Secure Boot remains enabled;
- Fedora updates still create bootable deployments;
- `rpm-ostree rollback --reboot` remains usable.

## Interaction With CachyOS Kernel

The CachyOS kernel experiment must be evaluated after the Fedora Secure
Boot/TPM2 baseline.

Acceptable lab results:

- CachyOS kernel boots only with Secure Boot disabled: useful lab data, but not
  target-compliant.
- CachyOS kernel boots with Secure Boot enabled through a documented trust path:
  candidate for later hardware testing.
- TPM2 unlock breaks after the kernel or initramfs changes: stop and return to
  the Fedora kernel until the PCR/initramfs behavior is understood.

Never make a script that forces the CachyOS deployment to stay default while the
boot security model is unresolved.

## References

- Fedora Secure Boot: https://fedoraproject.org/wiki/Secureboot
- systemd-cryptenroll manual: https://www.freedesktop.org/software/systemd/man/latest/systemd-cryptenroll.html
- crypttab manual: https://www.freedesktop.org/software/systemd/man/latest/crypttab.html
- Fedora Magazine TPM2/systemd-cryptenroll guide: https://fedoramagazine.org/use-systemd-cryptenroll-with-fido-u2f-or-tpm2-to-decrypt-your-disk/
- rpm-ostree administrator handbook: https://coreos.github.io/rpm-ostree/administrator-handbook/
- rpm-ostree architecture notes: https://coreos.github.io/rpm-ostree/architecture-core/
