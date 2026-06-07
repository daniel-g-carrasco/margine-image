# 2026-06-01 — systemd ordering cycle + rechunk storage rituals

A two-act story. Both acts changed how the CI now publishes images.
The user-visible takeaway is that `:stable` no longer means "the last
build that compiled"; it means "the last build that booted to a
usable state inside QEMU".

## Act 1 — the ordering-cycle that pushed a boot into emergency.target

### Symptoms

A fresh VM rebased to the morning's image, rebooted, and stalled at
the systemd console between sysinit and multi-user. `Ctrl+Alt+F2`
did nothing — the tty was captured by the emergency shell. Power
cycle, `bootc rollback`, log inspection on the previous deployment:

```
local-fs-pre.target: Found ordering cycle:
  systemd-tmpfiles-setup-dev.service/start
  after systemd-sysusers.service/start
  after margine-seed-etc-passwd.service/start
  after local-fs.target/start
  after var-lib-machines.mount/start
  after local-fs-pre.target/start
  - after systemd-tmpfiles-setup-dev.service
…
Timed out waiting for device dev-disk-by-uuid/…
Reached target emergency.target - Emergency Mode.
```

systemd had broken the cycle by **disabling `systemd-tmpfiles-setup-
dev.service`** — its way of unblocking the dag. Without that service
the `/dev/disk/by-uuid/*` symlinks were never populated, every
`*.device` unit timed out after 90s, and the system isolated to
`emergency.target`. Userspace was actually quiet (`gdm`, `NetworkManager`
and friends had been pulled in but never started), the kernel was
fine, the disk was fine — it was a pure dependency-graph deadlock.

### Cause

The new `margine-seed-etc-passwd.service` (which seeds `/etc/passwd`
+ `/etc/group` from `/usr/lib/{passwd,group}` if a post-rechunk
deployment has them stripped, see
[2026-05-28 initramfs and bootc labels](2026-05-28-initramfs-and-bootc-labels.md))
was wired with:

```ini
DefaultDependencies=no
Before=sysinit.target systemd-sysusers.service systemd-tmpfiles-setup.service
After=local-fs.target
```

The `After=local-fs.target` was the offender. `local-fs.target` itself
depends transitively on `systemd-tmpfiles-setup-dev.service`, but the
seed unit was also `Before=systemd-sysusers.service`, which is in the
chain that includes `tmpfiles-setup-dev`. Closed loop.

### Fix

```diff
 DefaultDependencies=no
-Before=sysinit.target systemd-sysusers.service systemd-tmpfiles-setup.service
-After=local-fs.target
+Before=systemd-sysusers.service systemd-tmpfiles-setup.service sysinit.target
+After=local-fs-pre.target
```

`/etc` and `/usr` are part of the ostree deployment and are mounted
before any local-fs unit runs in userspace, so depending on
`local-fs.target` was overkill. `local-fs-pre.target` is enough to
guarantee `/etc` is writable when the seed runs, and crucially it
sits *before* `tmpfiles-setup-dev` rather than after it — no more
cycle.

### Memory entry

feedback-systemd-after-local-fs (internal note)
(local AI memory). Rule of thumb: **never combine `After=local-fs.target`
with `Before=systemd-sysusers/tmpfiles` on a unit that runs in early
boot.** Use `After=local-fs-pre.target` or no `After=` at all.

### CI change: Layer A now runs `systemd-analyze verify`

This class of bug is statically detectable: `systemd-analyze verify
default.target` reports cycles offline without needing a boot. The
Layer A guardrail step in `build.yml` now runs it inside the image
before push:

```bash
inspect 'SYSTEMD_OFFLINE=1 systemd-analyze verify default.target'
```

If it errors, the image fails to publish.

## Act 2 — `:stable` now means "smoke-bootedded", not "compiled"

The bigger architectural change. Before today, `build.yml` published
`:stable` directly. Smoke-boot was a separate `workflow_run` that
*also* booted the image in QEMU, but if it failed, the user could
still `bootc upgrade` and pick up the broken image — the failure of
the smoke-test did not retract the tag.

### New model: candidate → stable

1. `build.yml` now publishes only `:candidate` + `:candidate.<date>`.
2. `smoke-boot.yml` is auto-triggered by `workflow_run` on success of
   the build.
3. It pulls `:candidate`, runs `bootc-image-builder` to produce a
   qcow2, boots it in QEMU, and waits for any of:
   - `Started ... gdm.service`
   - `Reached target graphical.target`
   - `margine login:` (getty banner)
4. If any of the three appears, it `skopeo copy --preserve-digests`
   the candidate digest to `:stable` + `:stable.<date>` + `:<date>`.
5. If nothing appears within 20 min, the smoke-boot fails; `:stable`
   is left untouched and the maintainer gets a high-priority ntfy
   push.

`--preserve-digests` means promotion does not rebuild or re-rechunk —
the bytes a user pulls under `:stable` are identical to the bytes
that booted in CI.

### Other CI hardening that landed the same day

- **GHCR pre-build login** in `build.yml` so the base-image pull of
  `ghcr.io/ublue-os/bluefin-dx:stable` is authenticated. Anonymous
  pulls were getting 403 from ghcr.io after the builder cache reset.
- **OCI-archive intermediate** for the `move built image to root
  storage` step. Replaced `podman save | sudo podman load` (which
  silently corrupted a blob under memory pressure on the degraded
  ZFS host) with `podman save --format oci-archive` → sha256 verify
  twice → `sudo skopeo copy oci-archive: containers-storage:`.
- **`/var/tmp` instead of `/tmp`** for the oci-archive (the builder
  VM has `/tmp` as a 3.9 GB tmpfs which can't hold a 5 GB archive).
- **`gh run watch --exit-status` is not trustworthy** (bug cli/cli#3962
  and variants). All polling now uses a `gh api … --jq '.conclusion //
  empty'` until-loop against the actual API value.
- **Hard caps on the builder VM** (cpulimit, cpuunits, balloon=0,
  per-disk IOPS/MBPS limits, cache=writeback) to keep the build
  from saturating the ZFS-degraded PVE host like it did on the
  evening of 2026-05-31.

### Bug class buried by all of this

`:stable` can no longer leak an emergency-mode image. The Act 1 fix
removes the specific bug; the Act 2 change removes the *class* of
bug, because every future ordering-cycle / dracut / kernel /
initramfs regression that survives Layer A but kills the boot will
be caught by the smoke-boot QEMU run before promotion.
