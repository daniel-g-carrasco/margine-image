#!/usr/bin/env python3
"""
margine-bench-compare.py — compare kernel benchmark runs and emit a chart.

Takes two or more JSON result files produced by:

    BENCH_LABEL=margine-cachyos BENCH_JSON_OUT=margine.json ./margine-bench-kernel.sh
    BENCH_LABEL=bluefin-dx      BENCH_JSON_OUT=bluefin.json  ./margine-bench-kernel.sh
    BENCH_LABEL=fedora-stock    BENCH_JSON_OUT=fedora.json   ./margine-bench-kernel.sh

(run the SAME script on each OS, on the SAME laptop, governor=performance), then:

    ./margine-bench-compare.py margine.json bluefin.json fedora.json

and writes three things:

  1. a terminal table (always),
  2. <prefix>.md  — a Markdown table + chart embed, ready to paste into the site,
  3. <prefix>.svg — a grouped bar chart of RELATIVE performance
                    (baseline = 1.00; taller = better, direction-aware).

Pure Python standard library — no matplotlib, no pip, runs anywhere python3 does.
Honesty notes:
  * a metric is only charted/tabled when EVERY run reported it (no apples-to-
    oranges gaps); missing metrics are listed as skipped.
  * the chart normalises each metric against the chosen baseline so "higher is
    better" holds for every bar regardless of whether the raw metric is a
    latency (lower better) or a throughput (higher better).
"""
from __future__ import annotations

import argparse
import html
import json
import sys
from statistics import median

# key, human label, unit, lower_is_better, comparison word for the delta phrase
METRICS = [
    ("sched_pipe_usecs_op",     "Context-switch latency", "µs/op", True,  "faster"),
    ("schbench_p99_us",         "Wakeup latency p99",     "µs",    True,  "faster"),
    ("schbench_p50_us",         "Wakeup latency p50",     "µs",    True,  "faster"),
    ("sched_messaging_total_s", "Sched-messaging time",   "s",     True,  "faster"),
    ("sysbench_lat_avg_ms",     "Thread latency avg",     "ms",    True,  "faster"),
    ("sysbench_lat_95th_ms",    "Thread latency p95",     "ms",    True,  "faster"),
    ("sched_pipe_ops_sec",      "Context-switch rate",    "ops/s", False, "higher"),
    ("sysbench_events",         "Thread events",          "count", False, "more"),
]

# Subject highlighted in the chart/table; baseline = the 1.00 reference.
SUBJECT_HINTS = ("margine", "cachy")
BASELINE_HINTS = ("fedora",)

COLORS = {
    "subject":  "#D97757",   # Margine accent
    "bluefin":  "#0066CC",
    "fedora":   "#6B7280",
    "other":    ("#C2A180", "#7BA05B", "#8E7CC3"),
}


def load(path):
    with open(path, encoding="utf-8") as f:
        d = json.load(f)
    if "label" not in d:
        d["label"] = path.rsplit("/", 1)[-1].removesuffix(".json")
    return d


def pick(labels, hints, default_idx):
    for i, lab in enumerate(labels):
        if any(h in lab.lower() for h in hints):
            return i
    return default_idx


def color_for(label, is_subject, other_iter):
    low = label.lower()
    if is_subject:
        return COLORS["subject"]
    if "bluefin" in low:
        return COLORS["bluefin"]
    if "fedora" in low:
        return COLORS["fedora"]
    return next(other_iter)


def fmt(v):
    if isinstance(v, float):
        return f"{v:.3g}" if v < 100 else f"{v:,.0f}"
    if isinstance(v, int):
        return f"{v:,}"
    return str(v)


