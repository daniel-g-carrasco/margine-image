#!/usr/bin/env bash
# Margine image build, section 47-koofr-tray-fix:
# Build koofr-tray-fix.so, an LD_PRELOAD shim for Koofr Desktop's tray icon.
#
# Koofr Desktop (closed source, Go) re-announces the same tray icon once a
# second through a new temp file, so every tray host re-reads it every
# second. In GNOME that is only wasted wakeups; Noctalia (Lucciola) rebuilds
# the whole tray each time, so hover and clicks on every tray icon break
# (noctalia-dev/noctalia#4537). The shim passes the icon on only when the
# image really changes; see the comment at the top of koofr-tray-fix.c.
# `ujust install-koofr` starts Koofr with it.
set -euo pipefail
. /ctx/00-common.sh

OUT=/usr/lib64/margine/koofr-tray-fix.so
transient=0
if ! command -v gcc >/dev/null 2>&1; then
  dnf5 -y install --setopt=install_weak_deps=False gcc glibc-devel
  transient=1
fi
install -d "$(dirname "$OUT")"
gcc -shared -fPIC -O2 -Wall -Wextra -Werror -o "$OUT" \
  /ctx/47-koofr-tray-fix/koofr-tray-fix.c -ldl -lpthread
chmod 0755 "$OUT"
# It must export dlsym: that is the whole mechanism.
nm -D --defined-only "$OUT" | grep -qE ' T dlsym$' || { err "47-koofr-tray-fix: dlsym not exported"; exit 1; }
if (( transient )); then
  dnf5 -y remove gcc glibc-devel
fi
log "47-koofr-tray-fix: built $OUT"
