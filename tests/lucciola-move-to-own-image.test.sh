#!/usr/bin/env bash
# Tests for Lucciola's move to its own image, against fake rpm-ostree,
# skopeo, loginctl and runuser:
#   /usr/libexec/lucciola/move-to-own-image (system, stages the move)
#   /usr/libexec/lucciola/move-notify       (user session, the notice)
# What the mover must do: rebase ONLY an install that follows exactly
# margine:lucciola, to ostree-image-signed:docker://ghcr.io/daniel-g-carrasco/
# lucciola:stable, once that image is published; leave every other install,
# pending switch and opt-out alone; change nothing when the rebase (which
# verifies the signature first) fails.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lucciola/system_files/usr/libexec/lucciola"
MOVER="$ROOT/move-to-own-image"
NOTIFIER="$ROOT/move-notify"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fails=0
mkdir -p "$T/bin" "$T/home"
# shellcheck disable=SC2016
cat > "$T/bin/rpm-ostree" <<'STUB'
#!/bin/sh
case "$1" in
  status) cat "$FAKE_STATUS" ;;
  rebase) echo "rebase $2" >> "$FAKE_LOG"; [ -z "${FAKE_REBASE_FAIL:-}" ] ;;
esac
STUB
# shellcheck disable=SC2016
cat > "$T/bin/skopeo" <<'STUB'
#!/bin/sh
echo "skopeo $*" >> "$FAKE_LOG"
[ -z "${FAKE_UNPUBLISHED:-}" ]
STUB
# uid 42 is gdm's greeter, 0 root: never asked to show the notice.
printf '#!/bin/sh\nprintf "0 root no active\\n42 gdm no active\\n1000 alice no active\\n1001 bob yes lingering\\n"\n' > "$T/bin/loginctl"
# shellcheck disable=SC2016
printf '#!/bin/sh\necho "runuser $*" >> "$FAKE_LOG"\n' > "$T/bin/runuser"
# shellcheck disable=SC2016
printf '#!/bin/sh\necho "notify $*" >> "$FAKE_LOG"\n[ -z "${FAKE_NOTIFY_FAIL:-}" ]\n' > "$T/bin/margine-notify"
printf '#!/bin/sh\nexit 0\n' > "$T/bin/logger"
printf '#!/bin/sh\nexit 0\n' > "$T/bin/sleep"
chmod +x "$T/bin/"*
SCOPE='[{"type":"sigstoreSigned","keyPath":"/usr/lib/pki/containers/margine.pub","signedIdentity":{"type":"matchRepository"}}]'
printf '{"default":[{"type":"reject"}],"transports":{"docker":{"ghcr.io/daniel-g-carrasco/margine":%s,"ghcr.io/daniel-g-carrasco/lucciola":%s}}}\n' "$SCOPE" "$SCOPE" > "$T/policy.json"
printf '{"default":[{"type":"reject"}],"transports":{"docker":{"ghcr.io/daniel-g-carrasco/margine":%s,"":[{"type":"insecureAcceptAnything"}]}}}\n' "$SCOPE" > "$T/policy-margine-only.json"

M=ghcr.io/daniel-g-carrasco/margine
L=ghcr.io/daniel-g-carrasco/lucciola
D=sha256:$(printf '%064d' 0)

# status BOOTED [PENDING] [ROLLBACK]: rpm-ostree status --json with the
# pending deployment first and the rollback last, as rpm-ostree lists them.
# "none" leaves a slot out; "-" is a deployment without an image reference.
status() {
  local b="$1" p="${2:-none}" r="${3:-none}" out='{"deployments":['
  dep() { if [ "$1" = - ]; then printf '{"checksum":"%s","booted":%s}' "$2" "$3"
          else printf '{"container-image-reference":"%s","checksum":"%s","booted":%s}' "$1" "$2" "$3"; fi; }
  [ "$p" = none ] || out+="$(dep "$p" pending-sum false),"
  out+="$(dep "$b" booted-sum true)"
  [ "$r" = none ] || out+=",$(dep "$r" rollback-sum false)"
  printf '%s]}\n' "$out" > "$T/status.json"
}

