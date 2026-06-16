#!/usr/bin/env bash
#
# margine-bench-kernel.sh
#
# Kernel / scheduler benchmark + characterisation for the Margine machine.
#
# Margine is a Bluefin-DX-based Fedora bootc atomic image whose CORE identity is
# a *signed CachyOS/BORE kernel*. This script characterises that kernel under
# load and prints a human-readable report:
#
#   1. Identity   : booted kernel, confirmation it is the CachyOS/BORE kernel,
#                   BORE runtime tunable, the active sched_ext (scx) scheduler
#                   if one is loaded, and the signed bootc deployment.
#   2. Scheduler  : wakeup / request latency under load   (schbench, OPTIONAL)
#   3. Throughput : task messaging / context-switch cost  (perf bench sched)
#   4. Contention : thread-contention responsiveness       (sysbench threads)
#   5. Load gen   : background CPU pressure during the above (stress-ng)
#
# DESIGN CONSTRAINTS (Margine host rules — all honoured here):
#   * The HOST has NO dnf/apt. Host packages are brew / flatpak / rpm-ostree
#     ONLY. This script NEVER layers, installs, or mutates anything on the host.
#   * Benchmark tooling (perf, sysbench, stress-ng, and the OPTIONAL schbench)
#     runs inside a THROWAWAY distrobox container (Fedora by default) created on
#     demand. The container is given a DEDICATED scratch HOME via `--home` so it
#     does NOT bind-mount or litter Daniel's real $HOME. If every required tool
#     already exists on the host PATH, no container is created.
#   * Tool availability is REAL: stress-ng, sysbench and perf are packaged in
#     Fedora. schbench and hackbench are NOT in Fedora, so:
#       - hackbench is replaced by `perf bench sched messaging`, the kernel's
#         own canonical scheduler-messaging benchmark (always available with
#         perf, pure userspace, no perf_event access required).
#       - schbench is treated as a CLEARLY-OPTIONAL best-effort: built from its
#         upstream git inside the container. If git/network/build is unavailable
#         the schbench section is skipped cleanly — it is never a hard dependency.
#   * READ-ONLY toward host system state: it does not change the cpufreq
#     governor, does not load/unload schedulers, does not touch sysctls or
#     perf_event_paranoid, and performs no destructive operations. It only reads
#     /proc & /sys and runs self-contained user-space micro-benchmarks.
#   * Idempotent + safe: a pre-existing container of the same name is REUSED and
#     is NEVER force-removed. Only a container that THIS run created is cleaned
#     up on exit (unless BENCH_KEEP=1).
#
# Container note: distrobox containers share the host kernel, so latency numbers
# reflect the real booted CachyOS/BORE kernel even when the tools live in a
# container. This is exactly why a container is acceptable here.
#
set -euo pipefail

# ----------------------------------------------------------------------------
# Configuration (override via environment)
# ----------------------------------------------------------------------------
BENCH_IMAGE="${BENCH_IMAGE:-quay.io/fedora/fedora:44}"   # throwaway tooling image
BENCH_BOX="${BENCH_BOX:-margine-bench}"                  # distrobox container name
BENCH_RUNTIME="${BENCH_RUNTIME:-30}"                     # seconds per long bench
BENCH_KEEP="${BENCH_KEEP:-0}"                            # 1 = keep container afterwards
BENCH_NO_CONTAINER="${BENCH_NO_CONTAINER:-0}"           # 1 = host tools only, never create a box
BENCH_BUILD_SCHBENCH="${BENCH_BUILD_SCHBENCH:-1}"       # 1 = try to build optional schbench from git
# Dedicated, throwaway HOME for the container so the host $HOME is never shared.
BENCH_HOME="${BENCH_HOME:-${XDG_RUNTIME_DIR:-/tmp}/margine-bench-home}"
# Machine-readable output. When BENCH_JSON_OUT is set, the parsed metrics +
# identity metadata are written there as JSON (in ADDITION to the human report)
# so margine-bench-compare can diff several kernels. BENCH_LABEL names the run
# (e.g. margine-cachyos / bluefin-dx / fedora-stock); defaults to the kernel rel.
BENCH_JSON_OUT="${BENCH_JSON_OUT:-}"
BENCH_LABEL="${BENCH_LABEL:-}"

NPROC="$(nproc)"
HALF_PROC="$(( NPROC > 1 ? NPROC / 2 : 1 ))"

# Runtime state.
USE_CONTAINER=0    # 1 once we have committed to using the container
CREATED_BOX=0      # 1 ONLY if this run created the container (gates cleanup)

# Structured results, populated by the bench functions and emitted as JSON at
# the end when BENCH_JSON_OUT is set. Keys are stable metric identifiers.
declare -A RESULTS=()
BENCH_TMPDIR=""    # holds each bench's raw output for parsing; removed on exit
LAST_BENCH_OUT=""  # path to the most recent bench's captured raw output

# res KEY VALUE — record a structured result (skipped if VALUE is empty, so a
# bench that didn't run / didn't parse simply leaves the key absent).
res() { [[ -n "${2:-}" ]] && RESULTS["$1"]="$2"; return 0; }

# ----------------------------------------------------------------------------
# Pretty printing helpers
# ----------------------------------------------------------------------------
if [[ -t 1 ]]; then
  C_BOLD=$'\033[1m'; C_GRN=$'\033[32m'; C_YEL=$'\033[33m'; C_RED=$'\033[31m'
  C_CYN=$'\033[36m'; C_RST=$'\033[0m'
