# Margine stack — end-to-end audit, 2026-06-05

**Author:** Margine project review
**Scope:** every Margine codebase, build pipeline, runtime behaviour, supply
chain, and external dependency, audited against the late-2025 / early-2026
state of the art in the Universal Blue / bootc / Fedora Atomic ecosystem.
**Method:** local read of `margine-image`, `margine-fedora-atomic`,
`margine-os-personal` (HEAD as of 2026-06-05) + parallel web research on
Bluefin team direction, Bazzite patterns, bootc / rechunk / cosign / BIB
SOTA + cross-reference vs canonical upstreams.

> Verdict in one sentence — Margine is **on the modern Universal Blue / bootc
> path**, with a build pipeline that is in many places *more* careful than
> upstream Bluefin's (SHA-pinned actions, by-digest signing, split jobs,
> retry loops, smoke-boot gate, observability). Three categories of issue
> remain: **(a)** a handful of declarations in `margine-fedora-atomic` drift
> from the actually-shipping `margine-image`, **(b)** several "belt +
> suspenders" duplications that were correct historically but now beg for
> single-source-of-truth refactors, **(c)** a small number of long-tail
> follow-ups (SBOM, fsverity composefs, ublue-update integration) that the
> upstream is moving toward and that Margine has not yet adopted. Nothing
> blocking, no security red flags, no broken supply chain.

---

## 0. How to read this audit

Findings are tagged with a severity:

| Tag | Meaning |
|---|---|
| **🟥 CRITICAL** | actively broken, security risk, or user-visible breakage; fix soon |
| **🟧 IMPORTANT** | drift / inconsistency / SOTA gap that will bite within months |
| **🟨 NICE** | hygiene, future-proofing, small wins |
| **🟩 NOTABLE** | done particularly well; preserve through future refactors |

Each item links to specific file/line so it's actionable, not just rhetoric.

---

## 1. Inventory — what Margine actually IS, today

