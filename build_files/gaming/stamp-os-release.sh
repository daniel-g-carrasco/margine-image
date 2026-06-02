#!/usr/bin/env bash
# Stamp the margine-gaming variant's identity into os-release(5).
# Distinguishes this image from the base margine: in `bootc status`,
# GNOME's About panel, `lsb_release`, etc. — without changing the
# Fedora-side ID (we're still Fedora downstream).
#
# Why a separate script: build.sh in the base image rewrites os-release
# as a regular file (Fix A 2026-05-29) so subsequent layers CAN edit
# it normally. Variant images just sed in their own tags on top of
# what base wrote.
set -euo pipefail

OS_RELEASE=/etc/os-release

if [[ ! -f "$OS_RELEASE" || -L "$OS_RELEASE" ]]; then
  echo "✗ $OS_RELEASE is not a regular file — base image strip step regressed"
  exit 1
fi

# Replace VARIANT_ID and adjust PRETTY_NAME / VARIANT. Add VARIANT_ID
# if missing (base may not declare one).
sed -i \
    -e '/^VARIANT_ID=/d' \
    -e '/^VARIANT=/d' \
    -e 's|^PRETTY_NAME=.*|PRETTY_NAME="Margine Gaming"|' \
  "$OS_RELEASE"
{
  echo 'VARIANT="Gaming"'
  echo 'VARIANT_ID=gaming'
} >> "$OS_RELEASE"

echo "Stamped os-release for margine-gaming variant:"
grep -E '^(NAME|ID|PRETTY_NAME|VARIANT|VARIANT_ID|LOGO)=' "$OS_RELEASE"

# Mirror to /usr/lib/os-release so anything reading the canonical
# Fedora location sees the same values.
if [[ -f /usr/lib/os-release && ! -L /usr/lib/os-release ]]; then
  cp -f "$OS_RELEASE" /usr/lib/os-release
fi
