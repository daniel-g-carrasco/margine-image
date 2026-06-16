#!/usr/bin/env bash
# Layer A file-level validation of a built (pre-rechunk) Margine image.
#
#   usage: sudo .github/scripts/validate-image-rootfs.sh <image-ref>
#
# Extracted from build.yml's inline run: block (2026-06-12 review,
# phase 3) so it is shellcheck-gated, reviewable as a file, and
# runnable locally against any locally built image:
#   sudo .github/scripts/validate-image-rootfs.sh localhost/margine:latest
#
# Guardrail against the 5 first-boot regressions surfaced on the
# 2026-06-06 fresh install (Bluefin logo in About, missing welcome
# screen icon, extensions not installed, no background-Flatpak toast,
# icon-size drift). Runs BEFORE rechunk/push/SBOM/sign so a regression
# fails fast instead of leaking into :stable. The grep sentinels here
# overlap the shipped validators (run in-container by a sibling CI
# step) on purpose during the adoption window — once the in-container
# run has two green runs, the duplicated checks below get deleted.
set -euo pipefail

IMAGE_REF="${1:?usage: validate-image-rootfs.sh <image-ref>}"

podman container create --replace --name validate-fs \
  --entrypoint /bin/true "$IMAGE_REF" >/dev/null
ROOTFS=$(mktemp -d)
trap 'rm -rf "$ROOTFS"; podman rm validate-fs >/dev/null 2>&1 || true' EXIT
podman export validate-fs | tar -C "$ROOTFS" -xf -

fail=0
check_file() { [[ -f "$ROOTFS/$1" ]] || { echo "::error::missing file $1 ($2)"; fail=1; }; }
check_dir()  { [[ -d "$ROOTFS/$1" ]] || { echo "::error::missing dir $1 ($2)";  fail=1; }; }
check_nonempty() { [[ -s "$ROOTFS/$1" ]] || { echo "::error::file $1 missing or empty ($2)"; fail=1; }; }
check_exec() { [[ -x "$ROOTFS/$1" ]] || { echo "::error::not executable $1 ($2)"; fail=1; }; }

# A.1 — About-panel logo: os-release LOGO + asset on disk
if ! grep -qE '^LOGO=margine-logo$' "$ROOTFS/etc/os-release"; then
  echo "::error::A.1 /etc/os-release does not declare LOGO=margine-logo"; fail=1
fi
if [[ ! -f "$ROOTFS/usr/share/pixmaps/margine-logo.png" && ! -f "$ROOTFS/usr/share/pixmaps/margine-logo.svg" ]]; then
  echo "::error::A.1 /usr/share/pixmaps/margine-logo.{png,svg} missing"; fail=1
fi
check_nonempty "usr/share/pixmaps/fedora_logo_med.png" "A.1"
check_nonempty "usr/share/pixmaps/fedora_whitelogo_med.png" "A.1"

# A.2 — Welcome screen icon: present + non-empty (retry_curl_strict)
check_nonempty "usr/share/icons/Adwaita/symbolic/places/start-here-symbolic.svg" "A.2"
if grep -Eiq '<image[[:space:]>]|data:image/' "$ROOTFS/usr/share/icons/Adwaita/symbolic/places/start-here-symbolic.svg"; then
  echo "::error::A.2 start-here-symbolic.svg embeds a raster image; GTK4 symbolic icons require path/circle/rect primitives"; fail=1
fi

# A.3 — Every baked extension installed system-wide (9 enabled by default +
# blur-my-shell, which is installed-but-not-enabled-by-default — kept so a
# user can re-enable it with the smooth STATIC defaults in
# dconf/05-margine-blur-my-shell; dropped from the enabled set 2026-06-16 for
# 120Hz-iGPU jank + upstream bugs).
# (search-light is likewise NOT enabled by Margine — GNOME-native search
# replaces it — but it stays installed by Bluefin and patched by us; its
# presence + crash patches are still asserted by A.3.ter below.)
for uuid in \
  appindicatorsupport@rgcjonas.gmail.com \
  bazaar-integration@kolunmi.github.io \
  blur-my-shell@aunetx \
  dash-to-dock@micxgx.gmail.com \
  gradia-integration@alexandervanhee.github.io \
  gsconnect@andyholmes.github.io \
  o-tiling@oliwebd.github.com \
  hide-cursor@elcste.com \
  caffeine@patapon.info \
  smile-extension@mijorus.it; do
  check_dir "usr/share/gnome-shell/extensions/$uuid" "A.3"
done

