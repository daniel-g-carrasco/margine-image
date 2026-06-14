#!/usr/bin/env bash
#
# margine-bench-gaming.sh — Gaming-performance capture helper for Margine
# ----------------------------------------------------------------------
# Margine is a Bluefin-DX-based Fedora bootc atomic image with a signed
# CachyOS/BORE kernel and an OPT-IN gaming layer (`ujust margine-gaming`:
# Steam Flatpak + gamescope/MangoHud/vkBasalt layered via rpm-ostree).
#
# This helper makes it easy to:
#   1. CAPTURE a frametime/FPS log for a game session via MangoHud's CSV
#      logging (MANGOHUD_CONFIG output_folder=.../autostart_log=...), by
#      wrapping any launch command (a Steam %command%, a gamescope+
#      mangohud invocation, or a bare binary).
#   2. SUMMARISE a MangoHud CSV log into a readable report:
#      avg / 1% low / 0.1% low FPS, min/max FPS, and frametime stats
#      (avg / p99 / max), plus session duration and sample count.
#
# Design constraints (Margine house rules):
#   * READ-ONLY toward the system. The ONLY thing it writes is log/report
#     files under a user-owned directory (default: ~/mangologs/margine).
#   * No host package management. It uses tools already provided by the
#     gaming layer (mangohud/gamescope on the host, or inside the Steam
#     Flatpak). Nothing is installed.
#   * No destructive operations. Logs are only ever created/appended/moved
#     within the log dir, never deleted by this script.
#   * Pure bash + coreutils + awk (find/sort/comm/cut, all in the base
#     image). No bc/python/jq needed.
#
# Typical uses:
#   # Wrap a game/benchmark binary and capture 60 s, then summarise:
#   ./margine-bench-gaming.sh run --duration 60 -- vkcube
#
#   # Wrap a gamescope + mangohud session:
#   ./margine-bench-gaming.sh run -- gamescope -W 2560 -H 1440 -- mangohud %game%
#
#   # Just summarise the most recent log (e.g. after a Steam session that
#   # used the launch-options string printed by `steam-options`):
#   ./margine-bench-gaming.sh summary --latest
#
#   # Summarise a specific log:
#   ./margine-bench-gaming.sh summary ~/mangologs/margine/MyGame_2026-06-14_21-00-00.csv
#
#   # Print the exact Steam launch-options line to paste per-game:
#   ./margine-bench-gaming.sh steam-options
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration (override via flags or environment).
# ---------------------------------------------------------------------------
PROG="${0##*/}"

# Where MangoHud writes its CSV. Must be user-writable; we never touch
# anything outside it. Defaults under $HOME.
LOG_DIR="${MARGINE_BENCH_LOGDIR:-${HOME}/mangologs/margine}"

# Default capture window in seconds (0 = log until the wrapped process
# exits / you close the game). MangoHud stops logging after this many
# seconds when log_duration is set. Validated as a non-negative integer.
DURATION="${MARGINE_BENCH_DURATION:-0}"

# Sampling interval in MICROSECONDS for MangoHud's log_interval. 0 means
# "every presented frame" (highest fidelity, what you usually want for
# 1%/0.1% lows). A non-zero value (e.g. 100000 = 100 ms) shrinks logs for
# very long sessions. Validated as a non-negative integer.
LOG_INTERVAL="${MARGINE_BENCH_INTERVAL:-0}"

# Tab literal used as the field separator between the producer awk and the
# coreutils sort/consumer awk in summarise_csv. Kept in one place so the
# delimiter is identical everywhere.
TAB=$(printf '\t')

# ---------------------------------------------------------------------------
# Small helpers.
# ---------------------------------------------------------------------------
err()  { printf '%s: %s\n' "$PROG" "$*" >&2; }
die()  { err "$*"; exit 1; }
info() { printf '[margine-bench] %s\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

# Validate that a value is a non-negative whole number (decimal digits only).
# Empty string is rejected. Used for --duration and --interval so that bad
# input fails loudly instead of being silently swallowed by `[ ... -gt 0 ]`.
require_uint() {
  local name="$1" value="$2"
  case "$value" in
    '' ) die "$name must be a whole number, got empty value" ;;
    *[!0-9]* ) die "$name must be a whole non-negative number, got: $value" ;;
  esac
}

