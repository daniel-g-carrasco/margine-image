# mib/build.py — Build page: local live-ISO build + ISO inventory.
#
# Owns the log TextView: it registers itself as the window's log sink via
# win.set_log_sink(), so anything routed through win.append_log() (from any
# page) lands here.
import datetime
import os
import re
import shlex
import threading

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Gtk, Adw, Gio, GLib  # noqa: E402

from . import core  # noqa: E402

IMPRESSION_ID = "io.gitlab.adhami3310.Impression"


def _slug(name):
    """Filename → libvirt-safe domain-name fragment (lowercase [a-z0-9-])."""
    base = re.sub(r"\.iso$", "", name, flags=re.IGNORECASE)
    s = re.sub(r"[^a-z0-9]+", "-", base.lower()).strip("-")
    return (s or "iso")[:40].strip("-")


class BuildPage:
    def __init__(self, win):
        self.win = win
        self._proc = None    # the running Gio.Subprocess, if any
        self._stream = None  # its stdout pipe (kept referenced while reading)
        self._cancelling = False  # set only after the root-side TERM was sent
        self._iso_rows = []      # rows currently in the ISOs group
        self._refresh_gen = 0    # discards results of superseded refreshes

        self.root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12,
                            margin_top=12, margin_bottom=12,
                            margin_start=12, margin_end=12)

        # --- controls -------------------------------------------------------
        controls = Adw.PreferencesGroup(
            title="Local live-ISO build",
            description="Mirrors the CI live-ISO build — runs rootful "
                        "podman via pkexec. Output lands in output/.",
        )

        # No raw '<'/'&' in row titles/subtitles — they are Pango markup.
        self.tag_row = Adw.ComboRow(
            title="Base image tag",
            subtitle="Which published margine image the live ISO is built from")
        self.tag_row.set_model(Gtk.StringList.new(core.BASE_TAGS))
        self.tag_row.set_selected(0)  # stable
        controls.add(self.tag_row)

        # Plain labelled buttons (native dialog-action look) — the zstd
        # trade-off lives in the tooltips and the help dialog, not a card.
        self.fast_btn = Gtk.Button(label="Fast test ISO")
        self.fast_btn.set_tooltip_text("zstd-1 - quick, best for iterating")
        self.fast_btn.add_css_class("suggested-action")
        self.fast_btn.connect("clicked", lambda *_: self.start_build(
            level="1", label="fast test ISO (zstd-1)"))

        self.full_btn = Gtk.Button(label="Full ISO")
        self.full_btn.set_tooltip_text("zstd-19 - byte-identical to CI")
        self.full_btn.connect("clicked", lambda *_: self.start_build(
            level="19", label="full ISO (zstd-19)"))

        # btn_row sits OUTSIDE the PreferencesGroup, trailing-aligned.
        btn_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12,
                          homogeneous=False, halign=Gtk.Align.END)
        btn_row.append(self.fast_btn)
        btn_row.append(self.full_btn)

        # --- ISO inventory ----------------------------------------------------
        self.iso_group = Adw.PreferencesGroup(
            title="ISOs",
            description="Everything in output/ — local builds and CI downloads")
        refresh_btn = Gtk.Button(icon_name="view-refresh-symbolic",
                                 valign=Gtk.Align.CENTER)
        refresh_btn.add_css_class("flat")
        refresh_btn.set_tooltip_text("Refresh the ISO list")
        refresh_btn.connect("clicked", lambda *_: self.refresh())
        self.iso_group.set_header_suffix(refresh_btn)

        # Empty-state placeholder, toggled against the group in _apply_isos.
        self.iso_empty = Adw.StatusPage(
            icon_name="drive-optical-symbolic", title="No ISOs yet",
            description="Build one above, or download a CI ISO from the CI page")
        self.iso_empty.add_css_class("compact")
        self.iso_empty.set_visible(False)

        iso_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        iso_box.append(self.iso_group)
        iso_box.append(self.iso_empty)

        # Bounded height so a long inventory can't push the log pane off-screen.
        iso_scroll = Gtk.ScrolledWindow(propagate_natural_height=True,
                                        max_content_height=288,
                                        hscrollbar_policy=Gtk.PolicyType.NEVER)
        iso_scroll.set_child(iso_box)

        # Clamp the form column to the CI/Maintenance PreferencesPage width;
        # the log card below stays full-width.
        top = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        top.append(controls)
        top.append(btn_row)
        top.append(iso_scroll)
        top_clamp = Adw.Clamp(maximum_size=600)
        top_clamp.set_child(top)
        self.root.append(top_clamp)

        # --- status + cancel ------------------------------------------------
        # One action bar directly above the log: spinner, status, and the
        # build's stop control together instead of scattered rows.
        statusbar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        self.spinner = Gtk.Spinner()
        statusbar.append(self.spinner)
        self.status = Gtk.Label(xalign=0, label="Idle", hexpand=True)
        self.status.add_css_class("dim-label")
        statusbar.append(self.status)
        self.cancel_btn = Gtk.Button(label="Cancel build", valign=Gtk.Align.CENTER)
        self.cancel_btn.add_css_class("destructive-action")
        self.cancel_btn.set_sensitive(False)
        self.cancel_btn.connect("clicked", self.on_cancel)
        statusbar.append(self.cancel_btn)
        self.root.append(statusbar)

        # --- log --------------------------------------------------------------
        scroller = Gtk.ScrolledWindow(vexpand=True)
        scroller.add_css_class("card")
        scroller.set_overflow(Gtk.Overflow.HIDDEN)  # clip the TextView to .card radius
        self.log_view = Gtk.TextView(editable=False, cursor_visible=False,
                                     monospace=True,
                                     wrap_mode=Gtk.WrapMode.WORD_CHAR,
                                     top_margin=8, bottom_margin=8,
                                     left_margin=8, right_margin=8)
        self.log_buf = self.log_view.get_buffer()
        scroller.set_child(self.log_view)
        self.root.append(scroller)

        # Register the sink AFTER the buffer exists — the window may flush
        # lines it buffered before this page was constructed.
        win.set_log_sink(self._append)
        self._append(f"Repo: {core.REPO_ROOT}\n"
                     "Ready. Pick a base tag and start a build.\n")
        self.refresh()

    # -- page protocol ---------------------------------------------------------
    def refresh(self):
        """Rescan output/ into the ISOs group. Idempotent; the scan (content
        hash of live-env/src + stat/meta reads) runs in a thread."""
        self._refresh_gen += 1
        gen = self._refresh_gen

        def work():
            try:
                rev = core.liveenv_rev()
            except Exception:
                rev = ""
            try:
                isos = core.list_isos()
            except Exception:
                isos = []
            GLib.idle_add(self._apply_isos, gen, isos, rev)

        threading.Thread(target=work, daemon=True).start()

    def current_tag(self):
        """Selected base tag — win.current_tag() delegates here (the CI page
        publishes with it)."""
        return core.BASE_TAGS[self.tag_row.get_selected()]

    # -- helpers -----------------------------------------------------------------
    def _append(self, text):
        end = self.log_buf.get_end_iter()
        self.log_buf.insert(end, text)
        # auto-scroll to the bottom
        mark = self.log_buf.create_mark(None, self.log_buf.get_end_iter(), False)
        self.log_view.scroll_mark_onscreen(mark)
        self.log_buf.delete_mark(mark)

    def _set_running(self, running, status_text):
        for b in (self.fast_btn, self.full_btn, self.tag_row):
            b.set_sensitive(not running)
        self.cancel_btn.set_sensitive(running)
        self.cancel_btn.set_label("Cancel build")  # reset from "Cancelling…"
        self.status.set_label(status_text)
        if running:
            self.spinner.start()
        else:
            self.spinner.stop()

    def _newest_iso(self):
        try:
            isos = [os.path.join(core.OUTPUT_DIR, f)
                    for f in os.listdir(core.OUTPUT_DIR) if f.endswith(".iso")]
        except FileNotFoundError:
            return None
        return max(isos, key=os.path.getmtime) if isos else None

    # -- build -------------------------------------------------------------------
    def start_build(self, level, label):
        if self._proc is not None:
            return
        if not os.path.exists(core.BUILD_SCRIPT):
            self.win.toast("build-iso-local.sh not found")
            return
        tag = self.current_tag()
        argv = ["pkexec", core.BUILD_SCRIPT, tag, level]
        self._append(f"\n$ {' '.join(shlex.quote(a) for a in argv)}\n")
        self._set_running(True, f"Building {label} from margine:{tag}…")
        try:
            launcher = Gio.SubprocessLauncher.new(
                Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_MERGE)
            launcher.setenv("NO_COLOR", "1", True)
            self._proc = launcher.spawnv(argv)
        except GLib.Error as e:
            self._append(f"Failed to start: {e.message}\n")
            self._set_running(False, "Failed to start")
            self._proc = None
            return
        # Keep a reference to the pipe: if it were GC'd the FD would close and
        # the still-writing script would die of SIGPIPE (exit 141).
        self._stream = self._proc.get_stdout_pipe()
        self._read_next(self._stream)
        self._proc.wait_async(None, self._on_build_done)

    def _read_next(self, stream):
        # read_bytes (not read_line): a true EOF is a zero-length GBytes, while
        # an empty output LINE still carries its '\n' — so unlike read_line
        # (where both EOF and an empty line return b''), this never stops early.
        stream.read_bytes_async(8192, GLib.PRIORITY_DEFAULT, None,
                                self._on_chunk, None)

    def _on_chunk(self, stream, result, _user):
        try:
            chunk = stream.read_bytes_finish(result)
        except GLib.Error:
            return
        if chunk is None or chunk.get_size() == 0:
            return  # true EOF
        self._append(chunk.get_data().decode("utf-8", "replace"))
        self._read_next(stream)

    def _on_build_done(self, proc, result):
        try:
            proc.wait_finish(result)
            ok = proc.get_successful()
            # A cancelled build dies of SIGTERM: get_exit_status() is only
            # valid for a normal exit, so branch on get_if_exited().
            code = (proc.get_exit_status() if proc.get_if_exited()
                    else -(proc.get_term_sig() or 0))
        except GLib.Error as e:
            ok, code = False, -1
            self._append(f"\n[error waiting for process: {e.message}]\n")
        self._proc = None
        self._stream = None
        if self._cancelling:
            self._cancelling = False
            self._set_running(False, "Cancelled")
            self._append("\n✋ Build cancelled — partial artifacts stay in .cache/ "
                         "(ownership handed back by the script's EXIT trap).\n")
            return
        if ok:
            self._set_running(False, "Done")
            iso = self._newest_iso()
            self._append(f"\n✓ Build finished. ISO: {iso or '(see output/)'}\n")
            # Adw.Toast text is Pango markup — escape the filename, same '&'
            # hazard as the escaped row titles below.
            self.win.toast(GLib.markup_escape_text(
                "ISO ready" + (f": {os.path.basename(iso)}" if iso else "")))
            self.refresh()  # new ISO + its meta sidecar → inventory row/badge
        else:
            # pkexec exits 126/127 when polkit auth is cancelled or fails
            hint = " (authentication cancelled or failed?)" if code in (126, 127) else ""
            self._set_running(False, f"Failed (exit {code}){hint}")
            self._append(f"\n✗ Build failed (exit {code}){hint}\n")

    def on_cancel(self, _btn):
        if self._proc is None or self._cancelling:
            return
        # The build runs as ROOT (pkexec) and the heavy work — mksquashfs /
        # xorriso — runs inside a Titanoboa podman container that conmon keeps
        # ALIVE independently of the host process tree (Daniel, 2026-07-04:
        # force_exit was EPERM-ignored; then the host tree died but xorriso in
        # the container marched on). So cancel does BOTH, root-side via pkexec:
        #   1. podman kill the worker container — Titanoboa runs it unnamed
        #      (`podman run --rm -i … fedora:latest /src/build_iso.sh`), so
        #      match it by its unique command /src/build_iso.sh.
        #   2. recursive children-first TERM of the pkexec tree (build-iso-
        #      local.sh, sudo podman build/pull), whose EXIT trap hands
        #      .cache//output ownership back. Then a hard sweep by name.
        # The build stays "running" in the UI until the process actually dies
        # (_on_build_done) — no premature "Cancelled" with work still going.
        pid = int(self._proc.get_identifier())
        script = (
            'for cid in $(podman ps -q 2>/dev/null); do '
            'case "$(podman inspect --format "{{.Config.Cmd}}" "$cid" 2>/dev/null)" '
            'in *build_iso.sh*) podman kill "$cid" 2>/dev/null || true;; esac; done; '
            'k(){ for c in $(pgrep -P "$1" 2>/dev/null); do k "$c"; done; '
            'kill -TERM "$1" 2>/dev/null || true; }; k %d; '
            'sleep 2; pkill -KILL -f build-iso-local.sh 2>/dev/null || true' % pid
        )
        self.cancel_btn.set_sensitive(False)     # no double-click while auth pends
        self.cancel_btn.set_label("Cancelling…")
        self._append("\n[stopping the rootful build + its container — "
                     "authenticate in the polkit dialog…]\n")

        def sent(ok, _out, err):
            if ok:
                # Mark, but DON'T reset the UI here: _on_build_done fires when
                # self._proc (pkexec) actually exits and does the reset — the
                # real-completion check you asked for.
                self._cancelling = True
                self._append("[terminate + container kill sent — waiting for "
                             "the build to exit]\n")
            else:
                last = err.strip().splitlines()[-1] if err.strip() else "auth cancelled"
                self._append(f"[cancel aborted: {last} — build still running]\n")
                self.cancel_btn.set_label("Cancel build")
                self.cancel_btn.set_sensitive(True)   # build lives → let them retry

        core.spawn_collect(["pkexec", "bash", "-c", script], sent)

    # -- ISO inventory -------------------------------------------------------------
    def _apply_isos(self, gen, isos, rev):
        if gen != self._refresh_gen:
            return GLib.SOURCE_REMOVE
        for row in self._iso_rows:
            self.iso_group.remove(row)
        self._iso_rows = []
        if not isos:
            self.iso_group.set_visible(False)
            self.iso_empty.set_visible(True)
            return GLib.SOURCE_REMOVE
        self.iso_group.set_visible(True)
        self.iso_empty.set_visible(False)
        for entry in isos:
            row = self._iso_row(entry, rev)
            self.iso_group.add(row)
            self._iso_rows.append(row)
        return GLib.SOURCE_REMOVE

    def _iso_row(self, entry, rev):
        # NB: row titles are Pango markup — a raw '&' in a filename would
        # silently blank the whole title, so escape.
        row = Adw.ActionRow(title=GLib.markup_escape_text(entry["name"]))
        row.set_subtitle(self._iso_subtitle(entry))

        meta = entry.get("meta")
        if meta is not None:
            # Freshness = the sidecar's liveenv_rev still matches the current
            # content hash of live-env/src. No sidecar → no badge (unknown).
            fresh = meta.get("liveenv_rev") == rev
            badge = Gtk.Label(label="Fresh" if fresh else "Stale",
                              valign=Gtk.Align.CENTER)
            badge.add_css_class("caption")
            badge.add_css_class("success" if fresh else "error")
            if not fresh:
                badge.set_tooltip_text("live-env sources changed after this build")
            else:
                badge.set_tooltip_text("live-env sources unchanged since this build")
            row.add_suffix(badge)

        # LABELED buttons, not bare icons: three mute glyphs in a row left
        # Daniel hunting for "which one boots the VM?" (2026-07-04). The
        # primary action carries icon+text; USB keeps a text label; only
        # Delete stays icon-only (trash is unambiguous and destructive
        # actions shouldn't invite casual clicks).
        def add_btn(cb, label=None, icon=None, tip=None, css="flat"):
            if label and icon:
                inner = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
                inner.append(Gtk.Image.new_from_icon_name(icon))
                inner.append(Gtk.Label(label=label))
                b = Gtk.Button(child=inner, valign=Gtk.Align.CENTER)
            elif label:
                b = Gtk.Button(label=label, valign=Gtk.Align.CENTER)
            else:
                b = Gtk.Button(icon_name=icon, valign=Gtk.Align.CENTER)
            if css:
                b.add_css_class(css)
            if tip:
                b.set_tooltip_text(tip)
            b.connect("clicked", lambda *_: cb(entry))
            row.add_suffix(b)

        add_btn(self._iso_test_vm, label="Test in VM", icon="computer-symbolic",
                tip="Boot this ISO in the virt-manager test VM "
                    "(Secure Boot + TPM 2.0 + clipboard)", css=None)
        add_btn(self._iso_write_usb, label="USB",
                tip="Write to a USB stick (opens Impression)")
        add_btn(self._iso_delete, icon="user-trash-symbolic",
                tip="Delete this ISO")
        return row

    def _iso_subtitle(self, entry):
        parts = []
        meta = entry.get("meta")
        if meta is not None:
            built = str(meta.get("built_at", ""))[:16].replace("T", " ")
            if built:
                parts.append(f"built {built}")
            parts.append(core.human_size(entry["size"]))
            z = meta.get("zstd_level")
            if z is not None:
                parts.append(f"zstd-{z}")
            base = str(meta.get("base_image", ""))
            if base:
                parts.append("base " + base.rsplit(":", 1)[-1])
        else:
            built = datetime.datetime.fromtimestamp(
                entry["mtime"]).strftime("%Y-%m-%d %H:%M")
            parts.append(f"built {built}")
            parts.append(core.human_size(entry["size"]))
        if entry.get("ci_run"):
            parts.append(f"CI run {entry['ci_run']}")
        # subtitles are Pango markup too — escape, same '&' hazard as titles
        return GLib.markup_escape_text(" · ".join(parts))

    def _iso_test_vm(self, entry):
        # Preflight: the path can go stale between the scan and the click
        # (2026-07-07: the old recycle deleted the ISO out from under this
        # handler and it still toasted success). Fail loudly, then rescan.
        if not os.path.exists(entry["path"]):
            self.win.toast("That ISO no longer exists on disk — rescanning")
            self.refresh()
            return
        name = core.VM_PREFIX + _slug(entry["name"])
        self._append(f"\n$ ujust margine-test-vm {entry['name']} {name}\n")

        def done(ok, out, err):
            if ok:
                return
            tail = [ln for ln in ((out or "") + "\n" + (err or "")).splitlines()
                    if ln.strip()]
            for ln in tail[-8:]:
                self._append(ln + "\n")
            msg = tail[-1] if tail else "unknown error"
            self.win.toast(GLib.markup_escape_text(f"VM launch failed: {msg}"))

        core.bash_collect(core.vm_test_script(entry["path"], name), done)
        self.win.toast("Launching the test VM (clipboard + Secure Boot + TPM 2.0)")

    def _iso_write_usb(self, entry):
        path = entry["path"]

        def checked(ok, _out, _err):
            if not ok:
                # covers both a missing flatpak binary and a missing app
                self.win.toast("Impression not installed — flatpak install "
                               "flathub " + IMPRESSION_ID)
                return
            err = core.spawn_fire(["flatpak", "run", IMPRESSION_ID, path])
            if err:
                self.win.toast(GLib.markup_escape_text(
                    f"Failed to launch Impression: {err}"))
            else:
                self.win.toast("Opening in Impression — pick the USB stick there")

        core.spawn_collect(["flatpak", "info", IMPRESSION_ID], checked)

    def _iso_delete(self, entry):
        dlg = Adw.AlertDialog.new(
            "Delete this ISO?",
            f"{entry['name']} ({core.human_size(entry['size'])}) and its "
            ".meta.json sidecar will be removed.")
        dlg.add_response("cancel", "Cancel")
        dlg.add_response("del", "Delete")
        dlg.set_response_appearance("del", Adw.ResponseAppearance.DESTRUCTIVE)

        def resp(_d, r):
            if r != "del":
                return
            try:
                os.unlink(entry["path"])
            except OSError as e:
                self.win.toast(GLib.markup_escape_text(
                    f"Delete failed: {e.strerror or e}"))
                return
            try:
                os.unlink(entry["path"] + ".meta.json")
            except OSError:
                pass
            self.win.toast(GLib.markup_escape_text(f"Deleted {entry['name']}"))
            self.refresh()

        dlg.connect("response", resp)
        dlg.present(self.win)
