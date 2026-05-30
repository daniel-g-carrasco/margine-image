#!/usr/bin/env bash
# check-upstreams.sh — print upstream-project activity since the most
# recent "Last reviewed" date recorded in docs/upstream-inspirations.md.
#
# This is the manual-review companion to docs/upstream-inspirations.md.
# Use it quarterly (or after a build failure that smells like an
# upstream behaviour change) to know whether one of the projects we
# inherit from or derive code from has moved meaningfully since we
# last checked.
#
# Requires: gh CLI authenticated, jq.

set -euo pipefail

# Resolve repo root (works from anywhere)
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOC="${REPO_ROOT}/docs/upstream-inspirations.md"

if [[ ! -f "$DOC" ]]; then
  echo "ERROR: $DOC not found" >&2
  exit 1
fi

declare -A repos=(
  [bluefin]="ublue-os/bluefin"
  [origami]="john-holt4/Origami-Linux"   # GitHub mirror; canonical is on GitLab
  [morros]="morrolinux/morros"
  [image-template]="ublue-os/image-template"
  [rechunk]="hhd-dev/rechunk"
  [bazzite]="ublue-os/bazzite"
)

LAST_REVIEWED=$(grep -oE '202[0-9]-[0-9]{2}-[0-9]{2}' "$DOC" | sort -u | tail -1)
if [[ -z "$LAST_REVIEWED" ]]; then
  echo "ERROR: no 'Last reviewed' date found in $DOC" >&2
  exit 1
fi

echo "Most recent 'Last reviewed' date in $DOC: $LAST_REVIEWED"
echo
echo "Counting commits per upstream since that date..."
echo

any_activity=0
for name in $(echo "${!repos[@]}" | tr ' ' '\n' | sort); do
  repo="${repos[$name]}"
  count=$(gh api -X GET "/repos/${repo}/commits" \
                 -f since="${LAST_REVIEWED}T00:00:00Z" \
                 --jq 'length' 2>/dev/null || echo "?")
  if [[ "$count" =~ ^[0-9]+$ ]] && (( count > 0 )); then
    any_activity=1
    printf "  %-15s %-30s  %s new commit(s)  →  https://github.com/%s/commits/main\n" \
      "$name" "$repo" "$count" "$repo"
  else
    printf "  %-15s %-30s  %s\n" "$name" "$repo" "${count} commit(s) (no review needed)"
  fi
done

echo
if (( any_activity )); then
  cat <<EOF
For each upstream with new commits, skim the commit log on GitHub.
If anything affects what's listed in docs/upstream-inspirations.md
(custom-kernel script for Origami, build pattern for MorrOS, action
arguments for rechunk, gschema baseline for Bluefin, …) update the
'Last reviewed' date in that table row to today: $(date -u +%Y-%m-%d)
EOF
else
  echo "No new activity; nothing to do."
fi