usage() {
  cat <<EOF
$PROG — capture & summarise gaming FPS/frametime on Margine

USAGE:
  $PROG run [options] -- <launch command...>
      Wrap a launch command with MangoHud CSV logging, then summarise.
      The command can be a bare binary, a 'gamescope -- mangohud <game>'
      pipeline, or anything you'd normally run. If the command does not
      already start with mangohud/gamescope, 'mangohud' is auto-prefixed
      (needed to hook OpenGL apps); MANGOHUD_CONFIG is also exported so
      nested mangohud/gamescope and Vulkan apps pick up the same settings.

  $PROG summary [--latest | -l | <logfile.csv>]
      Summarise a MangoHud CSV log. --latest (alias -l) picks the newest
      *.csv in the log dir. Accepts MangoHud's per-frame CSV (not the
      _summary.csv).

  $PROG steam-options
      Print the exact Steam per-game Launch Options string to use so a
      Steam/Proton title logs into this tool's log dir. (Print-only: it
      does not create the log dir; that happens on first capture.)

  $PROG list
      List captured logs in the log dir, newest first.

OPTIONS (for 'run'):
  -d, --duration <sec>   Capture window in seconds. 0 = until game exits.
                         Whole number only. (default: $DURATION; env
                         MARGINE_BENCH_DURATION)
  -i, --interval <us>    MangoHud log_interval in microseconds. Whole number
                         only. 0 = every frame (best for lows).
                         (default: $LOG_INTERVAL; env MARGINE_BENCH_INTERVAL)
  -o, --output-dir <d>   Log directory (default: $LOG_DIR;
                         env MARGINE_BENCH_LOGDIR)
  -n, --name <label>     Filename prefix for this capture (default: derived
                         from the wrapped command's basename).
      --no-summary       Capture only; skip the post-run summary.
  -h, --help             Show this help.

ENVIRONMENT:
  MARGINE_BENCH_LOGDIR    Log directory.
  MARGINE_BENCH_DURATION  Default capture seconds (whole number).
  MARGINE_BENCH_INTERVAL  Default log_interval in microseconds (whole number).

NOTES:
  * Writes ONLY to the log dir. Read-only toward the rest of the system.
  * For Flatpak Steam, MangoHud/gamescope run inside the sandbox; see
    '$PROG steam-options' for the one-time flatpak override that lets the
    host log dir through.
EOF
}

# ---------------------------------------------------------------------------
# steam-options: print the per-game Steam Launch Options line.
#
# This subcommand is PRINT-ONLY: it must not touch the filesystem (no mkdir).
# The log dir is created lazily by the first 'run' capture (or by MangoHud
# itself when Steam launches with the printed config).
# ---------------------------------------------------------------------------
cmd_steam_options() {
  cat <<EOF
Steam → right-click the game → Properties → General → Launch Options.

Paste ONE of these (keep %command% verbatim — Steam expands it):

  # Recommended: overlay + CSV log, every frame, logs the whole session.
  # Works for Proton/DX games (Vulkan via DXVK/VKD3D, so MANGOHUD=1 hooks)
  # and native Vulkan titles.
  MANGOHUD=1 MANGOHUD_CONFIG=output_folder=${LOG_DIR},autostart_log=1,log_interval=${LOG_INTERVAL} %command%

  # Fixed N-second window (replace 60 with your desired capture length):
  MANGOHUD=1 MANGOHUD_CONFIG=output_folder=${LOG_DIR},autostart_log=1,log_duration=60,log_interval=${LOG_INTERVAL} %command%

  # Native OpenGL game (the env var alone may not hook GL — prefix mangohud):
  mangohud %command%

  # Through host gamescope (e.g. 1440p, FSR) + MangoHud:
  gamescope -W 2560 -H 1440 -F fsr -- mangohud %command%

Tip: with autostart_log you can also start/stop logging on demand in-game
with MangoHud's default hotkey Shift_L+F2.

(The log dir ${LOG_DIR} is created on first capture; this command only
prints — it does not create directories.)

After playing, summarise the newest log:
  ${PROG} summary --latest

One-time setup so Flatpak Steam can read the host log dir and MangoHud
config (Steam Flatpak does NOT remap \$HOME, so the absolute path above
resolves identically inside the sandbox):
  flatpak override --user --filesystem=${LOG_DIR} com.valvesoftware.Steam
  flatpak override --user --filesystem=xdg-config/MangoHud:ro com.valvesoftware.Steam
EOF
}

