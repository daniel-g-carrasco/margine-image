#!/usr/bin/env bash
# Every symbolic icon name our GUIs reference must exist in the icon
# theme the image ships. Missing names do not crash: GTK silently draws
# the broken-image placeholder, which is exactly what shipped in the
# first Margine System build (os-symbolic, processor-symbolic and
# emblem-ok-symbolic were invented, not looked up).
#
# Runs inside the built image (adwaita-icon-theme present); lists the
# names, then asserts each one resolves.
set -euo pipefail

mapfile -t NAMES < <(
  grep -rhoE '"[a-z0-9-]+-symbolic"' \
    build_files/system_files/usr/libexec/margine/ \
    2>/dev/null | tr -d '"' | sort -u
)
[ "${#NAMES[@]}" -gt 0 ] || { echo "no icon names found — did the GUIs move?"; exit 1; }
printf 'checking %d symbolic icon names\n' "${#NAMES[@]}"

missing=0
for name in "${NAMES[@]}"; do
  found=0
  for dir in /usr/share/icons/hicolor /usr/share/icons/Adwaita; do
    [ -d "$dir" ] || continue
    if find "$dir" -name "${name}.svg" -print -quit | grep -q .; then found=1; break; fi
  done
  if [ "$found" -eq 0 ]; then
    echo "::error::icon not found in the image: ${name}"
    missing=$((missing + 1))
  fi
done
[ "$missing" -eq 0 ] || exit 1
echo "all icon names resolve"
