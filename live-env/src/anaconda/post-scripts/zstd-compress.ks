# btrfs zstd:1 compression for the installed root (Titanoboa / ADR-0008,
# ported verbatim from disk_config/iso-gnome.toml:139-218).
#
# Anaconda's default btrfs has no compression. We enable zstd:1 (fastest
# preset, ~30% saved on typical desktop data, negligible CPU) — the same
# level Bazzite/SteamOS ship. Two layers: `btrfs property set` for new
# writes, and compress=zstd:1 in /etc/fstab for durability/debuggability.
# Not --erroronfail: a missing compress flag is a QoL regression, not an
# install failure.
%post --log=/tmp/anaconda-post-zstd.log
set -uo pipefail

echo "=== zstd:1 setup ==="
mount | grep -E ' on / type' || true
echo "Initial /etc/fstab:"
cat /etc/fstab

if findmnt -no FSTYPE / | grep -q '^btrfs$'; then
  if btrfs property set / compression zstd 2>&1; then
    echo "OK: btrfs property compression=zstd set on /"
  else
    echo "WARN: btrfs property set failed (continuing)"
  fi
else
  echo "/ is not btrfs (findmnt says $(findmnt -no FSTYPE /)) — skipping btrfs property set"
fi

# Idempotently add compress=zstd:1 to the / btrfs line in /etc/fstab.
# python3 (always present) avoids sed/grep backslash pain.
python3 <<'PYEOF'
import sys
try:
    with open('/etc/fstab') as f:
        lines = f.read().splitlines()
except FileNotFoundError:
    print('WARN: /etc/fstab not found, skipping zstd patch')
    sys.exit(0)
out = []
patched = False
for line in lines:
    if line.startswith('#') or not line.strip():
        out.append(line)
        continue
    fields = line.split()
    if len(fields) >= 4 and fields[1] == '/' and fields[2] == 'btrfs':
        if 'compress=' in fields[3]:
            print('compress= already present on / btrfs line, no change')
            out.append(line)
        else:
            fields[3] = fields[3] + ',compress=zstd:1'
            out.append(' '.join(fields))
            patched = True
            print('patched / btrfs line: ' + ' '.join(fields))
    else:
        out.append(line)
with open('/etc/fstab', 'w') as f:
    f.write('\n'.join(out) + '\n')
if not patched:
    print('No btrfs / line to patch in /etc/fstab')
PYEOF

echo "Final /etc/fstab:"
cat /etc/fstab
%end