# ---------------------------------------------------------------------------
# list / latest helpers.
# ---------------------------------------------------------------------------
# List per-frame CSVs (excluding MangoHud's auto *_summary.csv) newest
# first, one per line. Uses find for mtime sorting (no 'ls | grep'), so it
# is robust to odd filenames and passes shellcheck.
list_logs() {
  [ -d "$LOG_DIR" ] || return 0
  # find with -printf '<mtime>\t<path>' then sort numerically desc, strip key.
  find "$LOG_DIR" -maxdepth 1 -type f -name '*.csv' ! -name '*_summary.csv' \
       -printf '%T@\t%p\n' 2>/dev/null | sort -rn -k1,1 | cut -f2-
}

latest_log() {
  list_logs | head -n1
}

cmd_list() {
  [ -d "$LOG_DIR" ] || die "no log dir yet: $LOG_DIR"
  local out
  out=$(list_logs)
  [ -n "$out" ] || die "no logs found in $LOG_DIR"
  info "logs in $LOG_DIR (newest first):"
  printf '%s\n' "$out"
}

# ---------------------------------------------------------------------------
# summarise: parse a MangoHud per-frame CSV.
#
# MangoHud CSV layout (verified against MangoHud v0.8.x output):
#   line 1: os,cpu,gpu,ram,kernel,driver,cpuscheduler   (metadata header)
#   line 2: <metadata values>
#   line 3: fps,frametime,cpu_load,...,elapsed           (data column header)
#   line 4+: data rows
#   Column 1 = fps, column 2 = frametime (ms), last column = elapsed (ns).
# We do NOT hard-code "skip 3 lines"; we start parsing at the data row whose
# first field literally equals "fps", which tolerates layout drift.
#
# STATISTICS
# ----------
# Average FPS is frametime-weighted (total frames / total presented time),
# which equals MangoHud's reported average.
#
# 1% / 0.1% low FPS use the PURPOSE definition for this tool:
#   "1% low = average FPS of the slowest 1% of frames by frametime".
# That is a COUNT-based metric: take the slowest k = round(p * N) frames
# (largest frametime), and report the ARITHMETIC MEAN of their per-frame FPS
# values (mean of 1000/frametime over those k frames). This is intentionally
# NOT the time-weighted CapFrameX/MangoHud percentile (which returns the
# single instantaneous FPS of the one frame where cumulative slowest-frame
# time crosses p*total_time); that other definition is harsher and is a
# different metric than the one this tool is specified to report.
#
# WORKED EXAMPLE (hand-verified, matches the implementation below):
#   10 frames, frametimes (ms): nine 8 ms frames + one 40 ms frame.
#     sorted ascending fts = 8,8,8,8,8,8,8,8,8,40
#     sum_ft = 9*8 + 40 = 112 ms  (total presented time = 0.112 s)
#     N = 10  ->  avg FPS = 1000*10/112 = 89.29
#   1% low : k = round(0.01 * 10) = round(0.1) = 0 -> clamped to 1 frame.
#            Slowest 1 frame is the 40 ms frame -> FPS 1000/40 = 25.0.
#            Mean over 1 frame = 25.0 fps.
#   10% low: k = round(0.10 * 10) = 1 frame -> same slowest frame -> 25.0 fps.
#   50% low: k = round(0.50 * 10) = 5 frames -> slowest 5 are 40,8,8,8,8.
#            FPS values: 25.0, 125, 125, 125, 125; mean = 525/5 = 105.0 fps.
#   Note the 1% low here (25.0) matches the time-weighted method by luck on
#   this tiny log, but the two diverge on realistic heavy-tailed captures:
#   the COUNT-based average (this tool's spec) reports a milder, averaged low,
#   while the time-weighted percentile reports the single worst crossing
#   frame. We implement the COUNT-based average, per the PURPOSE.
#
# IMPLEMENTATION
# --------------
# Frametimes are sorted with coreutils `sort -n` (already a stated dependency),
# NOT with an in-awk sort. An earlier version used an O(n^2) insertion sort in
# awk, which made realistic captures (default log_interval=0 logs every frame:
# ~72k rows for 10 min @120fps, ~432k rows for an hour) take minutes to hours.
# The pipeline below is:
#   producer awk  -> emit "<frametime>\t<fps>" per frame, plus one SENTINEL
#                    line carrying the order-dependent scalars (count, min/max
#                    FPS, first/last elapsed) computed in CHRONOLOGICAL order
#                    BEFORE the sort. The sentinel uses sort key "-1" so it
#                    lands first under `sort -n` (all real frametimes are > 0).
#   sort -n       -> ascending by frametime (field 1).
#   consumer awk  -> read sentinel (NR==1), then the ascending frametimes;
#                    compute averages, percentiles and count-based lows.
# A 200k-row log summarises in well under a second this way.
# ---------------------------------------------------------------------------
summarise_csv() {
  local csv="$1"
  [ -f "$csv" ] || die "log not found: $csv"
  case "$csv" in
    *_summary.csv) die "that is MangoHud's auto-summary, not a per-frame log: $csv" ;;
  esac

  # Pull the metadata values (line 2) for the cosmetic System footer in a
  # single awk pass. MangoHud emits UNQUOTED CSV, so a comma inside a GPU/CPU
  # string would shift these fields — but this only affects the footer text,
  # never the statistics. Fields: os,cpu,gpu,ram,kernel,driver,cpuscheduler.
  local meta_os="" meta_cpu="" meta_gpu="" meta_kernel=""
  IFS=, read -r meta_os meta_cpu meta_gpu _ meta_kernel _ \
    < <(awk 'NR==2{print; exit}' "$csv" 2>/dev/null || true)

  # PRODUCER: stream per-frame "<frametime>\t<fps>" lines, plus one sentinel
  # line (sort key -1) carrying the order-dependent scalars. Column 1 = fps,
  # column 2 = frametime (ms), last column = elapsed (ns). The order-dependent
  # scalars (min/max FPS, first/last elapsed) are computed HERE, before the
  # sort, because after `sort -n` rows are ordered by frametime, not by time.
  #
  # SORT: coreutils `sort -n` on field 1 (frametime), ascending.
  #
  # CONSUMER: read the sentinel first (it sorts to the top), then walk the
  # ascending frametimes. low_fps() reads the SLOWEST k frames (the top k
  # indices, since the array is ascending) and averages their FPS.
  awk -F, -v tab="$TAB" '
    {
      if (!started) {
        if ($1 == "fps") { started = 1 }
        next
      }
      # Data row. Guard against trailing blank lines / partial rows.
      if (NF < 2 || $1 == "" || $2 == "") next
      ft = $2 + 0             # frametime in ms
      if (ft <= 0) next       # ignore bogus zero/negative-frametime rows
      fps = $1 + 0
      el  = $NF + 0           # elapsed in ns (last column)
      cnt++
      if (cnt == 1 || fps < min_fps) min_fps = fps
      if (cnt == 1 || fps > max_fps) max_fps = fps
      if (cnt == 1) elapsed_first = el
      elapsed_last = el
      printf "%.6f%s%s\n", ft, tab, fps
    }
    END {
      # Sentinel line carrying order-dependent scalars; key -1 sorts first.
      if (cnt > 0)
        printf "%d%s%d%s%s%s%s%s%s%s%s\n", \
          -1, tab, cnt, tab, min_fps, tab, max_fps, tab, \
          elapsed_first, tab, elapsed_last
    }
  ' "$csv" \
  | sort -t"$TAB" -k1,1n \
  | awk -F"$TAB" -v fname="$csv" \
        -v meta_os="${meta_os:-?}" -v meta_cpu="${meta_cpu:-?}" \
        -v meta_gpu="${meta_gpu:-?}" -v meta_kernel="${meta_kernel:-?}" '
    NR == 1 {
      # The sentinel MUST be the first line (it sorts before any positive
      # frametime). If it is absent, the log had no usable frame samples.
      if ($1 + 0 != -1) {
        print "ERROR: no usable frame samples found in " fname > "/dev/stderr"
        exit 3
      }
      min_fps = $3 + 0; max_fps = $4 + 0
      elapsed_first = $5 + 0; elapsed_last = $6 + 0
      next
    }
    { n++; fts[n] = $1 + 0; sum_ft += fts[n] }
    END {
      # Division-by-zero / empty-log guard: no frames -> clear error, exit 3.
      if (n == 0 || sum_ft <= 0) {
        print "ERROR: no usable frame samples found in " fname > "/dev/stderr"
        exit 3
      }

      # Average FPS = frametime-weighted (matches MangoHud).
      avg_fps = 1000.0 * n / sum_ft
      avg_ft  = sum_ft / n

      # Count-based low FPS (PURPOSE definition: average FPS of the slowest
      # p of frames by frametime). See the worked example in the shell
      # comment above this awk program.
      low1_fps  = low_fps(0.01)
      low01_fps = low_fps(0.001)

      # Frametime p99 / max from the ascending frametime array.
      i99 = int(0.99 * n + 0.5)
      if (i99 < 1) i99 = 1
      if (i99 > n) i99 = n
      ft_p99 = fts[i99]
      ft_max = fts[n]

      # Session duration: total presented time (sum of frametimes) is the
      # primary value — it is exactly what the frametime-weighted average is
      # computed over. The elapsed-column delta is kept only as a sanity
      # cross-check (it is one frametime short of true session length).
      dur_s = sum_ft / 1000.0
      dur_elapsed = (elapsed_last - elapsed_first) / 1e9

      printf "\n"
      printf "  Margine gaming benchmark summary\n"
      printf "  --------------------------------\n"
      printf "  Log file     : %s\n", fname
      printf "  Samples      : %d frames over %.1f s\n", n, dur_s
      if (dur_elapsed > 0) {
        printf "  Elapsed (xchk): %.1f s\n", dur_elapsed
      }
      printf "\n"
      printf "  FPS  (higher = better; lows show stutter)\n"
      printf "    Average      : %8.1f fps\n", avg_fps
      printf "    1%% low        : %8.1f fps\n", low1_fps
      printf "    0.1%% low      : %8.1f fps\n", low01_fps
      printf "    Min / Max    : %8.1f / %.1f fps\n", min_fps, max_fps
      printf "\n"
      printf "  Frametime (ms)  (lower = smoother)\n"
      printf "    Average      : %8.3f ms\n", avg_ft
      printf "    p99          : %8.3f ms\n", ft_p99
      printf "    Max (worst)  : %8.3f ms\n", ft_max
      printf "\n"
      # System context footer (from metadata passed in via -v).
      if (meta_gpu != "?") {
        printf "  System       : %s | %s | %s | %s\n\n", \
          meta_os, meta_cpu, meta_gpu, meta_kernel
      }
    }

    # Count-based low FPS (PURPOSE: "average FPS of the slowest p of frames
    # by frametime"). fts[] is sorted ASCENDING by the coreutils `sort -n`
    # pipeline, so the slowest k frames are the top k indices fts[n-k+1..n].
    # k = round(p * n), clamped to [1, n]. We average the per-frame FPS
    # (arithmetic mean of 1000/ft over those k frames), which is the literal
    # reading of "average FPS of the slowest 1% of frames".
    function low_fps(p,   k, i, sum_inv) {
      k = int(p * n + 0.5)          # nearest-integer count of frames
      if (k < 1) k = 1
      if (k > n) k = n
      sum_inv = 0
      for (i = n - k + 1; i <= n; i++) sum_inv += 1000.0 / fts[i]
      return sum_inv / k
    }
  '
}

