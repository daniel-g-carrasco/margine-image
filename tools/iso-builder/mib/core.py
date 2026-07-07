# mib/core.py — shared plumbing for the Margine ISO Builder pages.
# NO Gtk here (only Gio/GLib): pages import this from any context, including
# worker threads that must not touch widget code.
import datetime
import hashlib
import json
import os
import re
import shlex
import shutil
import subprocess

import gi  # noqa: F401  (gi.repository needs the gi import side effects)
from gi.repository import Gio, GLib

APP_ID = "place.empty.margine.IsoBuilder"
# core.py lives in tools/iso-builder/mib/ → repo root is three levels up.
REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
BUILD_SCRIPT = os.path.join(REPO_ROOT, "live-env", "build-iso-local.sh")
OUTPUT_DIR = os.path.join(REPO_ROOT, "output")
BASE_TAGS = ["stable", "latest", "nvidia"]

QEMU_CONN = "qemu:///session"
VM_PREFIX = "margine-test-"
VM_TEMPLATE = "margine-test-template"
LIBVIRT_IMAGES = os.path.expanduser("~/.local/share/libvirt/images")


def _detect_repo_slug():
    """owner/repo of the git origin — gh calls never rely on the process cwd
    (the app may be launched from the GNOME grid, whose cwd is $HOME)."""
    try:
        url = subprocess.run(
            ["git", "-C", REPO_ROOT, "remote", "get-url", "origin"],
            capture_output=True, text=True, timeout=5).stdout.strip()
        m = re.search(r"github\.com[:/]([^/\s]+/[^/\s.]+)", url)
        return m.group(1) if m else None
    except Exception:
        return None


def _detect_gh():
    """Absolute path of gh. On Bluefin DX gh is typically brew-installed under
    /home/linuxbrew/.linuxbrew/bin, which a GNOME-launched process never has on
    PATH — and shells don't help: /etc/profile.d/brew.sh is guarded by
    `$- == *i*`, so even `bash -lc` (login, non-interactive) skips it. Probe
    the known locations directly instead of trusting any shell."""
    candidates = [shutil.which("gh"),
                  "/home/linuxbrew/.linuxbrew/bin/gh",
                  os.path.expanduser("~/.local/bin/gh"),
                  "/usr/bin/gh", "/usr/local/bin/gh"]
    for cand in candidates:
        if cand and os.access(cand, os.X_OK):
            return cand
    return None


# Startup-time one-shots (exempt from the async-only rule).
GH_REPO = _detect_repo_slug()
GH_BIN = _detect_gh()


# -- subprocess plumbing -------------------------------------------------------
def spawn_collect(argv, cb):
    """Run argv asynchronously; cb(ok, stdout, stderr) on the main loop."""
    try:
        proc = Gio.Subprocess.new(
            list(argv),
            Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE)
    except GLib.Error as e:
        # Keep the contract async even when spawn itself fails.
        GLib.idle_add(cb, False, "", e.message)
        return

    def _done(p, res):
        try:
            _, out, errtxt = p.communicate_utf8_finish(res)
        except GLib.Error as e:
            cb(False, "", e.message)
            return
        cb(p.get_successful(), out or "", errtxt or "")

    proc.communicate_utf8_async(None, None, _done)


def spawn_fire(argv):
    """Fire-and-forget spawn. None on success, else a human error message."""
    try:
        Gio.Subprocess.new(list(argv), Gio.SubprocessFlags.NONE)
        return None
    except GLib.Error as e:
        return e.message


def bash_fire(script):
    """Fire-and-forget a bash script. None on success, else an error message."""
    return spawn_fire(["bash", "-lc", script])


def bash_collect(script, cb):
    """Run a bash script asynchronously; cb(ok, stdout, stderr) on the main
    loop. Unlike bash_fire, a script that starts fine but exits non-zero
    reports back — bash_fire's silent late failure is how a broken VM
    launch once toasted success (2026-07-07)."""
    spawn_collect(["bash", "-lc", script], cb)


def gh(args, cb):
    """Run `gh` asynchronously; cb(ok, stdout, stderr) on the main loop.
    Uses the absolute GH_BIN — brew's bin dir is not on a GNOME-launched
    process' PATH."""
    if GH_BIN is None:
        GLib.idle_add(cb, False, "", "gh CLI not found")
        return
    spawn_collect([GH_BIN, *args], cb)


def gh_unavailable_reason():
    """None when gh is usable; else the human reason to show in the UI.
    Auth is NOT checked here — callers probe `gh auth status` async."""
    if GH_REPO is None:
        return "no GitHub origin remote found"
    if GH_BIN is None:
        return "gh CLI not found — install it (e.g. brew install gh)"
    return None


# -- small helpers --------------------------------------------------------------
def human_size(nbytes):
    """Decimal units, '9.6 GB' style (matches the GB maths CI sizes use)."""
    n = float(nbytes or 0)
    for unit in ("B", "kB", "MB", "GB", "TB", "PB"):
        if n < 1000 or unit == "PB":
            if unit == "B":
                return f"{int(n)} B"
            return f"{n:.1f} {unit}"
        n /= 1000


def iso_ts(s):
    """ISO8601 (trailing Z ok) → epoch seconds; 0.0 on parse failure."""
    try:
        return datetime.datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except Exception:
        return 0.0