else
  C_BOLD=""; C_GRN=""; C_YEL=""; C_RED=""; C_CYN=""; C_RST=""
fi

hr()   { printf '%s\n' "------------------------------------------------------------"; }
head1(){ printf '\n%s== %s ==%s\n' "$C_BOLD$C_CYN" "$*" "$C_RST"; }
ok()   { printf '  %s[ ok ]%s %s\n'   "$C_GRN" "$C_RST" "$*"; }
warn() { printf '  %s[warn]%s %s\n'   "$C_YEL" "$C_RST" "$*"; }
bad()  { printf '  %s[FAIL]%s %s\n'   "$C_RED" "$C_RST" "$*"; }
info() { printf '  %s\n' "$*"; }
kv()   { printf '  %-28s %s\n' "$1" "$2"; }

# read_cpu_temp_c — best-effort current CPU temperature in °C (one decimal),
# printed to stdout; returns non-zero if no sensor is readable. Prefers a real
# CPU-package sensor (AMD k10temp/zenpower, Intel coretemp), then falls back to
# the x86_pkg_temp / acpitz thermal zones. Pure /sys read, no tools, no mutation.
read_cpu_temp_c() {
  local want h n z
  for want in k10temp zenpower coretemp; do
    for h in /sys/class/hwmon/hwmon*; do
      [[ -r "$h/name" ]] || continue
      n="$(cat "$h/name" 2>/dev/null || true)"
      if [[ "$n" == "$want" && -r "$h/temp1_input" ]]; then
        awk '{printf "%.1f", $1/1000}' "$h/temp1_input" 2>/dev/null && return 0
      fi
    done
  done
  for want in x86_pkg_temp acpitz; do
    for z in /sys/class/thermal/thermal_zone*; do
      [[ -r "$z/type" && -r "$z/temp" ]] || continue
      if [[ "$(cat "$z/type" 2>/dev/null || true)" == "$want" ]]; then
        awk '{printf "%.1f", $1/1000}' "$z/temp" 2>/dev/null && return 0
      fi
    done
  done
  return 1
}

