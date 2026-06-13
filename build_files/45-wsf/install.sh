#!/usr/bin/env bash
# Margine image build — section: 45-wsf
# Bake wayland-scroll-factor (WSF) — touchpad scroll/pinch tuning for
# GNOME Wayland — and pre-enable its gnome-shell preload.
#
# WSF (github.com/daniel-g-carrasco/wayland-scroll-factor) is an
# LD_PRELOAD interposer on public libinput getters
# (libinput_event_pointer_get_scroll_value for finger scroll,
# libinput_event_gesture_get_scale/_get_angle_delta for pinch),
# process-guarded to activate only inside gnome-shell. No daemon, no
# udev, no mutter patch. Its default factor is 1.0 (mathematical
# no-op), so loading the preload unconditionally is inert until the
# user runs `wsf set ...` or wsf-gui — and then changes apply live on
# the next gesture, no logout (the logout requirement upstream is only
# for loading/unloading the preload itself, which the image pre-bakes).
set -euo pipefail
. /ctx/00-common.sh

WSF_VERSION=0.3.5
WSF_SHA256=59d49cf6e1ebbb5434db0c8f629e50830d33d09a6e6280458b9187f722f7f983
WSF_URL="https://github.com/daniel-g-carrasco/wayland-scroll-factor/archive/refs/tags/v${WSF_VERSION}.tar.gz"

log "Building wayland-scroll-factor v${WSF_VERSION}"

# Build deps: gcc + pkgconf are already in the bluefin-dx base; only
# meson/ninja are missing. Removed again below to keep the image lean.
dnf -y install meson ninja-build

workdir="$(mktemp -d /tmp/wsf-build.XXXXXX)"
retry_curl_strict "$WSF_URL" "${workdir}/wsf.tar.gz"
echo "${WSF_SHA256}  ${workdir}/wsf.tar.gz" | sha256sum -c -

tar -xzf "${workdir}/wsf.tar.gz" -C "$workdir"
pushd "${workdir}/wayland-scroll-factor-${WSF_VERSION}" >/dev/null

# Margine's PATH puts /usr/lib64/ccache first; in the build container
# ccache's cache dir isn't writable and every compile dies with
# "ccache: error: File exists" (caught by a local container test of
# this section). Compile without it — a one-shot build gains nothing
# from a compiler cache anyway.
export CCACHE_DISABLE=1

# --libdir=lib64 is meson's Fedora default, but pin it explicitly: the
# path is compiled into the wsf CLI as WSF_LIBDIR and referenced by
# the systemd drop-in below — they must agree.
meson setup build --prefix=/usr --libdir=lib64 --buildtype=release
ninja -C build
meson install -C build
install -Dm0644 LICENSE /usr/share/licenses/wayland-scroll-factor/LICENSE
popd >/dev/null
rm -rf "$workdir"

# Margine is GNOME-only: drop the "Hyprland (WSF gestures)" wayland
# session. Its TryExec (wsf-start-hyprland) exists after install, so
# GDM would otherwise list a session that cannot start (no Hyprland).
rm -f /usr/share/wayland-sessions/wayland-scroll-factor-hyprland.desktop

# Pre-enable the preload for gnome-shell system-wide. Upstream's
# per-user `wsf enable` writes ~/.config/environment.d/ and needs a
# logout; instead inject LD_PRELOAD only into the gnome-shell unit
# (template drop-in covers every org.gnome.Shell@<instance>.service,
# including the GDM greeter, where it is a no-op). The library scrubs
# itself from LD_PRELOAD after loading, so gnome-shell's children do
# not inherit it.
install -Dm0644 /ctx/45-wsf/margine-wsf-preload.conf \
  /usr/lib/systemd/user/org.gnome.Shell@.service.d/50-margine-wsf.conf

# Refresh caches for the new .desktop + hicolor icons (mirrors the
# AUR package's post_install hooks).
update-desktop-database -q /usr/share/applications || true
gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor || true

dnf -y remove meson ninja-build
dnf -y clean packages metadata

log "wayland-scroll-factor installed (preload baked for gnome-shell)"
