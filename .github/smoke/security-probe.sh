#!/usr/bin/env bash
# Margine security smoke probe: runs INSIDE the smoke-boot VM as a root
# oneshot (margine-security-smoke.service), injected into the qcow2 by
# .github/scripts/inject-gui-probe.sh. GATING: qemu-boot-wait.sh refuses
# to pass the boot without "MARGINE-SEC-SMOKE: PASS" (2026-10-07).
#
# Why: every security hole found in the first week of October 2026 was
# "present but never exercised": a kernel signing chain nobody booted
# with Secure Boot on, an enrollment service that never enrolled, image
# signatures no device could read, an SELinux home mapping inherited
# reversed. Each check below exercises the promise on the booted system,
# the way a user's machine does.
#
# The VM boots with Secure Boot enforcing (OVMF + Microsoft keys + the
# Margine key in MokList) and a software TPM. SELinux runs permissive in
# this VM (injected test files carry no labels), so every denial is still
# logged: that is the AVC report below.
set -u
out() {
  # PROBE_STDOUT=1: print instead (running it by hand on a real machine)
  if [ "${PROBE_STDOUT:-0}" = 1 ]; then echo "$@"; return 0; fi
  echo "$@" > /dev/console 2>/dev/null || true
  echo "<sec> $*" > /dev/kmsg 2>/dev/null || true
}
FAILS=0
res() {  # name PASS|FAIL|WARN detail
  out "MARGINE-SEC: $1 $2 ${3:-}"
  [ "$2" = FAIL ] && FAILS=$((FAILS + 1))
  return 0
}
SMOKE="${PROBE_DIR:-/etc/margine-smoke}"
REF="$(cat "$SMOKE/image-ref" 2>/dev/null || true)"

# 1. Secure Boot enforcing, and still booted: shim accepted the kernel.
sb="$(mokutil --sb-state 2>&1 | head -n1)"
case "$sb" in
  *"SecureBoot enabled"*) res secure-boot PASS "booted with Secure Boot enforcing" ;;
  *) res secure-boot FAIL "$sb" ;;
esac

# 2. The Margine key is the one shim trusts here, and Margine's own helper
#    agrees (the helper is what users rely on: ujust margine-secureboot).
k="$(mokutil --test-key /usr/share/cert/MOK.der 2>/dev/null)"
case "$k" in
  *"is already enrolled"*) res mok-key PASS "Margine key in MokList" ;;
  *) res mok-key FAIL "${k:-mokutil gave no answer}" ;;
esac
h="$(/usr/libexec/margine/mok-enroll status 2>/dev/null || true)"
[ "$h" = enrolled ] && res mok-helper PASS "mok-enroll status: enrolled" || res mok-helper FAIL "mok-enroll status: ${h:-no answer}"

# 3. Measured boot reaches the TPM: PCR 7 (Secure Boot policy) extended.
pcr=/sys/class/tpm/tpm0/pcr-sha256/7
if [ -r "$pcr" ]; then
  v="$(cat "$pcr")"
  case "$v" in
    ""|*[!0]*) [ -n "$v" ] && res tpm-pcr7 PASS "PCR 7 measured" || res tpm-pcr7 FAIL "PCR 7 unreadable" ;;
    *) res tpm-pcr7 FAIL "PCR 7 all zeros: nothing measured" ;;
  esac
else
  res tpm-pcr7 WARN "no TPM in this VM"
fi

# 4. SELinux maps the real home path, not the /home alias (2026-10 bug:
#    the base's policy package reversed it and every home became default_t).
a="$(matchpathcon /var/home/probe/.ssh 2>/dev/null)"
b="$(matchpathcon /var/home/probe 2>/dev/null)"
case "$a" in *:ssh_home_t:*) res selinux-ssh-home PASS "${a##* }" ;; *) res selinux-ssh-home FAIL "${a:-no answer}" ;; esac
case "$b" in *:user_home_dir_t:*) res selinux-home-dir PASS "${b##* }" ;; *) res selinux-home-dir FAIL "${b:-no answer}" ;; esac

