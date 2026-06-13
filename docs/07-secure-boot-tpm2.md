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

## Lab-Validated Procedure (Fedora Silverblue 44 VM)

These commands were proven in the phase 1 VM lab. Use them as the reference for
the hardware lab and for documentation of any divergences.

### PCR policy choice

In a VM without Secure Boot, PCR 7 (Secure Boot state) is not stable. Use
`--tpm2-pcrs=0` (Platform Firmware) only:

```sh
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0 /dev/vda3
```

On real hardware with Secure Boot enabled, add PCR 7:

```sh
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+7 /dev/sda3
```

Replace `/dev/vda3` / `/dev/sda3` with the actual LUKS2 block device from
`lsblk -f`. The passphrase is prompted during enrollment.

### Crypttab update

After enrollment, add `tpm2-device=auto` and the matching `tpm2-pcrs` value to
the options in `/etc/crypttab`:

```sh
sudoedit /etc/crypttab
```

The existing Anaconda-generated line looks like:

```text
luks-<uuid>  UUID=<uuid>  none  discard,x-initrd.attach
```

Append the TPM2 options:

```text
luks-<uuid>  UUID=<uuid>  none  discard,x-initrd.attach,tpm2-device=auto,tpm2-pcrs=0
```

Use `tpm2-pcrs=0+7` on hardware with Secure Boot.

### Initramfs regeneration

On Silverblue, `rpm-ostree initramfs` is **disabled by default**. The stock
initramfs comes from the OSTree commit and does not include your local
`/etc/crypttab` changes. Enable local initramfs regeneration to bake the
updated crypttab into the next deployment:

```sh
sudo rpm-ostree initramfs --enable
```

This stages a new deployment. Reboot using the GNOME menu to enter it. After
reboot the system should unlock automatically without prompting for a
passphrase.

### Verify TPM2 unlock is active

```sh
systemd-cryptenroll --tpm2-device=list
sudo cat /etc/crypttab
rpm-ostree initramfs
rpm-ostree status
```

Expected:

- `systemd-cryptenroll --tpm2-device=list` reports the enrolled TPM2 device;
- `/etc/crypttab` contains `tpm2-device=auto`;
- `rpm-ostree initramfs` reports `Initramfs regeneration: enabled`;
- the system booted without a passphrase prompt.

### Rollback and roll-forward test results (VM lab, Fedora 44)

After TPM2 enrollment, a rollback/roll-forward cycle was tested:

| Deployment | Initramfs | Result |
| --- | --- | --- |
| Current (local regenerated) | `Initramfs: regenerate` | Auto-unlock — no passphrase |
| Previous (stock OSTree) | Stock Fedora initramfs | Auto-unlock — no passphrase |
| Roll-forward (local regenerated) | `Initramfs: regenerate` | Auto-unlock — no passphrase |

**Key finding.** TPM2 auto-unlock works on both the local and stock initramfs
deployments. The Fedora stock initramfs includes the dracut TPM2 modules.
systemd-cryptsetup reads the TPM2 token directly from the LUKS2 header and
attempts auto-unlock automatically, regardless of whether `tpm2-device=auto`
is present in the embedded crypttab.

The `tpm2-device=auto` crypttab entry and local initramfs regeneration remain
correct practice because they make the intent explicit, document the PCR policy,
and ensure predictable behavior across systemd versions. They are not strictly
required for basic auto-unlock to function.

**Recovery path confirmed.** The passphrase enrolled in key slot 0 was not
removed. It can be used to unlock the disk at any time regardless of TPM2 state.

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

## MOK Signing for the CachyOS Kernel

The Margine bootc image solves the "CachyOS under Secure Boot" problem by
**signing the kernel and modules at image build time** with a Margine MOK
(Machine Owner Key). Fresh ISO installs submit the matching certificate from
Anaconda before the first post-install reboot, while `mok-enroll.service`
remains the rebase and missed-prompt fallback. The user confirms the import
from the bootloader's MOK Manager UI once; thereafter the CachyOS kernel boots
under Secure Boot without intervention.

