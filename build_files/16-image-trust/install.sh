#!/usr/bin/env bash
# Margine image build: make devices verify Margine's own signature on
# every update (2026-10-06).
#
# CI signs every image with cosign (secrets/cosign.pub), but until now no
# installed system checked it: /etc/containers/policy.json had no scope for
# ghcr.io/daniel-g-carrasco/margine, so pulls fell through to the docker
# catch-all `insecureAcceptAnything`. A system on the "signed" transport
# (ostree-image-signed:) therefore verified nothing, and ISO installs sat on
# ostree-unverified-registry: anyway.
#
# This adds the missing scope next to Bluefin's ublue-os one. It does not
# replace the file: policy.json has no drop-in directory, and replacing it
# would freeze every other scope the base ships.
#
# Prerequisites shipped from system_files:
#   /usr/lib/pki/containers/margine.pub              copy of secrets/cosign.pub
#   /etc/containers/registries.d/margine.yaml        use-sigstore-attachments
# The key only verifies the CLASSIC cosign signature (sha256-<digest>.sig);
# build.yml writes one since #448 and smoke-boot refuses images without it.
set -euo pipefail
. /ctx/00-common.sh

POLICY=/etc/containers/policy.json
KEY=/usr/lib/pki/containers/margine.pub
SCOPE=ghcr.io/daniel-g-carrasco/margine

[[ -s "$KEY" ]] || { err "missing $KEY (system_files)"; exit 1; }
[[ -s "$POLICY" ]] || { err "missing $POLICY in the base image"; exit 1; }

python3 - "$POLICY" "$SCOPE" "$KEY" <<'PY'
import json, sys
path, scope, key = sys.argv[1:4]
policy = json.load(open(path))
docker = policy.setdefault("transports", {}).setdefault("docker", {})
docker[scope] = [{
    "type": "sigstoreSigned",
    "keyPath": key,
    "signedIdentity": {"type": "matchRepository"},
}]
with open(path, "w") as f:
    json.dump(policy, f, indent=2)
    f.write("\n")
PY

python3 -c "import json; p=json.load(open('$POLICY')); r=p['transports']['docker']['$SCOPE'][0]; assert r['type']=='sigstoreSigned' and r['keyPath']=='$KEY'" \
  || { err "policy scope for $SCOPE did not stick"; exit 1; }
log "image trust: $SCOPE must be signed by $KEY"
