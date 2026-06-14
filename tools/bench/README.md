# Margine bench / diagnostic tools

Host-side scripts you run **on a Margine machine** to characterise the build —
they are *not* baked into the image and never run in CI (`tools/**` is in
`build.yml`'s `paths-ignore`). All three are read-only toward host system
state, `set -euo pipefail`, and `shellcheck -S warning` clean.

The Margine host has no `dnf`/`apt`, so anything that needs extra tooling runs
it inside a **throwaway distrobox container** with a dedicated scratch HOME
(your real `$HOME` is never shared, and a pre-existing same-named container is
reused, never removed).

| Script | What it does | Needs a container? |
|--------|--------------|--------------------|
| `margine-bench-kernel.sh` | Characterises the signed CachyOS/BORE kernel: identity (CONFIG_CACHY/SCHED_BORE/SCHED_CLASS_EXT, `sched_bore` tunable, active scx scheduler, signed bootc deployment) + scheduler latency under load (schbench, optional) + throughput (`perf bench sched messaging`/`pipe`) + thread contention (sysbench), all under a stress-ng background load. | yes (perf/sysbench/stress-ng) |
| `margine-bench-gaming.sh` | Captures a game session's FPS/frametime via MangoHud logging and summarises avg / 1% low / 0.1% low FPS + frametime (1% low = mean FPS of the slowest 1% of frames by frametime). Prints the exact Steam launch-options string to use. | no |
| `margine-check-nonhidpi.sh` | Verifies Margine's Plymouth/GRUB/GNOME HiDPI tuning degrades gracefully at standard (~96) DPI — flags anything hard-coded for HiDPI that would look wrong on a 1080p display/VM. | no |

## Usage

```bash
# kernel — identity always runs; benchmarks pull a Fedora tooling container on
# first run (several minutes cold). For comparable numbers set the cpufreq
# governor to 'performance' first (the script won't change it for you).
./margine-bench-kernel.sh
#   env: BENCH_RUNTIME=30  BENCH_NO_CONTAINER=1  BENCH_KEEP=1  BENCH_BUILD_SCHBENCH=0

# gaming — print the Steam launch options, then summarise the captured log
./margine-bench-gaming.sh steam-options
./margine-bench-gaming.sh summary --latest

# non-HiDPI — read-only diagnostic
./margine-check-nonhidpi.sh
```

Each script's header comment documents its full behaviour, env overrides, and
the exact metrics it reports.