This section documents the procedure as it actually ships. Source code:
[`margine-image/build_files/custom-kernel/install.sh`](https://github.com/daniel-g-carrasco/margine-image/blob/main/build_files/custom-kernel/install.sh).

### Key material

| File | Where it lives | Visibility |
| --- | --- | --- |
| `MOK.key` (RSA 2048 private) | GitHub Actions secret `MOK_KEY`; local backup at `~/data/technology/00-admin/security/encryption/margine-image-keys/MOK.key` (chmod 600) | **private — never committed** |
| `MOK.pem` (X.509 certificate, PEM) | `margine-image/secrets/MOK.pem` (committed) and GH Actions secret `MOK_CERT` | public |
| `MOK.der` (X.509 certificate, DER) | `margine-image/secrets/MOK.der` (committed) | public |
| MOK enrollment passphrase | **Not a secret.** Hardcoded constant `MOK_PASSWORD="margine-os"` in `margine-image/build_files/custom-kernel/install.sh`. Public by design: the user types it at the MOK Manager screen, the live-ISO dialog prints it, and these docs spell it out — routing it through a GitHub Actions secret would imply a confidentiality that does not exist. The old `MOK_PASSWORD` repo secret was **removed 2026-06-12** (the build no longer consumes it; only `MOK_KEY` + `MOK_CERT` are staged). This string only gates the one-shot physical-presence trust handoff on first boot. | public-by-design |

The cert fingerprint at the time of this writing is
`DF:C0:A7:0A:8B:90:EC:8F:01:04:1C:F7:7C:05:F0:79:76:B8:CC:72:BC:8C:38:F4:6D:26:5D:DA:6C:1E:55:B1`.

### Build-time flow

1. `dnf -y install sbsigntools` (provides `sbsign` and `sbverify`).
2. Remove Bluefin's stock kernel packages, then `dnf -y install kernel-cachyos kernel-cachyos-core kernel-cachyos-modules kernel-cachyos-devel-matched` from the `bieszczaders/kernel-cachyos` COPR.
3. **Sign vmlinuz**: `sbsign --key MOK.key --cert MOK.pem --output … /usr/lib/modules/${KERNEL_VERSION}/vmlinuz`, then `sbverify --cert MOK.pem` to confirm.
4. **Sign every kernel module**: for each `*.ko`/`*.ko.xz`/`*.ko.zst`/`*.ko.gz` under `/usr/lib/modules/${KERNEL_VERSION}`, decompress, run `scripts/sign-file sha256 MOK.key MOK.pem <module>`, recompress.
5. **Write the cert + fallback enrollment unit**: convert `MOK.pem` to DER at `/usr/share/cert/MOK.der`, write `/usr/lib/systemd/system/mok-enroll.service` (oneshot, gated by `ConditionPathExists=!/var/.mok-enrolled`), `systemctl enable mok-enroll.service`.
6. Regenerate the initramfs against the new kernel (`dracut --force --kver "$KERNEL_VERSION" --regenerate-all`).

### ISO install user experience

1. During Anaconda `%post --nochroot`, the installer locates `/usr/share/cert/MOK.der` in the target deployment and runs `mokutil --timeout -1` plus `mokutil --import` with the `margine-os` passphrase.
2. On the first post-install reboot, shim notices the pending request and presents the **MOK Manager** screen before the installed system starts.
3. The user selects "Enroll MOK", confirms, types the MOK passphrase (`margine-os`), and reboots into Margine.
4. The CachyOS kernel now boots under Secure Boot. `mokutil --sb-state` should report `SecureBoot enabled`, and `mokutil --list-enrolled` should show the Margine cert.

### Titanoboa live ISO (ADR-0008, in migration)

[ADR-0008](adr/0008-titanoboa-migration-plan.md) moves the ISO build from
bootc-image-builder to Titanoboa. The MOK staging logic is unchanged — it
ports verbatim into `live-env/src/anaconda/post-scripts/secureboot-enroll-key.ks`
(same `mokutil --timeout -1` + `mokutil --import` with the `margine-os`
passphrase, same `/usr/share/cert/MOK.der`, same "do not write
`/var/.mok-enrolled`" so the service fallback still recovers). The
post-install MOK Manager experience above is identical.

One NEW consideration is specific to the Titanoboa live medium. The
current BIB installer ISO boots a Fedora-signed Anaconda kernel, so the
*installer itself* runs under Secure Boot and only the *installed* CachyOS
kernel needs enrollment. The Titanoboa live ISO instead runs Margine's own
CachyOS kernel as the live environment (ADR-0008 §3.2 keeps CachyOS in both
live and installed — no vanilla-kernel swap), which is not trusted until the
Margine MOK is enrolled. The supported flow is therefore:

1. Disable Secure Boot in firmware to boot the Margine live ISO.
2. Install Margine (Anaconda stages the MOK request, as above).
3. Re-enable Secure Boot.
4. MOK Manager prompts on the next reboot; enroll with `margine-os`.
5. The installed CachyOS kernel now boots under Secure Boot.

This is the documented trade-off for shipping a single distinguishing
kernel in both environments rather than a separate signed live kernel.

### Rebase user experience

1. After `rpm-ostree rebase` to the Margine image and reboot, `mok-enroll.service` runs once. It pipes the MOK password twice into `mokutil --import /usr/share/cert/MOK.der` and writes `/var/.mok-enrolled` as its skip marker.
2. The user reboots again. The firmware presents the **MOK Manager** screen.
3. The user selects "Enroll MOK", confirms, types the MOK passphrase (`margine-os`), and reboots one final time. User-facing walkthrough with screenshots: <https://margine.the-empty.place/docs/first-boot>.
4. The CachyOS kernel now boots under Secure Boot. `mokutil --sb-state` should report `SecureBoot enabled`, and `mokutil --list-enrolled` should show the Margine cert.

### Recovery if MOK enrollment is missed

If the user reboots past the MOK Manager screen without confirming on the
ISO path, the booted-system service can recreate the request because Anaconda
does not write `/var/.mok-enrolled`. If the service fallback has already run
and created the marker, retry by logging in (using the original LUKS passphrase
if TPM2 sealed against PCR 7), then:

```sh
sudo rm /var/.mok-enrolled
sudo systemctl start mok-enroll.service
sudo systemctl reboot
```

The MOK Manager will appear again on next boot.

### PCR policy after MOK enrollment

Once the Margine MOK is enrolled and Secure Boot is enabled with the
CachyOS kernel, the **hardware** target PCR policy is `0+7` (Platform
Firmware + Secure Boot state). The VM lab uses `0` only, because Secure
Boot is disabled in the VM. Re-enroll TPM2 against the new PCR policy
after the first successful Secure-Boot boot, **before** wiping the
passphrase slot (which Margine never does in any case — passphrase
recovery is permanent).

## References

- Fedora Secure Boot: https://fedoraproject.org/wiki/Secureboot
- systemd-cryptenroll manual: https://www.freedesktop.org/software/systemd/man/latest/systemd-cryptenroll.html
- crypttab manual: https://www.freedesktop.org/software/systemd/man/latest/crypttab.html
- Fedora Magazine TPM2/systemd-cryptenroll guide: https://fedoramagazine.org/use-systemd-cryptenroll-with-fido-u2f-or-tpm2-to-decrypt-your-disk/
- rpm-ostree administrator handbook: https://coreos.github.io/rpm-ostree/administrator-handbook/
- rpm-ostree architecture notes: https://coreos.github.io/rpm-ostree/architecture-core/
