#!/usr/bin/env bash
# Run every remaining experiment, sequentially, unattended.
#
# Order is by value to the manuscript:
#   1. finish E9                     downstream.csv, kraken2_human.csv
#   2. comparator benchmark          the largest remaining gap: Editor 6 and 19,
#                                    and all three reviewers. hostile_matched,
#                                    hostile_default and kneaddata scored
#                                    against truth on all 12 synthetic libraries
#   3. E4 real-library scoring       per-category host removal, Editor point 1
#   4. aggregate + integrity + audit
#
# Everything runs ONE AT A TIME. Each HostSweep-class run peaks at 11.05-11.15 GB
# against an 11 GB ceiling, so two pipelines at once OOM both. This is why the
# chain exists instead of launching the stages in parallel.
#
# Every stage is idempotent: completed (library, tool, run) triples are skipped,
# so if this is interrupted it resumes exactly where it stopped and recomputes
# nothing. That has been exercised repeatedly on this host.
#
# n=1 throughout. E3 ran twelve libraries three times each and produced
# bit-identical sensitivity AND false positive rate in 12 of 12; the replicates
# proved determinism and added no accuracy information. Runtime varied by up to
# 3.7x, but that is paging against the memory ceiling rather than a property of
# any method (D17), so it is not reportable either.
#
# Usage:  bash chain_all.sh
set -uo pipefail

ROOT="$HOME/hostsweep"
REPO="$ROOT/HostSweep"
OUT="$ROOT/out"
BENCH="$ROOT/bench"
SYN="$BENCH/synthetic"
E4="$ROOT/e4_fastq"
SCRIPTS="$REPO/benchmark/scripts"

say() { echo "[ALL $(date -u +%FT%H:%M:%SZ)] $*"; }

# Refresh the clone first. A stale clone once cost three idle hours when a
# chain called a script that did not exist in it yet.
if [ -d "$REPO/.git" ]; then
    git -C "$REPO" fetch -q origin 2>/dev/null \
        && git -C "$REPO" reset -q --hard origin/main 2>/dev/null \
        && say "clone at $(git -C "$REPO" rev-parse --short HEAD)" \
        || say "WARNING: could not refresh clone; running what is on disk"
fi

# shellcheck disable=SC1091
. "$ROOT/miniforge3/etc/profile.d/conda.sh"
conda activate hostsweep || { echo "cannot activate hostsweep" >&2; exit 1; }

export THREADS="${THREADS:-8}"
export HOSTSWEEP_BBDUK_MEM="${HOSTSWEEP_BBDUK_MEM:-3g}"
export INDEX=standard
export BT2_INDEX="$ROOT/miniforge3/envs/hostsweep/share/hostsweep/databases/standard/human_bt2"
export K2DB="$ROOT/k2_standard_08gb"

exec 5>"$OUT/.chain_all.lock"
if ! flock -n 5; then say "another chain_all is running; exiting"; exit 0; fi

mkdir -p "$OUT/results" "$OUT/e4_results"

# --- 1. finish E9 -----------------------------------------------------
say "STAGE 1/4  E9 downstream (waiting for any running instance first)"
for _ in $(seq 1 2880); do
    pgrep -f chain_e9.sh >/dev/null 2>&1 || break
    sleep 30
done
bash "$SCRIPTS/chain_e9.sh" || say "E9 returned non-zero; continuing"
for f in downstream.csv kraken2_human.csv; do
    [ -s "$OUT/downstream_results/$f" ] && cp "$OUT/downstream_results/$f" "$OUT/$f" \
        && say "  $f: $(( $(wc -l < "$OUT/$f") - 1 )) rows"
done

# --- 2. comparator benchmark -----------------------------------------
# Scored against the same truth labels as HostSweep, by the same script, on the
# same libraries. hostile_matched uses the identical T2T Bowtie2 index every
# other method uses, so what differs is method rather than reference;
# hostile_default is Hostile as its authors intend it, with its own index.
say "STAGE 2/4  comparator benchmark on the synthetic panel"
bash "$SCRIPTS/run_e3.sh" "$SYN" "$OUT/results" 1 \
     hostile_matched hostile_default kneaddata \
    || say "comparators returned non-zero; continuing"

# --- 3. E4 real-library scoring --------------------------------------
# Real libraries carry no per-read origin label, so run_e4.sh records reads in,
# reads out and retention, and leaves sensitivity and FPR EMPTY rather than
# scoring against a ground truth that does not exist.
say "STAGE 3/4  E4 real-library scoring, HostSweep on 30 libraries"
if [ -d "$E4" ] && ls "$E4"/*_1.fastq.gz >/dev/null 2>&1; then
    bash "$SCRIPTS/run_e4.sh" "$E4" "$OUT/e4_results" 1 hostsweep \
        || say "E4 returned non-zero; continuing"
else
    say "  no reads in $E4; skipping"
fi

# --- 4. aggregate, verify, audit -------------------------------------
say "STAGE 4/4  aggregate and audit"
python "$SCRIPTS/aggregate_results.py" --results "$OUT/results" \
    --synthetic "$SYN" --out-dir "$OUT" || say "aggregate failed"
python "$SCRIPTS/aggregate_results.py" --results "$OUT/e4_results" \
    --synthetic "$SYN" --out-dir "$OUT/e4_agg" || say "E4 aggregate failed"
python "$SCRIPTS/verify_results_integrity.py" --results "$OUT/results" \
    || say "integrity check reported problems"
python "$REPO/benchmark/run/audit.py" --run-dir "$OUT" \
    --out "$OUT/AUDIT.md" || say "audit reported failures"

say "ALL STAGES COMPLETE"
say "outputs in $OUT: $(ls "$OUT"/*.csv 2>/dev/null | wc -l) CSV files"
