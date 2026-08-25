#!/usr/bin/env bash
# Fonts Margine declares that the base may ship differently.
#
# Noto Sans CJK (2026-08-25): today's base (bluefin-dx) ships the static
# google-noto-sans-cjk-fonts (124 MiB, one .ttc with every weight); the
# plain Bluefin image ships its variable successor
# google-noto-sans-cjk-vf-fonts (31 MiB). fc-match resolves ja, zh-cn,
# zh-tw and ko to Noto Sans CJK JP/SC/TC/KR from either file, and nothing
# in either image requires the static package. Fedora already moved the
# CJK mono and serif to the variable builds, which Margine has. So the
# declaration (margine-atomic.yaml, fonts) names the vf package, and this
# step makes the image match it on any base: install the vf package when
# missing, drop the static one when present. Net today: 93 MiB less.
set -euo pipefail
. /ctx/00-common.sh
log() { printf '[fonts] %s\n' "$*"; }
err() { printf '[fonts] ERROR: %s\n' "$*" >&2; }

if rpm -q google-noto-sans-cjk-vf-fonts >/dev/null 2>&1; then
  log "google-noto-sans-cjk-vf-fonts already in the base"
else
  log "base lacks google-noto-sans-cjk-vf-fonts, installing"
  retry 3 30 dnf -y install --setopt=install_weak_deps=False google-noto-sans-cjk-vf-fonts
fi
if rpm -q google-noto-sans-cjk-fonts >/dev/null 2>&1; then
  log "base ships the static google-noto-sans-cjk-fonts, removing it (the vf build covers the same scripts)"
  dnf -y remove --setopt=clean_requirements_on_remove=False google-noto-sans-cjk-fonts
fi

# --- Prove it -------------------------------------------------------------
fc-cache -f >/dev/null 2>&1 || true
for lang in ja zh-cn zh-tw ko; do
  f="$(fc-match -f '%{file}' ":lang=$lang" 2>/dev/null || true)"
  case "$f" in
    */google-noto-sans-cjk-vf-fonts/*) ;;
    *) err "fc-match :lang=$lang resolves to '${f:-nothing}', not the Noto Sans CJK variable font"; exit 1 ;;
  esac
done
log "Noto Sans CJK: variable font serves ja, zh-cn, zh-tw, ko"
