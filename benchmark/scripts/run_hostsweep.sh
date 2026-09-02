#!/usr/bin/env bash
# Run HostSweep over a directory of paired FASTQ files and record wall-clock
# time and peak RSS for each sample.
#
# Usage:
#     bash run_hostsweep.sh <fastq_dir> <results_dir> [index_name]
#
# Expects <fastq_dir>/<sample>_1.fastq.gz and <sample>_2.fastq.gz
# (or _R1/_R2, both suffix conventions are handled).

set -euo pipefail

FASTQ_DIR="${1:?usage: run_hostsweep.sh <fastq_dir> <results_dir> [index_name]}"
RESULTS_DIR="${2:?usage: run_hostsweep.sh <fastq_dir> <results_dir> [index_name]}"
INDEX="${3:-standard}"
THREADS="${THREADS:-8}"

command -v hostsweep >/dev/null 2>&1 || {
    echo "ERROR: hostsweep not on PATH. Run 'pip install -e .' in the repo root." >&2
    exit 1
}

mkdir -p "$RESULTS_DIR"
TIMING="$RESULTS_DIR/timing.tsv"
printf 'sample\twall_clock_seconds\tpeak_rss_kb\n' > "$TIMING"

# GNU time reports peak RSS; macOS /usr/bin/time does not, so fall back cleanly.
if command -v gtime >/dev/null 2>&1; then
    TIME_BIN="gtime"
elif /usr/bin/time -v true >/dev/null 2>&1; then
    TIME_BIN="/usr/bin/time"
else
    TIME_BIN=""
    echo "[run_hostsweep] NOTE: GNU time not found; peak RSS will be recorded as NA." >&2
fi

shopt -s nullglob
for R1 in "$FASTQ_DIR"/*_1.fastq.gz "$FASTQ_DIR"/*_R1.fastq.gz; do
    if [[ "$R1" == *_R1.fastq.gz ]]; then
        SAMPLE="$(basename "$R1" _R1.fastq.gz)"; R2="${R1%_R1.fastq.gz}_R2.fastq.gz"
    else
        SAMPLE="$(basename "$R1" _1.fastq.gz)";  R2="${R1%_1.fastq.gz}_2.fastq.gz"
    fi

    [ -s "$R2" ] || { echo "[run_hostsweep] missing mate for $R1, skipping" >&2; continue; }

    OUT="$RESULTS_DIR/$SAMPLE"
    echo "[run_hostsweep] === $SAMPLE ==="

    START=$(date +%s)
    if [ -n "$TIME_BIN" ]; then
        "$TIME_BIN" -v -o "$OUT.time" \
            hostsweep -1 "$R1" -2 "$R2" -n "$SAMPLE" -o "$OUT" -i "$INDEX" -t "$THREADS"
        RSS=$(grep -i 'Maximum resident set size' "$OUT.time" | grep -oE '[0-9]+' || echo NA)
    else
        hostsweep -1 "$R1" -2 "$R2" -n "$SAMPLE" -o "$OUT" -i "$INDEX" -t "$THREADS"
        RSS=NA
    fi
    END=$(date +%s)

    printf '%s\t%s\t%s\n' "$SAMPLE" "$((END - START))" "$RSS" >> "$TIMING"
done

echo "[run_hostsweep] timings written to $TIMING"