def main():
    ap = argparse.ArgumentParser(description="Compare margine-bench-kernel JSON runs.")
    ap.add_argument("json", nargs="+", help="result JSON files (2+)")
    ap.add_argument("--baseline", help="label substring of the baseline (1.00 ref)")
    ap.add_argument("--subject", help="label substring of the highlighted run")
    ap.add_argument("--out-prefix", default="margine-bench-compare",
                    help="output path prefix for .svg / .md (default: %(default)s)")
    ap.add_argument("--title", default="Kernel performance — Margine vs stock")
    args = ap.parse_args()

    if len(args.json) < 2:
        ap.error("need at least two JSON files to compare")

    raw = [load(p) for p in args.json]

    # Guard: refuse identity-only runs (a bench that didn't actually execute).
    # Name the offending FILE so it's obvious which run to redo.
    empty = [args.json[i] for i, r in enumerate(raw)
             if not any(isinstance(r.get(k), (int, float)) for k, *_ in METRICS)]
    if empty:
        sys.exit("error: these files have NO benchmark metrics (identity-only — "
                 "re-run the bench, without interrupting it): " + ", ".join(empty))

    # Aggregate: group runs by label and take the MEDIAN of each metric, so
    # several runs of the same system collapse into one robust column. Run each
    # system 2-3× with the SAME BENCH_LABEL for a defensible, throttling-resistant
    # number; a single run per label still works (median of one = that value).
    groups, order = {}, []
    for r in raw:
        lab = r.get("label", "?")
        if lab not in groups:
            groups[lab] = []
            order.append(lab)
        groups[lab].append(r)

    runs, variance = [], []
    for lab in order:
        g = groups[lab]
        a = {"label": lab, "n_runs": len(g)}
        for k in ("cpu_model", "nproc", "governor", "date", "kernel"):
            a[k] = g[0].get(k)
        for key, name, *_ in METRICS:
            vals = [r[key] for r in g if isinstance(r.get(key), (int, float))]
            if vals:
                a[key] = median(vals)
                if len(vals) >= 2 and median(vals) and \
                        (max(vals) - min(vals)) / median(vals) > 0.25:
                    rng = (max(vals) - min(vals)) / median(vals) * 100
                    variance.append(
                        f"{lab} · {name}: {rng:.0f}% spread across {len(vals)} runs")
        for tkey in ("temp_start_c", "temp_end_c"):
            vals = [r[tkey] for r in g if isinstance(r.get(tkey), (int, float))]
            if vals:
                a[tkey] = median(vals)
        runs.append(a)
    labels = order

    if len(labels) < 2:
        ap.error("need at least two distinct systems (labels) to compare; got: "
                 + ", ".join(labels))

    subj = (pick(labels, [args.subject.lower()], 0) if args.subject
            else pick(labels, SUBJECT_HINTS, 0))
    base = (pick(labels, [args.baseline.lower()], len(runs) - 1) if args.baseline
            else pick(labels, BASELINE_HINTS, len(runs) - 1))
    if base == subj and len(runs) > 1:
        base = next((i for i in range(len(runs)) if i != subj), base)

    # Keep only metrics every run reported (and that are numeric & > 0).
    usable, skipped = [], []
    for key, label, unit, lower, word in METRICS:
        vals = [r.get(key) for r in runs]
        if all(isinstance(v, (int, float)) and v > 0 for v in vals):
            usable.append((key, label, unit, lower, word, vals))
        elif any(v is not None for v in vals):
            skipped.append(label)

    if not usable:
        sys.exit("error: no metric was reported by every run — nothing to compare.")

    # Relative score per metric (direction-aware, baseline = 1.0, higher better).
    def rel(val, baseval, lower):
        return (baseval / val) if lower else (val / baseval)

    meta = runs[subj]
    ctx = (f"{meta.get('cpu_model', 'unknown CPU')} · {meta.get('nproc', '?')} CPUs · "
           f"governor {meta.get('governor', '?')} · {meta.get('date', '')}")

    # Thermal comparability: a run that started much hotter throttles and looks
    # worse, so surface the start temps and warn if they diverge too much.
    temps = {labels[i]: runs[i].get("temp_start_c") for i in range(len(runs))}
    have = {k: float(v) for k, v in temps.items() if isinstance(v, (int, float))}
    if have:
        ctx += " · start temp " + ", ".join(f"{k} {v:.0f}°C" for k, v in have.items())
        if len(have) >= 2 and (max(have.values()) - min(have.values())) > 8:
            spread = max(have.values()) - min(have.values())
            ctx += (f"  ⚠ Δ{spread:.0f}°C — not thermally comparable; "
                    f"re-run from a similar cold start")
            print(f"WARNING: start temps differ by {spread:.0f}°C "
                  f"({', '.join(f'{k} {v:.0f}°C' for k, v in have.items())}). "
                  f"For a defensible claim, re-run both from a similar temperature.\n")

    if any(r["n_runs"] > 1 for r in runs):
        ctx += " · median of " + ", ".join(
            f"{labels[i]} ×{runs[i]['n_runs']}" for i in range(len(runs)))
    for v in variance:
        print(f"NOTE — high run-to-run variance: {v} (consider another run)")

    _terminal(labels, subj, base, usable, rel, args.title, ctx, skipped)
    md_path = args.out_prefix + ".md"
    svg_path = args.out_prefix + ".svg"
    _write_md(md_path, svg_path, labels, subj, base, usable, rel, args.title, ctx, skipped, runs)
    _write_svg(svg_path, labels, subj, base, usable, rel, args.title, ctx)
    print(f"\nWrote {md_path} and {svg_path}")


