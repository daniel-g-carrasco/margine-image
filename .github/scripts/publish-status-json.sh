#!/usr/bin/env bash
# Publish the generated status.json to the website repo (drives /status).
#
# Run from INSIDE a checkout of the website repo. Same robust pattern as
# bump-site-iso-date.sh: commit straight to main and push (the site repo is
# private on a free plan — no "Allow auto-merge", no branch protection — so a
# PR round-trip just strands an un-mergeable PR), with a rebase-retry on a
# race. To avoid a commit on every scheduled tick, the publish is skipped
# when only `generatedAt` changed.
#
# Usage: ../.github/scripts/publish-status-json.sh <path-to-new-status.json>
set -euo pipefail

SITE_REPO="${SITE_REPO:-daniel-g-carrasco/margine-os-1084ca72}"
SRC="${1:?usage: publish-status-json.sh <path-to-status.json>}"
TARGET="src/generated/status.json"

# Preserve the curated margine kernel: the producer can't label it at build
# time, so when the freshly generated doc has an empty kernel, carry over the
# value already committed on the site (see build-status-json.sh).
OLD_KERNEL="$(git show "HEAD:$TARGET" 2>/dev/null \
  | jq -r 'first(.chain[] | select(.key=="margine") | .kernel) // ""' 2>/dev/null || echo '')"
NEW_KERNEL="$(jq -r 'first(.chain[] | select(.key=="margine") | .kernel) // ""' "$SRC" 2>/dev/null || echo '')"
if [ -z "$NEW_KERNEL" ] && [ -n "$OLD_KERNEL" ]; then
  patched="$(mktemp)"
  jq --arg k "$OLD_KERNEL" '(.chain[] | select(.key=="margine") | .kernel) = $k' "$SRC" > "$patched"
  SRC="$patched"
  echo "Preserved margine kernel from site: $OLD_KERNEL"
fi

# Material-change check: compare new vs committed, ignoring generatedAt.
norm() { jq -S 'del(.generatedAt)' "$1" 2>/dev/null || echo '{}'; }
OLD_NORM="$(git show "HEAD:$TARGET" 2>/dev/null | jq -S 'del(.generatedAt)' 2>/dev/null || echo '{}')"
NEW_NORM="$(norm "$SRC")"
if [ "$OLD_NORM" = "$NEW_NORM" ]; then
  echo "status.json unchanged (ignoring timestamp) — nothing to publish."
  exit 0
fi

cp "$SRC" "$TARGET"
git config user.email "noreply@margine.the-empty.place"
git config user.name "margine-status-bot"
git add "$TARGET"
git commit -m "chore(status): refresh status.json"

for attempt in 1 2 3; do
  if git push origin "HEAD:main"; then
    echo "Published status.json to ${SITE_REPO} main — site will redeploy."
    exit 0
  fi
  echo "::warning::push rejected (attempt ${attempt}) — rebasing on origin/main and retrying"
  git fetch origin main || true
  git rebase origin/main || { git rebase --abort || true; break; }
done
echo "::error::could not publish status.json to ${SITE_REPO} main"
exit 1
