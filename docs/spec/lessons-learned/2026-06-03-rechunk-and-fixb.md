# 2026-06-03 — Rechunk wind-down of Fix A (regular-file os-release)

## TL;DR

The Fix A workaround that wrote `/etc/os-release` and
`/usr/lib/os-release` as regular files (instead of the canonical
`/etc/os-release → ../usr/lib/os-release` symlink) is no longer
needed. The build pipeline has had `hhd-dev/rechunk@v1.2.4` in
`build.yml` since 2026-06-01, which re-commits the image into an
ostree-canonical state — composefs is fully set up by the time
switch-root reads `os-release`, so the symlink resolves normally,
the same way it does on upstream Fedora / Bluefin.

`build_files/build.sh` now restores the canonical symlink layout.
The Fix A workaround comments are preserved as a one-paragraph
historical note in the same file.

## Why this matters

Fix A only routed around the *one* bug we found at the time. Other
things that depend on `/usr` being available before composefs is up
would still have failed quietly:

- systemd units referencing `/usr/lib/systemd/system/...` paths
- GNOME Shell extensions under `/usr/share/gnome-shell/extensions/`
- post-deploy hooks that walk `/usr`

Without rechunk, our published image's `ostree.commit` label was also
inherited from Bluefin DX (not regenerated) — we had already had to
add one workaround for the related `ostree.linux` label
(margine-image commit `5096d7d`). Each non-rechunk workaround was
extra surface area that has now collapsed back into the standard
Fedora layout that Bluefin uses.

## Validation

The change ships on `feat/remove-fixa-osrelease-workaround`. Validated
end-to-end before merge:

1. Build dispatched manually on the branch.
2. `smoke-boot.yml` (workflow_run) auto-fired on build success and
   booted the resulting image in QEMU.
3. Smoke-boot reached `multi-user.target` (gdm.service, the existing
   marker) within the 20-min budget — no `os-release file is missing`
   regression.
4. Branch merged to main; the post-merge build promoted `:stable`.

## What we did NOT do (out of scope, possible follow-ups)

- Add a Layer A check that `ostree.commit` label matches the composefs
  hash. Optional belt-and-suspenders against a future regression
  where rechunk silently no-ops. Margin for now is "if rechunk
  breaks, smoke-boot catches it" — already strong enough.
- Re-evaluate the other "factory seed" workarounds in `build.sh`
  (Bug 6 `/etc/passwd` + `/etc/group` factory seeding, et al.). Those
  address a *different* failure mode (`ostree` 3-way merge over
  factory) which rechunk does not change.

## Cross-references

- [2026-05-28 initramfs and bootc labels](2026-05-28-initramfs-and-bootc-labels.md)
  — original investigation that produced Fix A.
- `margine-image/build_files/build.sh` — section 0 "OS identity".
- `margine-image/.github/workflows/build.yml` — `ReChunk image` step
  (uses `hhd-dev/rechunk@v1.2.4`).