def _delta_phrase(r, word):
    pct = (r - 1.0) * 100.0
    if abs(pct) < 0.5:
        return "≈ same"
    if pct > 0:
        return f"{pct:.0f}% {word}"
    opp = {"faster": "slower", "higher": "lower", "more": "fewer"}[word]
    return f"{abs(pct):.0f}% {opp}"


def _terminal(labels, subj, base, usable, rel, title, ctx, skipped):
    print(f"\n{title}")
    print(ctx)
    print(f"subject: {labels[subj]}   baseline (1.00): {labels[base]}\n")
    w = max(24, max(len(m[1]) + len(m[2]) + 3 for m in usable))
    header = f"{'Metric':<{w}}" + "".join(f"{lab[:16]:>18}" for lab in labels)
    header += f"{'Δ subj vs base':>18}"
    print(header)
    print("-" * len(header))
    for key, label, unit, lower, word, vals in usable:
        row = f"{label + ' (' + unit + ')':<{w}}"
        for v in vals:
            row += f"{fmt(v):>18}"
        row += f"{_delta_phrase(rel(vals[subj], vals[base], lower), word):>18}"
        print(row)
    if skipped:
        print(f"\nskipped (not reported by every run): {', '.join(skipped)}")


def _write_md(path, svg_path, labels, subj, base, usable, rel, title, ctx, skipped, runs):
    order = [subj] + [i for i in range(len(labels)) if i != subj]
    cols = " | ".join(f"**{labels[i]}**" if i == subj else labels[i] for i in order)
    lines = [
        f"## {title}",
        "",
        f"*{ctx}. Lower is better for latency/time, higher for throughput. "
        f"Baseline for the deltas is **{labels[base]}**. Each run executed the same "
        f"`margine-bench-kernel.sh` under a `stress-ng` background load.*",
        "",
        f"| Metric | {cols} | {labels[subj]} vs {labels[base]} |",
        "|" + "---|" * (len(order) + 2),
    ]
    for key, label, unit, lower, word, vals in usable:
        cells = []
        for i in order:
            cell = fmt(vals[i])
            cells.append(f"**{cell}**" if i == subj else cell)
        delta = _delta_phrase(rel(vals[subj], vals[base], lower), word)
        lines.append(f"| {label} ({unit}) | " + " | ".join(cells) + f" | **{delta}** |")
    lines += [
        "",
        f"![Relative kernel performance — baseline {labels[base]} = 1.00]"
        f"({svg_path.rsplit('/', 1)[-1]})",
        "",
    ]
    if skipped:
        lines.append(f"*Not measured on every system (omitted): {', '.join(skipped)}.*")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


