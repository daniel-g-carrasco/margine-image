#!/usr/bin/python3
# Margine ISO Builder — a small GTK4 / libadwaita GUI to drive the LOCAL
# live-ISO build (live-env/build-iso-local.sh) and the QEMU install test.
#
# DEVELOPER TOOL — it is NOT shipped in the Margine distro. It only wraps the
# same `just` recipes / script a developer would run by hand, so install-time
# and ISO bugs can be iterated without the ~40 min CI build + 8.5 GB download.
#
# Privileged steps (rootful podman) run via `pkexec` so you get a graphical
# polkit password prompt; build output streams into the log pane. The "Test
# install in VM" action runs `just test-install-vm` as your user (QEMU/KVM).
#
# Deps (present on a GNOME / Fedora-atomic desktop): python3-gobject, gtk4,
# libadwaita. No VTE needed.
#
# Run:  just iso-gui    (or: python3 tools/iso-builder/margine-iso-builder.py)
import os
import shlex
import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Gtk, Adw, Gio, GLib  # noqa: E402

APP_ID = "place.empty.margine.IsoBuilder"
REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
BUILD_SCRIPT = os.path.join(REPO_ROOT, "live-env", "build-iso-local.sh")
OUTPUT_DIR = os.path.join(REPO_ROOT, "output")
BASE_TAGS = ["stable", "latest", "nvidia"]

GUIDE = """<b>Margine ISO Builder</b> builds the Margine live ISO locally, so you \
can test install-time and ISO bugs without the ~40 min CI build or an 8.5 GB \
download. It is a developer tool — nothing here ships in the distro.

<b>1 · Build an ISO</b>
• Pick the <b>base image tag</b> (leave <tt>stable</tt> unless you know otherwise).
• <b>Fast test ISO</b> — zstd-1, quick; best for iterating on bugs.
• <b>Full ISO</b> — zstd-19, byte-identical to what CI ships.
• A graphical password prompt appears — the build needs rootful podman.
• Watch the log. When it shows <b>Done ✓</b>, the ISO is in <tt>output/</tt> \
(open it with the folder button, top-right). The first build is slower (it pulls \
the base image and clones Titanoboa); later builds are cached.

<b>2 · Test the install</b>
• Click <b>Test install in VM</b> — QEMU boots the newest ISO with a blank disk.
• In the installer pick the <b>DEFAULT partitioning</b> — that creates the \
dedicated /var the shipped ISO uses (the layout where the Flatpak bake matters).
• After install → reboot → log in → open a terminal:
   <tt>flatpak --system remotes</tt>  — must list <tt>flathub</tt>, no opendir error
   <tt>flatpak --system list --app | wc -l</tt>  — ~37 baked apps right away

<b>Good to know</b>
• Needs ~30 GB free for the build scratch.
• The password is your own user password (polkit), not a separate one.
• <b>Cancel build</b> stops a build in progress.

<b>Same actions from a terminal</b>
<tt>just build-iso-fast</tt> · <tt>just test-install-vm</tt> · <tt>just build-iso</tt>
"""


