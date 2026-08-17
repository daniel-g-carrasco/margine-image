#!/usr/bin/env bash
# Margine image build orchestrator.
#
# Replaces the prior 1416-line monolith with a thin dispatcher over
# numbered per-section scripts under /ctx/<NN>-<area>/install.sh.
# See 00-common.sh for shared helpers + global env, and audit §8 rec
# #22 / docs/build-sh-decomposition.md for the rationale.
set -euo pipefail
. /ctx/00-common.sh

log "==== Margine build orchestrator: starting ===="

# The rpmdb is sqlite, and it does not always survive the layer commit
# that precedes this RUN. Since 2026-08-12 every CI build has opened
# this script with a torn database:
#
#   error: SELECT hnum, blob FROM 'Packages': 11: database disk image
#          is malformed
#
# and the first dnf transaction then "fails" on dependencies that are
# plainly installed (the package it blames moves around: seahorse,
# sqlite-libs, ...). The same commit and base digest build clean on a
# workstation, and disk space, metacopy, fsync=0 and the storage driver
# were each ruled out by experiment; what is left is the commit of the
# very large custom-kernel layer right before this one.
#
# `rpm --rebuilddb` reconstructs the index from the package headers. It
# costs seconds, it is a no-op on a healthy database, and it means a
# torn index heals here instead of failing the build 20 minutes in.
if command -v rpm >/dev/null 2>&1; then
  log "Rebuilding the rpmdb (layer-commit corruption guard)"
  rpm --rebuilddb
fi

# Run every sub-script in lexicographic order. Globs expand
# deterministically because we name dirs <NN>-<area>.
for d in /ctx/[1-9][0-9]-*/install.sh; do
  log "==> running $d"
  bash "$d"
done

log "==== Margine build orchestrator: done ===="
