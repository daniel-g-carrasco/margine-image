#!/usr/bin/env bash
# Margine image build — common helpers and environment.
# Sourced by every NN-<area>/install.sh script.
#
# Split out of the monolithic build.sh on 2026-06-06 (audit §8 rec #22).
# The orchestrator at build.sh just dispatches to /ctx/[1-9][0-9]-*/
# install.sh in lexicographic order; each script sources this file.

set -euo pipefail

log() { printf '[margine-build] %s\n' "$*"; }

# retry_curl <url> <output_path> — fetch with the same brownout-tolerance
# the kernel-cachyos COPR install uses. Branding asset pulls from
# raw.githubusercontent.com can fail transiently (5xx, DNS blip,
# GitHub Pages cold-start); without retry a single hiccup costs us a
# 25-min rebuild near the end. 5 attempts, 30-150s exponential backoff.
retry_curl() {
  local url="$1" out="$2"
  local attempt=1 max=5
  while :; do
    if curl --fail --silent --show-error -L "$url" -o "$out"; then
      return 0
    fi
    if (( attempt >= max )); then
      log "retry_curl FAILED after $max attempts: $url"
      return 1
    fi
    local backoff=$(( attempt * 30 ))
    log "retry_curl attempt $attempt failed for $url; sleeping ${backoff}s"
    sleep $backoff
    attempt=$(( attempt + 1 ))
  done
}

# retry_curl_strict <url> <output_path> — same retry behaviour as
# retry_curl, but ABORTS the build if the asset is missing or empty
# after all attempts. Use only for assets without which the image is
# broken at first boot (welcome screen logo, About-panel logo). Silent
# failure of these has shipped to user-visible regressions twice
# (2026-06-04 welcome page dinosaur, 2026-06-06 logo absent), so
# fail-loud is the right default here even if it means a build retry.
retry_curl_strict() {
  local url="$1" out="$2"
  if ! retry_curl "$url" "$out"; then
    log "FATAL: required asset fetch failed: $url"
    return 1
  fi
  if [[ ! -s "$out" ]]; then
    log "FATAL: required asset is empty after fetch: $out (url=$url)"
    return 1
  fi
  return 0
}

# retry <max-attempts> <base-backoff-seconds> <cmd...> — generic outer
# retry with linear backoff (30, 60, 90... for base=30). Deduplicates
# the three hand-copied dnf retry loops custom-kernel carried (review
# P3). For dnf installs that should clean metadata between attempts,
# wrap the command in `bash -c`.
retry() {
  local max=$1 base=$2 n=1
  shift 2
  while ! "$@"; do
    if (( n >= max )); then
      log "retry FAILED after ${max} attempts: $*"
      return 1
    fi
    log "retry: attempt ${n} failed; sleeping $(( n * base ))s: $*"
    sleep $(( n * base ))
    n=$(( n + 1 ))
  done
  return 0
}

# NOTE on trap-based cleanup in build scripts: deliberately ABSENT.
# A failed RUN discards the whole container layer, so half-restored
# state (moved kernel hooks, remounted /proc/sys, tmpdirs) can never
# ship. Documented once here so it stops being re-litigated at every
# review.

# Cached, exported globals used across sections. Defined here once so
# every sub-script gets the same value without recomputing.
export FEDORA_VER="${FEDORA_VER:-$(rpm -E %fedora 2>/dev/null || echo 44)}"
export BUILD_DATE="${BUILD_DATE:-$(date -u +%Y%m%d)}"
