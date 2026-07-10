# Margine ISO Builder v2 — design (frozen for parallel implementation)

Dev tool, NOT shipped in the distro. This doc freezes module boundaries and
interfaces so multiple implementers can work in parallel without touching each
other's files. **Each implementer writes ONLY the files assigned to them.**

## Layout

```
tools/iso-builder/
  margine-iso-builder.py   # thin entry: app + window + page assembly (integration owns this)
  mib/
    __init__.py            # empty (core owner creates it)
    core.py                # shared plumbing — NO Gtk import (only Gio/GLib ok)
    build.py               # page 1: local build + ISO inventory (+ USB handoff)
    ci.py                  # page 2: CI dashboard + rebuild/publish/download + changelog
    maint.py               # page 3: test VMs + disk usage/reclaim
    help.py                # redesigned How-to-use dialog
```

Entry point path and `APP_ID = "dev.margine.IsoBuilder"` MUST NOT
change (a .desktop launcher and a Justfile recipe point at them).
Runtime: `/usr/bin/python3` (system, PyGObject), GTK4 + libadwaita ≥ 1.5
(Fedora 44). Stdlib + gi only — no new dependencies.

## Window shell (entry file)

- `Adw.ApplicationWindow`, header `Adw.HeaderBar` with:
  - title widget: `Adw.ViewSwitcher` over an `Adw.ViewStack` with three pages —
    "Build" (`drive-optical-symbolic`), "CI" (`network-transmit-receive-symbolic`),
    "Maintenance" (`user-trash-symbolic`)
  - pack_start: help button (`help-about-symbolic`) → `mib.help.show_help(win)`
  - pack_end: open-output-folder button (unchanged behavior)
- On `notify::visible-child` call the incoming page's `.refresh()`.
- Window exposes to pages:
  - `win.toast(text)` — Adw.Toast
  - `win.notify(title, body="")` — toast + `Gio.Notification` via the app
  - `win.append_log(text)` — appends to the Build page log pane (Build page
    registers the sink via `win.set_log_sink(callable)`; before registration
    `append_log` buffers)
- Smoke mode: if env `MIB_SMOKE` is set, the app auto-quits ~1.5 s after
  activate (constructor coverage in CI-less testing). Exit 0 = pass.

## mib/core.py — frozen interface (consumers import exactly these names)

```python
APP_ID, REPO_ROOT, OUTPUT_DIR, BUILD_SCRIPT   # as in v1
BASE_TAGS = ["stable", "latest", "nvidia"]
GH_REPO: str | None      # "owner/repo" from git origin (v1 logic)
GH_BIN: str | None       # absolute gh path; probe which() + /home/linuxbrew/
                         # .linuxbrew/bin/gh + ~/.local/bin/gh + /usr/bin/gh +
                         # /usr/local/bin/gh. NEVER rely on PATH or `bash -lc`
                         # (/etc/profile.d/brew.sh is interactive-guarded).
QEMU_CONN = "qemu:///session"
VM_PREFIX = "margine-test-"
VM_TEMPLATE = "margine-test-template"
LIBVIRT_IMAGES = "~/.local/share/libvirt/images" (expanded)

spawn_collect(argv, cb)        # async Gio.Subprocess; cb(ok, stdout, stderr) on main loop
spawn_fire(argv) -> str|None   # detached; None on success, else error message
bash_fire(script) -> str|None  # ["bash", "-lc", script] detached
gh(args, cb)                   # spawn_collect([GH_BIN, *args]); errors if GH_BIN None
gh_unavailable_reason() -> str|None   # None=usable; else human reason (not found /
                                      # no origin). Auth is checked async by callers.
human_size(nbytes) -> str      # "9.6 GB" style
iso_ts(s) -> float             # ISO8601 (Z ok) → epoch, 0.0 on parse failure
liveenv_rev() -> str           # sha256 content hash of live-env/src, first 16 hex —
                               # MUST byte-match build-iso-local.sh's LIVEENV_REV
                               # (find -type f, LC_ALL=C sort by path, sha256 of
                               # each file's content, sha256 of the concatenated
                               # "<hash>  <path>\n" lines, cut -c1-16)
list_isos() -> list[dict]      # newest-first over OUTPUT_DIR/*.iso and
                               # OUTPUT_DIR/ci-*/**.iso:
                               # {path, name, size, mtime, meta: dict|None,
                               #  ci_run: str|None}
read_iso_meta(path) -> dict|None   # loads f"{path}.meta.json"
dir_size(path) -> int          # os.walk sum, 0 if missing
vm_test_script(iso, name) -> str   # bash: recycle same-named session VM
                               # (destroy; undefine --nvram --remove-all-storage
                               # fallbacks) then `exec ujust margine-test-vm
                               # <iso> <name>` — v1's _launch_vm_with prelude
