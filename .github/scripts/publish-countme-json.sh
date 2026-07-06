#!/usr/bin/env bash
# Refresh the site's countme.json (the /status "Devices running Margine"
# chart) from Fedora's public Count Me dataset.
#
# Every Fedora-based install pings the mirrors once a week; Margine ships
# VARIANT_ID=margine + rpm-ostree-countme.timer, so it shows up in the
# public weekly totals under its own name. This script pulls the tail of
# that dataset, aggregates the Margine rows, merges them with the history
# already committed on the site, and publishes the result. Same
# run-from-inside-the-site-checkout + direct-push pattern as its sibling
# publish-status-json.sh (see there for why direct push, not a PR).
#
# devices = per week, max across repos of sum(hits) with sys_age >= 0:
# a tagged ping is sent once per system per week per countme-enabled
# repo, so summing one repo counts systems and the max is robust to a
# repo being disabled on some machines. sys_age=-1 rows are untagged
# metadata fetches, not devices, and are excluded.
#
# Usage: cd site && ../.github/scripts/publish-countme-json.sh
set -euo pipefail

CSV_URL="${COUNTME_CSV_URL:-https://data-analysis.fedoraproject.org/csv-reports/countme/totals.csv}"
# The full CSV is ~600 MB, append-only by week (~5 MB/week across all
# distros). A suffix range covers the recent weeks; older Margine weeks
# survive through the merge with the committed JSON below.
TAIL_BYTES="${COUNTME_TAIL_BYTES:-60000000}"
TARGET="src/generated/countme.json"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

curl -fsSL --retry 3 --max-time 300 -r "-${TAIL_BYTES}" "$CSV_URL" -o "$TMP/tail.csv"

# NF/date filters drop the header and the partial first line of the
# range. Columns: week_start,week_end,hits,os_name,os_version,
# os_variant,os_arch,sys_age,repo_tag,repo_arch.
awk -F, 'NF==10 && $1 ~ /^20..-..-..$/ && $4=="Margine" && $8+0>=0 { sum[$1"|"$2"|"$9]+=$3 }
  END { for (k in sum) { split(k,a,"|"); w=a[1]"|"a[2]; if (sum[k]>best[w]) best[w]=sum[k] }
        for (w in best) { split(w,b,"|"); printf "{\"start\":\"%s\",\"end\":\"%s\",\"devices\":%d}\n", b[1], b[2], best[w] } }' \
  "$TMP/tail.csv" | jq -s 'sort_by(.start)' > "$TMP/new-weeks.json"

NEW_COUNT="$(jq length "$TMP/new-weeks.json")"
if [ "$NEW_COUNT" -eq 0 ]; then
  echo "::warning::no Margine weeks in the CSV tail — keeping the committed countme.json"
  exit 0
fi
echo "aggregated ${NEW_COUNT} week(s) from the dataset tail"

# Merge: committed history wins for weeks the tail no longer covers;
# fresh data replaces overlapping weeks (a week keeps collecting
# late-arriving hits for a few days after it closes). group_by is
# stable, so with old before new, map(last) picks the fresh row.
OLD_WEEKS="$(git show "HEAD:$TARGET" 2>/dev/null | jq '.weeks // []' 2>/dev/null || echo '[]')"
jq -n --argjson old "$OLD_WEEKS" --slurpfile new "$TMP/new-weeks.json" \
  --arg gen "$(date -u +%FT%TZ)" --arg src "$CSV_URL" '
  (($old + $new[0]) | group_by(.start) | map(last) | sort_by(.start)) as $weeks |
  { generatedAt: $gen,
    source: $src,
    note: "devices = weekly Fedora countme pings with os_name=Margine, sys_age>=0, max across repos",
    weeks: $weeks }' > "$TMP/countme.json"

# Material-change check (ignore the timestamp) — no commit on a no-op tick.
OLD_NORM="$(git show "HEAD:$TARGET" 2>/dev/null | jq -S 'del(.generatedAt)' 2>/dev/null || echo '{}')"
NEW_NORM="$(jq -S 'del(.generatedAt)' "$TMP/countme.json")"
if [ "$OLD_NORM" = "$NEW_NORM" ]; then
  echo "countme.json unchanged (ignoring timestamp) — nothing to publish."
  exit 0
fi

cp "$TMP/countme.json" "$TARGET"
git config user.email "noreply@margine.the-empty.place"
git config user.name "margine-countme-bot"
git add "$TARGET"
git commit -m "chore(countme): refresh weekly device data"

for attempt in 1 2 3; do
  if git push origin "HEAD:main"; then
    echo "Published countme.json — site will redeploy."
    exit 0
  fi
  echo "::warning::push rejected (attempt ${attempt}) — rebasing on origin/main and retrying"
  git fetch origin main || true
  git rebase origin/main || { git rebase --abort || true; break; }
done
echo "::error::could not publish countme.json"
exit 1
