# mib/ci.py — CI page: Status dashboard + the three remote flows (rebuild
# base image, publish ISO, download+test the newest CI ISO), ported from v1
# behavior-unchanged, plus the changes-since-last-publish changelog.
#
# Three remote flows, all through the gh CLI (user-level, no pkexec):
# rebuild the base image, publish the official ISO, download+test the
# newest CI ISO. Each row runs its own poll loop and reports progress via
# its subtitle + desktop notifications — keep the window open while a CI
# job is monitored (closing it stops the monitoring, not the CI job).
#
# All gh spawns go through core.gh (absolute GH_BIN — brew's bin dir is not
# on a GNOME-launched process' PATH; see core's probe rationale).
import datetime
import json
import os
import shutil

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Gtk, Gdk, Adw, Gio, GLib  # noqa: E402

from . import core  # noqa: E402


def _find_aria2():
    """Absolute path of aria2c, or None. Same probing story as gh in core:
    brew's bin dir is not on a GNOME-launched process' PATH."""
    for cand in (shutil.which("aria2c"),
                 "/home/linuxbrew/.linuxbrew/bin/aria2c",
                 os.path.expanduser("~/.local/bin/aria2c"),
                 "/usr/bin/aria2c", "/usr/local/bin/aria2c"):
        if cand and os.access(cand, os.X_OK):
            return cand
    return None

_esc = GLib.markup_escape_text


def _runs(out):
    """gh --json output → list; [] on empty/garbage."""
    try:
        return json.loads(out) if out.strip() else []
    except ValueError:
        return []


def _errline(err):
    """First stderr line, truncated + Pango-escaped (row subtitles and toast
    titles are markup — a raw '&' in a gh error URL would blank them)."""
    lines = (err or "").strip().splitlines()
    return _esc(lines[0][:120]) if lines else "unknown error"


def _job(data, prefix):
    for j in (data or {}).get("jobs", []):
        if j.get("name", "").startswith(prefix):
            return j.get("status"), (j.get("conclusion") or "")
    return None, ""


def _jobdict(data, prefix):
    for j in (data or {}).get("jobs", []):
        if j.get("name", "").startswith(prefix):
            return j
    return None


def _step_frac(job):
    """Fraction of a job's steps that are completed (0.0-1.0), and the name of
    the step currently running (or "" ) — used to advance the progress bar on
    real GitHub data and to detect the opaque long steps we pulse through."""
    if not job:
        return 0.0, ""
    steps = job.get("steps") or []
    if not steps:
        return (1.0 if job.get("status") == "completed" else 0.0), ""
    done = sum(1 for s in steps if s.get("status") == "completed")
    running = next((s.get("name", "") for s in steps
                    if s.get("status") == "in_progress"), "")
    return done / len(steps), running


def _state(s, c):
    return c or s or "—"


def _fmt_date(created):
    # "2026-07-01T09:12:33Z" → "2026-07-01 09:12 UTC"
    return created[:16].replace("T", " ") + " UTC" if created else "?"


