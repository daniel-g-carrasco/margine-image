# Margine Live Environment Scaffold

This directory is scaffolding for the ADR-0008 Titanoboa live-ISO migration.
Phase 0 only stores read-only upstream reference copies for Phase 1 and later.

The files under `references/` are not active build inputs. They are copied from
known upstream commits so future phases can port the live environment,
Anaconda profile, and Titanoboa workflow shape without relying on floating
`main` branches.

Do not edit files under `references/` directly. If an upstream reference needs
to be refreshed, replace the copied file from a new source SHA and update that
source directory's `PROVENANCE.md`.
