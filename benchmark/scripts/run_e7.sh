#!/usr/bin/env bash
# E7: entropy x minimum-length threshold sweep on three synthetic libraries.
#
#     entropy H in {0.75, 0.80, 0.85, 0.90, 0.95}
#     length  L in {70, 80, 90, 100, 110}
#
# ---------------------------------------------------------------------------
# Why this does not re-run the whole pipeline 25 times per library
#
# --bbeg and --stringent-minlen are consumed only by Step 8, whose input is the
# Step 7 profiling output:
#
#     run_bbduk_stringent(profiling_out, stringent_out, entropy, min_length, ...)
#
# Steps 0-7 do not read either parameter, so their output is byte-identical
# across all 25 combinations. This script therefore runs the full pipeline ONCE
# per library to produce the profiling tier, then runs Step 8 alone 25 times
# against it. The stringent outputs are identical to those a full re-run would
# produce, at roughly 1/25th of the compute.
#
# The equivalence is asserted, not assumed: with --verify-full the script also
# does one complete `hostsweep` run at one (H, L) point per library and
# compares read counts against the cached path. A mismatch is a hard failure.
# ---------------------------------------------------------------------------
#
# Usage:
#     bash run_e7.sh <synthetic_dir> <results_dir> <lib1> <lib2> <lib3>
#
# Environment:
#     THREADS  default 8
#     INDEX    hostsweep index name, default 'standard'
#     VERIFY_FULL  set to 1 to run the equivalence check

set -uo pipefail

SYN_DIR="${1:?usage: run_e7.sh <synthetic_dir> <results_dir> <lib>...}"
RESULTS="${2:?usage: run_e7.sh <synthetic_dir> <results_dir> <lib>...}"
shift 2
LIBS=("$@")
[ ${#LIBS[@]} -gt 0 ] || { echo "give at least one library" >&2; exit 1; }

THREADS="${THREADS:-8}"
INDEX="${INDEX:-standard}"
VERIFY_FULL="${VERIFY_FULL:-0}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ENTROPIES=(0.75 0.80 0.85 0.90 0.95)
LENGTHS=(70 80 90 100 110)

mkdir -p "$RESULTS"
CSV="$RESULTS/threshold_sweep.csv"
[ -s "$CSV" ] || printf 'library,entropy,min_length,host_sensitivity_pct,microbial_fpr_pct,microbial_retention_pct,residual_human_reads\n' > "$CSV"

say() { echo "[E7 $(date -u +%H:%M:%S)] $*"; }

BBDUK_MEM="${HOSTSWEEP_BBDUK_MEM:-2g}"

for LIB in "${LIBS[@]}"; do
    R1="$SYN_DIR/${LIB}_R1.fastq.gz"
    R2="$SYN_DIR/${LIB}_R2.fastq.gz"
    [ -s "$R1" ] && [ -s "$R2" ] || { say "SKIP $LIB: reads absent"; continue; }

    BASE="$RESULTS/$LIB/base"
    PROFILING="$BASE/cleaned/${LIB}_PROFILING.fastq.gz"

    # --- steps 0-7, once ---------------------------------------------
    if [ -s "$PROFILING" ]; then
        say "$LIB: profiling tier already built"
    else
        say "$LIB: building the profiling tier (full pipeline, once)"
        mkdir -p "$RESULTS/$LIB"
        /usr/bin/time -v -o "$RESULTS/$LIB/base.time" \
            hostsweep -1 "$R1" -2 "$R2" -n "$LIB" -o "$BASE" -i "$INDEX" \
                      -t "$THREADS" --keep-intermediates \
            > "$RESULTS/$LIB/base.stdout" 2> "$RESULTS/$LIB/base.stderr" \
            || { say "$LIB: FAILED building profiling tier"; continue; }
    fi
    [ -s "$PROFILING" ] || { say "$LIB: no profiling output; skipping sweep"; continue; }

    # --- step 8 only, 25 times ---------------------------------------
    for H in "${ENTROPIES[@]}"; do
        for L in "${LENGTHS[@]}"; do
            TAG="H${H}_L${L}"
            MJ="$RESULTS/$LIB/metrics_${TAG}.json"
            if [ -s "$MJ" ]; then say "$LIB $TAG: already scored"; continue; fi

            OUT="$RESULTS/$LIB/${LIB}_${TAG}_STRINGENT.fastq.gz"
            say "$LIB $TAG"
            /usr/bin/time -v -o "$RESULTS/$LIB/${TAG}.time" \
                bbduk.sh in="$PROFILING" out="$OUT" entropy="$H" minlen="$L" \
                         threads="$THREADS" -Xmx"$BBDUK_MEM" \
                > "$RESULTS/$LIB/${TAG}.stdout" 2> "$RESULTS/$LIB/${TAG}.stderr" \
                || { say "  FAILED bbduk"; echo "bbduk failed" > "$RESULTS/$LIB/${TAG}.failed"; continue; }

            python3 "$SCRIPT_DIR/compute_metrics.py" \
                --truth-r1 "$R1" --cleaned "$OUT" \
                --tool "hostsweep_${TAG}" --tier stringent --out "$MJ" \
                >> "$RESULTS/$LIB/${TAG}.stdout" 2>&1 \
                || { say "  FAILED scoring"; echo "scoring failed" > "$RESULTS/$LIB/${TAG}.failed"; continue; }

            python3 - "$MJ" "$LIB" "$H" "$L" "$CSV" <<'PYEOF'
import json, sys, csv
mj, lib, h, l, out = sys.argv[1:6]
d = json.load(open(mj))
with open(out, "a", newline="") as fh:
    csv.writer(fh).writerow([
        lib, h, l,
        d.get("sensitivity", ""),
        d.get("false_positive_rate", ""),
        d.get("background_retention", ""),
        d.get("false_negatives_human_retained", ""),
    ])
PYEOF
            rm -f "$OUT"
        done
    done

    # --- equivalence check -------------------------------------------
    if [ "$VERIFY_FULL" = "1" ]; then
        say "$LIB: verifying cached Step 8 == a full pipeline run at H=0.85 L=90"
        FULL="$RESULTS/$LIB/verify_full"
        rm -rf "$FULL"
        hostsweep -1 "$R1" -2 "$R2" -n "$LIB" -o "$FULL" -i "$INDEX" -t "$THREADS" \
                  --bbeg 0.85 --stringent-minlen 90 \
            > "$RESULTS/$LIB/verify_full.stdout" 2>&1 \
            || { say "  verification run FAILED"; continue; }

        bbduk.sh in="$PROFILING" out="$RESULTS/$LIB/verify_cached.fastq.gz" \
                 entropy=0.85 minlen=90 threads="$THREADS" -Xmx"$BBDUK_MEM" \
            > /dev/null 2>&1
        A=$(( $(zcat "$FULL/cleaned/${LIB}_STRINGENT.fastq.gz" | wc -l) / 4 ))
        B=$(( $(zcat "$RESULTS/$LIB/verify_cached.fastq.gz" | wc -l) / 4 ))
        if [ "$A" -eq "$B" ]; then
            say "  OK: full=$A cached=$B"
            echo "library=$LIB full=$A cached=$B MATCH" >> "$RESULTS/equivalence_check.txt"
        else
            say "  MISMATCH: full=$A cached=$B -- the sweep shortcut is INVALID"
            echo "library=$LIB full=$A cached=$B MISMATCH" >> "$RESULTS/equivalence_check.txt"
            exit 1
        fi
        rm -rf "$FULL" "$RESULTS/$LIB/verify_cached.fastq.gz"
    fi
done

say "sweep written to $CSV"
