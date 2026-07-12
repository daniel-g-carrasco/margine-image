# ADR 0009 — NVIDIA variant: CachyOS-native, MOK-signed kmod (build-time variant)

Status: **Accepted (experimental scaffold)** — 2026-06-15
Supersedes/relates: [0006](0006-kernel-cachyos-decision.md) (CachyOS kernel), [0003](0003-fedora-native-boot-security.md) (Secure Boot / MOK).

## Context

Margine builds `FROM ghcr.io/ublue-os/bluefin-dx:stable` (the **non**-NVIDIA DX
base) and its core identity is a **signed CachyOS/BORE kernel**: every module
and `vmlinuz` is signed at build time with the Margine MOK (see ADR 0003,
`build_files/custom-kernel/install.sh`). NVIDIA users currently have no
proprietary driver on Margine.

The hard tension: `ublue-os/akmods` and `bluefin-dx-nvidia` ship `akmod-nvidia`
**prebuilt and signed against the Fedora kernel and the ublue Secure Boot
key** — wrong kABI *and* wrong signature the moment Margine swaps in the
CachyOS kernel. And the BuildKit secret `MOK.key` is mounted **only** in the
kernel RUN, so nothing outside that layer (host, build.sh, a post-install
recipe) can sign a module with the Margine MOK.

A design workflow evaluated three approaches (CachyOS + in-kernel-layer akmod;
`bluefin-dx-nvidia` base dropping CachyOS; host-side opt-in layer) with an
adversarial boot/signing review. Verdict: **GO with mandatory fixes.**

## Decision

Ship a **build-time NVIDIA variant** that keeps the CachyOS kernel and builds
the NVIDIA kmod **inside the existing kernel RUN**, signed by the **same
Margine MOK**:

1. **Keep `FROM bluefin-dx:stable`** (unchanged base). Do **not** switch to
   `bluefin-dx-nvidia` (wrong kABI + wrong key).
2. **Build `akmod-nvidia-open` against `kernel-cachyos-devel-matched`** via the
   already-proven `akmods` flow (the `disable_akmodsbuild` /var patch +
   `akmods --force --kernels $KVER --kmod nvidia-open`, mirroring the
   v4l2loopback block). Source: **RPMFusion-nonfree** (already transiently
   enabled in `install.sh`).
3. Drop the `.ko` under `/usr/lib/modules/$KVER/extra/` **before** the existing
   `sign_kernel_modules()` loop, so it's signed by the **same MOK** that signs
   `vmlinuz`. **One key, one enrollment, Secure Boot stays ON.**
4. **`nvidia-open` is the default** (`NVIDIA_KMOD` build-arg): required for
   Blackwell+, preferred Turing+. A `nvidia` (proprietary, Maxwell..Ada) tag
   can follow later via the same arg.
5. **Variant toggle** = a `ENABLE_NVIDIA` build-arg (default `0`), wired through
   a `variant: [base, nvidia]` CI matrix. Same `margine` GHCR package, **`-nvidia`
   tag suffix** (`:stable-nvidia`) so status.json / cosign-by-digest /
   ghcr-cleanup keep working unchanged.

**Rejected — host-side opt-in layer:** it cannot sign with the Margine MOK
(key absent from the image by design → a second per-machine MOK + extra
MokManager dialog), has zero CI gating, and pushes a kernel-bump akmod rebuild
onto every user. It is a trap, not a convenience.

## Why this resolves the tension

The kmod is compiled against `kernel-cachyos-devel-matched` (correct kABI for
the CachyOS kernel) and signed with `MOK.key`/`MOK.pem` — the exact cert
`mok-enroll.service` already imports. Kernel and NVIDIA module share one key,
one kABI, one enrollment. NVIDIA is a strict **superset** of the kernel layer,
not a fork.

## Mandatory fixes (from the adversarial review — applied in the scaffold)

- **Version-lock userland to the kmod.** Install `akmod-$NVIDIA_KMOD` and
  `xorg-x11-drv-nvidia-cuda` in **one** dnf transaction so a mid-bump RPMFusion
  can't produce a userland/kmod driver-version mismatch.
- **Don't gate the build on a CN string match.** `modinfo -F signer` vs an
  `openssl … CN` `sed` is brittle and will false-fail a correct build. Verify
  the signature exists / compare cert **fingerprints**, and trust the signing
  loop.
- **Hard-fail**, never best-effort: a `margine-nvidia` image with no NVIDIA
  module must never ship (unlike the optional v4l2loopback block).
- **kargs**: `/usr/lib/bootc/kargs.d/30-margine-nvidia.toml` →
  `nvidia-drm.modeset=1` + blacklist nouveau; **dracut** drop-in to pull the
  (already-signed) nvidia modules into the initramfs.

## Consequences / risks (honest)

- **Genuinely novel.** No precedent for NVIDIA-against-a-CachyOS-kernel under
  bootc (ublue akmods is Fedora-kernel only). Budget **several** CI build
  iterations, not 1–3.
- **Schedule skew is a named upstream problem.** The CachyOS COPR itself
  dropped prebuilt NVIDIA (Feb 2026) over RPMFusion/Fedora/CachyOS release
  mismatch. Each CachyOS kernel bump may need an NVIDIA rebuild that can lag.
