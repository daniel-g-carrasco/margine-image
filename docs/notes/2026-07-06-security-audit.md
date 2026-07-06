# Security + correctness audit, 2026-07-06

Deep audit of the unified `margine-image` repo across four surfaces
(CI/CD + supply chain, image build + install, runtime services +
privilege, `ujust` recipes). Every finding below was verified against
the code before action. Overall posture was already strong: no
`pull_request_target`, secrets gated off fork PRs, all `uses:` actions
SHA-pinned, kernel signing sound, no local-to-root escalation without
authentication. One HIGH (in code shipped the same day) and a set of
supply-chain / robustness items were fixed; a few low-risk bootstrap
trust roots are documented and accepted.

## Fixed

| Sev | Area | Finding | Fix |
|-----|------|---------|-----|
| HIGH | build-offline-docs.py | Path traversal: URL paths from the docs site (CSS `url()`, `<img>`/`srcset`, `routes.json`) were joined onto the output dir with no containment check; `pathlib` does not collapse `..`, so a hostile or MITM'd site could make the build-time, root-run writer plant a file at an arbitrary path (e.g. `/etc/cron.d/...`). Confirmed empirically. | `_within()` containment guard on every write target (asset + route), plus `normalize_docs_path` rejects `..` segments. Unit-tested: traversal refused, normal scrape unaffected (87 assets). |
| MEDIUM | build.yml | grype `install.sh` fetched from a movable `v0.114.0` tag and piped to `sh` inside the cosign-key job (comment even claimed it was pinned). | Pinned the installer URL to commit `ef8e65a` (the commit the tag points at). |
| MEDIUM | build-disk.yml, ia-prune-history.yml | `pip install internetarchive` unpinned in the jobs that hold the IA S3 keys — a trojaned upstream release would run with the account credentials. | Pinned `==5.9.0`. |
| MEDIUM | 30-gnome-defaults/install.sh | MoreWaita SVG baked into the image from a mutable `main` branch, no checksum. | Pinned to commit `53bc2ba` + `sha256sum -c` verify. |
| MEDIUM | scheduler-apply | Root helper (pkexec) wrote its args verbatim into `/etc/scx_loader/config.toml` and passed them to `scxctl` with no validation — defence-in-depth gap even though callers validate. | Whitelist sched/mode args at the privileged boundary. |
| MEDIUM | 60-custom.just | Recipe args interpolated raw (`{{ }}`) into shebang bodies (`margine-bootstrap`, `margine-scheduler`, `margine-test-vm-clean`) — a shell-metachar arg executes; inconsistent with siblings. Self-inflicted (caller already has sudo) but a real footgun, and `test-vm-clean` drives `virsh undefine --remove-all-storage`. | Export the params (`$MODE`/`$ALL`) so they arrive as inert env vars; quoted `margine-tpm-unlock`. Verified `just` neutralizes an injected arg. |
| MEDIUM | 60-custom.just | `margine-gaming` / `-native` abort under `set -e` on re-run (rpm-ostree errors on already-layered pkgs). | `rpm-ostree install --idempotent`. |
| MEDIUM | system_files | Committed `__pycache__/*.pyc` shipped into `/usr/libexec/__pycache__` (tracked despite `.gitignore`). | `git rm`. |
| LOW | 50-branding/install.sh | Image build coupled to docs-site uptime (uncaught scraper failure fails the ~28-min build). | Best-effort seed + warning; runtime `docs-refresh` backfills. |

## Accepted / documented (no change)

- **`install-koofr`** downloads and runs a vendor installer with no checksum (rolling "latest"). Runs as the user, not root. Fixing needs an upstream-provided checksum; documented as unverified vendor code.
- **RPMFusion / NVIDIA release RPMs and the CachyOS COPR kernel** are installed with dnf GPG + TLS trust but no independent version pin. Industry-standard bootstrap; re-signed with Margine's MOK afterward. Noted as a trust root.
- **docs-refresh** serves root-fetched, regex-rewritten remote HTML to the user's browser over a broad Flatpak `file://` grant. HTTPS-gated, not a local escalation; the service sandbox is already tight (`ProtectSystem=strict`, all caps dropped). Left as-is.
- Secret-on-argv nits (`skopeo -p`, curl `-H authorization` in ia-upload-iso.sh, IA config chmod-after-write): masked, single-tenant ephemeral runners; low practical risk, deferred.

## Verified clean

Kernel signing (`sbsign`→`sbverify`→stamped re-check, hard-fail); MOK/cosign private keys `.gitignore`d and never baked; extension/WSF fetches version-pinned + sha256; zip extraction zip-slip-safe; per-job least-privilege tokens; the polkit scheduler rule (`AUTH_ADMIN_KEEP`, local+active, exact program path); `margine-seed-etc-passwd` (root-only inputs, atomic replace); the LUKS/TPM and autologin helpers.