# ----------------------------------------------------------------------------
# 1. KERNEL / SCHEDULER IDENTITY (pure host read, no mutation)
# ----------------------------------------------------------------------------
identity_report() {
  head1 "Margine kernel identity"

  local krel; krel="$(uname -r)"
  local kver; kver="$(uname -v)"
  kv "Booted kernel (uname -r)" "$krel"
  kv "Build string  (uname -v)" "$kver"

  # --- CachyOS confirmation -------------------------------------------------
  # Primary signal: the release string. Corroborated below by kernel config.
  if [[ "$krel" == *cachyos* || "$krel" == *cachy* ]]; then
    ok "Release string identifies a CachyOS kernel."
  else
    warn "Release string does NOT contain 'cachyos' — not the expected Margine kernel?"
  fi

  # --- Kernel config corroboration (CONFIG_CACHY / BORE / sched_ext) --------
  # Try the in-kernel config first (/proc/config.gz), then /boot fallback.
  local cfg=""
  if [[ -r /proc/config.gz ]] && command -v zcat >/dev/null 2>&1; then
    cfg="$(zcat /proc/config.gz 2>/dev/null || true)"
  elif [[ -r "/boot/config-$krel" ]]; then
    cfg="$(cat "/boot/config-$krel" 2>/dev/null || true)"
  fi

  if [[ -n "$cfg" ]]; then
    if grep -q '^CONFIG_CACHY=y' <<<"$cfg"; then
      ok "CONFIG_CACHY=y           (CachyOS patchset built in)"
    else
      warn "CONFIG_CACHY not set in kernel config"
    fi
    if grep -q '^CONFIG_SCHED_BORE=y' <<<"$cfg"; then
      ok "CONFIG_SCHED_BORE=y      (BORE scheduler built in)"
    else
      warn "CONFIG_SCHED_BORE not set in kernel config"
    fi
    if grep -q '^CONFIG_SCHED_CLASS_EXT=y' <<<"$cfg"; then
      ok "CONFIG_SCHED_CLASS_EXT=y (sched_ext / scx support)"
    else
      info "CONFIG_SCHED_CLASS_EXT not set (no scx support)"
    fi
  else
    warn "Kernel config not readable (/proc/config.gz, /boot/config-*); relying on uname only."
  fi

  # --- BORE runtime tunable -------------------------------------------------
  # /proc/sys/kernel/sched_bore == 1 means BORE is the active CFS/EEVDF flavour.
  if [[ -r /proc/sys/kernel/sched_bore ]]; then
    local bore; bore="$(cat /proc/sys/kernel/sched_bore 2>/dev/null || echo '?')"
    if [[ "$bore" == "1" ]]; then
      ok "sched_bore=1            (BORE burst-oriented scheduling ACTIVE)"
    else
      warn "sched_bore=$bore (BORE compiled in but currently disabled)"
    fi
  else
    info "No /proc/sys/kernel/sched_bore tunable (kernel may use BORE unconditionally or not at all)."
  fi

  # --- sched_ext (scx) active scheduler, if any -----------------------------
  # scx is OPTIONAL on Margine. When loaded it overrides BORE for scheduling.
  # On this kernel /sys/kernel/sched_ext contains FILES only (state, enable_seq,
  # hotplug_seq, nr_rejected, switch_all) — there are NO per-scheduler subdirs,
  # so we do not enumerate subdirs. The scheduler name (when enabled) comes from
  # scxctl, carefully filtered for its "no scx scheduler running" idle message.
  if [[ -d /sys/kernel/sched_ext ]]; then
    local scx_state="unknown"
    [[ -r /sys/kernel/sched_ext/state ]] && scx_state="$(cat /sys/kernel/sched_ext/state 2>/dev/null || echo unknown)"
    if [[ "$scx_state" == "enabled" ]]; then
      local scx_name=""
      if command -v scxctl >/dev/null 2>&1; then
        # scxctl prints the running scheduler, OR "no scx scheduler running"
        # (exit 0) when idle. Filter that idle message out so we never report it
        # as a scheduler name.
        local scx_raw
        scx_raw="$(scxctl get 2>/dev/null | head -1 || true)"
        if [[ -n "$scx_raw" && "$scx_raw" != *"no scx scheduler"* ]]; then
          scx_name="$scx_raw"
        fi
      fi
      ok "sched_ext state=enabled — active scx scheduler: ${scx_name:-<unknown>}"
      warn "An scx scheduler is loaded; benchmarks reflect scx, not stock BORE."
    else
      ok "sched_ext present, state=${scx_state} — running stock BORE (no scx override)."
    fi
  else
    info "No sched_ext sysfs (scx not supported / not present)."
  fi

  # --- Boot image provenance (signed Margine image) -------------------------
  if command -v rpm-ostree >/dev/null 2>&1; then
    local booted
    booted="$(rpm-ostree status --booted 2>/dev/null \
              | grep -E 'ostree-image-signed|Digest:|Version:' \
              | sed 's/^ */    /' || true)"
    if [[ -n "$booted" ]]; then
      info "Booted bootc deployment:"
      printf '%s\n' "$booted"
    fi
  fi

  # --- Hardware / load context for interpreting the numbers ------------------
  kv "Logical CPUs (nproc)" "$NPROC"
  if [[ -r /proc/cpuinfo ]]; then
    kv "CPU model" "$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | sed 's/^ *//')"
  fi
  if [[ -r /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]]; then
    local gov; gov="$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)"
    kv "cpufreq governor (cpu0)" "$gov (read-only; NOT modified)"
    [[ "$gov" != "performance" ]] && warn "Governor is '$gov' — results may vary run-to-run; this is expected, the script never changes it."
  fi
  if command -v free >/dev/null 2>&1; then
    kv "Memory" "$(free -h | awk '/^Mem:/ {print $3" used / "$2" total"}')"
  fi
  kv "Load average" "$(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null || echo n/a)"
  local temp_start; temp_start="$(read_cpu_temp_c || true)"
  if [[ -n "$temp_start" ]]; then
    kv "CPU temp (start)" "${temp_start} °C"
  else
    info "CPU temp sensor not readable — thermal context will be omitted."
  fi

  # ---- Structured metadata for the optional JSON output --------------------
  res temp_start_c "$temp_start"
  res label    "${BENCH_LABEL:-$krel}"
  res kernel   "$krel"
  res hostname "$(hostname 2>/dev/null || cat /etc/hostname 2>/dev/null || echo unknown)"
  res date     "$(date -Is 2>/dev/null || date)"
  res nproc    "$NPROC"
  res cachyos  "$( [[ "$krel" == *cachy* ]] && echo 1 || echo 0 )"
  res bore     "$( [[ "$(cat /proc/sys/kernel/sched_bore 2>/dev/null || echo 0)" == 1 ]] && echo 1 || echo 0 )"
  [[ -r /proc/cpuinfo ]] && res cpu_model "$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | sed 's/^ *//')"
  # Machine model from DMI (e.g. "Framework Laptop 13 (AMD Ryzen 7040Series)") —
  # the comparer prefers this over cpu_model for the chart subtitle.
  [[ -r /sys/class/dmi/id/product_name ]] && res machine "$(printf '%s %s' \
    "$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true)" \
    "$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)" \
    | sed 's/  */ /g; s/^ *//; s/ *$//')"
  [[ -r /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]] && \
    res governor "$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)"
  [[ -r /sys/kernel/sched_ext/state ]] && \
    res scx_state "$(cat /sys/kernel/sched_ext/state 2>/dev/null || echo unknown)"
}

# ----------------------------------------------------------------------------
# 2. TOOLING: prefer host PATH, else a throwaway distrobox container
# ----------------------------------------------------------------------------
host_has_all() {
  local t
  for t in "$@"; do command -v "$t" >/dev/null 2>&1 || return 1; done
  return 0
}

# tool_available <tool>
# True if <tool> can be executed for this run: on the host (when not using a
# container) OR inside the container (probed live, not assumed). This turns a
# best-effort install that didn't land a package into a CLEAN skip instead of
# noisy "command not found" output.
tool_available() {
  local tool="$1"
  if [[ "$USE_CONTAINER" == "1" ]]; then
    # `command` is a SHELL BUILTIN, not an executable: running it directly via
    # `distrobox enter -- command -v ...` makes crun try to exec a binary named
    # `command`, which fails with exit 127 and would make EVERY probe report the
    # tool as missing. Wrap it in `bash -lc` (matching run_in) so `command -v`
    # runs as a builtin and the probe actually reflects container reality.
    distrobox enter --name "$BENCH_BOX" -- \
      bash -lc 'command -v "$1" >/dev/null 2>&1' _ "$tool"
  else
    command -v "$tool" >/dev/null 2>&1
  fi
}

