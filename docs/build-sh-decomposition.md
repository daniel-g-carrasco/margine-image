# `build_files/build.sh` decomposition (2026-06-06)

## What changed

The previously monolithic `build_files/build.sh` (1416 lines, 11
numbered sections + helpers) was split into:

- **`build_files/00-common.sh`** — shared helpers and exported
  globals. Sourced by every sub-script.
- **`build_files/NN-<area>/install.sh`** — one script per logical
  area, named in lexicographic order so the orchestrator dispatches
  them deterministically:

  | Dir | Original sections | Lines |
  |---|---|---|
  | `10-os-identity/` | 0 + 0.bis + 0.ter (os-release, /etc/passwd factory seed, copy system_files/) | ~153 |
  | `20-flatpaks/` | 1 (BAKE + DEFER Flatpak lists) | ~149 |
  | `30-gnome-defaults/` | 2 (zz1-margine.gschema.override + tiling/dock/keybindings) | ~256 |
  | `40-spec-scripts/` | 3 (margine-* helpers from margine-fedora-atomic) | ~74 |
  | `50-branding/` | 4 + 4.bis (visual identity + Bluefin strip) | ~425 |
  | `60-ujust-services/` | 5 + 5b + 5c (ujust recipes, autostart, mask remount-fs) | ~52 |
  | `70-passwd-seed-boot/` | 5d (boot-time `/etc/passwd` seed for rechunk stripping) | ~258 |

- **`build_files/build.sh`** (was 1416 lines, now 14) — thin
  orchestrator that sources `00-common.sh` and loops:

  ```bash
  for d in /ctx/[1-9][0-9]-*/install.sh; do
    bash "$d"
  done
  ```

## Why

Audit `§8 rec #22` flagged the 1416-line single script as the largest
technical-debt surface in the build pipeline:

- Hard to review (no PR touches a small piece without bumping the
  whole file's blame).
- Sections sharing implicit state via globals (`FEDORA_VER`,
  `BUILD_DATE`, `MARGINE_REPO`, `MARGINE_REF`) made it impossible to
  understand any section in isolation.
- Adding a new section meant scrolling 1000+ lines past unrelated
  code.

The split mirrors the canonical pattern in `ublue-os/bluefin` (their
`build_files/shared/*.sh`) and `ublue-os/image-template`. Each section
script is `bash -n`-clean independently and now blame-stable.

## How sub-scripts find shared state

Every `NN-<area>/install.sh` starts with:

```bash
#!/usr/bin/env bash
set -euo pipefail
. /ctx/00-common.sh
```

`/ctx/` is the bind mount of `build_files/` set by the Containerfile
(`COPY build_files /` into the `ctx` stage), so the absolute path
always resolves. `00-common.sh` defines:

- `log()`, `retry_curl()` helper functions
- `set -euo pipefail` (idempotent, but the install.sh also sets it
  defensively in case `00-common.sh` ever loses the line)
- `FEDORA_VER`, `BUILD_DATE`, `MARGINE_REPO`, `MARGINE_REF` exported
  globals (cached: each one is computed once at first import of the
  orchestrator, not in every sub-script)

Variables that are not in `00-common.sh` (e.g. flag locals inside a
section) remain section-local; sub-scripts are sandboxed by virtue
of being launched as separate `bash` processes from the orchestrator.

## Adding a new section

1. Pick an unused two-digit prefix (current sections use `10`, `20`,
   …, `70` — leaves the gaps for natural insertion).
2. Create `build_files/<NN>-<area>/install.sh` with the standard
   four-line header (`#!/usr/bin/env bash` + `set -euo pipefail` +
   `. /ctx/00-common.sh`).
3. The orchestrator auto-picks it up via the glob.

## Removing a section

`git rm -r build_files/<NN>-<area>/`. The orchestrator's glob no
longer includes it. No other change required.

## Audit reference

- Audit 2026-06-05 §8 recommendation #22 (architectural)
- This PR closes that recommendation.

## What is NOT in this change

The split is a refactor: **no semantics changed**. Every line of
the original `build.sh` is now in one of the sub-scripts (or in
`00-common.sh` for the helpers), in the same execution order. The
final image manifest should be byte-identical to a build of the
parent commit (modulo build-time timestamps).

Validation gate is smoke-boot: if QEMU reaches `multi-user.target`
on the rechunked image produced from this branch, the split is
semantically OK.
