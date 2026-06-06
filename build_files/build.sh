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

# Run every sub-script in lexicographic order. Globs expand
# deterministically because we name dirs <NN>-<area>.
for d in /ctx/[1-9][0-9]-*/install.sh; do
  log "==> running $d"
  bash "$d"
done

log "==== Margine build orchestrator: done ===="