# run_in <command...>
# Execute <command...> on the host (no container) or inside the container.
run_in() {
  if [[ "$USE_CONTAINER" == "1" ]]; then
    # Re-quote the argv so it survives the bash -lc wrapper unambiguously.
    distrobox enter --name "$BENCH_BOX" -- bash -lc "$(printf '%q ' "$@")"
  else
    "$@"
  fi
}

# preflight_container_manager
# Best-effort sanity check that podman is usable before we attempt a network
# pull. Non-fatal: distrobox can use other backends, so we only warn.
preflight_container_manager() {
  if command -v podman >/dev/null 2>&1; then
    if ! podman info >/dev/null 2>&1; then
      warn "podman is installed but 'podman info' failed; container creation may not work."
    fi
  fi
}

ensure_container() {
  # Create the distrobox only if it does not already exist, then install the
  # benchmark tools inside it (container packages only — host untouched).
  # Returns non-zero on any failure so callers can degrade gracefully.
  if [[ "$BENCH_NO_CONTAINER" == "1" ]]; then
    info "BENCH_NO_CONTAINER=1 — not creating a container."
    return 1
  fi
  if ! command -v distrobox >/dev/null 2>&1; then
    warn "distrobox not found and tools missing on host; cannot run container benches."
    return 1
  fi

  preflight_container_manager

  if distrobox list 2>/dev/null | awk -F'|' '{gsub(/ /,"",$2); print $2}' | grep -qx "$BENCH_BOX"; then
    info "Reusing existing container '$BENCH_BOX' (NOT created by this run; will not be removed)."
    # CREATED_BOX stays 0 — we must never force-remove a pre-existing container.
  else
    head1 "Creating throwaway benchmark container"
    info "Image : $BENCH_IMAGE"
    info "Name  : $BENCH_BOX"
    info "HOME  : $BENCH_HOME (dedicated scratch dir; host \$HOME is NOT shared)"
    info "Note  : first run pulls the image and runs dnf over the network — this"
    info "        can take SEVERAL MINUTES on a cold cache. Errors are surfaced."
    mkdir -p "$BENCH_HOME"
    # Capture output so a pull/create failure (e.g. offline) is diagnosable
    # instead of being swallowed by /dev/null. --no-entry: no desktop launcher.
    local create_log; create_log="$(mktemp)"
    if ! distrobox create --yes --no-entry \
            --home "$BENCH_HOME" \
            --image "$BENCH_IMAGE" \
            --name "$BENCH_BOX" >"$create_log" 2>&1; then
      bad "distrobox create failed (offline? image pull blocked? backend down?):"
      sed 's/^/      /' "$create_log" >&2 || true
      rm -f "$create_log"
      return 1
    fi
    rm -f "$create_log"
    CREATED_BOX=1
  fi

  # From here we are committed to the container for tool probing/execution.
  USE_CONTAINER=1

  # Install tooling INSIDE the container only (host untouched). Only packages
  # that ACTUALLY exist in Fedora are installed here: stress-ng, sysbench, perf.
  # (schbench/hackbench are NOT in Fedora — schbench is built separately below
  # as a clearly-optional best-effort; hackbench is replaced by perf bench.)
  info "Installing benchmark tools inside the container..."
  local inst_log; inst_log="$(mktemp)"
  if ! distrobox enter --name "$BENCH_BOX" -- bash -lc '
        set -euo pipefail
        if command -v dnf >/dev/null 2>&1; then
          sudo dnf -y install --setopt=install_weak_deps=False \
            stress-ng sysbench perf
        elif command -v pacman >/dev/null 2>&1; then
          # If a user points BENCH_IMAGE at an Arch/CachyOS image, these (plus
          # schbench and rt-tests) are packaged there.
          sudo pacman -Sy --noconfirm --needed stress-ng sysbench perf
        else
          echo "No supported package manager (dnf/pacman) in image" >&2
          exit 1
        fi
      ' >"$inst_log" 2>&1; then
    warn "Tool install inside the container reported errors (network/repo issue?):"
    sed 's/^/      /' "$inst_log" >&2 || true
    warn "Continuing with whatever installed; missing benches will be skipped cleanly."
  fi
  rm -f "$inst_log"

  # OPTIONAL: build schbench from upstream git as a best-effort. Never fatal.
  if [[ "$BENCH_BUILD_SCHBENCH" == "1" ]]; then
    maybe_build_schbench
  fi

  return 0
}

