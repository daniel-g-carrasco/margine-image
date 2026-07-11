#!/usr/bin/env bash
# Stall-aware, ration-aware Internet Archive uploader for the multi-GB ISO.
#
# Why not plain `ia upload`: its --retries only fires on ERROR RESPONSES
# (S3 503s). A hung TCP connection never errors, so the CLI blocks until
# the JOB timeout kills it — run 28758416337 (2026-07-06) sat 5h50m on a
# dead socket and the ISO never published. curl gives what ia cannot:
# --speed-limit/--speed-time abort the transfer when it actually STALLS
# (moving-but-slow uploads are left alone), and a retry loop gets a fresh
# connection instead of a wedged one.
#
# Two distinct failure modes, handled differently (both seen 2026-07-06):
#   - STALL / transient error: back off a short fixed interval and retry.
#   - IA GLOBAL rationing (`?check_limit=1` -> over_limit:1, "total_tasks_
#     queued exceeds global_limit"): IA-wide congestion, our own queues
#     empty. This is "come back later", not "give up" — so we back off
#     LONGER and escalating, and keep trying until a wall-clock budget is
#     spent, rather than burning a small fixed attempt count in minutes
#     while the event lasts. Runs 28779615535 / 28781114094 both failed
#     this way; the ISO was built, only the upload was blocked.
#
# The loop is bounded by IA_MAX_WALL (default 40 min), well under the
# job's 350-min cap, so a genuine multi-hour IA outage still fails loudly
# (re-run the job — the verify short-circuit skips whatever already
# landed) instead of hanging.
#
# Verify short-circuit: before every attempt (and after every success)
# the remote object is HEADed and compared against local size + md5 (IA's
# ETag is the content md5 for plain PUTs). So a retry after an "upload
# finished but the 200 got lost" costs seconds, not a full re-PUT, and a
# same-day re-publish of an identical ISO is a no-op.
#
# The item must already exist with its metadata (created by the cheap
# `ia upload SHA256SUMS --metadata ...` in build-disk.yml); this script
# only moves the big file. x-archive-keep-old-version:0 mirrors the ia
# --no-backup rationale there (reproducible ISOs need no clobber history).
#
# Usage: ia-upload-iso.sh <identifier> <local-file> [remote-name]
# Env:   IA_S3_ACCESS, IA_S3_SECRET   (required)
#        IA_S3_BASE          override endpoint (tests)  [https://s3.us.archive.org]
#        IA_STALL_LIMIT_BPS  abort under this rate...   [10240]
#        IA_STALL_WINDOW_S   ...sustained this long     [300]
#        IA_MAX_WALL_S       total retry budget         [2400]
#        IA_RETRY_SLEEP_S    base backoff (stall/error) [90]
#        IA_RATION_SLEEP_S   first backoff when rationed, then escalates [120]
set -euo pipefail

IDENTIFIER="${1:?usage: ia-upload-iso.sh <identifier> <file> [remote-name]}"
FILE="${2:?usage: ia-upload-iso.sh <identifier> <file> [remote-name]}"
REMOTE="${3:-$(basename "$FILE")}"
: "${IA_S3_ACCESS:?IA_S3_ACCESS required}"
: "${IA_S3_SECRET:?IA_S3_SECRET required}"
BASE="${IA_S3_BASE:-https://s3.us.archive.org}"
LIMIT="${IA_STALL_LIMIT_BPS:-10240}"
WINDOW="${IA_STALL_WINDOW_S:-300}"
MAX_WALL="${IA_MAX_WALL_S:-2400}"
RETRY_SLEEP="${IA_RETRY_SLEEP_S:-90}"
RATION_SLEEP="${IA_RATION_SLEEP_S:-120}"

SIZE="$(stat -c %s "$FILE")"
echo "upload: ${FILE} (${SIZE} bytes) -> ${BASE}/${IDENTIFIER}/${REMOTE}"
echo "hashing local file (md5, for the verify short-circuit)..."
MD5="$(md5sum "$FILE" | awk '{print $1}')"

