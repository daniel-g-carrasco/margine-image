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

# 2b. GNOME stays stock. Lucciola keeps GNOME as a fallback session only,
#     and stock: without the extensions Margine adds (its own builds and
#     the ones the base image ships as RPMs), without the Shell,
#     window-manager and settings-daemon defaults that go with them
#     (enabled extensions, favourites, workspaces, focus mode, keybindings)
#     and without the first-login bootstrap of a GNOME session. Whole
#     sections of the gschema overrides are dropped or kept: the ones that
#     also serve the GTK applications of a Lucciola session (fonts, accent
#     colour, wallpaper, file chooser, Ptyxis, Nautilus, virt-manager)
#     stay. GNOME's own gnome-shell-extensions package (the Classic session
#     set) is part of stock GNOME and stays.
log "GNOME stays stock: removing the extensions and the Shell defaults"
mapfile -t ext_rpms < <(rpm -qa --qf '%{NAME} %{SOURCERPM}\n' 'gnome-shell-extension-*' \
  | awk '$2 !~ /^gnome-shell-extensions-/ { print $1 }')
if (( ${#ext_rpms[@]} )); then
  log "  RPM extensions: ${ext_rpms[*]}"
  dnf5 -y --setopt=clean_requirements_on_remove=False remove "${ext_rpms[@]}"
  rpm -q gnome-shell gdm gnome-control-center >/dev/null || { echo "ERROR: removing the extensions took GNOME with them" >&2; exit 1; }
fi
for d in /usr/share/gnome-shell/extensions/*/; do
  d="${d%/}"
  [[ -d "$d" ]] || continue   # the glob itself, when the directory is empty
  rpm -qf "$d" >/dev/null 2>&1 && continue
  rm -rf "$d"
  log "  removed $(basename "$d")"
done
for f in /usr/share/glib-2.0/schemas/org.gnome.shell.extensions.*.gschema.xml; do
  [[ -e "$f" ]] || continue
  rpm -qf "$f" >/dev/null 2>&1 || rm -f "$f"
done
# A section goes with the comment lines right above it.
python3 - /usr/share/glib-2.0/schemas/zz0-bluefin-modifications.gschema.override \
          /usr/share/glib-2.0/schemas/zz1-margine.gschema.override <<'PY'
import re, sys
drop = re.compile(r'^\[org\.gnome\.(shell|mutter|desktop\.wm|desktop\.app-folders'
                  r'|desktop\.search-providers|desktop\.peripherals|settings-daemon)[.\]:]')
for path in sys.argv[1:]:
    out, pending, keep = [], [], True
    for line in open(path):
        if line.startswith('['):
            keep = not drop.match(line)
            if keep:
                out += pending + [line]
            pending = []
        elif not line.strip() or line.lstrip().startswith('#'):
            pending.append(line)
        elif keep:
            out += pending + [line]
            pending = []
        else:
            pending = []
    if keep:
        out += pending
    open(path, 'w').write(''.join(out).lstrip('\n'))
PY
rm -f /usr/share/glib-2.0/schemas/zz1-bluefin-extensions.gschema.override
out="$(glib-compile-schemas /usr/share/glib-2.0/schemas 2>&1)" || { echo "$out" >&2; exit 1; }
if grep -q 'org\.gnome\.shell' <<<"$out"; then
  echo "$out" >&2; echo "ERROR: an override still names a removed Shell schema" >&2; exit 1
fi
# dconf defaults: every file that sets a Shell, mutter, window-manager or
# settings-daemon path goes (the authselect one does not).
for f in /etc/dconf/db/distro.d/*; do
  [[ -f "$f" ]] || continue
  if grep -q -E '^\[org/gnome/(shell|mutter|desktop/wm|desktop/app-folders|desktop/search-providers|desktop/peripherals|settings-daemon)(/|\])' "$f"; then
    rm -f "$f"
    log "  removed dconf $(basename "$f")"
  fi
done
dconf update
rm -f /etc/xdg/autostart/margine-first-boot.desktop /etc/xdg/autostart/margine-first-boot-status.desktop
for d in /usr/share/gnome-shell/extensions/*/; do
  [[ -d "$d" ]] || continue
  rpm -qf "${d%/}" >/dev/null 2>&1 || { echo "ERROR: unowned extension survived: $d" >&2; exit 1; }
done
if grep -l 'enabled-extensions' /usr/share/glib-2.0/schemas/zz*.gschema.override 2>/dev/null; then
  echo "ERROR: an override still enables extensions" >&2; exit 1
fi
for f in /etc/dconf/db/distro.d/*margine* /etc/dconf/db/distro.d/*shell*; do
  [[ -e "$f" ]] && { echo "ERROR: Margine's GNOME dconf defaults survived: $f" >&2; exit 1; }
done
log "GNOME extensions left: $(ls /usr/share/gnome-shell/extensions/ 2>/dev/null | tr '\n' ' ')"

# 2c. Lucciola is the session a new user gets. accounts-daemon fills a
#     user's record from these templates the first time it sees the user
#     and GDM preselects the session written there; whoever picks GNOME on
#     the login screen keeps GNOME from then on. Users that already have a
#     record (an install moved from Margine) are not touched.
for t in standard administrator; do
  f="/usr/share/accountsservice/user-templates/$t"
  grep -q '^Session=' "$f" || { echo "ERROR: $f has no Session key: the accountsservice template layout changed" >&2; exit 1; }
  sed -i 's/^Session=.*/Session=lucciola/' "$f"
  grep -q '^Session=lucciola$' "$f" || { echo "ERROR: $f not rewritten" >&2; exit 1; }
done

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
for f in /usr/libexec/lucciola/{session-start,lock,bar-widths,color-calibration}; do
  [[ -x "$f" ]] || { echo "ERROR: $f missing or not executable" >&2; exit 1; }
done
# The Python helpers must at least parse (ast, so no __pycache__ in /usr).
for f in /usr/libexec/lucciola/{bar-widths,color-calibration}; do
  python3 -c 'import ast, sys; ast.parse(open(sys.argv[1]).read(), sys.argv[1])' "$f"
done
rpm -q niri noctalia xwayland-satellite

dnf5 clean all
rm -rf /var/cache/libdnf5/* /var/lib/dnf/* /var/log/dnf5.log* 2>/dev/null || true
log "done"
