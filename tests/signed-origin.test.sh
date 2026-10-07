#!/usr/bin/env bash
# Tests for /usr/libexec/margine/signed-origin against a fake rpm-ostree.
# What it must do: move ONLY a Margine install on an unverified transport to
# ostree-image-signed:, keep the tag, and change nothing when the rebase
# (which verifies the signature first) fails.
set -euo pipefail
HELPER="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/build_files/system_files/usr/libexec/margine/signed-origin"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fails=0
mkdir -p "$T/bin"
# shellcheck disable=SC2016
cat > "$T/bin/rpm-ostree" <<'STUB'
#!/bin/sh
case "$1" in
  status) printf '{"deployments":[{"container-image-reference":"%s"}]}\n' "$FAKE_REF" ;;
  rebase) echo "rebase $2" >> "$FAKE_LOG"; [ -z "${FAKE_FAIL:-}" ] ;;
esac
STUB
printf '#!/bin/sh\nexit 0\n' > "$T/bin/logger"; chmod +x "$T/bin/"*
printf '{"default":[{"type":"reject"}],"transports":{"docker":{"ghcr.io/daniel-g-carrasco/margine":[{"type":"sigstoreSigned","keyPath":"/usr/lib/pki/containers/margine.pub","signedIdentity":{"type":"matchRepository"}}]}}}\n' > "$T/policy.json"
printf '{"default":[{"type":"insecureAcceptAnything"}],"transports":{"docker":{}}}\n' > "$T/policy-none.json"

run_case() {  # name ref expected-rebase-target(or -) expected-rc [policy] [fail]
  local name="$1" ref="$2" want="$3" want_rc="$4" pol="${5:-$T/policy.json}" ff="${6:-}" rc=0
  : > "$T/log"
  env -i PATH="$T/bin:/usr/bin:/bin" FAKE_REF="$ref" FAKE_LOG="$T/log" FAKE_FAIL="$ff" MARGINE_POLICY="$pol" \
    bash "$HELPER" > "$T/out" 2>&1 || rc=$?
  local got; got="$(sed -n 's/^rebase //p' "$T/log")"; [ -n "$got" ] || got="-"
  if [ "$got" = "$want" ] && [ "$rc" = "$want_rc" ]; then echo "ok   $name"
  else echo "FAIL $name: rebase=$got (want $want) rc=$rc (want $want_rc)"; sed 's/^/     /' "$T/out"; fails=$((fails+1)); fi
}
R=ghcr.io/daniel-g-carrasco/margine
run_case "ISO install (unverified-registry, :stable) -> signed"   "ostree-unverified-registry:$R:stable"       "ostree-image-signed:docker://$R:stable" 0
run_case "unverified-image form, :lts tag kept"                   "ostree-unverified-image:docker://$R:lts"    "ostree-image-signed:docker://$R:lts"    0
run_case "already signed: nothing"                                "ostree-image-signed:docker://$R:stable"     -  0
run_case "rebased to another image: nothing"                      "ostree-unverified-registry:ghcr.io/ublue-os/bluefin-dx:stable" - 0
run_case "no Margine scope in the policy: nothing"                "ostree-unverified-registry:$R:stable"       -  0 "$T/policy-none.json"
run_case "rebase fails (bad signature/network): reported, rc 1"   "ostree-unverified-registry:$R:stable"       "ostree-image-signed:docker://$R:stable" 1 "$T/policy.json" yes
run_case "no image reference (not a container deployment)"        ""                                           -  0
D=sha256:$(printf '%064d' 0)
run_case "pinned to a digest (smoke-boot VM): nothing"             "ostree-unverified-registry:$R@$D"           -  0
run_case "tag plus digest: nothing, never a digest as a tag"       "ostree-unverified-registry:$R:stable@$D"    -  0
if (( fails )); then echo "$fails signed-origin case(s) failed"; exit 1; fi
echo "all signed-origin cases passed"
