# Roadmap

This document describes the four phases of the Margine Fedora Atomic project,
their objectives, and the decision gates between them. Phases are sequential:
each gate must pass before the next phase begins.

## Phase 1 — Manual VM lab

**Status:** Active

**Objective:** Understand and validate Fedora Atomic Desktop as it actually
behaves before building anything on top of it.

The deliverable is not a bootable Margine image. The deliverable is a verified
lab model and a declarative source of truth that reflects real observations.

**Milestones:**

- Fedora Silverblue 44 installed from official media in a UEFI VM with Secure Boot and vTPM 2.0
- First update and reboot into the updated rpm-ostree deployment
- `scripts/validate-atomic-layout` run and reviewed; layout matches the ostree model
- Baseline diagnostic bundle collected before any third-party repositories
- Stock Fedora Secure Boot path confirmed as working
- TPM2 auto-unlock enrolled via systemd-cryptenroll with passphrase recovery still available
- Update and rollback tested with TPM2 enrollment intact
- Draft declaration in `declarations/margine-atomic.yaml` reflects observed decisions
- CachyOS kernel experiment run in the VM, or explicitly deferred with rationale
- Rollback to a Fedora kernel deployment tested
- Observed risks documented in `docs/05-known-risks.md`

**Decision gate:** All milestones above complete before moving to phase 2.

## Phase 2 — Drift detection

**Status:** Future

**Objective:** Build read-only tooling that compares the running system against
the declarations without applying changes.

The deliverable is a `validate-declared-state` script that reads
`declarations/margine-atomic.yaml` and reports deviations between declared
intent and the actual system state. Each channel (rpm-ostree, Flatpak, toolbox,
GNOME settings, home layout) gets its own check.

**Milestones:**

- Channel-specific drift check for rpm-ostree layered packages
- Channel-specific drift check for installed Flatpak applications
- Channel-specific drift check for GNOME dconf settings
- Channel-specific drift check for home layout (XDG dirs, fonts, folder metadata)
- Drift check integrated into `scripts/update-all` as a pre-update report
- Declaration schema documented in `declarations/README.md`

**Decision gate:** Drift detection covers all declared channels before moving to phase 3.

## Phase 3 — Plan-first adapters

**Status:** Future

**Objective:** Build channel-specific apply adapters that turn declarations into
system state, with explicit plan-then-confirm workflow.

The deliverable is a provisioner per channel that takes the declaration as
input, computes the required changes, shows a diff, and applies only after
confirmation. Each adapter is independent and does not assume other adapters
have run.

**Milestones:**

- rpm-ostree adapter: compute layered package additions/removals, confirm, apply
- Flatpak adapter: compute app additions/removals, confirm, apply
- GNOME dconf adapter: compute setting changes, confirm, apply
- Home layout adapter: create XDG dirs, set folder metadata, install fonts
- Toolbox adapter: create declared containers with declared packages
- All adapters integrated into `scripts/update-all` as optional apply step
- Adapters are dry-run capable and idempotent

**Decision gate:** All adapters pass dry-run and apply in the VM before moving to phase 4.

## Phase 4 — Native image or bootc

**Status:** Future (requires phase 3 complete)

**Objective:** Evaluate whether rpm-ostree layering can be replaced or
supplemented with a native image build or bootc-managed image.

This phase is intentionally underspecified. The correct approach depends on
what phases 1–3 reveal about the real operating model. Likely candidates:

- A bootc-compatible Containerfile that reproduces the layered package set
- A native ostree compose that replaces the stock Silverblue base
- Continued rpm-ostree layering with bootc as an opt-in update mechanism

**Milestones to define before starting:**

- Secure Boot and TPM2 strategy for a custom image (custom keys vs. Fedora shim)
- Persistent host state strategy in a container-image model
- Migration path from existing rpm-ostree deployments
- Rollback strategy with the new image mechanism
