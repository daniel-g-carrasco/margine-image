# Margine ISO Builder — How-to-use dialog (v2 redesign).
#
# v1 bug this file exists to fix (do not regress): the old guide was one giant
# Gtk.Label(selectable=True) inside a ScrolledWindow — a selectable label
# grabs initial focus, which selects ALL the text and scrolls the view to the
# bottom. Here nothing is selectable and nothing is focused on open; command
# examples are monospace chips with an explicit copy button instead.
import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
gi.require_version("Gdk", "4.0")
from gi.repository import Gtk, Adw, Gdk  # noqa: E402


def _heading(text):
    lbl = Gtk.Label(label=text, xalign=0, wrap=True)
    lbl.add_css_class("title-4")
    return lbl


def _body(text):
    # Plain-text label (no markup parsing), NOT selectable — free-form prose
    # can contain any character without the Pango-escaping worries Adw row
    # titles have, and can never steal focus/selection like v1's guide label.
    lbl = Gtk.Label(label=text, xalign=0, wrap=True)
    lbl.add_css_class("body")
    return lbl


def _caption(text):
    lbl = Gtk.Label(label=text, xalign=0, wrap=True)
    lbl.add_css_class("caption")
    lbl.add_css_class("dim-label")
    return lbl


def _row(group, icon, title, subtitle):
    # NB: Adw row titles/subtitles are Pango markup — keep them free of raw
    # '&', '<', '>' (an unescaped ampersand silently blanks the whole title).
    row = Adw.ActionRow(title=title, subtitle=subtitle)
    row.add_prefix(Gtk.Image.new_from_icon_name(icon))
    group.add(row)


def _cmd(toasts, text, note=None):
    """Monospace command chip with a copy button — replaces v1's selectable
    text as the way to get a command out of the dialog."""
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
    chip = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6,
                   halign=Gtk.Align.START)
    chip.add_css_class("card")
    lbl = Gtk.Label(label=text, xalign=0, wrap=True,
                    margin_top=6, margin_bottom=6, margin_start=12)
    lbl.add_css_class("monospace")
    chip.append(lbl)
    btn = Gtk.Button(icon_name="edit-copy-symbolic", valign=Gtk.Align.CENTER,
                     margin_end=2)
    btn.add_css_class("flat")
    btn.set_tooltip_text("Copy command")

    def copy(_btn):
        display = Gdk.Display.get_default()
        if display is not None:
            display.get_clipboard().set(text)
            toasts.add_toast(Adw.Toast.new("Copied"))

    btn.connect("clicked", copy)
    chip.append(btn)
    box.append(chip)
    if note:
        box.append(_caption(note))
    return box


def _issue(toasts, symptom, explanation, cmd=None):
    """A troubleshooting item: symptom heading + explanation (+ fix chip)."""
    item = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=3)
    head = Gtk.Label(label=symptom, xalign=0, wrap=True)
    head.add_css_class("heading")
    item.append(head)
    item.append(_body(explanation))
    if cmd:
        item.append(_cmd(toasts, cmd))
    return item


