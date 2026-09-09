#!/usr/bin/env bash
# Wait for the synthetic panel to finish building, then run E3 (HostSweep only).
#
# Exists to remove idle time at the handover: E2 takes hours, and starting E3
# by hand afterwards wastes whatever gap falls between them.
#
# Waits on the E2 lock rather than on a process name, so it cannot race a
# builder that has not started yet or one that is mid-restart.
#
# Usage:  bash chain_e3.sh [runs]
set -uo pipefail

RUNS="${1:-3}"
ROOT="$HOME/hostsweep"
BENCH="$ROOT/bench"
REPO="$ROOT/HostSweep"
OUT="$ROOT/out"
LOCK="$BENCH/.e2.lock"
SYN="$BENCH/synthetic"
EXPECTED=12

say() { echo "[chain $(date -u +%H:%M:%S)] $*"; }

# shellcheck disable=SC1091
. "$ROOT/miniforge3/etc/profile.d/conda.sh"
conda activate hostsweep || { echo "cannot activate hostsweep" >&2; exit 1; }

mkdir -p "$OUT"
# Claim the E3 lock FIRST, before any slow step.
#
# It used to be taken just before run_e3.sh, after waiting on E2 and running
# the aggregate. chain_e7_e5.sh waits on this same lock to know E3 has
# finished, and in that window it acquired the lock, concluded E3 was done and
# started E7 alongside a still-running E3 -- two pipelines against an 11 GB
# ceiling, which is precisely what the locking exists to prevent. Holding it
# from the outset closes the window.
exec 8>"$OUT/.e3.lock"
if ! flock -n 8; then
    say "another E3 chain holds $OUT/.e3.lock; exiting"
    exit 0
fi

say "waiting for the E2 lock to clear"
# flock -w blocks until the builder releases the lock, then we drop it again.
exec 9>"$LOCK"
if ! flock -w 86400 9; then
    say "timed out waiting for E2"; exit 1
fi
flock -u 9
say "E2 finished"

BUILT=$(ls "$SYN"/*_manifest.json 2>/dev/null | wc -l)
say "libraries with a manifest: $BUILT / $EXPECTED"
if [ "$BUILT" -eq 0 ]; then
    say "no libraries were built; not starting E3"
    exit 1
fi
if [ "$BUILT" -lt "$EXPECTED" ]; then
    say "WARNING: proceeding with $BUILT of $EXPECTED libraries; the missing"
    say "         ones will simply be absent from per_library.csv, not faked"
fi

say "writing synthetic_manifest.csv"
python "$REPO/benchmark/scripts/aggregate_results.py" \
    --results "$OUT/results" \
    --synthetic "$SYN" \
    --out-dir "$OUT" || say "aggregate failed (continuing)"

# Single-instance lock on E3 itself. Two chains would each launch run_e3.sh
# against the same metrics paths, which is the same class of corruption that
# hit the mixing stage. fd 8, because fd 9 held the E2 lock above.
# (The E3 lock is already held from the top of this script.)

say "starting E3, HostSweep only, $RUNS runs per library"
bash "$REPO/benchmark/scripts/run_e3.sh" \
     "$SYN" "$OUT/results" "$RUNS" hostsweep

say "E3 finished; rebuilding per_library.csv"
python "$REPO/benchmark/scripts/aggregate_results.py" \
    --results "$OUT/results" \
    --synthetic "$SYN" \
    --out-dir "$OUT"

say "done"
