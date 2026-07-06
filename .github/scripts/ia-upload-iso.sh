#!/usr/bin/env bash
# Stall-aware Internet Archive uploader for the multi-GB ISO.
#
# Why not plain `ia upload`: its --retries only fires on ERROR RESPONSES
# (S3 503s). A hung TCP connection never errors, so the CLI blocks until
# the JOB timeout kills it — run 28758416337 (2026-07-06) sat 5h50m on a
# dead socket and the ISO never published. curl gives what ia cannot:
# --speed-limit/--speed-time abort the transfer when it actually STALLS
# (moving-but-slow uploads are left alone), and a bounded retry loop gets
# a fresh connection instead of a wedged one.
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
#        IA_MAX_ATTEMPTS     bounded attempts           [4]
#        IA_RETRY_SLEEP_S    pause between attempts     [90]
set -euo pipefail

IDENTIFIER="${1:?usage: ia-upload-iso.sh <identifier> <file> [remote-name]}"
FILE="${2:?usage: ia-upload-iso.sh <identifier> <file> [remote-name]}"
REMOTE="${3:-$(basename "$FILE")}"
: "${IA_S3_ACCESS:?IA_S3_ACCESS required}"
: "${IA_S3_SECRET:?IA_S3_SECRET required}"
BASE="${IA_S3_BASE:-https://s3.us.archive.org}"
LIMIT="${IA_STALL_LIMIT_BPS:-10240}"
WINDOW="${IA_STALL_WINDOW_S:-300}"
ATTEMPTS="${IA_MAX_ATTEMPTS:-4}"
RETRY_SLEEP="${IA_RETRY_SLEEP_S:-90}"

SIZE="$(stat -c %s "$FILE")"
echo "upload: ${FILE} (${SIZE} bytes) -> ${BASE}/${IDENTIFIER}/${REMOTE}"
echo "hashing local file (md5, for the verify short-circuit)..."
MD5="$(md5sum "$FILE" | awk '{print $1}')"

already_uploaded() {
  # Complete when the S3 object's size matches and, if an ETag comes
  # back, its md5 matches too (missing/opaque ETag falls back to size).
  local headers size etag
  headers="$(curl -fsSI -m 60 \
    -H "authorization: LOW ${IA_S3_ACCESS}:${IA_S3_SECRET}" \
    "${BASE}/${IDENTIFIER}/${REMOTE}" 2>/dev/null)" || return 1
  size="$(printf '%s' "$headers" | tr -d '\r' | awk 'tolower($1)=="content-length:" {print $2}' | tail -1)"
  etag="$(printf '%s' "$headers" | tr -d '\r' | awk 'tolower($1)=="etag:" {gsub(/"/, "", $2); print $2}' | tail -1)"
  [ "$size" = "$SIZE" ] || return 1
  if [ -n "$etag" ] && [ "$etag" != "$MD5" ]; then return 1; fi
  return 0
}

for attempt in $(seq 1 "$ATTEMPTS"); do
  if already_uploaded; then
    echo "remote object already complete (size + md5 match) — nothing to do."
    exit 0
  fi
  echo "── attempt ${attempt}/${ATTEMPTS}: PUT (aborts if <${LIMIT} B/s for ${WINDOW}s)"
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
    echo "upload complete + verified (attempt ${attempt})."
    exit 0
  fi
  echo "::warning::attempt ${attempt} failed (curl rc=${rc}; 28 = stall abort) — probing IA S3 load"
  curl -fsS -m 30 "${BASE}/?check_limit=1&accesskey=${IA_S3_ACCESS}" || true
  echo
  if [ "$attempt" -lt "$ATTEMPTS" ]; then
    sleep "$RETRY_SLEEP"
  fi
done
echo "::error::IA upload of ${REMOTE} not verified after ${ATTEMPTS} bounded attempts"
exit 1
