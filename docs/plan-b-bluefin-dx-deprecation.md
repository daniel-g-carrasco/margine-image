# Plan B — Bluefin DX deprecation contingency

> **Status:** Contingency plan. Not active. `Containerfile` still
> uses `FROM ghcr.io/ublue-os/bluefin-dx:stable`. This document and the
> sibling `Containerfile.plan-b-from-bluefin` exist so that, if/when the
> Bluefin team deprecates the -dx variant, Margine can switch tracks in
> a single PR without an emergency redesign.

## Why

The Bluefin team has [publicly discussed](https://github.com/ublue-os/bluefin/discussions/4607)
(Spring 2026 roadmap blog + Discussion #4607) removing the `bluefin-dx`
variant in favor of installing developer tooling on-demand via
[Brew](https://docs.projectbluefin.io/brew/). The most recent
maintainer comment is *"we haven't even thought about migration yet, no
changes any time soon"* — but the direction is clear: smaller bases,
opt-in tools.

Margine inherits the full `bluefin-dx` stack (libvirt, qemu-kvm,
virt-manager, swtpm, edk2-ovmf, distrobox, podman-compose, VS Code,
etc.) for free today. If that disappears upstream:
- `Containerfile` `FROM` fails outright at the next nightly build.
- Margine has to either layer those packages itself or move to a
  "minimal base + opt-in" model.

This Plan B picks the **layer the packages ourselves** option, scoped
to the dev tools that Margine actually expects to be present (used by
Margine's own runbooks + the GNOME-side dev experience for the target
audience).

## What Plan B contains

`Containerfile.plan-b-from-bluefin` is a parallel Containerfile that:

1. `FROM ghcr.io/ublue-os/bluefin:stable` (no `-dx`).
2. Adds, in a single RUN, the dev stack RPMs that `bluefin-dx`
   currently provides and that Margine relies on:
   - libvirt + libvirt-daemon-kvm + libvirt-client (VM management)
   - virt-manager + virt-viewer (GUI)
   - qemu-kvm + qemu-system-x86 (hypervisor)
   - edk2-ovmf (UEFI firmware for VMs)
   - swtpm + swtpm-tools (virtual TPM for VMs)
   - distrobox (per-distro toolboxes)
   - podman-compose (compose syntax for podman)
3. `systemctl enable libvirtd.service` (matching `bluefin-dx` behaviour).
4. Then the SAME three RUN steps as `Containerfile`:
   - `custom-kernel/install.sh` (CachyOS kernel swap + MOK signing)
   - `build.sh` (Margine deltas)
   - `build-margine-extensions.sh` (GNOME extensions baked)
5. `bootc container lint`.

## What Plan B intentionally DROPS

- **VS Code from the Microsoft RPM repo.** Bluefin DX preinstalls VS
  Code via a layer + Microsoft's signed repo. Plan B follows the
  upstream Bluefin team's stated direction: VS Code, JetBrains IDEs,
  and other "personal favourite IDE" choices go via `brew install`
  on-demand. Same UX users will encounter on stock Bluefin from
  whichever quarter the Plan B becomes the live Containerfile.
- **User-specific runtimes** (golang, rustup, node, sdkman, sdkman-java)
  also stay outside the image. The composable rule is: anything a
  single user can install in $HOME stays out of /usr.

## When to flip the switch

Activate Plan B when any of these become true:

1. `ghcr.io/ublue-os/bluefin-dx:stable` returns 404 / "manifest not found"
   for ≥ 7 days. Watched indirectly via the nightly `build.yml` cron
   (Sunday 04:00 UTC) — two consecutive Sundays of pull failure on
   the `bluefin-dx` tag is the heuristic.
2. The Bluefin team announces deprecation with a sunset date >= 30
   days out. Same `scripts/check-upstreams.sh` monthly cron in
   `margine-fedora-atomic` will surface the announcement via the
   upstream-review tracking issue.
3. A `bluefin-dx`-shipped package is removed from upstream and Margine
   relies on it for a SPECIFIC user-visible behaviour (e.g. virt-manager
   GUI). At that point Plan B is the lower-friction fix vs piecewise
   layering on top of the broken DX base.

## Migration procedure (when the switch becomes warranted)

1. **Read** `Containerfile.plan-b-from-bluefin` — confirm the dev RPM
   list still matches what's expected of Margine. Update if upstream
   Bluefin DX has shipped new pieces since this file was written.
2. **Dispatch** a `workflow_dispatch` Build of `build.yml` with a
   one-liner override that points at the plan-B Containerfile. Easiest:
   open a temporary PR that swaps the `--file ./Containerfile` flag in
   `build.yml`'s build step. CI builds + rechunks + smoke-boots.
3. **Smoke-boot QEMU success required.** This is the gate. If the new
   base + layered dev stack fails to reach `multi-user.target`, debug
   the smoke-boot log; do not promote.
4. **Promote** by merging the swap PR. From that PR forward,
   `Containerfile` IS `Containerfile.plan-b-from-bluefin` content (or
   we delete the original and keep the plan-B as the canonical name —
   organizational preference).
5. **Communicate** in the next CHANGELOG entry. Users rebasing from
   `margine:stable` keep working — the OCI image digest changes but
   the user-visible behaviour stays the same.

## Reference

- Audit 2026-06-05 §6.13 — "bluefin-dx may go away"
- Audit 2026-06-05 §8 recommendation #20
- [ublue-os/bluefin Discussion #4607](https://github.com/ublue-os/bluefin/discussions/4607)
- [Bluefin Spring 2026 roadmap](https://docs.projectbluefin.io/blog/bluefin-spring-2026/)
