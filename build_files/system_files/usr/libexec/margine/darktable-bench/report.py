#!/usr/bin/python3
"""Records and report for `ujust margine-darktable-bench`.

  report.py record LOG SAMPLES CONFIG IMAGE SIZE TAG ATTEMPT WALL RC QUIET_OK
                   QUIET DISTURB KFAULT AC PROFILE CPU_MAX GPU_MAX CLOCKS0 CLOCKS1
      parse one darktable-cli run and print it as a JSON line
  report.py line JSON      one-line summary of a run (for the live log)
  report.py report DIR     markdown report from DIR/runs.jsonl
"""
import json
import math
import os
import re
import statistics
import sys

SLEPT_S = 2.0   # boot clock ahead of the monotonic one by more: the system slept


def record(a):
    (logf, samples, c, img, size, tag, attempt, wall, rc, quiet_ok, quiet, disturb, kfault,
     ac, prof, cpu_max, gpu_max, clocks0, clocks1) = a
    text = open(logf, errors="replace").read()
    mods = {}
    for m in re.finditer(r"took ([0-9.]+) secs .*?processed `([^']+)' on (CPU|GPU)( with tiling)?", text):
        t, name, dev, tiled = float(m.group(1)), m.group(2), m.group(3), bool(m.group(4))
        e = mods.setdefault(name, {"t": 0.0, "dev": dev, "tiled": False})
        e["t"] += t
        e["tiled"] |= tiled
    pipe = re.findall(r"pixel pipeline processing took ([0-9.]+)", text)
    unified = re.findall(r"UNIFIED MEM SIZE:\s+(\d+) MB", text)
    s = [line.split() for line in open(samples) if len(line.split()) == 3]
    d = json.loads(disturb)
    m0, b0 = (float(x) for x in clocks0.split())
    m1, b1 = (float(x) for x in clocks1.split())
    slept = (b1 - b0) - (m1 - m0) > SLEPT_S
    disturbed = d["other_cpu_pct"] > float(cpu_max) or d["other_gpu_pct"] > float(gpu_max)
    print(json.dumps({
        "config": c, "image": img, "size": size, "tag": tag, "attempt": int(attempt),
        "wall": round(float(wall), 3), "pipeline": float(pipe[-1]) if pipe else None, "rc": int(rc),
        "opencl": "AVAILABLE and ENABLED" in text,
        "unified_mb": int(unified[-1]) if unified else None,
        "gpu_modules": sum(1 for m in mods.values() if m["dev"] == "GPU"),
        "cpu_modules": sum(1 for m in mods.values() if m["dev"] == "CPU"),
        "tiled_modules": sorted(n for n, m in mods.items() if m["tiled"]),
        "modules": {n: round(m["t"], 3) for n, m in mods.items()},
        "module_dev": {n: m["dev"] for n, m in mods.items()},
        "cpu_temp_max": max((int(x[0]) for x in s), default=None),
        "gpu_temp_max": max((int(x[1]) for x in s), default=None),
        "quiet_before": quiet_ok == "0", "quiet": quiet, "ac": ac, "profile": prof,
        "other_cpu_pct": d["other_cpu_pct"], "other_gpu_pct": d["other_gpu_pct"], "other_top": d["top"],
        "kernel_fault": kfault.strip(), "slept": slept, "disturbed": disturbed,
        "valid": (int(rc) == 0 and bool(pipe) and not disturbed and not kfault.strip()
                  and not slept and ac in ("11", "00")),
    }))


def line(r):
    if r["valid"]:
        state = "ok"
    else:
        why = []
        if r["slept"]:
            why.append("system slept")
        if r["disturbed"]:
            why.append(f"other programs {r['other_top']}")
        if r["kernel_fault"]:
            why.append(r["kernel_fault"])
        if r["ac"] not in ("11", "00"):
            why.append("power source changed")
        if r["rc"] != 0 or r["pipeline"] is None:
            why.append(f"darktable-cli failed (rc {r['rc']})")
        state = "DISCARDED: " + "; ".join(why)
    return (f"{r['config']:10} {r['image']} {r['size']:6} {r['tag']:6} "
            f"pipeline={r['pipeline']}s wall={r['wall']}s gpu/cpu modules={r['gpu_modules']}/{r['cpu_modules']} "
            f"others cpu={r['other_cpu_pct']}% gpu={r['other_gpu_pct']}% {state}")


