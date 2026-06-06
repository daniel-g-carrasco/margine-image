# SBOM pipeline — revisit plan

> **Status (2026-06-06):** The SBOM sub-pipeline (syft → oras attach
> → cosign sign SBOM) is **NOT shipping** in Margine's build. The
> image itself remains cosign-signed by digest in both `build.yml`
> and `build-gaming.yml` — that's the actual consumer-trust gate.

## History

| PR | Action | Result |
|---|---|---|
| #49 | Add SBOM pipeline (`syft → oras attach → cosign sign SBOM`) following Bluefin's reference flow | Sign job timed out at 10 min in syft |
| #52 | Bump sign job `timeout-minutes` 10 → 30 | Sign job runner-shutdown-signal'd at ~11 min |
| #53 | Free 30 GB disk before sign via `ublue-os/remove-unwanted-software` | Same shutdown signal at ~14 min |
| #54 | Disable SBOM block entirely | Unblocked the pipeline |
| #58 | Re-enable with `syft --scope squashed` (top-layer view) | Sign job runner-shutdown-signal'd at ~13 min |
| #60 | Fix syft v0.42 `scan` subcommand syntax + bump action to v0.24.0 | Same shutdown signal at ~13 min |
| #62 | **Revert SBOM block** | This PR. SBOM block removed pending the refactor below. |

## Root cause

`syft` on an OCI image reference **always pulls every layer**, even
when `--scope squashed` is specified. `--scope` controls the
**representation** of the resulting SBOM (top-layer view vs all-
layers view), not the **input** that syft has to walk to construct
it. For a 14 GB rechunked Margine image (≥30 layers, ≥10 GB
compressed), the expanded in-memory tree exceeds the 16 GB RAM of
the stock `ubuntu-24.04` GHA runner — the runner kills syft with a
shutdown signal at ~13 min in.

PR #53 (free 30 GB disk) does not help because the bottleneck is
RAM, not disk. PR #58's `--scope squashed` does not help because
syft still has to pull every layer to compute the squashed view.

## The fix shape

Move `syft` **inside the `build_push` job**, after the rechunk
step. At that point:

- The image is already in local podman storage (no registry pull).
- `syft scan podman:<image>:<tag>` reads layer data from
  `~/.local/share/containers/storage`, no HTTP pull, no full
  expansion to RAM.
- Bluefin's reference workflow does exactly this — they generate
  the SBOM in `just build-ghcr` / `just gen-sbom` before the push.

Sign job stays cosmetic + fast: cosign-sign the manifest by digest,
download the SBOM file from a workflow artifact handoff, `oras
attach`, cosign-sign the SBOM by digest.

## Why not now

- The `build_push` job is already complex (kernel signing, rechunk,
  multi-tag skopeo push). Adding a syft step that has to slot in
  after rechunk and before push needs careful sequencing — same
  supervised-session risk profile as the `build.sh` split or
  titanoboa ISO.
- Margine has no pressing security obligation that requires SBOM in
  the next sprint. Consumer verification flow (`bootc switch
  --enforce-container-sigpolicy`) works on cosign-by-digest alone.

## Re-open trigger

Re-evaluate when any of these become true:

1. We integrate Margine with a tool that expects an SBOM (e.g. a
   compliance scanner that hits `oras discover` on every image
   before approving an install).
2. The supervised session for `build.sh` split / titanoboa
   evaluation is being scheduled — pair this with it.
3. GitHub raises the default `ubuntu-24.04` runner RAM (24 GB+
   would make the simple registry-pull path viable without the
   refactor).

## Reference

- Audit 2026-06-05 §6.1 + §8 rec #13
- Audit status delta (2026-06-06):
  margine-fedora-atomic `docs/audits/2026-06-05-margine-stack-audit-status-delta.md`
- Bluefin reference workflow:
  <https://github.com/ublue-os/bluefin/blob/main/.github/workflows/reusable-build.yml>
