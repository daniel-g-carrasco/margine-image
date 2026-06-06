#!/usr/bin/env bash
# Margine image build — section: 70-passwd-seed-boot
# Sub-script of the build.sh orchestrator. Decomposed on 2026-06-06
# (audit §8 rec #22 — split build.sh into per-area install scripts).
# See build_files/00-common.sh + build_files/build.sh.
set -euo pipefail
. /ctx/00-common.sh

# 5d. Bug 6 v2 — boot-time seed of /etc/passwd + /etc/group
# ---------------------------------------------------------------------------
# Build-time seed (step 0.bis) IS run, Layer A confirms 65 entries in
# /etc/passwd at the end of buildah. But rechunk subsequently strips
# /etc/passwd / /etc/group from /usr/etc/ when it re-commits the image
# as an ostree-canonical tree (verified 2026-05-31 on a fresh-VM
# rebase: Layer A says 65 entries, deployed image has 1). So Bug 6
# returns post-rebase.
#
# Workaround: ship a systemd oneshot that re-applies the seed at
# every boot, before sysinit. Idempotent (only seeds if /etc/passwd
# is below the entry threshold). Doesn't depend on rechunk preserving
# /etc — it doesn't need to.
log "Installing /usr/libexec/margine-seed-etc-passwd + systemd oneshot"
mkdir -p /usr/libexec
cat > /usr/libexec/margine-seed-etc-passwd <<'SEED'
#!/usr/bin/env python3
"""Boot-time seed of /etc/passwd + /etc/group from /usr/lib factory.
Runs only if /etc/passwd has fewer than 20 entries (the post-rebase
stripped state). Otherwise no-op."""
import os, sys
def load(p):
    try:
        with open(p) as f: return [l.rstrip("\n") for l in f if l.strip()]
    except FileNotFoundError: return []
def by_name(lines): return {l.split(":",1)[0]: l for l in lines}
need_seed = False
for kind in ("passwd","group"):
    cur = load(f"/etc/{kind}")
    if len(cur) < 20:
        need_seed = True
        break
if not need_seed:
    print("/etc/passwd + /etc/group look populated, no seeding needed")
    sys.exit(0)
for kind in ("passwd","group"):
    local = by_name(load(f"/etc/{kind}"))
    factory = by_name(load(f"/usr/lib/{kind}"))
    merged = dict(factory); merged.update(local)
    def k(line):
        try:
            u = int(line.split(":")[2]); return (u >= 1000, u)
        except Exception:
            return (True, 999999)
    tmp = f"/etc/{kind}.new"
    with open(tmp,"w") as f:
        for l in sorted(merged.values(), key=k): f.write(l+"\n")
    os.replace(tmp, f"/etc/{kind}")
    print(f"/etc/{kind}: was {len(local)} → now {len(merged)} (+{len(merged)-len(local)} from factory)")
SEED
chmod 0755 /usr/libexec/margine-seed-etc-passwd

cat > /usr/lib/systemd/system/margine-seed-etc-passwd.service <<'UNIT'
[Unit]
Description=Margine: seed /etc/passwd + /etc/group from /usr/lib if stripped
Documentation=https://github.com/daniel-g-carrasco/margine-fedora-atomic/blob/main/docs/lessons-learned/2026-05-28-initramfs-and-bootc-labels.md
DefaultDependencies=no
# Run only AFTER local-fs-pre.target (so /etc exists as the overlay
# upper layer is mounted) and BEFORE systemd-sysusers / systemd-tmpfiles
# (so they see the seeded users). DO NOT add After=local-fs.target: it
# creates an ordering cycle through systemd-tmpfiles-setup-dev.service,
# which systemd resolves by disabling tmpfiles-setup-dev → /dev/disk
# /by-uuid/* never gets populated → boot times out into emergency mode
# (incident 2026-06-01). /usr is part of the immutable ostree commit
# so it's available from the start; we don't need local-fs.target.
After=local-fs-pre.target
Before=systemd-sysusers.service systemd-tmpfiles-setup.service sysinit.target
ConditionFileNotEmpty=/usr/lib/passwd

[Service]
Type=oneshot
ExecStart=/usr/libexec/margine-seed-etc-passwd
RemainAfterExit=yes
# Self-recovery if a previous boot left /etc files mid-write
ProtectSystem=no

[Install]
WantedBy=sysinit.target
UNIT

mkdir -p /usr/lib/systemd/system/sysinit.target.wants
ln -sf ../margine-seed-etc-passwd.service \
   /usr/lib/systemd/system/sysinit.target.wants/margine-seed-etc-passwd.service
log "Wired margine-seed-etc-passwd.service to sysinit.target"

# ---------------------------------------------------------------------------
# Observability helpers: notify the user when (a) the build pipeline goes
# stale (no new :stable on ghcr for >7 days = something broken upstream),
# and (b) when an actual upgrade has just occurred (so the user knows
# their reboot did something).
#
# Both helpers run as user-systemd (no root needed at runtime). They use
# the freedesktop notification API via notify-send, so they integrate
# with GNOME's normal popup stream.
# ---------------------------------------------------------------------------

log "Installing /usr/libexec/margine-staleness-check (staleness watchdog)"
cat > /usr/libexec/margine-staleness-check <<'PYEOF'
#!/usr/bin/env python3
"""Notify user if ghcr.io/.../margine:stable hasn't been refreshed
in >7 days. Either the build pipeline is broken, or upstream has
genuinely paused — either way the user should know."""
import json
import subprocess
import sys
import time

WARN_AGE_DAYS = 7
CRIT_AGE_DAYS = 14

def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=30)

