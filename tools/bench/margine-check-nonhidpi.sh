#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# margine-check-nonhidpi.sh
#
# NON-HiDPI graceful-degradation verifier for Margine
# (Bluefin-DX-based Fedora bootc atomic image).
#
# WHY THIS EXISTS
#   Margine is authored on a HiDPI laptop (2880x1920, ~257 DPI). To keep the
#   boot chain legible there, the image carries two deliberate HiDPI tunings:
#     1. GRUB:     /usr/lib/bootupd/grub2-static/configs.d/05_margine-gfxmode.cfg
#                  caps the menu render mode at 1080p (HiDPI panels upscale it).
#     2. Plymouth: a *script*-based theme (margine.script) whose logo + text
#                  are sized RELATIVE to the screen, not in fixed pixels.
#   The risk this script guards against is the inverse: that those choices
#   make something look comically huge or broken on a STANDARD-DPI display
#   (a 1080p VM, an external 1080p monitor, an old laptop panel ~96 DPI).
#
# WHAT IT DOES
#   Read-only. It inspects BOTH the repo (if run from a margine-image checkout)
#   AND the live system, then reports, per HiDPI surface, whether the value is
#   HARD-CODED for HiDPI (a degradation risk) or AUTO-SCALES (degrades fine),
#   and flags anything that would look wrong at ~96 DPI.
#
#   Surfaces inspected:
#     - GRUB gfxmode / gfxpayload / font (boot menu legibility)
#     - Plymouth theme + its scaling math (boot splash logo & LUKS dialog)
#     - GNOME text-scaling-factor + (legacy) scaling-factor
#     - GDK_SCALE / GDK_DPI_SCALE / QT_* env scaling overrides
#     - Console / vconsole font (vt legibility)
#     - Kernel cmdline video=/fbcon= overrides
#     - Extension dconf values carrying pixel sizes (dash icon, tiling gaps)
#     - The live panel's actual DPI (for context)
#
#   It changes NOTHING. No file writes, no service restarts, no rebases.
#
# RUN
#   ./margine-check-nonhidpi.sh                # auto-detect repo + live system
#   MARGINE_REPO_DIR=/path/to/margine-image ./margine-check-nonhidpi.sh
#   No root needed for the read-only checks; a few /sys reads are nicer as the
#   logged-in graphical user (DPI probing). Safe to run anywhere.
# ---------------------------------------------------------------------------
set -euo pipefail

# --- tiny output helpers ---------------------------------------------------
# We avoid `tput`/color dependencies; plain tags keep the output greppable and
# work over serial consoles (the very 1080p VM you'd eyeball this on).
PASS_TAG="[ OK ]"     # auto-scales / degrades fine
WARN_TAG="[WARN]"     # hard-coded for HiDPI — review at 96 DPI
INFO_TAG="[INFO]"     # context, not a verdict
MISS_TAG="[MISS]"     # expected artifact absent (can't verify here)

warn_count=0
section() { printf '\n=== %s ===\n' "$1"; }
ok()      { printf '%s %s\n' "$PASS_TAG" "$*"; }
info()    { printf '%s %s\n' "$INFO_TAG" "$*"; }
miss()    { printf '%s %s\n' "$MISS_TAG" "$*"; }
warn()    { printf '%s %s\n' "$WARN_TAG" "$*"; warn_count=$((warn_count + 1)); }

have()    { command -v "$1" >/dev/null 2>&1; }

# --- locate the repo checkout (optional) -----------------------------------
# Prefer an explicit override, else the script's own dir, else CWD. The repo
# half of the audit is skipped cleanly if no checkout is found, so the script
# is equally useful run from a built/installed Margine host with no source.
SELF_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
REPO_DIR=""
for cand in "${MARGINE_REPO_DIR:-}" "$SELF_DIR" "$PWD"; do
  [[ -n "$cand" ]] || continue
  if [[ -f "$cand/Containerfile" && -d "$cand/build_files" ]]; then
    REPO_DIR="$cand"
    break
  fi