# maybe_build_schbench
# Best-effort: build schbench from kernel.org inside the container and symlink
# it onto PATH. Any failure (no git/make/gcc, no network, build break) is a
# clean skip — schbench is NEVER a hard dependency.
maybe_build_schbench() {
  [[ "$USE_CONTAINER" == "1" ]] || return 0
  if tool_available schbench; then
    return 0   # already present (e.g. Arch image)
  fi
  info "Attempting OPTIONAL build of schbench from upstream git (best-effort)..."
  local sb_log; sb_log="$(mktemp)"
  if distrobox enter --name "$BENCH_BOX" -- bash -lc '
        set -euo pipefail
        if command -v dnf >/dev/null 2>&1; then
          sudo dnf -y install --setopt=install_weak_deps=False git make gcc
        fi
        workdir="$HOME/.cache/margine-bench"
        mkdir -p "$workdir"
        cd "$workdir"
        if [ ! -d schbench/.git ]; then
          rm -rf schbench
          git clone --depth 1 \
            https://git.kernel.org/pub/scm/linux/kernel/git/mason/schbench.git
        fi
        make -C schbench
        # Put the freshly built binary on PATH for non-login shells too.
        sudo install -m 0755 schbench/schbench /usr/local/bin/schbench
      ' >"$sb_log" 2>&1; then
    ok "Built optional schbench from git."
  else
    warn "Optional schbench build skipped/failed (non-fatal):"
    sed 's/^/      /' "$sb_log" >&2 || true
  fi
  rm -f "$sb_log"
}

# ----------------------------------------------------------------------------
# 3. LOAD GENERATOR (stress-ng): background CPU pressure so the latency benches
#    measure the scheduler UNDER LOAD, which is the interesting case for BORE.
# ----------------------------------------------------------------------------
LOAD_PID=""
LOAD_KIND=""   # "host" or "container"

start_background_load() {
  if ! tool_available stress-ng; then
    warn "stress-ng unavailable; latency benches will run WITHOUT extra background load."
    return 0
  fi
  info "Starting background CPU load: stress-ng --cpu $HALF_PROC for the bench window."
  if [[ "$USE_CONTAINER" == "1" ]]; then
    # Run stress-ng detached inside the container; record its container PID.
    LOAD_PID="$(distrobox enter --name "$BENCH_BOX" -- bash -lc \
      "setsid stress-ng --cpu $HALF_PROC --timeout $(( BENCH_RUNTIME * 4 + 30 ))s >/dev/null 2>&1 & echo \$!" \
      2>/dev/null || true)"
    LOAD_KIND="container"
  else
    setsid stress-ng --cpu "$HALF_PROC" --timeout "$(( BENCH_RUNTIME * 4 + 30 ))s" >/dev/null 2>&1 &
    LOAD_PID="$!"
    LOAD_KIND="host"
  fi
  [[ -n "$LOAD_PID" ]] && ok "Background load running (pid $LOAD_PID, $LOAD_KIND)."
}

stop_background_load() {
  [[ -n "$LOAD_PID" ]] || return 0
  if [[ "$LOAD_KIND" == "container" ]]; then
    distrobox enter --name "$BENCH_BOX" -- bash -lc "kill $LOAD_PID 2>/dev/null || true" >/dev/null 2>&1 || true
  else
    kill "$LOAD_PID" 2>/dev/null || true
  fi
  LOAD_PID=""
}

# ----------------------------------------------------------------------------
# 4. BENCHMARKS
# ----------------------------------------------------------------------------

# run_bench_filtered <label> <filter-ERE> -- <command...>
# Run a benchmark, capturing BOTH its output and its OWN exit status, then
# display only the lines matching <filter-ERE>. This avoids the classic
# `CMD 2>&1 | grep ... || warn` trap, where (under pipefail) the grep's exit
# status dominates and a crashing benchmark whose stderr happens to contain a
# filter token is silently reported as success. Here we warn iff the BENCHMARK
# itself failed, independently of whether grep matched anything.
run_bench_filtered() {
  local label="$1" filter="$2"; shift 2
  [[ "${1:-}" == "--" ]] && shift
  local out_file rc=0
  out_file="$(mktemp -p "${BENCH_TMPDIR:-${TMPDIR:-/tmp}}")"
  # Capture the bench's real exit status; do NOT let a pipeline mask it.
  run_in "$@" >"$out_file" 2>&1 || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    warn "$label exited non-zero (rc=$rc) — output may be partial/invalid:"
  fi
  # Display the metric lines; if none match, show that explicitly (do not let an
  # empty grep be mistaken for a clean run).
  if ! grep -Ei "$filter" "$out_file"; then
    if [[ "$rc" -eq 0 ]]; then
      warn "$label produced no lines matching the expected metrics; raw output:"
    fi
    sed 's/^/      /' "$out_file"
  fi
  # Keep the raw output for the caller to parse into RESULTS (cleaned with
  # BENCH_TMPDIR on exit) instead of deleting it here.
  LAST_BENCH_OUT="$out_file"
  return 0
}

# parse_metric FILE SED_EXPR — print the first capture-group-1 match, else empty.
parse_metric() { sed -nE "$2" "$1" 2>/dev/null | head -1; }

