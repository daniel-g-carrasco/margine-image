# Code-quality review and rewrite plan — 2026-06-12

**Scope:** `margine-image`, `margine-fedora-atomic`, the website repo (private), their CI, and the
runtime tooling shipped in the image.
**Method:** five parallel deep reviews (CI workflows · build scripts · runtime tooling + validators ·
website · cross-repo hygiene), each grounded in tool runs rather than reading alone: `actionlint`
1.7.12 (with shellcheck on `run:` blocks), `shellcheck -S style` over every tracked script,
`tsc --noEmit`, `eslint`, `desktop-file-validate`, a headless `gjs` reproduction, dist-bundle
inspection of the deployed site, and GitHub API checks (branch protection, bots, secret scanning).
**Status:** PROPOSAL — nothing in this document has been applied yet.

---

## Verdict

Per-file quality is well above the solo-maintainer bar. Strict TypeScript passes with zero errors
on a 15k-LOC site; every bash entry script sets `-euo pipefail`; shellcheck across both OS repos
returns zero errors (18 style/info items total); systemd units carry incident-dated rationale
comments; secret handling in the Containerfile (tmpfs-mounted BuildKit secrets) is exemplary;
fail-loud fetch policy exists and is documented.

The systemic weakness is **hand-synced duplication**: expectations (flatpak lists, extension UUIDs,
branding checks, route lists, image refs) are copied across 2–4 places with "keep in sync" comments,
and the review found four spots where they have **already drifted**. The second weakness is
**lint-invisible embedded code**: ~250 lines of Python/units/JS/desktop files live inside heredocs
in build scripts or YAML, where no linter, test, or reviewer tooling can see them — and the two real
bugs below sat in exactly such blind spots (a `just` recipe body and a workflow expression).

---

## A. Bugs found during review (fix first — independent of any rewrite)

