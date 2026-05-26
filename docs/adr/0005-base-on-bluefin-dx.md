# ADR 0005 — Base Margine on Bluefin DX (Fedora track), not on stock Silverblue

**Date:** 2026-05-25 (amended 2026-05-26)
**Status:** Accepted and shipping. Margine is published as a bootc image
(`ghcr.io/daniel-g-carrasco/margine:stable`) built by GitHub Actions from
[`margine-image`](https://github.com/daniel-g-carrasco/margine-image),
which uses Bluefin DX as the `FROM`. The original "Silverblue + layered
baseline" lab path (`scripts/apply-host-layer`, `host_packages.baseline`)
and the interim "Bluefin DX rebase + adapter" path
(`scripts/apply-margine-on-bluefin`) remain in the repo as fallbacks for
users who do not want the published image, but the shipping deployment is
the bootc image rebase.

**Amendment 2026-05-26.** The `kitty` delta listed below was dropped:
Margine now keeps Bluefin's Ptyxis as the default terminal. The published
image installs no terminal-related layer. See the strike-through in the
delta table.

## Context

Phase 1 of Margine started from "Fedora Silverblue stock + a declarative
Margine layer on top" (`scripts/apply-host-layer` + the
`host_packages.baseline` section of `declarations/margine-atomic.yaml`).
That layer grew over the lab sessions to ~130 packages and ~70 dconf
settings, in three batches:

1. RPMFusion + freeworld codec replacement (8 packages override-removed,
   3 added).
2. Generic baseline (Mesa diagnostics, audio, virt stack, hardware
   diagnostics, GNOME tools, curated fonts, creative apps).
3. Aesthetic polish ported from Bluefin's
   `projectbluefin/common` →
   `usr/share/glib-2.0/schemas/zz0-bluefin-modifications.gschema.override`:
   blur-my-shell config, dash-to-dock config (transparency DYNAMIC,
   dock-fixed, opacity 0.8, running-indicator-style=DOTS), hot-corners
   off, font-antialiasing=rgba, button-layout=":minimize,maximize,close",
   center-new-windows, sort-directories-first.

When we audited the Margine baseline against `ublue-os/bluefin` and
`projectbluefin/common` on GitHub, the answer was unambiguous: the
Margine baseline is **a hand-rolled clone of ~70% of Bluefin**. Almost
every decision in batch 1 and batch 3 above is a literal copy of what
Bluefin's gschema override and `build_files/base/04-packages.sh` do.

The "Margine-specific" decisions reduce to five:

| Diff | Direction |
| --- | --- |
| Tiling Shell user-installed | Margine **adds** (Bluefin has no tiling extension) |
| Kernel CachyOS via COPR | Margine **adds** (Bluefin uses its own signed kernel from `ublue-akmods`) |
| ~~`kitty` as default terminal~~ | ~~Margine replaces~~ — **dropped 2026-05-26**; Margine keeps Bluefin's Ptyxis. (Original delta is preserved here for traceability; the image, YAML keybindings, and adapter scripts no longer reference kitty.) |
| Bluefin branding extensions (bazaar-integration, gradia-integration, logomenu) | Margine **disables** (the packages can stay) |
| Hyprland-style keybindings (workspace binds, custom launchers, Tiling Shell binds, default applications) | Margine **adds** via `configure-gnome-keybindings` and `configure-gnome-{appearance,extensions,app-folders,default-applications}` |

Maintaining a hand-rolled clone of 130 packages and 70 settings for the
sake of five real differences is a maintenance burden out of proportion
to the actual customisation value:

- every Mesa / GStreamer / RPMFusion version drift we discover, Bluefin
  has already discovered weeks earlier and fixed in their CI;
- every GNOME minor release breaks extensions in different ways
  (search-light EGO v42 vs upstream v101, Forge maintenance status,
  workspaces-bar abandoned at GNOME 42), and Bluefin pins git submodules
  to the right versions for the shell they ship;
- our `apply-host-layer` is fragile because rpm-ostree's depsolve
  semantics bite hard (override-remove for ffmpeg-libs split, "already
  requested" re-run guards, `--allow-inactive` for "already provided"
  cases) — Bluefin bakes the same packages into an OCI image where
  these distinctions don't apply at install time.

