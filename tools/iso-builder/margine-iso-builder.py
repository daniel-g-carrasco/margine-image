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
import datetime
import json
import os
import re
import shlex
import subprocess
import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Gtk, Adw, Gio, GLib  # noqa: E402

APP_ID = "place.empty.margine.IsoBuilder"
REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
BUILD_SCRIPT = os.path.join(REPO_ROOT, "live-env", "build-iso-local.sh")
OUTPUT_DIR = os.path.join(REPO_ROOT, "output")
BASE_TAGS = ["stable", "latest", "nvidia"]


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


GH_REPO = _detect_repo_slug()

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

<b>3 · CI (GitHub Actions)</b>
• <b>Rebuild base</b> — CI builds <tt>:candidate</tt>, QEMU smoke-boots it, and \
only if green promotes it to <tt>:stable</tt>. You get a notification when \
<tt>:stable</tt> is live — then <b>Fast test ISO</b> builds from the new base.
• <b>Publish ISO</b> — full CI ISO (zstd-19) → real-install gate → Internet \
Archive + site date bump. <b>The gate blocks publishing</b>: a stable ISO that \
fails a real install never reaches the public mirror.
• <b>Download &amp; test CI ISO</b> — fetches the newest CI ISO artifact \
(~9 GB) into <tt>output/ci-&lt;run&gt;/</tt> and boots it in the usual test VM. \
Use it to verify the EXACT bytes CI built before sharing a link.
• All three need the GitHub CLI (<tt>gh</tt>) authenticated. Progress arrives \
as desktop notifications — keep this window open while a CI job is monitored.

<b>Good to know</b>
• Needs ~30 GB free for the build scratch.
• The password is your own user password (polkit), not a separate one.
• <b>Cancel build</b> stops a build in progress.

