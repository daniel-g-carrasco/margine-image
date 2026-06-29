# Margine Flatpak BAKE — rsync the pre-baked /var/lib/flatpak from the
# live env into the freshly installed target (Titanoboa / ADR-0008).
#
# The live-env image already has the ~38 BAKE fundamentals in
# /var/lib/flatpak (baked by live-env/src/build.sh). ostree+bootc reset
# /var per deployment on install, and Margine does NOT bake Flatpaks into
# the committed image /var, so without this rsync the baked apps are lost
# on first boot.
#
# 2026-06-28 fix (forum 12247 / fresh-install broken-flatpak P0, take 2):
#   - TARGET the per-deployment stateroot var checkout ($deployment.0/var),
#     EXACTLY as upstream Bluefin/Aurora do (projectbluefin/iso and
#     get-aurora-dev/iso, configure_iso_anaconda.sh). The previous take
#     (PR #222) baked into the bare /mnt/sysimage/var subvol on the theory
#     that margine.conf's dedicated /var btrfs subvol IS the booted runtime
#     var. That theory was WRONG and was refuted on a fresh VM install: on
#     first deploy ostree seeds the stateroot var from the IMAGE COMMIT's
#     /var, and the booted system runs on THAT stateroot var — not the bare
#     subvol the bake wrote to. Net result: the booted /var/lib/flatpak was
#     empty and every flatpak op failed. Upstream uses the IDENTICAL
#     dedicated-/var partitioning yet bakes into .0/var, so we do the same.
#   - Bluefin pattern: `rsync -aAXUHKP /var/lib/flatpak "$target"` directly
#     (no /var/lib/flatpak_original snapshot — Aurora makes that copy at ISO
#     BUILD time, which would bake the whole flatpak set into the ISO twice;
#     Bluefin skips it and so do we).
#   - Do NOT strip SELinux labels: plain `rsync -aAXUHKP` preserves the
#     live env's correct contexts; flatpak-restore-selinux-labels.ks
#     relabels afterwards as belt-and-braces.
#   - LOUD validation: the repo MUST end with refs/remotes/flathub or the
#     bake failed; log a grep-able marker either way.
#
# NOT --erroronfail: every BAKE app is also in
# /usr/share/flatpak/preinstall.d/margine-defaults.preinstall, so a failed
# rsync degrades to a first-boot flatpak-preinstall.service download rather
# than a bricked install. NOTE: the heavy creative apps (GIMP, Inkscape,
# darktable, OBS) and Reaper are DEFER-only — they ALWAYS install via
# flatpak-preinstall.service at first boot, never via this bake. Reaper in
# particular cannot be baked: its apply_extra downloads the proprietary
# binary, which fails in the build container. So flatpak-preinstall.service
# stays ENABLED by design (unlike upstream, which bakes everything and
# disables it).
%post --nochroot --log=/mnt/sysimage/var/log/anaconda-post-flatpak-bake.log
set -uo pipefail

log() { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*"; }

# Upstream-parity target: the per-deployment stateroot var checkout, which
# is what the booted system actually reads as /var. Resolve the deployed
# commit the same way Bluefin/Aurora do; fall back to globbing the .0 dir.
deployment="$(ostree rev-parse --repo=/mnt/sysimage/ostree/repo ostree/0/1/0 2>/dev/null || true)"
if [[ -n "$deployment" ]]; then
  TARGET="/mnt/sysimage/ostree/deploy/default/deploy/${deployment}.0/var/lib"
else
  DEPLOY_DIR="$(ls -d /mnt/sysimage/ostree/deploy/*/deploy/*.0 2>/dev/null | head -1)"
  if [[ -z "$DEPLOY_DIR" ]]; then
    log "MARGINE-BAKE-FAIL: no ostree deployment under /mnt/sysimage — cannot rsync flatpaks"
    exit 0
  fi
  TARGET="$DEPLOY_DIR/var/lib"
fi
log "Target var/lib = $TARGET"
mkdir -p "$TARGET"

if [[ -d /var/lib/flatpak ]]; then
  installed="$(find /var/lib/flatpak/app -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)"
  log "Source /var/lib/flatpak has $installed installed apps (pre-baked in live env)"
  log "rsync /var/lib/flatpak -> $TARGET/"
  rsync -aAXUHKP /var/lib/flatpak "$TARGET/"
  sync
  if [[ -d "$TARGET/flatpak/repo/refs/remotes/flathub" ]]; then
    log "MARGINE-BAKE-OK: $TARGET/flatpak/repo/refs/remotes/flathub present ($installed apps)"
  else
    log "MARGINE-BAKE-FAIL: $TARGET/flatpak/repo/refs/remotes/flathub MISSING after rsync"
  fi
else
  log "MARGINE-BAKE-FAIL: /var/lib/flatpak does not exist in the live env (nothing baked?)"
fi
%end
