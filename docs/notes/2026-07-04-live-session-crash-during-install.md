# 2026-07-04 — live session dies ("logout") while Anaconda finishes installing

**Symptom.** At the end of a VM install from the published `margine-20260703.iso`
(virt-manager, SB+TPM, 8 GB RAM), the GNOME live session abruptly ends and GDM's
greeter appears — it looks like "Anaconda logged me out". Daniel had seen the
same on earlier ISOs. CRITICAL: a first-time user watching their install would
think it failed.

**It is NOT**: an Anaconda reboot (journal continuous, VM never rebooted), NOT
systemd-oomd / OOM (5.8 Gi available, zram at 117 MB, zero oom lines), NOT the
CI autoinstall unit (karg-guarded), NOT the earlier idle-lock issue (fixed by
zz4 in June — that was a different, superficially identical symptom).

**It IS a gnome-shell SIGSEGV.** Forensics from the live VM (session timeline
via loginctl/journal, then coredumpctl):

```
18:20:09  session 1 (liveuser)  — live desktop
18:20:28  session c1 (root)     — anaconda backend starts
18:43:31  anaconda Installation queue done (1349 s) → Configuration queue
18:43:32  systemd-localed: X11 layout flaps ('us' → '' → 'us' → '')
          ← anaconda's localization tasks touching the LIVE system's locale1
18:43:32-35  o-tiling throws 3× in _show_skip_taskbar_windows:
          "TypeError: global.log is not a function"   (extension.js:3234)
18:43:35  kernel: gnome-shell[2356] segfault ... in libgio-2.0.so
18:43:38  coredumpctl: gnome-shell SIGSEGV, core dumped (32.4 M)
18:43:39  session 1 removed; GDM greeter (c2) spawns    ← the "logout"
18:44:39  anaconda (c1) finishes normally a minute later
```

Native stack (thread 2356): `g_settings_get_enum` ← `update_clock`
(libgnome-desktop) ← `g_settings_real_change_event` ←
`settings_backend_path_changed` — a **use-after-free in GnomeWallClock's
settings listener** while a GSettings change-event storm is in flight. The
storm's driver: anaconda's configuration phase pushing keyboard/locale to the
live session via localed (layout flapping above), with our o-tiling handler
aborting mid-monkey-patch on every skip-taskbar window (Anaconda dialogs) in
the same seconds.

## Fixes shipped

1. **o-tiling hotfix at build** (`build_files/build-margine-extensions.sh`,
   base image): `global.log()` → `console.log()` (GNOME removed `global.log`;
   on GNOME 50 the WARNING branches that call it are always taken, so the
   handler died on every event). Patch applied post-unzip with a loud
   post-check; drop when upstream oliwebd/o-tiling fixes it.
2. **Live session runs without o-tiling** (`live-env/src/build.sh`,
   zz4-margine-live override): the installer session needs zero tiling — the
   highest-surface extension is now not loaded there. Installed systems keep
   the full set.
3. Upstream: issue to oliwebd/o-tiling (global.log). The gnome-desktop
   `update_clock` UAF is upstream GNOME material — coredump stack preserved
   here if we decide to file it.

## Part 2 — the SAME crash also broke the Flatpak bake (found on first boot)

The installed system from this very run booted fine but had NO flatpaks:
`/var/lib/flatpak` contained `app/` (953 M, timestamps of the ISO build) while
`repo/`, `runtime/`, `exports/` were EMPTY dirs stamped 18:43 UTC — the crash
minute — and `/var/log/anaconda` did not exist. Chain, completed:

1. The session died → **slitherer (the WebUI viewer) died with it**.
2. anaconda's live mode **stops when its viewer disappears** (by design:
   `_watch_webui_on_live` → PidWatcher → main-loop quit).
3. That killed the %post chain **mid-rsync of the bake** (alphabetical: app/
   copied, repo/ and runtime/ never) and before the final copy-logs task —
   hence no /var/log/anaconda.
4. `bootc switch` had already completed → the system boots and LOOKS installed.
5. On first boot `flatpak-preinstall` crash-loops forever: remote-add, repair
   and the preinstall all die on `opendir(objects)` — the drop-in's existing
   heals can't fix a repo with no objects/.

**Why the CI gate was green on this exact ISO**: the gate installs headless —
no GNOME session, no crash, scripts complete. Its blind spot is the truncation
class, not the bake location.

Follow-up hardening shipped with this note:
- `flatpak-repo-heal` (new first ExecStartPre): detects the repo-without-
  objects signature and resets /var/lib/flatpak so the heal chain rebuilds it
  — turns "broken forever" into "recovers by downloading".