# Get current booted image reference
r = run(["bootc", "status", "--json"])
if r.returncode != 0:
    sys.exit(0)  # no bootc, no-op
booted = json.loads(r.stdout)["status"]["booted"]
image_ref = booted["image"]["image"]["image"]  # e.g. ghcr.io/daniel-g-carrasco/margine:stable

# Inspect upstream :stable to find its creation timestamp
r = run(["skopeo", "inspect", "--no-tags", f"docker://{image_ref}"])
if r.returncode != 0:
    sys.exit(0)  # network down? skip silently this round
created = json.loads(r.stdout)["Created"]  # ISO 8601

created_ts = time.mktime(time.strptime(created.split(".")[0], "%Y-%m-%dT%H:%M:%S"))
age_days = (time.time() - created_ts) / 86400

if age_days < WARN_AGE_DAYS:
    sys.exit(0)

urgency = "critical" if age_days >= CRIT_AGE_DAYS else "normal"
title = "Margine: upstream stale"
body  = f"Latest :stable is {age_days:.0f} days old. Build pipeline may be broken."
subprocess.run([
    "notify-send", "-u", urgency, "-a", "Margine",
    "-i", "system-software-update", title, body,
])
PYEOF
chmod 0755 /usr/libexec/margine-staleness-check

log "Installing /usr/libexec/margine-upgrade-notify (post-upgrade notification)"
cat > /usr/libexec/margine-upgrade-notify <<'PYEOF'
#!/usr/bin/env python3
"""On first graphical login after a reboot, if the booted deployment's
image digest differs from the one recorded at last run, raise a
notification telling the user *which version they just upgraded to*.
Reassures them that the reboot actually did something."""
import json
import os
import pathlib
import subprocess
import sys

state_dir = pathlib.Path(os.environ["HOME"]) / ".cache" / "margine"
state_dir.mkdir(parents=True, exist_ok=True)
state_file = state_dir / "last-booted-digest"

r = subprocess.run(["bootc", "status", "--json"], capture_output=True, text=True, timeout=15)
if r.returncode != 0:
    sys.exit(0)
booted = json.loads(r.stdout)["status"]["booted"]
digest  = booted["image"].get("imageDigest", "?")
version = booted["image"].get("version", "?")

previous = state_file.read_text().strip() if state_file.exists() else ""

if previous and previous != digest:
    title = "Margine updated"
    body  = f"Now running: {version}\nDigest: {digest[:23]}…"
    subprocess.run([
        "notify-send", "-u", "normal", "-a", "Margine",
        "-i", "system-software-update", title, body,
    ])

state_file.write_text(digest)
PYEOF
chmod 0755 /usr/libexec/margine-upgrade-notify

# User systemd units live in /etc/skel so every NEW user account picks
# them up on first login. Existing accounts get them through the bootstrap
# helper (configure-home-layout, idempotent).
mkdir -p /etc/skel/.config/systemd/user/timers.target.wants \
         /etc/skel/.config/systemd/user/default.target.wants

# Staleness watchdog: timer every 12h after boot.
cat > /etc/skel/.config/systemd/user/margine-staleness.service <<'UNIT'
[Unit]
Description=Margine: check ghcr.io/:stable staleness
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/libexec/margine-staleness-check
UNIT

cat > /etc/skel/.config/systemd/user/margine-staleness.timer <<'UNIT'
[Unit]
Description=Margine: schedule staleness check every 12h

[Timer]
OnBootSec=10min
OnUnitActiveSec=12h
AccuracySec=10min
Persistent=true

[Install]
WantedBy=timers.target
UNIT
ln -sf ../margine-staleness.timer \
   /etc/skel/.config/systemd/user/timers.target.wants/margine-staleness.timer

# Upgrade notify: oneshot, fires on every graphical login.
cat > /etc/skel/.config/systemd/user/margine-upgrade-notify.service <<'UNIT'
[Unit]
Description=Margine: notify if booted deployment changed since last login
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=oneshot
ExecStart=/usr/libexec/margine-upgrade-notify

[Install]
WantedBy=default.target
UNIT
ln -sf ../margine-upgrade-notify.service \
   /etc/skel/.config/systemd/user/default.target.wants/margine-upgrade-notify.service

log "Wired observability user units (staleness 12h + upgrade-notify) into /etc/skel"

log "Installing /etc/xdg/autostart/margine-first-boot.desktop"
mkdir -p /etc/xdg/autostart
cat > /etc/xdg/autostart/margine-first-boot.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Margine first-login user-state bootstrap
Comment=Apply Margine home layout, GNOME extensions, keybindings, defaults
Exec=/usr/bin/bash -c 'mkdir -p "$HOME/.config/margine" && { test -f "$HOME/.config/margine/bootstrapped" || ujust margine-bootstrap unattended > "$HOME/.config/margine/bootstrap.log" 2>&1; }'
NoDisplay=true
OnlyShowIn=GNOME;
X-GNOME-Autostart-enabled=true
EOF
# NOTE: do NOT add X-GNOME-Autostart-Phase=Applications. GNOME 50+
# dropped session-phase management; gnome-session-service warns
# "App ... sets X-GNOME-Autostart-Phase, but gnome-session no longer
# manages session services" and SKIPS the entire entry, so the
# bootstrap never runs at login. The other keys above (Type/Exec/
# OnlyShowIn/Autostart-enabled) are sufficient for standard autostart.
chmod 0644 /etc/xdg/autostart/margine-first-boot.desktop

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
log "Margine build modifications complete."
log "Image is ready: Bluefin DX + CachyOS signed kernel + Margine deltas."
