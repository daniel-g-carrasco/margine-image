#!/usr/bin/env bash
# Margine Phone Camera — use an Android phone as a webcam, with a GUI.
#
# Ingredients baked here:
#   - v4l2loopback is already built+signed by custom-kernel; this module
#     makes it LOAD at boot with a deterministic device: /dev/video21,
#     labeled "Margine Phone Cam". exclusive_caps=1 means apps only see
#     a capture device while a producer is feeding it, so the idle node
#     never clutters camera pickers.
#   - scrcpy from the OFFICIAL release tarball, pinned by version+sha256
#     (same pattern as the WSF release RPM). Not in Fedora proper (COPR
#     only), and the release bundle ships the matching scrcpy-server,
#     which MUST match the client version.
#   - adb from Fedora android-tools; gstreamer1-plugin-gtk4 for the
#     GUI's embedded preview (Gtk4PaintableSink).
#   - The GUI itself ships in system_files (usr/libexec/margine/
#     phone-cam-gui + dev.margine.PhoneCam.desktop).
set ${SET_X:+-x} -eou pipefail
source /ctx/00-common.sh

log "Installing phone-cam dependencies (android-tools, gtk4 gst sink)"
dnf -y install --no-docs --setopt=install_weak_deps=False \
  android-tools gstreamer1-plugin-gtk4

SCRCPY_VERSION=4.1
SCRCPY_SHA256=ad56ae8bfeedf41e824945c11dbf55fcb092b3e615b9b486f48a50e30d389635
SCRCPY_TAR="scrcpy-linux-x86_64-v${SCRCPY_VERSION}.tar.gz"

log "Installing scrcpy v${SCRCPY_VERSION} from the official release tarball"
curl -fsSL --retry 5 --retry-delay 10 -o "/tmp/${SCRCPY_TAR}" \
  "https://github.com/Genymobile/scrcpy/releases/download/v${SCRCPY_VERSION}/${SCRCPY_TAR}"
echo "${SCRCPY_SHA256}  /tmp/${SCRCPY_TAR}" | sha256sum -c -

mkdir -p /usr/lib/margine/scrcpy
tar xzf "/tmp/${SCRCPY_TAR}" -C /usr/lib/margine/scrcpy --strip-components=1
rm -f "/tmp/${SCRCPY_TAR}"
# The release bundle carries its own adb; prefer the distro one (updated
# by the image) and keep the bundle's server+client together.
rm -f /usr/lib/margine/scrcpy/adb

cat > /usr/bin/scrcpy <<'WRAP'
#!/usr/bin/env bash
# Margine wrapper: the release-tarball client must run with ITS OWN
# matching scrcpy-server (version-paired protocol).
#
# ADB is load-bearing here: the release client looks for an `adb` NEXT
# TO ITSELF before falling back to PATH, and this install deliberately
# drops the bundled copy in favour of the distro one (kept current by
# image updates). Without the explicit ADB env var the client dies with
# "Command not found: [/usr/lib/margine/scrcpy/adb]" even though adb is
# perfectly installed (field failure 2026-08-09, first run from the
# shipped image).
export ADB=/usr/bin/adb
export SCRCPY_SERVER_PATH=/usr/lib/margine/scrcpy/scrcpy-server
export SCRCPY_ICON_PATH=/usr/lib/margine/scrcpy/scrcpy.png
exec /usr/lib/margine/scrcpy/scrcpy "$@"
WRAP
chmod 0755 /usr/bin/scrcpy

/usr/bin/scrcpy --version >/dev/null || { echo "scrcpy smoke test failed" >&2; exit 1; }
# Assert the wrapper's adb wiring: --list-camera-sizes with no device
# must fail on "no device", NOT on a missing adb binary (the 2026-08-09
# regression). Any other output is fine; the adb-not-found string is not.
if /usr/bin/scrcpy --list-camera-sizes 2>&1 | grep -q "Command not found.*adb"; then
  echo "scrcpy cannot find adb — check the ADB env var in the wrapper" >&2
  exit 1
fi
log "scrcpy $( /usr/bin/scrcpy --version | head -1 ) installed"