# A.4 — First-boot notify autostart + libexec
check_file "etc/xdg/autostart/margine-first-boot.desktop" "A.4"
check_file "etc/xdg/autostart/margine-first-boot-status.desktop" "A.4"
check_exec "usr/libexec/margine-first-boot-status" "A.4"

# A.4.gfx — GRUB HiDPI legibility via a BAKED LARGE FONT (2026-06-16, was a
# gfxmode-low scheme that firmware ignored on amdgpu UEFI = no-op). Assert the
# image ships: the generated font, a drop-in that loadfonts it + selects it
# via gfxterm_font + switches to gfxterm, and the re-render helper (bootupd
# does NOT re-render the static config on `bootc upgrade`, so existing installs
# need `ujust margine-grub-hidpi`).
GRUB_GFX="usr/lib/bootupd/grub2-static/configs.d/05_margine-gfxmode.cfg"
check_file "$GRUB_GFX" "A.4.gfx"
check_nonempty "usr/lib/bootupd/grub2-static/fonts/margine.pf2" "A.4.gfx"
check_exec "usr/libexec/margine/grub-hidpi-apply" "A.4.gfx"
# The re-render runs automatically at boot (the bootloader on /boot isn't
# updated by image upgrades) — assert the service ships AND is enabled.
check_file "usr/lib/systemd/system/margine-grub-hidpi.service" "A.4.gfx"
test -L "$ROOTFS/usr/lib/systemd/system/multi-user.target.wants/margine-grub-hidpi.service" \
  || { echo "::error::A.4.gfx margine-grub-hidpi.service is not enabled (multi-user.target.wants symlink missing) — GRUB font won't auto-apply"; fail=1; }
grep -q 'loadfont .*margine\.pf2' "$ROOTFS/$GRUB_GFX" 2>/dev/null \
  || { echo "::error::A.4.gfx GRUB drop-in does not loadfont the baked margine.pf2 — menu stays tiny on HiDPI"; fail=1; }
grep -q '^[[:space:]]*set gfxterm_font=' "$ROOTFS/$GRUB_GFX" 2>/dev/null \
  || { echo "::error::A.4.gfx GRUB drop-in does not set gfxterm_font — gfxterm would fall back to its tiny built-in font"; fail=1; }
grep -q 'terminal_output gfxterm' "$ROOTFS/$GRUB_GFX" 2>/dev/null \
  || { echo "::error::A.4.gfx GRUB drop-in does not switch to gfxterm"; fail=1; }

# A.4.keyring — login-keyring helper + its GUI backend (2026-06-16). Lets
# `ujust margine-keyring blank` set the login keyring password empty so it
# auto-unlocks under fingerprint/autologin (Seahorse provides the dialog;
# there is no headless API).
check_exec "usr/bin/margine-keyring" "A.4.keyring"
check_exec "usr/bin/seahorse" "A.4.keyring"

# A.4.bis — desktop launchers have high-res icons and docs fallback
check_nonempty "usr/share/icons/hicolor/scalable/apps/margine-scheduler.svg" "A.4.bis"
check_nonempty "usr/share/icons/hicolor/scalable/apps/margine-documentation.svg" "A.4.bis"
check_exec "usr/libexec/margine/docs-open" "A.4.bis"
check_exec "usr/bin/margine-docs-open" "A.4.bis"
check_nonempty "usr/share/margine/offline-docs/index.html" "A.4.bis"
check_nonempty "usr/share/margine/offline-docs/docs/index.html" "A.4.bis"
check_nonempty "usr/share/margine/offline-docs/docs/install-status/index.html" "A.4.bis"
docs_count="$(find "$ROOTFS/usr/share/margine/offline-docs" -path '*/index.html' -type f | wc -l)"
if (( docs_count < 14 )); then
  echo "::error::A.4.bis offline docs mirror is incomplete (index.html count=$docs_count)"
  fail=1
fi
if grep -R -n -E '<script|/assets/.*\.(js|css)|href="/docs' "$ROOTFS/usr/share/margine/offline-docs"; then
  echo "::error::A.4.bis offline docs still reference live JS/CSS assets or root-relative docs links"
  fail=1
fi
grep -qxF 'Icon=margine-scheduler' "$ROOTFS/usr/share/applications/margine-scheduler.desktop" || { echo "::error::A.4.bis scheduler launcher does not use margine-scheduler icon"; fail=1; }
grep -qxF 'Exec=margine-docs-open' "$ROOTFS/usr/share/applications/margine-documentation.desktop" || { echo "::error::A.4.bis docs launcher does not use margine-docs-open"; fail=1; }
grep -qxF 'Icon=margine-documentation' "$ROOTFS/usr/share/applications/margine-documentation.desktop" || { echo "::error::A.4.bis docs launcher does not use margine-documentation icon"; fail=1; }