def show_help(win):
    dlg = Adw.Dialog()
    dlg.set_title("How to use")
    dlg.set_content_width(640)
    dlg.set_content_height(720)

    # The window's toast overlay sits under the dialog scrim, so the "Copied"
    # feedback gets its own overlay inside the dialog.
    toasts = Adw.ToastOverlay()

    content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=24,
                      margin_top=12, margin_bottom=24,
                      margin_start=12, margin_end=12)

    def section(title, *widgets):
        sec = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        sec.append(_heading(title))
        for w in widgets:
            sec.append(w)
        content.append(sec)

    # --- intro ---------------------------------------------------------------
    content.append(_body(
        "Margine ISO Builder builds the Margine live ISO locally, so "
        "install-time and ISO bugs can be iterated without the ~40 min CI "
        "build or an 8.5 GB download. It is a developer tool — nothing here "
        "ships in the distro."))

    # --- Build page ------------------------------------------------------------
    build_group = Adw.PreferencesGroup()
    _row(build_group, "preferences-system-symbolic", "Base image tag",
         "Which published margine base the live ISO is built from. Leave "
         "stable unless you know otherwise; publishing accepts stable or "
         "nvidia only.")
    _row(build_group, "media-playback-start-symbolic", "Fast test ISO",
         "zstd-1 — quick, best for iterating on bugs. A graphical password "
         "prompt appears: the build needs rootful podman (polkit).")
    _row(build_group, "drive-optical-symbolic", "Full ISO",
         "zstd-19 — byte-identical to what CI ships. Slower; use it to "
         "reproduce the published ISO exactly.")
    _row(build_group, "view-list-symbolic", "ISOs (inventory)",
         "Every ISO in output/, newest first, with a fresh or STALE badge — "
         "STALE means the live-env sources changed after that build. Per "
         "ISO: Test in VM, Write to USB (via Impression), Delete.")
    section(
        "Build",
        build_group,
        _body("The first build is slower — it pulls the base image and "
              "clones Titanoboa; later builds are cached. Budget about 30 GB "
              "of free disk for the build scratch. When the log shows Done, "
              "the ISO is in output/ (folder button, top right). Cancel "
              "build stops a build in progress; the password asked for is "
              "your own user password (polkit), not a separate one."))

    # --- testing an install ------------------------------------------------------
    section(
        "Test an install",
        _body("Test in VM boots the ISO in QEMU with a blank disk (session "
              "libvirt, with clipboard, Secure Boot and TPM 2.0). In the "
              "installer pick the DEFAULT partitioning — that creates the "
              "dedicated /var the shipped ISO uses (the layout where the "
              "Flatpak bake matters). After install, reboot, log in, open a "
              "terminal and check:"),
        _cmd(toasts, "flatpak --system remotes",
             "must list flathub, with no opendir error"),
        _cmd(toasts, "flatpak --system list --app | wc -l",
             "about 37 baked apps, right away"))

    # --- CI page ---------------------------------------------------------------
    ci_group = Adw.PreferencesGroup()
    _row(ci_group, "emblem-synchronizing-symbolic", "Rebuild base image",
         "CI builds :candidate (roughly 40–60 min), QEMU smoke-boots it and "
         "— only if green — promotes it to :stable. You are notified at "
         "each stage; Fast test ISO then builds from the new base.")
    _row(ci_group, "send-to-symbolic", "Publish ISO via CI",
         "Full zstd-19 ISO, then the real-install gate, then Internet "
         "Archive plus the site date bump. The gate blocks publishing: an "
         "ISO that fails a real install never reaches the public mirror. "
         "Uses the Build page's base tag (stable or nvidia); an "
         "already-running publish is attached to, never doubled.")
    _row(ci_group, "folder-download-symbolic", "Download + test newest CI ISO",
         "Fetches the newest CI ISO artifact (about 9 GB) into "
         "output/ci-(run)/ and offers to boot it in the test VM — the way "
         "to verify the EXACT bytes CI built before sharing a link.")
    section(
        "CI",
        _body("Remote builds on the repo's GitHub Actions, driven through "
              "the gh CLI (user-level, no password prompts). The Status "
              "group shows when :stable was last promoted, the last publish "
              "run's per-job verdicts (iso, gate, publish), the Internet "
              "Archive link and the changes since the last publish."),
        ci_group,
        _body("Progress arrives as toasts and desktop notifications — keep "
              "the window open while a CI job is monitored. Closing it "
              "stops the monitoring, not the CI job itself."))

    # --- Maintenance page --------------------------------------------------------
    maint_group = Adw.PreferencesGroup()
    _row(maint_group, "computer-symbolic", "Test VMs",
         "The margine-test-* VMs on qemu:///session — a stock virt-manager "
         "watches qemu:///system, so they are invisible there. Console "
         "opens virt-viewer; Clean all removes every test VM and keeps the "
         "template unless you tick the checkbox. Nothing outside the "
         "margine-test- prefix is ever touched.")
    _row(maint_group, "drive-harddisk-symbolic", "Disk usage",
         "Totals for local ISOs, CI downloads and the Titanoboa cache, "
         "each with a one-click reclaim. Rootful podman images are only "
         "inspected on click — that action asks for your password (pkexec).")
    section("Maintenance", maint_group)

    # --- Troubleshooting -----------------------------------------------------------
    section(
        "Troubleshooting",
        _body("The CI page disables its actions with an unavailable "
              "subtitle when gh cannot be used:"),
        _issue(toasts, "gh CLI not found",
               "GNOME-launched apps never have brew's bin dir on PATH — and "
               "even bash -lc skips brew's profile script (it is "
               "interactive-guarded) — so the app probes the known install "
               "locations directly. Install gh with:",
               "brew install gh"),
        _issue(toasts, "gh not authenticated",
               "Authenticate once in a terminal, then reopen this app:",
               "gh auth login"),
        _issue(toasts, "no GitHub origin remote",
               "The repo folder has no GitHub origin. Check what the "
               "remotes point at:",
               "git remote -v"),
        _issue(toasts, "Build fails instantly with exit 126 or 127",
               "pkexec exits 126/127 when the polkit authentication is "
               "cancelled or fails — start the build again and enter your "
               "user password."))

    # --- terminal equivalents ---------------------------------------------------
    section(
        "Same actions from a terminal",
        _body("Everything the buttons do can be run by hand:"),
        _cmd(toasts, "just build-iso-fast", "fast local ISO (zstd-1)"),
        _cmd(toasts, "just build-iso", "full local ISO (zstd-19)"),
        _cmd(toasts, "just test-install-vm",
             "boot the newest local ISO in the test VM"),
        _cmd(toasts, "gh workflow run build-disk.yml -f image_tag=stable",
             "trigger the CI publish flow"))

    clamp = Adw.Clamp(maximum_size=560)
    clamp.set_child(content)
    scroller = Gtk.ScrolledWindow(vexpand=True)
    scroller.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
    scroller.set_child(clamp)

    view = Adw.ToolbarView()
    view.add_top_bar(Adw.HeaderBar())
    view.set_content(scroller)
    toasts.set_child(view)
    dlg.set_child(toasts)
    dlg.present(win)
    # No initial focus: with focus unset, nothing can select-all or yank the
    # scroll position on open (the v1 regression this dialog replaces).
    dlg.set_focus(None)
