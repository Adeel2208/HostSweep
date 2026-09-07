#!/usr/bin/env bash
# E5: run the three dual-pass ablation configurations over the whole synthetic
# panel, N independent runs each, and score every output.
#
# Each run is a separate invocation of run_ablation.py under GNU time -v.
# Replicates are never derived from one another. The panel is deterministic, so
# identical accuracy across the three replicates is the expected result, not a
# defect -- see the replicate-spacing check in benchmark/run/audit.py.
#
# Idempotent: a (library, config, run) whose metrics JSON exists is skipped.
#
# Usage:
#     bash run_ablation_panel.sh <synthetic_dir> <results_dir> [runs]
#
# Environment:
#     THREADS  default 8
#     INDEX    hostsweep index name, default 'standard'
#
# Writes ablation.csv with library,config,run,sensitivity_pct,fpr_pct,runtime_min

set -uo pipefail

SYN_DIR="${1:?usage: run_ablation_panel.sh <synthetic_dir> <results_dir> [runs]}"
RESULTS="${2:?usage: run_ablation_panel.sh <synthetic_dir> <results_dir> [runs]}"
RUNS="${3:-3}"

THREADS="${THREADS:-8}"
INDEX="${INDEX:-standard}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIGS=(minimap2_only bowtie2_only dual_pass)

mkdir -p "$RESULTS"
say() { echo "[E5 $(date -u +%H:%M:%S)] $*"; }

if command -v gtime >/dev/null 2>&1; then TIME_BIN="gtime"
elif /usr/bin/time -v true >/dev/null 2>&1;  then TIME_BIN="/usr/bin/time"
else TIME_BIN=""; say "WARNING: GNU time absent; runtime/peak RSS will be NA"; fi

CSV="$RESULTS/ablation.csv"
[ -s "$CSV" ] || printf 'library,config,run,sensitivity_pct,fpr_pct,runtime_min\n' > "$CSV"

shopt -s nullglob
LIBS=("$SYN_DIR"/*_R1.fastq.gz)
[ ${#LIBS[@]} -gt 0 ] || { say "no libraries in $SYN_DIR"; exit 1; }
say "${#LIBS[@]} libraries x ${#CONFIGS[@]} configs x $RUNS runs"

for R1 in "${LIBS[@]}"; do
    LIB="$(basename "$R1" _R1.fastq.gz)"
    R2="${R1%_R1.fastq.gz}_R2.fastq.gz"
    [ -s "$R2" ] || { say "missing mate for $LIB, skipping"; continue; }
    DIR="$RESULTS/$LIB"; mkdir -p "$DIR"

    for CFG in "${CONFIGS[@]}"; do
        for N in $(seq 1 "$RUNS"); do
            MJ="$DIR/metrics_${CFG}_run${N}.json"
            if [ -s "$MJ" ]; then say "$LIB / $CFG / run $N: already scored"; continue; fi

            say "$LIB / $CFG / run $N"
            WD="$DIR/${CFG}_run${N}.work"
            TF="$DIR/${CFG}_run${N}.time"
            rm -rf "$WD"; mkdir -p "$WD"

            STATUS=0
            if [ -n "$TIME_BIN" ]; then
                "$TIME_BIN" -v -o "$TF" \
                    python "$SCRIPT_DIR/run_ablation.py" \
                        --r1 "$R1" --r2 "$R2" --sample "$LIB" \
                        --config "$CFG" --outdir "$WD" \
                        --index "$INDEX" --threads "$THREADS" \
                    > "$DIR/${CFG}_run${N}.stdout" 2> "$DIR/${CFG}_run${N}.stderr" \
                    || STATUS=$?
            else
                python "$SCRIPT_DIR/run_ablation.py" \
                    --r1 "$R1" --r2 "$R2" --sample "$LIB" \
                    --config "$CFG" --outdir "$WD" \
                    --index "$INDEX" --threads "$THREADS" \
                    > "$DIR/${CFG}_run${N}.stdout" 2> "$DIR/${CFG}_run${N}.stderr" \
                    || STATUS=$?
            fi

            if [ "$STATUS" -ne 0 ]; then
                echo "exit_status=$STATUS" > "$DIR/${CFG}_run${N}.failed"
                say "  FAILED exit=$STATUS (see ${CFG}_run${N}.stderr)"
                printf '%s,%s,%s,FAILED,FAILED,FAILED\n' "$LIB" "$CFG" "$N" >> "$CSV"
                rm -rf "$WD"
                continue
            fi

            SCORED="$WD/${LIB}_${CFG}_PROFILING.fastq.gz"
            if [ ! -s "$SCORED" ]; then
                echo "no profiling output" > "$DIR/${CFG}_run${N}.failed"
                say "  FAILED: exited 0 but produced no profiling output"
                printf '%s,%s,%s,FAILED,FAILED,FAILED\n' "$LIB" "$CFG" "$N" >> "$CSV"
                rm -rf "$WD"
                continue
            fi

            python "$SCRIPT_DIR/compute_metrics.py" \
                --truth-r1 "$R1" --cleaned "$SCORED" \
                --tool "$CFG" --tier profiling --out "$MJ" \
                >> "$DIR/${CFG}_run${N}.stdout" 2>&1 \
                || { echo "scoring failed" > "$DIR/${CFG}_run${N}.failed"
                     say "  FAILED during scoring"
                     printf '%s,%s,%s,FAILED,FAILED,FAILED\n' "$LIB" "$CFG" "$N" >> "$CSV"
                     rm -rf "$WD"; continue; }

            python - "$MJ" "$TF" "$LIB" "$CFG" "$N" "$CSV" <<'PYEOF'
import csv, json, re, sys
mj, tf, lib, cfg, run, out = sys.argv[1:7]
d = json.load(open(mj))
runtime = "NA"
try:
    for line in open(tf, errors="replace"):
        if "Elapsed (wall clock) time" in line:
            parts = line.split(": ")[-1].strip().split(":")
            if len(parts) == 3:
                secs = int(parts[0]) * 3600 + int(parts[1]) * 60 + float(parts[2])
            elif len(parts) == 2:
                secs = int(parts[0]) * 60 + float(parts[1])
            else:
                secs = float(parts[0])
            runtime = round(secs / 60, 4)
except OSError:
    pass
with open(out, "a", newline="") as fh:
    csv.writer(fh).writerow([lib, cfg, run,
                             d.get("sensitivity", ""),
                             d.get("false_positive_rate", ""),
                             runtime])
PYEOF

            # The work tree holds full intermediates; the evidence that matters
            # (metrics JSON, .time, stdout/stderr) is kept.
            rm -rf "$WD"
            say "  done"
        done
    done
done

say "ablation written to $CSV"