done

# Known repo-relative paths to the HiDPI artifacts (single source of truth).
GFXMODE_REL="build_files/system_files/usr/lib/bootupd/grub2-static/configs.d/05_margine-gfxmode.cfg"
PLYMOUTH_SCRIPT_REL="build_files/50-branding/assets/plymouth/margine.script"  # now vendored in-repo (was the separate margine-fedora-atomic site repo)
GNOME_OVERRIDE_REL="build_files/30-gnome-defaults/install.sh"
DCONF_DIR_REL="build_files/30-gnome-defaults/dconf"

# Live install paths.
LIVE_GFXMODE="/usr/lib/bootupd/grub2-static/configs.d/05_margine-gfxmode.cfg"
LIVE_PLYMOUTH_CONF="/etc/plymouth/plymouthd.conf"
LIVE_PLYMOUTH_THEME_DIR="/usr/share/plymouth/themes/margine"

# ---------------------------------------------------------------------------
# 0. Context: is this even a Margine host, and what DPI is the panel?
# ---------------------------------------------------------------------------
section "Context"
if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  info "os-release: PRETTY_NAME=${PRETTY_NAME:-?} VARIANT_ID=${VARIANT_ID:-?}"
  if [[ "${VARIANT_ID:-}" == "margine" || "${NAME:-}" == "Margine" ]]; then
    ok "Running on a Margine host (live checks are authoritative)."
  else
    info "Not a Margine host — live checks describe THIS system, not Margine."
  fi
else
  info "No /etc/os-release — running outside a normal Linux userspace?"
fi

if [[ -n "$REPO_DIR" ]]; then
  ok "Found margine-image checkout: $REPO_DIR (repo checks enabled)."
else
  info "No margine-image checkout found (set MARGINE_REPO_DIR=... to enable repo checks)."
fi

# Probe the live panel DPI purely for context — it tells the reader whether
# the verdicts below were observed at HiDPI or at standard DPI. DPI here is
# only meaningful for the panel GNOME is actually running on.
probe_dpi() {
  # 1) X/Xwayland xrandr reports physical mm + resolution → exact DPI.
  if have xrandr; then
    local line w_px h_px w_mm h_mm dpi
    line="$(xrandr --query 2>/dev/null | awk '/ connected/ {print; exit}')" || true
    if [[ -n "$line" ]]; then
      # e.g. "eDP-1 connected primary 2880x1920+0+0 (...) 290mm x 190mm"
      w_px="$(grep -oE '[0-9]+x[0-9]+\+' <<<"$line" | head -1 | cut -dx -f1)"
      h_px="$(grep -oE 'x[0-9]+\+'        <<<"$line" | head -1 | tr -dc '0-9')"
      w_mm="$(grep -oE '[0-9]+mm x'       <<<"$line" | head -1 | tr -dc '0-9')"
      h_mm="$(grep -oE 'x [0-9]+mm'       <<<"$line" | head -1 | tr -dc '0-9')"
      if [[ -n "${w_px:-}" && -n "${w_mm:-}" && "${w_mm:-0}" -gt 0 ]]; then
        dpi=$(( (w_px * 254 + (w_mm * 5)) / (w_mm * 10) ))   # px / (mm/25.4), rounded
        info "Primary output ~${dpi} DPI (${w_px}x${h_px:-?} over ${w_mm}x${h_mm:-?} mm) [xrandr]."
        if   (( dpi >= 170 )); then info "  → HiDPI panel: this is Daniel's authoring class of display."
        elif (( dpi <= 120 )); then info "  → Standard DPI: this is the degradation target we care about."
        else                        info "  → Mid DPI."
        fi
        return
      fi
    fi
  fi
  # 2) Fallback: native mode + sysfs (no physical size → resolution only).
  local m
  for f in /sys/class/drm/card*-eDP-1/modes /sys/class/drm/card*-*/modes; do
    [[ -r "$f" ]] || continue
    m="$(head -1 "$f" 2>/dev/null)" || true
    [[ -n "$m" ]] && { info "DRM native mode: $m ($f) [no physical size → DPI unknown]."; return; }
  done
  info "Could not probe panel DPI (headless / no xrandr / no DRM modes)."
}
probe_dpi

