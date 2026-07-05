#!/usr/bin/python3
# Margine ISO Builder — a small GTK4 / libadwaita GUI to drive the LOCAL
# live-ISO build (live-env/build-iso-local.sh), the CI workflows, and the
# QEMU install test.
#
# DEVELOPER TOOL — it is NOT shipped in the Margine distro. It only wraps the
# same `just` recipes / script a developer would run by hand, so install-time
# and ISO bugs can be iterated without the ~40 min CI build + 8.5 GB download.
#
# Privileged steps (rootful podman) run via `pkexec` so you get a graphical
# polkit password prompt; build output streams into the Build page's log pane.
#
# Deps (present on a GNOME / Fedora-atomic desktop): python3-gobject, gtk4,
# libadwaita. No VTE needed.
#
# This is the thin v2 entry: it owns ONLY the app, the window shell (a
# ViewSwitcher header over a three-page ViewStack) and the small services the
# pages call back into (toast / notify / log sink / current tag). All feature
# logic lives in the mib/ package.
#
# Run:  just iso-gui    (or: python3 tools/iso-builder/margine-iso-builder.py)
import os

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Gtk, Adw, Gio, GLib  # noqa: E402

# The script's own directory is sys.path[0], so `mib` resolves whether the app
# is launched from the repo, a .desktop file, or the GNOME grid.
from mib import core, build, ci, maint  # noqa: E402
from mib import help as mib_help  # noqa: E402

# Frozen: a .desktop launcher and a Justfile recipe point at this id / path.
APP_ID = core.APP_ID


