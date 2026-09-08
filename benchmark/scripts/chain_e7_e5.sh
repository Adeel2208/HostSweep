#!/usr/bin/env bash
# Run E7 then E5 once E3 has finished, without leaving the machine idle between.
#
# Order is deliberate: E7 is ~2.5 h and E5 is ~27 h, so running the sweep first
# puts threshold_sweep.csv in hand roughly a day earlier at no cost to either.
#
# Nothing here runs concurrently with E3 or with each other. Every HostSweep
# invocation on this host peaks at 11.05-11.12 GB against an 11 GB ceiling, so
# two pipelines at once would OOM both.
#
# Usage:  bash chain_e7_e5.sh [runs]
set -uo pipefail

RUNS="${1:-3}"
ROOT="$HOME/hostsweep"
BENCH="$ROOT/bench"
REPO="$ROOT/HostSweep"
OUT="$ROOT/out"
SYN="$BENCH/synthetic"
SCRIPTS="$REPO/benchmark/scripts"

mkdir -p "$OUT"
say() { echo "[chain75 $(date -u +%H:%M:%S)] $*"; }

# shellcheck disable=SC1091
. "$ROOT/miniforge3/etc/profile.d/conda.sh"
conda activate hostsweep || { echo "cannot activate hostsweep" >&2; exit 1; }

export THREADS="${THREADS:-8}"
export HOSTSWEEP_BBDUK_MEM="${HOSTSWEEP_BBDUK_MEM:-3g}"

# Single instance for this chain itself.
exec 7>"$OUT/.chain75.lock"
if ! flock -n 7; then
    say "another chain holds .chain75.lock; exiting"; exit 0
fi

# --- wait for E3 -------------------------------------------------------
say "waiting for the E3 lock to clear"
exec 8>"$OUT/.e3.lock"
if ! flock -w 172800 8; then
    say "timed out waiting for E3"; exit 1
fi
flock -u 8
say "E3 finished"

say "rebuilding per_library.csv from whatever E3 produced"
python "$SCRIPTS/aggregate_results.py" --results "$OUT/results" \
    --synthetic "$SYN" --out-dir "$OUT" || say "aggregate failed (continuing)"

# --- E7: threshold sweep ----------------------------------------------
# Three libraries spanning the host-fraction range, named explicitly because
# the protocol requires stating which three:
#   SYN-CHM13-01   0.1%  low
#   SYN-CHM13-04   5%    medium
#   SYN-CHM13-07   40%   high
SWEEP_LIBS=(SYN-CHM13-01 SYN-CHM13-04 SYN-CHM13-07)

# VERIFY_FULL asserts that Step-8-only re-runs equal a complete pipeline run at
# one (H, L) point per library. It costs three extra full runs, roughly an
# hour, to validate a shortcut that saves about forty. Worth paying.
export VERIFY_FULL=1

say "E7 threshold sweep on ${SWEEP_LIBS[*]}"
bash "$SCRIPTS/run_e7.sh" "$SYN" "$OUT/sweep_results" "${SWEEP_LIBS[@]}" \
    || say "E7 returned non-zero; continuing to E5"

if [ -s "$OUT/sweep_results/threshold_sweep.csv" ]; then
    cp "$OUT/sweep_results/threshold_sweep.csv" "$OUT/threshold_sweep.csv"
    say "threshold_sweep.csv: $(( $(wc -l < "$OUT/threshold_sweep.csv") - 1 )) rows"
else
    say "threshold_sweep.csv was not produced"
fi
if [ -s "$OUT/sweep_results/equivalence_check.txt" ]; then
    say "equivalence check:"
    sed 's/^/    /' "$OUT/sweep_results/equivalence_check.txt"
fi

# --- E5: dual-pass ablation -------------------------------------------
say "E5 ablation over the full panel, $RUNS runs per configuration"
bash "$SCRIPTS/run_ablation_panel.sh" "$SYN" "$OUT/ablation_results" "$RUNS" \
    || say "E5 returned non-zero"

if [ -s "$OUT/ablation_results/ablation.csv" ]; then
    cp "$OUT/ablation_results/ablation.csv" "$OUT/ablation.csv"
    say "ablation.csv: $(( $(wc -l < "$OUT/ablation.csv") - 1 )) rows"
else
    say "ablation.csv was not produced"
fi

say "rebuilding per_library.csv"
python "$SCRIPTS/aggregate_results.py" --results "$OUT/results" \
    --synthetic "$SYN" --out-dir "$OUT" || true

say "chain complete"
