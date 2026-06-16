# Kernel benchmark — 2026-06-16

Raw [`margine-bench-kernel.sh`](../../margine-bench-kernel.sh) results and the
generated comparison for **Margine's CachyOS/BORE kernel vs the stock Fedora
kernel**, plus the published chart.

![Margine kernel vs stock Fedora](perf-kernel.svg)

## Conditions

- **Hardware:** AMD Ryzen 5 7640U w/ Radeon 760M (12 threads), laptop, on AC.
- **Governor:** `performance`. sched_ext (scx) schedulers: **off** (stock BORE).
- **Method:** the *same* `margine-bench-kernel.sh` on the *same* laptop, switching
  ostree deployments — Margine vs `ghcr.io/ublue-os/bluefin-dx:stable` — so the
  **only variable is the kernel**. Benchmark tools run in a throwaway Fedora
  distrobox (the host has no `dnf`), so they exercise the real booted kernel.
- **Kernels:** Margine `7.0.12-cachyos1.fc44`, Bluefin/Fedora `7.0.8-200.fc44`
  (each distro's current stable kernel — different trees, can't be version-matched).
- **Thermal control:** 4 runs per OS at varied start temperatures, so the
  *median* start temp matches (Margine ~51–54 °C, Bluefin ~52 °C → comparable).
  Every run ended at the CPU's ~100 °C thermal limit, so both kernels throttle
  equally; absolute numbers are therefore conservative, the relative gap is fair.

## Files

- `margine-cachyos-N.json`, `bluefin-dx-N.json` — raw per-run results
  (parsed metrics + kernel/CPU/governor identity + start/end temperature).
- `perf-kernel.svg` / `perf-kernel.md` — the published comparison (median).

## Published median (and one excluded run)

`margine-cachyos-1.json` is **excluded** from the published median: it was taken
on an older candidate deployment in a separate session and is a 2× outlier on the
context-switch (`perf bench sched pipe`) metric — its value (~7.7 µs) matches
Bluefin's while the other three Margine runs agree at ~4.4 µs. It is kept here for
transparency. The median absorbs it either way; dropping it just tightens the set.

Regenerate the published chart (run from this directory):

```sh
../../margine-bench-compare.py \
  margine-cachyos-2.json margine-cachyos-3.json margine-cachyos-4.json \
  bluefin-dx-*.json \
  --title "Margine kernel vs stock Fedora — same laptop, median of runs" \
  --out-prefix perf-kernel
```

## Headline (median, this hardware)

| Metric | Margine (CachyOS/BORE) | Δ vs stock Fedora |
|--------|------------------------|-------------------|
| Context-switch latency / rate | 4.45 µs/op · 224k ops/s | **~1.8× faster** |
| Thread throughput (events) | 88k | **+54%** |
| Thread latency (avg) | 4.1 ms | **55% lower** |
| Wakeup latency (p50) | 2.08 ms | **43% lower** |
| Sched-messaging | 2.99 s | 9% faster |
| Tail latency (p95 / p99) | — | ~10% **higher** (BORE trades worst-case for common-case) |
