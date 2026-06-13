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
#
# WSF is installed from its official release RPM (not built from source).
# That makes it a real rpmdb package — so a host can `rpm-ostree override
# replace` a test build over it — and drops meson/ninja from the image
# build. Pinned by version + sha256 for reproducibility; Renovate
# (.github/renovate.json5) + .github/workflows/wsf-pin-sha.yml keep both
# current on each upstream release. The fc tag tracks the base Fedora
# release (the WSF release builds its RPM on the same Fedora).
set -euo pipefail
. /ctx/00-common.sh

WSF_VERSION=0.3.5
WSF_SHA256=fca3070e3df55795f201bb9c7e42013f31215963f2117ff90809117dba4722fe
WSF_RPM="wayland-scroll-factor-${WSF_VERSION}-1.fc44.x86_64.rpm"
WSF_URL="https://github.com/daniel-g-carrasco/wayland-scroll-factor/releases/download/v${WSF_VERSION}/${WSF_RPM}"

log "Installing wayland-scroll-factor v${WSF_VERSION} (release RPM)"

workdir="$(mktemp -d /tmp/wsf-rpm.XXXXXX)"
retry_curl_strict "$WSF_URL" "${workdir}/${WSF_RPM}"
echo "${WSF_SHA256}  ${workdir}/${WSF_RPM}" | sha256sum -c -

# Local-file install: dnf resolves the runtime deps (gtk4, libadwaita,
# python3-gobject) from the base repos. No weak deps — keep it lean.
dnf -y install --setopt=install_weak_deps=False "${workdir}/${WSF_RPM}"
rm -rf "$workdir"

# Margine is GNOME-only: drop the "Hyprland (WSF gestures)" wayland
# session the package ships. Its TryExec (wsf-start-hyprland) exists, so
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
# package's post_install hooks).
update-desktop-database -q /usr/share/applications || true
gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor || true

dnf -y clean packages metadata

log "wayland-scroll-factor installed from RPM (preload baked for gnome-shell)"
