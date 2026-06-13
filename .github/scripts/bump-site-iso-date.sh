#!/usr/bin/env bash
# Bump LATEST_ISO_DATE on the margine site and open (and auto-merge) a
# PR for it. Runs from inside a checkout of margine-os-1084ca72; the
# caller (build-disk.yml bump_site job) provides GH_TOKEN with push
# rights and RUN_URL pointing at the triggering workflow run.
#
#   usage: cd site && ../.github/scripts/bump-site-iso-date.sh
#
# Extracted from build-disk.yml's inline run: block (2026-06-12 review,
# phase 3) — heredocs for the commit/PR bodies become plain strings
# here, and shellcheck sees the whole program.
set -euo pipefail

: "${GH_TOKEN:?GH_TOKEN with push rights to the site repo is required}"
RUN_URL="${RUN_URL:-https://github.com/daniel-g-carrasco/margine-image/actions}"
SITE_REPO="daniel-g-carrasco/margine-os-1084ca72"

NEW_DATE="$(date -u +%Y%m%d)"
# Match the line shape exactly: `const LATEST_ISO_DATE = "YYYYMMDD";`
OLD_DATE="$(grep -oE 'LATEST_ISO_DATE = "[0-9]+"' src/routes/index.tsx \
  | head -1 | grep -oE '[0-9]+' || true)"

if [[ -z "$OLD_DATE" ]]; then
  echo "::error::Could not find LATEST_ISO_DATE in src/routes/index.tsx"
  exit 1
fi
if [[ "$OLD_DATE" == "$NEW_DATE" ]]; then
  echo "LATEST_ISO_DATE already at $NEW_DATE — no bump needed."
  exit 0
fi
echo "Bumping LATEST_ISO_DATE: $OLD_DATE → $NEW_DATE"

sed -i "s|LATEST_ISO_DATE = \"$OLD_DATE\"|LATEST_ISO_DATE = \"$NEW_DATE\"|" \
  src/routes/index.tsx
# Note: LATEST_ISO_BTIH used to be bumped here too, when the Hero had a
# magnet:? button composed from the btih. That button was retired
# 2026-06-07 — Fragments rejects valid magnets parsed from arbitrary
# trackers — and replaced with a direct link to the .torrent file
# (which the LATEST_ISO_TORRENT constant already computes from
# LATEST_ISO_DATE). So a single date bump now suffices.

# If a PR for the same target date already exists on the head branch
# (re-dispatch on same UTC day), skip — don't churn.
BRANCH="chore/bump-iso-date-$NEW_DATE"
if gh pr list --repo "$SITE_REPO" \
     --head "$BRANCH" --state open --json number --jq '.[0].number' \
   | grep -q '^[0-9]'; then
  echo "PR for branch $BRANCH already exists — leaving in place."
  exit 0
fi

git config user.email "noreply@margine.the-empty.place"
git config user.name "margine-bump-bot"
git checkout -b "$BRANCH"
git add src/routes/index.tsx

git commit -m "chore(release): bump LATEST_ISO_DATE to ${NEW_DATE}

Auto-bump triggered by margine-image build-disk.yml after a
successful IA publish.

Previous: ${OLD_DATE}
New:      ${NEW_DATE}"
git push -u origin "$BRANCH"

PR_BODY="Auto-opened by [margine-image build-disk](${RUN_URL}).

The site's hardcoded direct-link URLs point at the dated Internet
Archive item. This PR bumps the date constant after a successful IA
publish so the Hero CTAs and Install Option A reference the just-
released ISO.

Previous: \`${OLD_DATE}\`
New:      \`${NEW_DATE}\`

If everything looks right, squash-merge. The webhook deploy on VM 110
picks up the change in ~2-3 min."

gh pr create \
  --repo "$SITE_REPO" \
  --base main \
  --head "$BRANCH" \
  --title "chore(release): bump LATEST_ISO_DATE to ${NEW_DATE}" \
  --body "$PR_BODY"

# Merge the bump PR so the Hero buttons + Install Option A block point at
# the just-published ISO without manual intervention. This is a critical
# path: if it stays open, the live site keeps advertising the PREVIOUS
# ISO.
#
# Prefer GitHub auto-merge (waits for the lint check). It needs the repo's
# "Allow auto-merge" setting; when that's off, --auto errors out — so fall
# back to a direct squash merge after the lint check goes green. The change
# is a single date constant, so a direct merge once lint passes is safe.
if gh pr merge --repo "$SITE_REPO" "$BRANCH" --squash --auto --delete-branch; then
  echo "Auto-merge enabled on the bump PR."
else
  echo "::warning::auto-merge unavailable (repo 'Allow auto-merge' off?) — merging directly once lint is green"
  merged=false
  for _ in $(seq 1 30); do
    state="$(gh pr checks "$BRANCH" --repo "$SITE_REPO" --json bucket \
      --jq '[.[].bucket] | join(",")' 2>/dev/null || echo "")"
    case ",$state," in
      *,fail,*|*,cancelled,*)
        echo "::error::bump PR checks not green ($state) — leaving it open for review"
        break
        ;;
      *,pending,*|,,)
        sleep 15
        ;;
      *)
        if gh pr merge --repo "$SITE_REPO" "$BRANCH" --squash --delete-branch; then
          merged=true
        fi
        break
        ;;
    esac
  done
  if [ "$merged" != true ]; then
    echo "::warning::bump PR not merged automatically — merge ${BRANCH} manually so the site points at ${NEW_DATE}"
  fi
fi
