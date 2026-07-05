# Expected Silverblue Behaviors

This document covers system behaviors that look like errors but are normal on
Fedora Silverblue. Each entry has been observed in the phase 1 VM lab and
confirmed as expected.

These are not workarounds. They are how Fedora Atomic works.

## systemd-remount-fs.service fails at boot

```
systemd-remount-fs.service: Failed with result 'exit-code'.
mount: /: fsconfig() failed: overlay: No changes allowed in read-execute mode
```

**Why it happens.** Silverblue uses a composefs overlay as the root filesystem.
`systemd-remount-fs` attempts to remount `/` with options from `/etc/fstab`, but
composefs overlays cannot be remounted once mounted read-only. The root is
already correctly mounted; the remount is redundant and unsupported.

**Status.** Harmless. This is a known interaction between systemd-remount-fs and
composefs on Fedora Atomic. No action required.

**Validator behavior.** `scripts/validate-atomic-layout` reports this unit as
failed via `systemctl --failed`. The failure is visible but does not cause
`validate-atomic-layout` to exit non-zero.

## mcelog.service fails in a VM

```
mcelog.service: Failed with result 'exit-code'.
```

**Why it happens.** `mcelog` provides Machine Check Exception logging, which
reads hardware CPU error registers. These registers are not available in
virtualized environments.

**Status.** Harmless in a VM. On physical hardware, `mcelog` may work or may
still fail depending on the CPU and kernel configuration. Either outcome is
acceptable in phase 1.

## /usr has no separate mount point

On Silverblue with composefs (Fedora 39 and later), `/usr` is embedded in the
root overlay. Running `findmnt /usr` returns nothing.

**Why it happens.** The composefs root presents the entire ostree deployment
content — including `/usr` — as a single read-only overlay layer. There is no
need for a separate `/usr` mount.

**Status.** Correct. The read-only guarantee for `/usr` is enforced by the
composefs overlay, not by a separate mount with `ro` options.

**Validator behavior.** `scripts/validate-atomic-layout` detects this case and
reports it as expected when the root fstype is `overlay`.

## systemctl reboot is blocked in a GNOME session

```
Operation inhibited by "margineuser" (PID ... "gnome-session-s", ...),
reason is "user session inhibited".
```

**Why it happens.** systemd logind respects GNOME session inhibitors. When a
GNOME session is active, `systemctl reboot` (even with `sudo`) is blocked to
allow the session to clean up first.

**`systemctl reboot -i`** bypasses inhibitors but is also blocked by the default
polkit configuration:

```
The current polkit policy does not allow root to ignore inhibitors without
authentication in order to reboot.
```

**Standard path.** Use the GNOME top-right menu → Power → Restart. This is the
correct way to reboot from an active GNOME session. The terminal `systemctl
reboot` pattern applies on headless systems or after the GNOME session has ended.

## /etc/crypttab is not readable without elevated privileges

The file `/etc/crypttab` is mode 600 and owned by root. Running `cat
/etc/crypttab` as a normal user produces a permission error.

**Standard path.** Use `sudo cat /etc/crypttab` or `sudoedit /etc/crypttab`.

**Validator behavior.** `scripts/validate-atomic-layout` checks whether
`/etc/crypttab` is readable by the current user. When it exists but is not
readable, the validator emits a warning explaining that sudo is required, rather
than reporting the file as missing.

## rpm-ostree initramfs is disabled by default

```
$ rpm-ostree initramfs
Initramfs regeneration: disabled
```

**Why it happens.** By default, Silverblue uses the stock initramfs bundled with
the OSTree commit. rpm-ostree does not regenerate the initramfs locally unless
explicitly told to do so.

**When this matters.** After updating `/etc/crypttab` (for example to add
`tpm2-device=auto` after TPM2 enrollment), the change will not be picked up at
the next boot unless initramfs regeneration is enabled. The stock initramfs
contains the crypttab snapshot from when the OSTree commit was composed.

**Standard path.** Enable local initramfs regeneration before rebooting after a
crypttab change:

```sh
sudo rpm-ostree initramfs --enable
```

This stages a new deployment with a locally built initramfs that includes the
current `/etc/crypttab`. Reboot using the GNOME menu to enter the new
deployment.

After the TPM2 lab is stable, local initramfs regeneration should remain enabled
so that future crypttab changes are always reflected automatically.