- Gate: asserts var/log/anaconda + `MARGINE-BAKE-OK` in ks-script logs on the
  installed disk — the truncated-install sensor, cause-agnostic.
- This also most likely explains CyberOto's original broken-flatpaks report.

## Part 3 — re-test WITHOUT o-tiling: the shell still dies → localed masked

Re-test on the fixed fast ISO (zz4 confirmed in-VM: o-tiling not loaded, zero
global.log errors) ended the same way: session gone at the end of the
install, new gnome-shell coredump — this time **SIGABRT** (21:40:05). So
o-tiling was an incidental amplifier, not the trigger: gnome-shell 50.2 dies
under Anaconda's configuration-phase GSettings storm on its own. The storm's
single source is anaconda's localization tasks driving the LIVE system's
locale1 (X11 layout flapping in the journal both runs).

Mitigation ATTEMPTED then REVERTED (2026-07-05): masking systemd-localed did
stop the storm's source, but anaconda-webui's KEYBOARD spoke enumerates and
sets layouts via org.freedesktop.locale1 — masking localed left the
installer's keyboard picker EMPTY and blocked the install entirely (Daniel).
So localed masking is OFF the table. The crash's worst consequence — a
truncated Flatpak bake — already self-heals on first boot (flatpak-repo-heal,
PR #255), so the interim posture is: crash may recur at end-of-install, but
the installed system recovers. A verified, targeted fix still owed — get the
exact coredump backtrace first, do NOT blind-mask services the installer
needs. The o-tiling console.log hotfix remains correct on its own merits.

Upstream: gnome-shell/gnome-desktop crash reproduced twice with different
signals (SEGV in update_clock/g_settings_get_enum, then ABRT) — worth filing
with both coredumps if masking confirms the trigger.

## Part 4 — coredump confirms an UPSTREAM GNOME bug; decision: ship + upstream

The 2026-07-05 coredump (gnome-shell 50.2, SIGSEGV, on the promoted
:stable candidate.20260704, o-tiling NOT loaded) nails it:

```
#0  update_clock              (libgnome-desktop-4.so.2)   <- crash
#1  g_cclosure_marshal_VOID__STRINGv
#5  g_settings_real_change_event
#10 settings_backend_path_changed
#11 g_settings_backend_invoke_closure
#12 g_idle_dispatch
```

`GnomeWallClock.update_clock` (the top-bar clock in libgnome-desktop) derefs
freed/invalid memory when a GSettings change-event is dispatched to it. This is
an UPSTREAM GNOME bug, not Margine code — and gnome-desktop3-44.5-1.fc44 is the
newest build available (no update fixes it).

Trigger (confirmed against anaconda source, pyanaconda/modules/localization/
installation.py `write_x_configuration`): Anaconda's Configuration queue applies
language/keyboard/timezone to the LIVE session. For keyboard it does a
save -> set_layouts(new) -> copy-to-chroot -> set_layouts(restore) dance on the
live systemd-localed (the journal's 'us' -> '' -> 'us' -> '' flap), which
storms dconf; one of those change events lands on the wall clock and it crashes.

Why masking localed was the WRONG fix (reverted, #261): anaconda-webui's
keyboard SPOKE enumerates/sets layouts via the same localed, so masking it left
the installer's keyboard picker empty and blocked the install.

DECISION (Daniel, 2026-07-05): option A — treat as a cosmetic, self-healing
upstream bug and SHIP.
- The crash is at the very END (Configuration phase), AFTER `bootc switch` — the
  OS is already deployed, so the install is not broken, just ends with a session
  logout instead of the completion screen.
- If it truncates the Flatpak bake, flatpak-repo-heal (#255) rebuilds it on first
  boot; the deferred + baked apps download normally. Net: installed system
  recovers on its own.
- File an upstream gnome-shell/gnome-desktop bug with this backtrace + the
  anaconda set_layouts trigger. Revisit a targeted mitigation (do NOT mask
  services the installer needs) once upstream responds or a fixed gnome-desktop
  lands.

Interim user-facing note: a first-boot may spend ~10-15 min populating apps if
the bake was truncated; that is the self-heal, not a failure.

## Lessons

- "Logout at end of install" had TWO distinct root causes months apart
  (idle-lock June, shell segfault July). Same symptom ≠ same bug — get the
  coredump before fixing.
- The live journal is tmpfs: forensics must happen before the VM reboots.
- `journalctl | tail` windows kept missing the trigger seconds; the decisive
  artifacts were `coredumpctl list` + the kernel segfault line.
- Extensions in the LIVE session are pure risk during an install; keep that
  session minimal.