cmd_summary() {
  local target=""
  case "${1:-}" in
    --latest|-l)
      [ -d "$LOG_DIR" ] || die "no log dir yet: $LOG_DIR"
      target=$(latest_log) || true
      [ -n "$target" ] || die "no logs found in $LOG_DIR"
      ;;
    "" ) die "summary needs --latest or a logfile (see '$PROG --help')" ;;
    * )  target="$1" ;;
  esac
  info "summarising: $target"
  summarise_csv "$target"
}

# ---------------------------------------------------------------------------
# run: wrap a launch command with MangoHud logging.
# ---------------------------------------------------------------------------
cmd_run() {
  local name="" do_summary=1
  # Parse 'run' options up to the '--' separator.
  while [ $# -gt 0 ]; do
    case "$1" in
      -d|--duration)   DURATION="${2:?--duration needs a value}"; shift 2 ;;
      -i|--interval)   LOG_INTERVAL="${2:?--interval needs a value}"; shift 2 ;;
      -o|--output-dir) LOG_DIR="${2:?--output-dir needs a value}"; shift 2 ;;
      -n|--name)       name="${2:?--name needs a value}"; shift 2 ;;
      --no-summary)    do_summary=0; shift ;;
      -h|--help)       usage; exit 0 ;;
      --)              shift; break ;;
      -*)              die "unknown option for run: $1" ;;
      *)               die "run expects options then '-- <command>' (got '$1')" ;;
    esac
  done

  [ $# -gt 0 ] || die "no launch command after '--' (see '$PROG --help')"

  # Validate numeric inputs up front so bad values fail loudly instead of
  # being silently swallowed (e.g. '--duration 1.5' or '--duration abc' would
  # otherwise leave MangoHud logging forever while the user expects a window).
  require_uint "duration (seconds)" "$DURATION"
  require_uint "interval (microseconds)" "$LOG_INTERVAL"

  # Sanity: MangoHud must be reachable somewhere. Even if the wrapped command
  # is a Flatpak that bundles its own, warn if the host one is absent so the
  # user knows where logging is coming from.
  if ! have mangohud; then
    info "note: host 'mangohud' not found; relying on the wrapped command"
    info "      (e.g. Flatpak Steam) to provide it. Install the gaming"
    info "      layer with: ujust margine-gaming"
  fi

  # Derive a label for filenames.
  if [ -z "$name" ]; then
    name="${1##*/}"          # basename of the first command token
    name="${name%% *}"       # first word only
    [ -n "$name" ] || name="session"
  fi

  # Create ONLY the log dir. Nothing else on disk is touched.
  mkdir -p -- "$LOG_DIR" || die "cannot create log dir: $LOG_DIR"
  [ -w "$LOG_DIR" ] || die "log dir not writable: $LOG_DIR"

  # Build the MangoHud config.
  #   autostart_log=1   start logging the instant the app starts rendering
  #   output_folder=... where to write (the only dir we ever touch)
  #   log_interval=us   sampling cadence (0 = every frame, best for lows)
  #   log_duration=s    auto-stop logging after N s (only if --duration > 0)
  # NOTE: we deliberately do NOT set MangoHud's output_file. MangoHud names
  # the on-disk file <appname>_<YYYY-MM-DD_HH-MM-SS>.csv in output_folder, so
  # instead of guessing the name we snapshot the dir before launch and detect
  # whatever new *.csv appears afterwards, then rename it to our label.
  local stamp
  stamp=$(date +%Y-%m-%d_%H-%M-%S)
  local mh_cfg="output_folder=${LOG_DIR},autostart_log=1,log_interval=${LOG_INTERVAL}"
  if [ "$DURATION" -gt 0 ]; then
    mh_cfg="${mh_cfg},log_duration=${DURATION}"
  fi

  # Decide whether we must prefix 'mangohud' ourselves. MangoHud's GL apps
  # need the 'mangohud' wrapper (it sets LD_PRELOAD); the MANGOHUD=1 env var
  # alone only auto-enables the Vulkan layer. If the user's command already
  # starts with mangohud or gamescope (which can inject mangohud), we respect
  # it and don't double-wrap.
  local -a launch
  case "$1" in
    mangohud|*/mangohud|gamescope|*/gamescope)
      launch=("$@")
      ;;
    *)
      if have mangohud; then
        launch=(mangohud "$@")
      else
        # No host mangohud (e.g. command is a Flatpak that bundles its own).
        # Run as-is and rely on MANGOHUD=1 inside the sandbox.
        launch=("$@")
      fi
      ;;
  esac

  info "log dir   : $LOG_DIR"
  info "label     : ${name}_${stamp}"
  if [ "$DURATION" -gt 0 ]; then
    info "duration  : ${DURATION}s (MangoHud auto-stops logging)"
  else
    info "duration  : until the wrapped process exits"
  fi
  info "interval  : ${LOG_INTERVAL}us (0 = every frame)"
  info "command   : ${launch[*]}"
  info "launching now — play your benchmark, then quit the game/app."

  # Snapshot existing per-frame CSVs (sorted) so we can identify the new one
  # afterwards. list_logs already excludes *_summary.csv; sort for comm.
  local before
  before=$(list_logs | sort || true)

  # Export so a nested mangohud/gamescope (and Vulkan apps) pick up config.
  export MANGOHUD=1
  export MANGOHUD_CONFIG="$mh_cfg"

  # Run the (possibly mangohud-prefixed) command. We keep going on non-zero
  # exit so we still summarise a partial capture.
  local rc=0
  "${launch[@]}" || rc=$?
  [ "$rc" -eq 0 ] || info "wrapped command exited with code $rc (continuing to summary)"

  # Detect the newly written per-frame CSV (present after, absent before).
  local after
  after=$(list_logs | sort || true)
  local produced
  produced=$(comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after") | tail -n1)
  # Fallback: if comm found nothing (e.g. identical names across runs in the
  # same second), take the newest CSV in the dir.
  [ -n "$produced" ] || produced=$(latest_log)

  if [ -z "$produced" ] || [ ! -f "$produced" ]; then
    info "no per-frame CSV was produced. Things to check:"
    info "  - the app actually rendered frames (MangoHud only logs frames)"
    info "  - for Flatpak Steam, run the flatpak overrides from 'steam-options'"
    info "  - try 'mangohud <app>' to confirm the overlay appears"
    return 0
  fi

  # Rename to our label so logs are self-describing and easy to find. We also
  # move the matching _summary.csv MangoHud wrote alongside it. Both stay
  # inside the log dir; nothing is ever deleted.
  local target="${LOG_DIR}/${name}_${stamp}.csv"
  local base="${produced%.csv}"
  if [ "$produced" != "$target" ]; then
    if mv -- "$produced" "$target" 2>/dev/null; then
      produced="$target"
    fi
    if [ -f "${base}_summary.csv" ]; then
      mv -- "${base}_summary.csv" "${LOG_DIR}/${name}_${stamp}_summary.csv" 2>/dev/null || true
    fi
  fi
  info "captured  : $produced"

  # Summarise the capture. Guard with '|| info ...' so that a summary error
  # (e.g. a present-but-frameless CSV exiting 3) does NOT propagate under
  # 'set -e' and fail the whole 'run' AFTER a successful capture+rename. The
  # capture is intact on disk regardless of the summary outcome.
  if [ "$do_summary" -eq 1 ]; then
    summarise_csv "$produced" || info "summary failed; capture saved at $produced"
  fi
}

# ---------------------------------------------------------------------------
# Dispatch.
# ---------------------------------------------------------------------------
main() {
  [ $# -gt 0 ] || { usage; exit 1; }
  local sub="$1"; shift
  case "$sub" in
    run)                 cmd_run "$@" ;;
    summary|sum)         cmd_summary "$@" ;;
    steam-options|steam) cmd_steam_options ;;
    list|ls)             cmd_list ;;
    -h|--help|help)      usage ;;
    *)                   die "unknown subcommand: $sub (try '$PROG --help')" ;;
  esac
}

main "$@"
