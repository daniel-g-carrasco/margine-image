# shellcheck shell=bash
# Sourced by Margine helpers that write to /boot (grub-hidpi-apply,
# grub-lock). Not executable on its own.
#
# Recent bootc installs mount /boot READ-ONLY to protect it (found
# 2026-10-07 by the security smoke probe: margine-grub-hidpi.service
# failed on every boot of a fresh install with "Read-only file system",
# and margine-grub-lock would have failed the same way). Older installs,
# such as the reference laptop, still have it read-write. boot_writable
# remounts /boot read-write only if it is read-only, and boot_restore puts
# it back exactly as it was; callers run boot_restore from an EXIT trap so
# a failed write never leaves /boot writable.
#
# MARGINE_BOOT_MOUNT overrides the mount point (tests).
BOOT_MOUNT="${MARGINE_BOOT_MOUNT:-/boot}"
BOOT_REMOUNTED=0

boot_writable() {
  local opts
  # Not a mount point of its own (no separate /boot): nothing to do.
  opts="$(findmnt -no OPTIONS "$BOOT_MOUNT" 2>/dev/null || true)"
  case ",$opts," in
    *,ro,*)
      mount -o remount,rw "$BOOT_MOUNT" \
        || { echo "ERROR: $BOOT_MOUNT is read-only and could not be remounted read-write" >&2; return 1; }
      BOOT_REMOUNTED=1 ;;
  esac
  return 0
}

boot_restore() {
  if [ "$BOOT_REMOUNTED" = 1 ]; then
    sync
    mount -o remount,ro "$BOOT_MOUNT" || echo "WARNING: could not put $BOOT_MOUNT back to read-only" >&2
    BOOT_REMOUNTED=0
  fi
  return 0
}
