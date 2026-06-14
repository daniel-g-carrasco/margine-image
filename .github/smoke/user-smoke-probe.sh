#!/usr/bin/env bash
# Margine USER-SMOKE probe — runs INSIDE the smoke-boot VM as a root
# oneshot (margine-user-smoke.service), injected offline into the qcow2
# by .github/scripts/inject-gui-probe.sh. Where the Layer C gui-probe.sh
# asks "is the graphical session HEALTHY?" (alive shell, no coredumps),
# this probe asks the user-facing question "is this image still
# MARGINE?" — the identity assertions a person would notice if they
# regressed: the CachyOS/BORE kernel booted, o-tiling on, the Hyprland-
# style binds present, search-light gone, the gaming recipe shipped, and
# the zz1-margine gschema applied.
#
# SOFT ("morbido") GATE — every check is WARN-only. This probe NEVER
# fails the job and NEVER blocks the candidate->stable promotion: it
# only annotates the run (serial -> step summary). It ALWAYS exits 0.
# The CI watcher greps the serial console for:
#   MARGINE-USER-SMOKE: <CHECK> <PASS|WARN> ...   (per check)
#   MARGINE-USER-SMOKE: SUMMARY pass=N warn=M ...  (one line)
#   MARGINE-USER-SMOKE: DONE                       (probe finished)
#
# Runs AFTER gui-probe.sh's poweroff would fire, so it must NOT power the
# VM off itself — gui-probe.sh owns the poweroff (it calls wait_gaming
# then `systemctl poweroff`). This probe just emits and returns; if it
# is the only probe injected it still leaves shutdown to the gui-probe
# unit ordering. Bounded everywhere (no unbounded waits) so it can never
# hold the boot window open.
#
# Lives as a real file (like gui-probe.sh) so shellcheck gates it and it
# can be run on the lab VM directly:  sudo .github/smoke/user-smoke-probe.sh
set -u

# Markers to BOTH /dev/console (the watcher reads -serial) and /dev/kmsg
# (mirrored to console=ttyS0 forced by inject-gui-probe.sh) so the
# verdict survives a BLS entry that lacks the serial console karg.
out() {
  echo "$@" > /dev/console 2>/dev/null || true
  echo "<usersmoke> $*" > /dev/kmsg 2>/dev/null || true
}

PASS=0
WARN=0
# check <NAME> <0-if-ok> <detail...> — soft: a failure is a WARN, never fatal.
check() {
  local name="$1" rc="$2"; shift 2
  if [[ "$rc" -eq 0 ]]; then
    PASS=$((PASS + 1)); out "MARGINE-USER-SMOKE: ${name} PASS $*"
  else
    WARN=$((WARN + 1)); out "MARGINE-USER-SMOKE: ${name} WARN $*"
  fi
}

# The injected smoke autologin user is uid 1010 (see inject-gui-probe.sh).
SMOKE_UID=1010
SMOKE_USER=smoke
RUN_DIR="/run/user/${SMOKE_UID}"

# Read a dconf/gsettings value AS THE SMOKE USER so the distro-db
# defaults (system-db:distro -> /etc/dconf/db/distro.d) and the gschema
# overrides resolve through the user's dconf profile exactly as they
# would for a real first login. Falls back to an empty string.
usettings() {  # usettings <schema> <key>
  runuser -u "$SMOKE_USER" -- env \
    XDG_RUNTIME_DIR="$RUN_DIR" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=${RUN_DIR}/bus" \
    gsettings get "$1" "$2" 2>/dev/null || true
}
udconf() {  # udconf <full/dconf/path>
  runuser -u "$SMOKE_USER" -- env \
    XDG_RUNTIME_DIR="$RUN_DIR" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=${RUN_DIR}/bus" \
    dconf read "$1" 2>/dev/null || true
}

# Give the autologin session a bounded moment to settle so the per-user
# dbus/dconf is up (this unit is After=graphical.target but the user bus
# may lag the target). Bounded — never an unbounded wait.
for _ in $(seq 1 24); do
  [[ -S "${RUN_DIR}/bus" ]] && break
  sleep 5
done

out "MARGINE-USER-SMOKE: BEGIN"

# 1. CachyOS/BORE kernel is the one that actually booted (CORE identity).
KREL="$(uname -r 2>/dev/null || echo '?')"
if [[ "$KREL" == *cachyos* ]]; then check KERNEL 0 "uname=$KREL"
else check KERNEL 1 "expected *cachyos*, got uname=$KREL"; fi

# 2. GNOME/gdm session reachable — gdm active and a gnome-shell running
#    for the autologin user (the user-facing "did I get a desktop").
GDM_OK=1
systemctl is-active --quiet gdm.service 2>/dev/null && GDM_OK=0
SHELL_OK=1
pgrep -u "$SMOKE_USER" -x gnome-shell >/dev/null 2>&1 && SHELL_OK=0
if [[ "$GDM_OK" -eq 0 && "$SHELL_OK" -eq 0 ]]; then
  check GDM_SESSION 0 "gdm active + gnome-shell up for $SMOKE_USER"
elif [[ "$GDM_OK" -eq 0 ]]; then
  check GDM_SESSION 1 "gdm active but no gnome-shell for $SMOKE_USER yet"
else
  check GDM_SESSION 1 "gdm.service not active"
fi