# 4a. schbench (OPTIONAL) — wakeup & request latency under load. This is the
#     gold-standard scheduler latency metric: how quickly a woken task gets to
#     run when the box is busy. Lower p50/p99 = snappier desktop. Only runs if
#     the optional build succeeded; otherwise cleanly skipped.
bench_schbench() {
  head1 "Scheduler wakeup latency under load (schbench, OPTIONAL)"
  if ! tool_available schbench; then
    info "schbench not built/available — skipping (this metric is optional)."
    return 0
  fi
  info "Config: -m $HALF_PROC message threads, -t $HALF_PROC workers/msg, runtime ${BENCH_RUNTIME}s"
  info "(Reports wakeup latency and request latency percentiles in microseconds.)"
  hr
  # schbench's CLI is broadly stable on -m/-t/-r across recent versions; if a
  # given build differs, we surface a hint rather than aborting.
  local sb_out; sb_out="$(mktemp -p "${BENCH_TMPDIR:-${TMPDIR:-/tmp}}")"
  run_in schbench -m "$HALF_PROC" -t "$HALF_PROC" -r "$BENCH_RUNTIME" >"$sb_out" 2>&1 \
    || warn "schbench returned non-zero (CLI flag mismatch in this build?); see output below."
  cat "$sb_out"
  # Capture the FINAL Wakeup-Latency percentiles (steady state at the end of the
  # run), not the first interval checkpoint. schbench prints several interval
  # blocks; track the Wakeup sections (ignoring Request/RPS) and keep the last
  # 50.0th/99.0th seen. The token search tolerates the "* " marker schbench puts
  # on a percentile line. Wakeup latency = the desktop-snappiness metric.
  local sb_wake
  sb_wake="$(awk '
    /Wakeup Latencies/ { sec = 1; next }
    /Request Latencies|RPS percentiles|sched delay/ { sec = 0 }
    sec {
      for (i = 1; i <= NF; i++) {
        if ($i == "50.0th:") p50 = $(i + 1)
        if ($i == "99.0th:") p99 = $(i + 1)
      }
    }
    END { print p50 "\t" p99 }
  ' "$sb_out")"
  res schbench_p50_us "$(printf '%s' "$sb_wake" | cut -f1)"
  res schbench_p99_us "$(printf '%s' "$sb_wake" | cut -f2)"
  hr
}

# 4b. perf bench sched messaging — the kernel's OWN scheduler-messaging
#     benchmark and the canonical, packaged substitute for hackbench (which is
#     NOT in Fedora). Many tasks exchange messages over sockets/pipes; reports
#     total wall-clock seconds, lower = better. Pure userspace: it needs no
#     perf_event access, so perf_event_paranoid is irrelevant and untouched.
bench_perf_messaging() {
  head1 "Scheduler messaging throughput (perf bench sched messaging)"
  if ! tool_available perf; then
    warn "perf unavailable; skipping."; return 0
  fi
  local groups=20 loops=1000
  info "Config: $groups groups, $loops loops (process/socket messaging). Lower time = better."
  info "(This is the canonical hackbench-equivalent; hackbench itself is not packaged in Fedora.)"
  hr
  run_bench_filtered "perf bench sched messaging" \
    'total|messaging|sec|groups' \
    -- perf bench sched messaging -g "$groups" -l "$loops"
  res sched_messaging_total_s \
    "$(parse_metric "$LAST_BENCH_OUT" 's/.*Total time:[[:space:]]*([0-9.]+).*/\1/p')"
  hr
}

# 4c. perf bench sched pipe — context-switch round-trip latency between two
#     tasks over a pipe. Directly exercises the wakeup fast path BORE tunes.
#     Reports ops/sec and usecs/op; lower usecs/op = snappier.
bench_perf_pipe() {
  head1 "Context-switch latency (perf bench sched pipe)"
  if ! tool_available perf; then
    warn "perf unavailable; skipping."; return 0
  fi
  hr
  run_bench_filtered "perf bench sched pipe" \
    'total|ops|usecs|seconds' \
    -- perf bench sched pipe
  res sched_pipe_usecs_op \
    "$(parse_metric "$LAST_BENCH_OUT" 's@.*[[:space:]]([0-9.]+)[[:space:]]+usecs/op.*@\1@p')"
  res sched_pipe_ops_sec \
    "$(parse_metric "$LAST_BENCH_OUT" 's@.*[[:space:]]([0-9.]+)[[:space:]]+ops/sec.*@\1@p')"
  hr
}

# 4d. sysbench threads — thread-contention responsiveness under heavy thread
#     switching and mutex churn. events/sec higher = better; latency lower =
#     better. Complements perf bench with a lock-contention angle.
bench_sysbench() {
  head1 "Thread-contention responsiveness (sysbench threads)"
  if ! tool_available sysbench; then
    warn "sysbench unavailable; skipping."; return 0
  fi
  info "Config: threads test, $NPROC threads, ${BENCH_RUNTIME}s, heavy mutex churn."
  hr
  # sysbench 1.0.x (Fedora) does NOT print an 'events per second' line for the
  # `threads` test. It DOES print 'total number of events:' and 'total time:'
  # plus latency min/avg/max/95th. Match those real tokens (and 'events/s'/'eps'
  # in case a build emits a rate) so the headline throughput proxy — total event
  # count — is actually surfaced instead of being filtered away.
  run_bench_filtered "sysbench threads" \
    'total time|total number of events|events/s|eps|min:|avg:|max:|95th' \
    -- sysbench threads \
      --threads="$NPROC" --time="$BENCH_RUNTIME" --thread-yields=1000 --thread-locks=8 run
  res sysbench_events \
    "$(parse_metric "$LAST_BENCH_OUT" 's/.*total number of events:[[:space:]]*([0-9]+).*/\1/p')"
  res sysbench_total_time_s \
    "$(parse_metric "$LAST_BENCH_OUT" 's/.*total time:[[:space:]]*([0-9.]+)s.*/\1/p')"
  res sysbench_lat_avg_ms \
    "$(parse_metric "$LAST_BENCH_OUT" 's/.*avg:[[:space:]]*([0-9.]+).*/\1/p')"
  res sysbench_lat_95th_ms \
    "$(parse_metric "$LAST_BENCH_OUT" 's/.*95th percentile:[[:space:]]*([0-9.]+).*/\1/p')"
  hr
}