- **QEMU smoke-boot canNOT validate NVIDIA at runtime** (no GPU). Layer B only
  proves the image boots when NVIDIA is *absent*; a signed-but-failing module
  + `nvidia-drm.modeset=1` = **black screen on real NVIDIA hardware** that the
  gate won't catch. `:stable-nvidia` must be **validated on real NVIDIA
  hardware** before it is trusted. Margine's reference machine is AMD, so
  runtime validation needs a community/contributor NVIDIA box.

## Rollout

1. **Scaffold (this ADR):** the `ENABLE_NVIDIA`-gated block in
   `custom-kernel/install.sh` (default off — zero impact on base) + the
   Containerfile build-arg + an **experimental, manual-dispatch**
   `build-nvidia.yml` that builds+signs and pushes a test tag. No auto-promote.
2. **Make it build green in CI** (compiles + signs against CachyOS) — the
   achievable, verifiable milestone.
3. **Real-hardware runtime validation** (an NVIDIA contributor) → only then
   promote `:stable-nvidia`, wire the matrix into the main build/smoke/ISO, and
   advertise it.

## Update 2026-06-15 — precedent found (RakuOS), source revised

The "no precedent / genuinely novel" framing above was **wrong** — corrected here.

**[RakuOS](https://rakuos.org)** is a production distro with a near-identical
model to Margine: Fedora-atomic + **CachyOS kernel + bootc**, custom modules
**signed for Secure Boot** with its own key (MOK enroll on first boot, password
`rakuos` — the exact pattern Margine uses with `margine-os`), and it ships
**NVIDIA**. So NVIDIA-on-a-signed-CachyOS-kernel-under-bootc is *proven in the
field*, not hypothetical. Reference to study:
[`coreos/fedora-bootc-nvidia`](https://github.com/coreos/fedora-bootc-nvidia).

**Source revision.** RakuOS pulls the **NVIDIA upstream driver** (its `.run`/DKMS
payload) and compiles it **against the CachyOS kernel**, rather than the
RPMFusion `akmod-nvidia` the v0 scaffold (margine-image #161) uses. This
sidesteps the RPMFusion↔CachyOS **schedule-skew** the review flagged as the top
fragility (and that the CachyOS COPR itself cited when it dropped prebuilt
NVIDIA), and tracks the latest driver automatically.

**Revised recommendation:** keep the architecture (compile against
`kernel-cachyos-devel-matched`, sign with the Margine MOK via the existing loop,
build-arg gated) but **move the source RPMFusion akmod → NVIDIA-upstream
(DKMS / repo / `.run`)**, aligning the build block with
`coreos/fedora-bootc-nvidia` + RakuOS. The #161 RPMFusion path stays a valid v0
to get *a* signed module building; v1 swaps the source. MOK signing + build-arg
+ tag/CI structure are unchanged.

## Update 2026-06-15 — v1 landed (NVIDIA-upstream / DKMS)

The source revision above is **implemented** in margine-image
(PR #164): the `ENABLE_NVIDIA`-gated block in `build_files/custom-kernel/
install.sh` now pulls `kmod-nvidia-open-dkms` from NVIDIA's own CUDA repo and
**DKMS-builds it against this image's CachyOS kernel tree**
(`dkms build/install -m nvidia -k "$KERNEL_VERSION"`, where `$KERNEL_VERSION`
is the `kernel-cachyos-devel-matched` build tree, **not** the build-host
kernel). The `.ko` lands under `/usr/lib/modules/$KVER/extra/`, so the existing
`sign_kernel_modules()` loop signs it with the same Margine MOK — unchanged.

Adversarial-review fixes baked into v1:

- **No `binutils-gold`** — deprecated/absent on F44, would abort the
  transaction; `nvidia-open` does not need it.
- **Exact `%fedora` CUDA repo, hard-fail if absent** — no Fedora 42/41
  cross-grade fallback (glibc/userland skew). kABI correctness comes from the
  `-k` flag, not the repo's Fedora version.
- **`nvidia-drm.fbdev=1`** added to the kargs (Wayland/Plymouth handoff).
- Contingency documented in-code: if a future RPM makes the host-kernel
  `%post` dkms-autoinstall fatal to the dnf transaction, add
  `--setopt=tsflags=noscripts` + an explicit `dkms add` before the build.

The two `## Mandatory fixes` bullets that referenced the v0 akmod flow
(`akmod-$NVIDIA_KMOD` + `xorg-x11-drv-nvidia-cuda` in one dnf transaction;
the `modinfo -F signer` CN-match warning) are **superseded** by v1: userland
+ kmod now come from the single NVIDIA repo in one transaction, and signing is
left entirely to the existing loop (no CN gate). Status stays **experimental**
— rollout steps 2 (build green in CI) and 3 (real-hardware runtime validation)
are unchanged and still gate `:stable-nvidia`.

## Update 2026-07-12 — single-repo invariant enforced against negativo17

First scheduled weekly run (29184241364) failed: the base image's
fedora-multimedia repo (negativo17) also ships `nvidia-driver`, and it had
published 610.43.03 while NVIDIA's CUDA repo was still at .02. With `--best`,
dnf tried to take the userland from negativo17 and the kmod from CUDA and the
transaction became unsolvable. The "single NVIDIA repo, one transaction"
invariant above was stated but not enforced; it now is, via
`--setopt='fedora-multimedia.excludepkgs=*nvidia*'` on the install, so the
whole nvidia family always resolves from the CUDA repo regardless of which
repo happens to be ahead on a given day.
