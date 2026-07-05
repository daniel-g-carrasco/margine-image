# ADR 0004 — rpm-ostree owns the base OS boundary

**Date:** 2026-05-22
**Status:** Superseded by [ADR 0005](0005-base-on-bluefin-dx.md) (the principle stands; the implementation is now Bluefin's `uupd`, not our own `update-all`)

> **Why this ADR is preserved.** The principle this ADR established — that the
> base-OS update step must own pre/post validation, reboot judgment, and
> rollback, and that no generic tool (Topgrade) should run in its place —
> remains correct. The pivot to Bluefin DX (ADR 0005) and then to a published
> bootc image realized this principle through a different artifact: Bluefin's
> `uupd.timer` is the canonical orchestrator, with `bootc upgrade` as the
> base-OS step. Margine's own `scripts/update-all` and `config/topgrade.toml`
> were deleted as duplication. The ADR text below is the original rationale
> and is kept as the historical reasoning that motivated the pivot.

---

## Context

Margine uses Topgrade as a convenience tool for updating multiple software
channels (Flatpak, toolbox, user-installed packages). Topgrade can also update
the base OS if configured to do so. On Fedora Atomic systems, Topgrade includes
an `rpm_ostree` step that runs `rpm-ostree upgrade`.

If Topgrade owns the rpm-ostree upgrade step, it also owns the pre/post
validation, reboot judgment, and rollback decision. The concern is that
Topgrade's generic update model does not account for:

- Pre-update validators that must block on failure
- Post-update validators that prove the deployment is sound
- Reboot scheduling after rpm-ostree upgrades
- Rollback triggers when post-update checks fail
- The hard boundary between what rpm-ostree owns and what Flatpak/toolbox own

The alternative is to build a dedicated orchestrator (`scripts/update-all`)
that owns the rpm-ostree step and uses Topgrade only for accessory channels.

## Decision

**`scripts/update-all` owns the base OS update boundary.** Topgrade is
configured to run only as an accessory updater and is explicitly blocked from
running rpm-ostree, bootc, firmware, or Secure Boot/TPM2 operations.

The Topgrade profile in `config/topgrade.toml` disables:

- `system` (rpm-ostree)
- `firmware` (fwupd)
- `rpm_ostree`
- `bootc`

`scripts/update-all` runs in this order:

1. Pre-flight checks (disk space, network, rpm-ostree status)
2. Hard pre-update validators (stop if they fail)
3. Soft pre-update validators (warn but continue)
4. Pre-update diagnostics
5. `rpm-ostree upgrade`
6. Topgrade for accessory channels (Flatpak fallback if Topgrade unavailable)
7. Hard post-update validators
8. Soft post-update validators
9. Post-update diagnostics
10. Reboot guidance

## Rationale

**rpm-ostree upgrades are not generic package installs.** They replace the
entire OS deployment. A failed upgrade does not leave a partially updated
system; it leaves an unapplied pending deployment. A successful upgrade does
nothing until reboot. Topgrade's generic "run the upgrade command" model does
not express this correctly.

**Pre-update validation is a hard gate.** If `validate-atomic-layout` fails
before an upgrade, the system may be in a state that makes the upgrade unsafe
(modified `/usr` files, wrong ostree status, etc.). Topgrade has no mechanism
to enforce this.

**Post-update validation must run in the new deployment.** After reboot into
the new deployment, validators must re-run to confirm the deployment is sound.
This is not part of any Topgrade update step.

**Rollback must be an explicit decision.** If post-update checks fail, the
correct response is `rpm-ostree rollback`. Topgrade has no rollback capability.

**Topgrade is useful for accessories.** Flatpak updates, toolbox image updates,
and user-installed tooling (rustup, etc.) are good Topgrade candidates. They
can fail without breaking the base system and do not require pre/post
validation gates.

## Consequences

- `config/topgrade.toml` permanently disables the steps listed above.
- `scripts/update-all` is the canonical way to update a Margine Fedora Atomic
  system.
- Topgrade can be run independently for accessory-only updates, but not as a
  replacement for `scripts/update-all`.
- `bootc` is deferred to phase 4 and is not a Topgrade concern in any phase.
- Firmware updates remain manual, following a separate runbook, because they
  require hardware-specific judgment.