## Why Bluefin DX (Fedora track), not Bluefin LTS

Bluefin ships two channels on the Universal Blue release page:

| Channel | Base | GNOME | Mesa | Kernel | Notes |
| --- | --- | --- | --- | --- | --- |
| **Bluefin** (Recommended) | Fedora 44 | 50.1 | 26.0.6 | 6.19 | the "modern desktop at leading edge" track |
| **Bluefin LTS** | **CentOS Stream 10** | 49.5 | 25.2.7 | 6.12 (RHEL LTS) | "enterprise-grade foundation"; opt-in HWE kernel from Fedora |

Bluefin LTS is **not** Fedora N-1. It is built on CentOS Stream 10
(EPEL10, RHEL-derived kernel, dnf4 instead of dnf5). For Margine that
means three of our base decisions break or degrade:

1. **CachyOS COPR is Fedora-only**. The COPR `bieszczaders/kernel-cachyos`
   builds for Fedora 43/44, not CentOS Stream / EPEL10. We can't run the
   chosen kernel on LTS without rebuilding it ourselves.
2. **RPMFusion freeworld coverage on EL10 is far thinner than on Fedora**
   and lags behind by months. The codec story we already validated would
   need re-validation on a smaller package set.
3. **Toolbox / dnf assumptions**: many of our scripts use Fedora-style
   `dnf5`, `fedora-toolbox`, package names that have CentOS Stream
   equivalents but with different names / versions.

The "enterprise-grade stability" of LTS is real value, but it solves a
problem Margine doesn't have. Margine controls everything itself: the
kernel via CachyOS, the desktop via dconf scripts, the daily tools via
Flatpak and toolbox. A stable Fedora base under a strict declarative
layer is already stable enough. Trading away CachyOS + dnf5 + Fedora
RPMFusion to get RHEL stability would lose more than it gains.

We pick **Bluefin DX (Fedora 44 track)** going forward.

## Why DX, not the base Bluefin image

Both Bluefin and Bluefin DX ship the same desktop polish (codec,
mesa-freeworld, blur-my-shell, dash-to-dock, gsconnect, AppIndicator).
DX adds on top of base:

- virtualization stack (libvirt, libvirt-nss, qemu-kvm, virt-manager,
  virt-viewer, edk2-ovmf, swtpm, dnsmasq, qemu-* helpers, libvirt
  storage drivers) — **the exact set the Margine baseline had layered**;
- containers tooling: podman-compose, podman-machine, podman-tui,
  distrobox, Docker CE (daemon disabled by default);
- kernel debugging: bcc, bpftrace, bpftop, sysprof, trace-cmd;
- developer tools: VS Code (Microsoft repo), Cockpit (web admin
  modules — service disabled by default), Tailscale (service disabled
  by default), android-tools (adb/fastboot), virt-v2v, incus, lxc.

Going with base Bluefin would force Margine to layer back virt-manager
+ libvirt + qemu + edk2-ovmf + swtpm + dnsmasq — exactly what the old
`apply-host-layer` Step 3 was doing. That re-introduces the maintenance
class we are trying to eliminate.

The DX additions that we don't actively want (Docker daemon, Cockpit,
Tailscale, VS Code Microsoft) are present but with services disabled.
They consume ~500 MB of image size and zero runtime resources. Removing
them via `rpm-ostree override remove` is possible but adds maintenance
churn for almost no benefit. We accept the size cost.

## Decision

Margine deploys as **Bluefin DX (Fedora track) rebased + a small
Margine delta**:

```
rpm-ostree rebase ostree-unverified-registry:ghcr.io/ublue-os/bluefin-dx:stable
# reboot
scripts/apply-margine-on-bluefin --apply
# logout/login or reboot, depending on what changed
```

`scripts/apply-margine-on-bluefin` is the single Margine adapter. It:

1. layers `kernel-cachyos` from `copr:bieszczaders/kernel-cachyos` on
   top of Bluefin's base kernel (Bluefin's signed kernel is replaced via
   `rpm-ostree override remove kernel kernel-core ... --install
   kernel-cachyos`);
2. ~~layers `kitty` and registers it as the default terminal emulator~~ —
   dropped (see delta-table note above); Bluefin's Ptyxis stays as default;