already_uploaded() {
  # Complete when the item METADATA lists the file with matching size and
  # md5. This replaced the S3 HEAD probe on 2026-07-11 after it silently
  # broke the verify for a whole day (run 29129693269, 3 red attempts on
  # an ISO that was PUBLISHED and intact): s3.us.archive.org started
  # answering HEAD with a 307 to the storage node, and without -L the
  # probe read the redirect's own headers (content-length: 403) so the
  # size never matched; following the redirect is no better, the node
  # answers HEAD with Content-Length: 1. The metadata API has neither
  # problem: no redirects, and explicit size + md5 that IA computed from
  # the bytes it actually stored. The old etag heuristics (multipart
  # etags, 2026-07-06) are obsolete with it. Metadata appears only after
  # IA finishes ingesting, which is exactly the "complete" we want; the
  # caller's retry loop rides out the ingest delay. Every mismatch is
  # LOGGED: the silent `return 1` cost hours of blind diagnosis today.
  local meta size md5
  meta="$(curl -fsS -m 60 "https://archive.org/metadata/${IDENTIFIER}" 2>/dev/null)" || {
    echo "verify: metadata fetch failed (transient?)"; return 1; }
  size="$(jq -r --arg n "$REMOTE" '.files[]? | select(.name==$n) | .size' <<<"$meta" 2>/dev/null | head -1)"
  md5="$(jq -r --arg n "$REMOTE" '.files[]? | select(.name==$n) | .md5' <<<"$meta" 2>/dev/null | head -1)"
  if [ -z "$size" ] || [ "$size" = "null" ]; then
    echo "verify: ${REMOTE} not in item metadata yet (still ingesting?)"; return 1
  fi
  if [ "$size" != "$SIZE" ]; then
    echo "verify: size mismatch (remote ${size} vs local ${SIZE})"; return 1
  fi
  if [ -n "$md5" ] && [ "$md5" != "null" ] && [ "$md5" != "$MD5" ]; then
    echo "verify: md5 mismatch (remote ${md5} vs local ${MD5}) — remote copy is corrupt, re-uploading"; return 1
  fi
  echo "verify: metadata match (size + md5) — remote object is complete"
  return 0
}

ia_over_limit() {
  # IA publishes live S3 ingest pressure at ?check_limit=1. over_limit:1
  # means the global queue is saturated (our own accesskey/bucket queues
  # can still be 0) — a transient, wait-it-out condition.
  local j
  j="$(curl -fsS -m 30 "${BASE}/?check_limit=1&accesskey=${IA_S3_ACCESS}" 2>/dev/null)" || return 1
  printf '%s' "$j" | grep -q '"over_limit"[[:space:]]*:[[:space:]]*1'
}

START=$SECONDS
attempt=0
ration_backoff=$RATION_SLEEP
while :; do
  if already_uploaded; then
    echo "remote object already complete (size + md5 match) — nothing to do."
    exit 0
  fi
  attempt=$((attempt + 1))
  elapsed=$((SECONDS - START))
  echo "── attempt ${attempt} (elapsed ${elapsed}s / ${MAX_WALL}s budget): PUT (aborts if <${LIMIT} B/s for ${WINDOW}s)"
  rc=0
  curl -fS --connect-timeout 30 \
    --speed-limit "$LIMIT" --speed-time "$WINDOW" \
    -H "authorization: LOW ${IA_S3_ACCESS}:${IA_S3_SECRET}" \
    -H "x-archive-auto-make-bucket:1" \
    -H "x-archive-keep-old-version:0" \
    -H "x-archive-size-hint:${SIZE}" \
    -T "$FILE" "${BASE}/${IDENTIFIER}/${REMOTE}" || rc=$?
  echo
  if [ "$rc" -eq 0 ] && already_uploaded; then
    echo "upload complete + verified (attempt ${attempt}, $((SECONDS - START))s)."
    exit 0
  fi

  # Out of budget? stop before sleeping so we don't overshoot the cap.
  if [ $((SECONDS - START)) -ge "$MAX_WALL" ]; then break; fi

  # Choose the backoff by cause. A global over-limit is "IA busy, retry
  # later": back off longer and escalate. Anything else (stall rc=28,
  # http error rc=22, connection reset) backs off the short fixed base.
  if ia_over_limit; then
    echo "::warning::attempt ${attempt} failed (rc=${rc}) — IA S3 globally rationed; waiting ${ration_backoff}s"
    sleep "$ration_backoff"
    ration_backoff=$(( ration_backoff * 2 )); [ "$ration_backoff" -gt 600 ] && ration_backoff=600
  else
    echo "::warning::attempt ${attempt} failed (rc=${rc}; 28=stall abort, 22=http error) — retrying in ${RETRY_SLEEP}s"
    sleep "$RETRY_SLEEP"
    ration_backoff=$RATION_SLEEP   # reset escalation once the global limit clears
  fi
done

echo "::error::IA upload of ${REMOTE} not verified within ${MAX_WALL}s budget"
echo "::error::IA S3 stayed degraded across the budget — re-run THIS job when https://s3.us.archive.org/?check_limit=1 shows over_limit:0 (the verify short-circuit resumes, it won't re-send what already landed)"
exit 1
