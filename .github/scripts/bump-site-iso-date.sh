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

# Where the constant lives. It moved out of the landing-page route into a
# shared module when the site header started showing the ISO date on every
# page (site PR #182). Both locations are searched, in the new-first order,
# so this script works whichever side of that change the site checkout is
# on and the two repos can merge in either order.
DATE_FILE=""
for f in src/lib/release.ts src/routes/index.tsx; do
  if [[ -f "$f" ]] && grep -qE 'LATEST_ISO_DATE = "[0-9]+"' "$f"; then
    DATE_FILE="$f"
    break
  fi
done

if [[ -z "$DATE_FILE" ]]; then
  echo "::error::Could not find LATEST_ISO_DATE in src/lib/release.ts or src/routes/index.tsx"
  exit 1
fi
echo "LATEST_ISO_DATE lives in $DATE_FILE"

# Match the line shape exactly: `const LATEST_ISO_DATE = "YYYYMMDD";`
OLD_DATE="$(grep -oE 'LATEST_ISO_DATE = "[0-9]+"' "$DATE_FILE" \
  | head -1 | grep -oE '[0-9]+' || true)"

if [[ -z "$OLD_DATE" ]]; then
  echo "::error::LATEST_ISO_DATE in $DATE_FILE does not carry a date"
  exit 1
fi
if [[ "$OLD_DATE" == "$NEW_DATE" ]]; then
  echo "LATEST_ISO_DATE already at $NEW_DATE — no bump needed."
  exit 0
fi
echo "Bumping LATEST_ISO_DATE: $OLD_DATE → $NEW_DATE"

sed -i "s|LATEST_ISO_DATE = \"$OLD_DATE\"|LATEST_ISO_DATE = \"$NEW_DATE\"|" \
  "$DATE_FILE"

# Versioned ISO filename (margine-<date>.iso) — keeps the direct-HTTP link in
# sync with the renamed upload so the downloaded file carries the version.
if [[ -n "${NEW_FILE:-}" ]]; then
  if grep -q 'LATEST_ISO_FILE = "[^"]*"' src/routes/index.tsx; then
    sed -i "s|LATEST_ISO_FILE = \"[^\"]*\"|LATEST_ISO_FILE = \"$NEW_FILE\"|" \
      src/routes/index.tsx
    echo "Set LATEST_ISO_FILE = $NEW_FILE"
  else
    echo "::warning::LATEST_ISO_FILE constant not found in site — skipped (renamed?)"
  fi
fi

# Keep the edited files prettier-clean: the site lints with prettier and a
# raw sed edit has left index.tsx unformatted before (site PR #151 had to
# hand-fix it). Best effort: a formatting hiccup must not block a release
# bump.
#
# The version is read from the site's own package.json rather than pinned
# here. It used to be hardcoded at 3.8.4 while the site had moved to
# 3.8.5, which is a quiet way to commit formatting the site's own check
# would then reject. Whatever the site declares is by definition the
# version that agrees with the repo.
if command -v npx >/dev/null 2>&1; then
  PRETTIER_VER="$(grep -oE '"prettier": *"[0-9][^"]*"' package.json \
    | head -1 | grep -oE '[0-9][^"]*' || true)"
  PRETTIER_SPEC="prettier${PRETTIER_VER:+@${PRETTIER_VER}}"
  echo "Formatting with ${PRETTIER_SPEC}"
  npx --yes "$PRETTIER_SPEC" --write "$DATE_FILE" src/routes/index.tsx \
    || echo "::warning::prettier pass failed, committing the raw edit"
fi

# If a PR for the same target date already exists on the head branch
# (re-dispatch on same UTC day), skip — don't churn.
# Commit the bump straight to main and push — do NOT open a PR.
#
# Why direct push: the site repo is private on a free plan, so "Allow
# auto-merge" is OFF and branch protection is unavailable. The old
# branch+PR+auto-merge path therefore left an un-mergeable PR open after
# EVERY release while the live site kept advertising the PREVIOUS ISO
# (recurring failure, 2026-06-14). This is a deterministic one-line
# constant change made by a trusted bot, so a direct push to main is the
# robust path: it always lands, and the push triggers build-site.yml to
# redeploy in ~2-3 min. The OLD==NEW guard above keeps it idempotent on a
# same-day re-dispatch.
git config user.email "noreply@margine.dev"
git config user.name "margine-bump-bot"
# Stage the file that carries the date (src/lib/release.ts since site #182)
# AND index.tsx (LATEST_ISO_FILE). Staging only index.tsx is what shipped a
# site whose header said 2026-07-31 while the download button said
# margine-20260823.iso, with an HTTP link made of the old identifier and
# the new file name (2026-08-23 to 2026-08-29).
git add "$DATE_FILE" src/routes/index.tsx
git diff --cached --name-only | grep -qx "$DATE_FILE" \
  || { echo "::error::$DATE_FILE is not staged: the date bump would be lost"; exit 1; }
git commit -m "chore(release): bump LATEST_ISO_DATE to ${NEW_DATE}

Auto-bump by margine-image build-disk.yml after a successful IA publish.
Previous: ${OLD_DATE} -> New: ${NEW_DATE}
Triggering run: ${RUN_URL}"

# Push to main; if main advanced under us, rebase our single commit and
# retry. First attempt succeeds in the common (no-race) case.
for attempt in 1 2 3; do
  if git push origin "HEAD:main"; then
    echo "Pushed LATEST_ISO_DATE=${NEW_DATE} to ${SITE_REPO} main — site will redeploy."
    exit 0
  fi
  echo "::warning::push rejected (attempt ${attempt}) — rebasing on origin/main and retrying"
  git fetch origin main || true
  git rebase origin/main || { git rebase --abort || true; break; }
done
echo "::error::could not push the LATEST_ISO_DATE bump to ${SITE_REPO} main"
exit 1
