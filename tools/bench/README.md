# Margine bench / diagnostic tools

Host-side scripts you run **on a Margine machine** to characterise the build —
they are *not* baked into the image and never run in CI (`tools/**` is in
`build.yml`'s `paths-ignore`). All are `set -euo pipefail` and
`shellcheck -S warning` clean; the shell scripts are read-only toward host
system state.

The Margine host has no `dnf`/`apt`, so anything that needs extra tooling runs
it inside a **throwaway distrobox container** with a dedicated scratch HOME
(your real `$HOME` is never shared, and a pre-existing same-named container is
reused, never removed).

| Script | What it does | Needs a container? |
|--------|--------------|--------------------|
| `margine-bench-kernel.sh` | Characterises the signed CachyOS/BORE kernel: identity (CONFIG_CACHY/SCHED_BORE/SCHED_CLASS_EXT, `sched_bore` tunable, active scx scheduler, signed bootc deployment) + scheduler latency under load (schbench, optional) + throughput (`perf bench sched messaging`/`pipe`) + thread contention (sysbench), all under a stress-ng background load. Can also emit machine-readable JSON (see below). | yes (perf/sysbench/stress-ng) |
| `margine-bench-compare.py` | Reads two or more `margine-bench-kernel.sh` JSON results and produces a terminal table, a **Markdown table**, and an **SVG bar chart** of relative performance — the "CachyOS vs stock" comparison for the website. Pure stdlib, no pip. | no (just python3) |
| `margine-bench-gaming.sh` | Captures a game session's FPS/frametime via MangoHud logging and summarises avg / 1% low / 0.1% low FPS + frametime (1% low = mean FPS of the slowest 1% of frames by frametime). Prints the exact Steam launch-options string to use. | no |
| `margine-check-nonhidpi.sh` | Verifies Margine's Plymouth/GRUB/GNOME HiDPI tuning degrades gracefully at standard (~96) DPI — flags anything hard-coded for HiDPI that would look wrong on a 1080p display/VM. | no |

## Usage

```bash
# kernel — identity always runs; benchmarks pull a Fedora tooling container on
# first run (several minutes cold). For comparable numbers set the cpufreq
# governor to 'performance' first (the script won't change it for you).
./margine-bench-kernel.sh
#   env: BENCH_RUNTIME=30  BENCH_NO_CONTAINER=1  BENCH_KEEP=1  BENCH_BUILD_SCHBENCH=0
#        BENCH_JSON_OUT=<file>   write machine-readable results (for compare)
#        BENCH_LABEL=<name>      label this run (e.g. margine-cachyos)

# gaming — print the Steam launch options, then summarise the captured log
./margine-bench-gaming.sh steam-options
./margine-bench-gaming.sh summary --latest

# non-HiDPI — read-only diagnostic
./margine-check-nonhidpi.sh
```

Each script's header comment documents its full behaviour, env overrides, and
the exact metrics it reports.

## Comparing kernels → website chart (CachyOS vs stock)

The selling point of Margine is the signed CachyOS/BORE kernel. To produce an
honest, repeatable "Margine vs stock" comparison and a chart for the site:

**1. Measure the SAME way on each OS, on the SAME laptop.** Boot each system,
set the governor to `performance`, and run the identical script. Margine has no
host package manager, so the bench tools run in a throwaway container
automatically; on stock Fedora/Bluefin they install into a container the same
way.

```bash
# On Margine (CachyOS/BORE):
BENCH_LABEL=margine-cachyos BENCH_JSON_OUT=margine.json ./margine-bench-kernel.sh

# Reboot into Bluefin DX (stock Fedora kernel, same stack as Margine minus the kernel):
BENCH_LABEL=bluefin-dx      BENCH_JSON_OUT=bluefin.json  ./margine-bench-kernel.sh

# Reboot into a stock Fedora (Silverblue/Workstation):
BENCH_LABEL=fedora-stock    BENCH_JSON_OUT=fedora.json   ./margine-bench-kernel.sh
```

Tips for numbers you can defend as a claim: plug in the laptop, governor on
`performance`, close other apps, and run each a few times (`BENCH_RUNTIME=30`)
to confirm they're stable. Same kernel build, same hardware — the only variable
between Bluefin DX and Margine is the kernel itself, which is the cleanest A/B.

**2. Generate the comparison + chart:**

```bash
./margine-bench-compare.py margine.json bluefin.json fedora.json \
    --out-prefix perf-kernel
#   --baseline fedora   choose the 1.00× reference (default: a *fedora* run, else last)
#   --subject  margine  choose the highlighted run (default: a *margine*/*cachy* run)
#   --title    "..."    chart/table title
```

This prints a table to the terminal and writes:

* `perf-kernel.md`  — a Markdown table (subject column bold, per-metric delta vs
  baseline) + an embed of the chart, ready to paste into the site or handbook.
* `perf-kernel.svg` — a dark-theme grouped bar chart of **relative** performance
  (baseline = `1.00×`, taller = better, latency inverted so higher is always
  better). Margine bars use the brand accent.

Only metrics reported by **every** run are charted (no apples-to-oranges gaps);
anything missing on one OS is listed as skipped rather than silently dropped.

**3. Put it on the website.** Drop `perf-kernel.svg` into the site's `public/`
and paste the `perf-kernel.md` table/section into the relevant page
(homepage performance section or a handbook/docs page). Keep the `*Measured … on
<hardware>*` caption — dated, hardware-stamped numbers are what make the claim
credible.