# mover NAME WANT-REBASE(or -) WANT-RC [VAR=VALUE...]: runs the mover on the
# current status.json; extra VAR=VALUE pairs go to its environment.
mover() {
  local name="$1" want="$2" want_rc="$3" rc=0; shift 3
  : > "$T/log"
  env -i PATH="$T/bin:/usr/bin:/bin" FAKE_STATUS="$T/status.json" FAKE_LOG="$T/log" \
    MARGINE_POLICY="$T/policy.json" LUCCIOLA_MOVE_OPTOUT="$T/stay-on-margine" "$@" \
    bash "$MOVER" > "$T/out" 2>&1 || rc=$?
  local got; got="$(sed -n 's/^rebase //p' "$T/log")"; [ -n "$got" ] || got="-"
  if [ "$got" = "$want" ] && [ "$rc" = "$want_rc" ]; then echo "ok   $name"
  else echo "FAIL $name: rebase=$got (want $want) rc=$rc (want $want_rc)"; sed 's/^/     /' "$T/out"; fails=$((fails+1)); fi
}
check() {  # NAME CONDITION...: an extra assertion on the last run
  local name="$1"; shift
  if "$@"; then echo "ok   $name"; else echo "FAIL $name"; sed 's/^/     /' "$T/log" "$T/out"; fails=$((fails+1)); fi
}
logged() { grep -q -- "$1" "$T/log"; }
said() { grep -q -- "$1" "$T/out"; }
count() { [ "$(grep -c -- "$1" "$T/log" || true)" = "$2" ]; }

S="ostree-image-signed:docker://$L:stable"
echo "== move-to-own-image"
status "ostree-unverified-registry:$M:lucciola"
mover "ISO/rebase install (unverified-registry, :lucciola) -> signed :stable" "$S" 0
check "  target checked on the registry first" logged "skopeo inspect --no-tags docker://$L:stable"
check "  notice sent to uid 1000 and 1001 only" count "systemctl --user start --no-block lucciola-move-notify.service" 2
check "  never to root or gdm" sh -c "! grep -qE 'runuser -u (root|gdm) ' '$T/log'"
check "  in the user's own manager" logged "runuser -u alice -- env XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus systemctl --user"
status "ostree-image-signed:docker://$M:lucciola"
mover "signed transport, :lucciola -> signed :stable" "$S" 0
status "ostree-unverified-image:docker://$M:lucciola"
mover "unverified-image docker:// form" "$S" 0
status "ostree-image-signed:registry:$M:lucciola"
mover "registry: form" "$S" 0

status "ostree-image-signed:docker://$M:lucciola-test"
mover "lucciola-test: nothing" - 0
check "  no registry check either" sh -c "! grep -q skopeo '$T/log'"
status "ostree-image-signed:docker://$M:lucciola.20261017"
mover "dated lucciola tag: nothing" - 0
status "ostree-unverified-registry:$M@$D"
mover "pinned to a digest (smoke-boot VM): nothing" - 0
status "ostree-unverified-registry:$M:lucciola@$D"
mover "tag plus digest: nothing" - 0
status "ostree-image-signed:docker://$M:stable"
mover "plain Margine :stable: nothing" - 0
status "ostree-unverified-registry:ghcr.io/ublue-os/bluefin-dx:stable"
mover "another image: nothing" - 0
status "ostree-image-signed:docker://$L:stable"
mover "already on Lucciola's own image: nothing" - 0
status "-"
mover "no container image reference: nothing" - 0
status "ostree-remote-image:fedora:docker://$M:lucciola"
mover "ostree remote transport: nothing" - 0

status "ostree-unverified-registry:$M:lucciola" "$S"
mover "move already staged: nothing" - 0
check "  no registry check" sh -c "! grep -q skopeo '$T/log'"
status "ostree-unverified-registry:$M:lucciola" "ostree-image-signed:docker://$L:candidate"
mover "a switch to another Lucciola tag pending: nothing" - 0
status "ostree-unverified-registry:$M:lucciola" "ostree-image-signed:docker://$M:lucciola"
mover "update of margine:lucciola staged (signed-origin/uupd): replaced by the move" "$S" 0
status "ostree-image-signed:docker://$M:lucciola" "ostree-image-signed:docker://$M:stable"
mover "user staged a switch to Margine :stable: left alone" - 0
check "  says why" said "another switch is pending"
status "ostree-image-signed:docker://$M:lucciola" "-"
mover "pending deployment without an image reference: left alone" - 0
status "ostree-image-signed:docker://$M:lucciola" none "$S"
mover "went back from Lucciola's image (rollback): waits" - 0
check "  points at the opt-out" said "stay-on-margine"

