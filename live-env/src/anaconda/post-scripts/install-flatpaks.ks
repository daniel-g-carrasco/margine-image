# Margine Flatpak BAKE — rsync the pre-baked /var/lib/flatpak from the
# live env into the freshly installed target (Titanoboa / ADR-0008).
#
# Ported from disk_config/iso-gnome.toml (BIB %post flatpak bake). The
# live-env image already has the ~38 fundamentals in /var/lib/flatpak
# (baked by live-env/src/build.sh). ostree+bootc reset /var per
# deployment on install, so without this rsync the Flatpaks are lost on
# first boot.
#
# rsync flags: ADR-0008 §4 invariant uses Bluefin's verified-in-production
# `--filter='-x security.selinux'` — it preserves POSIX xattrs/ACLs but
# strips SELinux labels, which ostree's finalize relabels correctly on the
# target. Without this, baked Flatpaks can fail to launch with AVC denials.
#
# NOT --erroronfail: every BAKE app is also in
# /usr/share/flatpak/preinstall.d/margine-defaults.preinstall, so a failed
# rsync degrades to a first-boot flatpak-preinstall.service download rather
# than a bricked install. (bootc switch + partitioning carry --erroronfail;
# the Flatpak bake is quality-of-life.)
%post --nochroot --log=/mnt/sysimage/var/log/anaconda-post-flatpak-bake.log
set -uo pipefail

log() { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*"; }

log "Locate target ostree deployment under /mnt/sysimage"
DEPLOY_DIR="$(ls -d /mnt/sysimage/ostree/deploy/default/deploy/*.0 2>/dev/null | head -1)"
if [[ -z "$DEPLOY_DIR" ]]; then
  log "ERROR: no ostree deployment found under /mnt/sysimage — cannot rsync flatpaks"
  ls -la /mnt/sysimage/ostree/deploy/ 2>&1 || true
  exit 0
fi
log "Target deploy dir = $DEPLOY_DIR"

mkdir -p "$DEPLOY_DIR/var/lib"
if [[ -d /var/lib/flatpak ]]; then
  installed="$(find /var/lib/flatpak/app -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)"
  log "Source /var/lib/flatpak has $installed installed apps (pre-baked in live env)"
  log "rsync /var/lib/flatpak -> $DEPLOY_DIR/var/lib/"
  rsync -aAXUHKP --filter='-x security.selinux' /var/lib/flatpak "$DEPLOY_DIR/var/lib/"
  sync
  log "rsync complete — target /var/lib/flatpak populated"
else
  log "WARN: /var/lib/flatpak does not exist in the live env (nothing baked?)"
fi
%end
