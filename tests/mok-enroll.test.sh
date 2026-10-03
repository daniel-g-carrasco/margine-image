#!/usr/bin/env bash
# Tests for /usr/libexec/margine/mok-enroll against a fake mokutil.
# The bug these guard (2026-10-04): with Secure Boot off the old unit
# never enrolled the key and stamped itself done, so turning Secure Boot
# on later left the Margine kernel unbootable. No firmware, no root.
set -euo pipefail
HELPER="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/build_files/system_files/usr/libexec/margine/mok-enroll"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fails=0

mkdir -p "$T/bin" "$T/efi"
: > "$T/MOK.der"
# Fake mokutil: state in $MOK_STATE (enrolled|pending|absent), imports
# logged with the password they were given, $MOK_IMPORT_FAILS makes the
# import fail. Output text matches mokutil 0.7.2 (Fedora 44); its exit
# code is 0 whatever the answer, as the real one.
# shellcheck disable=SC2016
cat > "$T/bin/mokutil" <<'STUB'
#!/bin/sh
case "$1" in
  --test-key)
    if [ "$(cat "$MOK_STATE")" = enrolled ]; then echo "$2 is already enrolled"; else echo "$2 is not enrolled"; fi ;;
  --list-new)
    [ "$(cat "$MOK_STATE")" = pending ] && printf '[key 1]\n        Subject: CN=Margine MOK Signing Key\n' ;;
  --import)
    read -r p1; read -r p2
    echo "import $p1 $p2" >> "$MOK_LOG"
    [ -n "${MOK_IMPORT_FAILS:-}" ] && exit 1
    echo pending > "$MOK_STATE" ;;
esac
exit 0
STUB
printf '#!/bin/sh\nexit 0\n' > "$T/bin/logger"
chmod +x "$T/bin/"*

# run_case NAME STATE MODE EXPECT_IMPORTS EXPECT_RC [switch] [efi] [cert] [import_fails]
run_case() {
  local name="$1" state="$2" mode="$3" want_imports="$4" want_rc="$5"
  local sw="${6:-}" efi="${7:-$T/efi}" cert="${8:-$T/MOK.der}" ifail="${9:-}"
  echo "$state" > "$T/state"; : > "$T/log"
  if [ -n "$sw" ]; then echo "$sw" > "$T/switch"; else rm -f "$T/switch"; fi
  local rc=0
  env -i PATH="$T/bin:/usr/bin:/bin" MOK_STATE="$T/state" MOK_LOG="$T/log" \
      MOK_IMPORT_FAILS="$ifail" MARGINE_MOK_CERT="$cert" MARGINE_MOK_SWITCH="$T/switch" \
      MARGINE_MOK_EFI_DIR="$efi" bash "$HELPER" $mode > "$T/out" 2>&1 || rc=$?
  local imports; imports="$(grep -c '^import' "$T/log" || true)"
  if [ "$imports" = "$want_imports" ] && [ "$rc" = "$want_rc" ] \
     && { [ "$imports" = 0 ] || grep -qx 'import margine margine' "$T/log"; }; then
    echo "ok   $name"
  else
    echo "FAIL $name: imports=$imports (want $want_imports) rc=$rc (want $want_rc)"; sed 's/^/     /' "$T/out"; fails=$((fails+1))
  fi
}

run_case "key absent, boot: staged, with the public password" absent "" 1 0
run_case "key already enrolled: nothing staged"               enrolled "" 0 0
run_case "request already pending: not staged twice"          pending "" 0 0
run_case "absent but switched off: left alone at boot"        absent "" 0 0 off
run_case "absent, switched off, explicit enroll: staged"      absent enroll 1 0 off
run_case "status never stages anything"                       absent status 0 0
run_case "legacy BIOS boot (no efi dir): nothing to do"       absent "" 0 0 "" "$T/no-efi"
run_case "image without the certificate: nothing to do"       absent "" 0 0 "" "$T/efi" "$T/missing.der"
run_case "import fails: reported as a failure"                absent "" 1 1 "" "$T/efi" "$T/MOK.der" yes

# The state the reference laptop was found in: an old marker from the
# first version exists. The helper must not care about it at all.
grep -q '/var/.mok-enrolled' "$HELPER" && grep -n '/var/.mok-enrolled' "$HELPER" | grep -v '^[0-9]*:#' \
  && { echo "FAIL helper still reads /var/.mok-enrolled"; fails=$((fails+1)); }

if (( fails )); then echo "$fails mok-enroll case(s) failed"; exit 1; fi
echo "all mok-enroll cases passed"