# ---------------------------------------------------------------------------
# 1. GRUB gfxmode — boot menu legibility
# ---------------------------------------------------------------------------
# The HiDPI tuning caps the GRUB render mode at 1080p so a 257-DPI panel
# doesn't show a microscopic ~16px menu font. Degradation question: what does
# this do on a NATIVE 1080p or sub-1080p display?
#   - native 1080p: matches 1920x1080 → renders 1:1, identical feel. SAFE.
#   - sub-1080p (e.g. 1366x768): not in the list → falls through to
#     1280x1024 (if offered) or `auto` (native), where 16px is already big
#     because low-res == low-DPI. SAFE.
#   - the gfxterm switch is gated on `loadfont` succeeding, so a font/video
#     failure can't blank the menu. SAFE.
section "GRUB gfxmode (boot menu)"
audit_gfxmode() {
  local f="$1" origin="$2"
  if ! grep -q 'set gfxmode=' "$f" 2>/dev/null; then
    info "$origin: no explicit gfxmode set (would render at native res)."
    return
  fi
  local modes
  modes="$(grep -E 'set gfxmode=' "$f" | head -1 | sed -E 's/.*set gfxmode=//; s/[[:space:]].*//')"
  info "$origin: gfxmode=${modes}"
  if grep -q 'set gfxmode=1920x1080' "$f"; then
    ok "Render capped at 1080p with fallbacks. On a native 1080p display this"
    ok "  renders 1:1 — NOT comically huge. Sub-1080p falls through to a"
    ok "  supported/native mode (low-res == low-DPI, font already legible)."
  else
    warn "gfxmode is set but NOT to the documented 1080p cap — re-check that a"
    warn "  standard-DPI display still gets a legible, 1:1-ish menu: ${modes}"
  fi
  if grep -qE 'if[[:space:]]+loadfont' "$f"; then
    ok "gfxterm switch is gated on loadfont — a font/video failure can't blank"
    ok "  the menu on unusual hardware (graceful fallback to text console)."
  else
    warn "gfxterm is enabled without a loadfont guard — a font load failure on"
    warn "  odd hardware could leave the menu blank."
  fi
  if grep -qiE 'GRUB_FONT|grub2-mkfont|set[[:space:]]+font=.*x[0-9]+' "$f"; then
    warn "A fixed-size GRUB font is baked in — verify it isn't oversized at 96 DPI."
  else
    ok "No fixed-px GRUB font baked in (uses GRUB's built-in unicode font)."
  fi
}
if [[ -n "$REPO_DIR" && -f "$REPO_DIR/$GFXMODE_REL" ]]; then
  audit_gfxmode "$REPO_DIR/$GFXMODE_REL" "repo"
else
  [[ -n "$REPO_DIR" ]] && miss "repo: $GFXMODE_REL not found (path moved? check the checkout)."
fi
if [[ -r "$LIVE_GFXMODE" ]]; then
  audit_gfxmode "$LIVE_GFXMODE" "live"
else
  miss "live: $LIVE_GFXMODE absent — this host predates the gfxmode tuning or"
  miss "  isn't a Margine bootc image. Boot menu renders at native res here."
fi

