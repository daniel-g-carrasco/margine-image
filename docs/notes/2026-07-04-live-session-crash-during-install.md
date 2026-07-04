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

## Lessons

- "Logout at end of install" had TWO distinct root causes months apart
  (idle-lock June, shell segfault July). Same symptom ≠ same bug — get the
  coredump before fixing.
- The live journal is tmpfs: forensics must happen before the VM reboots.
- `journalctl | tail` windows kept missing the trigger seconds; the decisive
  artifacts were `coredumpctl list` + the kernel segfault line.
- Extensions in the LIVE session are pure risk during an install; keep that
  session minimal.