```

## Page protocol

```python
class BuildPage:               # same shape for CiPage, MaintPage
    def __init__(self, win): self.root = <Gtk.Widget>
    def refresh(self): ...     # idempotent; heavy work async (threads for
                               # os.walk sizing, spawn_collect for commands),
                               # results applied via GLib.idle_add
```

## Page 1 — Build (mib/build.py)

Port from v1: tag ComboRow, Fast (zstd-1) / Full (zstd-19) buttons, pkexec
build with the read_bytes_async streaming (keep the SIGPIPE note + stream ref),
cancel button, status spinner, log pane (this page owns the TextView and calls
`win.set_log_sink`).

**New — ISO inventory** (`Adw.PreferencesGroup "ISOs"`): one row per
`list_isos()` entry:
- title: filename; NO raw `&`/`<` in row titles (Pango markup — a raw `&`
  silently blanks the title)
- subtitle: `built <date> · <size> · zstd-<n> · base <tag>` from meta when
  present; CI ISOs (in `ci-<run>/`) show `CI run <id>`
- **freshness badge**: if `meta.liveenv_rev != core.liveenv_rev()` → suffix
  `Gtk.Label "STALE"` with css class `error` + tooltip "live-env sources
  changed after this build"; matching → `Gtk.Label "fresh"` css `success`.
  No meta → no badge.
- per-row suffix buttons: **Test in VM** (`bash_fire(vm_test_script(path,
  "margine-test-" + slug(name)))`), **Write to USB** (launch the Impression
  flatpak on the file: `spawn_fire(["flatpak", "run",
  "io.gitlab.adhami3310.Impression", path])`; toast a hint if flatpak/app
  missing), **Delete** (AlertDialog confirm → unlink iso + its .meta.json →
  refresh)
- group header suffix: refresh button.

**build-iso-local.sh** (same owner): after the ISO is produced, write
`"${ISO_PATH}.meta.json"`:
```json
{"built_at": "<UTC ISO8601>", "zstd_level": N, "base_image": "...",
 "base_digest": "<podman image inspect --format {{.Digest}} or unknown>",
 "liveenv_rev": "<the LIVEENV_REV already computed>", "builder": "local"}
```
(ownership handback already covers output/ via the EXIT trap; keep `set -euo`
safe — meta failures must not fail the build: guard with `|| true`.)

## Page 2 — CI (mib/ci.py)

Port from v1 unchanged in behavior: rebuild-base flow (two-stage: build.yml →
chained smoke-boot → ":stable promoted" notification), publish flow (tag from
Build page's combo — expose the selected tag via `win.current_tag()`;
attach-don't-double-publish; milestone notifications for iso/gate/publish),
download+test flow (artifact probe newest-first, size-based % progress,
offer-test dialog). All gh spawns via `core.gh` / `[GH_BIN, ...]` absolute.

**New — dashboard** (`Adw.PreferencesGroup "Status"`, filled by `refresh()`):
- **Base :stable** — newest successful `smoke-boot.yml` run (`gh run list
  --workflow smoke-boot.yml --status success --limit 1 --json
  databaseId,createdAt`) → "promoted <date>"
- **Last publish run** — newest `build-disk.yml` dispatch run: date + per-job
  verdicts (iso / gate / publish) via `gh run view --json status,conclusion,jobs`
- **Internet Archive link** — derive the identifier the workflow uses: READ
  `.github/workflows/build-disk.yml` (the `ia_upload` step) and reproduce its
  identifier/filename construction from the run date; render as a "Copy IA
  link" button (Gdk clipboard). If the pattern needs run data you can't
  reconstruct, fall back to a "Open run page" button (run URL) — do not guess.
- **Changelog button** — "Changes since last publish": headSha of the newest
  *successful* publish run (`gh run list ... --json headSha`), then local
  `git -C REPO_ROOT log --oneline <sha>..HEAD`; show in a scrollable
  Adw.Dialog (monospace, NOT selectable — see help.py rationale — with a Copy
  button for the whole text).

## Page 3 — Maintenance (mib/maint.py)

**Test VMs group**: rows from `virsh -c qemu:///session list --all --name`
filtered to `margine-test-*`:
- subtitle: state (`virsh domstate`) + qcow2 size (LIBVIRT_IMAGES/<name>.qcow2
  if present)