class CiPage:
    def __init__(self, win):
        self.win = win
        self._ia_link = None       # derived archive.org details URL
        self._pub_url = None       # newest successful publish run's URL
        self._status_busy = False  # a dashboard refresh is in flight
        self._status_pending = 0
        self._gh_reason = core.gh_unavailable_reason()

        page = Adw.PreferencesPage()
        page.set_vexpand(True)
        # A single Banner carries the gh-unavailable reason instead of smearing
        # it across every status/action row's subtitle.
        self.banner = Adw.Banner(revealed=False)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        box.append(self.banner)
        box.append(page)
        self.root = box

        # --- Status dashboard -------------------------------------------
        status = Adw.PreferencesGroup(
            title="Status",
            description="Latest CI state — refreshed when this page is shown.")
        refresh_btn = Gtk.Button(icon_name="view-refresh-symbolic",
                                 valign=Gtk.Align.CENTER,
                                 tooltip_text="Refresh status")
        refresh_btn.add_css_class("flat")
        refresh_btn.connect("clicked", lambda *_: self.refresh())
        status.set_header_suffix(refresh_btn)
        page.add(status)

        self.stable_row = Adw.ActionRow(title="Base :stable", subtitle="—")
        status.add(self.stable_row)

        self.pubstat_row = Adw.ActionRow(title="Last publish run", subtitle="—")
        # "Open" jumps to the run page — the run NUMBER must be inspectable
        # before trusting a download (Daniel, 2026-07-03: the id was only shown
        # after pressing Download, inside the confirm dialog).
        self._pubstat_rid = None
        self.pubstat_open_btn = Gtk.Button(label="Open",
                                           valign=Gtk.Align.CENTER, visible=False)
        self.pubstat_open_btn.connect("clicked", self.on_open_pubstat_run)
        self.pubstat_row.add_suffix(self.pubstat_open_btn)
        status.add(self.pubstat_row)
        # The verdict subtitle (iso / gate / publish) is dense — let it wrap.
        self.pubstat_row.set_subtitle_lines(2)

        self.ia_row = Adw.ActionRow(title="Internet Archive", subtitle="—")
        self.ia_copy_btn = Gtk.Button(label="Copy link",
                                      valign=Gtk.Align.CENTER, visible=False)
        self.ia_copy_btn.connect("clicked", self.on_copy_ia)
        self.ia_row.add_suffix(self.ia_copy_btn)
        self.ia_open_btn = Gtk.Button(label="Open run page",
                                      valign=Gtk.Align.CENTER, visible=False)
        self.ia_open_btn.connect("clicked", self.on_open_run)
        self.ia_row.add_suffix(self.ia_open_btn)
        status.add(self.ia_row)

        self.chlog_row = Adw.ActionRow(
            title="Changes since last publish",
            subtitle="local commits not yet in a published ISO")
        self.chlog_btn = Gtk.Button(label="Show", valign=Gtk.Align.CENTER)
        self.chlog_btn.connect("clicked", self.on_changelog)
        self.chlog_row.add_suffix(self.chlog_btn)
        status.add(self.chlog_row)

        # --- CI actions (ported from v1) ----------------------------------
        ci = Adw.PreferencesGroup(
            title="CI (GitHub Actions)",
            description="Remote builds on the repo's Actions — needs the gh "
                        "CLI authenticated. Keep the window open to be notified.")
        page.add(ci)

        # Each long-running CI row embeds ITS OWN full-width progress bar,
        # inside the row (under title+subtitle) so ownership is unambiguous.
        # v2 lesson: PreferencesGroup appends non-row widgets AFTER its boxed
        # list, so a plain ci.add(bar) rendered every bar at the bottom of the
        # group, detached from its button (Daniel, 2026-07-05). ActionRow has a
        # fixed layout, so these are custom Adw.PreferencesRows that mimic its
        # look (title / dim caption subtitle / suffix button) + the bar line.
        # show_text carries "NN% · phase · Xm elapsed · ~Ym left": the ETA is
        # measured from THIS run's pace, never a made-up timer, and the opaque
        # IA-upload step pulses with an honest "elapsed".
        # id(bar) -> pulse-timer source; id(bar) -> {t0, f0} pace state.
        self._pulse_ids = {}
        self._bar_state = {}

        class _CiRow:
            """ActionRow-look row with an embedded progress bar; exposes the
            set_subtitle/get_subtitle the existing flows already call (markup
            semantics match ActionRow: callers pass Pango-escaped text)."""
            def __init__(self, title, subtitle, btn_label, cb):
                self._subtitle = subtitle
                self.row = Adw.PreferencesRow(activatable=False, focusable=False)
                v = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4,
                            margin_top=10, margin_bottom=10,
                            margin_start=12, margin_end=12)
                h = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
                labels = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2,
                                 hexpand=True, valign=Gtk.Align.CENTER)
                t = Gtk.Label(label=title, xalign=0, wrap=True)
                self._sub = Gtk.Label(xalign=0, wrap=True)
                self._sub.add_css_class("dim-label")
                self._sub.add_css_class("caption")
                self._sub.set_markup(subtitle)
                labels.append(t)
                labels.append(self._sub)
                self.btn = Gtk.Button(label=btn_label, valign=Gtk.Align.CENTER)
                self.btn.connect("clicked", cb)
                h.append(labels)
                h.append(self.btn)
                self.bar = Gtk.ProgressBar(show_text=True, hexpand=True,
                                           visible=False, margin_top=4)
                v.append(h)
                v.append(self.bar)
                self.row.set_child(v)

            def set_subtitle(self, text):
                self._subtitle = text
                self._sub.set_markup(text)

            def get_subtitle(self):
                return self._subtitle

        def _ci_row(title, subtitle, btn_label, cb):
            r = _CiRow(title, subtitle, btn_label, cb)
            ci.add(r.row)
            return r, r.btn, r.bar

        self.base_row, self.base_btn, self.base_bar = _ci_row(
            "Rebuild base image",
            "build :candidate → QEMU smoke-boot → promote :stable",
            "Rebuild", self.on_ci_base)
        self.pub_row, self.pub_btn, self.pub_bar = _ci_row(
            "Publish ISO via CI",
            "zstd-19 → install gate → Internet Archive + site bump",
            "Publish", self.on_ci_publish)
        # NB: no raw '&' in row titles — Adw row titles are Pango markup, an
        # unescaped ampersand silently blanks the whole title.
        self.dl_row, self.dl_btn, self.dl_bar = _ci_row(
            "Download + test newest CI ISO",
            "fetch the margine-live-iso artifact, boot it in the test VM",
            "Download", self.on_ci_download)

        self._ci_subtitles = {}   # row -> resting subtitle (restored when idle)
        for row in (self.base_row, self.pub_row, self.dl_row):
            self._ci_subtitles[row] = row.get_subtitle()

        if self._gh_reason is not None:
            self._ci_disable(self._gh_reason)
        else:
            # Auth is checked async — the buttons stay live meanwhile (v1
            # behavior): a failed check disables them a moment later.
            core.gh(["auth", "status"], self._on_gh_auth)

    # -- gh availability -------------------------------------------------
    def _ci_disable(self, why):
        self._gh_reason = why
        self.banner.set_title(why)
        self.banner.set_revealed(True)
        # The banner carries the reason now; disable the action buttons but
        # leave the rows' resting subtitles (and the status rows at "—")
        # instead of repeating the reason on each.
        for btn in (self.base_btn, self.pub_btn, self.dl_btn, self.chlog_btn,
                    self.ia_copy_btn, self.ia_open_btn):
            btn.set_sensitive(False)

    def _on_gh_auth(self, ok, _out, _err):
        if not ok:
            self._ci_disable("gh not authenticated — run: gh auth login")

    # -- Status dashboard --------------------------------------------------
    def refresh(self):
        if self._gh_reason is not None or self._status_busy:
            return
        self._status_busy = True
        self._status_pending = 3
        for row in (self.stable_row, self.pubstat_row, self.ia_row):
            row.set_subtitle("checking…")
        self._ia_link = None
        self._pub_url = None
        self.ia_copy_btn.set_visible(False)
        self.ia_open_btn.set_visible(False)
        self._q_stable()
        self._q_publish()
        self._q_ia()

    def _done_one(self):
        self._status_pending -= 1
        if self._status_pending <= 0:
            self._status_busy = False

    def _q_stable(self):
        # :stable is only ever moved by a green smoke-boot run, so the newest
        # successful smoke-boot IS the promotion moment.
        def got(ok, out, err):
            try:
                if not ok:
                    self.stable_row.set_subtitle("unavailable — " + _errline(err))
                    return
                runs = _runs(out)
                if not runs:
                    self.stable_row.set_subtitle("no successful smoke-boot run found")
                    return
                self.stable_row.set_subtitle(
                    "promoted " + _fmt_date(runs[0].get("createdAt", "")))
            finally:
                self._done_one()

        core.gh(["run", "list", "--repo", core.GH_REPO,
                 "--workflow", "smoke-boot.yml", "--status", "success",
                 "--limit", "1", "--json", "databaseId,createdAt"], got)

    def _q_publish(self):
        def listed(ok, out, err):
            runs = _runs(out) if ok else []
            if not runs:
                self.pubstat_row.set_subtitle(
                    ("unavailable — " + _errline(err)) if not ok
                    else "no publish run yet")
                self._done_one()
                return
            rid = runs[0]["databaseId"]
            created = _fmt_date(runs[0].get("createdAt", ""))
            self._pubstat_rid = rid
            self.pubstat_open_btn.set_visible(True)

            def viewed(ok2, out2, err2):
                try:
                    if not ok2:
                        self.pubstat_row.set_subtitle(
                            f"run {rid} · {created} — " + _errline(err2))
                        return
                    try:
                        data = json.loads(out2)
                    except ValueError:
                        self.pubstat_row.set_subtitle(
                            f"run {rid} · {created} — bad gh JSON")
                        return
                    iso = _state(*_job(data, "Build Live ISO"))
                    gate = _state(*_job(data, "Automated install gate"))
                    pub = _state(*_job(data, "Publish ISO"))
                    # Keep the run id in the HAPPY path too — it's the number a
                    # tester cross-checks against gh/Actions before downloading.
                    self.pubstat_row.set_subtitle(
                        f"run {rid} · {created} · iso: {iso} · gate: {gate} · publish: {pub}")
                finally:
                    self._done_one()

            core.gh(["run", "view", str(rid), "--repo", core.GH_REPO,
                     "--json", "status,conclusion,jobs"], viewed)

        core.gh(["run", "list", "--repo", core.GH_REPO,
                 "--workflow", "build-disk.yml", "--event", "workflow_dispatch",
                 "--limit", "1", "--json", "databaseId,createdAt"], listed)

    def _q_ia(self):
        def listed(ok, out, err):
            runs = _runs(out) if ok else []
            if not runs:
                self.ia_row.set_subtitle(
                    ("unavailable — " + _errline(err)) if not ok
                    else "no successful publish run yet")
                self._done_one()
                return
            self._pub_url = runs[0].get("url") or ""

            def viewed(ok2, out2, _err2):
                try:
                    data = None
                    if ok2 and out2.strip():
                        try:
                            data = json.loads(out2)
                        except ValueError:
                            data = None
                    ident = self._derive_ia_identifier(data)
                    if ident:
                        self._ia_link = f"https://archive.org/details/{ident}"
                        self.ia_row.set_subtitle(_esc(ident))
                        self.ia_copy_btn.set_visible(True)
                    else:
                        self.ia_row.set_subtitle(
                            "No Archive link for this run "
                            "(non-stable variant?) — open the run page")
                        self.ia_open_btn.set_visible(bool(self._pub_url))
                finally:
                    self._done_one()

            core.gh(["run", "view", str(runs[0]["databaseId"]),
                     "--repo", core.GH_REPO, "--json", "jobs"], viewed)

        core.gh(["run", "list", "--repo", core.GH_REPO,
                 "--workflow", "build-disk.yml", "--event", "workflow_dispatch",
                 "--status", "success", "--limit", "1",
                 "--json", "databaseId,url"], listed)

    @staticmethod
    def _derive_ia_identifier(data):
        """Reproduce the ia_upload step of .github/workflows/build-disk.yml:

            DATE_TAG="$(date -u +%Y%m%d)"        # taken IN the publish_ia job
            VSLUG="live" for stable, else the raw tag (e.g. "nvidia")
            IDENTIFIER="margine-${VSLUG}-iso-${DATE_TAG}"
            → https://archive.org/details/$IDENTIFIER

        What is reconstructable from run data:
        * DATE_TAG — the 'Publish ISO' JOB's startedAt (UTC day), NOT the
          run's createdAt: `gh run rerun --failed <id>` re-runs just
          publish_ia days later and DATE_TAG is re-derived then.
        * variant — workflow_dispatch inputs are not exposed by the runs
          API, but install_gate's `if:` runs it exactly when image_tag is
          ''/'stable', so gate success => stable => VSLUG "live". A skipped
          gate means a non-stable tag whose VALUE is unrecoverable — do not
          guess (return None → the run-page fallback button).
        matrix.image is single-entry "margine" (gaming variant retired
        2026-06-06), so the identifier prefix is a constant.
        """
        gate_s, gate_c = _job(data, "Automated install gate")
        if gate_s != "completed" or gate_c != "success":
            return None
        pub = None
        for j in (data or {}).get("jobs", []):
            if j.get("name", "").startswith("Publish ISO"):
                pub = j
                break
        if pub is None or pub.get("conclusion") != "success":
            return None
        ts = core.iso_ts(pub.get("startedAt") or "")
        if ts <= 0:
            return None
        date_tag = datetime.datetime.fromtimestamp(
            ts, datetime.timezone.utc).strftime("%Y%m%d")
        return f"margine-live-iso-{date_tag}"

    def on_copy_ia(self, _btn):
        if not self._ia_link:
            return
        display = Gdk.Display.get_default()
        if display is not None:
            display.get_clipboard().set(self._ia_link)
            self.win.toast("Copied")

    def on_open_run(self, _btn):
        if not self._pub_url:
            return
        try:
            Gio.AppInfo.launch_default_for_uri(self._pub_url, None)
        except GLib.Error as e:
            self.win.toast(_esc(f"Failed to open the run page: {e.message}"))

    def on_open_pubstat_run(self, _btn):
        if self._pubstat_rid is None:
            return
        url = f"https://github.com/{core.GH_REPO}/actions/runs/{self._pubstat_rid}"
        try:
            Gio.AppInfo.launch_default_for_uri(url, None)
        except GLib.Error as e:
            self.win.toast(_esc(f"Failed to open the run page: {e.message}"))

    # -- changelog since the last publish -----------------------------------
    def on_changelog(self, _btn):
        self.chlog_btn.set_sensitive(False)

        def listed(ok, out, err):
            runs = _runs(out) if ok else []
            if not runs or not runs[0].get("headSha"):
                self.chlog_btn.set_sensitive(True)
                self.win.toast(("gh failed: " + _errline(err)) if not ok else
                               "No successful publish run found — nothing to diff against")
                return
            sha = runs[0]["headSha"]
            since = _fmt_date(runs[0].get("createdAt", ""))

            def got(ok2, out2, err2):
                self.chlog_btn.set_sensitive(True)
                if not ok2:
                    # Typical cause: the published sha isn't in the local
                    # clone (stale checkout / rebase) — surface git's words.
                    self.win.toast("git log failed: " + _errline(err2) +
                                   " (git fetch first?)")
                    return
                text = out2.strip() or "(no commits since the last publish)"
                self._show_changelog(text, sha, since)

            core.spawn_collect(["git", "-C", core.REPO_ROOT, "log",
                                "--oneline", f"{sha}..HEAD"], got)

        core.gh(["run", "list", "--repo", core.GH_REPO,
                 "--workflow", "build-disk.yml", "--event", "workflow_dispatch",
                 "--status", "success", "--limit", "1",
                 "--json", "headSha,createdAt"], listed)

    def _show_changelog(self, text, sha, since):
        dlg = Adw.Dialog()
        dlg.set_title("Changes since last publish")
        dlg.set_content_width(640)
        dlg.set_content_height(560)
        view = Adw.ToolbarView()
        header = Adw.HeaderBar()
        copy_btn = Gtk.Button(icon_name="edit-copy-symbolic",
                              tooltip_text="Copy all")

        def do_copy(_b):
            display = Gdk.Display.get_default()
            if display is not None:
                display.get_clipboard().set(text)
                self.win.toast("Copied")

        copy_btn.connect("clicked", do_copy)
        header.pack_end(copy_btn)
        view.add_top_bar(header)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6,
                      margin_top=12, margin_bottom=12,
                      margin_start=12, margin_end=12)
        head = Gtk.Label(xalign=0, wrap=True)
        head.add_css_class("dim-label")
        head.set_label(f"git log --oneline {sha[:12]}..HEAD — last publish {since}")
        box.append(head)
        # NOT selectable: a selectable label inside a ScrolledWindow grabs
        # initial focus, select-alls and scrolls to the bottom (the v1 help
        # dialog bug) — the Copy button covers the copy use case. No wrap:
        # long subject lines scroll horizontally instead of mangling.
        card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        card.add_css_class("card")
        body = Gtk.Label(label=text, xalign=0, yalign=0, selectable=False,
                         wrap=False, margin_top=8, margin_bottom=8,
                         margin_start=12, margin_end=12)
        body.add_css_class("monospace")
        card.append(body)
        box.append(card)
        scroller = Gtk.ScrolledWindow(vexpand=True)
        scroller.set_child(box)
        view.set_content(scroller)
        dlg.set_child(view)
        dlg.present(self.win)

    # -- CI: shared plumbing -------------------------------------------------
    def _find_dispatch_run(self, workflow, since_ts, cb, attempts=12,
                           event="workflow_dispatch"):
        """Poll `gh run list` until a run of `workflow` created around/after
        since_ts shows up (trigger → visible lag is seconds; workflow_run
        chaining can take a minute); cb(run_id | None)."""
        state = {"left": attempts}

        def ask():
            core.gh(["run", "list", "--repo", core.GH_REPO,
                     "--workflow", workflow, "--event", event, "--limit", "3",
                     "--json", "databaseId,createdAt"], got)
            return GLib.SOURCE_REMOVE

        def got(ok, out, _err):
            if ok and out.strip():
                try:
                    for r in json.loads(out):
                        if core.iso_ts(r.get("createdAt", "")) >= since_ts - 120:
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

    # -- progress bars -------------------------------------------------------
    @staticmethod
    def _fmt_dur(seconds):
        m = int(seconds // 60)
        return f"{m // 60}h {m % 60}m" if m >= 60 else f"{m}m"

    def _bar_pace(self, bar, f=None):
        """Per-bar pace state: first call (or re-show) stamps t0 and the
        starting fraction, so the ETA reflects THIS run's measured speed."""
        st = self._bar_state.get(id(bar))
        if st is None or not bar.get_visible():
            st = {"t0": GLib.get_monotonic_time() / 1e6,
                  "f0": f if f is not None else 0.0}
            self._bar_state[id(bar)] = st
        return st, GLib.get_monotonic_time() / 1e6 - st["t0"]

    def _bar_frac(self, bar, f, label=""):
        """Determinate bar with rich in-bar text: 'NN% · label · pace'.
        The ETA is extrapolated from this run's own progress rate — shown only
        once there's enough signal (>=90s and >=3% advanced) to be honest."""
        st, elapsed = self._bar_pace(bar, f)
        self._bar_stop_pulse(bar)
        f = max(0.0, min(1.0, f))
        txt = f"{int(f * 100)}%"
        if label:
            txt += f" · {label}"
        adv = f - st["f0"]
        if elapsed >= 90 and adv >= 0.03 and f < 0.995:
            eta = (1.0 - f) * (elapsed / adv)
            txt += f" · {self._fmt_dur(elapsed)} elapsed · ~{self._fmt_dur(eta)} left"
        elif elapsed >= 60:
            txt += f" · {self._fmt_dur(elapsed)} elapsed"
        bar.set_visible(True)
        bar.set_fraction(f)
        bar.set_text(txt)

    def _bar_pulse(self, bar, label=""):
        """Indeterminate, animating bar for opaque long steps (the IA upload:
        GitHub exposes no sub-progress). The text says so honestly — phase +
        elapsed — and a 150ms ticker keeps it alive between the 60s polls."""
        st, elapsed = self._bar_pace(bar)
        bar.set_visible(True)
        if label:
            bar.set_text(f"{label} · {self._fmt_dur(elapsed)} elapsed"
                         if elapsed >= 60 else label)
        if id(bar) in self._pulse_ids:
            return
        def _p():
            bar.pulse()
            return GLib.SOURCE_CONTINUE
        self._pulse_ids[id(bar)] = GLib.timeout_add(150, _p)

    def _bar_stop_pulse(self, bar):
        pid = self._pulse_ids.pop(id(bar), 0)
        if pid:
            GLib.source_remove(pid)

    def _bar_hide(self, bar):
        self._bar_stop_pulse(bar)
        self._bar_state.pop(id(bar), None)
        bar.set_fraction(0.0)
        bar.set_visible(False)

    def _watch_run(self, run_id, handler, interval=45):
        """Poll a run's status+jobs until handler(data) returns False.
        data is None on a transient gh error (handler usually keeps going)."""
        def ask():
            core.gh(["run", "view", str(run_id), "--repo", core.GH_REPO,
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
            "Builds margine:candidate (about 40–60 min), QEMU smoke-boots it and — "
            "only if green — promotes it to :stable. You'll be notified at "
            "each stage; Fast test ISO then builds from the new base.")
        dlg.add_response("cancel", "Cancel")
        dlg.add_response("go", "Rebuild")
        dlg.set_response_appearance("go", Adw.ResponseAppearance.SUGGESTED)

        def resp(_d, r):
            if r == "go":
                self._ci_base_start()

        dlg.connect("response", resp)
        dlg.present(self.win)

    def _ci_base_start(self):
        self.base_btn.set_sensitive(False)
        self.base_row.set_subtitle("triggering the rebuild…")
        t0 = datetime.datetime.now(datetime.timezone.utc).timestamp()

        def triggered(ok, _out, err):
            if not ok:
                self._ci_base_done(f"trigger failed: {_errline(err)}", notify=True)
                return
            self.base_row.set_subtitle("waiting for the run to appear…")
            self._find_dispatch_run("build.yml", t0, found)

        def found(run_id):
            if run_id is None:
                self._ci_base_done("run never appeared — check Actions", notify=True)
                return
            self.win.append_log(f"\n[CI] base rebuild run {run_id} — monitoring\n")
            self.base_row.set_subtitle(f"building :candidate… (run {run_id})")
            self._watch_run(run_id, tick)

        def tick(data):
            if data is None:
                return True
            if data.get("status") != "completed":
                bf, _s = _step_frac(_jobdict(data, ""))  # primary job's steps
                self._bar_frac(self.base_bar, 0.05 + 0.60 * bf,
                               "building :candidate")  # build owns 5-65%
                return True
            if data.get("conclusion") == "success":
                self._bar_frac(self.base_bar, 0.65, "waiting for smoke-boot")
                self.base_row.set_subtitle(":candidate built — waiting for smoke-boot…")
                self.win.notify("Base :candidate built",
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
            if data is None:
                return True
            if data.get("status") != "completed":
                sf, _s = _step_frac(_jobdict(data, ""))
                self._bar_frac(self.base_bar, 0.65 + 0.35 * sf,
                               "smoke-boot + promote")  # smoke-boot 65-100%
                return True
            if data.get("conclusion") == "success":
                self._ci_base_done(":stable promoted")
                self.win.notify("Base :stable updated",
                                "Fast test ISO now builds from the new base.")
            else:
                self._ci_base_done("smoke-boot FAILED — :candidate NOT promoted",
                                   notify=True)
            return False

        core.gh(["workflow", "run", "build.yml", "--repo", core.GH_REPO,
                 "--ref", "main"], triggered)

    def _ci_base_done(self, text, notify=False):
        self.base_btn.set_sensitive(True)
        self._bar_hide(self.base_bar)
        # `text` is already Pango-escaped by its callers (gh errors via
        # _errline, otherwise markup-safe literals) and the toast below
        # consumes the same markup — do NOT re-escape here, or a gh error's
        # '&' double-escapes to '&amp;' in the row subtitle.
        self.base_row.set_subtitle(text)
        if notify:
            self.win.notify("Base rebuild: " + text)
        # a finished rebuild moves the Base :stable dashboard row
        self.refresh()

    # -- CI: publish the official ISO ------------------------------------------
    def on_ci_publish(self, _btn):
        tag = self.win.current_tag()
        if tag not in ("stable", "nvidia"):
            self.win.toast(f"Publishing needs tag stable or nvidia (got: {tag})")
            return
        extra = ("Also bumps the site's ISO date." if tag == "stable" else
                 "Publishes as margine-nvidia-<date>; the site date is untouched.")
        dlg = Adw.AlertDialog.new(
            f"Publish the margine:{tag} ISO publicly?",
            "CI builds the full zstd-19 ISO (about 60–80 min), runs the real-install "
            f"gate, then uploads to Internet Archive. {extra} The gate blocks "
            "publishing if the install fails.")
        dlg.add_response("cancel", "Cancel")
        dlg.add_response("go", "Publish")
        dlg.set_response_appearance("go", Adw.ResponseAppearance.SUGGESTED)

        def resp(_d, r):
            if r == "go":
                self._ci_publish_start(tag)

        dlg.connect("response", resp)
        dlg.present(self.win)

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
                self.win.toast(f"A publish run is already in progress — monitoring run {active}")
                self._ci_publish_watch(active)
                return
            t0 = datetime.datetime.now(datetime.timezone.utc).timestamp()

            def triggered(ok2, _o, err2):
                if not ok2:
                    self._ci_publish_done(f"trigger failed: {_errline(err2)}",
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

            core.gh(["workflow", "run", "build-disk.yml", "--repo", core.GH_REPO,
                     "--ref", "main", "-f", f"image_tag={tag}"], triggered)

        core.gh(["run", "list", "--repo", core.GH_REPO, "--workflow", "build-disk.yml",
                 "--event", "workflow_dispatch", "--limit", "5",
                 "--json", "databaseId,status"], listed)

    def _ci_publish_watch(self, run_id):
        self.win.append_log(f"\n[CI] publish run {run_id} — monitoring\n")
        seen = set()

        def milestone(key, title, body=""):
            if key not in seen:
                seen.add(key)
                self.win.notify(title, body)

        def tick(data):
            if data is None:
                return True
            iso_s, iso_c = _job(data, "Build Live ISO")
            gate_s, gate_c = _job(data, "Automated install gate")
            pub_s, pub_c = _job(data, "Publish ISO")
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

            # Progress bar, weighted by phase on real step data: ISO build owns
            # 0-50%, gate 50-65%, IA publish 65-100% — and the IA upload step
            # (opaque, no sub-progress) pulses instead of freezing.
            if pub_s == "in_progress":
                pf, pstep = _step_frac(_jobdict(data, "Publish ISO"))
                if any(k in pstep for k in ("Internet Archive", "Upload", "derive")):
                    self._bar_pulse(self.pub_bar,
                                    "uploading to Internet Archive (no % from GitHub)")
                else:
                    self._bar_frac(self.pub_bar, 0.65 + 0.35 * pf, "publishing")
            elif iso_s == "completed" and iso_c == "success":
                gf, _gs = _step_frac(_jobdict(data, "Automated install gate"))
                self._bar_frac(self.pub_bar, 0.50 + 0.15 * gf, "install gate")
            elif iso_s == "in_progress":
                isf, _is = _step_frac(_jobdict(data, "Build Live ISO"))
                self._bar_frac(self.pub_bar, 0.50 * isf, "building ISO (zstd-19)")
            else:
                self._bar_frac(self.pub_bar, 0.02, "queued")  # queued

            self.pub_row.set_subtitle(
                f"run {run_id} · iso: {_state(iso_s, iso_c)} · "
                f"gate: {_state(gate_s, gate_c)} · publish: {_state(pub_s, pub_c)}")
            if data.get("status") != "completed":
                return True
            self._ci_publish_done(
                f"run {run_id} finished: {data.get('conclusion') or '?'}",
                notify=True, body=data.get("url") or "")
            return False

        self._watch_run(run_id, tick, interval=60)

    def _ci_publish_done(self, text, notify=False, body=""):
        self.pub_btn.set_sensitive(True)
        self._bar_hide(self.pub_bar)
        # text already markup-escaped by callers (see _ci_base_done)
        self.pub_row.set_subtitle(text)
        if notify:
            self.win.notify("Publish: " + text, body)
        # a finished publish changes the dashboard (last run, IA link, changelog)
        self.refresh()

    # -- CI: download the newest CI ISO + test it -------------------------------
    def on_ci_download(self, _btn):
        self.dl_btn.set_sensitive(False)
        self.dl_row.set_subtitle("looking for the newest CI ISO artifact…")

        def listed(ok, out, _err):
            runs = _runs(out) if ok else []
            self._ci_dl_probe(runs, 0)

        core.gh(["run", "list", "--repo", core.GH_REPO, "--workflow", "build-disk.yml",
                 "--limit", "15", "--json", "databaseId,createdAt"], listed)

    def _ci_dl_probe(self, runs, idx):
        """Newest-first: first run with a live margine-live-iso artifact wins
        (ISO-less qcow2-only runs and expired artifacts are skipped)."""
        if idx >= len(runs):
            # The multi-GB CI artifacts expire within hours by design — they
            # only exist to hand the ISO to publish_ia. Once they're gone the
            # authoritative copy is the PUBLISHED one on Internet Archive,
            # which is also the exact bytes end users download: fall back.
            self._ci_dl_ia_fallback()
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

        core.gh(["api", f"repos/{core.GH_REPO}/actions/runs/{rid}/artifacts"], got)

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
        dlg.present(self.win)

    def _ci_dl_start(self, rid, size):
        dest = os.path.join(core.OUTPUT_DIR, f"ci-{rid}")
        os.makedirs(dest, exist_ok=True)

        # `gh run download` streams the ~9 GB artifact ZIP to $TMPDIR and only
        # unzips it into -D at the very end. On this host /tmp is tmpfs (RAM,
        # ~14 GB): with the default TMPDIR the zip balloons in RAM while the
        # size-based progress below — which walks `dest` — reads 0% until that
        # final extraction. Point TMPDIR *inside* dest so the zip lands on real
        # disk and the walk (which sums every file under dest, the in-flight
        # *.zip included) tracks the download live. This needs a
        # SubprocessLauncher: the plain Gio.Subprocess.new form used by core.gh
        # has no way to set the child's environment, hence the direct spawn.
        try:
            launcher = Gio.SubprocessLauncher.new(
                Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE)
            launcher.setenv("TMPDIR", dest, True)
            proc = launcher.spawnv(
                [core.GH_BIN or "gh", "run", "download", str(rid),
                 "--repo", core.GH_REPO, "-n", "margine-live-iso", "-D", dest])
        except GLib.Error as e:
            self._ci_dl_done("download failed to start: " + _errline(e.message))
            return
        self.dl_row.set_subtitle("downloading… 0%")
        # Same speed/ETA treatment as the Archive path — percent alone moves
        # too slowly on multi-GB files to look alive.
        state = {"live": True, "prev": 0, "rate": 0.0}

        def progress():
            if not state["live"]:
                return GLib.SOURCE_REMOVE
            have = 0
            for root_, _dirs, files in os.walk(dest):
                for f in files:
                    try:
                        # st_blocks (allocated), NOT st_size: torrents write
                        # pieces at scattered offsets, so the file goes sparse
                        # with a near-full APPARENT size almost immediately —
                        # getsize would show ~97% at once and then sit there.
                        st = os.stat(os.path.join(root_, f))
                        have += st.st_blocks * 512
                    except OSError:
                        pass
            inst = max(0, have - state["prev"]) / 2.0          # B/s this tick
            state["rate"] = (0.7 * state["rate"] + 0.3 * inst) if state["prev"] else inst
            state["prev"] = have
            pct = min(99, int(have * 100 / size)) if size else 0
            self._bar_frac(self.dl_bar, (pct or 0) / 100.0, "downloading")
            extra = ""
            if state["rate"] > 1024:
                left = (size - have) / state["rate"] if size else 0
                eta = (f"{int(left // 3600)}h {int(left % 3600 // 60)}m"
                       if left >= 3600 else f"{int(left // 60)}m")
                extra = f" · {state['rate'] / 1e6:.1f} MB/s · ~{eta} left"
            self.dl_row.set_subtitle(
                f"downloading… {have / 1e9:.2f} / {size / 1e9:.1f} GB ({pct}%){extra}")
            return GLib.SOURCE_CONTINUE

        GLib.timeout_add_seconds(2, progress)

        def done(p, res):
            state["live"] = False
            try:
                p.communicate_utf8_finish(res)
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
            self._ci_dl_done("downloaded: " + _esc(os.path.basename(isos[0])))
            self.win.notify("CI ISO downloaded", os.path.basename(isos[0]))
            self._ci_dl_offer_test(isos[0])

        # communicate_utf8_async drains stdout/stderr (so a chatty gh can't
        # fill the pipe and stall) and fires `done` when the process exits.
        proc.communicate_utf8_async(None, None, done)

    # -- CI: Internet Archive fallback (artifact expired) ---------------------
    def _ci_dl_ia_fallback(self):
        # Identifier comes from the dashboard derivation (self._ia_link, set
        # by refresh()); the actual .iso filename is read from IA's metadata
        # API rather than guessed (nvidia variants name differently).
        ident = (self._ia_link or "").rsplit("/", 1)[-1]
        if not ident:
            self._ci_dl_done("no live CI artifact, and no Archive link derived "
                             "yet — refresh the Status group above first")
            return
        self.dl_row.set_subtitle("CI artifact expired — checking Internet Archive…")

        def got(ok, out, _err):
            name, size = None, 0
            if ok and out.strip():
                try:
                    for f in json.loads(out).get("files", []):
                        if str(f.get("name", "")).endswith(".iso"):
                            name = f["name"]
                            size = int(f.get("size") or 0)
                            break
                except (ValueError, TypeError):
                    pass
            if not name:
                self._ci_dl_done("Archive item has no .iso yet (still deriving?) "
                                 "— try again in a few minutes")
                return
            self._ci_dl_ia_confirm(ident, name, size)

        core.spawn_collect(["curl", "-sSL", "--max-time", "30",
                            f"https://archive.org/metadata/{ident}"], got)

    def _ci_dl_ia_confirm(self, ident, name, size):
        method = ("Via torrent with aria2: many parallel connections and "
                  "per-piece hash verification — measured well over the "
                  "single-connection rate on archive.org."
                  if _find_aria2() else
                  "Direct HTTP (archive.org serves ~1 MB/s single-connection; "
                  "install aria2 for the much faster torrent path: "
                  "brew install aria2).")
        dlg = Adw.AlertDialog.new(
            "Download the published ISO instead?",
            "The CI artifact has expired (artifacts only live long enough to "
            f"reach the publisher). {name} — {size / 1e9:.1f} GB — is live on "
            "Internet Archive: the exact bytes end users download. "
            f"{method} It lands in output/ia-{ident}/ and can be booted in "
            "the test VM right after.")
        dlg.add_response("cancel", "Cancel")
        dlg.add_response("go", "Download")
        dlg.set_response_appearance("go", Adw.ResponseAppearance.SUGGESTED)

        def resp(_d, r):
            if r == "go":
                self._ci_dl_ia_start(ident, name, size)
            else:
                self._ci_dl_done(None)

        dlg.connect("response", resp)
        dlg.present(self.win)

    def _ci_dl_ia_start(self, ident, name, size):
        dest = os.path.join(core.OUTPUT_DIR, f"ia-{ident}")
        os.makedirs(dest, exist_ok=True)
        aria = _find_aria2()
        if aria:
            # Torrent route (preferred): IA items ship a webseed torrent, so
            # aria2 opens many parallel connections, hash-verifies every piece
            # and resumes via its control file. --file-allocation=none keeps
            # the walk()-based progress meaningful (falloc would make the file
            # full-size instantly); --follow-torrent=mem keeps the .torrent
            # itself off disk; --seed-time=0 exits when the download is done.
            argv = [aria, "--seed-time=0", "--dir", dest,
                    "--file-allocation=none", "--follow-torrent=mem",
                    "--max-connection-per-server=8", "--split=16",
                    "--console-log-level=warn", "--summary-interval=0",
                    f"https://archive.org/download/{ident}/{ident}_archive.torrent"]
            label = "downloading via torrent (aria2)…"
        else:
            # curl fallback: single connection (slow on archive.org), but
            # writes straight into dest so the same progress works; -C -
            # resumes a half-downloaded file instead of restarting ~9 GB.
            argv = ["curl", "-L", "--fail", "-sS", "-C", "-",
                    "-o", os.path.join(dest, name),
                    f"https://archive.org/download/{ident}/{name}"]
            label = "downloading from Internet Archive…"
        try:
            proc = Gio.Subprocess.new(
                argv, Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_MERGE)
        except GLib.Error as e:
            self._ci_dl_done("download failed to start: " + _errline(e.message))
            return
        self.dl_row.set_subtitle(label + " 0%")
        # Speed + ETA in the subtitle: archive.org often serves ~0.5-1 MB/s, so
        # percent alone moves every ~90 s and reads as "stuck" (Daniel,
        # 2026-07-04). prev/EMA over the 2 s ticks smooths the rate.
        state = {"live": True, "prev": 0, "rate": 0.0}

        def progress():
            if not state["live"]:
                return GLib.SOURCE_REMOVE
            have = 0
            for root_, _dirs, files in os.walk(dest):
                for f in files:
                    try:
                        # st_blocks (allocated), NOT st_size: torrents write
                        # pieces at scattered offsets, so the file goes sparse
                        # with a near-full APPARENT size almost immediately —
                        # getsize would show ~97% at once and then sit there.
                        st = os.stat(os.path.join(root_, f))
                        have += st.st_blocks * 512
                    except OSError:
                        pass
            inst = max(0, have - state["prev"]) / 2.0          # B/s this tick
            state["rate"] = (0.7 * state["rate"] + 0.3 * inst) if state["prev"] else inst
            state["prev"] = have
            pct = min(99, int(have * 100 / size)) if size else 0
            self._bar_frac(self.dl_bar, (pct or 0) / 100.0, "downloading")
            extra = ""
            if state["rate"] > 1024:
                left = (size - have) / state["rate"] if size else 0
                eta = (f"{int(left // 3600)}h {int(left % 3600 // 60)}m"
                       if left >= 3600 else f"{int(left // 60)}m")
                extra = f" · {state['rate'] / 1e6:.1f} MB/s · ~{eta} left"
            self.dl_row.set_subtitle(
                f"{label} {have / 1e9:.2f} / {size / 1e9:.1f} GB ({pct}%){extra}")
            return GLib.SOURCE_CONTINUE

        GLib.timeout_add_seconds(2, progress)

        def done(p, res):
            state["live"] = False
            try:
                p.communicate_utf8_finish(res)
            except GLib.Error:
                pass
            # The torrent lands under dest/<identifier>/, curl directly in
            # dest/ — walk instead of assuming a layout.
            isos = []
            if p.get_successful():
                for root_, _dirs, files in os.walk(dest):
                    isos += [os.path.join(root_, f)
                             for f in files if f.endswith(".iso")]
            if not isos:
                self._ci_dl_done("Archive download failed — partial data is "
                                 "kept; Download again resumes it")
                return
            self._ci_dl_done("downloaded: " + _esc(os.path.basename(isos[0])))
            self.win.notify("Published ISO downloaded", os.path.basename(isos[0]))
            self._ci_dl_offer_test(isos[0])

        proc.communicate_utf8_async(None, None, done)

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
                self._launch_vm(iso, core.VM_PREFIX + "ci")

        dlg.connect("response", resp)
        dlg.present(self.win)

    def _launch_vm(self, iso, name):
        self.win.append_log(f"\n$ ujust margine-test-vm {os.path.basename(iso)} {name}\n")
        err = core.bash_fire(core.vm_test_script(iso, name))
        if err:
            self.win.toast(_esc(f"Failed to launch the VM: {err}"))
        else:
            self.win.toast("Launching the CI-ISO test VM (clipboard + Secure Boot + TPM 2.0)")

    def _ci_dl_done(self, text):
        self.dl_btn.set_sensitive(True)
        self._bar_hide(self.dl_bar)
        # text already markup-escaped by callers (see _ci_base_done)
        self.dl_row.set_subtitle(text if text else self._ci_subtitles[self.dl_row])