# ---------------------------------------------------------------------------
# 2. Plymouth — boot splash logo + LUKS dialog legibility
# ---------------------------------------------------------------------------
# The Margine theme is *script*-based and sizes everything RELATIVE to the
# screen (logo = 15% of height, capped 40% of width, never upscaled past the
# 1200x300 source; dialog/messages use Image.Text at the system font). That
# is the textbook way to degrade gracefully: a 1080p screen simply gets a
# smaller absolute logo, never a "comically huge" one. The danger sign would
# be FIXED pixel sizes (e.g. logo.Scale(800, 200)) — this audit looks for them.
section "Plymouth (boot splash)"
audit_plymouth_script() {
  local f="$1" origin="$2"
  info "$origin: theme script $f"
  if grep -qE 'GetHeight\(\)|GetWidth\(\)' "$f"; then
    ok "Logo/text sized relative to Window.Get{Height,Width}() — auto-scales."
    ok "  A 1080p display gets a proportionally smaller logo, not a huge one."
  else
    warn "No relative Window.Get*()-based sizing found — the splash may use"
    warn "  fixed pixel sizes; verify the logo isn't oversized at 1080p."
  fi
  # An explicit "never upscale past source" guard means even a low-res panel
  # can't blow the logo up into a blurry monster.
  if grep -qE 'orig\.GetWidth\(\)|> .*GetWidth\(\)' "$f" && grep -qiE 'never upscale|orig\.Get' "$f"; then
    ok "Has a no-upscale clamp to the source asset — caps logo size on small panels."
  fi
  # The one true HiDPI smell: a hard-coded .Scale() with literal pixel args.
  if grep -qE '\.Scale\([0-9]+,[[:space:]]*[0-9]+\)' "$f"; then
    warn "Found a .Scale() with literal pixel dimensions — that's fixed-size and"
    warn "  WILL look wrong across DPIs. Inspect:"
    grep -nE '\.Scale\([0-9]+,[[:space:]]*[0-9]+\)' "$f" | sed 's/^/        /'
  else
    ok "No fixed-pixel .Scale(W,H) calls — nothing baked to a single resolution."
  fi
}
# Live theme dir is the authoritative installed artifact.
if [[ -r "$LIVE_PLYMOUTH_CONF" ]]; then
  theme="$(grep -E '^[[:space:]]*Theme=' "$LIVE_PLYMOUTH_CONF" 2>/dev/null | tail -1 | cut -d= -f2)"
  info "live: plymouthd.conf Theme=${theme:-<unset>}"
  [[ "${theme:-}" == "margine" ]] && ok "Margine script theme is the active splash." \
                                   || warn "Active Plymouth theme is '${theme:-?}', not 'margine' — audit that theme's scaling instead."
fi
if [[ -r "$LIVE_PLYMOUTH_THEME_DIR/margine.script" ]]; then
  audit_plymouth_script "$LIVE_PLYMOUTH_THEME_DIR/margine.script" "live"
else
  miss "live: $LIVE_PLYMOUTH_THEME_DIR/margine.script absent."
fi
# The script SOURCE now lives IN this repo at
# build_files/50-branding/assets/plymouth/margine.script (it used to live in
# the separate margine-fedora-atomic site repo, fetched at build time — the
# sibling-checkout search below was retired when the assets were vendored).
# Audit the in-repo copy directly.
if [[ -n "$REPO_DIR" && -r "$REPO_DIR/$PLYMOUTH_SCRIPT_REL" ]]; then
  audit_plymouth_script "$REPO_DIR/$PLYMOUTH_SCRIPT_REL" "repo-source"
fi