# remove_scratch_home <path>
# Safely remove the dedicated scratch HOME. Returns non-zero (without deleting)
# unless the path is clearly OUR throwaway scratch dir, so a misconfigured
# override such as BENCH_HOME=$HOME or BENCH_HOME=/ can never be rm -rf'd.
remove_scratch_home() {
  local path="${1:-}"
  # Must be non-empty and an absolute path.
  [[ -n "$path" && "$path" == /* ]] || return 1
  # Never the user's $HOME, root, or a top-level dir.
  [[ "$path" != "${HOME:-}" ]] || return 1
  [[ "$path" != "/" ]] || return 1
  # Basename must match our expected scratch name.
  [[ "$(basename -- "$path")" == *margine-bench-home ]] || return 1
  # Only remove an existing directory (not a symlink, not a file).
  if [[ -d "$path" && ! -L "$path" ]]; then
    rm -rf -- "$path" 2>/dev/null || true
  fi
  return 0
}

# ----------------------------------------------------------------------------
# Cleanup of the throwaway container.
# We ONLY remove a container that THIS run created (CREATED_BOX=1), and only
# when BENCH_KEEP!=1. A reused/pre-existing user container is NEVER touched.
# Also stops any background load we started.
# ----------------------------------------------------------------------------
cleanup() {
  stop_background_load
  if [[ "$CREATED_BOX" == "1" && "$BENCH_KEEP" != "1" ]]; then
    head1 "Cleanup"
    info "Removing throwaway container '$BENCH_BOX' created by this run (set BENCH_KEEP=1 to keep)."
    distrobox rm --force "$BENCH_BOX" >/dev/null 2>&1 \
      || warn "Could not remove '$BENCH_BOX'; remove manually with: distrobox rm --force $BENCH_BOX"
    # Best-effort: drop the dedicated scratch HOME we created. Guard hard against
    # a misconfigured override (e.g. BENCH_HOME=$HOME): only ever recursively
    # remove a path whose basename is the EXPECTED scratch name AND which is
    # neither $HOME nor a root/empty path. Refuse anything else loudly.
    if remove_scratch_home "$BENCH_HOME"; then
      :
    else
      warn "Refusing to remove BENCH_HOME='$BENCH_HOME' (not an expected scratch dir); leaving it in place."
    fi
  elif [[ "$CREATED_BOX" == "1" ]]; then
    info "Keeping container '$BENCH_BOX' (BENCH_KEEP=1). Scratch HOME: $BENCH_HOME"
  fi
  # Remove the per-bench raw-output scratch dir (only ever our own mktemp -d).
  [[ -n "$BENCH_TMPDIR" && -d "$BENCH_TMPDIR" ]] && rm -rf -- "$BENCH_TMPDIR"
}
trap cleanup EXIT

# ----------------------------------------------------------------------------
# Machine-readable output: write RESULTS as JSON so margine-bench-compare can
# diff several kernels. Uses python3 (present on Fedora/Bluefin/Margine) for
# correct typing + escaping; degrades to a clean warning if python3 is absent.
# ----------------------------------------------------------------------------
emit_json() {
  [[ -n "$BENCH_JSON_OUT" ]] || return 0
  if ! command -v python3 >/dev/null 2>&1; then
    warn "BENCH_JSON_OUT set but python3 not found — skipping JSON output."
    return 0
  fi
  local k
  {
    printf 'schema\t%s\n' "margine-bench-kernel/1"
    for k in "${!RESULTS[@]}"; do printf '%s\t%s\n' "$k" "${RESULTS[$k]}"; done
  } | python3 -c '
import sys, json
d = {}
for line in sys.stdin:
    line = line.rstrip("\n")
    if "\t" not in line:
        continue
    k, v = line.split("\t", 1)
    try:
        d[k] = int(v)
    except ValueError:
        try:
            d[k] = float(v)
        except ValueError:
            d[k] = v
with open(sys.argv[1], "w") as f:
    json.dump(d, f, indent=2, sort_keys=True)
    f.write("\n")
' "$BENCH_JSON_OUT" \
    && ok "Wrote machine-readable results to $BENCH_JSON_OUT (label: ${RESULTS[label]:-?})" \
    || warn "Failed to write JSON to $BENCH_JSON_OUT"
}

# ----------------------------------------------------------------------------
# MAIN
# ----------------------------------------------------------------------------
main() {
  printf '%s' "$C_BOLD"
  hr
  printf 'Margine kernel/scheduler benchmark  —  %s\n' "$(date -Is 2>/dev/null || date)"
  hr
  printf '%s' "$C_RST"

  # Scratch dir for each bench's raw output (parsed into RESULTS, removed on exit).
  BENCH_TMPDIR="$(mktemp -d 2>/dev/null || true)"

  # Always-available identity section (pure host read).
  identity_report

  # Decide tooling source. The benches we ACTUALLY rely on are perf + sysbench
  # + stress-ng (all packaged); schbench is optional/extra. If the required
  # tools are already on the host, use them and never spin up a container.
  local need=(perf sysbench stress-ng)
  head1 "Benchmark tooling"
  if host_has_all "${need[@]}"; then
    ok "Required benchmark tools present on host PATH — no container needed."
    USE_CONTAINER=0
    # Optionally pick up a host schbench if the user already has one.
  else
    info "Some benchmark tools are missing on the host (expected: host pkg mgmt is brew/flatpak/rpm-ostree only)."
    if ensure_container; then
      ok "Using container '$BENCH_BOX' for benchmark tooling."
    else
      warn "No container available; running only the benches whose tools exist on host (if any)."
    fi
  fi

  # Background CPU load so the latency benches measure the scheduler UNDER LOAD.
  head1 "Background load"
  start_background_load

  # Run the suite. Each bench self-skips cleanly if its tool is unavailable.
  bench_schbench
  bench_perf_messaging
  bench_perf_pipe
  bench_sysbench

  # End-of-run CPU temp (still under sustained load ≈ peak) — records the
  # thermal envelope and lets us flag throttling that would skew the numbers.
  res temp_end_c "$(read_cpu_temp_c || true)"

  # Stop load before the summary so the load-average reading settles.
  stop_background_load

  head1 "Summary"
  info "Kernel:   $(uname -r)"
  info "BORE:     $( [[ "$(cat /proc/sys/kernel/sched_bore 2>/dev/null || echo 0)" == 1 ]] && echo 'active' || echo 'inactive/unknown' )"
  if [[ -r /sys/kernel/sched_ext/state ]]; then
    info "scx:      $(cat /sys/kernel/sched_ext/state 2>/dev/null || echo unknown)"
  fi
  local _ts="${RESULTS[temp_start_c]:-}" _te="${RESULTS[temp_end_c]:-}"
  if [[ -n "$_ts" ]]; then
    info "CPU temp: start ${_ts} °C${_te:+, end ${_te} °C (under load)}"
    if awk -v s="$_ts" 'BEGIN{exit !(s+0>=60)}'; then
      warn "Start temp >=60 °C — let the machine cool for a comparable cold start."
    fi
    if [[ -n "$_te" ]] && awk -v e="$_te" 'BEGIN{exit !(e+0>=90)}'; then
      warn "End temp >=90 °C — possible thermal throttling; numbers may be conservative."
    fi
    info "(Compare runs only when both machines START from a similar temperature.)"
  fi
  info ""
  info "How to read the numbers:"
  info "  * schbench p50/p99 wakeup latency (us, OPTIONAL): lower = snappier under"
  info "    load. The gold-standard scheduler-responsiveness metric when available."
  info "  * perf bench sched messaging total time (s): lower = better task/message"
  info "    throughput (the packaged stand-in for hackbench)."
  info "  * perf bench sched pipe usecs/op: lower = faster context-switch round-trip."
  info "  * sysbench 'total number of events' (throughput proxy): higher = better"
  info "    under heavy thread contention; latency avg/95th: lower = better."
  info "    (sysbench 1.0.x prints no 'events per second' line for the threads"
  info "    test; derive a rate as total events / total time if you need one.)"
  info "Tip: pin the cpufreq governor to 'performance' BEFORE running for the most"
  info "     comparable numbers — but this script intentionally does NOT change it."
  hr

  # ---- Guard: did the benchmarks actually RUN? -----------------------------
  # A run interrupted before the tooling was ready (or one that reused a broken
  # container left by a previous Ctrl-C) writes an identity-only result that
  # silently looks "done". Count the core (non-optional) metrics and make an
  # empty result impossible to miss — including a non-zero exit status.
  local guard_rc=0 have=0 k
  local core_keys=(sched_messaging_total_s sched_pipe_usecs_op sched_pipe_ops_sec \
                   sysbench_events sysbench_total_time_s sysbench_lat_avg_ms \
                   sysbench_lat_95th_ms)
  for k in "${core_keys[@]}"; do [[ -n "${RESULTS[$k]:-}" ]] && have=$((have + 1)); done
  res metrics_collected "$have"
  res metrics_expected "${#core_keys[@]}"

  if [[ "$have" -eq 0 ]]; then
    hr
    bad "NO BENCHMARK METRICS WERE COLLECTED — this result is IDENTITY-ONLY."
    warn "The benchmarks did not run. Usual causes: no network, an interrupted"
    warn "previous run left a half-built container, or the container/tools could"
    warn "not be installed (and the host has no perf/sysbench/stress-ng either)."
    info "Fix and re-run — and do NOT Ctrl-C it mid-way:"
    info "    distrobox rm --force ${BENCH_BOX} 2>/dev/null || true"
    info "    BENCH_LABEL=... BENCH_JSON_OUT=... ${0##*/}"
    [[ -n "$BENCH_JSON_OUT" ]] && \
      warn "'${BENCH_JSON_OUT}' has NO metrics — do not use it for a comparison."
    hr
    guard_rc=1
  elif [[ "$have" -lt "${#core_keys[@]}" ]]; then
    warn "PARTIAL result: only ${have}/${#core_keys[@]} core metrics captured — some"
    warn "benches were skipped (their tool was unavailable). The comparison will"
    warn "simply omit the missing rows; re-run if you want the full set."
  else
    ok "All ${have}/${#core_keys[@]} core benchmark metrics captured."
  fi

  # Optional machine-readable output for margine-bench-compare.
  emit_json
  return "$guard_rc"
}

main "$@"