# ADR 0002 — GNOME stock in phase 1, Hyprland deferred

**Date:** 2026-05-22
**Status:** Accepted

## Context

Margine Personal (the existing Arch/CachyOS product) uses Hyprland as its
primary desktop. The Fedora Atomic experiment could attempt to reproduce that
choice — installing Hyprland on Silverblue — or it could use GNOME stock for
phase 1 and evaluate Hyprland later.

Installing Hyprland on Fedora Silverblue is possible but involves:

- Installing Hyprland and dependencies via rpm-ostree layering or a
  third-party COPR, both of which are unvalidated surfaces
- Reproducing configuration (waybar, hyprlock, mako, walker, etc.) that
  currently lives in Arch-specific tooling
- Rebuilding a full Wayland compositor setup before the base Fedora Atomic
  model (ostree, Btrfs, Secure Boot, TPM2, Flatpak) has been validated

## Decision

Use **GNOME stock** for all phase 1 work. Do not install Hyprland, Waybar,
Walker, or any Wayland compositor configuration during phase 1.

## Rationale

**Phase 1 must validate the base model, not the desktop layer.** The critical
unknowns are rpm-ostree mechanics, Btrfs layout, Secure Boot, TPM2 enrollment,
and Flatpak/toolbox channels. Adding a non-default compositor to that surface
introduces unnecessary variables.

**GNOME is what Silverblue ships.** Using stock GNOME means the entire Fedora
QA chain applies. Replacing it before understanding the base model means any
problem might come from the replacement.

**Hyprland on Atomic needs its own validated path.** On Arch, Hyprland is
installed from pacman or AUR. On Fedora Atomic, the correct delivery mechanism
(rpm-ostree COPR, toolbox session, native image) is an open question that
requires its own evaluation.

**Waybar, Walker, Fuzzel, and Lua configuration are Arch artifacts.** They
exist in Margine Personal because they fit the Arch tooling model. Importing
them without adaptation would silently import Arch assumptions into the Atomic
branch.

**The personal layer maps well to GNOME first.** Fonts, XDG dirs, folder
metadata, and dconf settings can all be validated against GNOME before
Hyprland is considered.

## Consequences

- GNOME stock is the only desktop for phase 1 lab work.
- Hyprland evaluation is a future decision, not a phase 1 goal.
- Waybar, Walker, Fuzzel, and Lua configuration are explicitly out of scope
  for this repository's phase 1.
- The personal layer (docs/08) targets GNOME settings and dconf.
- A future phase or product could evaluate Hyprland on Atomic with a
  documented delivery mechanism.