def fmt(x):
    return "-" if x is None else f"{x:.2f}s"


def report(out):
    runs = [json.loads(x) for x in open(os.path.join(out, "runs.jsonl")) if x.strip()]
    env = open(os.path.join(out, "environment.txt")).read().strip()
    measured = [r for r in runs if r["tag"] != "warmup"]
    valid = [r for r in measured if r["valid"]]
    configs = list(dict.fromkeys(r["config"] for r in runs))
    images = list(dict.fromkeys(r["image"] for r in runs))
    sizes = list(dict.fromkeys(r["size"] for r in measured))
    p = print

    p("# darktable benchmark: CPU against GPU\n")
    p("```\n" + env + "\n```\n")
    p(f"Measured runs: {len(measured)}, valid {len(valid)}, discarded {len(measured) - len(valid)}.\n")
    p("`cpu` is darktable without OpenCL; `gpuNNNaX` uses the GPU through ROCm with NNN/100 of the RAM "
      "as its share and advantage X. `full` is a full-resolution export, `screen` a 2560 px render, "
      "close to what the darkroom does when a photo opens.\n")

    speedups = {c: [] for c in configs}
    for size in sizes:
        for img in images:
            rows = {c: [r for r in valid if r["config"] == c and r["image"] == img and r["size"] == size]
                    for c in configs}
            if not any(rows.values()):
                continue
            cpu = rows.get("cpu") or []
            cpu_med = statistics.median([r["pipeline"] for r in cpu]) if cpu else None
            p(f"## {img}, {'full resolution export' if size == 'full' else '2560 px render'}\n")
            p("| configuration | runs | median | min | max | against CPU | GPU memory | on the CPU |")
            p("|---|---|---|---|---|---|---|---|")
            for c in configs:
                rs = rows[c]
                if not rs:
                    p(f"| {c} | 0 | - | - | - | - | - | - |")
                    continue
                v = [r["pipeline"] for r in rs]
                med = statistics.median(v)
                rel = "-"
                if cpu_med and c != "cpu":
                    f = cpu_med / med
                    speedups[c].append(f)
                    rel = f"{f:.2f}x " + ("faster" if f >= 1 else "slower")
                on_cpu = sorted(m for m, d in rs[-1]["module_dev"].items() if d == "CPU") if c != "cpu" else []
                p(f"| {c} | {len(rs)} | {fmt(med)} | {fmt(min(v))} | {fmt(max(v))} | {rel} | "
                  f"{(str(rs[0]['unified_mb']) + ' MB') if rs[0]['unified_mb'] else '-'} | "
                  f"{', '.join(on_cpu) or '-'} |")
            p("")

    p("## Summary\n")
    ranked = []
    for c in configs:
        if c == "cpu" or not speedups[c]:
            continue
        g = math.exp(sum(math.log(x) for x in speedups[c]) / len(speedups[c]))
        ranked.append((g, min(speedups[c]), c))
        p(f"- **{c}**: {g:.2f}x the CPU on average (geometric mean), "
          f"from {min(speedups[c]):.2f}x to {max(speedups[c]):.2f}x")
    if ranked:
        g, worst, best = max(ranked)
        p("")
        if g < 1:
            p("On these photos the GPU does not pay off: keep darktable on the CPU "
              "(`ujust margine-darktable-opencl disable`).")
        else:
            p(f"Fastest on average: **{best}**"
              + ("" if worst >= 1 else f" (but slower than the CPU in at least one case, down to {worst:.2f}x)")
              + ". `ujust margine-darktable-opencl` sets gpu005a4.")
    bad = [r for r in measured if not r["valid"]]
    if bad:
        p("\nDiscarded runs:")
        for r in bad:
            p("- " + line(r))
    faults = [r for r in runs if r["kernel_fault"]]
    p("\nGPU faults in the kernel log: " + ("none" if not faults else
      "; ".join(f"{r['config']} {r['image']}: {r['kernel_fault']}" for r in faults)))


def main():
    cmd = sys.argv[1]
    if cmd == "record":
        record(sys.argv[2:])
    elif cmd == "line":
        print(line(json.loads(sys.argv[2])))
    elif cmd == "report":
        report(sys.argv[2])


if __name__ == "__main__":
    main()
