#!/usr/bin/env bash
# Margine status.json producer.
#
# Emits the schemaVersion-2 document that drives the website's /status flow
# page (Fedora Atomic → Bluefin DX → Margine). Run by status-json.yml after
# every build / smoke-promotion / ISO, and on a daily schedule so upstream
# Bluefin drift is reflected even when Margine itself didn't change.
#
# What's STATIC (lineage story — names, per-layer deltas, prose, links, the
# two verify commands) lives in the python block below; it changes only when
# the story changes. Everything else is resolved live:
#   - bluefin / margine version + date + digest  ← skopeo inspect :stable
#   - baseDigestMatchesBluefin                    ← margine base-digest label
#                                                   vs current bluefin digest
#   - margine kernel                              ← preserved from the last
#                                                   published status.json
#                                                   (no clean pre-build label;
#                                                   uname -r is only knowable
#                                                   on a booted host, which
#                                                   `ujust margine-status` uses)
#   - build / smoke / iso health                  ← gh api workflow runs
#
# Usage: build-status-json.sh > status.json
# Env:   GH_TOKEN (required, for gh api)
#        BLUEFIN_IMAGE / MARGINE_IMAGE / MARGINE_REPO (optional overrides)
set -euo pipefail

BLUEFIN_IMAGE="${BLUEFIN_IMAGE:-ghcr.io/ublue-os/bluefin-dx:stable}"
MARGINE_IMAGE="${MARGINE_IMAGE:-ghcr.io/daniel-g-carrasco/margine:stable}"
REPO="${MARGINE_REPO:-daniel-g-carrasco/margine-image}"

BLU_F="$(mktemp)"; MAR_F="$(mktemp)"
trap 'rm -f "$BLU_F" "$MAR_F"' EXIT

# Large skopeo JSON goes through temp files, never env vars — the Labels map
# overflows the "Argument list too long" limit when exported.
skopeo inspect --no-tags "docker://$BLUEFIN_IMAGE" > "$BLU_F" 2>/dev/null || echo '{}' > "$BLU_F"
skopeo inspect --no-tags "docker://$MARGINE_IMAGE" > "$MAR_F" 2>/dev/null || echo '{}' > "$MAR_F"

# Latest *completed* run conclusion + date for a workflow file.
gh_field() {
  gh api "repos/$REPO/actions/workflows/$1/runs?per_page=1&status=completed" \
    --jq ".workflow_runs[0].$2 // \"\"" 2>/dev/null || echo ""
}
BUILD_C="$(gh_field build.yml conclusion)";      BUILD_C="${BUILD_C:-unknown}"
BUILD_D="$(gh_field build.yml updated_at)";       BUILD_D="${BUILD_D:0:10}"
SMOKE_C="$(gh_field smoke-boot.yml conclusion)";  SMOKE_C="${SMOKE_C:-unknown}"
SMOKE_D="$(gh_field smoke-boot.yml updated_at)";   SMOKE_D="${SMOKE_D:0:10}"
ISO_C="$(gh_field build-disk.yml conclusion)";    ISO_C="${ISO_C:-unknown}"
ISO_D="$(gh_field build-disk.yml updated_at)";      ISO_D="${ISO_D:0:10}"

export BLU_F MAR_F BUILD_C BUILD_D SMOKE_C SMOKE_D ISO_C ISO_D

python3 <<'PY'
import json, os, datetime

def load(p):
    try:
        with open(p) as f:
            return json.load(f)
    except Exception:
        return {}

blu = load(os.environ["BLU_F"]); mar = load(os.environ["MAR_F"])
blu_l = blu.get("Labels") or {}; mar_l = mar.get("Labels") or {}

def ver(lbl):
    return lbl.get("org.opencontainers.image.version", "")

def created(d):
    c = d.get("Created", "")
    return c[:10] if c else ""

blu_ver = ver(blu_l); blu_date = created(blu)
mar_ver = ver(mar_l); mar_date = created(mar)
fedora_ver = blu_ver.split(".")[0] if "." in blu_ver else "44"

# Kernel: no clean build-time source (the real running kernel is only
# knowable on a booted host — `ujust margine-status` uses `uname -r`). The
# engine emits whatever a build labelled, else leaves it empty; the publish
# step (publish-status-json.sh) preserves the curated value already on the
# site so the field never blanks out.
mar_kernel = mar_l.get("place.the-empty.margine.kernel", "")

blu_digest = blu.get("Digest", "")
mar_digest = mar.get("Digest", "")
mar_base = mar_l.get("org.opencontainers.image.base.digest", "")
base_match = (mar_base == blu_digest) if (mar_base and blu_digest) else None

def health(c):
    return {"success": "current", "failure": "failed", "cancelled": "failed"}.get(c, "unknown")

# A layer is "current" when its build is healthy; margine drops to "behind"
# when it was built from an older Bluefin than what's published now.
mar_status = "current"
if base_match is False:
    mar_status = "behind"
if os.environ["SMOKE_C"] == "failure":
    mar_status = "failed"

doc = {
    "schemaVersion": 2,
    "generatedAt": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "chain": [
        {
            "key": "fedora", "name": "Fedora Atomic", "version": fedora_ver or "44",
            "date": "", "status": "current", "delta": [],
            "detail": "The atomic / ostree foundation — immutable /usr, transactional updates.",
            "link": "https://fedoraproject.org/atomic-desktops/silverblue/",
        },
        {
            "key": "bluefin", "name": "Bluefin DX", "version": blu_ver or "—",
            "date": blu_date, "status": "current",
            "delta": [
                "Developer / container / virt toolbox (DX)",
                "Universal Blue automation — uupd auto-updates, ujust recipes",
                "Codecs, hardware enablement, Flathub",
            ],
            "detail": "Universal Blue's developer image — what Margine builds FROM.",
            "link": "https://github.com/ublue-os/bluefin/pkgs/container/bluefin-dx",
        },
        {
            "key": "margine", "name": "Margine OS", "version": mar_ver or "—",
            "date": mar_date, "kernel": mar_kernel, "status": mar_status,
            "delta": [
                "Signed CachyOS / BORE kernel + scx scheduler picker",
                "o-tiling tiling + Hyprland-style keybindings",
                "Opt-in gaming layer (Steam/Proton, gamescope, MangoHud)",
                "Curated GNOME, Smile emoji picker, Margine branding",
            ],
            "detail": "The Margine deltas — what makes it Margine. Built, boot-tested, promoted to :stable.",
            "link": "https://github.com/daniel-g-carrasco/margine-image/pkgs/container/margine",
        },
    ],
    "margine": {
        "stableDigest": mar_digest or "—",
        "stableCreated": mar_date,
        "baseDigestMatchesBluefin": base_match,
        "build": {"conclusion": os.environ["BUILD_C"], "date": os.environ["BUILD_D"]},
        "smoke": {"conclusion": os.environ["SMOKE_C"], "date": os.environ["SMOKE_D"]},
        "iso": {"status": health(os.environ["ISO_C"]), "date": os.environ["ISO_D"]},
    },
    "verify": {
        "status": {
            "cmd": "ujust margine-status",
            "note": "show your deployment vs the latest :stable, plus the chain above",
        },
        "update": {
            "cmd": "ujust margine-update",
            "note": "pull the latest and stage it for the next reboot",
        },
    },
}
print(json.dumps(doc, indent=2, ensure_ascii=False))
PY
