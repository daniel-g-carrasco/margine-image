#!/usr/bin/env bash
# Margine image build, section 11-fedora-release-gate:
# Refuse to build on a Fedora release nobody has reviewed yet.
#
# The base image tag floats (bluefin-dx:stable), so the day Universal Blue
# rebases it to the next Fedora, every Margine build silently moves with it.
# Several things in this tree are tied to the release: packages pinned by
# their fc44 name, the Fedora 45 switch of the Secret Service from
# gnome-keyring to oo7 (which changes how margine-keyring and the TPM
# keyring unlock work), third-party repos, the Flatpak GL runtime.
# checklist.md next to this script lists them. This step compares the
# base's VERSION_ID with expected-release and fails the build, printing the
# checklist, until someone walks through it and bumps the number. The build
# failure reaches ntfy like any other, so it cannot go unnoticed.
set -euo pipefail
. /ctx/00-common.sh

expected="$(tr -d '[:space:]' < /ctx/11-fedora-release-gate/expected-release)"
actual="$(. /usr/lib/os-release && echo "${VERSION_ID:-}")"
if [[ "$actual" == "$expected" ]]; then
  log "11-fedora-release-gate: base is Fedora $actual, as expected"
  exit 0
fi
err "11-fedora-release-gate: the base image is Fedora ${actual:-unknown}, this tree was reviewed for Fedora $expected"
echo "::error title=Fedora release changed::The base moved to Fedora ${actual:-unknown}. Walk through build_files/11-fedora-release-gate/checklist.md, then set build_files/11-fedora-release-gate/expected-release to ${actual:-the new release}."
echo "----- build_files/11-fedora-release-gate/checklist.md -----"
cat /ctx/11-fedora-release-gate/checklist.md
exit 1