# 3. o-tiling extension present on disk AND in the enabled set.
OTILING_UUID='o-tiling@oliwebd.github.com'
OTILING_PRESENT=1
for d in "/usr/share/gnome-shell/extensions/${OTILING_UUID}" \
         "/usr/share/gnome-shell/extensions/${OTILING_UUID}"/*; do
  [[ -f "$d/metadata.json" || -f "${d}/metadata.json" ]] 2>/dev/null && OTILING_PRESENT=0
done
[[ -f "/usr/share/gnome-shell/extensions/${OTILING_UUID}/metadata.json" ]] && OTILING_PRESENT=0
ENABLED_LIST="$(usettings org.gnome.shell enabled-extensions)"
if [[ "$OTILING_PRESENT" -eq 0 && "$ENABLED_LIST" == *"$OTILING_UUID"* ]]; then
  check OTILING 0 "installed + in enabled-extensions"
elif [[ "$OTILING_PRESENT" -eq 0 ]]; then
  check OTILING 1 "installed but NOT in enabled-extensions ($ENABLED_LIST)"
else
  check OTILING 1 "extension dir/metadata missing"
fi

# 4. Margine Hyprland-style tiling keybindings present in dconf. The
#    Super+1..0 workspace binds are applied per-user by margine-bootstrap
#    (NOT run for this throwaway smoke user), so assert the SYSTEM-baked
#    ones instead: o-tiling focus binds (03-margine-o-tiling) and the
#    Smile custom keybinding (07-margine-custom-keybindings) both ship in
#    /etc/dconf/db/distro.d and resolve through the user's dconf profile.
FOCUS_LEFT="$(usettings org.gnome.shell.extensions.o-tiling focus-left)"
SMILE_BIND="$(udconf /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/margine-smile/binding)"
KB_HITS=0
[[ "$FOCUS_LEFT" == *"<Super>h"* ]] && KB_HITS=$((KB_HITS + 1))
[[ "$SMILE_BIND" == *"<Super>period"* ]] && KB_HITS=$((KB_HITS + 1))
if [[ "$KB_HITS" -ge 2 ]]; then
  check KEYBINDINGS 0 "o-tiling focus-left=$FOCUS_LEFT smile=$SMILE_BIND"
elif [[ "$KB_HITS" -eq 1 ]]; then
  check KEYBINDINGS 1 "partial (focus-left=$FOCUS_LEFT smile=$SMILE_BIND)"
else
  check KEYBINDINGS 1 "Margine binds absent (focus-left=$FOCUS_LEFT smile=$SMILE_BIND)"
fi

# 5. search-light NOT enabled (it was deliberately removed from the
#    default enabled set; the package may stay installed for opt-in).
if [[ "$ENABLED_LIST" == *"search-light"* ]]; then
  check SEARCH_LIGHT 1 "search-light is in enabled-extensions (should be OFF)"
else
  check SEARCH_LIGHT 0 "not in enabled-extensions (correct)"
fi

# 6. Gaming ujust recipe exists — `ujust --list` shows margine-gaming*.
#    Run as the smoke user (ujust is the user-facing entry point).
UJUST_BIN=""
for c in /usr/bin/ujust /usr/local/bin/ujust; do [[ -x "$c" ]] && UJUST_BIN="$c" && break; done
if [[ -n "$UJUST_BIN" ]]; then
  UJUST_LIST="$(runuser -u "$SMOKE_USER" -- "$UJUST_BIN" --list 2>/dev/null || true)"
  GAMING_RECIPES="$(printf '%s\n' "$UJUST_LIST" | grep -oE 'margine-gaming[a-z-]*' | sort -u | tr '\n' ',' | sed 's/,$//')"
  if printf '%s\n' "$UJUST_LIST" | grep -qE 'margine-gaming'; then
    check GAMING_UJUST 0 "recipes: ${GAMING_RECIPES:-margine-gaming*}"
  else
    check GAMING_UJUST 1 "no margine-gaming* in ujust --list"
  fi
else
  check GAMING_UJUST 1 "ujust binary not found"
fi

# 7. zz1-margine gschema applied — assert two keys the override sets that
#    are NOT GNOME/Bluefin defaults: accent-color=yellow and the bumped
#    num-workspaces=10. Reading them via gsettings exercises the
#    compiled glib schema + the override precedence (loads after zz0).
ACCENT="$(usettings org.gnome.desktop.interface accent-color)"
NUMWS="$(usettings org.gnome.desktop.wm.preferences num-workspaces)"
GS_HITS=0
[[ "$ACCENT" == *yellow* ]] && GS_HITS=$((GS_HITS + 1))
[[ "$NUMWS" == *10* ]] && GS_HITS=$((GS_HITS + 1))
if [[ "$GS_HITS" -ge 2 ]]; then
  check GSCHEMA 0 "accent=$ACCENT num-workspaces=$NUMWS"
elif [[ "$GS_HITS" -eq 1 ]]; then
  check GSCHEMA 1 "partial (accent=$ACCENT num-workspaces=$NUMWS)"
else
  check GSCHEMA 1 "zz1-margine override not applied (accent=$ACCENT num-workspaces=$NUMWS)"
fi

# ---- Summary (one parseable line) -----------------------------------------
TOTAL=$((PASS + WARN))
out "MARGINE-USER-SMOKE: SUMMARY pass=${PASS} warn=${WARN} total=${TOTAL}"
if [[ "$WARN" -eq 0 ]]; then
  out "MARGINE-USER-SMOKE: VERDICT ALL-PASS (${PASS}/${TOTAL})"
else
  out "MARGINE-USER-SMOKE: VERDICT WARN (${PASS}/${TOTAL} ok, ${WARN} warning) — soft gate, promotion NOT blocked"
fi
out "MARGINE-USER-SMOKE: DONE"

# SOFT GATE: always succeed. The verdict is annotation only.
exit 0
