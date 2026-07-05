# ADR 0006 — Kernel: stay on `kernel-cachyos` (bieszczaders COPR), not OGC, not ublue-akmods

**Date:** 2026-06-05
**Status:** Accepted and shipping. `margine-image` installs `kernel-cachyos` +
`kernel-cachyos-core` + `kernel-cachyos-modules` + `kernel-cachyos-devel-matched`
from `copr:bieszczaders/kernel-cachyos` and MOK-signs every binary at image-build
time. The corresponding spec entry is `kernel:` in
[`declarations/margine-atomic.yaml`](../../declarations/margine-atomic.yaml).

## Context

Until June 2026 the kernel-choice question on the Margine side was implicit:
"Margine uses CachyOS because CachyOS is fast." That was true at install time
(phase-0 lab) and remained true through the pivot to a bootc image
([ADR 0005](0005-base-on-bluefin-dx.md)). What was *not* on record was a
deliberate comparison against the other viable options that exist on a
Fedora-Atomic-DX base in 2026.

Two events forced the comparison:

1. **The Open Gaming Collective (OGC) formed in January 2026** and published a
   shared kernel — [`OpenGamingCollective/kernel-packages`](https://github.com/OpenGamingCollective/kernel-packages),
   built on top of [`OpenGamingCollective/linux`](https://github.com/OpenGamingCollective/linux)
   (a stable-tree mirror). Eight gaming/handheld distros adopted it: **Bazzite,
   ChimeraOS, Nobara, Playtron, PikaOS, Fyra/Ultramarine, ShadowBlip, ASUS
   Linux**. Bazzite specifically migrated off its own fork
   ([`hhd-dev/kernel-bazzite`](https://github.com/hhd-dev/kernel-bazzite),
   archived 2026-05-01). The charter is "upstream-first": every patch must
   have a path to mainline; no eternal out-of-tree carries. OGC is the
   current *gaming-stability consensus* on Fedora-derivative bootc desktops.

2. **The full Margine stack audit** ([2026-06-05](../audits/2026-06-05-margine-stack-audit.md))
   flagged the lack of a written decision as a risk in itself: the audit
   reviewer (and any future contributor) could not tell whether the kernel
   choice was a deliberate trade-off or inertia. ADR pending.

Concurrent context: **CachyOS publicly skipped joining OGC**. Peter Jung
(CachyOS lead) cited "bureaucracy slowing releases" and limited value-add for
their use case. By March 2026 CachyOS sat at **#1 on the Steam Linux survey
at 21.1%** of users; Bazzite was #4 at 9.5%. The decision to stay outside
OGC paid off for CachyOS in market share — relevant background for whether
Margine should follow Bazzite into OGC or follow CachyOS's "stay independent"
direction (or do something else).

## Options considered

### Option A — Stay on `kernel-cachyos` (bieszczaders COPR) — **decision**

What ships: `kernel-cachyos` (mainline CachyOS, currently 7.0.x) from the
`bieszczaders/kernel-cachyos` Fedora COPR. Source is the upstream CachyOS
patch set repackaged for Fedora by a single Fedora packager (`bieszczaders`,
unaffiliated with the CachyOS team itself but a long-running, reliable
maintainer).

### Option B — Adopt the OGC kernel

What would ship: `kernel-packages` from OGC, equivalent to Bluefin/Bazzite's
chosen kernel. KERNEL_FLAVOR=ogc convention; build via the akmods OCI image
the way Bazzite does (`ghcr.io/ublue-os/akmods:ogc-${FEDORA}-${KERNEL}`).

### Option C — Stay on Bluefin's own signed kernel (`ublue-akmods`)

What would ship: the same kernel Bluefin DX itself ships. Removes the whole
`build_files/custom-kernel/install.sh` machinery (~420 lines, plus MOK
secrets management in CI). Minimal delta from `bluefin-dx:stable`.

## Decision matrix

| Dimension | A (CachyOS / status quo) | B (OGC) | C (Bluefin ublue-akmods) |
|---|---|---|---|
| **BORE scheduler builtin** | ✅ `CONFIG_SCHED_BORE=y` upstream-included | ❌ BORE is upstream Linux 6.13+ but as opt-in; OGC stable-tree config does not enable it by default | ❌ Same as B |
| **ThinLTO build** | ✅ whole-kernel ThinLTO link; 3-5% cache-locality win on mixed workloads | ❌ stable-tree config, no LTO | ❌ no LTO |
| **CONFIG_HZ** | ✅ `1000` (tickless) — finest granularity for low-latency audio + frame pacing | ❌ `300` (typical Fedora/OGC) | ❌ `300` |
| **I/O scheduler tuning** | ✅ BFQ tuned for NVMe-on-laptop, MQ-deadline elsewhere | ➖ Fedora defaults | ➖ Fedora defaults |
| **handheld HID drivers** | ➖ available but not the focus | ✅ ROG Ally, Legion GO, MSI Claw, Ayaneo, OneXPlayer, GPD Win, Steam Deck — all in tree | ❌ |
| **NTSYNC** | ➖ available on opt-in builds | ✅ `NTSYNC=m` default | ❌ |
| **gyro IIO triggers** | ➖ | ✅ | ❌ |
| **scx-scheds upstream alignment** | ✅ same COPR maintainer (`bieszczaders/kernel-cachyos-addons`) — kernel and scx-scheds released as a pair, no version drift | ➖ via separate packaging | ➖ via separate packaging |
| **Source CI / maintainer count** | ❌ single Fedora packager (`bieszczaders`); upstream CachyOS team is small | ✅ 8-distro shared CI, charter governance | ✅ Bluefin team + Universal Blue community |
| **Patch trajectory** | ➖ CachyOS = "we ship what works now, upstream when convenient" | ✅ upstream-first charter; eternal out-of-tree carries discouraged | ✅ stock Fedora trajectory |
| **Nvidia prebuilt** | ❌ removed 2026-02-23; users source from RPMFusion / Negativo17 | ➖ via akmods | ✅ via ublue-akmods |
| **Steam market share** | ✅ CachyOS #1 (21.1%, March 2026) | ➖ Bazzite #4 (9.5%) | ➖ Bluefin not specifically broken out |
| **Build pipeline cost** | ❌ ~420 LOC custom-kernel/install.sh + MOK key in CI secrets | ➖ adopt akmods OCI pull pattern | ✅ inherit from `bluefin-dx:stable` — no custom-kernel step |

## Decision

**Option A — keep `kernel-cachyos` from `bieszczaders/kernel-cachyos` COPR.**

Three reasons, in order of weight:

### 1. Measurable performance for Margine's actual workload

Margine's stated identity (Bomb-proof immutable Linux desktop, **with a
curated creator toolkit ready from minute one**) is creator-first, not
gaming-first. The first-five-minute apps on a fresh Margine install are:

- Reaper (DAW, latency-critical, real-time audio threads under load)
- EasyEffects (system-wide PipeWire DSP graph)
- Audacity, Apostrophe, Pinta, Blanket (interactive, GUI-light)

…and *only then* the heavy creator-pros (GIMP, Inkscape, darktable, OBS)
that arrive via `flatpak-preinstall.service` during the user's first
session.

For that workload mix — interactive UI mixed with real-time audio mixed
with background download — **BORE** beats CFS/EEVDF and certainly beats a
stock stable-tree scheduler, and **CONFIG_HZ=1000** halves the worst-case
audio jitter compared to `HZ=300`. ThinLTO adds another 3-5% across the
board. None of these wins is available on OGC; all are available on
`kernel-cachyos` without further configuration.

The benchmark math says, for a creator desktop, OGC would be a
**measurable regression** vs the status quo, not a neutral swap.

### 2. Project identity mismatch with OGC's gaming-first charter

The OGC charter is explicitly oriented to gaming + handheld. The
8 consumer distros are gaming-first (Bazzite, Nobara, ChimeraOS, Playtron,
PikaOS, ShadowBlip), handheld-first (ASUS Linux), or general-purpose
distros adding a gaming pillar (Fyra/Ultramarine). None of them is
*creator-first*. The patches OGC carries (handheld HID drivers, NTSYNC,
gyro triggers) provide ~zero benefit to Margine's target hardware
(Framework 13 AMD 7640U + Intel iGPU laptops, no handheld controllers,
no gyro).

Joining OGC would put Margine on a kernel trajectory governed by
priorities that don't match its own. The likely outcome over 2-3 years
is that Margine's specific asks (low-latency audio defaults, ThinLTO
acceptance, BORE-enabled config) lose votes against handheld asks.

### 3. CachyOS's market position validates "outside OGC" as a defensible track

The strongest counter-argument to staying outside OGC was the worry that
"the rest of the ecosystem is moving to OGC; staying on CachyOS leaves
Margine alone in a corner." CachyOS's March 2026 Steam survey position
(#1, 21.1%, ahead of Bazzite, Pop!_OS, Manjaro, every Ubuntu, and Mint)
defuses that worry: CachyOS is not "alone in a corner", it is the most
popular Linux distro by active gaming users. Margine inheriting from that
upstream is the *mainstream* trajectory by user count, even if it's a
non-OGC trajectory by maintainer count.

## Accepted risks + mitigations

| Risk | Severity | Mitigation today | Re-review trigger |
|---|---|---|---|
| `bieszczaders` COPR goes silent (single maintainer) | High impact, low probability per ~3-year track record | `scripts/check-upstreams.sh` already watches `bieszczaders/kernel-cachyos` activity; ADR re-evaluation triggers below codify the "what then" | No new build in COPR for **>30 days** with kernel/Fedora releases in flight |
| CachyOS upstream pivots in a direction Margine can't follow (e.g. Arch-only patches) | Medium | Margine's `custom-kernel/install.sh` is bounded surface area — replaceable to OGC or ublue-akmods in a single ADR cycle | Major CachyOS architectural change that breaks Fedora packageability |
| Nvidia users (post-2026-02-23 prebuilt removal) | Low for Margine (target = AMD + Intel) | Documented in `docs/05-known-risks.md`; user-side: RPMFusion or Negativo17 | Margine ever ships an Nvidia variant |
| COPR transient flakiness | Low | Retry loop already in `custom-kernel/install.sh` (5 attempts, exponential backoff) — empirically observed and handled | N/A — known-good |
| BORE/ThinLTO config regression upstream CachyOS | Low | Pinned at install time per build; smoke-boot gate catches any regression that breaks boot. Behavioral regressions (perf, not correctness) would surface in user reports | Smoke-boot failure rate spikes |

## Re-review triggers

Re-open this ADR when any of the following occur:

1. **`bieszczaders/kernel-cachyos` shows no new build for 30 days** while
   upstream CachyOS or Fedora has shipped a kernel release in that window.
   The monthly cron driven by `scripts/check-upstreams.sh` (already in
   the TODO list per
   [`project_todo_check_upstreams_cron`](../../../proxmox-pve1/...))
   should open a tracking issue automatically.
2. **CachyOS publicly changes its packaging direction** away from
   Fedora-compatible RPM (e.g. mandatory Arch-specific dependencies, drop
   of glibc compat).
3. **OGC kernel adopts BORE + ThinLTO + HZ=1000** in its default config.
   At that point the performance argument for staying separate collapses,
   and the shared-CI argument wins.
4. **Bluefin DX itself moves to OGC or removes `ublue-akmods` kernel**.
   That would force a downstream conversation regardless.
5. **A specific Margine user need** that OGC's patches address (e.g. ASUS
   ROG Ally support, NTSYNC for a Windows app) becomes part of the
   shipping ICP.

## Consequences

- Margine continues to depend on a single-maintainer Fedora COPR for the
  most security-critical part of the image. This is *the* operational
  risk to keep visible.
- `scripts/check-upstreams.sh` watchlist is extended with
  `OpenGamingCollective/kernel-packages` so we know when OGC moves in
  ways that affect re-review trigger #3 above.
- The 420-LOC `build_files/custom-kernel/install.sh` machinery stays in
  the build pipeline — including the MOK secret in CI secrets, the dnf
  retry loops, the akmods patching, and the manual `bootc container lint`
  pass. Any refactor of that file should preserve the COPR retry pattern.
- The `kernel:` section of `declarations/margine-atomic.yaml` already
  documents the choice; this ADR is the why.
- No change to user-facing behaviour or documentation.

## References

- [`declarations/margine-atomic.yaml` `kernel:` section](../../declarations/margine-atomic.yaml#L191)
- [`build_files/custom-kernel/install.sh`](https://github.com/daniel-g-carrasco/margine-image/blob/main/build_files/custom-kernel/install.sh)
- [`docs/03-cachyos-kernel.md`](../03-cachyos-kernel.md) — operational guide
  for the CachyOS kernel choice (pre-bootc-image era; still relevant for
  the *why CachyOS at all* argument)
- [`docs/upstream-inspirations.md`](../upstream-inspirations.md) —
  Origami Linux entry covers our derivation of the `custom-kernel/install.sh`
  script
- [`docs/audits/2026-06-05-margine-stack-audit.md`](../audits/2026-06-05-margine-stack-audit.md)
  §6.8 — the audit finding that motivated this ADR
- [Open Gaming Collective announcement](https://blog.fyralabs.com/open-gaming-collective-announcement/)
  (Fyra Labs, 2026-01-28)
- [Open Gaming Collective formed](https://www.gamingonlinux.com/2026/01/open-gaming-collective-ogc-formed-to-push-linux-gaming-even-further/)
  (GamingOnLinux, 2026-01)
- [CachyOS skipped Open Gaming Initiative, now #1 on ProtonDB](https://www.xda-developers.com/cachyos-skipped-open-gaming-initiative-gamers-rewarded-making-top-linux-distro-steam/)
  (XDA Developers, March 2026)
- [`hhd-dev/kernel-bazzite` archived 2026-05-01](https://github.com/hhd-dev/kernel-bazzite)
- [`copr:bieszczaders/kernel-cachyos`](https://copr.fedorainfracloud.org/coprs/bieszczaders/kernel-cachyos/)
- [`copr:bieszczaders/kernel-cachyos-addons`](https://copr.fedorainfracloud.org/coprs/bieszczaders/kernel-cachyos-addons/)
- [BORE scheduler upstream merge (Linux 6.13)](https://github.com/firelzrd/bore-scheduler)
