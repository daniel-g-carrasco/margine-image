#!/usr/bin/env bash
# Lucciola image build: runs once inside the Containerfile, on top of the
# Margine image. Adds niri and Noctalia from the official Fedora repositories,
# makes "Lucciola" the session and the system name, and checks the result.
set -euo pipefail

log() { echo "[lucciola-build] $*"; }

: "${NOCTALIA_EVR:?NOCTALIA_EVR must be set (the pinned noctalia version)}"

# 1. Packages. Weak dependencies off: niri's package recommends waybar,
#    fuzzel, alacritty and swaylock, a second bar, launcher, terminal and
#    locker next to Noctalia, which owns those jobs (its other recommendations,
#    gnome-keyring, wireplumber and the GNOME/GTK portals, are already in the
#    Margine image).
#    Noctalia is pinned: upstream supports only its latest release and Fedora
#    ships every one within a day, so a new version arrives only through a
#    reviewed change of NOCTALIA_EVR, never by itself.
log "installing niri, xwayland-satellite, noctalia-${NOCTALIA_EVR}"
dnf5 -y --setopt=install_weak_deps=False install \
  niri xwayland-satellite "noctalia-${NOCTALIA_EVR}"
for p in waybar mako fuzzel alacritty swaylock; do
  if rpm -q "$p" >/dev/null 2>&1; then
    echo "ERROR: $p got installed; it would compete with Noctalia" >&2
    exit 1
  fi
done

# 2. Session. GDM lists wayland-sessions/*.desktop; Lucciola replaces the
#    plain "Niri" entry with its own (same niri-session underneath), so the
#    login screen offers "Lucciola" next to GNOME.
src=/usr/share/wayland-sessions/niri.desktop
[[ -f "$src" ]] || { echo "ERROR: $src missing: niri package layout changed" >&2; exit 1; }
grep -q '^Exec=niri-session' "$src" || { echo "ERROR: niri.desktop no longer runs niri-session" >&2; exit 1; }
sed -e 's/^Name=.*/Name=Lucciola/' \
    -e 's/^Comment=.*/Comment=Lucciola: niri with the Noctalia shell/' \
    "$src" > /usr/share/wayland-sessions/lucciola.desktop
rm -f "$src"
log "session entry: $(grep -E '^(Name|Exec|DesktopNames)=' /usr/share/wayland-sessions/lucciola.desktop | tr '\n' ' ')"

# 3. Identity. Only the public name changes: ID, VARIANT_ID and the rest stay
#    Margine's, because the tooling underneath (validators, status, update
#    helpers) is Margine's and keys on them.
fedora_ver="$(rpm -E %fedora)"
build_date="$(date -u +%Y%m%d)"
sed -i \
  -e 's/^NAME=.*/NAME="Lucciola"/' \
  -e "s/^VERSION=.*/VERSION=\"${fedora_ver} (Lucciola)\"/" \
  -e "s/^PRETTY_NAME=.*/PRETTY_NAME=\"Lucciola ${fedora_ver} (${build_date})\"/" \
  -e 's/^VARIANT=.*/VARIANT="Lucciola"/' \
  /usr/lib/os-release
grep -q '^NAME="Lucciola"$' /usr/lib/os-release || { echo "ERROR: os-release not rewritten" >&2; exit 1; }

# 4. Checks: the shipped niri config must parse (includes resolved), and the
#    helpers must be there and executable.
niri validate -c /etc/niri/config.kdl
# Noctalia's own validator; it only warns on bad values, so any warning fails.
out="$(noctalia config validate /usr/share/lucciola/noctalia/ 2>&1)" || { echo "$out" >&2; exit 1; }
if grep -q WARN <<<"$out"; then echo "$out" >&2; echo "ERROR: Noctalia defaults have warnings" >&2; exit 1; fi
# Noctalia silently falls back to its builtin palette when a custom palette
# lacks the "terminal" block (src/theme/theme_service.cpp,
# parseCommunityPaletteJson), so check what it actually requires.
python3 - /usr/share/lucciola/noctalia/palettes/Margine.json <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
keys = ["mPrimary", "mOnPrimary", "mSecondary", "mOnSecondary", "mTertiary", "mOnTertiary",
        "mError", "mOnError", "mSurface", "mOnSurface", "mSurfaceVariant", "mOnSurfaceVariant",
        "mOutline", "mShadow", "mHover", "mOnHover"]
dark = d["dark"]
missing = [k for k in keys if k not in dark]
term = dark.get("terminal", {})
for part in ("normal", "bright"):
    if set(term.get(part, {})) != {"black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"}:
        missing.append("terminal." + part)
if missing:
    sys.exit("ERROR: Margine palette incomplete, Noctalia would ignore it: " + ", ".join(missing))
PY
for f in /usr/libexec/lucciola/session-start /usr/libexec/lucciola/lock; do
  [[ -x "$f" ]] || { echo "ERROR: $f missing or not executable" >&2; exit 1; }
done
rpm -q niri noctalia xwayland-satellite

dnf5 clean all
rm -rf /var/cache/libdnf5/* /var/lib/dnf/* /var/log/dnf5.log* 2>/dev/null || true
log "done"
