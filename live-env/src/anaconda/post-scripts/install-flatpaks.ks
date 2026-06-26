# Margine Flatpak BAKE — rsync the pre-baked /var/lib/flatpak from the
# live env into the freshly installed target (Titanoboa / ADR-0008).
#
# The live-env image already has the ~38 fundamentals in /var/lib/flatpak
# (baked by live-env/src/build.sh). ostree+bootc reset /var per deployment
# on install, and Margine does NOT bake Flatpaks into the committed image
# /var, so without this rsync the Flatpaks are lost on first boot.
#
# 2026-06-26 fix (forum 12247 / fresh-install broken-flatpak P0):
#   - TARGET the actually-mounted runtime /var (/mnt/sysimage/var), NOT the
#     per-deployment .0/var checkout. With margine.conf's dedicated /var
#     btrfs subvol the booted system mounts that subvol at /var; the old
#     $DEPLOY_DIR/var (.0/var) was shadowed and the bake was silently lost.
#   - Do NOT strip SELinux labels. The previous `--filter='-x
#     security.selinux'` left the repo mislabeled, and ostree only relabels
#     /var once at deploy-finalize (BEFORE %post), so nothing ever fixed it
#     -> confined flatpak was denied access to /var/lib/flatpak/repo.
#     Plain `-aAXUHKP` (Bluefin/Aurora pattern) + a relabel ks that runs
#     AFTER this one (flatpak-restore-selinux-labels.ks) as belt-and-braces.
#   - LOUD validation: the repo MUST end with refs/remotes/flathub or the
#     bake failed; log a grep-able marker either way.
#
# NOT --erroronfail: every BAKE app is also in
# /usr/share/flatpak/preinstall.d/margine-defaults.preinstall, so a failed
# rsync degrades to a first-boot flatpak-preinstall.service download rather
# than a bricked install.
%post --nochroot --log=/mnt/sysimage/var/log/anaconda-post-flatpak-bake.log
set -uo pipefail

log() { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*"; }

# Target the actually-mounted runtime /var. Anaconda mounts the target's
# /var subvol at /mnt/sysimage/var; fall back to the deployment .0/var only
# if no separate /var was mounted (single-/ layout — still the right var).
if mountpoint -q /mnt/sysimage/var; then
  TARGET="/mnt/sysimage/var/lib"
elif [[ -d /mnt/sysimage/var/lib || -d /mnt/sysimage/var ]]; then
  TARGET="/mnt/sysimage/var/lib"
else
  DEPLOY_DIR="$(ls -d /mnt/sysimage/ostree/deploy/*/deploy/*.0 2>/dev/null | head -1)"
  if [[ -z "$DEPLOY_DIR" ]]; then
    log "ERROR: no /mnt/sysimage/var and no ostree deployment — cannot rsync flatpaks"
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