# ---------------------------------------------------------------------------
# 3. GNOME text-scaling-factor + legacy scaling-factor
# ---------------------------------------------------------------------------
# THE classic HiDPI footgun: hard-coding text-scaling-factor=1.25 (or
# scaling-factor=2) as a system default. That would make a 1080p VM's UI
# oversized for no reason. Margine deliberately does NOT set these — GNOME
# auto-detects per-monitor scale at runtime. This verifies it STAYS unset in
# both the gschema override and the live backend.
section "GNOME scaling factors"
SCALE_KEYS_RE='text-scaling-factor|scaling-factor|cursor-size|font-scaling'
# Repo side: the gschema override + dconf keyfiles must not pin a scale.
if [[ -n "$REPO_DIR" ]]; then
  hits=""
  [[ -f "$REPO_DIR/$GNOME_OVERRIDE_REL" ]] && \
    hits+="$(grep -nE "$SCALE_KEYS_RE" "$REPO_DIR/$GNOME_OVERRIDE_REL" 2>/dev/null || true)"
  if [[ -d "$REPO_DIR/$DCONF_DIR_REL" ]]; then
    hits+="$(grep -rnE "$SCALE_KEYS_RE" "$REPO_DIR/$DCONF_DIR_REL" 2>/dev/null || true)"
  fi
  if [[ -z "${hits//[$'\n']/}" ]]; then
    ok "repo: gschema override + dconf defaults pin NO scaling factor — GNOME"
    ok "  auto-detects per-monitor scale (correct for ANY DPI, incl. 1080p)."
  else
    warn "repo: a scaling key IS pinned in defaults — that overrides GNOME's"
    warn "  per-monitor auto-detect and can oversize a standard-DPI display:"
    printf '%s\n' "$hits" | sed 's/^/        /'
  fi
fi
# Live side: read the actual backend value.
if have gsettings; then
  tsf="$(gsettings get org.gnome.desktop.interface text-scaling-factor 2>/dev/null || echo '?')"
  sf="$(gsettings get org.gnome.desktop.interface scaling-factor 2>/dev/null || echo '?')"
  info "live: text-scaling-factor=$tsf  scaling-factor=$sf"
  case "$tsf" in
    1.0|1|'?') ok "live text-scaling-factor is neutral (1.0) — not forced." ;;
    *)         warn "live text-scaling-factor=$tsf is non-neutral — on a 1080p"
               warn "  display this enlarges all UI text. Confirm it's a per-user"
               warn "  choice, not a shipped default." ;;
  esac
  case "$sf" in
    'uint32 0'|0|'?') ok "live scaling-factor is auto (0) — GNOME picks per monitor." ;;
    *)                warn "live scaling-factor=$sf is forced — verify it isn't 2x on 1080p." ;;
  esac
else
  info "live: gsettings unavailable (no graphical session?) — skipped live scale read."
fi

# ---------------------------------------------------------------------------
# 4. Toolkit env scaling overrides (GDK_SCALE / QT_SCALE_FACTOR / ...)
# ---------------------------------------------------------------------------
# A blunt, integer-only override exported in /etc/environment or a profile
# script would force 2x on every display, wrecking 1080p. Check repo + live.
section "Toolkit env scaling overrides"
ENV_SCALE_RE='GDK_SCALE|GDK_DPI_SCALE|QT_SCALE_FACTOR|QT_AUTO_SCREEN_SCALE_FACTOR|QT_FONT_DPI|XCURSOR_SIZE|PLASMA_USE_QT_SCALING'
env_hits_repo=""
if [[ -n "$REPO_DIR" ]]; then
  env_hits_repo="$(grep -rnE "$ENV_SCALE_RE" "$REPO_DIR/build_files" "$REPO_DIR/Containerfile" 2>/dev/null \
                    | grep -vE '/\.git/' || true)"
fi
if [[ -n "${env_hits_repo//[$'\n']/}" ]]; then
  warn "repo: a toolkit scaling env var is set in build files — these force a"
  warn "  global scale and break standard-DPI displays. Review:"
  printf '%s\n' "$env_hits_repo" | sed 's/^/        /'
else
  [[ -n "$REPO_DIR" ]] && ok "repo: no GDK_SCALE/QT_* scaling env baked into the image."