class BuilderWindow(Adw.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Margine ISO Builder")
        self.set_default_size(900, 640)

        # Log routing: the Build page owns the log TextView and registers a
        # sink via set_log_sink(). Anything append_log()'d before that sink
        # exists is buffered here and flushed when it registers — so a CI/maint
        # line logged before the Build page is built is never lost.
        self._log_sink = None
        self._log_buffer = []

        self.toasts = Adw.ToastOverlay()
        self.set_content(self.toasts)

        header = Adw.HeaderBar()

        self.stack = Adw.ViewStack(vexpand=True)

        # Pages receive `self` so they can toast/notify/log and read the
        # currently selected base tag. The Build page registers the log sink
        # during its construction (hence the buffer above).
        self.build_page = build.BuildPage(self)
        self.ci_page = ci.CiPage(self)
        self.maint_page = maint.MaintPage(self)

        self.stack.add_titled_with_icon(
            self.build_page.root, "build", "Build", "drive-optical-symbolic")
        self.stack.add_titled_with_icon(
            self.ci_page.root, "ci", "CI", "network-transmit-receive-symbolic")
        self.stack.add_titled_with_icon(
            self.maint_page.root, "maint", "Maintenance",
            "applications-system-symbolic")

        # Map each page's root widget back to its page so a switch can refresh
        # the incoming page. Connected AFTER the pages are added, so the initial
        # visible-child (Build, which already self-refreshes) fires no handler.
        self._pages = {
            self.build_page.root: self.build_page,
            self.ci_page.root: self.ci_page,
            self.maint_page.root: self.maint_page,
        }
        self.stack.connect("notify::visible-child", self._on_page_switch)

        # Adaptive title: a WIDE ViewSwitcher in the header on a wide window,
        # collapsing to a bottom ViewSwitcherBar under the breakpoint below.
        switcher = Adw.ViewSwitcher(stack=self.stack,
                                    policy=Adw.ViewSwitcherPolicy.WIDE)
        header.set_title_widget(switcher)

        # Header actions grouped on the trailing edge (open at the far corner,
        # help beside it) instead of an orphaned button left of the switcher.
        self.help_btn = Gtk.Button(icon_name="help-browser-symbolic",
                                   tooltip_text="How to use")
        self.help_btn.connect("clicked", lambda *_: mib_help.show_help(self))

        self.open_btn = Gtk.Button(icon_name="folder-open-symbolic",
                                   tooltip_text="Open the output folder")
        self.open_btn.connect("clicked", self.on_open_output)
        header.pack_end(self.open_btn)
        header.pack_end(self.help_btn)

        # Adw.ToolbarView hosts the header + stack (and the bottom switcher bar)
        # so the shell gets libadwaita's managed top/bottom-bar styling.
        tv = Adw.ToolbarView()
        tv.add_top_bar(header)
        tv.set_content(self.stack)

        switcher_bar = Adw.ViewSwitcherBar(stack=self.stack)
        tv.add_bottom_bar(switcher_bar)
        self.toasts.set_child(tv)

        # On a narrow window the header switcher hides and the bottom bar shows.
        bp = Adw.Breakpoint.new(Adw.BreakpointCondition.parse("max-width: 550sp"))
        bp.add_setter(switcher, "visible", False)
        bp.add_setter(switcher_bar, "reveal", True)
        self.add_breakpoint(bp)

    # -- page switching ---------------------------------------------------------
    def _on_page_switch(self, _stack, _param):
        page = self._pages.get(self.stack.get_visible_child())
        if page is not None:
            page.refresh()  # idempotent; each page does its heavy work async

    # -- services the pages call back into --------------------------------------
    def toast(self, text):
        self.toasts.add_toast(Adw.Toast.new(text))

    def notify(self, title, body="", tag=None, url=None, failure=False):
        """Toast + desktop notification (survives the window being on another
        workspace — CI jobs take up to an hour).

        tag:    stable id per FLOW ("ci-publish", "ci-base", …). GNOME
                REPLACES a notification re-sent with the same id, so one flow
                shows a single, self-updating card instead of piling three
                stale milestones in the tray (Daniel, 2026-07-05).
        url:    adds an "Open run" button instead of dumping a raw link in
                the body.
        failure: urgent priority, so reds stand out from milestones."""
        self.toast(title)
        n = Gio.Notification.new(title)
        if body:
            n.set_body(body)
        if url:
            n.add_button("Open run", Gio.Action.print_detailed_name(
                "app.open-url", GLib.Variant.new_string(url)))
        n.set_priority(Gio.NotificationPriority.URGENT if failure
                       else Gio.NotificationPriority.NORMAL)
        try:
            self.get_application().send_notification(tag, n)
        except Exception:
            pass

    def set_log_sink(self, cb):
        """The Build page registers its TextView appender here; flush anything
        buffered before it existed."""
        self._log_sink = cb
        pending, self._log_buffer = self._log_buffer, []
        for text in pending:
            cb(text)

    def append_log(self, text):
        if self._log_sink is not None:
            self._log_sink(text)
        else:
            self._log_buffer.append(text)

    def current_tag(self):
        """Delegates to the Build page's base-tag combo (the CI page publishes
        with it)."""
        return self.build_page.current_tag()

    # -- header actions ---------------------------------------------------------
    def on_open_output(self, _btn):
        os.makedirs(core.OUTPUT_DIR, exist_ok=True)
        Gio.AppInfo.launch_default_for_uri(f"file://{core.OUTPUT_DIR}", None)


class BuilderApp(Adw.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID,
                         flags=Gio.ApplicationFlags.DEFAULT_FLAGS)
        # Target of the notification "Open run" button (win.notify url=…).
        act = Gio.SimpleAction.new("open-url", GLib.VariantType.new("s"))
        act.connect("activate", self._on_open_url)
        self.add_action(act)

    @staticmethod
    def _on_open_url(_action, param):
        try:
            Gio.AppInfo.launch_default_for_uri(param.get_string(), None)
        except GLib.Error:
            pass

    def do_activate(self):
        win = self.props.active_window or BuilderWindow(self)
        win.present()
        # Smoke mode: build the whole widget tree, then quit — headless-ish
        # coverage that every page constructs without a runtime error. Exit 0
        # means the constructors survived. Kept short so CI does not linger.
        if os.environ.get("MIB_SMOKE"):
            GLib.timeout_add(1500, self._smoke_quit)

    def _smoke_quit(self):
        self.quit()
        return GLib.SOURCE_REMOVE


if __name__ == "__main__":
    import sys
    sys.exit(BuilderApp().run(sys.argv))
