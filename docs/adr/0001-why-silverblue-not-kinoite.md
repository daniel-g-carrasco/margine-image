# ADR 0001 — Why Fedora Silverblue and not Kinoite

**Date:** 2026-05-22
**Status:** Accepted

## Context

The first Margine Fedora Atomic experiment needed to choose a starting variant
of Fedora Atomic Desktop. The main candidates were:

- **Fedora Silverblue** (GNOME) — the reference Fedora Atomic variant
- **Fedora Kinoite** (KDE Plasma) — the Plasma variant of Fedora Atomic
- **Universal Blue / Bazzite** (gaming-focused, GNOME or KDE) — a pre-configured
  image with opinionated defaults
- **Fedora CoreOS** — a server/container-focused Atomic variant

The question was which base to use for phase 1 of the lab.

## Decision

Use **Fedora Silverblue** with the stock GNOME desktop.

## Rationale

**Silverblue is the reference Atomic variant.** The Fedora Atomic Desktop
project treats Silverblue as its canonical GNOME expression. Documentation,
community knowledge, and Fedora upstream validation concentrate here. Starting
here means any issue is likely to have documented precedent.

**GNOME is the target for Margine's personal layer.** The personal layer plan
(fonts, home layout, XDG dirs, dconf settings) maps naturally to GNOME's
settings model. Carrying that intent across from Margine Personal requires
fewer design decisions on a GNOME base than on a KDE base.

**Bazzite and Universal Blue are useful references, not starting points.**
They include opinionated defaults (Steam Gaming Mode, custom kernels, specific
Flatpak sets) that would import policy Margine has not yet validated. Starting
from stock Silverblue means every addition is a deliberate choice.

**Kinoite is not wrong — it is a later question.** KDE Plasma's settings model
is different from GNOME's. Evaluating it makes sense after the GNOME baseline
is understood, not before.

**CoreOS is out of scope.** CoreOS targets server and container workloads, not
interactive desktop use. Its tooling assumes container-native workflows from the
start, which would complicate phase 1 desktop validation.

## Consequences

- GNOME is the desktop for all phase 1 lab work.
- Kinoite is an open possibility for a later phase or a parallel product.
- Bazzite remains a reference for gaming runtime design, not a rebase target.
- All GNOME-specific dconf and settings knowledge from phase 1 transfers
  directly to the personal layer design.
