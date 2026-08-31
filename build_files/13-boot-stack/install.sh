#!/usr/bin/env bash
# Keep the boot stack (ostree, bootc) at Fedora's current stable updates.
#
# WHY THIS EXISTS (2026-09-01)
#
# The base image can lag Fedora updates by days or weeks, and for most
# packages that is fine. ostree and bootc are the exception: they are
# the code that INSTALLS this very image. The chunkah-chunked candidate
# (candidate.20260831) could not be installed by bootc-image-builder or
# by any bootc install: the image carried ostree 2026.2, whose
# min-free-space accounting counts duplicate content objects as real
# writes. bootc >= 1.16.3 relabels every layer at import (bootc#2088),
# which produces exactly such duplicate writes, so the phantom counter
# filled disks of 33, 50 and 70 GiB while the real usage was a fraction
# of that ("min-free-space-percent '3%' would be exceeded", smoke-boot
# runs 33417319484, 33439763191, 33441541156). ostree 2026.3
# (ostreedev/ostree#3614/#3615, F44 stable 2026-08-17) fixes the
# accounting; ostree 2026.4 also caps the reserve at min(3%, 1GB)
# (#3640). Updating bootc alongside keeps the pair coherent.
#
# On a base that already ships current ostree/bootc this is a no-op.
set -euo pipefail
. /ctx/00-common.sh
log() { printf '[boot-stack] %s\n' "$*"; }
err() { printf '[boot-stack] ERROR: %s\n' "$*" >&2; }

log "updating ostree + bootc to current Fedora stable"
dnf -y update ostree bootc
log "now: $(rpm -q ostree bootc | tr '\n' ' ')"