def liveenv_rev():
    """Content hash of live-env/src, first 16 hex chars. MUST byte-match the
    LIVEENV_REV pipeline in build-iso-local.sh:
        find live-env/src -type f -print0 | LC_ALL=C sort -z \
          | xargs -0 sha256sum | sha256sum | cut -c1-16
    i.e. sha256 of the concatenated '<hash>  <relpath>\\n' lines, where the
    paths are REPO_ROOT-relative (the script runs from the repo root) and
    sorted as C-locale bytes. `find -type f` skips symlinks — so do we."""
    src = os.path.join(REPO_ROOT, "live-env", "src")
    try:
        paths = []
        for dirpath, _dirs, names in os.walk(src):  # followlinks=False = find
            for name in names:
                p = os.path.join(dirpath, name)
                if not os.path.islink(p):
                    paths.append(p)
        # LC_ALL=C sort = raw byte order of the repo-relative path.
        paths.sort(key=lambda p: os.fsencode(os.path.relpath(p, REPO_ROOT)))
        outer = hashlib.sha256()
        for p in paths:
            h = hashlib.sha256()
            with open(p, "rb") as f:
                for chunk in iter(lambda: f.read(1 << 20), b""):
                    h.update(chunk)
            rel = os.path.relpath(p, REPO_ROOT)
            outer.update(f"{h.hexdigest()}  {rel}\n".encode())
        return outer.hexdigest()[:16]
    except OSError:
        # Missing/unreadable src (broken checkout): no rev — callers treat a
        # mismatch as STALE, which is the honest answer here.
        return ""


# -- ISO inventory ---------------------------------------------------------------
def read_iso_meta(path):
    """Sidecar metadata written by build-iso-local.sh; None if absent/invalid."""
    try:
        with open(path + ".meta.json", encoding="utf-8") as f:
            meta = json.load(f)
        return meta if isinstance(meta, dict) else None
    except (OSError, ValueError):
        return None


def list_isos():
    """Newest-first inventory of OUTPUT_DIR/*.iso plus the download dirs
    (ci-<run>/ from gh artifacts, ia-<identifier>/ from the Internet Archive
    fallback). Each entry: {path, name, size, mtime, meta: dict|None,
    ci_run: str|None} — ci_run doubles as the download-source label."""
    found = []  # (path, ci_run)
    try:
        names = os.listdir(OUTPUT_DIR)
    except FileNotFoundError:
        return []
    for n in names:
        p = os.path.join(OUTPUT_DIR, n)
        if n.endswith(".iso") and os.path.isfile(p):
            found.append((p, None))
        elif (n.startswith("ci-") or n.startswith("ia-")) and os.path.isdir(p):
            # Downloads may nest (gh artifact layout, the torrent's root dir) —
            # walk the whole download dir.
            src = n[len("ci-"):] if n.startswith("ci-") else n
            for root_, _dirs, files in os.walk(p):
                for f in files:
                    if f.endswith(".iso"):
                        found.append((os.path.join(root_, f), src))
    entries = []
    for path, ci_run in found:
        try:
            st = os.stat(path)
        except OSError:
            continue  # raced with a delete
        entries.append({
            "path": path,
            "name": os.path.basename(path),
            "size": st.st_size,
            "mtime": st.st_mtime,
            "meta": read_iso_meta(path),
            "ci_run": ci_run,
        })
    entries.sort(key=lambda e: e["mtime"], reverse=True)
    return entries


def dir_size(path):
    """Recursive byte total; 0 if the path is missing."""
    total = 0
    for root_, _dirs, files in os.walk(path):
        for f in files:
            try:
                total += os.path.getsize(os.path.join(root_, f))
            except OSError:
                pass
    return total


# -- VM test ----------------------------------------------------------------------
def vm_teardown_script():
    """Bash lines that tear down the domain named in $N safely.

    NEVER `undefine --remove-all-storage`: libvirt deletes every attached
    volume, INCLUDING cdrom media. output/ is a session storage pool
    (virt-install auto-created it), so the ISO the old domain booted from
    resolves as a managed volume — and since rebuilds reuse the same
    Margine-Live.iso path, --remove-all-storage deleted a freshly built
    ISO on 2026-07-07. Instead: collect the writable-disk paths first,
    undefine with --nvram only, then delete just those scratch disks.

    Expects bash vars: CONN (connection URI) and N (domain name).
    """
    return (
        '  _vols=$(virsh -c "$CONN" domblklist "$N" --details 2>/dev/null'
        " | awk '$1==\"file\" && $2==\"disk\" && $NF!=\"-\" {print $NF}')\n"
        '  virsh -c "$CONN" destroy "$N" >/dev/null 2>&1 || true\n'
        '  virsh -c "$CONN" undefine "$N" --nvram >/dev/null 2>&1 \\\n'
        '    || virsh -c "$CONN" undefine "$N" >/dev/null 2>&1 || true\n'
        '  for _v in $_vols; do\n'
        '    virsh -c "$CONN" vol-delete "$_v" >/dev/null 2>&1 || rm -f -- "$_v"\n'
        '  done\n')


def vm_test_script(iso, name):
    # Recycle inline: the SHIPPED margine-test-vm recipe errors on an
    # existing same-named domain until the next base update ships PR #239's
    # recycle — same prelude the dev Justfile's test-install-vm uses.
    # (Once the base recipe DOES recycle, this teardown has already removed
    # the domain, so the shipped recycle stays a no-op.)
    return (
        f"CONN={QEMU_CONN}\n"
        f"N={shlex.quote(name)}\n"
        'if virsh -c "$CONN" dominfo "$N" >/dev/null 2>&1; then\n'
        + vm_teardown_script() +
        "fi\n"
        f"exec ujust margine-test-vm {shlex.quote(iso)} \"$N\"\n")
