# Roadmap

The phases below were drafted when Margine was a manual VM-lab on
Fedora Silverblue. The plan changed (see [ADR
0005](adr/0005-base-on-bluefin-dx.md)): Margine ships as a real
bootc image derived from Bluefin DX, with a CI pipeline that gates
`:stable` on a QEMU smoke-boot test. This page now records the **status
as of 2026-06-01**, what we delivered against each original milestone,
and what's still pending.

## Phase 1 — Validate the Atomic model

**Status:** Done.

**Original intent:** Understand and validate Fedora Atomic Desktop as
it actually behaves before building anything on top of it.

**Delivered:**

- ✅ Bluefin DX in a UEFI VM with Secure Boot + vTPM 2.0
  (chose Bluefin DX over stock Silverblue per ADR 0005 — it already
  brings the developer / virt / container toolbox we'd otherwise add)
- ✅ `scripts/validate-atomic-layout` validates the deployed ostree
  layout and is now baked into the image as `/usr/bin/margine-validate-atomic-layout`
- ✅ Baseline diagnostic bundle automated as
  `scripts/collect-diagnostics` (idem `/usr/bin/margine-collect-diagnostics`)
- ✅ Secure Boot + MOK signing for the CachyOS kernel (sbsign vmlinuz,
  sign-file modules), first-boot enrollment via `mok-enroll.service`
- ⏸ TPM2 auto-unlock via systemd-cryptenroll: documented in
  [`07-secure-boot-tpm2.md`](07-secure-boot-tpm2.md), runtime
  enrollment intentionally manual (one-time `systemd-cryptenroll`
  command on first boot)
- ✅ CachyOS kernel deployed and signed in CI; baseline image is
  `7.0.x-cachyos*.fc44.x86_64`
- ✅ Rollback tested and documented (`bootc rollback`, plus libvirt
  snapshot pattern for VM lab work)
- ✅ Declarative source of truth in `declarations/margine-atomic.yaml`
  drives the helpers
- ✅ Risks documented in [`05-known-risks.md`](05-known-risks.md) and
  in `lessons-learned/`

## Phase 2 — Drift detection / validators

**Status:** Done (in a different shape than originally planned).

**Original intent:** read-only `validate-declared-state` script that
diffs declarations against running system.

**Delivered, differently:** rather than a single drift-detector, the
repo ships **per-aspect validators** that are each baked into the
image. They cover the same surface and run faster:

- `validate-atomic-layout` — ostree layout, mounts, Secure Boot, TPM2
- `validate-cachyos-kernel` — version, signatures, MOK enrollment
- `validate-hardware-media-stack` — Mesa, Vulkan, VA-API, PipeWire, OpenCL
- `validate-gaming-runtime` — gaming-relevant runtime bits
- `validate-margine-system` — end-to-end acceptance test (sums up
  the others + branding + GNOME + flatpaks + helpers + bootstrap +
  failed-units detector). Used in the smoke-boot CI step and by the
  user after every `bootc upgrade`.

Still **TODO**, of the original intent:

- ⏳ A dedicated drift check for GNOME `dconf` settings vs the
  declaration (today the validators check key presence, not value
  diff). Lower priority — `configure-gnome-appearance` is
  idempotent, so users just re-run it.

## Phase 3 — Plan-first adapters / declarative apply

**Status:** Largely done (under a different name).

**Original intent:** plan-first adapters that compute a diff and
apply changes per channel.

**Delivered:** the `configure-*` helpers each read
`declarations/margine-atomic.yaml`, default to **dry-run**, and only
mutate on `--apply`. They are channel-specific (extensions, keybinds,
app folders, appearance, home layout, default applications, zen
browser). The `ujust margine-bootstrap` recipe runs the full chain
in sequence.

Still **TODO**:

- ⏳ A coarser drift report layered on top of the existing helpers
  (think `margine-status` that prints "OK / drifted / unknown" per
  channel without applying). Nice-to-have, not blocking.

## Phase 4 — Native bootc image + CI

**Status:** Done and operating.

**Delivered:**

- ✅ `margine-image` repo builds a bootc image (Bluefin DX +
  CachyOS signed kernel + Margine deltas) via GH Actions on a
  self-hosted runner
- ✅ Layer A guardrails (image internals check before push)
- ✅ `:candidate → :stable` promotion model with QEMU smoke-boot
  test on every build (see [lessons-learned 2026-06-01](lessons-learned/2026-06-01-systemd-ordering-cycle-and-rechunk-storage.md))
- ✅ Cosign signature on the published image
- ✅ ISO + qcow2 publishing via Internet Archive (torrent + 3 HTTP
  mirrors) + HTML index on `files.the-empty.place` (see
  [19-iso-distribution.md](19-iso-distribution.md))
- ✅ Observability via ntfy push (build / smoke-boot / disk-build
  outcomes) + client-side `margine-staleness.timer` +
  `margine-upgrade-notify.service` (see [18-observability.md](18-observability.md))

Still **TODO**:

- ⏳ Move the `:stable` redirect to a *signed cosign verification* on
  the user side (today `bootc` trusts the registry; we could
  configure rpm-ostree's `verify-by-key` to enforce cosign at the
  client). Defense in depth.
- ⏳ Build cadence: today builds run on push to main + on demand.
  A nightly cron is documented but not wired (would catch upstream
  drift in Bluefin DX even on quiet days).

## Beyond the original phases

Two pieces of platform infrastructure landed in 2026-05/06 that
weren't on the original roadmap but are now part of how Margine
operates:

- **`proxmox-pve1` integration**: the self-hosted runner lives on a
  PVE1 VM (`margine-builder`), guarded by `podman-guardian.timer`
  + I/O caps + cleanup hygiene; documented in
  `proxmox-pve1/docs/operations/{provision-margine-builder,builder-podman-guardian,builder-dashboard,notifications-ntfy,auto-updates,iso-distribution}.md`.
- **Builder dashboard**: small FastAPI on `http://192.168.2.40:8765`
  that aggregates GH Actions runs + podman/disk/process health on
  the builder + `qm list` on PVE.

Those are operational, not Margine-spec proper, so they live in the
`proxmox-pve1` repo. They're documented here for context because
they directly affect the build reliability story.