3. disables Bluefin branding extensions
   (`bazaar-integration@kolunmi.github.io`,
   `gradia-integration@alexandervanhee.github.io`, `logomenu@aryan_k`)
   via `gnome-extensions disable`; the packages stay installed so the
   user can re-enable per session;
4. installs Tiling Shell from the EGO release matching the running
   GNOME Shell (reuses `scripts/install-user-extensions`);
5. applies the Hyprland-style keybindings, default applications, app
   folders, and Margine-flavoured tweaks via the existing
   `configure-gnome-{keybindings,extensions,app-folders,appearance,
   default-applications}` scripts.

The adapter targets the **user-state + a single rpm-ostree layer
operation** for the kernel. No more RPMFusion enablement, no more codec
override removes, no more 130-package Step 4. Bluefin's image already
has them.

The end-user choice between "Margine = Silverblue + apply-host-layer"
and "Margine = Bluefin DX + apply-margine-on-bluefin" remains
technically possible (the old script is preserved in the repo for
audit/learning), but Margine **ships and documents the Bluefin DX
rebase as the recommended path**.

## Consequences

### What this fixes

- **Maintenance**: stop tracking RPMFusion vs Fedora Mesa version skew
  ourselves; Bluefin's CI handles that 1-2 weeks faster than we can on
  Saturday afternoons.
- **Codec replacement fragility**: the ffmpeg-libs split / mesa-vdpau
  upstream removal / "already provided" / "already requested" loop
  goes away — Bluefin's image is cooked once, not per-deployment.
- **Extension version churn**: Bluefin pins git submodules to versions
  tested against the GNOME Shell they ship. The "search-light EGO is
  stuck at v42 while upstream is v101" problem on lab does not exist
  for them.
- **Onboarding new hardware**: a Framework 13 install is one rebase
  command plus one script, instead of a ~30-step lab procedure.
- **Phase 2 path**: becomes a ~50-line Containerfile that `FROM
  ghcr.io/ublue-os/bluefin-dx` plus the same 5 diffs, published via
  BlueBuild on `ghcr.io/daniel-g-carrasco/margine`. The pivot in phase
  1 makes phase 2 nearly free.

### What this gives up

- **Margine no longer owns the codec/driver/virt baseline.** If Bluefin
  removes codec X from their image, we lose it too unless we layer it
  back in `apply-margine-on-bluefin`. So far the alignment has been
  perfect, but it's a future risk to monitor.
- **Default applications outside our five overrides are Bluefin's.**
  Browser=Firefox (Bluefin) until our `configure-default-applications`
  swaps it to Zen. UI font, dock orientation, etc. all inherit from
  Bluefin's `zz0-bluefin-modifications` override unless we explicitly
  unset them — which we mostly don't want to anyway, since they're the
  values we were copying by hand.
- **Tied to Bluefin's release cadence and lifecycle decisions.** When
  Bluefin moves to Fedora 45, so do we (no big deal — we want recent
  Fedora). When Bluefin switches a default desktop component, we
  inherit that.
- **CachyOS kernel + Bluefin's image-signing model interaction is
  untested.** Bluefin signs the image they publish. Layering
  kernel-cachyos via rpm-ostree on top of a signed image works
  technically (same as on Silverblue) but the signature-verification
  story across upgrades needs to be validated in lab. This is the only
  technical risk that survives the pivot.

### What stays valid from phase 1 lab

- The **Btrfs nested-subvolume design** (`home/<user>/.cache`,
  `home/<user>/dev`, `home/<user>/scratch`, `@data` top-level) is a
  partitioning decision, base-image-agnostic. Bluefin doesn't dictate
  partitions.
- The **TPM2 PCR 0 + systemd-cryptenroll flow** survives kernel changes
  (we proved that crossing the Fedora-kernel/CachyOS-kernel boundary).
  It's a one-time post-install enrollment.
- The **home layout** (`~/data`, `~/dev`, `~/scratch`, XDG remapping,
  GTK bookmarks) and the `home-organization-template` repository are
  base-image-agnostic.
- The **declarative model** (`declarations/margine-atomic.yaml`) and
  the configure-* scripts (default-applications, app-folders,
  keybindings, appearance, extensions, install-user-extensions) all
  apply to either base. They are user-state.
