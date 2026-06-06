# CachyOS Kernel Experiment

> **Production path (since 2026-05-26).** The Margine bootc image
> (`ghcr.io/daniel-g-carrasco/margine:stable`) bakes `kernel-cachyos`
> into the OCI image at build time and MOK-signs both the vmlinuz and
> every kernel module. First-boot `mok-enroll.service` imports the
> Margine MOK certificate via `mokutil`; after the user confirms the
> import from the bootloader, the CachyOS kernel boots cleanly under
> Secure Boot. See [docs/07-secure-boot-tpm2.md § MOK signing for the
> CachyOS kernel](07-secure-boot-tpm2.md#mok-signing-for-the-cachyos-kernel)
> and [`margine-image/build_files/custom-kernel/install.sh`](https://github.com/daniel-g-carrasco/margine-image/blob/main/build_files/custom-kernel/install.sh).
>
> **Userspace BPF schedulers (since 2026-06-03).** The sibling COPR
> `bieszczaders/kernel-cachyos-addons` ships `scx-scheds`, the
> sched_ext userspace schedulers (`scx_lavd`, `scx_bpfland`,
> `scx_rusty`, `scx_central`, `scx_simple`). These are installed in
> the **base** image, not gaming-only — pro-audio creators can use
> `scx_central` (single-CPU scheduling, lowest jitter) at any time.
> Runtime switch via `ujust margine-scheduler <name>`. The COPR is
> enabled transiently during `custom-kernel/install.sh`, the package
> is installed, then the repo is disabled and the `.repo` file
> removed so the runtime system has no exposure to the COPR
> (consistent with how the `kernel-cachyos` COPR itself is handled).
> The kernel-side `CONFIG_SCHED_CLASS_EXT=y` requirement is satisfied
> by the CachyOS kernel out of the box.
>
> **Same kernel binary whether or not the gaming layer is on.** The
> opt-in gaming layer (`ujust margine-gaming`, retired separate
> Margine Gaming OCI image 2026-06-06) only adds userspace RPMs
> (gamescope, vkBasalt) and Flatpaks — no `kmod-*`, no `kernel-*`
> packages, no `/lib/modules` changes.
>
> The lab procedure below is preserved as the **historical** Silverblue
> path (runtime `rpm-ostree override remove ... --install kernel-cachyos`).
> It runs unsigned, and only works with Secure Boot disabled. It is
> useful as a reference for understanding what the image build does, and
> as a fallback for users on stock Silverblue who want to experiment
> without rebasing.

---

The CachyOS kernel from COPR is experimental as a runtime-layered package.
It is not part of the Fedora Silverblue base and must not be treated as a
safe default in that path until rollback has been tested. It also must not
be treated as compatible with Secure Boot in the runtime-layered path
because nothing in the layered path signs vmlinuz or the modules.

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

## Lab Results (Fedora Silverblue 44 VM)

The CachyOS kernel experiment was run end-to-end in the phase 1 VM lab with
TPM2 auto-unlock already configured (PCR 0 only — see
[07-secure-boot-tpm2.md](07-secure-boot-tpm2.md)). All success criteria were
met.

### CPU

The lab VM passes through an AMD Ryzen 5 7640U (Zen 4). Output of
`/lib64/ld-linux-x86-64.so.2 --help`:

```
x86-64-v4 (supported, searched)
x86-64-v3 (supported, searched)
x86-64-v2 (supported, searched)
```

The `kernel-cachyos` main package (requires `x86-64-v3`) was used. The
`-lts` variant was not needed.

### Staging command

```sh
sudo rpm-ostree override remove \
  kernel kernel-core kernel-modules kernel-modules-core kernel-modules-extra \
  --install kernel-cachyos
```

Result: clean new deployment with `LayeredPackages: kernel-cachyos` and
`RemovedBasePackages: kernel-modules-core kernel-modules-extra kernel-core
kernel kernel-modules 7.0.9-205.fc44`. The pinned Fedora deployment was
preserved as the fallback.

### Boot into CachyOS

| Check | Result |
| --- | --- |
| Running kernel | `7.0.8-cachyos1.fc44.x86_64` |
| GNOME/GDM | works |
| TPM2 auto-unlock | works without passphrase |
| `systemctl --failed` | only `systemd-remount-fs` (expected on composefs) |
| `scripts/validate-cachyos-kernel` | `Failures: 0` |
| Kernel/initramfs/Btrfs/bootloader errors | none |

`mcelog.service` was not in the failed-units list under CachyOS (it had
been on Fedora kernel in the same VM). The reason is incidental; both
states are acceptable in a VM.

### TPM2 PCR behavior across kernel change

The most important observation: **TPM2 auto-unlock survived the kernel
change without re-enrollment**. The lab used `--tpm2-pcrs=0` (Platform
Firmware only), which does not depend on the kernel binary, the
initramfs, or Secure Boot state.

This is consistent with the design rationale recorded in
`07-secure-boot-tpm2.md`. On hardware with Secure Boot enabled and a
broader PCR policy (e.g. `0+7`), the same change would invalidate the
TPM2 token if the CachyOS kernel cannot be booted under the same Secure
Boot trust as the Fedora kernel.

### Rollback test

```sh
sudo rpm-ostree rollback
# reboot via GNOME menu
```

After reboot:

| Check | Result |
| --- | --- |
| Running kernel | `7.0.9-205.fc44.x86_64` (Fedora) |
| TPM2 auto-unlock | works without passphrase |
| CachyOS deployment | preserved as rollback (selectable from boot menu) |
| Fedora kernel packages | present in current deployment |

### Roll-forward test

A second `rpm-ostree rollback` re-staged CachyOS as the next boot. After
a second reboot, CachyOS was active again with TPM2 auto-unlock still
working.

### Lab default after the experiment

The VM was left with the CachyOS deployment as `● Booted` and the Fedora
pinned deployment preserved as the permanent fallback. This is a manual
decision for the VM lab so subsequent experiments run on top of CachyOS;
it is **not** a change to the project policy.

The declared policy in `declarations/margine-atomic.yaml`
(`kernel.experiment.force_as_default: false`) remains unchanged. Making
CachyOS the booted deployment on hardware requires:

- a documented Secure Boot trust path for the CachyOS kernel, or
- an explicit decision to disable Secure Boot and re-evaluate the
  TPM2 PCR policy (PCR 7 would no longer be stable).

Neither is in scope for phase 1.

### Key findings

- **CachyOS kernel boots cleanly on Fedora Silverblue 44 with composefs.**
  No special configuration was required beyond the documented `rpm-ostree
  override remove ... --install kernel-cachyos` flow.
- **TPM2 auto-unlock with PCR 0 only is robust to kernel change.**
  The same enrollment continues to work across Fedora kernel ↔ CachyOS
  kernel transitions, and across rpm-ostree rollback / roll-forward.
- **The Fedora pinned deployment is the right safety net.**
  Pinning the Fedora deployment before the experiment kept a known-good
  boot entry available at all times during rollback testing.
- **Secure Boot was disabled in this VM**, so the lab does **not** prove
  Secure Boot compatibility. Any decision to make CachyOS the default on
  hardware with Secure Boot enabled requires a separate analysis of the
  CachyOS signing/trust path. This is out of scope for phase 1.

### Out-of-tree module packages observed

`validate-cachyos-kernel` flagged two RPMs as potential out-of-tree
candidates:

```
nvidia-gpu-firmware-20260519-1.fc44.noarch
virtualbox-guest-additions-7.2.8-1.fc44.x86_64
```

Neither is an out-of-tree module driver:
- `nvidia-gpu-firmware` is part of `linux-firmware` and ships microcode
  blobs, not a kernel module;
- `virtualbox-guest-additions` here is the userspace tools package from
  Fedora; the kernel-side `vboxguest`/`vboxsf` modules are in-tree in
  CachyOS.

The validator warning is conservative and not actionable in this case.