- per-row: **Console** (`spawn_fire(["virt-viewer", "--connect", QEMU_CONN,
  "--wait", name])`), **Delete** (confirm → destroy + undefine fallbacks →
  refresh)
- header suffix: **Clean all** (confirm; deletes every margine-test-* EXCEPT
  the template; checkbox in the dialog to include it). NEVER touch non-prefixed
  domains or qemu:///system.

**Disk usage group** (sizes computed in a thread, applied via idle_add):
- ISOs in output/ root — total + "Keep newest only" button
- CI downloads (output/ci-*/) — total + "Delete all"
- Titanoboa cache (REPO_ROOT/.cache) — total + "Clear"
- Rootful podman (margine-live/base images) — this needs root: row shows an
  "Inspect…" button that runs
  `pkexec sh -c 'podman images --format "{{.Repository}}:{{.Tag}} {{.Size}}" | grep -E "margine"'`
  and displays the result; plus "Remove local live image" →
  `pkexec podman rmi localhost/margine-live:local` (confirm first). Never
  auto-run pkexec on refresh — only on explicit click.
All destructive actions: Adw.AlertDialog confirm with DESTRUCTIVE appearance.

## mib/help.py — How-to-use, redesigned

v1 bug being fixed (do not regress): one giant `Gtk.Label(selectable=True)`
inside a ScrolledWindow — a selectable label grabs initial focus, which
**selects all text and scrolls to the bottom**. Also it's ugly.

New: `show_help(win)` presents an `Adw.Dialog` (~640×720) with
`Adw.ToolbarView` + ScrolledWindow + `Adw.Clamp` (max width ~560) containing a
vertical box of **sections**; each section is a heading label (css `title-4`,
xalign 0) + either body labels (wrap=True, xalign 0, css `body`, NOT
selectable) or `Adw.PreferencesGroup` with compact `Adw.ActionRow`s (icon +
title + subtitle) for the per-button explanations. Command examples: monospace
label + small copy button (`edit-copy-symbolic`) that sets the Gdk clipboard
(`Gdk.Display.get_default().get_clipboard().set(text)`) and toasts "Copied".
Content = v1 GUIDE's information reorganized per page (Build / CI /
Maintenance / Troubleshooting incl. the gh-unavailable hints). Nothing
selectable, nothing focused on open (set initial focus to the close button or
`set_focus(None)`).

## Cross-cutting guardrails

- Pango: no raw `&`, `<`, `>` in any Adw row title/subtitle or AlertDialog
  heading/body (escape or reword).
- Async only — never block the main loop (no subprocess.run in callbacks;
  startup-time one-shots like git-origin detection are exempt).
- Every button that disables itself must re-enable on EVERY exit path
  (including gh errors and JSON parse failures).
- virsh: only `-c qemu:///session`, only `margine-test-*` names.
- pkexec only for rootful podman; gh and virsh are user-level.
- GLib timers: return `GLib.SOURCE_REMOVE`/`SOURCE_CONTINUE` explicitly.
- Keep v1's inline comments that explain non-obvious constraints (SIGPIPE
  stream reference, cache-bust rationale, brew PATH story) — port them along.
