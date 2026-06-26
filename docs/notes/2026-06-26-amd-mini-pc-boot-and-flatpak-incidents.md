# Incident notes: AMD mini-PC live-ISO boot hang + fresh-install Flatpak bake (June 2026)

Two distinct bugs surfaced from the same uBlue forum thread
([#12247](https://universal-blue.discourse.group/t/introducing-margine-os/12247))
by tester **CyberOto** on the same hardware class (AMD Ryzen 8000 / Radeon
780M mini-PCs). They are unrelated in cause but share two themes worth
recording: **the dev host masked both bugs**, and **CI never exercised the
path that broke**.

- **Incident 1 — live ISO hard-hangs on boot.** RESOLVED, PR #221.
- **Incident 2 — fresh install lands with a broken /var/lib/flatpak.** Fixed
  PR #222 (upstream-alignment); definitive confirmation pending the
  real-install CI gate.

---

## Incident 1 — AMD mini-PC live-ISO boot hang (baked `console=ttyS0`)

### Affected hardware
| Machine | CPU | iGPU | RAM | Result |
|---|---|---|---|---|
| Beelink SER8 (mini-PC) | Ryzen 7 8745(H) | Radeon 780M | 32 GB | **HANG** |
| Second AMD desktop | Ryzen 7 8745 | Radeon 780M | — | **HANG** |
| Tuxedo Pulse Gen3 (laptop) | Ryzen 7 7840 | Radeon 780M | — | boots fine |

Discriminators: same 780M iGPU works on the laptop but not the desktops;
**stock Bluefin DX live ISO booted fine on the same desktops.**

### Symptoms
- Margine live ISO: black screen shortly after peripheral init.
- With `quiet rhgb` removed (verbose): the boot **crawls ~30x too slow** —
  every systemd step ~30 s apart, even trivial socket units — reaches the
  initramfs, and **hard-hangs at ~700 s** during `systemd-modules-load`
  (right after the SCSI device handlers emc/rdac/alua). Keyboard then dead,
  no VT switch, no Caps/Num-Lock LED, no SSH, no ping.
- Early ACPI BIOS error: `\_SB.PCI0.GPP5.RTL8._S0W, AE_ALREADY_EXISTS`.
- Rebase to the installed image reached GDM, then froze on login, then disk
  write errors, then unbootable.

### Solutions tried
| Attempt | Result |
|---|---|
| `amd_iommu=off` | no change |
| `nomodeset` / `amdgpu.dc=0` | no change |
| remove `quiet rhgb` | no fix, but revealed the verbose log (the 30x slowdown) |
| Ctrl+Alt+F3 / Caps-Lock LED / SSH / ping | confirmed a true hard hang |
| BIOS UMA = Auto / 8 GB / UMA_AUTO | no change (ruled out RAM/UMA) |
| `processor.max_cstate=1` + remove `console=ttyS0` | booted |
| **remove only `console=ttyS0,115200n8`** | **booted fully, no slowness — THE FIX** |
| stock-Fedora-kernel test ISO, `console=ttyS0` removed | also booted (exonerates the kernel) |

### Hypotheses (and their fate)
1. **CachyOS kernel regression on Ryzen 8000** (amd_sfh GPF / amd_pstate /
   C-state). Investigated with two multi-agent research passes + a
   stock-kernel A/B test ISO. **REFUTED:** the stock-Fedora-kernel ISO hung
   identically and was fixed by the same param.
2. **RAM / UMA-VRAM exhaustion on the 780M.** **REFUTED:** 32 GB RAM, and
   changing the BIOS UMA setting made no difference.
3. **ACPI `_S0W` / Realtek.** Benign, common AM5 ACPI warning; red herring.
4. **Baked `console=ttyS0` stalling on a phantom UART.** Raised early as the
   one karg our ISO bakes that Bluefin's does not. **CONFIRMED** by CyberOto.

### Root cause
The live ISO baked `console=tty0 console=ttyS0,115200n8
systemd.show_status=1` into the default GRUB entries.
`console=ttyS0` was added only so the CI QEMU boot-test could watch the
serial console. On a board that advertises a **phantom 8250 UART** (common
on mini-PCs like the Beelink SER8) the device never drains its TX FIFO, so
every kernel `printk` busy-waits in `serial8250` until a timeout; with
`systemd.show_status` forcing per-unit output that drags the whole boot ~30x
slower and eventually wedges. Bluefin's ISO does not bake `console=ttyS0`,
which is why it booted. The CachyOS kernel was a coincidence, not a cause.

### Resolution
- **PR #221:** removed `console=ttyS0` + `systemd.show_status=1` from the two
  default ISO entries (now `console=tty0` only). CI keeps serial
  observability **without** the harmful karg by extracting the ISO's
  kernel+initrd and direct-booting them (`-kernel/-initrd/-append`, console
  injected there) while `-cdrom` serves the squashfs.
- **PR #220 (audit hardening, same week):** a "verbose, no splash, no serial"
  recovery GRUB entry; bounded the live overlay (`rd.live.overlay.size`);
  refreshed `linux-firmware`/microcode after the kernel swap; zstd-guards on
  the initramfs regen; a squashfs-is-zstd CI assertion; a warn-only 2 GiB
  constrained CI boot pass.
- Follow-up: republish a clean public ISO (the previously published one
  still carries the karg).

---

## Incident 2 — fresh install lands with a broken /var/lib/flatpak

### Affected hardware / scope
Reported on the Beelink SER8 (Ryzen 8745, 32 GB) after a fresh ISO install,
but the analysis concluded it affects **every fresh ISO install** on the
default partitioning (dedicated `/var` btrfs subvol) — not SER8-specific.

### Symptoms (installed system, post-boot)
- `margine-validate-margine-system`: all ~42 BAKE/preinstall apps "NOT
  installed" — "kickstart %post bake silently failed AND preinstall fallback
  hasn't caught it yet".
- `flatpak-preinstall.service`: failed (exit 1), "Start request repeated too
  quickly, restart counter at 3" → permanently failed.
- `flatpak update`: `Warning/error: opendir(refs/remotes): No such file or
  directory`; apps won't start; `sudo flatpak update` hung.

### Investigation + hypotheses
A 24-agent analysis (with adversarial verification) found Margine **diverged
from BOTH Bluefin and Bazzite** on four points of the bake/install path. The
exact on-disk corruption mechanism did **not** fully converge — and, crucially,
**it cannot be settled from the dev host because the host never exercised the
bake path** (its Flatpaks came from the first-boot download fallback, which
masks the bug). The four verified divergences (the actionable truth):

1. **SELinux labels stripped, never restored.** `install-flatpaks.ks` used
   `rsync --filter='-x security.selinux'`. ostree relabels `/var` only once
   at deploy-finalize (before `%post`), so the rsynced repo kept a wrong
   context → confined flatpak denied access to `/var/lib/flatpak/repo`.
   Bluefin does NOT strip; Bazzite strips but then `restorecon`s. Margine did
   neither's safe half.
2. **Bake rsync targeted the per-deployment `.0/var`**, which the booted
   system never mounts as `/var` (runtime `/var` is the stateroot var) —
   plausibly shadowing the bake. (Most-disputed of the four; upstream uses
   the same target but ALSO bakes into the committed image, which Margine
   does not.)
3. **No `disable-fedora-flatpak.ks`** (both upstreams ship it) — Fedora's
   `flatpak-add-fedora-repos` can half-initialize/clobber the system repo.
4. **`flatpak-preinstall.service` had a brittle 3-strike lockout** — one
   transient first-boot failure left it permanently `failed`, so the
   download fallback never recovered.

### Resolution (PR #222 — align to Bluefin/Bazzite)
- `install-flatpaks.ks`: target the real mounted runtime `/var`
  (`/mnt/sysimage/var`), drop the SELinux label-strip, add a loud
  `MARGINE-BAKE-OK/FAIL` marker.
- New `disable-fedora-flatpak.ks` (mask `flatpak-add-fedora-repos`) BEFORE
  the bake; new `flatpak-restore-selinux-labels.ks` (`restorecon`) AFTER it.
- `flatpak-preinstall.service` drop-in: `StartLimitIntervalSec=0` +
  ExecStartPre ensure-flathub + `flatpak repair` → self-healing fallback.

**Honest status:** these are upstream-alignment fixes (verified divergences),
not yet confirmed against a reproduced install. The definitive confirmation
is the real-install CI gate (below).

---

## Cross-cutting: why both shipped, and the CI gaps

- **The dev host masks both bugs.** It has Secure Boot off, a real/normal
  UART (so `console=ttyS0` doesn't stall), and its Flatpaks came from the
  download fallback (not the bake). Never trust the dev host to validate
  either path.
- **No CI ever did a real ISO install + first boot.** `smoke-boot` builds a
  qcow2 directly from the OCI image (skips Anaconda + the kickstart);
  `build-disk` only boots the LIVE session (where `/var/lib/flatpak` is a
  read-only mount that looks fine). `install-flatpaks.ks` had literally never
  run end-to-end in CI.
- **A truncated local ISO sent the first repro attempts down a rabbit hole.**
  A `curl` that died at 6.5/7.9 GB produced an ISO that failed to boot in
  every local QEMU configuration — mistaken for OVMF / `-kernel` problems.
  The `-kernel/-initrd` boot method is fine; the dev host has 4M OVMF.
- **The boot-test's own bug:** it loop-mounted the ISO with `sudo` then
  `cp`'d as the runner user → `Permission denied`. Fixed to extract with
  `xorriso` (no mount/sudo) in PR #221's follow-up.

### Regression guards added
- **Static guard** (`.github/scripts/check-flatpak-fixes.sh`, run in `lint`):
  asserts all four Flatpak invariants + the no-`console=ttyS0` invariant stay
  in place. Cheap, immediate.
- **Real-install gate** (planned): a `build-disk.yml` job that boots the ISO,
  triggers an automated Anaconda install (a dormant `anaconda --kickstart`
  service gated by a CI-only `margine.autoinstall` karg — `inst.ks`/OEMDRV do
  NOT work on this live ISO, its initrd has no anaconda-dracut modules), then
  offline-verifies the installed disk via `qemu-nbd`
  (`/var/lib/flatpak/repo/refs/remotes/flathub` present, app count, SELinux
  labels). This reproduces + permanently guards the class.

### Lessons
- A knob added for **CI/dev convenience** (the serial console) broke **real
  hardware**. Inject test-only knobs at test time, never ship them.
- "Works on our hardware + in CI" is not "works on arbitrary hardware":
  mini-PCs with phantom ACPI/firmware devices are a real, common class.
- Atomic/ostree `/var` semantics + SELinux relabel timing are subtle; mirror
  what two working upstreams (Bluefin, Bazzite) do rather than inventing a
  third way.