- The **AI validation prompt** (`docs/13-ai-validation-prompt.md`) and
  the **expected behaviors doc** (`docs/14-expected-behaviors.md`)
  describe Silverblue/Atomic-side facts that Bluefin inherits.

### Migration story

Lab VMs running stock Silverblue + Margine layer can either:

a. **Rebase in place** to `ghcr.io/ublue-os/bluefin-dx:stable` via
   `rpm-ostree rebase`. The layered packages survive (they're on top of
   whatever base). The user then runs `apply-margine-on-bluefin
   --apply`, which removes the duplicates that Bluefin already provides
   and leaves only the 5 Margine diffs.

b. **Re-install from Bluefin ISO** and immediately run
   `apply-margine-on-bluefin --apply`. Cleaner state, no leftover
   override-removed packages.

For hardware installs, only (b) is supported.

## Phase 2 path: SHORTCUT to image-based via Origami's custom-kernel pattern

Phase 2 (`declarations.base.image_workflow.future_candidates: bootc`) was
originally projected as 1-2 weeks of CI/BlueBuild setup. After surveying
the existing ecosystem (Origami Linux, MorrOS, the Universal Blue
`image-template`), we realised the heavy work was already done:

- The Universal Blue
  [`image-template`](https://github.com/ublue-os/image-template) is the
  recommended starting point — Containerfile + GitHub Actions + cosign
  scaffolding ready to fork.
- Origami Linux's
  [`custom-kernel` module](https://gitlab.com/origami-linux/images)
  installs the CachyOS kernel from COPR, signs vmlinuz with `sbsign`,
  signs all modules with `sign-file`, and creates a `mok-enroll.service`
  that imports the MOK on first boot. Reusable as-is (with attribution),
  simplified for Margine's single-kernel-variant + no-Nvidia profile.
- MorrOS [`morros`](https://github.com/morrolinux/morros) demonstrates the
  pattern with a different desktop choice, validating that the recipe is
  approachable for individual maintainers.

Margine adopts the same pattern. Phase 2 is therefore not "future work"
but a **second active repo**:
[`daniel-g-carrasco/margine-image`](https://github.com/daniel-g-carrasco/margine-image)
(or whatever final name we publish), built nightly by GitHub Actions and
pushed to `ghcr.io/daniel-g-carrasco/margine:stable`.

**End-user install becomes:**

```sh
# On any vanilla Bluefin DX / Fedora Atomic install
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/daniel-g-carrasco/margine:stable
systemctl reboot
# On first boot: mok-enroll.service imports the Margine MOK; reboot
# again and select "Enroll MOK" in the bootloader.
# The CachyOS kernel now boots under Secure Boot.
```

No host rpm-ostree layering at runtime. Container-first across the board.

This **supersedes** the `apply-margine-on-bluefin` adapter that this ADR
originally proposed. The adapter is kept in the repo as a fallback for
users who do not want to rebase to the published image (they stay on
Bluefin DX upstream and let the adapter layer kernel-cachyos
themselves), but the recommended path is the image rebase.

The two repos divide as follows:

| Repo | Scope |
| --- | --- |
| `margine-fedora-atomic` (this one) | Declarative spec (`declarations/margine-atomic.yaml`), ADRs, lab docs, `configure-gnome-*` user-state helpers, validation scripts. The "what Margine is" repo. |
| `margine-image` | bootc image build: `Containerfile`, `build_files/custom-kernel/install.sh`, `build_files/build.sh`, GitHub Actions CI for build+sign+push. The "how Margine is produced" repo. |

The image repo fetches `configure-gnome-*` and
`declarations/margine-atomic.yaml` from this repo at build time, pinning
to a specific commit (set via `MARGINE_REF` env in the build, default
`main`). So a change in the declarative spec rolls out to a new image
build automatically.

## References

- Bluefin selection screenshot from the Universal Blue site (2026-05-25):
  Bluefin LTS = CentOS Stream 10, Bluefin = Fedora 44.
- `projectbluefin/common`
  `system_files/bluefin/usr/share/glib-2.0/schemas/zz0-bluefin-modifications.gschema.override`
  — source of the dconf settings we copied in batch 3.
- `ublue-os/bluefin` `build_files/base/04-packages.sh` and
  `build_files/dx/00-dx.sh` — source of the package set we replicated.
