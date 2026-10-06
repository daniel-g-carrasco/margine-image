#!/usr/bin/env bash
# Tests for .github/scripts/scan-image-security.py on a throwaway rootfs.
# Exit codes under test: 0 clean, 1 baseline drift, 2 secrets.
set -euo pipefail
SCAN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.github/scripts/scan-image-security.py"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fails=0

fresh() {
  R="$T/root"; B="$T/base"; rm -rf "$R" "$B" "$T/owned"
  mkdir -p "$R/usr/bin" "$R/etc/ssh" "$R/usr/lib/systemd/system/multi-user.target.wants" "$R/var/roothome" "$B"
  printf 'echo hi\n' > "$R/usr/bin/tool"
  printf 'uninitialized\n' > "$R/etc/machine-id"
  ln -s ../tool.service "$R/usr/lib/systemd/system/multi-user.target.wants/tool.service"
  ln -s var/roothome "$R/root"
  : > "$T/owned"
}
key() { printf -- '-----BEGIN PRIVATE KEY-----\nMIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQC7VJTUt9Us8cKj\n-----END PRIVATE KEY-----\n' > "$1"; }
run() { rc=0; python3 "$SCAN" --rootfs "$R" --owned "$T/owned" --baseline "$B" --report "$T/report" ${1:-} || rc=$?; }
expect() {  # name expected-rc
  if [ "$rc" = "$2" ]; then echo "ok   $1"; else echo "FAIL $1: rc=$rc (want $2)"; sed 's/^/     /' "$T/report"; fails=$((fails+1)); fi
}

fresh; run "--write-baseline $B"; run;                                  expect "image equal to its own baseline: clean" 0
fresh; run "--write-baseline $B"; mkdir -p "$R/var/roothome/.android"; key "$R/var/roothome/.android/adbkey"; run
                                                                        expect "root adb key (the 2026-10 incident): secret" 2
grep -q 'var/roothome/.android/adbkey' "$T/report" && grep -vq '^+ root/' "$T/report" && echo "ok   reported once, not again through the /root symlink" || { echo "FAIL duplicate or missing report"; fails=$((fails+1)); }
fresh; mkdir -p "$R/usr/share/x"; key "$R/usr/share/x/test-private.pem"; printf 'usr/share/x/*-private.pem\n' > "$B/secrets-allow.txt"
       run "--write-baseline $B"; run;                                  expect "allowlisted public test key: not a secret" 0
fresh; key "$R/usr/bin/vendor.pem"; echo /usr/bin/vendor.pem > "$T/owned"; run "--write-baseline $B"; run
                                                                        expect "key in a package-owned file outside etc/var: not flagged" 0
fresh; key "$R/etc/ssh/ssh_host_ed25519_key"; run "--write-baseline $B"; run
                                                                        expect "ssh host key baked in: secret" 2
fresh; printf '0123456789abcdef0123456789abcdef\n' > "$R/etc/machine-id"; run "--write-baseline $B"; run
                                                                        expect "machine-id set in the image: secret" 2
fresh; run "--write-baseline $B"; chmod 4755 "$R/usr/bin/tool"; run;    expect "new setuid binary: drift" 1
grep -q '^+ usr/bin/tool setuid' "$T/report" && echo "ok   drift names the file" || { echo "FAIL drift report"; fails=$((fails+1)); }
fresh; run "--write-baseline $B"; ln -s ../evil.service "$R/usr/lib/systemd/system/multi-user.target.wants/evil.service"; run
                                                                        expect "newly enabled unit: drift" 1
fresh; mkdir -p "$R/etc/containers"; echo '{"default":[{"type":"reject"}]}' > "$R/etc/containers/policy.json"; run "--write-baseline $B"
       echo '{"default":[{"type":"insecureAcceptAnything"}]}' > "$R/etc/containers/policy.json"; run
                                                                        expect "container policy relaxed: drift with a diff" 1
grep -q 'insecureAcceptAnything' "$T/report" && echo "ok   the diff shows the new policy" || { echo "FAIL config diff"; fails=$((fails+1)); }
fresh; run "--write-baseline $B"; mkdir -p "$R/run/build"; touch "$R/run/build/lock"; run
                                                                        expect "build residue in /run: drift" 1
fresh; run "--write-baseline $B"; mkdir -p "$R/etc/w"; chmod 0777 "$R/etc/w"; run
                                                                        expect "world-writable dir without sticky bit in etc: drift" 1

fresh; mkdir -p "$R/etc/ImageMagick-7"; printf '<mime type="application/pgp-keys" magic="-----BEGIN PGP PRIVATE KEY BLOCK-----" priority="50"/>\n' > "$R/etc/ImageMagick-7/mime.xml"
       run "--write-baseline $B"; run;                                  expect "key header as a magic string (ImageMagick mime.xml): not a secret" 0
fresh; mkdir -p "$R/etc/aws"; printf 'aws_access_key_id = AKIAIOSFODNN7EXAMPLE\n' > "$R/etc/aws/docs.conf"; run "--write-baseline $B"; run
                                                                        expect "AWS documented example key: not a secret" 0
fresh; mkdir -p "$R/etc/aws"; printf 'aws_access_key_id = AKIA2E0A8F3B244C9986\n' > "$R/etc/aws/creds"; run "--write-baseline $B"; run
                                                                        expect "real-looking AWS key in etc: secret" 2
fresh; mkdir -p "$R/sysroot/ostree/repo/objects/05"; key "$R/sysroot/ostree/repo/objects/05/abc.file"; chmod 4755 "$R/sysroot/ostree/repo/objects/05/abc.file"
       run "--write-baseline $B"; run;                                  expect "sysroot/ostree object store (pruned before publishing): ignored" 0
grep -q sysroot "$B/privileged.txt" && { echo "FAIL sysroot object listed as privileged"; fails=$((fails+1)); } || echo "ok   sysroot not in the privileged list"

if (( fails )); then echo "$fails scan case(s) failed"; exit 1; fi
echo "all image security scan cases passed"
