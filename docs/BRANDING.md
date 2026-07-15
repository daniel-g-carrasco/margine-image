# Margine branding — the complete map

**Purpose.** Every place Margine overrides Fedora/Bluefin identity — logos, names,
boot splash, login screen, installer, notifications, CLI — lives here, so changing
one thing later doesn't silently break another. Each entry says **where** it is,
**what** it sets, **how** (the mechanism), and the **gotchas** that bite.

> **Anchors, not line numbers.** This doc points at files and *grep-able strings*
> (keys, function names, literals) instead of line numbers, which rot on every
> edit. To jump to a touchpoint: `grep -n "<anchor>" <file>`.

> **Two build surfaces.** Branding is split across two images:
> - **Base image** (`build_files/…`) → the installed system. Built by `just build`.
> - **Live image** (`live-env/src/…`) → the ISO / installer only. Built on top of
>   the published base by Titanoboa (see `live-env/build-iso-local.sh`).
> A change in `live-env/` is visible **only in the ISO**, never on an installed
> system, and vice-versa. Mixing these up is the #1 source of "I changed it but it
> didn't change."

---

## Golden rules (read these first)

These five cut across almost every touchpoint below:

1. **ostree `/etc` is three-way merged.** Deleting a file under `/etc` is not
   enough if a copy also exists under `/usr/etc` (the ostree factory tree) — the
   merge restores it. Always remove/replace **both**. (Affects shell-init deletes,
   dconf profiles.)
2. **dconf needs `dconf update`.** Writing a keyfile under `/etc/dconf/db/*.d/`
   does nothing until `dconf update` recompiles the binary db. GDM and the user
   session are **separate dconf databases**.
3. **Icon themes need a cache rebuild.** After dropping an SVG/PNG under
   `/usr/share/icons/hicolor/…`, run `gtk-update-icon-cache -f -t
   /usr/share/icons/hicolor`. Use `-t` (ignore-theme-index): a bare `--force`
   silently aborts early in the build when `index.theme` isn't there yet, leaving
   a stale cache and "missing" icons.
4. **GNOME 50+ killed `X-GNOME-Autostart-Phase`.** Setting that key in an
   autostart `.desktop` makes `gnome-session` **skip the entry entirely**. Never
   add it. (Verified 2026-06-04.)
5. **`.desktop Exec=` can't carry shell syntax.** No quotes, `&&`, pipes, or
   redirection — `desktop-file-validate` rejects them and GNOME won't launch them.
   Always point `Exec=` at a wrapper script under `/usr/libexec/…`.

---

## Quick reference

| What you want to change | File | Anchor to grep |
|---|---|---|
| Distro name / version / URLs / accent | `build_files/10-os-identity/install.sh` | `PRETTY_NAME`, `VARIANT_ID`, `LOGO`, `ANSI_COLOR` |
| The square "M" logo (everywhere) | `build_files/50-branding/install.sh` | `margine-logo.svg`, `gtk-update-icon-cache` |
| GNOME **About** logo | `build_files/50-branding/install.sh` | `margine-logo`, `LOGO=` in os-release |
| GNOME About distributor wordmark | `build_files/50-branding/install.sh` | `fedora_logo_med`, `fedora_whitelogo_med` |
| Boot splash (Plymouth) | `build_files/50-branding/install.sh` + `…/kargs.d/10-margine-plymouth.toml` | `plymouth-set-default-theme`, `rhgb` |
| GRUB menu text + HiDPI font | `live-env/src/iso.yaml` + `…/grub2-static/configs.d/05_margine-gfxmode.cfg` | `Install Margine`, `grub2-mkfont`, `margine.pf2` |
| GDM background / logo | `build_files/50-branding/install.sh` | `gdm.d/01-margine-background`, `login-screen` |
| Desktop wallpaper / accent / dock / workspaces | `build_files/50-branding/install.sh`, `build_files/30-gnome-defaults/install.sh` | `picture-uri`, `accent-color`, `favorite-apps`, `num-workspaces` |
| Live ISO "Welcome to Margine" | `live-env/src/build.sh` | `Welcome to Fedora` (the sed targets) |
| Anaconda installer **window icon** | `live-env/src/build.sh` | `AnacondaInstaller`, `_wmid in`, `StartupWMClass` |
| Installer product/storage config | `live-env/src/anaconda/profile.d/margine.conf` | `variant_id`, `default_partitioning` |
| "Secure Boot is disabled" notice | `live-env/src/build.sh` | `margine-live-sb-notice` |
| MOK passphrase / enrollment | `build_files/custom-kernel/install.sh` | `margine-os`, `mok-enroll` |
| First-login bootstrap + notification | `build_files/system_files/etc/xdg/autostart/margine-first-boot*.desktop` | `first-boot-bootstrap`, `first-boot-status` |
| Update notifications | `build_files/system_files/usr/libexec/margine*` (units in `…/usr/lib/systemd/user/`) | `margine-notify` |
| Notification icon on the lock screen | `build_files/system_files/usr/libexec/margine/margine-notify` | `app_icon`, `image-path` |
| fastfetch / MOTD / `/etc/issue` | `build_files/50-branding/install.sh`, `…/fastfetch/margine.jsonc`, `build_files/60-ujust-services/install.sh` | `ascii-logo.txt`, `no-show-user-motd`, `/etc/issue` |

