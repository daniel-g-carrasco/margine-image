#!/usr/bin/env bash
# Margine Layer C GUI smoke probe — runs INSIDE the smoke-boot VM as a
# root oneshot (margine-gui-smoke.service), injected offline into the
# qcow2 by .github/scripts/inject-gui-probe.sh. Verdict goes to the
# serial console; the CI watcher greps for MARGINE-GUI-SMOKE: PASS/FAIL.
#
# Lived as a triple-escaped heredoc inside smoke-boot.yml until
# 2026-06-12 — invisible to shellcheck and unrunnable locally. As a
# file it can be executed on the lab VM directly, which matters now
# that this probe is slated to become gating.
set -u
out() { echo "$@" > /dev/console; }
fail() { out "MARGINE-GUI-SMOKE: FAIL $*"; sleep 2; systemctl poweroff; exit 0; }

# ---- Gaming-native layer resolvability (independent of the GUI) ------------
# `ujust margine-gaming-native` layers a multilib RPM set whose fragile
# edge is steam's 32-bit graphics deps (i686 mesa/llvm must version-match
# the baked x86_64). A dry-run resolves that exact transaction the way the
# recipe would, WITHOUT applying it — so a depsolve failure here is the
# i686/x86_64 skew that broke `margine-gaming-native` for real. Package
# set is read from the same file the recipe installs from (no drift).
# Verdict is WARN-ONLY for now (parsed by qemu-boot-wait.sh); run first so
# it produces a verdict even when the GUI checks below bail out early.
gaming_check() {
  local list=/usr/share/margine/gaming-native-packages.txt
  if [[ ! -r "$list" ]]; then
    out "MARGINE-GAMING-NATIVE: SKIP (package list not found)"
    return
  fi
  local pkgs
  mapfile -t pkgs < <(grep -vE '^[[:space:]]*(#|$)' "$list")
  if [[ "${#pkgs[@]}" -eq 0 ]]; then
    out "MARGINE-GAMING-NATIVE: SKIP (empty package list)"
    return
  fi
  if timeout 240 rpm-ostree install --dry-run "${pkgs[@]}" >/tmp/gaming.out 2>&1; then
    out "MARGINE-GAMING-NATIVE: PASS (${#pkgs[@]} pkgs resolve)"
  else
    out "MARGINE-GAMING-NATIVE: FAIL $(grep -iE 'cannot install|conflict|requires|nothing provides|depsolve' /tmp/gaming.out | head -2 | tr '\n' ' ' | tr -s ' ')"
  fi
}
gaming_check

# Wait for the autologin session's gnome-shell (first boot is slow:
# flatpak preinstall etc. competes for I/O).
for _ in $(seq 1 60); do
  pgrep -u smoke -x gnome-shell >/dev/null && break
  sleep 5
done
pgrep -u smoke -x gnome-shell >/dev/null || fail "gnome-shell never started for autologin user"

# Give extensions time to load, then count the enabled ones through
# the user's session bus.
sleep 30
EXT=$(runuser -u smoke -- env \
  XDG_RUNTIME_DIR=/run/user/1010 \
  DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1010/bus \
  gnome-extensions list --enabled 2>/dev/null | wc -l)
[[ "$EXT" -ge 6 ]] || fail "only $EXT extensions enabled (expected >=6)"

# The shell must still be alive AND nothing may have dumped core.
pgrep -u smoke -x gnome-shell >/dev/null || fail "gnome-shell died during the probe window"
CORES=$(coredumpctl --no-pager -q list 2>/dev/null | grep -c gnome-shell || true)
[[ "$CORES" -eq 0 ]] || fail "gnome-shell dumped core ($CORES)"
journalctl -b -q --no-pager 2>/dev/null | grep -q "Bail out!" && fail "Clutter assertion (Bail out!) in journal"

# Branding validator (from margine-fedora-atomic) — file checks plus,
# when a display is reachable, the same gjs lookup the welcome dialogs
# use. (Headless-safe since fedora-atomic#56: no display => skip, not
# a false FAIL.)
if [[ -x /usr/bin/margine-validate-branding ]]; then
  /usr/bin/margine-validate-branding > /tmp/branding.out 2>&1 \
    || fail "margine-validate-branding: $(tail -3 /tmp/branding.out | tr '\n' ' ')"
fi

out "MARGINE-GUI-SMOKE: PASS ext=$EXT"
sleep 2
systemctl poweroff
