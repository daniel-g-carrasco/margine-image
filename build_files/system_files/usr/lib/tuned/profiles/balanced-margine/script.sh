#!/usr/bin/bash
# Tuned-driven scx_loader mode switch (Bazzite pattern).
# No-op unless the user has opted into scx_loader.
set -u
case "$1" in
  start)
    if systemctl is-active --quiet scx_loader.service 2>/dev/null; then
      scxctl switch -m auto >/dev/null 2>&1 || true
    fi
    ;;
esac
exit 0
