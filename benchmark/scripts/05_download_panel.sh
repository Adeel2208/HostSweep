#!/usr/bin/env bash
# E4 step 1: download the verified real-library panel from SRA.
#
# Reads benchmark/accessions.csv (the verified panel, comments ignored) and
# fetches each run as paired gzipped FASTQ.
#
# Idempotent: a run whose _1/_2 files already exist and are non-empty is
# skipped, so the job resumes after any interruption.
#
# Single-instance: takes an exclusive lock, because two downloaders writing the
# same output prefix would interleave and produce a corrupt FASTQ that still
# looks plausible -- the same failure that hit the mixing stage.
#
# A run that fails is recorded in failures.tsv with its exit status and left
# absent, never half-written and never substituted.
#
# Usage:  bash 05_download_panel.sh <outdir> [max_parallel]
set -uo pipefail

OUTDIR="${1:?usage: 05_download_panel.sh <outdir> [max_parallel]}"
JOBS="${2:-2}"
THREADS="${THREADS:-4}"

REPO="$HOME/hostsweep/HostSweep"
CSV="$REPO/benchmark/accessions.csv"
mkdir -p "$OUTDIR"

say() { echo "[E4dl $(date -u +%H:%M:%S)] $*"; }

LOCK="$OUTDIR/.download.lock"
exec 9>"$LOCK"
if ! flock -n 9; then
    say "another downloader holds $LOCK; exiting"
    exit 0
fi

for t in prefetch fasterq-dump pigz; do
    command -v "$t" >/dev/null 2>&1 || { say "MISSING $t on PATH"; MISSING=1; }
done
[ -z "${MISSING:-}" ] || { say "install sra-tools and pigz first"; exit 1; }

FAILURES="$OUTDIR/failures.tsv"
[ -s "$FAILURES" ] || printf 'run\tstage\texit_status\n' > "$FAILURES"

# Runs are the first column of the CSV, skipping comment lines and the header.
mapfile -t RUNS < <(grep -v '^#' "$CSV" | tail -n +2 | cut -d, -f1 | grep -v '^$')
say "${#RUNS[@]} runs to fetch into $OUTDIR (max $JOBS concurrent)"

fetch_one() {
    local run="$1"
    local r1="$OUTDIR/${run}_1.fastq.gz" r2="$OUTDIR/${run}_2.fastq.gz"
    if [ -s "$r1" ] && [ -s "$r2" ]; then
        say "  $run already present"; return 0
    fi
    say "  $run: prefetch"
    if ! prefetch --max-size 100G -O "$OUTDIR/sra" "$run" \
            > "$OUTDIR/${run}.prefetch.log" 2>&1; then
        printf '%s\tprefetch\t%s\n' "$run" "$?" >> "$FAILURES"
        say "  $run: prefetch FAILED"; return 1
    fi
    say "  $run: fasterq-dump"
    if ! fasterq-dump --split-3 --skip-technical -e "$THREADS" \
            -O "$OUTDIR" -t "$OUTDIR/tmp" "$OUTDIR/sra/$run" \
            > "$OUTDIR/${run}.dump.log" 2>&1; then
        printf '%s\tfasterq-dump\t%s\n' "$run" "$?" >> "$FAILURES"
        say "  $run: fasterq-dump FAILED"; return 1
    fi
    # --split-3 writes _1/_2 for paired runs; a single unsplit file means the
    # run is not actually paired, which the panel criteria should have excluded.
    if [ ! -s "$OUTDIR/${run}_1.fastq" ] || [ ! -s "$OUTDIR/${run}_2.fastq" ]; then
        printf '%s\tnot-paired\t0\n' "$run" >> "$FAILURES"
        say "  $run: no _1/_2 pair produced -- run is not paired despite metadata"
        rm -f "$OUTDIR/${run}"*.fastq
        return 1
    fi
    pigz -p "$THREADS" -f "$OUTDIR/${run}_1.fastq" "$OUTDIR/${run}_2.fastq"
    rm -rf "$OUTDIR/sra/$run"
    say "  $run: done ($(du -ch "$r1" "$r2" 2>/dev/null | tail -1 | cut -f1))"
}

declare -a PIDS=()
for RUN in "${RUNS[@]}"; do
    while [ "${#PIDS[@]}" -ge "$JOBS" ]; do
        wait "${PIDS[0]}" || true
        PIDS=("${PIDS[@]:1}")
    done
    fetch_one "$RUN" &
    PIDS+=($!)
done
for pid in "${PIDS[@]}"; do wait "$pid" || true; done

N=$(ls "$OUTDIR"/*_1.fastq.gz 2>/dev/null | wc -l)
say "complete: $N of ${#RUNS[@]} runs present"
say "failures recorded in $FAILURES"
[ -s "$OUTDIR/sra" ] && rm -rf "$OUTDIR/sra" "$OUTDIR/tmp"