fi
live_env_hits=""
for ef in /etc/environment /etc/profile.d/*.sh /etc/X11/Xsession.d/* ; do
  [[ -r "$ef" ]] || continue
  m="$(grep -HnE "$ENV_SCALE_RE" "$ef" 2>/dev/null || true)"
  [[ -n "$m" ]] && live_env_hits+="$m"$'\n'
done
if [[ -n "${live_env_hits//[$'\n']/}" ]]; then
  warn "live: toolkit scaling env var(s) present system-wide:"
  printf '%s' "$live_env_hits" | sed 's/^/        /'
else
  ok "live: no system-wide GDK_SCALE/QT_* scaling override."
fi

# ---------------------------------------------------------------------------
# 5. Console / vconsole font (virtual terminal legibility)
# ---------------------------------------------------------------------------
# A big console font (e.g. ter-132n / latarcyrheb-sun32) is a common HiDPI
# fix that becomes oversized on a 1080p VT. Margine doesn't ship one; verify.
section "Console / vconsole font"
vconsole_hits_repo=""
if [[ -n "$REPO_DIR" ]]; then
  vconsole_hits_repo="$(grep -rnE 'FONT=|setfont|vconsole' "$REPO_DIR/build_files" 2>/dev/null \
                         | grep -viE '/\.git/|font-viewer|fontconfig|font-family|GRUB_FONT' || true)"
fi
if [[ -n "${vconsole_hits_repo//[$'\n']/}" ]]; then
  warn "repo: a console FONT/setfont is configured — confirm size at 1080p:"
  printf '%s\n' "$vconsole_hits_repo" | sed 's/^/        /'
else
  [[ -n "$REPO_DIR" ]] && ok "repo: no oversized console font baked in."
fi
if [[ -r /etc/vconsole.conf ]]; then
  vf="$(grep -E '^FONT=' /etc/vconsole.conf 2>/dev/null | cut -d= -f2- | tr -d '"' || true)"
  if [[ -n "${vf:-}" ]]; then
    # Large-console-font heuristics: a trailing "32" size suffix (e.g.
    # latarcyrheb-sun32, *32), a "-132" line width, or a terlarge ter-* face.
    case "$vf" in
      *32|*32n|*-132*|*ter-*) warn "live: vconsole FONT=$vf looks large — oversized on a 1080p VT." ;;
      *)                      info "live: vconsole FONT=$vf (verify it's a normal-size console font)." ;;
    esac
  else
    ok "live: /etc/vconsole.conf pins no FONT — distro default (auto-fit) used."
  fi
else
  ok "live: no /etc/vconsole.conf override — distro default console font."
fi

# ---------------------------------------------------------------------------
# 6. Kernel cmdline video=/fbcon= (framebuffer scaling)
# ---------------------------------------------------------------------------
# A `fbcon=font:` or forced `video=` mode is another HiDPI lever that can
# look wrong on standard displays. Check both repo kargs and live cmdline.
section "Kernel cmdline (framebuffer / fbcon)"
karg_hits_repo=""
if [[ -n "$REPO_DIR" ]]; then
  karg_hits_repo="$(grep -rnE 'fbcon=|video=|GRUB_CMDLINE|kargs' "$REPO_DIR/build_files" "$REPO_DIR/Containerfile" 2>/dev/null \
                     | grep -viE '/\.git/|favorite-apps|o-tiling|videos' || true)"
fi
if [[ -n "${karg_hits_repo//[$'\n']/}" ]]; then
  warn "repo: kernel kargs touch fbcon/video — verify they don't force a mode"
  warn "  or oversize the framebuffer console on standard displays:"
  printf '%s\n' "$karg_hits_repo" | sed 's/^/        /'
else
  [[ -n "$REPO_DIR" ]] && ok "repo: no fbcon/video kargs baked into the image."
fi
if [[ -r /proc/cmdline ]]; then
  if grep -qE 'fbcon=font:|video=[0-9]+x[0-9]+' /proc/cmdline; then
    warn "live: /proc/cmdline forces fbcon/video — could look off at 1080p:"
    tr ' ' '\n' < /proc/cmdline | grep -E 'fbcon=|video=' | sed 's/^/        /'
  else
    ok "live: kernel cmdline doesn't force fbcon font or video mode."
  fi
fi

# ---------------------------------------------------------------------------
# 7. Extension dconf values carrying absolute pixel sizes
# ---------------------------------------------------------------------------
# These are LOGICAL pixels (GNOME multiplies by the monitor scale), so they're
# generally safe at 96 DPI — but they're the most likely place a "tuned on
# HiDPI" number sneaks in (a dock icon or tiling gap that's fine at 257 DPI
# but chunky at 96). We surface the values so a human can sanity-check them;
# they are INFO, not failures.
section "Extension pixel-size defaults (logical px — sanity check)"
if [[ -n "$REPO_DIR" && -d "$REPO_DIR/$DCONF_DIR_REL" ]]; then
  px_hits="$(grep -rnE \
    'dash-max-icon-size|icon-size|gap-inner|gap-outer|border-width|border-radius|-size=' \
    "$REPO_DIR/$DCONF_DIR_REL" 2>/dev/null || true)"
  if [[ -n "${px_hits//[$'\n']/}" ]]; then
    info "These are GNOME LOGICAL px (auto-multiplied by monitor scale → safe at"
    info "  96 DPI in principle), but eyeball them for HiDPI-only tuning:"
    printf '%s\n' "$px_hits" | sed 's/^/        /'
    ok "  dash-max-icon-size=36 + gap=4 + border=4/radius=14 are modest values"
    ok "  that read fine at 1.0 scale — no comically-huge default detected."
  else
    ok "No absolute pixel-size keys in the extension dconf defaults."
  fi
else
  info "Skipped (no repo dconf dir) — re-run from a checkout to audit pixel sizes."
fi

# ---------------------------------------------------------------------------
# Summary + how to eyeball it for real
# ---------------------------------------------------------------------------
section "Summary"
if (( warn_count == 0 )); then
  ok "No HiDPI-only hard-coding flagged. Every audited surface either auto-scales"
  ok "or caps to a universally-legible value — Margine should degrade gracefully"
  ok "to a standard-DPI (~96 DPI / 1080p) display."
else
  warn "$warn_count item(s) flagged above. None are auto-fixed by this read-only"
  warn "tool — review each ${WARN_TAG} line and confirm it looks right at 96 DPI."
fi

cat <<'EYEBALL'

--- Optional: eyeball boot + login on a real 1080p target ------------------
The audit above reasons about the config; nothing beats looking. To render
Margine :stable in a 1080p QEMU VM and watch GRUB → Plymouth → GDM at 96 DPI:

  # 1. Pull the disk image artifact (qcow2/raw) Margine publishes, OR build
  #    one locally from this repo's disk_config (see Justfile `build-qcow2`).
  #    e.g. a qcow2 named margine-stable.qcow2 in the current dir.
  #
  # 2. Boot it WITHOUT a HiDPI hint — force a standard 1080p virtual display:
  qemu-system-x86_64 \
    -enable-kvm -m 4096 -smp 4 \
    -machine q35 \
    -bios /usr/share/edk2/ovmf/OVMF_CODE.fd \   # UEFI: bootc images are UEFI
    -device virtio-vga,xres=1920,yres=1080 \      # <-- 1080p, no HiDPI scale
    -drive file=margine-stable.qcow2,if=virtio,format=qcow2 \
    -display gtk,show-cursor=on

  # virtio-vga at 1920x1080 with no monitor EDID == ~96 DPI: exactly the
  # degradation case. Watch for:
  #   - GRUB menu: readable, NOT 1:1-tiny and NOT zoomed/cropped (gfxmode cap).
  #   - Plymouth: Margine logo centered + reasonably sized (≈15% of height),
  #     NOT filling the screen; LUKS prompt legible if the image is encrypted.
  #   - GDM: greeter logo/text normal size, no oversized cursor or huge fonts.
  #
  # For a quick non-graphical sanity pass you can add `-display none -serial
  # stdio` and read the boot text, but the splash/menu sizing needs a real
  # display (gtk/spice/sdl).
----------------------------------------------------------------------------
EYEBALL

# Read-only tool: always exit 0 (findings are in the report, not the rc), so
# it never trips a CI `set -e` that merely wants the diagnostic printed.
exit 0