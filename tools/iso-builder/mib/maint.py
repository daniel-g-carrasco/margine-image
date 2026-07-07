# mib/maint.py — page 3: test-VM cleanup + disk usage/reclaim.
#
# Guardrails (frozen in DESIGN.md): virsh runs ONLY against qemu:///session
# and ONLY on margine-test-* domain names — other domains and qemu:///system
# are never touched. pkexec is used ONLY for rootful podman and ONLY on an
# explicit click (never on refresh). Sizing os.walk work runs in a thread and
# lands on the main loop via GLib.idle_add. Every destructive action goes
# through an Adw.AlertDialog with a DESTRUCTIVE response.
import os
import shlex
import shutil
import threading

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Gtk, Adw, GLib  # noqa: E402

from . import core  # noqa: E402

# Rootful podman needs root even to LIST its store, so this runs behind an
# explicit pkexec click (graphical polkit prompt) — never automatically.
_PODMAN_INSPECT = ('podman images --format "{{.Repository}}:{{.Tag}} {{.Size}}"'
                   ' | grep -E "margine"')
_LIVE_IMAGE = "localhost/margine-live:local"


class MaintPage:
    def __init__(self, win):
        self.win = win
        self._vm_names = []      # last successful listing (margine-test-* only)
        self._vm_rows = []       # rows currently attached to the VM group
        self._vm_gen = 0         # bumped per listing; stale domstate callbacks drop
        self._vms_busy = False
        self._sizes_busy = False

        self.root = Adw.PreferencesPage()

        # --- test VMs --------------------------------------------------------
        self.vm_group = Adw.PreferencesGroup(
            title="Test VMs",
            description="Session-libvirt domains (margine-test-*) created by "
                        "the Test-in-VM buttons — they are never auto-deleted.")
        self.clean_btn = Gtk.Button(label="Clean all", valign=Gtk.Align.CENTER)
        self.clean_btn.add_css_class("destructive-action")
        self.clean_btn.set_tooltip_text(
            "Delete every test VM — the template is kept unless opted in")
        self.clean_btn.set_sensitive(False)  # enabled once a listing succeeds
        self.clean_btn.connect("clicked", self._on_clean_all)
        self.vm_group.set_header_suffix(self.clean_btn)
        self.root.add(self.vm_group)

        # One reusable empty/error placeholder, toggled in _on_vm_list instead
        # of adding throwaway ActionRows.
        self.vm_empty = Adw.StatusPage()
        self.vm_empty.add_css_class("compact")
        self.vm_group.add(self.vm_empty)
        self.vm_empty.set_visible(False)

        # --- disk usage --------------------------------------------------------
        self.disk_group = Adw.PreferencesGroup(
            title="Disk usage",
            description="What the ISO workflow leaves on disk, and how to "
                        "reclaim it.")
        self.root.add(self.disk_group)

        self.iso_row, self.keep_btn = self._disk_row(
            "Local ISOs", "output/*.iso — not measured yet",
            "Keep newest only", self._on_keep_newest)
        self.ci_row, self.ci_btn = self._disk_row(
            "CI downloads", "output/ci-*/ — not measured yet",
            "Delete all", self._on_ci_delete)
        self.cache_row, self.cache_btn = self._disk_row(
            "Titanoboa cache", ".cache/ — not measured yet",
            "Clear", self._on_cache_clear)
        for btn in (self.keep_btn, self.ci_btn, self.cache_btn):
            btn.set_sensitive(False)  # enabled once sizes are known

        # ExpanderRow: the multi-line `podman images | grep margine` listing
        # goes in a monospace label inside the expander, not smeared across
        # the row subtitle (which stays a one-line summary).
        self.podman_row = Adw.ExpanderRow(
            title="Rootful podman images",
            subtitle="margine-live/base images live in root's podman store — "
                     "inspecting needs a polkit prompt, nothing runs "
                     "automatically")
        self.inspect_btn = Gtk.Button(label="Inspect…", valign=Gtk.Align.CENTER)
        self.inspect_btn.set_tooltip_text(
            "List margine images in the rootful store (pkexec)")
        self.inspect_btn.connect("clicked", self._on_inspect)
        self.podman_row.add_suffix(self.inspect_btn)
        self.rmi_btn = Gtk.Button(label="Remove live image",
                                  valign=Gtk.Align.CENTER)
        self.rmi_btn.add_css_class("destructive-action")
        self.rmi_btn.set_tooltip_text(f"pkexec podman rmi {_LIVE_IMAGE}")
        self.rmi_btn.connect("clicked", self._on_rmi)
        self.podman_row.add_suffix(self.rmi_btn)
        out_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL,
                          margin_top=6, margin_bottom=6,
                          margin_start=12, margin_end=12)
        # Plain Gtk.Label (use_markup off) — the listing is raw text, no
        # Pango-escaping worries the row subtitle would have.
        self._podman_out = Gtk.Label(xalign=0, yalign=0, selectable=False,
                                     wrap=True, label="")
        self._podman_out.add_css_class("monospace")
        out_box.append(self._podman_out)
        self.podman_row.add_row(out_box)
        self.disk_group.add(self.podman_row)

    # -- page protocol ----------------------------------------------------------
    def refresh(self):
        # Idempotent: both halves no-op while their previous pass is in flight.
        self._refresh_vms()
        self._refresh_sizes()

    # -- UI helpers ---------------------------------------------------------------
    def _disk_row(self, title, subtitle, btn_label, cb):
        row = Adw.ActionRow(title=title, subtitle=subtitle)
        btn = Gtk.Button(label=btn_label, valign=Gtk.Align.CENTER)
        btn.connect("clicked", cb)
        row.add_suffix(btn)
        self.disk_group.add(row)
        return row, btn

    def _confirm(self, heading, body, action_label, on_confirm, extra=None):
        # Destructive actions all funnel through here — DESTRUCTIVE appearance
        # and Cancel as both default and close response (Esc never deletes).
        dlg = Adw.AlertDialog.new(heading, body)
        dlg.add_response("cancel", "Cancel")
        dlg.add_response("go", action_label)
        dlg.set_response_appearance("go", Adw.ResponseAppearance.DESTRUCTIVE)
        dlg.set_default_response("cancel")
        dlg.set_close_response("cancel")
        if extra is not None:
            dlg.set_extra_child(extra)

        def resp(_d, r):
            if r == "go":
                on_confirm()
        dlg.connect("response", resp)
        dlg.present(self.win)

    # -- test VMs -------------------------------------------------------------------
    def _refresh_vms(self):
        if self._vms_busy:
            return
        self._vms_busy = True
        core.spawn_collect(
            ["virsh", "-c", core.QEMU_CONN, "list", "--all", "--name"],
            self._on_vm_list)

    def _on_vm_list(self, ok, out, err):
        self._vms_busy = False
        self._vm_gen += 1
        for row in self._vm_rows:
            self.vm_group.remove(row)
        self._vm_rows = []
        if not ok:
            self._vm_names = []
            self.clean_btn.set_sensitive(False)
            first = (err.strip().splitlines() or ["is libvirt installed?"])[0]
            self.vm_empty.set_icon_name("dialog-warning-symbolic")
            self.vm_empty.set_title("virsh unavailable")
            self.vm_empty.set_description(GLib.markup_escape_text(first[:120]))
            self.vm_empty.set_visible(True)
            return
        # Only margine-test-* domains are ever shown or acted on.
        self._vm_names = [n.strip() for n in out.splitlines()
                          if n.strip().startswith(core.VM_PREFIX)]
        self.clean_btn.set_sensitive(bool(self._vm_names))
        if not self._vm_names:
            self.vm_empty.set_icon_name("computer-symbolic")
            self.vm_empty.set_title("No test VMs")
            self.vm_empty.set_description(
                "The Test in VM buttons create margine-test-* domains here")
            self.vm_empty.set_visible(True)
            return
        self.vm_empty.set_visible(False)
        gen = self._vm_gen
        for name in self._vm_names:
            self._add_vm_row(name, gen)

    def _add_vm_row(self, name, gen):
        # Names come prefix-filtered from virsh but are still escaped: Adw row
        # titles are Pango markup — a raw '&' silently blanks the whole title.
        row = Adw.ActionRow(title=GLib.markup_escape_text(name))
        disk = os.path.join(core.LIBVIRT_IMAGES, name + ".qcow2")
        try:
            disk_txt = " · disk " + core.human_size(os.path.getsize(disk))
        except OSError:
            disk_txt = ""
        row.set_subtitle("state…")

        if name == core.VM_TEMPLATE:
            tag = Gtk.Label(label="template", valign=Gtk.Align.CENTER)
            tag.add_css_class("caption")
            tag.add_css_class("dim-label")
            row.add_suffix(tag)
        console = Gtk.Button(icon_name="video-display-symbolic",
                             valign=Gtk.Align.CENTER)
        console.add_css_class("flat")
        console.set_tooltip_text("Open console (virt-viewer)")
        console.connect("clicked", lambda *_: self._on_console(name))
        row.add_suffix(console)
        delete = Gtk.Button(icon_name="user-trash-symbolic",
                            valign=Gtk.Align.CENTER)
        delete.add_css_class("flat")
        delete.set_tooltip_text("Delete this VM (domain + disk)")
        delete.connect("clicked", lambda *_: self._on_vm_delete(name, row))
        row.add_suffix(delete)
        self.vm_group.add(row)
        self._vm_rows.append(row)

        def got_state(ok, out, _err):
            if gen != self._vm_gen:
                return  # the list was rebuilt while domstate was running
            state = (out.strip().splitlines() or ["unknown"])[0] if ok \
                else "state unknown"
            row.set_subtitle(GLib.markup_escape_text(state + disk_txt))
        core.spawn_collect(
            ["virsh", "-c", core.QEMU_CONN, "domstate", name], got_state)

    def _on_console(self, name):
        err = core.spawn_fire(
            ["virt-viewer", "--connect", core.QEMU_CONN, "--wait", name])
        # Adw.Toast text is Pango markup — escape the VM name / error, same
        # '&' hazard as the escaped row titles.
        if err is None:
            self.win.toast(GLib.markup_escape_text(f"Opening console: {name}"))
        else:
            self.win.toast(GLib.markup_escape_text(
                f"virt-viewer failed: {err} (is it installed?)"))

    def _on_vm_delete(self, name, row):
        def go():
            row.set_sensitive(False)  # rebuilt by the relist either way
            self._run_vm_delete([name], f"Deleted {name}")
        self._confirm(
            "Delete this test VM?",
            f"{name} is destroyed and undefined, disk included. This cannot "
            "be undone.",
            "Delete", go)

    def _on_clean_all(self, _btn):
        others = [n for n in self._vm_names if n != core.VM_TEMPLATE]
        has_template = core.VM_TEMPLATE in self._vm_names
        if not others and not has_template:
            self.win.toast("No test VMs to delete")
            return
        check = Gtk.CheckButton(
            label=f"Also delete the template ({core.VM_TEMPLATE})")

        def go():
            names = list(others)
            if has_template and check.get_active():
                names.append(core.VM_TEMPLATE)
            if not names:
                self.win.toast("Nothing deleted — only the template exists "
                               "and it was kept")
                return
            self._run_vm_delete(names, f"Deleted {len(names)} test VM(s)")
        self._confirm(
            "Delete all test VMs?",
            f"Destroys and undefines {len(others)} margine-test-* domain(s) "
            "on the session hypervisor, disks included. The template is kept "
            "unless ticked below. Other libvirt domains are never touched.",
            "Delete all", go,
            extra=check if has_template else None)

    def _run_vm_delete(self, names, toast_text):
        # Defense in depth: even a mistake upstream must never let a
        # non-prefixed domain reach virsh undefine.
        names = [n for n in names if n.startswith(core.VM_PREFIX)]
        if not names:
            return
        self.clean_btn.set_sensitive(False)
        # Same safe teardown as core.vm_test_script's recycle: delete only
        # the domain's writable disks, never cdrom media (an attached ISO
        # must survive — `--remove-all-storage` ate a fresh build on
        # 2026-07-07).
        lines = [f"CONN={shlex.quote(core.QEMU_CONN)}"]
        for n in names:
            lines += [f"N={shlex.quote(n)}", core.vm_teardown_script()]

        def done(_ok, _out, _err):
            self.win.toast(GLib.markup_escape_text(toast_text))
            # clean_btn re-enables via the relist (sensitivity follows the
            # remaining VM count) — every exit path of the relist sets it.
            self._refresh_vms()
        core.spawn_collect(["bash", "-c", "\n".join(lines)], done)

    # -- disk usage ---------------------------------------------------------------
    def _refresh_sizes(self):
        if self._sizes_busy:
            return
        self._sizes_busy = True
        for row in (self.iso_row, self.ci_row, self.cache_row):
            row.set_subtitle("measuring…")
        threading.Thread(target=self._measure_sizes, daemon=True).start()

    def _measure_sizes(self):
        # Worker thread: os.walk over multi-GB trees would stall the main
        # loop — results are applied via idle_add only.
        iso_total = iso_count = 0
        ci_total = ci_count = 0
        try:
            for entry in os.listdir(core.OUTPUT_DIR):
                p = os.path.join(core.OUTPUT_DIR, entry)
                if entry.endswith(".iso") and os.path.isfile(p):
                    try:
                        iso_total += os.path.getsize(p)
                        iso_count += 1
                    except OSError:
                        pass  # raced with a delete
                elif entry.startswith("ci-") and os.path.isdir(p):
                    ci_total += core.dir_size(p)
                    ci_count += 1
        except OSError:
            pass
        cache_total = core.dir_size(os.path.join(core.REPO_ROOT, ".cache"))
        GLib.idle_add(self._apply_sizes, iso_total, iso_count,
                      ci_total, ci_count, cache_total)

    def _apply_sizes(self, iso_total, iso_count, ci_total, ci_count,
                     cache_total):
        self._sizes_busy = False
        self.iso_row.set_subtitle(
            f"{iso_count} ISO(s) in output/ — {core.human_size(iso_total)}"
            if iso_count else "no ISOs in output/")
        self.keep_btn.set_sensitive(iso_count > 1)
        self.ci_row.set_subtitle(
            f"{ci_count} download folder(s) — {core.human_size(ci_total)}"
            if ci_count else "no CI downloads")
        self.ci_btn.set_sensitive(ci_count > 0)
        self.cache_row.set_subtitle(
            core.human_size(cache_total) if cache_total else "empty or missing")
        self.cache_btn.set_sensitive(cache_total > 0)
        return GLib.SOURCE_REMOVE

    def _delete_paths_async(self, paths, done_text):
        # rm work off the main loop (a ci-* dir is ~9 GB, .cache has thousands
        # of files). Root-owned leftovers (the build's EXIT trap normally
        # chowns everything back) surface as errors instead of failing quietly.
        def work():
            errors = []
            for p in paths:
                try:
                    if os.path.isdir(p) and not os.path.islink(p):
                        shutil.rmtree(p)
                    else:
                        os.unlink(p)
                except OSError as e:
                    errors.append(f"{os.path.basename(p)}: "
                                  f"{e.strerror or e}")
            GLib.idle_add(finish, errors)

        def finish(errors):
            if errors:
                self.win.toast(GLib.markup_escape_text(
                    "Could not remove: " + "; ".join(errors[:2]) +
                    (" …" if len(errors) > 2 else "")))
            elif done_text:
                self.win.toast(done_text)
            self._refresh_sizes()
            return GLib.SOURCE_REMOVE
        threading.Thread(target=work, daemon=True).start()

    def _root_isos(self):
        try:
            return [os.path.join(core.OUTPUT_DIR, f)
                    for f in os.listdir(core.OUTPUT_DIR) if f.endswith(".iso")]
        except OSError:
            return []

    def _on_keep_newest(self, _btn):
        isos = self._root_isos()
        try:
            newest = max(isos, key=os.path.getmtime) if len(isos) > 1 else None
        except OSError:
            newest = None  # raced with a delete — relist on next refresh
        if newest is None:
            self.win.toast("Nothing to delete — at most one ISO in output/")
            return
        doomed = [p for p in isos if p != newest]

        def go():
            paths = []
            for p in doomed:
                paths.append(p)
                if os.path.exists(p + ".meta.json"):
                    paths.append(p + ".meta.json")
            self._delete_paths_async(paths, f"Deleted {len(doomed)} ISO(s)")
        self._confirm(
            "Delete the older ISOs?",
            f"Keeps only {os.path.basename(newest)}. {len(doomed)} older "
            "ISO(s) and their .meta.json sidecars are removed; CI download "
            "folders are untouched.",
            "Delete", go)

    def _on_ci_delete(self, _btn):
        try:
            dirs = [os.path.join(core.OUTPUT_DIR, d)
                    for d in os.listdir(core.OUTPUT_DIR)
                    if d.startswith("ci-")
                    and os.path.isdir(os.path.join(core.OUTPUT_DIR, d))]
        except OSError:
            dirs = []
        if not dirs:
            self.win.toast("No CI download folders")
            return
        self._confirm(
            "Delete all CI downloads?",
            f"Removes {len(dirs)} output/ci-* folder(s). The CI page can "
            "re-download while the artifact retention lasts.",
            "Delete all",
            lambda: self._delete_paths_async(
                dirs, f"Deleted {len(dirs)} CI folder(s)"))

    def _on_cache_clear(self, _btn):
        cache = os.path.join(core.REPO_ROOT, ".cache")
        if not os.path.isdir(cache):
            self.win.toast("No .cache directory")
            return
        self._confirm(
            "Clear the Titanoboa cache?",
            "The next local ISO build re-clones Titanoboa and re-downloads "
            "what it needs — a slower first build, nothing else is lost.",
            "Clear",
            lambda: self._delete_paths_async([cache],
                                             "Titanoboa cache cleared"))

    # -- rootful podman (pkexec, explicit clicks only) ------------------------------
    def _on_inspect(self, btn):
        btn.set_sensitive(False)
        self.podman_row.set_subtitle("waiting for authentication…")

        def done(ok, out, err):
            btn.set_sensitive(True)  # re-enable on EVERY exit path
            out = out.strip()
            if ok and out:
                # Full listing in the expander's monospace label; the subtitle
                # gets a one-line summary instead of the whole dump.
                n = len(out.splitlines())
                self.podman_row.set_subtitle(
                    f"{n} margine image(s) in the rootful store")
                self._podman_out.set_text(out)
                self.podman_row.set_expanded(True)
            elif not out and not err.strip():
                # grep exits 1 on no match — an empty store, not a failure
                self.podman_row.set_subtitle(
                    "no margine images in the rootful store")
                self._podman_out.set_text("")
                self.podman_row.set_expanded(False)
            else:
                # pkexec exits 126/127 when polkit auth is cancelled or fails
                first = (err.strip().splitlines() or ["unknown error"])[0]
                self.podman_row.set_subtitle(
                    "inspect failed: " + GLib.markup_escape_text(first[:120]) +
                    " (authentication cancelled?)")
                self._podman_out.set_text("")
                self.podman_row.set_expanded(False)
        core.spawn_collect(["pkexec", "sh", "-c", _PODMAN_INSPECT], done)

    def _on_rmi(self, _btn):
        def go():
            self.rmi_btn.set_sensitive(False)

            def done(ok, _out, err):
                self.rmi_btn.set_sensitive(True)  # every exit path
                if ok:
                    self.win.toast("Removed " + _LIVE_IMAGE)
                    self.podman_row.set_subtitle(
                        "live image removed — Inspect… to re-check")
                    self._podman_out.set_text("")
                    self.podman_row.set_expanded(False)
                else:
                    first = (err.strip().splitlines() or ["unknown error"])[0]
                    self.win.toast(GLib.markup_escape_text(
                        f"podman rmi failed: {first[:120]}"))
            core.spawn_collect(["pkexec", "podman", "rmi", _LIVE_IMAGE], done)
        self._confirm(
            "Remove the local live image?",
            f"Runs pkexec podman rmi {_LIVE_IMAGE}. The next local ISO build "
            "recreates it from the base image — extra build time, nothing "
            "else is lost.",
            "Remove", go)