class BuilderWindow(Adw.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Margine ISO Builder")
        self.set_default_size(900, 620)
        self._proc = None    # the running Gio.Subprocess, if any
        self._stream = None  # its stdout pipe (kept referenced while reading)

        self.toasts = Adw.ToastOverlay()
        self.set_content(self.toasts)

        root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.toasts.set_child(root)

        header = Adw.HeaderBar()
        root.append(header)
        self.help_btn = Gtk.Button(icon_name="help-about-symbolic")
        self.help_btn.set_tooltip_text("How to use this")
        self.help_btn.connect("clicked", self.on_help)
        header.pack_start(self.help_btn)
        self.open_btn = Gtk.Button(icon_name="folder-open-symbolic")
        self.open_btn.set_tooltip_text("Open the output folder")
        self.open_btn.connect("clicked", self.on_open_output)
        header.pack_end(self.open_btn)

        body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12,
                       margin_top=12, margin_bottom=12, margin_start=12, margin_end=12)
        body.set_vexpand(True)
        root.append(body)

        # --- controls -------------------------------------------------------
        controls = Adw.PreferencesGroup(
            title="Local live-ISO build",
            description="Mirrors the CI build_iso_titanoboa job — runs rootful "
                        "podman via pkexec. Output lands in ./output/.",
        )
        body.append(controls)

        self.tag_row = Adw.ComboRow(title="Base image tag",
                                    subtitle="Published margine:<tag> to build the live env from")
        self.tag_row.set_model(Gtk.StringList.new(BASE_TAGS))
        self.tag_row.set_selected(0)  # stable
        controls.add(self.tag_row)

        btn_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8, homogeneous=True,
                          margin_top=6)
        controls.add(btn_row)

        self.fast_btn = Gtk.Button()
        self.fast_btn.set_child(self._btn_content("media-playback-start-symbolic",
                                                  "Fast test ISO", "zstd-1, quick"))
        self.fast_btn.add_css_class("suggested-action")
        self.fast_btn.connect("clicked", lambda *_: self.start_build(level="1",
                                                                     label="fast test ISO (zstd-1)"))
        btn_row.append(self.fast_btn)

        self.full_btn = Gtk.Button()
        self.full_btn.set_child(self._btn_content("drive-optical-symbolic",
                                                  "Full ISO", "zstd-19, CI-identical"))
        self.full_btn.connect("clicked", lambda *_: self.start_build(level="19",
                                                                     label="full ISO (zstd-19)"))
        btn_row.append(self.full_btn)

        self.vm_btn = Gtk.Button()
        self.vm_btn.set_child(self._btn_content("computer-symbolic",
                                                "Test install in VM", "boot newest ISO"))
        self.vm_btn.connect("clicked", self.on_test_vm)
        btn_row.append(self.vm_btn)

        # --- status ---------------------------------------------------------
        status_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        self.spinner = Gtk.Spinner()
        status_box.append(self.spinner)
        self.status = Gtk.Label(xalign=0, label="Idle.")
        self.status.add_css_class("dim-label")
        status_box.append(self.status)
        body.append(status_box)

        # --- log ------------------------------------------------------------
        scroller = Gtk.ScrolledWindow(vexpand=True)
        scroller.add_css_class("card")
        self.log_view = Gtk.TextView(editable=False, cursor_visible=False, monospace=True,
                                     wrap_mode=Gtk.WrapMode.WORD_CHAR,
                                     top_margin=8, bottom_margin=8, left_margin=8, right_margin=8)
        self.log_buf = self.log_view.get_buffer()
        scroller.set_child(self.log_view)
        body.append(scroller)

        self.cancel_btn = Gtk.Button(label="Cancel build")
        self.cancel_btn.add_css_class("destructive-action")
        self.cancel_btn.set_halign(Gtk.Align.END)
        self.cancel_btn.set_sensitive(False)
        self.cancel_btn.connect("clicked", self.on_cancel)
        body.append(self.cancel_btn)

        self._append(f"Repo: {REPO_ROOT}\nReady. Pick a base tag and start a build.\n")

    # -- helpers -------------------------------------------------------------
    def _btn_content(self, icon, title, subtitle):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2,
                      margin_top=6, margin_bottom=6)
        box.append(Gtk.Image.new_from_icon_name(icon))
        lbl = Gtk.Label(label=title)
        lbl.add_css_class("heading")
        box.append(lbl)
        sub = Gtk.Label(label=subtitle)
        sub.add_css_class("caption")
        sub.add_css_class("dim-label")
        box.append(sub)
        return box

    def _append(self, text):
        end = self.log_buf.get_end_iter()
        self.log_buf.insert(end, text)
        # auto-scroll to the bottom
        mark = self.log_buf.create_mark(None, self.log_buf.get_end_iter(), False)
        self.log_view.scroll_mark_onscreen(mark)
        self.log_buf.delete_mark(mark)

    def _set_running(self, running, status_text):
        for b in (self.fast_btn, self.full_btn, self.vm_btn, self.tag_row):
            b.set_sensitive(not running)
        self.cancel_btn.set_sensitive(running)
        self.status.set_label(status_text)
        if running:
            self.spinner.start()
        else:
            self.spinner.stop()

    def _current_tag(self):
        return BASE_TAGS[self.tag_row.get_selected()]

    # -- build ---------------------------------------------------------------
    def start_build(self, level, label):
        if self._proc is not None:
            return
        if not os.path.exists(BUILD_SCRIPT):
            self._toast("build-iso-local.sh not found")
            return
        tag = self._current_tag()
        argv = ["pkexec", BUILD_SCRIPT, tag, level]
        self._append(f"\n$ {' '.join(shlex.quote(a) for a in argv)}\n")
        self._set_running(True, f"Building {label} from margine:{tag}…")
        try:
            launcher = Gio.SubprocessLauncher.new(
                Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_MERGE)
            launcher.setenv("NO_COLOR", "1", True)
            self._proc = launcher.spawnv(argv)
        except GLib.Error as e:
            self._append(f"Failed to start: {e.message}\n")
            self._set_running(False, "Failed to start.")
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
        stream.read_bytes_async(8192, GLib.PRIORITY_DEFAULT, None, self._on_chunk, None)

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
            code = proc.get_exit_status()
        except GLib.Error as e:
            ok, code = False, -1
            self._append(f"\n[error waiting for process: {e.message}]\n")
        self._proc = None
        self._stream = None
        if ok:
            self._set_running(False, "Done ✓")
            iso = self._newest_iso()
            self._append(f"\n✓ Build finished. ISO: {iso or '(see output/)'}\n")
            self._toast("ISO ready" + (f": {os.path.basename(iso)}" if iso else ""))
        else:
            # pkexec exits 126/127 when polkit auth is cancelled or fails
            hint = " (authentication cancelled or failed?)" if code in (126, 127) else ""
            self._set_running(False, f"Failed ✗ (exit {code}){hint}")
            self._append(f"\n✗ Build failed (exit {code}){hint}\n")

    def on_cancel(self, _btn):
        if self._proc is not None:
            self._append("\n[cancelling…]\n")
            self._proc.force_exit()

    # -- VM test -------------------------------------------------------------
    def on_test_vm(self, _btn):
        iso = self._newest_iso()
        if not iso:
            self._toast("No ISO in output/ — build one first")
            return
        argv = ["bash", "-lc",
                f"cd {shlex.quote(REPO_ROOT)} && just test-install-vm"]
        self._append(f"\n$ just test-install-vm  (newest: {os.path.basename(iso)})\n")
        try:
            Gio.Subprocess.new(argv, Gio.SubprocessFlags.NONE)
            self._toast("Launching virt-manager VM (clipboard + Secure Boot + TPM2)")
        except GLib.Error as e:
            self._append(f"Failed to launch VM: {e.message}\n")
            self._toast("Failed to launch the test VM (is ujust/virt-install present?)")

    # -- misc ----------------------------------------------------------------
    def _newest_iso(self):
        try:
            isos = [os.path.join(OUTPUT_DIR, f) for f in os.listdir(OUTPUT_DIR) if f.endswith(".iso")]
        except FileNotFoundError:
            return None
        return max(isos, key=os.path.getmtime) if isos else None

    def on_open_output(self, _btn):
        os.makedirs(OUTPUT_DIR, exist_ok=True)
        Gio.AppInfo.launch_default_for_uri(f"file://{OUTPUT_DIR}", None)

    def on_help(self, _btn):
        dlg = Adw.Dialog()
        dlg.set_title("How to use")
        dlg.set_content_width(580)
        dlg.set_content_height(660)
        view = Adw.ToolbarView()
        view.add_top_bar(Adw.HeaderBar())
        scroller = Gtk.ScrolledWindow(vexpand=True)
        label = Gtk.Label(wrap=True, xalign=0, yalign=0, selectable=True,
                          margin_top=12, margin_bottom=16, margin_start=16, margin_end=16)
        label.set_markup(GUIDE)
        scroller.set_child(label)
        view.set_content(scroller)
        dlg.set_child(view)
        dlg.present(self)

    def _toast(self, text):
        self.toasts.add_toast(Adw.Toast.new(text))


class BuilderApp(Adw.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.DEFAULT_FLAGS)

    def do_activate(self):
        win = self.props.active_window or BuilderWindow(self)
        win.present()


if __name__ == "__main__":
    import sys
    sys.exit(BuilderApp().run(sys.argv))
