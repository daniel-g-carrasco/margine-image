#!/usr/bin/env bash
# Tests for /usr/libexec/margine/grub-lock in a throwaway GRUB directory.
# No root, no bootloader: MARGINE_GRUB_DIR points the helper at a temp dir
# and grub2-mkpasswd-pbkdf2 is stubbed (same output format as the real one).
set -euo pipefail
HELPER="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/build_files/system_files/usr/libexec/margine/grub-lock"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fails=0

mkdir -p "$T/bin"
# shellcheck disable=SC2016
cat > "$T/bin/grub2-mkpasswd-pbkdf2" <<'STUB'
#!/bin/sh
read -r a; read -r b
[ "$a" = "$b" ] || { echo "passwords don't match" >&2; exit 1; }
echo "Enter password: "
echo "Reenter password: "
echo "PBKDF2 hash of your password is grub.pbkdf2.sha512.10000.SALT.HASHOF$a"
STUB
chmod +x "$T/bin/grub2-mkpasswd-pbkdf2"

new_dir() {  # new_dir <with-users-snippet: yes|no>
  G="$T/grub2"; rm -rf "$G"; mkdir -p "$G"
  if [ "$1" = yes ]; then
    # shellcheck disable=SC2016
    printf 'if [ -f ${prefix}/user.cfg ]; then\n  source ${prefix}/user.cfg\n  if [ -n "${GRUB2_PASSWORD}" ]; then\n    set superusers="root"\n  fi\nfi\nblscfg\n' > "$G/grub.cfg"
  else
    printf 'blscfg\n' > "$G/grub.cfg"
  fi
}
run() {  # run <action> [stdin] ; sets RC and OUT
  RC=0
  OUT="$(printf '%s' "${2:-}" | env -i PATH="$T/bin:/usr/bin:/bin" MARGINE_GRUB_DIR="$G" bash "$HELPER" "$1" 2>&1)" || RC=$?
}
check() {  # check <name> <condition...>
  local name="$1"; shift
  if "$@"; then echo "ok   $name"; else echo "FAIL $name"; echo "$OUT" | sed 's/^/     /'; fails=$((fails+1)); fi
}
is_locked()   { grep -q '^GRUB2_PASSWORD=grub\.pbkdf2\.sha512\.' "$G/user.cfg" 2>/dev/null; }
not_locked()  { ! is_locked; }
rc_is()       { [ "$RC" = "$1" ]; }
mode_is_600() { [ "$(stat -c %a "$G/user.cfg")" = 600 ]; }
says()        { case "$OUT" in *"$1"*) return 0;; *) return 1;; esac; }

new_dir yes
run status;                              check "status on a fresh system: off"                     says "GRUB menu lock: off"
run on "$(printf 'Secret1234\nSecret1234\n')"; check "on: user.cfg written"                        is_locked
check "on: user.cfg is 0600"                                                                       mode_is_600
check "on: exit 0"                                                                                 rc_is 0
run status;                              check "status after on: ON"                               says "GRUB menu lock: ON"
run off;                                 check "off: user.cfg removed"                             not_locked
run on "$(printf 'Secret1234\nSecret9999\n')"; check "mismatch refused, nothing written"           not_locked
check "mismatch: non-zero exit"                                                                    rc_is 1
run on "$(printf 'p@ss-word!\np@ss-word!\n')"; check "symbols refused (US layout at boot)"          not_locked
run on "$(printf 'short1\nshort1\n')";   check "shorter than 8 refused"                            not_locked
new_dir no
run on "$(printf 'Secret1234\nSecret1234\n')"; check "config that ignores user.cfg: refused"       not_locked
run status;                              check "config that ignores user.cfg: says not available"  says "not available"
G="$T/absent"
run status;                              check "no GRUB directory: clear error"                    says "does not boot through GRUB"

if (( fails )); then echo "$fails grub-lock case(s) failed"; exit 1; fi
echo "all grub-lock cases passed"