# A.5 — REMOVED (org.gnome.shell.app-grid schema does not exist in
# GNOME 47/48; the keys we tried to set are ignored. Icon-size drift
# between app-grid/folder is a CSS theme issue, not a gschema one).

# A.3.bis — extension settings defaults are shipped through the
# distro dconf database. They intentionally do not live in zz1:
# GNOME Shell extensions may load their local schema source ahead
# of the global one, while dconf defaults apply at the backend path.
DCONF_DIR="$ROOTFS/etc/dconf/db/distro.d"
for keyfile in \
  01-margine-dash-to-dock \
  02-margine-search-light \
  03-margine-o-tiling \
  04-margine-tilingshell \
  05-margine-blur-my-shell \
  06-margine-caffeine \
  07-margine-custom-keybindings; do
  check_file "etc/dconf/db/distro.d/$keyfile" "A.3.bis"
done
if grep -qE '^\[org\.gnome\.shell\.extensions\.' "$ROOTFS/usr/share/glib-2.0/schemas/zz1-margine.gschema.override"; then
  echo "::error::A.3.bis extension defaults are still present in zz1 override"; fail=1
fi
grep -qxF 'system-db:distro' "$ROOTFS/etc/dconf/profile/user" || { echo "::error::A.3.bis /etc/dconf/profile/user lacks system-db:distro"; fail=1; }
grep -qxF '[org/gnome/shell/extensions/dash-to-dock]' "$DCONF_DIR/01-margine-dash-to-dock" || { echo "::error::A.3.bis dash-to-dock dconf section missing"; fail=1; }
grep -qxF '[org/gnome/shell/extensions/search-light]' "$DCONF_DIR/02-margine-search-light" || { echo "::error::A.3.bis search-light dconf section missing"; fail=1; }
grep -qxF '[org/gnome/shell/extensions/o-tiling]' "$DCONF_DIR/03-margine-o-tiling" || { echo "::error::A.3.bis o-tiling dconf section missing"; fail=1; }

# A.3.ter — downstream patches + branding must land on the FINAL
# image (added 2026-06-12 after the search-light mitigation nearly
# shipped unapplied: the build script's soft-fail and a 2-day-old
# staged deployment hid it). These assert OUTCOMES, independent of
# how the build scripts behave.
SL_EXT="$ROOTFS/usr/share/gnome-shell/extensions/search-light@icedman.github.com/extension.js"
grep -q 'margine: unmap before detach' "$SL_EXT" \
  || { echo "::error::A.3.ter search-light unrealize mitigation NOT present in the image"; fail=1; }
grep -q 'margine: defer the toggle out of the' "$SL_EXT" \
  || { echo "::error::A.3.ter search-light press-gesture mitigation NOT present in the image"; fail=1; }
grep -q 'margine: re-entrancy guard' "$SL_EXT" \
  || { echo "::error::A.3.ter search-light hide() re-entrancy guard NOT present in the image"; fail=1; }
grep -q 'margine: defer off input/gesture context' "$SL_EXT" \
  || { echo "::error::A.3.ter search-light input-context deferral (vector #4) NOT present in the image"; fail=1; }
# o-tiling session-only toggle (2026-06-16): the toggle-tiling keybinding must
# NOT persist tile-by-default into the user dconf layer (it would mask the
# distro default permanently). build-margine-extensions.sh points it at the
# no-persist overloads; assert the marker landed on the FINAL image so the core
# tiling toggle can never silently regress to the dconf foot-gun.
OT_EXT="$ROOTFS/usr/share/gnome-shell/extensions/o-tiling@oliwebd.github.com/extension.js"
grep -q 'margine: session-only toggle' "$OT_EXT" \
  || { echo "::error::A.3.ter o-tiling session-only toggle patch NOT present in the image"; fail=1; }
test -s "$ROOTFS/usr/share/icons/hicolor/scalable/apps/margine-logo.svg" \
  || { echo "::error::A.3.ter margine-logo.svg missing from hicolor"; fail=1; }
test -s "$ROOTFS/usr/share/icons/hicolor/scalable/apps/fedora-logo-icon.svg" \
  || { echo "::error::A.3.ter fedora-logo-icon.svg missing (fedora-welcome + gnome-initial-setup hardcode it)"; fail=1; }
