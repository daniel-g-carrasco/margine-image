#!/usr/bin/env bash
# Stamp the margine-gaming variant's identity into os-release(5).
# Distinguishes this image from the base margine: in `bootc status`,
# GNOME's About panel, `lsb_release`, etc. — without changing the
# Fedora-side ID (we're still Fedora downstream).
#
# Layout we expect (post-Fix-B / rechunk wind-down, 2026-06-03):
#   /usr/lib/os-release  — canonical, regular file written by base build.sh
#   /etc/os-release      — relative symlink → ../usr/lib/os-release
# We edit the canonical /usr/lib/os-release in place. The symlink
# automatically reflects the new content; no need to touch /etc.
set -euo pipefail

OS_RELEASE_CANONICAL=/usr/lib/os-release

if [[ ! -f "$OS_RELEASE_CANONICAL" || -L "$OS_RELEASE_CANONICAL" ]]; then
  echo "✗ $OS_RELEASE_CANONICAL is not a regular file — base image is in an unexpected state"
  ls -la "$OS_RELEASE_CANONICAL" /etc/os-release
  exit 1
fi

# Replace VARIANT_ID and adjust PRETTY_NAME / VARIANT. Add VARIANT_ID
# if missing (base may not declare one).
sed -i \
    -e '/^VARIANT_ID=/d' \
    -e '/^VARIANT=/d' \
    -e 's|^PRETTY_NAME=.*|PRETTY_NAME="Margine Gaming"|' \
  "$OS_RELEASE_CANONICAL"
{
  echo 'VARIANT="Gaming"'
  echo 'VARIANT_ID=gaming'
} >> "$OS_RELEASE_CANONICAL"

echo "Stamped os-release for margine-gaming variant:"
grep -E '^(NAME|ID|PRETTY_NAME|VARIANT|VARIANT_ID|LOGO)=' "$OS_RELEASE_CANONICAL"

# Sanity: /etc/os-release (the symlink) should resolve to the updated
# canonical file. Validate at build time so a future regression that
# breaks the symlink fails the gaming build loudly instead of shipping
# a divergent runtime.
if [[ ! -L /etc/os-release ]]; then
  echo "✗ /etc/os-release is not a symlink — Fix A workaround has resurfaced upstream"
  ls -la /etc/os-release
  exit 1
fi
if ! grep -q '^VARIANT_ID=gaming' /etc/os-release; then
  echo "✗ /etc/os-release does not reflect the gaming stamp via symlink"
  ls -la /etc/os-release
  cat /etc/os-release
  exit 1
fi