status "ostree-image-signed:docker://$M:lucciola"
touch "$T/stay-on-margine"
mover "opt-out file: nothing" - 0
check "  no registry check" sh -c "! grep -q skopeo '$T/log'"
rm -f "$T/stay-on-margine"

mover "Lucciola's :stable not published: nothing, rc 0" - 0 FAKE_UNPUBLISHED=1
check "  three tries" count "skopeo inspect" 3
check "  no notice" sh -c "! grep -q runuser '$T/log'"
mover "rebase fails (signature/network): reported, rc 1" "$S" 1 FAKE_REBASE_FAIL=1
check "  no notice" sh -c "! grep -q runuser '$T/log'"
mover "no signature scope for Lucciola's repository: nothing" - 0 MARGINE_POLICY="$T/policy-margine-only.json"
check "  never asks the registry" sh -c "! grep -q skopeo '$T/log'"
mover "policy file missing: nothing" - 0 MARGINE_POLICY="$T/nonexistent.json"

mover "test override to :candidate" "ostree-image-signed:docker://$L:candidate" 0 LUCCIOLA_MOVE_TARGET="$L:candidate"
check "  checks :candidate" logged "skopeo inspect --no-tags docker://$L:candidate"
mover "override outside Lucciola's repository: refused" - 1 LUCCIOLA_MOVE_TARGET="ghcr.io/example/other:stable"
mover "override to a look-alike repository: refused" - 1 LUCCIOLA_MOVE_TARGET="${L}-evil:stable"
mover "override by digest: refused" - 1 LUCCIOLA_MOVE_TARGET="$L@$D"
mover "override with tag and digest: refused" - 1 LUCCIOLA_MOVE_TARGET="$L:stable@$D"

# notifier NAME WANT-NOTICES WANT-STAMP(or -) [VAR=VALUE...]
notifier() {
  local name="$1" want_n="$2" want_stamp="$3" rc=0; shift 3
  : > "$T/log"
  env -i PATH="$T/bin:/usr/bin:/bin" HOME="$T/home" FAKE_STATUS="$T/status.json" FAKE_LOG="$T/log" \
    MARGINE_NOTIFY="$T/bin/margine-notify" "$@" bash "$NOTIFIER" > "$T/out" 2>&1 || rc=$?
  local n; n="$(grep -c '^notify ' "$T/log" || true)"
  local stamp; stamp="$(cat "$T/home/.local/state/lucciola/move-notified" 2>/dev/null || echo -)"
  if [ "$rc" = 0 ] && [ "$n" = "$want_n" ] && [ "$stamp" = "$want_stamp" ]; then echo "ok   $name"
  else echo "FAIL $name: rc=$rc notices=$n (want $want_n) stamp=$stamp (want $want_stamp)"; sed 's/^/     /' "$T/log" "$T/out"; fails=$((fails+1)); fi
}
echo "== move-notify"
status "ostree-unverified-registry:$M:lucciola" "$S"
notifier "move pending, no daemon answering: no stamp" 1 - FAKE_NOTIFY_FAIL=1
notifier "move pending: one notice, stamped with the booted deployment" 1 booted-sum
check "  title, sent as Lucciola" logged "notify -u normal -a Lucciola Lucciola moved to its own image"
check "  Margine's 'Update ready' for that deployment marked seen" \
  test "$(cat "$T/home/.local/state/margine/staged-seen")" = pending-sum
notifier "next login, same deployments: silent" 0 booted-sum
rm -rf "$T/home/.local"
status "ostree-image-signed:docker://$M:lucciola" "ostree-image-signed:docker://$L:candidate"
notifier "move to another Lucciola tag pending (test override): notice" 1 booted-sum
rm -rf "$T/home/.local"
status "ostree-image-signed:docker://$M:lucciola" "ostree-image-signed:docker://$M:lucciola"
notifier "only an update of margine:lucciola pending: silent" 0 -
status "ostree-image-signed:docker://$M:lucciola"
notifier "nothing pending: silent" 0 -
status "ostree-image-signed:docker://$L:stable" none "ostree-image-signed:docker://$M:lucciola"
notifier "after the restart, on Lucciola's image: silent" 0 -
status "ostree-image-signed:docker://$M:lucciola-test" "$S"
notifier "booted lucciola-test, Lucciola pending: silent (not the mover's case)" 0 -

if (( fails )); then echo "$fails Lucciola move case(s) failed"; exit 1; fi
echo "all Lucciola move cases passed"
