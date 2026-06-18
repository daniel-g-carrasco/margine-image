#!/usr/bin/env python3
"""Print the BitTorrent info-hash (btih) of a .torrent file.

Usage: ia-btih.py <torrent-file>

btih = sha1 of the bencoded `info` dict. The site composes the full magnet URI
from this hash plus constant trackers + the IA web-seed, so the only per-release
value that has to be bumped is this short hex string (trivially sed-able).
"""

import hashlib
import sys


def _parse(buf, i):
    """Minimal bencode reader. Returns (value, next_index); dict values are
    recorded as their (start, end) byte range so the info dict can be hashed
    byte-exactly."""
    c = chr(buf[i])
    if c == "d":
        i += 1
        out = {}
        while i < len(buf) and chr(buf[i]) != "e":
            key, i = _parse(buf, i)
            start = i
            _, i = _parse(buf, i)
            out[key] = (start, i)
        if i >= len(buf):
            raise ValueError("truncated dict (unterminated)")
        return out, i + 1
    if c == "l":
        i += 1
        while i < len(buf) and chr(buf[i]) != "e":
            _, i = _parse(buf, i)
        if i >= len(buf):
            raise ValueError("truncated list (unterminated)")
        return None, i + 1
    if c == "i":
        j = buf.index(b"e", i)
        return int(buf[i + 1 : j]), j + 1
    if c.isdigit():
        j = buf.index(b":", i)
        n = int(buf[i:j])
        raw = buf[j + 1 : j + 1 + n]
        try:
            return raw.decode(), j + 1 + n
        except UnicodeDecodeError:
            return raw, j + 1 + n
    raise ValueError(f"bad bencode at byte {i}")


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: ia-btih.py <torrent-file>")
    with open(sys.argv[1], "rb") as fh:
        data = fh.read()
    try:
        top, _ = _parse(data, 0)
    except (ValueError, IndexError) as exc:
        sys.exit(f"bencode parse error: {exc}")
    if not isinstance(top, dict) or "info" not in top:
        sys.exit("no info dict in torrent")
    start, end = top["info"]
    print(hashlib.sha1(data[start:end]).hexdigest())  # noqa: S324 (btih is sha1 by spec)


if __name__ == "__main__":
    main()