test -s "$ROOTFS/usr/share/pixmaps/fedora_logo_med.png" \
  || { echo "::error::A.3.ter About wordmark (fedora_logo_med.png) missing"; fail=1; }
if cmp -s "$ROOTFS/usr/share/pixmaps/fedora_logo_med.png" "$ROOTFS/usr/share/pixmaps/fedora_whitelogo_med.png"; then
  echo "::error::A.3.ter About wordmark dark/light variants are byte-identical (theme differentiation lost)"; fail=1
fi
test -x "$ROOTFS/usr/libexec/margine/staged-update-notify" \
  || { echo "::error::A.3.ter staged-update-notify missing"; fail=1; }

# A.3.quater — legacy icon-name compat shims (2026-06-13). adwaita-icon-
# theme 50 dropped these symbolic names, but the baked o-tiling and
# search-light extensions still reference them and render the broken-image
# placeholder without a shim (build-margine-extensions.sh copies the
# closest Adwaita symbolic under each legacy name). Assert the OUTCOME so
# a vanished source — which the build only warns about — cannot silently
# re-introduce the placeholders.
ICON_ACT="$ROOTFS/usr/share/icons/hicolor/scalable/actions"
for ic in view-quilt-symbolic view-compact-symbolic border-all-symbolic search-symbolic; do
  test -s "$ICON_ACT/${ic}.svg" \
    || { echo "::error::A.3.quater icon shim ${ic}.svg missing/empty — baked extensions will show placeholder icons"; fail=1; }
done

# search-light rounded-corners daniel default: border-radius=7.0
# (the value is an INDEX 0-7 into the extension's px table, not
# pixels — 7 = 32px max rounding; the old 30 was out of range and
# silently ignored. See #94.)
grep -qE "^border-radius=7" "$DCONF_DIR/02-margine-search-light" || { echo "::error::A.3.bis search-light border-radius!=7 — daniel default lost"; fail=1; }
# dash-to-dock background customisation present (cosmetic regression sentinel)
grep -qE "^running-indicator-style='DOTS'" "$DCONF_DIR/01-margine-dash-to-dock" || { echo "::error::A.3.bis dash-to-dock running-indicator-style sentinel missing"; fail=1; }

# A.3.quinquies — keybinding conflict resolution (2026-06-14). o-tiling's
# UPSTREAM keybinding defaults shadow GNOME-native + Margine custom shortcuts.
# The binding state of an INSTALLED system is exactly what these dconf
# defaults set, so a regression here ships broken keybindings to every user:
# Super+Return (terminal), Super+T (whole-session tiling toggle),
# Super+F/Super+S (fullscreen/quick-settings), Super+Alt+arrows (workspace-
# switch/overview-shift), and Super+period (Smile, eaten by IBus emoji).
OT_KB="$DCONF_DIR/03-margine-o-tiling"
grep -qE "^tile-enter=\['<Super><Ctrl>Return'" "$OT_KB" \
  || { echo "::error::A.3.quinquies o-tiling tile-enter not moved off <Super>Return — terminal launcher shadowed"; fail=1; }
grep -qE "^toggle-tiling=\['<Super><Shift>t'\]" "$OT_KB" \
  || { echo "::error::A.3.quinquies o-tiling toggle-tiling still on <Super>t — accidental whole-session tiling toggle"; fail=1; }
grep -qE "^toggle-floating=\['<Super><Shift>f'\]" "$OT_KB" \
  || { echo "::error::A.3.quinquies o-tiling toggle-floating still on <Super>f — shadows wm.toggle-fullscreen"; fail=1; }
grep -qE "^toggle-stacking-global=\['<Super><Shift>s'\]" "$OT_KB" \
  || { echo "::error::A.3.quinquies o-tiling toggle-stacking-global still on <Super>s — shadows shell.toggle-quick-settings"; fail=1; }
grep -qE "^focus-left=\['<Super>h'\]" "$OT_KB" \
  || { echo "::error::A.3.quinquies o-tiling focus-* still carries the <Super><Alt>arrows duplicates that shadow workspace-switch/overview-shift"; fail=1; }
grep -qE '^hotkey=@as \[\]' "$DCONF_DIR/07-margine-custom-keybindings" \
  || { echo "::error::A.3.quinquies IBus emoji hotkey not disabled — <Super>period types emoji input instead of opening Smile"; fail=1; }

if (( fail != 0 )); then
  echo "::error::First-boot asset validation FAILED — blocking rechunk/push/sign."
  exit 1
fi
echo "✓ First-boot asset + keybinding-conflict validation PASSED"