| Repo | Role | Heart |
|---|---|---|
| [`margine-image`](https://github.com/daniel-g-carrasco/margine-image) (141 commits) | bootc OCI image factory | `Containerfile` + `Containerfile.gaming` + `build_files/` + 4 GHA workflows |
| [`margine-fedora-atomic`](https://github.com/daniel-g-carrasco/margine-fedora-atomic) (118 commits) | declarative spec + runtime validators + user-state helpers | `declarations/margine-atomic.yaml` + `scripts/configure-*` + `scripts/validate-*` |
| [`margine-os-personal`](https://github.com/daniel-g-carrasco/margine-os-personal) (375 commits, **private**) | **separate** distro on **CachyOS** native (NOT Fedora) with Hyprland + Limine + root-on-ZFS | `products/*.toml` + `manifests/` + provisioners |
| [`margine-os-1084ca72`](https://github.com/daniel-g-carrasco/margine-os-1084ca72) | marketing site `margine.the-empty.place` (TanStack Start prerender) | `src/routes/` |

**Critical distinction.** `margine-os-personal` is a separate product line on
CachyOS Arch — same brand, *very* different architecture from the bootc
"public" Margine. This audit focuses on **the public bootc stack** (image +
spec + validators + site). The personal CachyOS layer is touched only in
§7 (it has its own ADRs and its own integration model).

Output of the public stack:

- `ghcr.io/daniel-g-carrasco/margine:stable` — base image (Bluefin DX +
  CachyOS kernel + creator tooling + GNOME deltas)
- `ghcr.io/daniel-g-carrasco/margine-gaming:stable` — gaming variant on top
- `ghcr.io/daniel-g-carrasco/margine-installer:run-<id>` — transient image
  with Flatpaks pre-baked into `/var/lib/flatpak`, consumed only by BIB
- `archive.org/details/margine-anaconda-iso-YYYYMMDD` — Anaconda ISO via
  Internet Archive (HTTP + torrent, IA-seeded)
- `archive.org/details/margine-gaming-anaconda-iso-YYYYMMDD` — same for gaming

---

## 2. Build pipeline — `margine-image/.github/workflows/`

### 2.1 What's good — keep doing it 🟩

These are explicit *NOTABLE STRENGTHS*. Universal Blue's own
`image-template` does not always have them.

- **SHA-pinned actions everywhere.** `actions/checkout`, `docker/metadata-action`,
  `ublue-os/remove-unwanted-software`, `actions/download-artifact`,
  `sigstore/cosign-installer` — all pinned to a 40-char SHA, with the
  human-readable version in a trailing comment for Dependabot lockstep
  bumps. This is the *correct* response to the
  [tj-actions/changed-files March 2025 incident](https://www.stepsecurity.io/blog/tj-actions-changed-files-supply-chain-attack)
  where a floating-tag GHA was compromised at the source.
  See [build.yml:104](https://github.com/daniel-g-carrasco/margine-image/blob/main/.github/workflows/build.yml#L104).
- **Cosign sign by digest, not by tag.** The build job emits
  `image_ref = ${REGISTRY}/${IMAGE}@sha256:...` as an output, and the
  separate `sign` job consumes that. Eliminates the race where the tag
  could be re-pushed between push and sign.
- **Split-stage jobs with `needs:` + `outputs.digest`.** `build_push` (≈25
  min) → `sign` (≈1 min) → `notify` (`if: always()`). Failed sign?
  `gh run rerun --failed` is 1 minute, not 26. This codifies the lesson
  filed in [feedback_ci_split_long_jobs.md](../../../proxmox-pve1/...).
- **Retry loops on upstream flakiness.** COPR install (5 attempts, 30-150s
  backoff) and `quay.io` BIB pull (8 attempts, exponential). Both
  documented with the exact failed-run IDs that motivated them.
- **No more `redhat-actions/buildah-build`.** Direct `sudo buildah build`
  inline gets us off the upstream Node 20 deprecation warning, kills a
  dependency on a paused upstream action ([redhat-actions/buildah-build#155](https://github.com/redhat-actions/buildah-build/issues/155)),
  and makes the build trivially reproducible on a developer laptop.
- **Smoke-boot promotion gate.** `:candidate` is published first;
  `smoke-boot.yml` builds a qcow2, boots it in QEMU on a KVM-enabled
  ubuntu-24.04 runner, waits for `multi-user.target`, then promotes the
  *exact digest* to `:stable` via `skopeo copy --preserve-digests`.
  This is the *correct* shape of "candidate → tested → promoted".
- **`rechunk@v1.2.4` end-of-build.** The 2026-06-01 wind-down note
  [`2026-06-03-rechunk-and-fixb.md`](../lessons-learned/2026-06-03-rechunk-and-fixb.md)
  documents the move from a workaround (regular-file `/etc/os-release`)
  to the canonical fix (rechunk re-commits the image into proper
  ostree-canonical form). The build now uses the rechunked artifact for
  push, and the published image is byte-for-byte what Universal Blue's
  own pipeline produces in shape.
- **ntfy push notifications with a *decision matrix***. Surfaces partial
  success (image pushed, sign failed) explicitly so daniel can
  `gh run rerun --failed` instead of guessing.
- **`bootc container lint`** at the end of every Containerfile.
- **Concurrency cancellation.** `cancel-in-progress: true` on the workflow
  group avoids the queue cascade where 4 pushes spawn 4 parallel
  long-running builds.
- **Workflow trigger chain.** `build.yml` → `smoke-boot.yml` (workflow_run)
  → `build-gaming.yml` (workflow_run on smoke-boot success). This means
  the gaming variant is *automatically* always within minutes of the
  latest *validated* base `:stable`. Carefully thought out.

### 2.2 Issues and gaps

#### 🟧 IMPORTANT — `smoke-boot.yml`: gate is workflow_dispatch-only

[smoke-boot.yml:33](https://github.com/daniel-g-carrasco/margine-image/blob/main/.github/workflows/smoke-boot.yml#L33)
says trigger is currently `workflow_dispatch` only and the header comment
says *"Once it's been validated end-to-end a few times, change to workflow_run
after Build Margine image so every push to main gets smoke-booted before
being trusted."* — But the actual file already has both `workflow_dispatch`
AND `workflow_run` triggers configured. The comment is stale; reality is
correct. **Fix:** delete the now-misleading "Current trigger:
workflow_dispatch only" paragraph in the file header.

#### 🟨 NICE — installer-image push uses `run-<id>` tag, never cleaned up

[build-disk.yml:177](https://github.com/daniel-g-carrasco/margine-image/blob/main/.github/workflows/build-disk.yml#L177)
pushes `ghcr.io/.../margine-installer:run-<run_id>`. Each ISO build leaves
a new tag on GHCR forever (the package was bootstrapped manually
2026-06-05). After 6 months of weekly ISO builds you'll have ~25 stale
tags. **Fix options:**
- Add a "purge stale installer tags" step at end of workflow keeping only
  the last 3 builds (Bazzite does this).
- Or use a single `:latest` mutable tag for the installer (it's transient,
  never user-consumable — daniel said himself it's not published as
  `:stable`). Mutable tag is fine because BIB pulls it immediately by
  digest within the same job.

#### 🟨 NICE — no SBOM (syft / cyclonedx) generation

Universal Blue's main image-template doesn't generate SBOMs either, but
this is a documented gap upstream. For an image that ships under Apache-2.0
and gets installed on real hardware, having an `sbom.spdx.json` next to
the cosign signature on GHCR is a reasonable hygiene step. Tooling:
`anchore/sbom-action` or `syft` direct. **Cost:** ~30 sec of CI, ~5 MB
artifact pushed to GHCR alongside the manifest.

#### 🟨 NICE — cosign uses key-based signing, not keyless OIDC

[build.yml:284](https://github.com/daniel-g-carrasco/margine-image/blob/main/.github/workflows/build.yml#L284)
signs with `--key env://COSIGN_PRIVATE_KEY`. Universal Blue's image-template
has moved to keyless OIDC for first-party images (`id-token: write` →
`cosign sign $IMAGE` — no `--key` flag, signs against the Fulcio CA with
the GHA workflow's OIDC identity as the subject). Trade-off:

| Path | Pros | Cons |
|---|---|---|
| Key-based (current) | Works in air-gapped CI; signature verifiable without sigstore trust root | Key rotation is a maintenance task; private key in repo secrets |
| Keyless OIDC | No key to manage; cryptographically tied to the workflow that produced it; auditable in Rekor | Slightly more complex consumer verification; new signature on every CI run |

**Recommendation:** keep key-based for now (cosign.pub published at
`https://raw.githubusercontent.com/daniel-g-carrasco/margine-image/main/cosign.pub`,
consumer can pin the key in their `policy-controller` config or in
`/etc/containers/policy.json` for `ostree-image-signed:` rebases). Migration
to keyless is a *future improvement*, not a fix. The relevant Universal Blue
discussion thread is the place to track when their default moves: linked in
§6.

#### 🟨 NICE — no in-CI `bootc-image-builder` for the qcow2 used in smoke-boot

`smoke-boot.yml` uses `bootc-image-builder-action@main` (line 153). That
"@main" is a *floating reference* — same supply-chain risk we eliminate
everywhere else by SHA-pinning. **Fix:** pin to a release tag + SHA, same
pattern as the rest of the workflows.

---

## 3. Containerfile + `build_files/` deep dive

### 3.1 Architecture 🟩

The split is **clean and modern**:

```
Containerfile               (≤30 lines, ≤3 RUN layers, declarative)
├── FROM ghcr.io/ublue-os/bluefin-dx:stable
├── RUN /ctx/custom-kernel/install.sh       (kernel swap + MOK signing)
├── RUN /ctx/build.sh                       (Margine deltas: branding,
│                                            os-release, gschemas, ujust,
│                                            BAKE/DEFER Flatpak lists)
└── RUN /ctx/build-margine-extensions.sh   (GNOME ext baked /usr-wide)
```

This is *cleaner* than Bluefin's own `Containerfile` (which has more
inline logic). All actual work lives in scripts under
`build_files/<area>/install.sh` — small, focused, testable.

### 3.2 `custom-kernel/install.sh` (421 lines) 🟩

Derived from Origami Linux per
[`docs/upstream-inspirations.md`](../upstream-inspirations.md) with
license attribution. Margine's version is *more* defensive than the
upstream:

- **Pre-flight validates MOK key/cert match** with `openssl pkey -pubout`
  vs `openssl x509 -pubkey -noout` + `cmp -s`. Catches mis-paired secrets
  *before* doing anything destructive to the kernel.
- **Retry loop on COPR install** (5 attempts, exponential backoff) —
  driven by an actual failed run on 2026-06-02 (run #26838562527),
  reference documented in code.
- **`dnf clean packages metadata` before COPR install** — addresses the
  "Payload SHA256 ALT digest: BAD" failure mode on persistent BuildKit
  caches.
- **v4l2loopback is best-effort, not build-blocking.** Origami fails the
  whole image if v4l2loopback can't compile. Margine logs `V4L2_OK=0` and
  ships without it. Pragmatic.
- **MOK-signing of *both* vmlinuz AND every `.ko`/`.ko.xz`/`.ko.zst`/`.ko.gz`**
  under `/usr/lib/modules/<KVER>` with `sign-file`, then DER-export to
  `/usr/share/cert/MOK.der`, with a one-shot `mok-enroll.service` for
  first-boot enrollment via `mokutil`. This is the *complete* signing
  chain Secure Boot needs. Many "custom kernel on Fedora Atomic" guides
  online stop at vmlinuz and leave modules unsigned (which works only
  with `MOK_VERIFY_OPTIONAL` policy — fragile).
- **`dracut --add ostree`** at end. The comment block explains *exactly*
  why: without the ostree dracut module, `ostree-prepare-root` is missing
  from the initramfs and switch-root fails on real installs ("Failed to
  switch root: ... os-release file is missing"). This is the kind of
  subtle bootc gotcha that takes hours to diagnose first time around.
  Code documents what AND why.

#### 🟧 IMPORTANT — `dnf -y copr enable bieszczaders/kernel-cachyos-addons` after kernel install

[custom-kernel/install.sh:~349](https://github.com/daniel-g-carrasco/margine-image/blob/main/build_files/custom-kernel/install.sh#L349)
enables a *second* COPR (kernel-cachyos-addons) just to install
`scx-scheds`, then `dnf copr disable` and removes the `.repo` file.
This is correct supply-chain hygiene (transient COPR), but:

- The retry loop pattern is NOT applied here. If `kernel-cachyos-addons`
  COPR has the same intermittent 5xx as `kernel-cachyos` COPR (same host,
  copr.fedorainfracloud.org), the build will fail without retry.
- Fix is one-line: wrap in the same `attempt/max_attempts` loop used
  above. Same backoff. Done.

#### 🟨 NICE — `disable_akmodsbuild` patches a system script

[custom-kernel/install.sh:84](https://github.com/daniel-g-carrasco/margine-image/blob/main/build_files/custom-kernel/install.sh#L84)
patches `/usr/sbin/akmodsbuild` to disable a signing step that doesn't
work in BuildKit containers. The change is reverted via `restore_akmodsbuild`
at the end. This is exactly Origami's hack. **It works** but:

- The patched bytes depend on `akmods` package internals. If the akmods
  upstream changes the script, the sed match silently no-ops and v4l2loopback
  fails *silently* (which is fine because we mark v4l2 best-effort, but
  the *cause* of the failure becomes invisible).
- Long-term: open an issue against
  [Akmods upstream](https://github.com/fedora-projects/akmods) asking
  for an env var or flag that disables the signing step natively, like
  `AKMODS_SKIP_SIGNING=1`. Origami carries the same patch; aligning to
  ask for upstream support would help several downstreams at once.

### 3.3 `build.sh` (1439 lines) — the big delta script

Well-organized into 11 numbered sections (visible via `grep "^# ----"`).
Highlights:

- **Section 0** — OS identity via canonical Fedora symlink layout
  (`/etc/os-release → ../usr/lib/os-release`). Pre-2026-06-03 this was a
  regular file workaround (Fix A); now restored to canonical with the
  history preserved as a comment paragraph. ✓
- **Section 1** — BAKE + DEFER Flatpak design. **This is the unique
  Margine engineering contribution.** Twenty-nine "fundamental" apps
  bake into the kickstart-installed `/var/lib/flatpak` (instant at first
  login), four "macigni" (GIMP, Inkscape, darktable, OBS) deferred to
  `flatpak-preinstall.service` first-boot download. Both lists are
  hand-merged (every BAKE app is *also* in DEFER as belt+suspenders so
  a silent BAKE failure still arrives at first boot). This is *better*
  than Bazzite's own model (which is BAKE-only, no fallback). 🟩
- **Section 5b** — `systemd-remount-fs.service` masked. Documented as
  Bug 8: composefs overlay refuses remount, unit always lands in
  `failed`, confusing humans. The fix is the right one. ✓
- **Section 5c** — `/etc/skel/.config/no-show-user-motd`. Disables
  Bluefin's MOTD for *new* users via skeleton, so it doesn't reappear
  after a fresh `useradd`. Hygiene point that Bluefin themselves got
  wrong; Margine got it right. 🟩
- **Section 5d** — Boot-time seed of `/etc/passwd` + `/etc/group`
  (Bug 6 v2). Workaround for rechunk stripping `/etc` factory entries.
  Implemented as a Python systemd oneshot with idempotency check
  (only seeds if count < 20). **This is a real gap in rechunk**, not a
  Margine bug — but the workaround is correctly minimal and idempotent.

#### 🟧 IMPORTANT — `MARGINE_REPO` + `MARGINE_REF` for branding assets is a *runtime* curl from GitHub

[build.sh:~696-730](https://github.com/daniel-g-carrasco/margine-image/blob/main/build_files/build.sh#L696)
fetches branding (logo, wallpaper, Plymouth theme) from
`margine-fedora-atomic` via `curl` *at image build time*. The repo URL +
ref are env vars (presumably set by the workflow). Consequences:

- **Network dependency mid-build.** If GitHub returns 5xx for 5 min,
  the 25-min build dies near the end. Unlike COPR or RPMFusion, no retry
  loop wraps the curls.
- **Branding tied to whatever ref the workflow picked.** Hard to know
  from looking at a published image which `margine-fedora-atomic` SHA
  produced its assets.
- **Build is no longer hermetic.** Same Containerfile + same build context
  + different time of day = potentially different output.

**Fix options (smallest first):**
1. Wrap branding `curl`s in the same retry loop as COPR/RPMFusion.
2. Stamp the resolved `margine-fedora-atomic` SHA into an OCI label
   (`org.opencontainers.image.documentation` or a custom
   `place.the-empty.margine.spec-ref`) so consumers can audit.
3. Pull branding from a git submodule pinned at a specific SHA, instead
   of curl at build-time. Most idiomatic for "two repos that build one
   product."

#### 🟧 IMPORTANT — `dnf -y install plymouth-plugin-script` at build time

[build.sh:~751](https://github.com/daniel-g-carrasco/margine-image/blob/main/build_files/build.sh#L751)
installs a Bluefin-not-shipped Plymouth plugin via dnf. This is the
*one* place in `build.sh` where a Fedora package is added to the base
without going through the transient/scrub pattern that the kernel does.
- It's not wrong (Plymouth plugin script is in main Fedora, not COPR).
- But it *adds a permanent package layer* that consumers see as part of
  the image. No problem if intentional; question is just whether it
  should be documented in the spec's `host_packages.baseline` section
  (it's not).

#### 🟨 NICE — spec drift: scx-scheds + mangohud/goverlay/steam-devices

`build.sh` (and `custom-kernel/install.sh:354`) installs **scx-scheds +
mangohud + goverlay + steam-devices** in the BASE image (promoted from
gaming variant 2026-06-03 and 2026-06-05). But
[`declarations/margine-atomic.yaml:1059`](../../declarations/margine-atomic.yaml#L1059)
still lists these as `gaming_runtime.opt_in.rpm_host_helpers_opt_in`, and
[line 1042](../../declarations/margine-atomic.yaml#L1042) says *"no
scx-scheds (we have the CachyOS kernel)"* — both stale.

**Fix:** update `declarations/margine-atomic.yaml` to reflect actual
baseline. Add a `host_packages.baseline.creator_tier:` subsection with
`scx-scheds, mangohud, goverlay, steam-devices` and remove them from
`gaming_runtime.opt_in.rpm_host_helpers_opt_in`. Update the
`inspired_by:` paragraph to drop the "no scx-scheds" claim.

### 3.4 `build-margine-extensions.sh` 🟩

Replicates Bluefin's pattern (`build-gnome-extensions.sh`): install
non-Fedora-repo GNOME extensions into `/usr/share/gnome-shell/extensions/`
at build time, enable them via gschema override, GDM picks them up on
first login. **No more per-user race** with `flatpak-preinstall.service`.

- Versions pinned (`OTILING_VERSION="v2.8.8"`). ✓
- Compatibility check via EGO API for `hide-cursor` (auto-picks the
  shell-version compatible release). Correct.
- **NO `dnf` install of `unzip`/`jq`/`glib2-devel`** — file header has
  a long block explaining how the previous version broke scx-scheds
  via `dnf5 autoremove` cascading through `scx-tools-git` →
  `Requires: jq`. Saved hour-class debugging. 🟩

### 3.5 `installer/Containerfile` + `installer/build.sh`

The **Bazzite installer-image pattern** for first-boot Flatpak instant
availability. This is the right pattern; Margine copied it exactly. The
4 quirks (`--cap-add sys_admin`, `--security-opt label=disable`,
`mkdir /root`, `mount -o remount,rw /proc/sys`) are documented inline.

#### 🟧 IMPORTANT — `installer/flatpaks-base` is a duplicate of `build.sh` BAKE list

Two lists carry the same 29 apps:
- `/home/daniel/dev/margine-image/installer/flatpaks-base`
- The here-doc inside `build_files/build.sh` at line ~217 that writes
  `/usr/share/margine/installer-flatpaks-base`

Both are "the BAKE list" and have to stay in sync **manually**. The
`installer/flatpaks-base` comment even says "Kept in sync manually for
now." This is the textbook drift hazard.

**Fix:** make `installer/flatpaks-base` (the file in the repo) the
single source of truth, and have `build.sh` `cp` it into
`/usr/share/margine/installer-flatpaks-base` at build time instead of
re-writing it via here-doc. One file, one truth.

(Same applies to `installer/flatpaks-gaming` vs
`build_files/gaming/install.sh`.)

### 3.6 `disk_config/iso-gnome.toml` 🟩

The kickstart embeds two `%post` blocks:
1. `bootc switch --mutate-in-place` to point the freshly installed
   system at `ghcr.io/.../margine:stable`. Correct.
2. `btrfs property set / compression zstd` + edit `/etc/fstab` to add
   `compress=zstd:1`. Documented with the rationale (same level
   Bazzite/SteamOS use). Two-layer (now + persist) is the right shape.

The `bootc switch` invocation is the canonical mechanism for ISO →
production-image migration. Margine does it cleanly.

---

## 4. `margine-fedora-atomic` — declarative spec + validators

### 4.1 `declarations/margine-atomic.yaml` (1134 lines)

A *very* well-thought-out top-down description of what Margine should
do. The `host_packages.baseline.codec_replacement` section is exemplary
(documents WHY each package, what tests it was validated against, what
RPMFusion vs Fedora version skew issues exist, what was DELIBERATELY
SKIPPED and why). This is documentation-as-code at its best. 🟩

#### 🟧 IMPORTANT — schema_version is still 0 / status is "draft"

[Line 1-2](../../declarations/margine-atomic.yaml#L1-L2):
```yaml
schema_version: 0
status: draft
```

The spec has been shipping in production for weeks. Either:
- Move to `schema_version: 1` + `status: stable` (no breaking changes
  since 2026-05-30 audit). Easy.
- Or define what would *cause* a bump (and document it in a comment so
  future-you knows the criterion).

#### 🟧 IMPORTANT — `gaming_runtime` section is stale (see §3.3)

Already covered above. Update the section to reflect actually-shipping
package set.

#### 🟨 NICE — no `validate-declared-state` drift detector

The roadmap mentions a future "drift detector" that diffs the spec
against the running system. `validate-margine-system` (731 lines) does
*part* of it (Flatpak presence, system users, schemas registered) but
not against the declared spec's full surface area. **Cost:** medium —
designing a useful diff against a large YAML is non-trivial. Add as a
phase-3 todo, not now.

### 4.2 `scripts/check-upstreams.sh` 🟩

This is a hidden gem. It reads `docs/upstream-inspirations.md` for the
"Last reviewed" dates, then hits the GitHub API to count commits per
upstream (bluefin, origami, morros, image-template, rechunk, bazzite)
since that date, and prints a "review needed" list. Exactly the right
shape for a small-team project: *automated nag, manual decision*.

**One ask:** the upstream-inspirations table all says
`Last reviewed: 2026-05-30`. As of 2026-06-05, Bluefin has had
non-trivial commits (e.g.
[fc4e800 docs: add THEPATTERN.md](https://github.com/ublue-os/bluefin/commit/fc4e800)
on 2026-06-01, [a527d4c feat(just): add validate-scripts shellcheck](https://github.com/ublue-os/bluefin/commit/a527d4c)
on 2026-05-31). Worth running `check-upstreams.sh` and re-reviewing.

The TODO memory already calls for "automate this on a monthly GHA cron" —
that's the right next step. Schedule: monthly cron in
`margine-fedora-atomic` that runs the script and opens a GH issue if any
upstream has new commits. ~50 lines of YAML.

### 4.3 `scripts/validate-margine-system` (731 lines) 🟩

End-to-end acceptance test. Eleven sections of checks (os-release
identity, kernel signature, system users + groups + wheel-user
auxiliary group membership, GNOME extension schemas registered, BAKE
Flatpak presence cross-check, etc.). Output is colored OK / WARN / FAIL
with a single PASS/FAIL summary line at the end. Designed to be
`curl | bash`-able from anywhere.

**No issues found.** This is the right shape.

### 4.4 `configure-*` helpers + `validate-*` validators 🟩

Idempotent, default to dry-run with `--apply`, become
`/usr/bin/margine-configure-*` in the image, used both by
`margine-bootstrap` ujust recipe and by user invocations. Stable design
pattern that hasn't needed refactoring in months.

---

## 5. `margine-os-personal` — separate CachyOS layer

(Quick scan only; this is a different architecture and is private.)

- 43 ADRs, dense and well-thought-out (Limine + UKI + signed boot +
  sbctl + LUKS2 + Btrfs *or* root-on-ZFS depending on product flavour).
- 375 commits in 6 months — actively evolving.
- Hyprland-first Wayland desktop, Walker launcher.
- Update orchestrator `update-all` with ZFS snapshot + rollback boot entry.
- Validation harness in QEMU (`scripts/prepare-qemu-root-zfs-validation`).

**No public bootc image here** — installation is via Arch live ISO +
provisioner scripts (`scripts/install-cachyos-personal-baseline` and
similar), not a `bootc switch`. This is consistent with the project's
own ADR 0006 ("Margine is NOT a frozen fork of Arch").

**Cross-line concern:** the brand name "Margine" is shared between two
*architecturally distinct* products (Fedora Atomic bootc vs CachyOS
native), which can confuse users discovering the project via the
public marketing site. The site doesn't mention the personal CachyOS
flavour; that's intentional (personal layer is private). Just keep this
distinction crisp in any future public-facing copy.

---

## 6. Universal Blue ecosystem alignment — 2026 SOTA

This section is the cross-reference: what we found in the Margine code vs
what the **rest of the world** is doing in June 2026. Built from three
parallel research passes against `ublue-os/bluefin` HEAD, `ublue-os/bazzite`
HEAD, `bootc-dev/bootc` (note: repo *moved* from `containers/bootc`),
`hhd-dev/rechunk`, `osbuild/bootc-image-builder`, Sigstore advisories, and
the Bluefin team's blog + new `THEPATTERN.md` (2026-06-02, commit
[`fc4e800`](https://github.com/ublue-os/bluefin/commit/fc4e800)).

### 6.1 The canonical 2026 build pipeline (vs Margine's)

The reference is
[`ublue-os/bluefin/.github/workflows/reusable-build.yml`](https://github.com/ublue-os/bluefin/blob/main/.github/workflows/reusable-build.yml)
HEAD as of 2026-06-02:

```
1. checkout (SHA-pinned)
2. ublue-os/remove-unwanted-software (disk)
3. just check (Justfile syntax)
4. DNF cache restore
5. just build-ghcr (buildah)
6. DNF cache save
7. anchore/sbom-action/download-syft       ← Margine MISSING
8. just gen-sbom → sbom_out/<image>/.json  ← Margine MISSING
9. just rechunk (hhd-dev/rechunk)          ← Margine: ✓
10. just load-rechunk → podman             ← Margine: implicit ✓
11. just secureboot (sbverify modules)     ← Margine: implicit via custom-kernel ✓
12. just generate-build-tags + tag-images
13. podman login + push --digestfile
14. cosign-installer @v3.10.1 (SHA-pinned)  ← Margine: @v3 floating ⚠
15. cosign sign -y --key env://... IMG@DIGEST  ← Margine ✓ (by-digest)
16. oras-project/setup-oras                 ← Margine MISSING (no SBOM)
17. oras attach --artifact-type spdx+json   ← Margine MISSING
18. cosign sign the SBOM artifact too       ← Margine MISSING
```

**Verdict:** Margine matches the spine but **misses the entire SBOM
sub-pipeline** (steps 7-8, 16-18). All other moving parts are present and
in some cases pinned more carefully than upstream.

### 6.2 🟥 CRITICAL — `cosign-installer@v3` floating tag exposes CVE-2026-39395

[`build.yml:290`](https://github.com/daniel-g-carrasco/margine-image/blob/main/.github/workflows/build.yml#L290)
and [`build-gaming.yml:206`](https://github.com/daniel-g-carrasco/margine-image/blob/main/.github/workflows/build-gaming.yml#L206)
both use `sigstore/cosign-installer@v3` — a *floating major tag*.

- [**CVE-2026-39395 / GHSA-w6c6-c85g-mmv6**](https://github.com/sigstore/cosign/security/advisories/GHSA-w6c6-c85g-mmv6)
  (April 2026): `cosign verify-blob-attestation` false-positive on
  malformed payloads. Patched in **cosign v3.0.6** and **v2.6.3**.
- The `@v3` floating reference doesn't pin to a specific cosign release
  *and* doesn't pin the action itself by SHA. Two layers of risk.
- The Universal Blue canonical pin today is
  `sigstore/cosign-installer@7e8b541eb2e61bf99390e1afd4be13a184e9ebc5 # v3.10.1`
  which pulls cosign v3.0.6.

**Fix (one-line, do this week):**
```yaml
uses: sigstore/cosign-installer@7e8b541eb2e61bf99390e1afd4be13a184e9ebc5  # v3.10.1
```

### 6.3 🟥 CRITICAL — `bootc-image-builder-action@main` is fully floating

[`build-disk.yml:198`](https://github.com/daniel-g-carrasco/margine-image/blob/main/.github/workflows/build-disk.yml#L198)
uses `osbuild/bootc-image-builder-action@main`. Any compromise of the
upstream repo or a single bad commit on main lands in your next ISO
build. **Same fix shape as 6.2:** find the latest release tag + SHA, pin.

### 6.4 🟧 IMPORTANT — installer-image BIB flags are the **old** pattern; `smoke-boot.yml` already uses the new one

Two different BIB invocations in this repo, *inconsistent*:

| File | Pattern |
|---|---|
| `smoke-boot.yml:96` | `--security-opt label=type:unconfined_t` ← **modern** |
| `build-disk.yml:186-187` | `--cap-add sys_admin --security-opt label=disable` ← **old (2024 GHA runners)** |

The agents' research against 2026 BIB docs is unambiguous: `--cap-add SYS_ADMIN`
is now superseded by `--privileged`; `--security-opt label=disable` is
replaced by `--security-opt label=type:unconfined_t`; the `mkdir /root`
and `mount -o remount,rw /proc/sys` workarounds (still in
[`installer/build.sh:32-33`](https://github.com/daniel-g-carrasco/margine-image/blob/main/installer/build.sh#L32))
are no longer documented anywhere.

**The "old" pattern still works today** — your last ISO build (2026-06-03)
proves that. But it's a stale-knowledge tax: anyone reading the code thinks
those flags are required and copies them forward. Worse, if `installer/build.sh`
is ever run on a newer base BIB image that *removes* compatibility with
the deprecated flags, it'll fail mysteriously.

**Fix (medium priority, this month):**
- `build-disk.yml:186-187` → replace `--cap-add sys_admin --security-opt label=disable`
  with `--security-opt label=type:unconfined_t` (or `--privileged` if needed).
- `installer/build.sh:32-33` → drop `mkdir /root` + `mount -o remount,rw /proc/sys`
  and re-test ISO build. If it fails, add `osbuild-selinux` to the runner
  instead — that's the modern equivalent.

### 6.5 🟧 IMPORTANT — `/etc/pki/containers/<key>.pub` + `policy.json` cross-check

[ublue-os/bluefin#4197](https://github.com/ublue-os/bluefin/issues/4197)
documents a 2026-02-12 incident where `bluefin-dx:stable` shipped without
`/etc/pki/containers/ublue-os.pub`, breaking `bootc upgrade` for all
downstream consumers using `--enforce-container-sigpolicy`. **Action for
Margine:**

- Verify `ghcr.io/daniel-g-carrasco/margine:stable` has a populated
  `/etc/pki/containers/` directory with the **margine** cosign public
  key alongside the inherited ublue-os one.
- Verify `/etc/containers/policy.json` allows your registry path with
  `cosign` verification, not just `insecureAcceptAnything`.
- This is what makes `bootc switch --enforce-container-sigpolicy
  ghcr.io/daniel-g-carrasco/margine:stable` *actually* verify, not just
  succeed.

### 6.6 🟧 IMPORTANT — Bazzite no longer ships `gamemode`; Margine still inherits it from Bluefin DX

The Bazzite Containerfile now does `dnf5 -y remove gamemode` and moved
performance tuning to `tuned profiles + scx_loader + dmemcg-booster`.
Margine's `build_files/gaming/install.sh` correctly notes that gamemode
is *inherited from Bluefin DX*, so we don't add it. **That's fine** —
but if Bluefin DX eventually follows Bazzite's lead (likely, given the
shared team), gamemode disappears from the base too and any Margine
documentation referencing `gamemoded` (e.g. `build_files/gaming/install.sh:123`
in the sanity-check loop) breaks. Track it.

### 6.7 🟧 IMPORTANT — sched_ext via `bieszczaders/kernel-cachyos-addons` is correct, but Margine ENABLES `scx_loader` by default; Bazzite explicitly disables it

Both Bazzite and Margine use `bieszczaders/kernel-cachyos-addons`
COPR (confirmed alignment ✓). But:

- **Bazzite**: `systemctl disable scx_loader.service` in the
  Containerfile. Users opt-in via `ujust`. When opted-in, tuned profile
  scripts drive `scxctl switch -m <mode>` on power-profile changes.
- **Margine**: no equivalent explicit disable. `scx_loader` is the
  default for the `ujust margine-scheduler` recipe but it's unclear
  from a code read whether the service auto-starts on every boot. The
  `margine-scheduler.desktop` UI lets users pick a scheduler imperatively.

**Action:** confirm `systemctl status scx_loader.service` on a fresh
Margine deployment. If `enabled`, consider Bazzite's pattern: disable
by default, let users opt in, let tuned profile scripts drive the
mode-switch. (Battery-life win on the base/creator image.)

### 6.8 🟧 IMPORTANT — Bazzite has pivoted to the **OGC kernel**; CachyOS is now an explicit "not us" choice

The Open Gaming Collective (`OpenGamingCollective/kernel-packages`,
created 2025-12-30) ships a shared kernel used by **Bazzite, ChimeraOS,
Nobara, Playtron, PikaOS, Fyra/Ultramarine, ShadowBlip, ASUS Linux**.
`hhd-dev/kernel-bazzite` (the old Bazzite-specific fork) was **archived
2026-05-01**. CachyOS publicly skipped joining OGC (Peter Jung cited
"bureaucracy slowing releases") and is now **#1 on ProtonDB at 21.1% of
Linux Steam users** (March 2026); Bazzite is #4 at 9.5%.

**For Margine, this is a strategic choice that deserves an ADR:**

| Path | Pros | Cons |
|---|---|---|
| Stay on `bieszczaders/kernel-cachyos` (today) | CachyOS won the Steam survey; performance story is real; aligns with `scx-scheds` addons same-COPR | Single-maintainer Fedora COPR (`bieszczaders` is *not* the CachyOS team); CachyOS removed prebuilt Nvidia drivers 2026-02-23; risk of COPR going silent |
| Switch to OGC kernel | 8-distro shared CI; upstream-first promise; aligned with where Bazzite/Bluefin team is investing | Slightly more conservative perf tuning than CachyOS; you join a charter you don't control |
| Stay on Bluefin's own signed `ublue-akmods` kernel | Boring, default, smaller delta from upstream | Lose the whole CachyOS perf story; remove the entire `custom-kernel/install.sh` machinery |

**Recommendation:** write **`docs/adr/0006-kernel-cachyos-decision.md`**
that records the trade-off explicitly. The CachyOS bet has *concrete*
upside (Steam survey) but is also *not* the path the rest of the
ecosystem is converging on. Either decision is defensible; the
*undocumented* status quo is the risk. Use `scripts/check-upstreams.sh`
to add OGC to the watch list.

### 6.9 🟨 NICE — Bazzite installer pattern has refactored; Margine's anaconda-iso path is now ~12 months behind

Bazzite's `installer/` moved off anaconda kickstart-with-rsync to
**bootc-image-builder + titanoboa hooks** (`iso.yaml` config, no more
kickstart). Margine still uses anaconda-iso with kickstart (`%post`
in `disk_config/iso-gnome.toml`). This works (your ISO builds OK), but
the upstream way has converged elsewhere.

**Action (later, not now):** when refactoring the ISO build (already in
TODOs as `project_todo_build_margine_iso`), study Bazzite's
`installer/build.sh` + `installer/iso.yaml` + the `titanoboa_hook_*.sh`
pair. Specifically, the read-only bind-mount of `/var/lib/flatpak` via a
systemd `.mount` unit is the trick that keeps the prebaked Flatpak tree
clean during `bootc install`.

### 6.10 🟨 NICE — Flatpak list alignment

Cross-referencing Margine's `installer/flatpaks-base` against Bazzite's
`installer/gnome_flatpaks/flatpaks` HEAD:

| App | Bazzite 2026 | Margine 2026 | Notes |
|---|---|---|---|
| ProtonPlus (`com.vysp3r.ProtonPlus`) | ✓ | — | Bazzite replaced ProtonUp-Qt with ProtonPlus. Margine ships ProtonUp-Qt in gaming variant. **Consider migrating.** |
| Mission Center (`io.missioncenter.MissionCenter`) | ✓ | — | Modern replacement for gnome-system-monitor; Bazzite removes gnome-system-monitor. Margine retains it. |
| Warehouse (`io.github.flattool.Warehouse`) | ✓ | — | Modern Flatpak manager UI. Optional add. |
| Refine (`page.tesk.Refine`) | ✓ | — | GNOME extensions GUI. Margine ships ExtensionManager. Both is overkill. |
| `runtime/...MangoHud/x86_64/25.08` | ✓ pinned | not shipped as Flatpak runtime | If a user runs Flatpak'd Steam (they might, despite system RPM steam), Flatpak Vulkan layers need the runtime. |
| `org.gnome.gitlab.somas.Apostrophe` | — | ✓ | Margine adds; Bazzite doesn't. Fine — Margine is a creator distro. |
| `com.github.PintaProject.Pinta`, `Audacity`, `easyeffects`, `Reaper` | — | ✓ | Same — creator additions. |

**Actionable difference:** swap `net.davidotek.pupgui2` (ProtonUp-Qt) →
`com.vysp3r.ProtonPlus` in `installer/flatpaks-gaming` +
`build_files/gaming/margine-gaming.preinstall` when convenient.

### 6.11 🟨 NICE — `uupd` auto-update daemon

Universal Blue masks the bootc-native `bootc-fetch-apply-updates.timer`
in favour of [`uupd`](https://github.com/ublue-os/uupd), a single Go
daemon that orchestrates `bootc upgrade` + Flatpak update + distrobox
refresh with user notifications. Since Margine inherits from Bluefin DX,
**`uupd` is already there**. Quick check: confirm
`bootc-fetch-apply-updates.timer` is `masked` in the deployed image
(otherwise the two updaters race and double-pull).

### 6.12 🟨 NICE — Bluefin's `THEPATTERN.md` calls the old pattern "deprecated"

Bluefin team published [`THEPATTERN.md`](https://github.com/ublue-os/bluefin/blob/main/THEPATTERN.md)
on 2026-06-02 (commit `fc4e800`), contrasting the old `ublue-os/bluefin`
pipeline (key-based cosign, no E2E test gate, full rebuild per PR) with
the new `projectbluefin/bluefin` pipeline (keyless OIDC, 255-scenario
E2E test gate, digest-pinned base from `quay.io/fedora-ostree-desktops`).
The new pattern is bleeding edge and rpm-ostree's verification side is
*not yet aligned* (per Universal Blue Discourse: "needs more upstream
changes before we can encourage keyless"). **For Margine:** track when
upstream consumers switch to the new pattern — it'll signal that the
sigstore consumer side has caught up. Until then, key-based is correct.

### 6.13 🟨 NICE — `bluefin-dx` may go away

Bluefin team has publicly mused (Discussion #4607, Spring 2026 blog)
about removing `bluefin-dx` and moving developer tooling to opt-in via
Brew. Comment from the maintainer: *"we haven't even thought about
migration yet, no changes any time soon"* — but direction is set. **For
Margine:** plan for a world where `bluefin-dx:stable` no longer exists
and your Containerfile does `FROM bluefin:stable` + adds dev tooling
yourself. Not urgent (1-2 year horizon) but worth being mentally ready.

### 6.14 🟩 GOOD — `rechunk@v1.2.4` still canonical in 2026

The agents confirm `hhd-dev/rechunk@v1.2.4` (2025-10-11) is still the
canonical rechunker for Universal Blue derivatives. BlueBuild has
announced future deprecation in favor of `rpm-ostree compose
build-chunked-oci --format-version=2` (which Red Hat upstreamed), but
**Bluefin's own pipeline still calls `hhd-dev/rechunk`** as of HEAD.
Margine's pinning to `@v1.2.4` is correct; one-line refactor when the
ecosystem moves.

### 6.15 🟩 GOOD — bootc / rpm-ostree co-existence is officially supported

The agents confirm: `bootc upgrade` and `rpm-ostree upgrade` are
**interchangeable** on a bootc system today. `rpm-ostree` will continue
shipping in Fedora/CentOS bootc images with **no announced deprecation
timeline**. Margine documenting both paths in user docs is correct.

The one caveat: `bootc switch --enforce-container-sigpolicy` exists
only on `switch`/`install`, **not on `upgrade`** ([bootc-dev/bootc#528](https://github.com/bootc-dev/bootc/issues/528)).
Upgrades implicitly trust the existing policy. Worth a one-line user
doc warning.

### 6.16 🟩 GOOD — composefs handling

The `Fix B` rechunk wind-down ([2026-06-03-rechunk-and-fixb.md](../lessons-learned/2026-06-03-rechunk-and-fixb.md))
puts Margine on the correct composefs-canonical path. Agents confirm:
*"Hard rule: every RUN line that touches /usr or /etc must be followed
by a rechunk pass"* — which is exactly what Margine does. Without it,
composefs digest mismatch can fail boot on F42+. Margine is on the right
side of this since 2026-06-01.

### 6.17 Old/dead patterns to grep + replace (consolidated)

| Pattern | Where found in Margine | Replacement | Severity |
|---|---|---|---|
| `cosign-installer@v3` (floating major) | `build.yml:290`, `build-gaming.yml:206` | `@<SHA> # v3.10.1` | 🟥 |
| `bootc-image-builder-action@main` | `build-disk.yml:198` | `@<SHA> # vX.Y.Z` | 🟥 |
| `--cap-add sys_admin --security-opt label=disable` | `build-disk.yml:186-187` | `--security-opt label=type:unconfined_t` | 🟧 |
| `mkdir /root` + `mount -o remount,rw /proc/sys` | `installer/build.sh:32-33` | drop; test; add `osbuild-selinux` to runner if needed | 🟧 |
| anaconda-iso kickstart with rsync of `/var/lib/flatpak` | `disk_config/iso-gnome.toml` | bootc-image-builder + titanoboa hooks pattern | 🟨 (later) |
| `net.davidotek.pupgui2` | `installer/flatpaks-gaming`, `margine-gaming.preinstall` | `com.vysp3r.ProtonPlus` | 🟨 |
| `containers/bootc` repo links in docs | search & replace globally | `bootc-dev/bootc` | 🟨 |
| Missing SBOM step | `build.yml`, `build-gaming.yml` | add syft + oras attach + cosign-sign-SBOM block | 🟨 |

---

## 7. Supply chain + risk inventory

### 7.1 Pinning hygiene 🟩

| Dependency | Type | Pinning | Renovation |
|---|---|---|---|
| GHA actions (checkout, cosign, BIB, etc.) | external | SHA + comment | Dependabot bumps in lockstep |
| `bluefin-dx:stable` (FROM base) | upstream image | `:stable` tag | Pulled fresh every nightly cron; smoke-boot gate catches breakage |
| `kernel-cachyos` (COPR) | distro pkg | `dnf install kernel-cachyos` (no version pin) | Whatever COPR ships at build time |
| `oven/bun:1.3.13-debian` (margine-site deploy) | dev-tool image | Exact patch (pinned 2026-06-05) | Manual bump |
| `hhd-dev/rechunk@v1.2.4` | GHA action | Tag (not SHA) | Dependabot |
| `bootc-image-builder-action@main` | GHA action | **floating ref** ⚠️ | none |

The two non-SHA pins (rechunk tag + BIB action main) are real items.
rechunk@v1.2.4 is a *signed release* and rechunk's repo is well-managed,
so the risk is low; BIB action @main is more concerning because BIB
itself is changing rapidly (see §6). **Fix:** SHA-pin both.

### 7.2 Secrets handling 🟩

- MOK key + cert + password come from GHA `secrets`, get written to
  `/tmp/margine-secrets/` with `chmod 600`, mounted as BuildKit
  `--secret` into the kernel-signing layer, *and unconditionally wiped*
  via `if: always()` step at end. No leakage path.
- Cosign private key in `secrets.COSIGN_PRIVATE_KEY`, consumed only by
  the `sign` job (split from build). The build job never sees it.
- IA upload credentials (`IA_ACCESS_KEY` + `IA_SECRET_KEY`) live in
  `secrets`, materialized into `/tmp/ia.ini` with `chmod 0600` for the
  `ia` CLI call.

### 7.3 Downstream consumer trust 🟩

Consumers verify Margine by:
1. `rpm-ostree rebase ostree-image-signed:docker://ghcr.io/.../margine:stable`
   — the `-signed:` prefix tells rpm-ostree to verify against cosign.pub
   before checking out.
2. `cosign verify --key cosign.pub ghcr.io/.../margine:stable` directly.
3. `sha256sum -c SHA256SUMS` against the IA-published ISO + checksum
   sibling.

All three paths work today. Documentation surface for the user is:
`README.md` in `margine-image` (3-step install). Could be longer on
*verification* — e.g. an explicit "to verify, run X" block. **NICE:**
add a "verifying your install" subsection to the site's `/docs/install`
page.

### 7.4 Single points of failure 🟧

| SPOF | Impact | Mitigation today | Mitigation gap |
|---|---|---|---|
| GitHub Actions outage | No new `:stable` until they recover | Last good `:stable` digest stays signed on GHCR | None needed |
| `bieszczaders/kernel-cachyos` COPR taken down | Kernel install fails; no new `:stable` | Retry loop hides flakes; persistent outage → `:stable` ages but doesn't break installed systems | Long-term: mirror the CachyOS kernel SRPMs into a custom COPR/Koji you control |
| `quay.io/centos-bootc/bootc-image-builder:latest` regression | ISO builds fail | Retry loop helps for 5xx, not for content regression | Pin BIB digest in `build-disk.yml` |
| `archive.org` upload rate-limit / outage | New ISO not published | `--retries 5 --sleep 60` handles short outages | Long-term: secondary distribution (S3, Hetzner Object Storage); keep IA as primary |
| `bluefin-dx:stable` breaking-change | Next `:stable` build either fails or boots wrong | Smoke-boot gate catches "fails to multi-user.target"; doesn't catch UX regressions | Add a `validate-margine-system` invocation in the smoke-boot QEMU after login |

---

## 8. Recommendations, by priority

### Now (this week)

1. **🟥 SHA-pin `sigstore/cosign-installer`** to `7e8b541eb...` (v3.10.1)
   in `build.yml:290` and `build-gaming.yml:206`. Currently `@v3`
   floating, which doesn't guarantee cosign ≥ v3.0.6 / v2.6.3 and so
   exposes [CVE-2026-39395](https://github.com/sigstore/cosign/security/advisories/GHSA-w6c6-c85g-mmv6).
2. **🟥 SHA-pin `osbuild/bootc-image-builder-action@main`** in
   `build-disk.yml:198`. `@main` is fully floating.
3. **🟧 BIB flags unification** — `build-disk.yml:186-187` uses the
   pre-2025 `--cap-add sys_admin --security-opt label=disable`. The
   sibling `smoke-boot.yml:96` already uses the modern
   `--security-opt label=type:unconfined_t`. Align them. Same pass:
   drop `mkdir /root` + `mount -o remount,rw /proc/sys` from
   `installer/build.sh:32-33` and re-test ISO.
4. **🟧 Update `declarations/margine-atomic.yaml`** to reflect that
   scx-scheds + mangohud + goverlay + steam-devices are now in base
   (not gaming-only). Bump `schema_version: 1` while you're there.
5. **🟧 Deduplicate Flatpak BAKE lists** —
   `installer/flatpaks-base` is the source of truth; `build.sh` should
   `cp` it, not re-write it via here-doc. Same for `flatpaks-gaming`.
6. **🟨 Run `scripts/check-upstreams.sh`** and update review dates if
   nothing critical needs changing in upstream-inspirations.md.

### Soon (this month)

7. **🟧 Retry loop around `kernel-cachyos-addons` COPR install** in
   `custom-kernel/install.sh:~349`. Use the same `attempt`/`max_attempts`
   template as the main kernel install.
8. **🟧 Hermetic branding** — either retry+SHA-stamp the curl-based
   asset pulls in `build.sh:~696`, or convert to a git submodule of
   `margine-fedora-atomic` pinned at a specific SHA.
9. **🟧 ADR for the CachyOS-vs-OGC kernel decision** (§6.8). Write
   `docs/adr/0006-kernel-cachyos-decision.md` explicitly justifying
   why Margine stays on `bieszczaders/kernel-cachyos` rather than
   joining the 8-distro OGC consensus. CachyOS won the Steam survey
   (March 2026, 21.1% / #1) so the bet pays off *today*, but the
   risk inventory (single-maintainer COPR, no shared CI, prebuilt
   Nvidia removed 2026-02-23) needs to be on record.
10. **🟧 Verify `/etc/pki/containers/` + `policy.json` in shipped image** (§6.5).
    Test `bootc switch --enforce-container-sigpolicy ghcr.io/.../margine:stable`
    end-to-end from a vanilla Bluefin DX install. If it fails with
    "no signature found", patch `policy.json` and re-test.
11. **🟧 Verify `bootc-fetch-apply-updates.timer` is masked** on shipped
    images (§6.11). Two updaters racing = double pull, possibly
    download bandwidth wasted + locks on `/var/lib/containers`.
12. **🟨 Schedule the monthly GH cron** to auto-run `check-upstreams.sh`
    and open a GH issue when an upstream is ahead of "Last reviewed".
    Add **OGC kernel-packages** to the watch list while there.
13. **🟨 Add SBOM generation** to `build.yml` + `build-gaming.yml`
    (syft → `oras attach --artifact-type application/vnd.spdx+json`
    → `cosign sign` the SBOM digest). Matches Bluefin's reference
    pipeline (§6.1 steps 7-8, 16-18). ~30s CI cost, ~5 MB on GHCR.
14. **🟨 Migrate `pupgui2` → `ProtonPlus`** in
    `installer/flatpaks-gaming` and `margine-gaming.preinstall`.
    Active maintenance, modern Proton-GE manager (§6.10).
15. **🟨 Add an OCI label** for the `margine-fedora-atomic` commit SHA
    that produced the branding/scripts in the image, so consumers can
    audit. Example: `place.the-empty.margine.spec-ref=<sha>`.
16. **🟨 Clean up stale `margine-installer:run-<id>` tags** on GHCR.
    Either purge step at end of `build-disk.yml`, or single mutable
    `:latest` tag.

### Later (next quarter)

17. **🟨 Migrate to cosign keyless OIDC** when Universal Blue's main
    image-template does (track upstream; deliberate, not preemptive).
    Today rpm-ostree consumer side isn't fully aligned — wait for the
    Universal Blue Discourse signal "we now encourage keyless" before
    moving (§6.12).
18. **🟨 Drift detector** — a `validate-declared-state` validator that
    diffs the running system against `margine-atomic.yaml`. The
    `validate-margine-system` script is the right substrate; extending
    it with a "spec diff" pass would close §4.1's open ask.
19. **🟨 Run `validate-margine-system` inside `smoke-boot.yml`** after
    the QEMU reaches `multi-user.target` — catches UX regressions, not
    just boot-success regressions.
20. **🟨 Plan for `bluefin-dx` deprecation** (§6.13) — keep a draft
    Containerfile that does `FROM bluefin:stable` + adds dev tooling
    (libvirt, qemu-kvm, virt-manager, swtpm, edk2-ovmf, distrobox,
    podman-compose, vscode-from-brew). Don't ship; have ready.
21. **🟨 Consider scx_loader-disabled-by-default + tuned mode hooks**
    (§6.7). Match Bazzite's pattern for battery-life win on the base
    creator image.

### Architectural

14. **🟨 Consider rewriting `build.sh`** (1439 lines) as a series of
    `build_files/<NN>-<area>/install.sh` scripts called sequentially
    from the Containerfile, matching the upstream Universal Blue
    `build_files/shared/` convention. Easier to review, test, and
    contribute to. Not urgent — current organization works — but if
    `build.sh` grows another 500 lines this becomes important.

---

## 9. Things that are NOT broken — explicitly

For the avoidance of doubt — these were checked and are correct as-is:

- The `Fix B` rechunk wind-down is complete; `/etc/os-release` is the
  canonical symlink.
- `bootc container lint` runs at the end of both Containerfiles. ✓
- `bootc switch --mutate-in-place ... ghcr.io/.../margine:stable` in
  the ISO kickstart. ✓
- No `:latest` floating tag for the `FROM` base — `:stable` is the
  promoted-after-smoke-boot tag.
- `:candidate` → `:stable` promotion via `skopeo copy
  --preserve-digests` (byte-for-byte, not rebuild).
- MOK key/cert match validation pre-flight.
- Generic-not-host-only dracut + `--add ostree`.
- BAKE+DEFER hybrid Flatpak shipping (a *better* pattern than upstream
  Bazzite, IMO).
- `installer-image` pattern adopted faithfully from Bazzite (Containerfile
  + bwrap quirks).
- Cosign sign by-digest.
- Split CI jobs with `needs:` + retry-friendly `gh run rerun --failed`.
- ntfy push notifications with a meaningful decision matrix.

---

## 10. Open architectural questions for daniel

1. **CachyOS-vs-OGC kernel decision** — Bazzite + 7 other distros went
   OGC; CachyOS publicly skipped. CachyOS won the Steam survey (21.1%,
   #1, March 2026) so the bet works *today*. Three options:
   (a) stay on `bieszczaders/kernel-cachyos`, write the ADR; (b) join
   OGC kernel and align with Bazzite/Bluefin/Nobara; (c) move to
   Bluefin's own signed `ublue-akmods` kernel (boring, minimal delta).
   Decision-blocking for new ADR 0006.
2. **Cosign keyless OIDC migration timing** — when Universal Blue
   moves, same week, same quarter, never? Today rpm-ostree consumer
   verification side isn't aligned; wait for upstream signal.
3. **CachyOS kernel pin policy** — today every build picks whatever
   COPR ships. Do you want a `KERNEL_VERSION_MAX` env to prevent a
   wild jump on a Friday night cron?
4. **margine-os-personal vs the public bootc Margine** — separate
   brand long-term, or eventually merge product lines (one ISO that
   offers "Margine GNOME Fedora bootc" / "Margine Hyprland CachyOS
   native" at install time)?
5. **GHCR retention** — purge images older than N months (default GHCR
   keeps everything), or keep full history forever for audit?
6. **Secondary ISO mirror** — is one source (Internet Archive) enough
   long-term, or do you want an S3/Hetzner backup?
7. **`bluefin-dx` deprecation contingency** — if upstream eliminates
   `bluefin-dx` in favour of Brew-installed dev tooling (signal seen,
   no timeline), do we want Margine to absorb the dev stack ourselves
   or move to `FROM bluefin:stable` + opt-in?
8. **scx_loader default state** — Bazzite ships disabled, lets tuned
   profiles drive mode switches. Margine ships enabled (user can pick
   via `margine-scheduler.desktop`). Do you want to flip to the
   battery-friendlier Bazzite pattern by default?

---

*End of audit. Document is intentionally long and detailed because daniel
asked for an "iper completo" assessment. The §6 SOTA section in particular
is the most time-sensitive — it'll need to be refreshed every quarter as
upstream moves (a `check-upstreams.sh`-style cron is the right
maintenance discipline).*
