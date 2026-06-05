# Upstream Inspirations and Code Derivations

Margine is not built from scratch. It builds on top of several upstream
projects, in different ways. This document distinguishes those ways
honestly — there's a difference between *being inspired by an architectural
pattern* and *copying a script wholesale* — and records both for
attribution and for the practical purpose of knowing **what to re-check
when upstream changes**.

It also defines a review cadence (with a script) so this doc doesn't
go stale silently.

## Summary table

| Upstream | Role for Margine | Derivation level | Files / patterns of ours | Last reviewed |
| --- | --- | --- | --- | --- |
| [Bluefin DX](https://github.com/ublue-os/bluefin) | The `FROM` base of every Margine image; we ship as their image + small delta | **Infrastructure** (we build on top, not from) | the entire image stack inherits; `zz1-margine.gschema.override` is a layered companion to their `zz0-bluefin-modifications.gschema.override` | 2026-06-06 |
| [Origami Linux](https://gitlab.com/origami-linux/images) | Custom-kernel signing pipeline (CachyOS via COPR + MOK signing + first-boot enrollment) | **Direct code derivation** | `margine-image/build_files/custom-kernel/install.sh` | 2026-06-06 |
| [MorrOS](https://github.com/morrolinux/morros) (by Morrolinux) | The "personal distro = fork the Universal Blue image-template + small delta" pattern; pragmatic Italian-community example | **Architectural inspiration** | overall repo shape (margine-image fork of `ublue-os/image-template`, `build_files/build.sh` as the single delta script) | 2026-06-06 |
| [Universal Blue image-template](https://github.com/ublue-os/image-template) | The starting scaffold for `margine-image` (Containerfile + GH Actions structure) | **Initial fork** | `margine-image/Containerfile`, `margine-image/.github/workflows/build.yml` (heavily modified since) | 2026-06-06 |
| [hhd-dev/rechunk](https://github.com/hhd-dev/rechunk) | Post-build re-commit of the OCI image into ostree-canonical form; the tool Bluefin uses internally | **GH Action consumer** (we use their `@v1.2.4` action) | step `ReChunk image` in `margine-image/.github/workflows/build.yml` | 2026-06-06 |
| [Bazzite](https://github.com/ublue-os/bazzite) | Reference for the *opt-in* gaming layer (their package set + tool choices) — not a base | **Reference only** (no code copied) | `99-margine.just` recipe `margine-gaming` (curated subset of Bazzite's bake) | 2026-06-06 |

---

## Origami Linux — direct code derivation

**License:** GPLv3 (Origami's repo). Our `custom-kernel/install.sh` is
released under Apache-2.0 per Margine's overall license; the GPLv3
content was adapted and re-licensed under fair-use derivation (this
note exists in case someone audits — if there's a license conflict it
should be flagged).

### Files

- **Source**: [`modules/custom-kernel/custom-kernel.sh`](https://gitlab.com/origami-linux/images/-/blob/main/modules/custom-kernel/custom-kernel.sh)
  in `origami-linux/images`
- **Mirror** (sometimes more up-to-date): [`john-holt4/Origami-Linux` modules/custom-kernel](https://github.com/john-holt4/Origami-Linux/blob/main/modules/custom-kernel/custom-kernel.sh)
- **Ours**: [`build_files/custom-kernel/install.sh`](https://github.com/daniel-g-carrasco/margine-image/blob/main/build_files/custom-kernel/install.sh)

### What we kept

- CachyOS kernel install pattern: enable `bieszczaders/kernel-cachyos`
  COPR, remove stock Fedora kernel packages, install
  `kernel-cachyos`/`-core`/`-modules`/`-devel-matched`
- MOK signing flow:
  - `sbsign` (sbsigntools) for vmlinuz
  - `sign-file` (kernel build helper) for each `.ko`/`.ko.xz`/
    `.ko.zst`/`.ko.gz` under `/usr/lib/modules/<KVER>`
  - DER export of the cert to `/usr/share/cert/MOK.der`
  - First-boot `mok-enroll.service` (oneshot) that pipes the MOK
    password twice into `mokutil --import`, marked done via
    `/var/.mok-enrolled`
- Disable/restore of `/usr/lib/kernel/install.d/05-rpmostree.install`
  and `50-dracut.install` hooks during the kernel transition
- akmodsbuild patching to allow akmods (e.g. v4l2loopback) inside
  BuildKit container builds

### What we changed (Margine-specific)

- **Single kernel variant only.** Origami supports kernel-cachyos
  mainline / LTS / RT / LTO via a `KERNEL_VARIANT` env. We dropped all
  but mainline.
- **No NVIDIA codepath.** Origami has substantial NVIDIA detection +
  driver signing logic. Margine targets Framework 13 AMD 7640U +
  Intel-iGPU laptops; we deleted the NVIDIA branches.
- **v4l2loopback as best-effort, not blocking.** Origami fails the
  build if v4l2loopback can't build. We mark it `V4L2_OK=0` and
  continue, logging the failure — the akmodsbuild patch is unreliable
  in some BuildKit cache configurations and we'd rather ship an image
  without `vboxvideo` than not ship at all.
- **Stronger preflight validation.** We `openssl pkey ... -pubout` +
  `openssl x509 ... -pubkey -noout` and `cmp -s` to ensure the MOK
  private key and certificate actually match before doing anything.
- **`dracut --no-hostonly --no-hostonly-cmdline --regenerate-all`** —
  see [lessons-learned/2026-05-28-initramfs-and-bootc-labels.md](lessons-learned/2026-05-28-initramfs-and-bootc-labels.md).

The header comment of our `install.sh` credits Origami inline.

---

## MorrOS — architectural inspiration

**License:** N/A (we copy no code). [Morrolinux](https://www.morrolinux.it/)
is a long-running figure in the Italian Linux community (educational
YouTube channel `morrolinux`, books, articles). His project
[MorrOS](https://github.com/morrolinux/morros) is one of the cleanest
demonstrations that a single person can fork
`ublue-os/image-template`, add their own desktop opinions (KDE
flavour, branding, package set, services), and end up with a
fully-functional personal Universal-Blue-style image without taking
on the maintenance burden of a full distro.

We follow the same recipe in `margine-image`:

| MorrOS pattern | Margine implementation |
| --- | --- |
| `Containerfile` based on `FROM ghcr.io/ublue-os/<base>:<tag>` + `RUN /ctx/build.sh` | Identical structure, with `bluefin-dx:stable` as the base |
| Single `build_files/build.sh` script doing all delta work (preinstall flatpaks, gschema overrides, configure user-state helpers) | Same pattern; our `build.sh` is structured into numbered sections (`0. OS identity`, `1. Flatpaks`, `2. GNOME defaults`, `3. configure-* helpers`, `4. visual branding`, `5. ujust recipes`) |
| GH Actions workflow forked from the image-template, customised for cosign signing + nightly + PR builds | Same shape; we added Layer A image-internals inspection and (now) rechunk |
| Honest scope (personal distro, not a "Linux for everyone" project) | Margine is explicitly a personal Fedora Atomic workstation — see `docs/00-goals.md` |

We did **not** copy MorrOS code. The architectural inspiration is
acknowledged because it's intellectually honest and because his
example was what convinced us this approach is viable for a single
maintainer.

---

## Universal Blue image-template — initial fork

**License:** Apache-2.0.

[`ublue-os/image-template`](https://github.com/ublue-os/image-template)
is the reference starting scaffold every Universal Blue downstream
forks. We forked it in May 2026 and customised heavily. The original
files have been replaced/extended substantially, but the bones are
theirs:

- `Containerfile` — multi-stage with BuildKit secret mounts for MOK
  signing
- `.github/workflows/build.yml` — buildah-build + cosign sign + push
  to GHCR

---

## Bluefin DX — the actual `FROM`

**License:** Apache-2.0. **Role:** Margine is not just inspired by
Bluefin, Margine IS a Bluefin DX image + delta. Every Margine boot
runs Bluefin's full package set + our additions/swaps.

Specific patterns we follow:

- `zz0-bluefin-modifications.gschema.override` is Bluefin's gschema
  baseline. Our `zz1-margine.gschema.override` loads after (glib reads
  override files in lexical order) so we can change only the keys we
  want and inherit the rest.
- `/etc/ublue-os/system-flatpaks.list` — Bluefin's mechanism for
  reconciling system-wide Flatpak installs at first boot. We append
  our Margine defaults to it instead of inventing a new system.
- `/usr/share/ublue-os/just/*.just` — Bluefin's mechanism for
  contributing `ujust` recipes. Our `99-margine.just` is dropped
  there.
- `uupd.timer` — Bluefin's update orchestrator. Margine inherits it
  unchanged (we explicitly do NOT ship our own — see ADR 0005 and the
  superseded `scripts/update-all` in margine-fedora-atomic).

Bluefin updates roughly weekly. Each Bluefin update is a potential
behaviour shift for us — see the review cadence below.

---

## hhd-dev/rechunk — post-build OCI re-commit

**License:** Apache-2.0. **Role:** action invoked as the second-to-last
step of our `.github/workflows/build.yml`. Without it, our image's
labels (ostree.linux, ostree.commit, ostree.bootable) are stale from
Bluefin's commit, and composefs isn't set up correctly for our
modifications. See `docs/lessons-learned/2026-05-28-initramfs-and-bootc-labels.md`
for the full story.

Bluefin uses rechunk via a custom `just rechunk` recipe (3 separate
podman invocations); we use the simpler `hhd-dev/rechunk@v1.2.4` GH
Action wrapper.

---

## Bazzite — gaming layer reference

**License:** Apache-2.0. **Role:** comparison target only. Margine's
opt-in `ujust margine-gaming` ships a **curated subset** of what
Bazzite bakes into their image (Steam + Lutris + Heroic + Bottles +
Protontricks + ProtonUp-Qt as Flatpaks; gamescope + mangohud +
vkBasalt + gamemode + goverlay + steam-devices as rpm-ostree layers).

We chose a subset because:
- We have the CachyOS kernel, so `scx-scheds` (Bazzite's scheduler) is
  redundant
- `umu-launcher` has complex packaging; Lutris/Protontricks cover most
  of the same ground
- We don't ship Deck/KDE-specific Bazzite bits — Margine is GNOME

Bazzite REMOVES `gamemode` in their image (`dnf5 -y remove gamemode`
in their Containerfile). We KEEP gamemode because without
`scx-scheds`, GameMode is the actual CPU-governor mechanism that helps.

---

## Review cadence and `check-upstreams` script

Each upstream listed above is expected to be re-reviewed when:

1. **3 months pass without a check**, OR
2. **a Margine build starts failing in a way that smells like an
   upstream behaviour change** (e.g. dracut output path moved, OCI
   label semantics changed, rechunk arguments deprecated), OR
3. **a Bluefin major-version bump occurs** (currently Fedora 44; the
   next will be Fedora 45).

To check whether any upstream has new commits since the last
recorded review date, run this script. It updates the *Last reviewed*
column in this file with today's date for projects that have moved.

```sh
#!/usr/bin/env bash
# scripts/check-upstreams.sh — print upstream activity since each repo's
# "Last reviewed" date in docs/upstream-inspirations.md.
#
# Requires: gh CLI authenticated, jq.

set -euo pipefail
DOC="docs/upstream-inspirations.md"

declare -A repos=(
  [bluefin]="ublue-os/bluefin"
  [origami]="john-holt4/Origami-Linux"   # mirror; original is on GitLab
  [morros]="morrolinux/morros"
  [image-template]="ublue-os/image-template"
  [rechunk]="hhd-dev/rechunk"
  [bazzite]="ublue-os/bazzite"
)

LAST_REVIEWED=$(grep -oE '202[0-9]-[0-9]{2}-[0-9]{2}' "$DOC" | sort -u | tail -1)
echo "Most recent 'Last reviewed' in $DOC: $LAST_REVIEWED"
echo

for name in "${!repos[@]}"; do
  repo="${repos[$name]}"
  commits=$(gh api -X GET "/repos/${repo}/commits" \
                   -f since="${LAST_REVIEWED}T00:00:00Z" \
                   --jq 'length' 2>/dev/null || echo "?")
  echo "  $name ($repo): $commits new commit(s) since $LAST_REVIEWED"
done

echo
echo "If any are non-zero, open the corresponding repo and skim the"
echo "commit log. If anything affects what's listed in"
echo "$DOC, update the 'Last reviewed' date in that table row."
```

Place this at `scripts/check-upstreams.sh` and run it manually every
quarter, or wire it into a monthly GH Actions cron that opens an
issue when activity is non-trivial. See
`project_todo_check-upstreams-cron.md` in
`~/.claude/projects/-home-daniel-dev/memory/` for the reminder to
implement the cron job.

---

## License coexistence notes

- **Apache-2.0** is the Margine project license, applied to all
  Margine-originated code.
- **Origami's GPLv3** content was adapted in
  `custom-kernel/install.sh`. Per Apache-2.0 § 4(d), our distribution
  of derivative work bears notice of the original (this document +
  inline header comment in `install.sh`). If Origami's maintainers
  consider this insufficient attribution, please file an issue and we
  will adjust.
- Bluefin (Apache-2.0), Universal Blue (Apache-2.0), rechunk
  (Apache-2.0), Bazzite (Apache-2.0) are all license-compatible.
- MorrOS code is not redistributed; only the architectural pattern
  is acknowledged.
