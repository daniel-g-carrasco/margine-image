#!/usr/bin/env bash
# Margine image build — section: 60-ujust-services
# Sub-script of the build.sh orchestrator. Decomposed on 2026-06-06
# (audit §8 rec #22 — split build.sh into per-area install scripts).
# See build_files/00-common.sh + build_files/build.sh.
set -euo pipefail
. /ctx/00-common.sh

# 5. Margine ujust recipes (gaming layer opt-in)
# ---------------------------------------------------------------------------
# Bluefin's /usr/share/ublue-os/just/00-entry.just hardcodes the list
# of imported recipe files. The ONLY one declared as optional is
# 60-custom.just (via `import?`) — that's the documented extension
# point for downstream distros. Files dropped under any other name
# (e.g. 99-margine.just) are simply ignored by `ujust --list`, even
# if syntactically valid. Use 60-custom.just so our recipes appear.
# (Steam Flatpak + Lutris/Heroic/Bottles + gamescope/mangohud/vkBasalt/
# gamemode/goverlay/steam-devices layered via rpm-ostree).
#
# Modeled after Bazzite's gaming bake, but opt-in: Margine default stays
# minimal; gamers run one command and get a working stack.
log "Installing Margine ujust recipes"
install -Dm0644 /ctx/60-custom.just /usr/share/ublue-os/just/60-custom.just

# ---------------------------------------------------------------------------
# 5b. First-login auto-bootstrap (XDG autostart)
# ---------------------------------------------------------------------------
# When a fresh user logs in for the first time after rebasing to
# Margine, run `ujust margine-bootstrap unattended` once. It's
# idempotent and skips re-running because of the marker file at
# ~/.config/margine/bootstrapped. The user can re-run by deleting
# that file or by invoking `ujust margine-bootstrap` manually.
#
# Without this, the configure-* scripts only ever run if the user
# happens to know they have to type the ujust command — which is
# exactly the "nothing's configured" bug we just fixed.
# ---------------------------------------------------------------------------
# 5c. Mask systemd-remount-fs.service (Bug 8 — composefs noise)
# ---------------------------------------------------------------------------
# The legacy "remount root rw from /etc/fstab" service is incompatible
# with composefs root: the overlay refuses reconfigure and the unit
# always lands in `failed` state. The system works fine — `/` is
# already rw via the overlay upper layer — but `systemctl --failed`
# always shows it and confuses humans. Mask it so the unit never
# starts and `--failed` returns empty on a clean boot.
log "Masking systemd-remount-fs.service (overlay rejects remount; see Bug 8 in lessons-learned)"
ln -sf /dev/null /etc/systemd/system/systemd-remount-fs.service

# /etc/skel default: disable Bluefin MOTD banner at terminal open.
# Bluefin ships /etc/profile.d/ublue-motd.sh which prints the
# "Welcome to Bluefin / ujust --choose / brew help" banner unless
# ~/.config/no-show-user-motd exists. We ship that marker in the
# skeleton so EVERY new user account inherits the off-by-default
# behavior. Existing users get the file via configure-home-layout
# (idempotent), which margine-bootstrap runs at first login.
mkdir -p /etc/skel/.config
touch /etc/skel/.config/no-show-user-motd
log "Installed: /etc/skel/.config/no-show-user-motd (disables Bluefin MOTD for new users)"

# ---------------------------------------------------------------------------