| # | Where | What | Fix size |
|---|-------|------|----------|
| A1 | `margine-image/.github/workflows/smoke-boot.yml:88` vs `:437` | **The auto-gate boots `:stable` but promotes `:candidate`.** On `workflow_run` (every automatic run) `github.event.inputs` is empty, so the boot test exercises the *previous* `:stable` while the promote step copies the *untested* `:candidate` to `:stable`. The Layer B gate has been void on the automatic path since promotion was introduced; only manual dispatch tests what it promotes. Found independently by two reviewers. | 1 word (`:stable`→`:candidate` at line 88); full fix = resolve ref to digest once, use everywhere (also closes A2) |
| A2 | `smoke-boot.yml:425-446` | Promotion re-resolves the `:candidate` tag **three times** (once per tag loop iteration) instead of copying the tested digest — a build finishing mid-smoke promotes an untested digest or skews the three tags. No `concurrency` group on the only workflow that mutates `:stable`. | ~15 lines |
| A3 | `margine-image/build_files/60-custom.just:369,376` | `systemctl --user-or-sudo` **is not a flag** (verified on host: "unrecognized option"). The recipe body runs without `-e`, so `ujust margine-scheduler <mode>` silently never enables `scx_loader.service` (no persistence across reboots) and `ujust margine-scheduler off` prints success while the disable failed. | 2 words (`sudo systemctl`) |
| A4 | `margine-fedora-atomic/scripts/validate-branding:22-27` | The gjs `Gtk.IconTheme` probe **false-FAILs wherever there is no display**: `Gtk.init()` exits before any print, `RES` is empty, both icons report "does NOT resolve". The Layer C GUI probe runs it as a root systemd unit with no display → the branding leg of Layer C is a guaranteed false FAIL, poisoning the "two green runs then make it gating" plan. Reproduced headless during review. | ~4 lines (check gjs rc; `skip:` not `err` when display absent) |
| A5 | `smoke-boot.yml:127` vs `:229-236` | Layer C cleanup trap covers `/mnt/smoke` but **not `/mnt/smokeboot`** (mounted rw), and is installed *after* `qemu-nbd --connect`. A failure mid-injection leaves a dirty ext4 journal on the boot partition of the same qcow2 that Layer B then boots — silently, because the step is `continue-on-error`. | 2 lines |
| A6 | website `.gitignore` | **`.env` is still not ignored** (only `*.local`). The exact incident that broke prod (#55, committed `.env` forcing `VITE_RECOMMEND_REBASE=true`) can recur with any `git add .`. | 1 line |
| A7 | `60-custom.just:546-548` (`margine-tpm2-enroll`) | The crypttab `sed` requires exactly 4 fields; a legal 3-field line matches the guard `grep` but not the `sed` → TPM enrolled, crypttab unchanged, user still prompted, recipe prints "Done." No post-edit verification. | 3 lines (verify-after-edit or fail with instructions) |
| A8 | `60-custom.just:571-583` (`margine-doctor`) | If the validator glob matches nothing (fetch regression — the exact failure class it exists to catch) the loop never runs and doctor reports all-good. Also writes predictable `/tmp/<name>.out` paths. | ~10 lines (`mktemp -d`, fail-if-zero-validators) |

Honest disclosure for the record: because of A1, the 2026-06-12 cumulative build was promoted to
`:stable` after a boot test of the *previous* image. It passed the full Layer A in-container
validation, and its changes were overlay-validated on real hardware beforehand, but the QEMU boot
gate did not actually exercise it.

---

## B. Evidence of the drift problem (why Phase 4 exists)

- Expected-flatpak list: validator checks **33** apps (`validate-margine-system:56`), the image
  ships **42** (`20-flatpaks/install.sh:91-132`) — the "Keep in sync" comment rotted by 9 apps.
- The `start-here-symbolic` no-raster grep exists **char-for-char in three places** (build.yml CI
  sentinel, `validate-margine-system:273`, `50-branding/install.sh:402`).
- Extension UUID list maintained in **three places** (build.yml:316, validate-margine-system:102,
  declarations YAML via validate-declared-state).
- `margine-first-boot-status.desktop` ships from **two sources**; the heredoc in
  `70-passwd-seed-boot/install.sh:279` silently overwrites the richer tracked file in
  `system_files/` (icon and localized name lost).
- Adding one docs page to the site touches **4 hand-synced files** (`PAGES`, `WIKI_PAGES`,
  `prerender.mjs` ROUTES, `sitemap.xml`) plus the offline-mirror route list in margine-image.
- `actions/checkout` pinned at **three different SHAs** across the estate (two within one file).
- `declarations/margine-atomic.yaml` `updates.validators_on_demand` lists 4 validators; the image
  ships 7.
- Two "validators" (`validate-gaming-runtime`, `validate-hardware-media-stack`) **cannot fail**
  (no failure counter, unconditional `exit 0`), and one checks the retired ProtonUp-Qt app id.
- `validate-margine-system:643` still probes a gschema CI removed with rationale ("does not exist
  in GNOME 47/48") → permanent WARN on healthy systems.

---

## C. Rewrite plan (phased; each phase independently shippable)

### Phase 0 — Bug fixes (table A) · effort: ~half a day · risk: none
A1–A8 verbatim. A1+A2 together as one digest-pinning patch to smoke-boot; the rest are one-liners
to ~10-liners. CI-validated by the next build+smoke cycle.

### Phase 1 — Guardrails: make the invisible visible · ~1 day · risk: none
The class of bug found in A1/A3 (plausible-looking code outside any checker) gets a permanent net:
1. **`lint.yml` in each repo** (all SHA-pinned, ~2 min runtime):
   - margine-image: `actionlint` (covers workflow expressions + inline bash via shellcheck) +
     shebang-aware shellcheck (the current Justfile `find -iname '*.sh'` misses the **6 extensionless
     scripts shipped into the image** and lints vendored `live-env/references/`) + `ruff` on the one
     Python file.
   - margine-fedora-atomic: shebang-aware shellcheck + ruff over `scripts/` (all extensionless) +
     actionlint.
   - website: `bun install --frozen-lockfile && bunx tsc --noEmit && bun run lint` — the site
     currently has **zero CI on PRs** (build-site only runs on push to main); a strict-clean repo
     gets no protection.
2. **One-time `bun run format`** on the site (539 of 539 eslint errors are prettier noise burying
   the signal), then demote formatting to `format:check` + `eslint-config-prettier`; re-enable
   `@typescript-eslint/no-unused-vars` (currently `off` — the one rule that would have flagged the
   dead code below).
3. **`.shellcheckrc`** in margine-image (`external-sources=true`, `source-path=build_files`) — kills
   all 9 structural SC1091 infos; fix the 2 real SC2086s; repo goes shellcheck-clean and stays so.
4. **Justfile repair** (margine-image): it is still ublue **template boilerplate** — `image_name`
   defaults to `image-template` (line 1), three recipes reference the nonexistent
   `disk_config/iso.toml`, `just build` cannot build this image at all (no `--secret` mounts for the
   MOK key). Adapt or trim to a minimal honest Justfile; make `lint`/`format` shebang-aware.
5. **Branch hygiene**: enable delete-branch-on-merge on all three repos + one-time prune of ~45
   merged topic branches.

### Phase 2 — Supply chain & pinning · ~1 day · risk: low
1. **Pass the already-resolved spec SHA into the build.** CI resolves `margine-fedora-atomic@main`
   to a SHA and stamps it as an OCI label, but the build itself **fetches whatever `main` is
   mid-build** (13 fetch call sites across 6 scripts; ~25-min TOCTOU window; non-reproducible
   rebuilds; the label can lie). Fix is mechanical: `ARG MARGINE_REF` in the Containerfile +
   `--build-arg MARGINE_REF=${{ steps.specref.outputs.sha }}` in build.yml. Local builds keep the
   `main` default. (Vendoring the 16 scripts was considered and rejected: daily co-evolution, sync
   toil; an immutable SHA over TLS is sufficient.)
2. `retry_curl` → `retry_curl_strict` for the 16 fetched **executables** (a 200-with-empty-body
   currently installs zero-byte scripts silently; the strict variant exists for exactly this).
3. Pin the remaining floaters: `hhd-dev/rechunk@v1.2.4` → SHA (the only action violating the pin
   policy); the grype `curl | sh` from `main` → versioned installer (it runs in the job holding the
   cosign key, and installs into a PATH dir that precedes cosign's); smoke-boot's
   `bootc-image-builder:latest --pull=newer` → the digest build-disk already pins; hide-cursor
   extension resolved "latest from EGO" at build time → pin `HIDECURSOR_VERSION_TAG` + sha256 both
   extension zips (the `45-wsf` pattern is the house model).
4. **Consolidate on Renovate, delete dependabot.yml.** Both are configured; only Dependabot has
   ever opened a PR (the Renovate app was never installed). Renovate covers what Dependabot can't:
   GHA digest-pinning presets, Containerfile digest updates (would unify the three checkout SHAs),
   and bun lockfiles, including the private site repo. Requires installing the Mend app (Daniel).
   Decision point: `config:best-practices` will digest-pin `FROM bluefin-dx:stable` — upstream then
   arrives as visible automergeable PRs instead of silently via the floating tag (arguably better;
   opt out with one packageRule if unwanted).
5. **Stop pretending the MOK passphrase is secret**: it is public by design (printed in the live
   ISO dialog), yet plumbed through GHA secrets + BuildKit secret mounts into a world-readable
   unit file — implying a confidentiality that doesn't exist and inviting a pointless "rotation".
   Hardcode the documented passphrase in the unit with a comment; keep key/cert as real secrets.

### Phase 3 — Structural dedup: extract embedded code · ~2–3 days · risk: low-medium
1. **Workflow inline bash → `.github/scripts/`** (shellcheck-gated by Phase 1):
   `validate-image-rootfs.sh` (~134 lines from build.yml), `inject-gui-probe.sh` + the probe script
   and unit as real files (~131 lines from smoke-boot — currently triple-escaped heredocs no linter
   can see), `bump-site-iso-date.sh` (~92 lines from build-disk), and **one shared
   `qemu-boot-wait.sh`** for the two QEMU boot-test call sites — which also fixes a real bug both
   copies share: `kill -9 $!` kills the `sudo` wrapper, not qemu; orphaned qemu holds the step open
   until job timeout (40–90 min) on every failure path. Fix once with `-pidfile` + trap. The two
   sites also carry divergent OVMF discovery (one fragile `ls|grep`, one robust loop) — keep the
   robust one.
2. **ntfy composite action** (3 near-identical ~40-line blocks; keep the decision matrices
   in-workflow).
3. **Heredoc payloads → `system_files/`** as real, lintable files: ~250 lines of Python
   (staleness-check, upgrade-notify, passwd-seeder), user units, autostart entries
   (`70-passwd-seed-boot`, parts of `50-branding`). Resolves the duplicate-desktop-file trap (B.4)
   by construction. The passwd merge logic currently exists **twice** (build-time heredoc + boot
   seeder) — ship the seeder once, call it at build too.
4. `custom-kernel/origami-upstream.sh` (502 lines, zero references, near-duplicate of install.sh's
   helpers): back-port its one good idea (post-sign sha256 self-check), then move to
   `live-env/references/` or delete (git history keeps it).
5. Shared `retry()` helper in `00-common.sh` (the 16-line retry loop is copy-pasted 3× in
   custom-kernel/install.sh); make `KERNEL_PACKAGES` an array.
6. Delete `publish-titanoboa-test-iso.yml` (self-declared superseded by Phase 5 of ADR-0008).
7. Permissions tightening: `build_disk` still has `packages: write` for a removed step; unused
   `id-token: write` in three jobs; notify jobs inherit defaults → `permissions: {}`.
8. Containerfile cache granularity: the kernel RUN bind-mounts the whole `ctx`, so any
   build_files edit invalidates the 25-min kernel layer → mount only `custom-kernel/`.

### Phase 4 — Validators as the single source of truth · ~2–3 days · risk: medium
Target: **the expectations live once** (in the shipped `declarations.yaml`), the validators read
them, and CI executes the validators in-container instead of duplicating greps.
1. Move expected flatpaks / extension UUIDs / dconf sentinels into the YAML; `20-flatpaks` *generates*
   the preinstall file from it. Retires three hand-synced lists; the 42-vs-33 drift becomes
   structurally impossible.
2. Generalize the existing `MARGINE_VALIDATE_CONTEXT` switch into contexts `image` (build container:
   file checks only) / `live` (booted host) / `smoke-boot`. Honest limits mapped during review: in a
   container you cannot check running kernel, bootc status, mokutil/EFI, failed units, session
   dconf, actual flatpak installs, or the gjs icon probe (headless — see A4); those stay in
   live/smoke contexts.
3. CI step becomes `podman run --rm -e MARGINE_VALIDATE_CONTEXT=image $IMG margine-validate-…`,
   replacing ~120 lines of grep in build.yml — and implicitly asserting the validators were fetched
   executable (A8's root cause). CI-only sentinels with no validator twin (docs-mirror completeness,
   search-light marker, dconf keyfiles) move *into* the validators' image context, so
   `margine-doctor` and Layer C inherit them for free.
4. Adoption mirrors the Layer C policy: run validators in-container alongside the greps until two
   green runs, then delete the greps.
5. Give the two can't-fail validators real failure conditions (or rename `margine-diag-*`), fix the
   ProtonUp-Qt→ProtonPlus app id, delete the stale §9b2 gschema probe, align the YAML
   `validators_on_demand` list with the 7 shipped.

### Phase 5 — Site: one content pipeline · ~3–5 days · risk: medium
The headline finding: `src/routes/docs/$slug.tsx` is **2,971 lines, 89% of which is a `PAGES`
record holding all 16 docs pages as inline JSX** — and because `beforeLoad`/`head()` reference it,
the **entire docs corpus ships in the 477 KB entry chunk on every page** (verified in dist; the
docs route's own lazy chunk is 587 bytes). Meanwhile the handbook already has the right
architecture: markdown → build script → committed JSON → lazy 20–35 KB per-chapter chunks.
1. Generalize `build-handbook.mjs` → `build-content.mjs`; move the 16 docs pages to
   `content/docs/*.md` with front-matter (title, lead, group, faq). The content is already
   markdown-shaped (counted: 86 `<Section>`→`##`, 43 `<Pre>`→fences, 10 figures, 1 FAQ page); the
   renderer needs two small extensions (figure-with-pending-placeholder; FAQ `<details>` + JSON-LD
   from front-matter, killing a manually-synced duplicate).
2. `docs/$slug.tsx` shrinks to ~120 lines (clone of `handbook/$slug.tsx`); nav, pager, sitemap and
   prerender routes all derive from the generated manifest — page addition becomes **1 file instead
   of 4** (+ the offline mirror can consume an emitted `routes.json` instead of a hardcoded list).
3. Search: delete the fragile React-tree walker (it couples to component identity across chunks);
   the existing h2-split HTML parser handles both kinds. Anchor-stability: keep the docs `sectionId`
   slugger semantics and diff rendered ids before cutover (offline-mirror and search deep-links
   depend on them). Offline-docs compatibility is preserved by construction (prerendered static
   HTML, script-free `<details>` FAQ).
4. **Dead-code purge**: 44 of 46 `src/components/ui/*` files have zero importers (verified
   per-file), plus `use-mobile.tsx`, the example server fn, and **~35 removable dependencies**
   (25 of 26 radix packages, recharts, embla, react-hook-form, zod, date-fns, react-query — wired
   but zero queries). Already tree-shaken from dist, so this is hygiene + install time + lint
   signal, not bundle size. Add `knip` to keep it that way.
5. Small shared primitives: one `SectionLayout` (docs+handbook layouts are ~120 duplicated lines),
   one `pageMeta()` helper (OG block copy-pasted in 6 route files, one variant already drifted),
   `<Kicker>`/`<EmberLink>`/`<PrevNextNav>`; move `LATEST_ISO_*` constants to one
   `src/content/release.ts` so the auto-bump PR touches one file.
6. MDX considered and rejected: it recompiles content as JS components, reproducing the exact
   bundle problem this phase removes.

### Phase 6 — Language & polish sweep · ~half a day · risk: none
1. **EN/IT inconsistency worklist** (feeds the pending OS-language decision): `margine-doctor`
   verdicts, `scheduler-picker` + 8 desktop actions, all `margine-first-boot-status` notification
   text (Italian) vs the English siblings; the IA `index.html` template and one ntfy message
   (Italian) in English-only workflows; the site shipping `Screenshot in arrivo` on the English
   docs (5 figures). Decide the policy, then sweep once.
2. Stale-comment sweep: 5 in workflows (incl. an orphaned SBOM block contradicting the real one,
   three timeout comments none matching the code), 4 `installer/build.sh` references in build
   scripts, `ID_LIKE` comment-vs-code, `Containerfile.plan-b` COPY of a removed file (plan-B would
   fail at line 37 if ever invoked — repair or stamp it).
3. Unit nits: `Persistent=true` on a monotonic-only timer; user-manager `network-online.target`
   deps that don't exist there; `strptime` that breaks on fractional-seconds timestamps and
   mis-handles UTC (`datetime.fromisoformat` + `timezone.utc`); converge the two older notifiers
   from `/etc/skel` wiring to `/usr/lib/systemd/user` (the pattern the newest already uses);
   stamp-after-notify in staged-update-notify; `docs-open` honoring `MARGINE_DOCS_BASE_URL` like
   its sibling.

---

## D. Explicit non-goals (anti-churn)

- **Keep** the numbered `build_files/` layout + 20-line orchestrator, the ujust/Bluefin idioms
  (single `60-custom.just` is upstream-imposed), and the incident-dated comment culture.
- **Keep the regex HTML rewriter** in `build-offline-docs.py` — over self-controlled Vite output it
  is simpler to audit than a parse/serialize round-trip. Add tests instead (pure functions are
  already separable): pytest + one golden Vite-page fixture, `lru_cache` the per-page CSS re-fetch
  (29 downloads of the same file today), optional thread-pool fetch.
- **No trap-based cleanup in build-container scripts** — a failed RUN discards the whole layer;
  half-restored state cannot ship. Document this once in `00-common.sh` so it stops being
  re-litigated.
- No PR/issue templates (solo, self-merged PRs), no markdownlint over 43 prose files (noise),
  no GitHub Releases (the registry + IA are the artifact store; optional: a lightweight
  `stable-YYYYMMDD` tag pushed by the promotion step for git↔image traceability), no test-framework
  buildout beyond the targeted pytest above + one prerender text-snapshot test (which also de-risks
  the Phase 5 migration).
- gjs payloads: no build-time JS parser exists worth adding; the fixed-string-patch +
  CI-asserted outcome marker is the right mitigation.

## E. Already state-of-the-art (found, kept, worth naming)

Tmpfs-mounted build secrets; by-digest cosign signing with `--digestfile`; job-split-for-cheap-retry
with documented recovery commands; label-gated PR builds; `bootc container lint` as final stage;
`45-wsf` pinned+checksummed fetch pattern; `docs-refresh` rsync-into-mountpoint with rationale;
`margine-docs-refresh.service` hardening; the ordering-cycle incident comment in the passwd seeder;
strict TS + lazy handbook chunks + vendored third-party assets + reduced-motion handling on the
site; GitHub-native secret scanning + push protection + required signed commits on the public repos.

---

*Raw per-area findings (5 review transcripts with full file:line tables) are preserved in the
session that produced this document; everything load-bearing is cited inline above.*
