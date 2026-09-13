#!/usr/bin/env bash
# Run every remaining experiment, sequentially, unattended.
#
# Order is by value to the manuscript:
#   1. finish E9                     downstream.csv, kraken2_human.csv
#   2. BMTagger index                built once, against the full T2T genome
#                                    (D20) -- untested at this scale before
#                                    this chain ran it for real
#   3. comparator benchmark          hostile_matched, hostile_default,
#                                    kneaddata AND bmtagger scored against
#                                    truth on all 12 synthetic libraries
#   4. E4 real-library scoring       per-category host removal, Editor point 1
#   5. CheckM2                       completeness/contamination over every
#                                    E9 assembly (D6 -- dropped on the
#                                    original 11 GB host, attempted here)
#   6. aggregate + integrity + audit
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

# --- 2. BMTagger index -------------------------------------------------
# Built once, reused by every library. Skips itself if already present.
say "STAGE 2/6  BMTagger index (D20; this is the first time this has run"
say "  against the full genome rather than a small test reference)"
BMT_DIR="$ROOT/bmtagger_index"
if conda env list | awk '{print $1}' | grep -qx bmtagger; then
    conda activate bmtagger
    bash "$SCRIPTS/07_build_bmtagger_index.sh" \
         "$CONDA_PREFIX/share/hostsweep/databases/standard/human_T2T.fasta" \
         "$BMT_DIR" \
        || say "  BMTagger index build FAILED; bmtagger will be skipped below"
    conda deactivate
    conda activate hostsweep
else
    say "  bmtagger conda env absent; skipping index build and the bmtagger tool"
fi

# --- 3. comparator benchmark -----------------------------------------
# Scored against the same truth labels as HostSweep, by the same script, on the
# same libraries. hostile_matched uses the identical T2T Bowtie2 index every
# other method uses, so what differs is method rather than reference;
# hostile_default is Hostile as its authors intend it, with its own index.
say "STAGE 3/6  comparator benchmark on the synthetic panel"
COMPARATOR_TOOLS=(hostile_matched hostile_default kneaddata)
if [ -s "$BMT_DIR/human.bitmask" ] && [ -s "$BMT_DIR/human.srprism.idx" ] && [ -s "$BMT_DIR/human.seqdb.nsq" ]; then
    export BMTAGGER_BITMASK="$BMT_DIR/human.bitmask"
    export BMTAGGER_SRPRISM="$BMT_DIR/human.srprism"
    export BMTAGGER_SEQDB="$BMT_DIR/human.seqdb"
    COMPARATOR_TOOLS+=(bmtagger)
else
    say "  BMTagger index incomplete; running without it (see stage 2 output)"
fi
bash "$SCRIPTS/run_e3.sh" "$SYN" "$OUT/results" 1 "${COMPARATOR_TOOLS[@]}" \
    || say "comparators returned non-zero; continuing"

# --- 4. E4 real-library scoring --------------------------------------
# Real libraries carry no per-read origin label, so run_e4.sh records reads in,
# reads out and retention, and leaves sensitivity and FPR EMPTY rather than
# scoring against a ground truth that does not exist.
say "STAGE 4/6  E4 real-library scoring, HostSweep on 30 libraries"
if [ -d "$E4" ] && ls "$E4"/*_1.fastq.gz >/dev/null 2>&1; then
    bash "$SCRIPTS/run_e4.sh" "$E4" "$OUT/e4_results" 1 hostsweep \
        || say "E4 returned non-zero; continuing"
else
    say "  no reads in $E4; skipping"
fi

# --- 5. CheckM2 ---------------------------------------------------------
# Dropped originally (D6): needed ~15 GB RAM plus its own database, over the
# original 11 GB ceiling. Attempted here since more memory may be available;
# if it still doesn't fit or won't install, run_checkm2.sh records that and
# this chain continues rather than guessing at what it would have said.
say "STAGE 5/6  CheckM2 over every E9 assembly (D6)"
if [ -d "$OUT/downstream_results" ]; then
    bash "$SCRIPTS/run_checkm2.sh" "$OUT/downstream_results" "$OUT/checkm2_results.csv" \
        || say "  CheckM2 returned non-zero; continuing (recorded FAILED rows where applicable)"
else
    say "  $OUT/downstream_results absent (E9 has not produced assemblies); skipping"
fi

# --- 6. aggregate, verify, audit -------------------------------------
say "STAGE 6/6  aggregate and audit"
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