# 5. The device verifies Margine images: a sigstoreSigned scope for the
#    Margine repository, with its key present. Without it every "signed"
#    transport falls through to insecureAcceptAnything and checks nothing.
if python3 - <<'PY' 2>/dev/null
import json, os, sys
p = json.load(open("/etc/containers/policy.json"))
r = p["transports"]["docker"]["ghcr.io/daniel-g-carrasco/margine"][0]
sys.exit(0 if r["type"] == "sigstoreSigned" and os.path.isfile(r["keyPath"]) else 1)
PY
then
  res trust-policy PASS "policy.json requires the Margine signature"

  # 6. ...and that check passes for the very image under test, through the
  #    device's own stack (containers/image as rpm-ostree uses it): the
  #    policy is evaluated before any blob is copied, so "Copying blob"
  #    means the signature was accepted.
  if [ -n "$REF" ]; then
    rm -rf /var/tmp/sigcheck
    timeout 120 skopeo copy --retry-times 2 "docker://$REF" dir:/var/tmp/sigcheck > /tmp/sigcheck.log 2>&1
    if grep -q "Copying blob" /tmp/sigcheck.log; then
      res image-signature PASS "device policy accepts $REF"
    elif grep -qiE "signature|rejected|policy" /tmp/sigcheck.log; then
      res image-signature FAIL "$(grep -m1 -oE 'msg=.*|rejected.*' /tmp/sigcheck.log | cut -c1-200)"
    else
      res image-signature WARN "no verdict (network?): $(tail -n1 /tmp/sigcheck.log | cut -c1-160)"
    fi
    rm -rf /var/tmp/sigcheck
  else
    res image-signature WARN "image reference not injected"
  fi
else
  res trust-policy FAIL "no sigstoreSigned scope for ghcr.io/daniel-g-carrasco/margine (or its key is missing)"
fi

# 7. No unexpected network listeners on non-loopback addresses.
allow="$SMOKE/listeners-allow.txt"
lfail=0
while read -r proto addr; do
  case "$addr" in 127.*|"[::1]"*|*%lo:*) continue ;; esac
  port="${addr##*:}"
  if grep -qxE "${proto}[[:space:]]+${port}" "$allow" 2>/dev/null; then
    continue
  fi
  res listener FAIL "unexpected $proto listener on $addr"
  lfail=1
done < <(ss -H -tlnu 2>/dev/null | awk '{print $1, $5}' | sort -u)
[ "$lfail" = 0 ] && res listeners PASS "only allowed ports on non-loopback addresses"

# 8. Failed units: a failed Margine unit fails the gate, others are reported.
#    An empty list says so explicitly: no line at all would look the same as
#    a check that never ran.
if failed_list="$(systemctl list-units --failed --plain --no-legend 2>/dev/null)"; then
  mapfile -t failed < <(printf '%s\n' "$failed_list" | awk 'NF {print $1}')
  for u in "${failed[@]}"; do
    case "$u" in
      margine-*|mok-enroll*) res failed-unit FAIL "$u: $(journalctl -b -u "$u" --no-pager -o cat 2>/dev/null | tail -n 4 | tr '\n' ' ' | cut -c1-240)" ;;
      *) res failed-unit WARN "$u" ;;
    esac
  done
  [ "${#failed[@]}" -eq 0 ] && res failed-units PASS "no failed units"
else
  res failed-units FAIL "could not list failed units"
fi

# 8b. /boot is read-only again once the boot-time writers are done. Fresh
#     bootc installs (this VM) mount it read-only; Margine's helpers make it
#     writable only for their own writes (#456). Read-write here means one
#     of them left it open, or bootc changed its default: look either way.
boot_opts="$(findmnt -no OPTIONS /boot 2>/dev/null || true)"
case ",$boot_opts," in
  ,,)     res boot-ro WARN "/boot is not a separate mount" ;;
  *,ro,*) res boot-ro PASS "/boot is read-only" ;;
  *)      res boot-ro FAIL "/boot is mounted read-write after boot: ${boot_opts}" ;;
esac

# 9. The in-image acceptance test (audit 2026-06-05 §8 rec #19, open
#    until now): the same validator users run, in its smoke-boot context.
if MARGINE_VALIDATE_CONTEXT=smoke-boot timeout 180 /usr/bin/margine-validate-margine-system > /tmp/validate.log 2>&1; then
  res validator PASS "margine-validate-margine-system"
else
  res validator WARN "$(sed 's/\x1b\[[0-9;]*m//g' /tmp/validate.log | grep -m3 'FAIL' | tr '\n' ' ' | cut -c1-220)"
fi

# 10. SELinux denials. Permissive here, so this is the list of what would
#     have been blocked on an enforcing system, minus the test scaffolding.
mapfile -t avc < <(journalctl -b -k --no-pager -o cat 2>/dev/null | grep 'avc:  denied' \
  | grep -vE 'margine-smoke|smoke|unlabeled_t|/var/home/smoke' | sed -E 's/.*avc:  denied  //' | sort | uniq -c | sort -rn)
if [ "$(id -u)" != 0 ]; then
  res selinux-denials WARN "not root: kernel log not readable"
elif [ "${#avc[@]}" -eq 0 ]; then
  res selinux-denials PASS "none outside the test scaffolding"
else
  res selinux-denials WARN "${#avc[@]} distinct; top: $(printf '%s | ' "${avc[@]:0:3}" | cut -c1-260)"
fi

if [ "$FAILS" -eq 0 ]; then
  out "MARGINE-SEC-SMOKE: PASS"
else
  out "MARGINE-SEC-SMOKE: FAIL ($FAILS check(s))"
fi
exit 0