---

## The foundation: one logo, many names

All visual branding resolves to **one asset, `margine-logo`** (the square "M"),
installed once and then aliased to every name Fedora/GNOME hardcodes.

Installed by `build_files/50-branding/install.sh`:

- `/usr/share/icons/hicolor/scalable/apps/margine-logo.svg` ← **primary**; the icon
  *name* `margine-logo` resolves here.
- `/usr/share/pixmaps/margine-logo.png` ← raster fallback for legacy/non-theme
  consumers.

Then **aliased** (copied onto names other software hardcodes — these cannot be
renamed or deleted):

- `fedora-logo-icon.{svg,png}` — hardcoded by **anaconda-live's welcome dialog**
  (`Adw.StatusPage iconName`) and by **gnome-initial-setup** (which maps
  `os-release ID=fedora` → this icon name). Must be *replaced*, never deleted.
- `org.fedoraproject.AnacondaInstaller.{svg,png}` — the installer window icon name
  (see [Anaconda installer icon](#7-anaconda-installer--window-icon-the-hard-one)).
  Lives in the **live image** (`live-env/src/build.sh`), not the base.

**Gotchas**
- The GNOME **About** panel looks up `LOGO=` via the **icon theme only** — the
  `/usr/share/pixmaps` fallback does *not* apply there. The SVG under
  `hicolor/scalable/apps/` is mandatory.
- Rebuild the icon cache after every drop (Golden Rule 3).
- Symbolic icons (e.g. the `start-here-symbolic` override) **cannot embed raster
  images** — GTK4 refuses them. The build validates this (greps for `<image`/
  `data:image/`) and fails if violated.

---

## 1. System identity — os-release & GNOME About

**File:** `build_files/10-os-identity/install.sh` → writes `/usr/lib/os-release`
(`/etc/os-release` is a *relative* symlink to it, so it resolves in any chroot).

Fields that matter for branding:

**Naming policy (2026-07-11, fixed with the DistroWatch submission):** the
public product name is **"Margine OS"**: titles, first mentions, About panel,
directories and stores all use it. **"Margine"** alone is the accepted short
form in running text after the first mention. Technical identifiers never
carry the suffix and never change: `VARIANT_ID=margine` (countme keys on it),
`margine-*` unit/script/icon names, `margine-live-iso-*` Archive identifiers,
the `margine.dev` domain, the ghcr.io/`margine` image name.

| Key | Value | Consumed by |
|---|---|---|
| `NAME` | `Margine OS` | GNOME About title, many tools |
| `PRETTY_NAME` | `Margine OS <ver> (<build-date>)` | login banners, `hostnamectl`, BLS boot entries |
| `VERSION` | `<ver> (Margine OS)` | About |
| `VARIANT` | `Margine OS` | About |
| `VARIANT_ID` | `margine` | **the authoritative discriminator** (anaconda profile, scripts, countme) — do not change |
| `ID` | `fedora` | kept for bootc-image-builder / tooling compat — **do not change** |
| `ID_LIKE` | `bluefin` | provenance |
| `LOGO` | `margine-logo` | GNOME About logo (icon-theme lookup) |
| `ANSI_COLOR` | `0;38;2;232;186;0` | terminal accent = **#E8BA00** (the Margine yellow) |
| `HOME_URL` / `DOCUMENTATION_URL` | `https://margine.dev` / `/docs` | About "Website", links |
| `SUPPORT_URL` / `BUG_REPORT_URL` | GitHub issues | About links |
| `DEFAULT_HOSTNAME` | `margine` | first-boot hostname |

**About panel extras** (`build_files/50-branding/install.sh`):
- The lower **distributor wordmark** uses two *hardcoded* filenames from
  `gnome-control-center.spec` — replace, don't rename:
  `/usr/share/pixmaps/fedora_logo_med.png` (light) and `fedora_whitelogo_med.png`
  (dark). These are **horizontal wordmarks**, not the square logo.
- Stray Fedora pixmaps (`fedora-logo*.png`, `system-logo-white.png`, etc.) are
  deleted to avoid clutter; `fedora-logo-icon` is the one exception (replaced, see
  foundation).

**Gotchas**
- `ID` stays `fedora` on purpose. Detect Margine via `VARIANT_ID=margine`.
- Identity (section `10-`) must run **before** branding (section `50-`); the logo
  aliasing and About config assume os-release is already Margine.
- About reads only `NAME`, `PRETTY_NAME`, `VARIANT`, `LOGO` from os-release; other
  fields come from elsewhere.

---

## 2. Plymouth boot splash

**Theme name:** `margine` → `/usr/share/plymouth/themes/margine/`
(`margine.plymouth` + `margine.script` + `watermark.png`).

**Mechanism** (`build_files/50-branding/install.sh`):
- Installs `plymouth-plugin-script` (the script-based theme needs
  `libply-splash-graphics.so`).
- Copies the three theme files from in-repo `build_files/50-branding/assets/plymouth/`.
- `plymouth-set-default-theme margine`.
- **Regenerates the initramfs** with `dracut --force --zstd --no-hostonly
  --no-hostonly-cmdline --add ostree` for every kernel — the theme is embedded
  in the initramfs, so this is mandatory at build.

**Kargs** (`build_files/system_files/usr/lib/bootc/kargs.d/10-margine-plymouth.toml`):
`rhgb quiet plymouth.ignore-serial-consoles` — `rhgb` enables graphical splash;
`ignore-serial-consoles` stops Plymouth from treating a VM serial console as
headless and skipping the splash.

**Gotchas**
- `bootc upgrade` does **not** re-embed the theme — it's baked into the initramfs at
  build time only.
- `--add ostree` is required on bootc/ostree or switch-root fails.
- Don't drop `plymouth.ignore-serial-consoles` or VMs lose the splash.

---

## 3. GRUB / boot menu

**Menu text** (`live-env/src/iso.yaml`): entries explicitly read **"Install
Margine"** (+ *Basic Graphics Mode*, + *verbose, no splash, no serial*, +
*Enroll Secure Boot key (MokManager)*). The ISO volume label must stay
`Margine-Live` (the CDLABEL the boot config references).

**HiDPI font** — GRUB has no DPI scaling, so the only legibility lever is a baked
large font:
- Built in `build_files/50-branding/install.sh` with
  `grub2-mkfont -s 36 -n "Margine"` → `margine.pf2`, shipped under
  `…/bootupd/grub2-static/fonts/`.
- Selected in `…/grub2-static/configs.d/05_margine-gfxmode.cfg` via
  `gfxterm_font="Margine Regular 36"`, `gfxpayload=keep`.
- Uses **Noto Sans Mono** (has box-drawing glyphs U+2500–25FF; Liberation Mono
  doesn't → menu borders render as `?`).

**Gotchas**
- `bootupd` renders `grub.cfg` from the static configs only at install /
  `bootupctl install`, **not** on `bootc upgrade`. Existing installs must run
  `ujust margine-grub-hidpi` once to pick up the font.
- `gfxpayload=keep` (native res) beats mode-switching, which is flaky on AMD
  amdgpu UEFI.

---

## 4. GDM / login screen

**File:** `build_files/50-branding/install.sh` → dconf db `gdm.d/` (compiled with
`dconf update`; GDM uses its **own** dconf profile at `/etc/dconf/profile/gdm`).

- **Background** (`gdm.d/01-margine-background`): `picture-uri[-dark]` →
  `/usr/share/backgrounds/margine/margine.png`, `picture-options='zoom'`,
  `primary-color='#000000'`.
- **Greeter logo** (`gdm.d/02-margine-logo`): `[org/gnome/login-screen] logo=''`
  — **intentionally empty**, and **locked** (`gdm.d/locks/…`). The Margine mark is
  a wide banner; GDM would stretch it across the password field. Disabled is
  cleaner.

**Gotchas**
- GDM dconf ≠ user-session dconf. Edit the `gdm.d/` db, not the user one.
- The wallpaper must live under `/usr/share/` (mounted before /home at greeter
  time).
- Run `dconf update` or GDM keeps the old compiled db.

---

## 5. Desktop defaults (installed system)

**Wallpaper** (`build_files/50-branding/install.sh`): gschema override
`/usr/share/glib-2.0/schemas/zz1-margine.gschema.override` →
`picture-uri[-dark]` = `/usr/share/backgrounds/margine/margine.png`. Named **zz1**
so it loads *after* Bluefin's `zz0`. A compat symlink
`autumn-leaves.png → margine.png` keeps old user dconf working.

**Accent / dock / workspaces** (`build_files/30-gnome-defaults/install.sh`):
- `accent-color='yellow'` (GNOME 47/48+; safe no-op on older).
- `favorite-apps` = 5-app dock (`zen, thunderbird, nautilus, bazaar, ptyxis`) — the
  intentional 5-app set, not Bluefin's 10.
- `num-workspaces=5` + `dynamic-workspaces=false` → **fixed 5 workspaces**
  (standing preference; do not revert to 10/dynamic).

**Gotcha:** after editing any `.gschema.override`, `glib-compile-schemas
/usr/share/glib-2.0/schemas` must run (the build does this).

---

## 6. Live ISO — "Welcome to Margine"

**File:** `live-env/src/build.sh` (live image only). anaconda-live ships a GJS
welcome app + an autostart `.desktop`, both saying "Welcome to Fedora":
- GJS source patched: `sed 's/Welcome to Fedora/Welcome to Margine/g'` on
  `…/anaconda/gnome/fedora-welcome` (and `…/org.fedoraproject.welcome-screen`).
- Autostart `Name=` patched: `s/^Name=Welcome to Fedora$/Name=Welcome to Margine/`.
- **Last-resort fallback** greps `/usr/share/anaconda` + `/etc/xdg/autostart` for
  the string and patches whatever it finds (survives anaconda file moves).

**Gotchas**
- Anaconda **moves/renames** these files between releases — that's why the script
  tries multiple paths + a grep fallback. If a future anaconda breaks the rebrand,
  extend the path list, don't hardcode one.
- The dialog **title** reads os-release `NAME` (already "Margine"); the
  alt-tab/overview label reads the `.desktop Name=` — both are handled.
- The dialog **icon** is `fedora-logo-icon` (provided by the base image, see
  foundation).

---

## 7. Anaconda installer — window icon (the hard one)

> This one has bitten us repeatedly. Read the whole thing before touching it.

**Goal:** the installer window shows the Margine logo (not a generic placeholder)
in the overview/dock, with the label "Install Margine" instead of "Anaconda Web
UI".

**How GNOME picks a window's icon (Wayland):** it matches the window's **app_id**
(== Wayland `app_id`, the modern WM_CLASS) to a `.desktop` by either
(a) a `.desktop` whose `StartupWMClass=` equals the app_id, or
(b) a `.desktop` whose **basename** equals `<app_id>.desktop`. It then shows that
`.desktop`'s `Icon=`. **`QIcon::fromTheme` / `setWindowIcon` are ignored** by the
overview on Wayland — only the in-window titlebar uses them.

**The installer engine** is `slitherer` (a Qt6 webengine running anaconda-webui).
It calls `setDesktopFileName("org.fedoraproject.AnacondaInstaller")`. On Qt6
Wayland that value **becomes the app_id** → the real app_id is almost certainly
`org.fedoraproject.AnacondaInstaller`. The packages ship **no** matching
`.desktop`: anaconda ships only `liveinst*.desktop` + welcome-screen, and the
`slitherer` RPM ships **no `.desktop`/icon at all** (verified by inspecting the
built live image, 2026-06-30). With no `<app_id>.desktop` present, nothing matched
→ generic placeholder + "Anaconda Web UI" label.

**The fix** (`live-env/src/build.sh`, anchors `AnacondaInstaller`, `_wmid in`):
1. Alias `margine-logo` onto the icon name the window expects, in **two sizes**
   (SVG can render blank on the overview's raster badge):
   `…/hicolor/scalable/apps/org.fedoraproject.AnacondaInstaller.svg` and
   `…/256x256/apps/org.fedoraproject.AnacondaInstaller.png`, then refresh the cache.
2. Ship a **NoDisplay window-matcher `.desktop` for every realistic app_id** —
   `slitherer`, `org.fedoraproject.AnacondaInstaller`, `anaconda-webui`,
   `org.fedoraproject.Anaconda` — each `Icon=margine-logo`. Whichever the real
   app_id is, one matches.
3. After `anaconda-live` installs, `desktop-file-edit` its `liveinst.desktop`:
   `Icon=margine-logo` + `StartupWMClass=slitherer` (the Aurora-proven path; covers
   an XWayland fallback where the app_id would be the binary name `slitherer`).

**VERIFIED WORKING 2026-07-04** — Daniel confirmed the Margine icon on the
Anaconda WebUI window on the published `margine-20260703.iso` (the multi-matcher
build). Do not remove any of the three layers above without re-testing on a
fresh ISO in the SB test VM.

**Gotchas**
- **Ordering:** the matchers + icon alias run *before* the `dnf install
  anaconda-live anaconda-webui …` (note: `slitherer` is **not** installed
  explicitly — it arrives as a dependency selected by `webui_web_engine =
  slitherer` in `margine.conf`). That's currently safe **only because those
  packages ship none of these files** (verified). If a future anaconda/
  slitherer starts shipping `org.fedoraproject.AnacondaInstaller.desktop` or that
  icon, the dnf install will **clobber** our versions — then move the alias +
  matcher block to *after* the dnf install. (Re-verify with
  `rpm -ql slitherer anaconda-core anaconda-webui | grep -E 'desktop|icons'` inside
  the built live image.)
- **Get ground truth if it ever regresses:** boot the ISO, open the installer, then
  `Alt+F2 → lg → Windows` tab and read the window's `wm-class`/`app` — that is the
  definitive app_id. `xprop WM_CLASS` only works if it's an XWayland window.
- Don't bother with `setWindowIcon`/theme icon hacks — the overview ignores them.
- `liveinst.desktop` is renamed to `anaconda.desktop` by livesys at boot; the
  `StartupWMClass` edit survives the rename.

**Installer config** (`live-env/src/anaconda/profile.d/margine.conf`): profile id
`margine`, detected by `os_id=fedora` **and** `variant_id=margine`; BTRFS +
`zstd:1`, `default_partitioning` enforced (don't add explicit `part` directives —
anaconda-webui v68 then shows CUSTOM); hidden Network/Password/User spokes (WebUI
handles them). The `%include` post-scripts are wired from
`live-env/src/anaconda/interactive-defaults.ks`.

---

## 8. Live ISO — "Secure Boot is disabled" notice

**File:** `live-env/src/build.sh` (anchor `margine-live-sb-notice`).
A one-shot autostart (`/etc/xdg/autostart/margine-live-sb-notice.desktop` →
`/usr/libexec/margine-live-sb-notice`) that, **only in the live session and only
if SB is off** (`mokutil --sb-state`), shows a `zenity --info` explaining that
Margine supports Secure Boot, how to enroll (boot-menu MokManager or first-boot,
passphrase `margine-os`), and links the docs. Idempotent via a marker in
`$XDG_RUNTIME_DIR` (falls back to `/tmp`).

**Gotchas**
- It uses a **plain `zenity --info`** (the default info icon). An earlier
  `--icon-name=margine-logo` was reverted — Daniel did **not** want the Margine
  logo inside the dialog body.
- The zenity *overview* icon (the taskbar/alt-tab entry for the dialog window) is
  still generic — zenity gives no control over its Wayland app_id. Fixing that
  needs replacing zenity with a tiny Adwaita app whose app_id we own. **Deferred.**
- Live-only: the autostart entry exists on the ISO, never on the installed system.

---

## 9. Secure Boot / MOK (installed system)

**File:** `build_files/custom-kernel/install.sh`.
- **Passphrase:** `margine-os` — **public by design** (printed on the ISO + docs;
  users type it into MokManager). Only the *signing key* is secret.
- Kernel + all modules (incl. NVIDIA) signed with the Margine MOK at build; a
  sha256 check fails the build if the kernel changes after signing. One key → one
  enrollment.
- Installed cert: `/usr/share/cert/MOK.der`. A one-shot `mok-enroll.service` imports
  it **only if** SB is on and the key isn't already enrolled; idempotency marker
  `/var/.mok-enrolled`.
- ISO offers `Enroll Secure Boot key (MokManager)` (chainloads `mmx64.efi`) so the
  key can be enrolled from the boot menu before install.

**Gotcha:** the installer stages its own MOK cert via
`…/anaconda/post-scripts/secureboot-enroll-key.ks`; the installed-system path
(`/usr/share/cert/MOK.der` + `mok-enroll.service`) is separate. See the handbook
for the user-facing provenance/SB docs ([[handbook-sync-mechanism]]).

---

## 10. First-login experience & notifications (installed system)

All under `build_files/system_files/`. All autostart entries follow Golden Rules
4 & 5 (no `X-GNOME-Autostart-Phase`; `Exec=` → a `/usr/libexec` wrapper).

- **Bootstrap** (`etc/xdg/autostart/margine-first-boot.desktop` →
  `usr/libexec/margine/first-boot-bootstrap`): runs `ujust margine-bootstrap
  unattended` once (home layout, extensions, keybindings, defaults). Idempotent
  marker `~/.config/margine/bootstrapped`.
- **First-boot status** (`…/margine-first-boot-status.desktop` →
  `usr/libexec/margine-first-boot-status`): notifies if `flatpak-preinstall.service`
  is still installing the deferred heavy apps ("installing extra apps… ~5–15 min"),
  and "Margine is ready" when done. Marker `~/.cache/margine/first-boot-notified`.
- **Upgrade notify** (`usr/lib/systemd/user/margine-upgrade-notify.service`):
  post-reboot **confirmation** — at login, if the booted deployment digest
  differs from the recorded one, toasts "Margine updated / Now running: …".
  The "reboot to apply" role belongs to staged-update notify, not here. State
  advances only after the notification succeeds, so a missed toast retries at
  the next login.
- **Staged-update notify** (`…/margine-staged-update-notify.{timer,service}` →
  `usr/libexec/margine/staged-update-notify`): timer is `OnStartupSec=20min` +
  `OnCalendar` at 09/13/17/21 with `Persistent=true` (wall-clock on purpose —
  monotonic `OnUnitActiveSec` never fires on a suspending laptop). The script
  posts three distinct notice classes: (1) "Update ready" once per staged
  checksum, at the first tick that sees it; (2) a once-per-day "staged for N
  days" nag only once the staged deployment is ≥2 days old; (3) a once-per-app
  notice when the update watchdog excludes an extra-data app.

**Gotchas**
- Notifications go through **`margine-notify`** (see section 12) — not
  `notify-send`. Only `margine-upgrade-notify.service` is actually bound to
  `graphical-session.target`; the timer and the autostart entries can tick
  without a session, and headless safety comes from the scripts themselves
  (a failed notification exits non-zero and the stamp/marker is not written).
- Every notifier is idempotent via a marker — don't remove the marker checks or
  users get spammed each login.

---

## 11. CLI branding

**File:** `build_files/50-branding/install.sh` + `60-ujust-services/install.sh`.

- **fastfetch:** ASCII logo `/usr/share/margine/ascii-logo.txt`, config
  `…/fastfetch/margine.jsonc` (logo color `yellow`), wired as the system default
  via a `/etc/fastfetch/config.jsonc` symlink.
- **MOTD off:** Bluefin's tipline is suppressed by pre-creating
  `/etc/skel/.config/no-show-user-motd`; the Bluefin shell-init files
  (`ublue-motd.sh`, `ublue-fastfetch.sh`, `90-bluefin-starship.sh`,
  `91-bluefin-aliases.sh`) are deleted from **both** `/etc/profile.d` and
  `/usr/etc/profile.d` (Golden Rule 1).
- **`/etc/issue`:** first line `Margine \r (\m) — Bluefin DX + CachyOS signed
  kernel`, second line `\d \t` (emergency console only).
- **ujust:** recipes live in `build_files/60-custom.just`, mostly under
  `[group('Margine')]` (`margine-bootstrap`, `margine-ai`, `margine-test-vm`, …;
  `margine-gaming` sits under `[group('Gaming')]`), discoverable via
  `ujust --list`.

---

## 12. Notification icons — the lock screen trap

**Symptom (found 2026-07-15, GNOME 50):** every Margine notification showed the
Margine logo in the tray/banner but the generic `application-x-executable`
gears on the **lock screen**, for all our notifiers at once.

**Root cause (wire-verified with `dbus-monitor`):** libnotify's `notify-send`
sends the fdo `Notify` call with the **`app_icon` field empty** and carries
`--icon` only in the `image-path` **hint**. GNOME Shell renders two different
icons:
- the **notification's own icon** (tray banner + message list) comes from the
  `image-data`/`image-path` hints → looked right;
- the **source icon** — the ONLY thing the lock screen shows — comes from the
  `app_icon` field (or a matching `.desktop` app) and **never** from
  `image-path` → empty → `St.Icon` falls back to `application-x-executable`.

**Fix:** `usr/libexec/margine/margine-notify` — a notify-send stand-in that
calls `Notify` over D-Bus (gdbus) with **both** `app_icon` and `image-path`
set. All Margine notifiers (staged-update, upgrade, staleness, first-boot
status) go through it. Matrix-tested on the lock screen 2026-07-15: themed
name, absolute path and Adwaita icons via notify-send all fail; the same
themed name via `app_icon` shows the logo.

**Gotchas**
- **Don't "simplify" back to `notify-send`** — its empty `app_icon` is
  hardcoded upstream; every regression here reintroduces the gears.
- **`desktop-entry` hints are not a substitute:** sources attributed to a
  `.desktop` via hint never appeared on the lock screen at all in the same
  tests (twice). `-d` in margine-notify only adds in-session app attribution
  (e.g. Bazaar for first-boot status), it does not fix the lock screen alone.
- The `--` in the helper's gdbus call is load-bearing: without it gdbus parses
  the `-1` expire-timeout as an option.
- Upstream: GNOME Shell `js/ui/unlockDialog.js` binds `source.icon` with
  `fallback_icon_name: 'application-x-executable'`; `notificationDaemon.js`
  only sets the source icon from `app_icon` (`_iconForNotificationData(appIcon)`)
  when the source has no app. Same class of bug reported against GSConnect in
  2019 (grey gear on lock screen) — this is old, unfixed upstream behavior.


---

## When you add a NEW branding touchpoint

1. Decide the surface: installed system (`build_files/`) or ISO (`live-env/src/`)?
2. If it's an icon: install the SVG under `hicolor/scalable/apps/`, add a raster
   size if anything renders it as a small badge, then rebuild the cache (`-f -t`).
3. If it's dconf: write the keyfile, then `dconf update`; remember GDM is a
   separate db; consider a lock if users shouldn't override it.
4. If it's an autostart `.desktop`: no `X-GNOME-Autostart-Phase`; `Exec=` a
   wrapper; `desktop-file-validate` it.
5. If it reuses a name Fedora hardcodes (logos, icon names): **replace, don't
   delete** — and note *who* hardcodes it here.
6. If it's a window icon: confirm the real Wayland **app_id** (`Alt+F2 → lg →
   Windows`) before shipping a matcher; don't guess.
7. **Add a row to this doc.** A touchpoint that isn't here is a touchpoint that
   gets broken later.

---

*Source map assembled 2026-07-01 from a full sweep of `build_files/` and
`live-env/`. Re-verified claim-by-claim against the code 2026-07-15 (stale
notifier semantics, timer schedule, anchors and package lists corrected; the
icon-cache `-t` rule is now actually enforced in `50-branding`). Line numbers
deliberately omitted — grep the anchors.*