def _write_svg(path, labels, subj, base, usable, rel, title, ctx):
    n_groups, n_series = len(usable), len(labels)
    pad_l, pad_r, pad_t, pad_b = 60, 24, 70, 130
    group_w, bar_gap, group_gap = 46 * n_series, 6, 40
    plot_w = n_groups * group_w + (n_groups - 1) * group_gap
    plot_h = 300
    W = pad_l + plot_w + pad_r
    H = pad_t + plot_h + pad_b

    rels = [[rel(vals[s], vals[base], lower) for s in range(n_series)]
            for (_, _, _, lower, _, vals) in usable]
    rmax = max(1.05, max(max(r) for r in rels) * 1.12)

    def y(v):
        return pad_t + plot_h - (v / rmax) * plot_h

    other_iter = iter(COLORS["other"])
    colors = [color_for(labels[i], i == subj, other_iter) for i in range(n_series)]

    s = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" '
         f'viewBox="0 0 {W} {H}" font-family="Inter,Segoe UI,sans-serif">']
    s.append(f'<rect width="{W}" height="{H}" fill="#0d0f12"/>')
    s.append(f'<text x="{pad_l}" y="30" fill="#f2f2f2" font-size="20" '
             f'font-weight="700">{html.escape(title)}</text>')
    s.append(f'<text x="{pad_l}" y="50" fill="#9aa0a6" font-size="12">'
             f'{html.escape(ctx)}</text>')

    # gridlines + y labels (relative scale)
    for gv in [0.5, 1.0, 1.5, 2.0]:
        if gv > rmax:
            continue
        yy = y(gv)
        dash = "" if gv == 1.0 else ' stroke-dasharray="3 4"'
        col = "#D97757" if gv == 1.0 else "#2a2e35"
        s.append(f'<line x1="{pad_l}" y1="{yy:.1f}" x2="{pad_l + plot_w}" '
                 f'y2="{yy:.1f}" stroke="{col}"{dash} stroke-width="1"/>')
        s.append(f'<text x="{pad_l - 8}" y="{yy + 4:.1f}" fill="#9aa0a6" '
                 f'font-size="11" text-anchor="end">{gv:.1f}×</text>')

    bw = (group_w - (n_series - 1) * bar_gap) / n_series
    for gi, (key, label, unit, lower, word, vals) in enumerate(usable):
        gx = pad_l + gi * (group_w + group_gap)
        for si in range(n_series):
            r = rels[gi][si]
            bx = gx + si * (bw + bar_gap)
            by = y(r)
            bh = pad_t + plot_h - by
            s.append(f'<rect x="{bx:.1f}" y="{by:.1f}" width="{bw:.1f}" '
                     f'height="{bh:.1f}" rx="3" fill="{colors[si]}"/>')
            s.append(f'<text x="{bx + bw/2:.1f}" y="{by - 5:.1f}" fill="#e8e8e8" '
                     f'font-size="10" text-anchor="middle">{r:.2f}×</text>')
        # metric label (wrapped to two lines)
        cx = gx + group_w / 2
        words = label.split()
        mid = (len(words) + 1) // 2
        l1, l2 = " ".join(words[:mid]), " ".join(words[mid:])
        ly = pad_t + plot_h + 18
        s.append(f'<text x="{cx:.1f}" y="{ly}" fill="#c7ccd1" font-size="11" '
                 f'text-anchor="middle">{html.escape(l1)}</text>')
        if l2:
            s.append(f'<text x="{cx:.1f}" y="{ly + 14}" fill="#c7ccd1" '
                     f'font-size="11" text-anchor="middle">{html.escape(l2)}</text>')
        s.append(f'<text x="{cx:.1f}" y="{ly + 30}" fill="#7f868d" font-size="9" '
                 f'text-anchor="middle">({html.escape(unit)})</text>')

    # legend
    lx, ly = pad_l, H - 30
    for si in range(n_series):
        s.append(f'<rect x="{lx}" y="{ly - 10}" width="12" height="12" rx="2" '
                 f'fill="{colors[si]}"/>')
        lab = labels[si] + ("  (baseline)" if si == base else "")
        s.append(f'<text x="{lx + 18}" y="{ly}" fill="#c7ccd1" font-size="12">'
                 f'{html.escape(lab)}</text>')
        lx += 30 + (len(lab) * 7)
    s.append(f'<text x="{pad_l}" y="{H - 10}" fill="#7f868d" font-size="10">'
             f'Higher = better (latency inverted). Baseline = 1.00×.</text>')
    s.append("</svg>")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(s) + "\n")


if __name__ == "__main__":
    main()
