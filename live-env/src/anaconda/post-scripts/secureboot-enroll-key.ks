# Margine Secure Boot MOK import — staged before the first installed boot
# (Titanoboa / ADR-0008, ported VERBATIM from disk_config/iso-gnome.toml:80-137,
# which is the PR #88 fix). ADR §4 invariant: MOK enrollment must keep
# working and the mok-enroll.service first-boot fallback in margine:stable
# stays unchanged.
#
# mokutil writes a pending MOK request into EFI variables. Running it here
# (Anaconda %post --nochroot) means shim sees the request on the first
# post-install reboot and opens MokManager before the installed system
# reaches systemd — matching Bluefin/Bazzite's secureboot-enroll-key.ks.
#
# Do NOT create /var/.mok-enrolled here. If the user misses MokManager,
# mok-enroll.service re-stages the request on the next boot. mokutil
# --timeout -1 disables shim's 10 s auto-continue so the prompt waits.
%post --nochroot --log=/mnt/sysimage/var/log/anaconda-post-mok-enroll.log
set -uo pipefail

log() { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*"; }

log "Attempting pre-first-reboot Margine MOK enrollment request"

if [[ ! -d /sys/firmware/efi ]]; then
  log "EFI mode not detected — skipping MOK import"
  exit 0
fi

if ! command -v mokutil >/dev/null 2>&1; then
  log "mokutil unavailable in installer environment — first-boot service remains fallback"
  exit 0
fi

MOK_CERT=""
for candidate in \
  /mnt/sysimage/usr/share/cert/MOK.der \
  /mnt/sysimage/ostree/deploy/default/deploy/*.0/usr/share/cert/MOK.der
do
  if [[ -f "$candidate" ]]; then
    MOK_CERT="$candidate"
    break
  fi
done

if [[ -z "$MOK_CERT" ]]; then
  log "Margine MOK certificate not found in target deployment — first-boot service remains fallback"
  exit 0
fi

log "Using MOK certificate: $MOK_CERT"

if mokutil --test-key "$MOK_CERT" >/dev/null 2>&1; then
  log "Margine MOK is already enrolled — nothing to import"
  exit 0
fi

log "Setting MokManager timeout to direct entry"
mokutil --timeout -1 || log "WARN: failed to set MokTimeout; continuing"

log "Importing Margine MOK request"
if printf '%s\n%s\n' 'margine-os' 'margine-os' | mokutil --import "$MOK_CERT"; then
  log "MOK import request submitted — shim should launch MokManager on the next boot"
else
  log "WARN: mokutil import failed — first-boot mok-enroll.service remains fallback"
fi
%end