<b>Same actions from a terminal</b>
<tt>just build-iso-fast</tt> · <tt>just test-install-vm</tt> · <tt>just build-iso</tt> · \
<tt>gh workflow run build-disk.yml -f image_tag=stable</tt>
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

        # --- CI (GitHub Actions) ---------------------------------------------
        # Three remote flows, all through the gh CLI (user-level, no pkexec):
        # rebuild the base image, publish the official ISO, download+test the
        # newest CI ISO. Each row runs its own poll loop and reports progress
        # via its subtitle + desktop notifications.
        ci = Adw.PreferencesGroup(
            title="CI (GitHub Actions)",
            description="Remote builds on the repo's Actions — needs the gh "
                        "CLI authenticated. Keep the window open to be notified.",
        )
        body.append(ci)

        def _ci_row(title, subtitle, btn_label, cb):
            row = Adw.ActionRow(title=title, subtitle=subtitle)
            btn = Gtk.Button(label=btn_label, valign=Gtk.Align.CENTER)
            btn.connect("clicked", cb)
            row.add_suffix(btn)
            ci.add(row)
            return row, btn

        self.base_row, self.base_btn = _ci_row(
            "Rebuild base image",
            "build :candidate → QEMU smoke-boot → promote :stable",
            "Rebuild", self.on_ci_base)
        self.pub_row, self.pub_btn = _ci_row(
            "Publish ISO via CI",
            "zstd-19 → install gate → Internet Archive + site bump",
            "Publish", self.on_ci_publish)
        self.dl_row, self.dl_btn = _ci_row(
            "Download & test newest CI ISO",
            "fetch the margine-live-iso artifact, boot it in the test VM",
            "Download", self.on_ci_download)

        self._ci_subtitles = {}   # row -> resting subtitle (restored when idle)
        for row in (self.base_row, self.pub_row, self.dl_row):
            self._ci_subtitles[row] = row.get_subtitle()
        if GH_REPO is None:
            self._ci_disable("no GitHub origin remote found")
        else:
            self._gh(["auth", "status"], self._on_gh_auth)

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

    # -- CI: shared plumbing ---------------------------------------------------
    def _ci_disable(self, why):
        for row, btn in ((self.base_row, self.base_btn),
                         (self.pub_row, self.pub_btn),
                         (self.dl_row, self.dl_btn)):
            btn.set_sensitive(False)
            row.set_subtitle(f"unavailable — {why}")

    def _on_gh_auth(self, ok, _out, _err):
        if not ok:
            self._ci_disable("gh CLI missing or not authenticated (gh auth login)")

    def _gh(self, args, cb):
        """Run `gh` asynchronously; cb(ok, stdout, stderr) on the main loop."""
        try:
            proc = Gio.Subprocess.new(
                ["gh", *args],
                Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE)
        except GLib.Error as e:
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

    def _notify(self, title, body=""):
        """Toast + desktop notification (survives the window being in another
        workspace — CI jobs take up to an hour)."""
        self._toast(title)
        n = Gio.Notification.new(title)
        if body:
            n.set_body(body)
        try:
            self.get_application().send_notification(None, n)
        except Exception:
            pass

    @staticmethod
    def _iso_ts(s):
        try:
            return datetime.datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
        except Exception:
            return 0.0

    @staticmethod
    def _job(data, prefix):
        for j in (data or {}).get("jobs", []):
            if j.get("name", "").startswith(prefix):
                return j.get("status"), (j.get("conclusion") or "")
        return None, ""

    def _find_dispatch_run(self, workflow, since_ts, cb, attempts=12,
                           event="workflow_dispatch"):
        """Poll `gh run list` until a run of `workflow` created around/after
        since_ts shows up (trigger → visible lag is seconds; workflow_run
        chaining can take a minute); cb(run_id | None)."""
        state = {"left": attempts}
        def ask():
            self._gh(["run", "list", "--repo", GH_REPO, "--workflow", workflow,
                      "--event", event, "--limit", "3",
                      "--json", "databaseId,createdAt"], got)
            return GLib.SOURCE_REMOVE
        def got(ok, out, _err):
            if ok and out.strip():
                try:
                    for r in json.loads(out):
                        if self._iso_ts(r.get("createdAt", "")) >= since_ts - 120:
                            cb(r["databaseId"])
                            return
                except ValueError:
                    pass
            state["left"] -= 1
            if state["left"] <= 0:
                cb(None)
                return
            GLib.timeout_add_seconds(10, ask)
        ask()

    def _watch_run(self, run_id, handler, interval=45):
        """Poll a run's status+jobs until handler(data) returns False.
        data is None on a transient gh error (handler usually keeps going)."""
        def ask():
            self._gh(["run", "view", str(run_id), "--repo", GH_REPO,
                      "--json", "status,conclusion,jobs,url"], got)
            return GLib.SOURCE_REMOVE
        def got(ok, out, _err):
            data = None
            if ok and out.strip():
                try:
                    data = json.loads(out)
                except ValueError:
                    data = None
            if handler(data):
                GLib.timeout_add_seconds(interval, ask)
        ask()

    # -- CI: rebuild base (:candidate → smoke-boot → :stable) ------------------
    def on_ci_base(self, _btn):
        dlg = Adw.AlertDialog.new(
            "Rebuild the base image in CI?",
            "Builds margine:candidate (~40-60 min), QEMU smoke-boots it and — "
            "only if green — promotes it to :stable. You'll be notified at "
            "each stage; Fast test ISO then builds from the new base.")
        dlg.add_response("cancel", "Cancel")
        dlg.add_response("go", "Rebuild")
        dlg.set_response_appearance("go", Adw.ResponseAppearance.SUGGESTED)
        def resp(_d, r):
            if r == "go":
                self._ci_base_start()
        dlg.connect("response", resp)
        dlg.present(self)

    def _ci_base_start(self):
        self.base_btn.set_sensitive(False)
        self.base_row.set_subtitle("triggering build.yml…")
        t0 = datetime.datetime.now(datetime.timezone.utc).timestamp()

        def triggered(ok, _out, err):
            if not ok:
                self._ci_base_done(f"trigger failed: {err.strip()[:120]}", notify=True)
                return
            self.base_row.set_subtitle("waiting for the run to appear…")
            self._find_dispatch_run("build.yml", t0, found)

        def found(run_id):
            if run_id is None:
                self._ci_base_done("run never appeared — check Actions", notify=True)
                return
            self._append(f"\n[CI] base rebuild run {run_id} — monitoring\n")
            self.base_row.set_subtitle(f"building :candidate… (run {run_id})")
            self._watch_run(run_id, tick)

        def tick(data):
            if data is None or data.get("status") != "completed":
                return True
            if data.get("conclusion") == "success":
                self.base_row.set_subtitle(":candidate built ✓ — waiting for smoke-boot…")
                self._notify("Base :candidate built",
                             "QEMU smoke-boot runs next; :stable follows if green.")
                now = datetime.datetime.now(datetime.timezone.utc).timestamp()
                self._find_dispatch_run("smoke-boot.yml", now - 60, sb_found,
                                        attempts=30, event="workflow_run")
            else:
                self._ci_base_done(
                    f"build failed ({data.get('conclusion')}) — :stable untouched",
                    notify=True)
            return False

        def sb_found(run_id):
            if run_id is None:
                self._ci_base_done("smoke-boot run not found — check Actions",
                                   notify=True)
                return
            self.base_row.set_subtitle(f"smoke-boot + promote… (run {run_id})")
            self._watch_run(run_id, sb_tick, interval=30)

        def sb_tick(data):
            if data is None or data.get("status") != "completed":
                return True
            if data.get("conclusion") == "success":
                self._ci_base_done(":stable promoted ✓")
                self._notify("Base :stable updated",
                             "Fast test ISO now builds from the new base.")
            else:
                self._ci_base_done("smoke-boot FAILED — :candidate NOT promoted",
                                   notify=True)
            return False

        self._gh(["workflow", "run", "build.yml", "--repo", GH_REPO,
                  "--ref", "main"], triggered)

    def _ci_base_done(self, text, notify=False):
        self.base_btn.set_sensitive(True)
        self.base_row.set_subtitle(text)
        if notify:
            self._notify("Base rebuild: " + text)

    # -- CI: publish the official ISO ------------------------------------------
    def on_ci_publish(self, _btn):
        tag = self._current_tag()
        if tag not in ("stable", "nvidia"):
            self._toast(f"Publishing needs tag stable or nvidia (got: {tag})")
            return
        extra = ("Also bumps the site's ISO date." if tag == "stable" else
                 "Publishes as margine-nvidia-<date>; the site date is untouched.")
        dlg = Adw.AlertDialog.new(
            f"Publish the margine:{tag} ISO publicly?",
            "CI builds the full zstd-19 ISO (~60-80 min), runs the real-install "
            f"gate, then uploads to Internet Archive. {extra} The gate blocks "
            "publishing if the install fails.")
        dlg.add_response("cancel", "Cancel")
        dlg.add_response("go", "Publish")
        dlg.set_response_appearance("go", Adw.ResponseAppearance.DESTRUCTIVE)
        def resp(_d, r):
            if r == "go":
                self._ci_publish_start(tag)
        dlg.connect("response", resp)
        dlg.present(self)

    def _ci_publish_start(self, tag):
        self.pub_btn.set_sensitive(False)
        self.pub_row.set_subtitle("checking for a publish already in progress…")

        def listed(ok, out, _err):
            active = None
            if ok and out.strip():
                try:
                    for r in json.loads(out):
                        if r.get("status") in ("queued", "in_progress"):
                            active = r["databaseId"]
                            break
                except ValueError:
                    pass
            if active is not None:
                # Don't double-publish: attach to the run that's already going.
                self._toast(f"A publish run is already in progress — monitoring {active}")
                self._ci_publish_watch(active)
                return
            t0 = datetime.datetime.now(datetime.timezone.utc).timestamp()

            def triggered(ok2, _o, err2):
                if not ok2:
                    self._ci_publish_done(f"trigger failed: {err2.strip()[:120]}",
                                          notify=True)
                    return
                self.pub_row.set_subtitle("waiting for the run to appear…")
                self._find_dispatch_run("build-disk.yml", t0, found)

            def found(run_id):
                if run_id is None:
                    self._ci_publish_done("run never appeared — check Actions",
                                          notify=True)
                    return
                self._ci_publish_watch(run_id)

            self._gh(["workflow", "run", "build-disk.yml", "--repo", GH_REPO,
                      "--ref", "main", "-f", f"image_tag={tag}"], triggered)

        self._gh(["run", "list", "--repo", GH_REPO, "--workflow", "build-disk.yml",
                  "--event", "workflow_dispatch", "--limit", "5",
                  "--json", "databaseId,status"], listed)

    def _ci_publish_watch(self, run_id):
        self._append(f"\n[CI] publish run {run_id} — monitoring\n")
        seen = set()

        def milestone(key, title, body=""):
            if key not in seen:
                seen.add(key)
                self._notify(title, body)

        def state(s, c):
            return c or s or "—"

        def tick(data):
            if data is None:
                return True
            iso_s, iso_c = self._job(data, "Build Live ISO")
            gate_s, gate_c = self._job(data, "Automated install gate")
            pub_s, pub_c = self._job(data, "Publish ISO")
            if iso_s == "completed":
                if iso_c == "success":
                    milestone("iso", "CI ISO built ✓",
                              "You can already download & test it (third CI row).")
                else:
                    milestone("isofail", "CI ISO build failed ✗")
            if gate_s == "completed" and gate_c:
                milestone("gate", "Install gate: " + (
                    "PASS ✓" if gate_c == "success"
                    else f"{gate_c.upper()} ✗ — publishing is blocked"))
            if pub_s == "completed" and pub_c == "success":
                milestone("pub", "ISO published to Internet Archive ✓")
            self.pub_row.set_subtitle(
                f"run {run_id} · iso: {state(iso_s, iso_c)} · "
                f"gate: {state(gate_s, gate_c)} · publish: {state(pub_s, pub_c)}")
            if data.get("status") != "completed":
                return True
            self._ci_publish_done(
                f"run {run_id} finished: {data.get('conclusion') or '?'}",
                notify=True, body=data.get("url") or "")
            return False

        self._watch_run(run_id, tick, interval=60)

    def _ci_publish_done(self, text, notify=False, body=""):
        self.pub_btn.set_sensitive(True)
        self.pub_row.set_subtitle(text)
        if notify:
            self._notify("Publish: " + text, body)

    # -- CI: download the newest CI ISO + test it -------------------------------
    def on_ci_download(self, _btn):
        self.dl_btn.set_sensitive(False)
        self.dl_row.set_subtitle("looking for the newest CI ISO artifact…")

        def listed(ok, out, _err):
            runs = []
            if ok and out.strip():
                try:
                    runs = json.loads(out)
                except ValueError:
                    runs = []
            self._ci_dl_probe(runs, 0)

        self._gh(["run", "list", "--repo", GH_REPO, "--workflow", "build-disk.yml",
                  "--limit", "15", "--json", "databaseId,createdAt"], listed)

    def _ci_dl_probe(self, runs, idx):
        """Newest-first: first run with a live margine-live-iso artifact wins
        (ISO-less qcow2-only runs and expired artifacts are skipped)."""
        if idx >= len(runs):
            self._ci_dl_done("no CI run with a live margine-live-iso artifact found")
            return
        rid = runs[idx]["databaseId"]

        def got(ok, out, _err):
            art = None
            if ok and out.strip():
                try:
                    for a in json.loads(out).get("artifacts", []):
                        if a.get("name") == "margine-live-iso" and not a.get("expired"):
                            art = a
                            break
                except ValueError:
                    pass
            if art is None:
                self._ci_dl_probe(runs, idx + 1)
                return
            self._ci_dl_confirm(rid, runs[idx].get("createdAt", "?"),
                                art.get("size_in_bytes") or 0)

        self._gh(["api", f"repos/{GH_REPO}/actions/runs/{rid}/artifacts"], got)

    def _ci_dl_confirm(self, rid, created, size):
        dlg = Adw.AlertDialog.new(
            "Download this CI ISO?",
            f"Run {rid} — built {created[:16].replace('T', ' ')} UTC — "
            f"{size / 1e9:.1f} GB.\nIt lands in output/ci-{rid}/ and can be "
            "booted in the test VM right after.")
        dlg.add_response("cancel", "Cancel")
        dlg.add_response("go", "Download")
        dlg.set_response_appearance("go", Adw.ResponseAppearance.SUGGESTED)
        def resp(_d, r):
            if r == "go":
                self._ci_dl_start(rid, size)
            else:
                self._ci_dl_done(None)
        dlg.connect("response", resp)
        dlg.present(self)

    def _ci_dl_start(self, rid, size):
        dest = os.path.join(OUTPUT_DIR, f"ci-{rid}")
        os.makedirs(dest, exist_ok=True)
        try:
            proc = Gio.Subprocess.new(
                ["gh", "run", "download", str(rid), "--repo", GH_REPO,
                 "-n", "margine-live-iso", "-D", dest],
                Gio.SubprocessFlags.STDERR_PIPE)
        except GLib.Error as e:
            self._ci_dl_done(f"gh failed to start: {e.message}")
            return
        self.dl_row.set_subtitle("downloading… 0%")
        state = {"live": True}

        def progress():
            if not state["live"]:
                return GLib.SOURCE_REMOVE
            have = 0
            for root_, _dirs, files in os.walk(dest):
                for f in files:
                    try:
                        have += os.path.getsize(os.path.join(root_, f))
                    except OSError:
                        pass
            pct = min(99, int(have * 100 / size)) if size else 0
            self.dl_row.set_subtitle(
                f"downloading… {have / 1e9:.1f} / {size / 1e9:.1f} GB ({pct}%)")
            return GLib.SOURCE_CONTINUE

        GLib.timeout_add_seconds(2, progress)

        def done(p, res):
            state["live"] = False
            try:
                p.wait_finish(res)
            except GLib.Error:
                pass
            if not p.get_successful():
                self._ci_dl_done("download failed — check gh auth / artifact retention")
                return
            isos = []
            for root_, _dirs, files in os.walk(dest):
                isos += [os.path.join(root_, f) for f in files if f.endswith(".iso")]
            if not isos:
                self._ci_dl_done("no .iso inside the artifact?")
                return
            self._ci_dl_done(f"downloaded: {os.path.basename(isos[0])}")
            self._notify("CI ISO downloaded", os.path.basename(isos[0]))
            self._ci_dl_offer_test(isos[0])

        proc.wait_async(None, done)

    def _ci_dl_offer_test(self, iso):
        dlg = Adw.AlertDialog.new(
            "Boot it in the test VM now?",
            f"{os.path.basename(iso)} — virt-manager VM with clipboard, Secure "
            "Boot (enrolled MS keys) and TPM 2.0. Any previous 'margine-test-ci' "
            "VM is recycled (domain + disk).")
        dlg.add_response("later", "Later")
        dlg.add_response("go", "Test now")
        dlg.set_response_appearance("go", Adw.ResponseAppearance.SUGGESTED)
        def resp(_d, r):
            if r == "go":
                self._launch_vm_with(iso, "margine-test-ci")
        dlg.connect("response", resp)
        dlg.present(self)

    def _launch_vm_with(self, iso, name):
        # Recycle inline: the SHIPPED margine-test-vm recipe errors on an
        # existing same-named domain until the next base update ships PR #239's
        # recycle — same prelude the dev Justfile's test-install-vm uses.
        script = (
            "CONN=qemu:///session\n"
            f"N={shlex.quote(name)}\n"
            'if virsh -c "$CONN" dominfo "$N" >/dev/null 2>&1; then\n'
            '  virsh -c "$CONN" destroy "$N" >/dev/null 2>&1 || true\n'
            '  virsh -c "$CONN" undefine "$N" --nvram --remove-all-storage >/dev/null 2>&1 \\\n'
            '    || virsh -c "$CONN" undefine "$N" --nvram >/dev/null 2>&1 \\\n'
            '    || virsh -c "$CONN" undefine "$N" >/dev/null 2>&1 || true\n'
            "fi\n"
            f"exec ujust margine-test-vm {shlex.quote(iso)} \"$N\"\n")
        self._append(f"\n$ ujust margine-test-vm {os.path.basename(iso)} {name}\n")
        try:
            Gio.Subprocess.new(["bash", "-lc", script], Gio.SubprocessFlags.NONE)
            self._toast("Launching the CI-ISO test VM (clipboard + SB + TPM2)")
        except GLib.Error as e:
            self._toast(f"Failed to launch the VM: {e.message}")

    def _ci_dl_done(self, text):
        self.dl_btn.set_sensitive(True)
        self.dl_row.set_subtitle(text or self._ci_subtitles[self.dl_row])

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
