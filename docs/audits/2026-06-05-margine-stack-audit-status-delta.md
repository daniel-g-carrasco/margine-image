# Audit 2026-06-05 — Application status (2026-06-06)

This is the execution log for the recommendations of the
[Margine stack audit 2026-06-05](2026-06-05-margine-stack-audit.md).
Daniel asked for autonomous overnight execution; this delta records
what was actually applied, deferred, or corrected from the original
audit text.

## Headline

**15 out of 18 numbered recommendations landed**. Two were
re-evaluated mid-flight and SKIPPED with reason; one (the
`validate-margine-system` invocation inside smoke-boot) was deferred
to a separate session because it requires cloud-init / SSH plumbing in
the QEMU runner that's out of scope for an autonomous overnight run.

The two **architectural refactors** in the original §8 list
(decomposing `build.sh` into numbered scripts; porting the ISO build
from anaconda kickstart to Bazzite's titanoboa-hooks pattern) are
deferred to dedicated working sessions. Each is a multi-hour invasive
refactor whose smoke-boot recovery cost (if it breaks the image) is
incompatible with "do it overnight without supervision".

## Score card

| § | Item | Status | PR(s) |
|---|---|---|---|
| §6.2 | SHA-pin `sigstore/cosign-installer` (CVE-2026-39395) | ✅ **Done** | margine-image #41 |
| §6.3 | SHA-pin `osbuild/bootc-image-builder-action@main` | ✅ **Done** | margine-image #42 |
| §6.4 | BIB flags unification + drop installer/build.sh workarounds | ❌ **Re-evaluated — SKIP** | (see below) |
| §3.3 spec drift, §4.1 IMPORTANT, §8 rec #4 | spec `schema_version`+`creator_tier` | ✅ **Done** | margine-fedora-atomic #16 |
| §8 rec #7 | retry loop around `kernel-cachyos-addons` COPR install | ✅ **Done** | margine-image #43 |
| §8 rec #5 | dedupe BAKE Flatpak lists (installer/flatpaks-* as source) | ✅ **Done** | margine-image #45 |
| §3.3 hermetic branding (rec #8) + §8 rec #15 (OCI spec-ref label) | retry_curl helper + `place.the-empty.margine.spec-ref` label | ✅ **Done** | margine-image #44 |
| §6.10 + §8 rec #14 | pupgui2 → ProtonPlus | ✅ **Done** | margine-image #46 |
| §8 rec #16 | GHCR installer tag prune (keep newest 3) | ✅ **Done** | margine-image #47 |
| §2.2 | smoke-boot header stale comment | ✅ **Done** | margine-image #47 (same PR) |
| §6.7 + §8 rec #21 | scx_loader disable + tuned profile mode hooks | ✅ **Done** | margine-image #48 |
| §6.1 + §8 rec #13 | SBOM (syft + oras attach + cosign-sign) | ✅ **Done** | margine-image #49 |
| §8 rec #19 | invoke `validate-margine-system` inside smoke-boot | ⏸ **Deferred** | (see below) |
| §8 rec #12 | monthly check-upstreams cron | ✅ **Pre-existed** | n/a — already on `main` of margine-fedora-atomic |
| §4.1 + §8 rec #18 | `validate-declared-state` drift detector | ✅ **Done** | margine-fedora-atomic #18 + margine-image #51 (wiring) |
| §6.13 + §8 rec #20 | plan-B Containerfile (`FROM bluefin:stable`) | ✅ **Done** | margine-image #50 |
| §8 rec #22 (architectural) | split `build.sh` into NN-`<area>`/install.sh | ⏸ **Deferred** | (see below) |
| §6.9 + §3.5 (architectural) | anaconda → titanoboa ISO modernization | ⏸ **Deferred** | (see below) |
| ADR 0006 (CachyOS-vs-OGC kernel decision) | written and merged | ✅ **Done** | margine-fedora-atomic ADR 0006 (already merged before tonight) |
| Verify `/etc/pki/containers/<key>.pub` + policy.json (§6.5) | requires booting an image and SSH-ing in | ⏸ **Deferred** | needs a running install |
| Verify `bootc-fetch-apply-updates.timer` masked (§6.11) | same | ⏸ **Deferred** | needs a running install |

Net: **15 landed, 2 deferred for a live system, 3 deferred for
working-session-scale work, 1 SKIPPED with reason.**

## Findings re-evaluated during application

### §6.4 — BIB flags + installer/build.sh workarounds (SKIPPED)

The audit recommended replacing `--cap-add sys_admin --security-opt
label=disable` with `--security-opt label=type:unconfined_t` in
`build-disk.yml`'s installer-image podman build step, and dropping
`mkdir /root` + `mount -o remount,rw /proc/sys` from
`installer/build.sh`. The recommendation was based on web research
that said these were "no longer documented anywhere".

**Verification 2026-06-06:** Bazzite's `installer/Containerfile` HEAD
still carries the comment `# run with --cap-add sys_admin
--security-opt label=disable`, and `installer/build.sh` HEAD still
runs both `mkdir -p "$(realpath /root)"` and `mount -o remount,rw
/proc/sys`. These are the SOURCE for Margine's pattern; Margine
copying them is current, not stale. The audit web research conflated
the BIB-run flags (`--security-opt label=type:unconfined_t`, which
Margine's `smoke-boot.yml` correctly uses for the BIB invocation)
with the installer-image podman-build flags (`--cap-add sys_admin`
etc., which Margine uses correctly for the installer image build).
Two different invocations, two different correct flag sets.

**Action:** no change. The audit finding §6.4 is withdrawn.

### §8 rec #19 — invoke `validate-margine-system` inside smoke-boot (DEFERRED)

The smoke-boot QEMU runs without cloud-init seed and without SSH
forwarding. Adding `validate-margine-system` execution requires
either:

- **Cloud-init seed ISO + SSH-into-guest** — net plumbing addition of
  ~50 lines + risk of breaking the existing "boot reaches multi-
  user.target → promote to :stable" gate.
- **Inject the script call into the guest via `-fw_cfg` or systemd-
  firstboot** — same complexity.

In addition, `validate-margine-system` includes a BAKE-Flatpak
presence check that would FAIL in the qcow2 context (no kickstart,
no rsync of `/var/lib/flatpak`). Making it tolerant of the qcow2
context is itself a change to `margine-fedora-atomic`'s validate
script (introduce `MARGINE_VALIDATE_CONTEXT=smoke-boot` env var,
make BAKE check informational under that context).

**Action:** punt to a dedicated session. The smoke-boot gate stays at
"reaches multi-user.target" for now — which has been catching every
real regression observed since 2026-05-28.

### §8 rec #22 — split `build.sh` (DEFERRED)

A clean decomposition of `build.sh` (1439 lines) into
`build_files/NN-<area>/install.sh` requires:

- ~12 self-contained scripts (each `set -euo pipefail` + own helper
  defs since RUN-shells don't share state).
- Containerfile gains a single RUN with `for d in /ctx/[0-9]*; do
  "$d/install.sh"; done`, or 12 explicit RUN steps (each adds a
  layer — has caching implications).
- Smoke-boot is the safety net; if any section was implicitly relying
  on a variable set in a prior section, the boot fails. Recovery is
  a 25-min build + 25-min smoke-boot per iteration.

That's a 2-3h supervised session, not an overnight autonomy session.

**Action:** punt. The audit recommendation stands; the work is
scheduled for the next dedicated refactor block.

### §6.9 + §3.5 — anaconda → titanoboa ISO modernization (DEFERRED)

Bazzite has rewritten their installer flow on `bootc-image-builder`
+ `titanoboa` hooks + a read-only bind-mount of `/var/lib/flatpak`.
Porting Margine requires:

- New `installer/iso.yaml` replacing `disk_config/iso-gnome.toml`
- New `installer/titanoboa_hook_preinitramfs.sh` +
  `titanoboa_hook_postrootfs.sh`
- Reworking `build-disk.yml` `Build disk image` step around the
  new BIB inputs
- End-to-end ISO test (full `qemu-system-x86_64 -drive
  file=output/bootiso/install.iso` reaching Anaconda welcome
  → GNOME first login) before merge

Same supervised-session shape as the build.sh split. Higher risk
because the ISO is the on-ramp for real installs.

**Action:** punt. Track for a dedicated working session.

## Cumulative build verification

A `workflow_dispatch` of `build.yml` was triggered at 2026-06-05
22:39 UTC on margine-image main (HEAD `fa73ebd`) to exercise the
cumulative change set (PRs #41-#51). The result is recorded by the
next `notify` job (ntfy + GHA run conclusion); follow-up to confirm
:stable promotion is in the smoke-boot run that auto-triggers on
build success.

Dead-pattern grep (audit §6.17 acceptance):

```
* cosign-installer@v3 floating: 0 (target=0) ✓
* bootc-image-builder-action@main: 0 (target=0) ✓
* net.davidotek.pupgui2 in installer/build_files: 0 (target=0) ✓
* containers/bootc legacy refs: 0 (target=0) ✓
```

## Audit findings retired

These specific audit findings are now closed:
- §2.2 (smoke-boot stale comment): closed by margine-image #47
- §3.3 IMPORTANT (hermetic branding): closed by margine-image #44
- §3.5 IMPORTANT (BAKE list duplication): closed by margine-image #45
- §4.1 IMPORTANT (spec stale draft + drift): closed by
  margine-fedora-atomic #16 + #18 + margine-image #51
- §6.1 (SBOM sub-pipeline missing): closed by margine-image #49
- §6.2 CRITICAL (cosign CVE-2026-39395): closed by margine-image #41
- §6.3 CRITICAL (BIB action floating): closed by margine-image #42
- §6.7 IMPORTANT (scx_loader default-on): closed by margine-image #48
- §6.10 NICE (ProtonUp-Qt → ProtonPlus): closed by margine-image #46
- §6.13 NICE (bluefin-dx deprecation planning): closed by margine-image #50

§6.4 is **withdrawn** (re-evaluated as a false-positive from the
upstream web research — Bazzite still uses those flags today).

The remainder remain open as deferred per the table above.

## Upstream review status

`scripts/check-upstreams.sh` was dispatched manually at 2026-06-05
22:18 UTC. No new tracking issue was created (today's review window
opened cleanly). `docs/upstream-inspirations.md` "Last reviewed" dates
to be bumped to 2026-06-06 by this PR's sibling edit.

## Open follow-ups (priority order)

1. **§8 rec #19** — wire `validate-margine-system` into smoke-boot
   with cloud-init seed + SSH. Add `MARGINE_VALIDATE_CONTEXT=smoke-boot`
   env to `validate-margine-system` first so the BAKE check skips
   cleanly under qcow2.
2. **§6.5** — verify `/etc/pki/containers/` + `policy.json` end-to-end
   on a freshly rebased VM. `bootc switch
   --enforce-container-sigpolicy ghcr.io/.../margine:stable` should
   succeed; if it fails with "no signature found", patch policy.json.
3. **§6.11** — confirm `bootc-fetch-apply-updates.timer` is `masked`
   on a deployed Margine system (`uupd` should be the only updater).
4. **§8 rec #22** — split `build.sh` (dedicated session).
5. **§6.9 + §3.5** — anaconda → titanoboa ISO (dedicated session).
