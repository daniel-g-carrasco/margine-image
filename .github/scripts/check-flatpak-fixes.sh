#!/usr/bin/env bash
# Regression guard for the 2026-06 fresh-install Flatpak-bake fixes
# (forum 12247) and the phantom-UART console fix. These are subtle,
# install-time-only behaviours that no boot-test exercises, so a static
# assertion is the cheap insurance that a future edit can't silently undo
# them. Run in CI (lint). Exit 1 on any regression.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 2

KS=live-env/src/anaconda/post-scripts/install-flatpaks.ks
IDEF=live-env/src/anaconda/interactive-defaults.ks
ISO=live-env/src/iso.yaml
fail=0
ok()   { printf '  OK   %s\n' "$1"; }
bad()  { printf '::error::%s\n' "$1"; fail=1; }

echo "== Flatpak-bake fix invariants =="

# 1) The SELinux label-strip filter must NOT come back.
if grep -q -- "--filter=.-x security.selinux" "$KS"; then
  bad "install-flatpaks.ks re-introduced the SELinux label-strip filter (breaks the repo on first boot)"
else ok "no SELinux label-strip filter in install-flatpaks.ks"; fi

# 2) The bake must target the real mounted runtime /var, not only .0/var.
if grep -q 'mnt/sysimage/var' "$KS"; then
  ok "install-flatpaks.ks targets the mounted runtime /var"
else
  bad "install-flatpaks.ks no longer targets /mnt/sysimage/var (bake would land in the shadowed .0/var)"
fi

# 3) The two upstream-parity post-scripts must exist AND be %included
#    (disable-fedora-flatpak BEFORE the bake, relabel AFTER).
for f in disable-fedora-flatpak.ks flatpak-restore-selinux-labels.ks; do
  [ -f "live-env/src/anaconda/post-scripts/$f" ] \
    && ok "post-script present: $f" || bad "missing post-script: $f"
  grep -q "$f" "$IDEF" \
    && ok "%include present: $f" || bad "$f not %included in interactive-defaults.ks"
done
# order: disable-fedora before install-flatpaks; relabel after.
awk '/disable-fedora-flatpak.ks/{d=NR} /install-flatpaks.ks/{i=NR} /flatpak-restore-selinux-labels.ks/{r=NR}
     END{exit !(d && i && r && d<i && i<r)}' "$IDEF" \
  && ok "post-script %include order is disable -> bake -> relabel" \
  || bad "interactive-defaults.ks %include order wrong (need disable-fedora < install-flatpaks < restore-labels)"

# 4) The preinstall self-heal drop-in must exist with the lockout removed.
DROPIN=build_files/system_files/usr/lib/systemd/system/flatpak-preinstall.service.d/10-margine.conf
if grep -q 'StartLimitIntervalSec=0' "$DROPIN" 2>/dev/null; then
  ok "flatpak-preinstall self-heal drop-in present (no 3-strike lockout)"
else bad "flatpak-preinstall.service.d/10-margine.conf missing or lacks StartLimitIntervalSec=0"; fi

echo "== Phantom-UART console fix invariants =="
# 5) The shipped default ISO entries must NOT bake console=ttyS0.
if grep -nE '^\s+linux:.*console=ttyS0' "$ISO" >/dev/null; then
  bad "iso.yaml default entries re-baked console=ttyS0 (stalls phantom-UART mini-PCs)"
else ok "no console=ttyS0 baked in the shipped iso.yaml linux entries"; fi

echo
[ "$fail" -eq 0 ] && echo "All Flatpak/console fix invariants hold." || echo "REGRESSION(S) DETECTED."
exit "$fail"
