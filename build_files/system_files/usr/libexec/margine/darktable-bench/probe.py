#!/usr/bin/python3
"""Disturbance probe for `ujust margine-darktable-bench`.

  probe.py clocks                  print the monotonic and boot clocks: their
                                   difference grows only while the system
                                   sleeps, so a run that spans a suspend shows
  probe.py snapshot FILE           save CPU time and GPU engine time per process
  probe.py diff BEFORE AFTER WALL EXCLUDE_PIDS
      print a JSON object with the CPU and GPU share used by OTHER programs
      between the two snapshots (darktable-cli, its sandbox and the benchmark
      itself excluded), so a run disturbed by a video, a browser or the open
      darktable can be thrown away and repeated.

CPU: utime+stime from /proc/<pid>/stat. GPU: amdgpu's per-client counters in
/proc/<pid>/fdinfo (drm-engine-gfx/compute/dec/enc, nanoseconds), deduplicated
by drm-client-id. ROCm compute goes through /dev/kfd and is not counted there,
which is fine: only the other programs' GPU use matters.
"""
import json
import os
import sys
import time

HZ = os.sysconf("SC_CLK_TCK")
NCPU = os.cpu_count() or 1
OURS = {"darktable-cli", "bwrap", "xdg-dbus-proxy", "flatpak", "probe.py"}


def snapshot():
    procs = {}
    gpu_clients = {}
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            with open(f"/proc/{pid}/stat") as f:
                stat = f.read()
            comm = stat[stat.index("(") + 1:stat.rindex(")")]
            fields = stat[stat.rindex(")") + 2:].split()
            cpu = int(fields[11]) + int(fields[12])
        except (OSError, ValueError, IndexError):
            continue
        procs[pid] = {"comm": comm, "cpu": cpu}
        try:
            fds = os.listdir(f"/proc/{pid}/fdinfo")
        except OSError:
            continue
        for fd in fds:
            try:
                with open(f"/proc/{pid}/fdinfo/{fd}") as f:
                    text = f.read()
            except OSError:
                continue
            if "drm-client-id" not in text:
                continue
            client, busy = None, 0
            for line in text.splitlines():
                if line.startswith("drm-client-id:"):
                    client = line.split()[1]
                elif line.startswith("drm-engine-") and line.endswith("ns"):
                    busy += int(line.split()[1])
            if client is not None:
                gpu_clients[client] = {"pid": pid, "ns": busy}
    return {"procs": procs, "gpu": gpu_clients}


def diff(before, after, wall, exclude):
    other_cpu = 0
    offenders = {}
    for pid, p in after["procs"].items():
        if pid in exclude or p["comm"] in OURS:
            continue
        delta = p["cpu"] - before["procs"].get(pid, {"cpu": p["cpu"]})["cpu"]
        if delta > 0:
            other_cpu += delta
            offenders[p["comm"]] = offenders.get(p["comm"], 0) + delta
    other_gpu = 0
    for client, c in after["gpu"].items():
        comm = after["procs"].get(c["pid"], {}).get("comm", "?")
        if c["pid"] in exclude or comm in OURS:
            continue
        delta = c["ns"] - before["gpu"].get(client, {"ns": c["ns"]})["ns"]
        if delta > 0:
            other_gpu += delta
            offenders["gpu:" + comm] = offenders.get("gpu:" + comm, 0) + delta / 1e9 * HZ
    top = sorted(offenders.items(), key=lambda kv: -kv[1])[:4]
    return {
        # share of the whole machine (all CPU threads) used by other programs
        "other_cpu_pct": round(100 * other_cpu / HZ / wall / NCPU, 2),
        # GPU engine time of other programs, as a share of the wall time
        "other_gpu_pct": round(100 * other_gpu / 1e9 / wall, 2),
        "top": [f"{name} {value / HZ:.1f}s" for name, value in top],
    }


def main():
    if sys.argv[1] == "clocks":
        print(f"{time.monotonic():.3f} {time.clock_gettime(time.CLOCK_BOOTTIME):.3f}")
    elif sys.argv[1] == "snapshot":
        with open(sys.argv[2], "w") as f:
            json.dump(snapshot(), f)
    elif sys.argv[1] == "diff":
        before = json.load(open(sys.argv[2]))
        after = json.load(open(sys.argv[3]))
        exclude = set(sys.argv[5].split(",")) if len(sys.argv) > 5 else set()
        print(json.dumps(diff(before, after, float(sys.argv[4]), exclude)))


if __name__ == "__main__":
    main()
