#!/usr/bin/env bash
# E4: run a tool over the real-library panel, N independent runs each.
#
# Separate from run_e3.sh for two reasons that matter:
#
#  1. Naming. fasterq-dump writes <run>_1.fastq.gz / _2.fastq.gz, while the
#     synthetic panel uses _R1/_R2. run_e3.sh globs only _R1 and would find
#     zero libraries here -- silently, reporting success over an empty set.
#
#  2. NO TRUTH SET. Real libraries have no per-read origin label, so
#     sensitivity and false-positive rate are NOT COMPUTABLE and are written
#     empty. run_e3.sh calls compute_metrics.py unconditionally, which would
#     score reads against a ground truth that does not exist. What is measured
#     here instead is what can be measured: reads in, reads out, retention,
#     wall clock and peak RSS.
#
# Idempotent and single-instance, like the other stages.
#
# Usage:
#     bash run_e4.sh <fastq_dir> <results_dir> [runs] [tool ...]
#
# Environment: THREADS (8), INDEX (standard), BT2_INDEX

set -uo pipefail

FASTQ_DIR="${1:?usage: run_e4.sh <fastq_dir> <results_dir> [runs] [tool ...]}"
RESULTS="${2:?}"
RUNS="${3:-3}"
shift 3 2>/dev/null || shift $#
TOOLS=("$@")
[ ${#TOOLS[@]} -gt 0 ] || TOOLS=(hostsweep)

THREADS="${THREADS:-8}"
INDEX="${INDEX:-standard}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$RESULTS"
say() { echo "[E4 $(date -u +%H:%M:%S)] $*"; }

LOCK="$RESULTS/.e4.lock"
exec 9>"$LOCK"
if ! flock -n 9; then
    say "another E4 run holds $LOCK; exiting"; exit 0
fi

if command -v gtime >/dev/null 2>&1; then TIME_BIN="gtime"
elif /usr/bin/time -v true >/dev/null 2>&1;  then TIME_BIN="/usr/bin/time"
else TIME_BIN=""; say "WARNING: GNU time absent; runtime/peak RSS will be NA"; fi

# Accept both conventions so this works on downloaded and hand-staged panels.
shopt -s nullglob
LIBS=("$FASTQ_DIR"/*_1.fastq.gz "$FASTQ_DIR"/*_R1.fastq.gz)
[ ${#LIBS[@]} -gt 0 ] || { say "no libraries in $FASTQ_DIR"; exit 1; }
say "${#LIBS[@]} libraries x ${#TOOLS[@]} tools x $RUNS runs"

for R1 in "${LIBS[@]}"; do
    if [[ "$R1" == *_R1.fastq.gz ]]; then
        LIB="$(basename "$R1" _R1.fastq.gz)"; R2="${R1%_R1.fastq.gz}_R2.fastq.gz"
    else
        LIB="$(basename "$R1" _1.fastq.gz)";  R2="${R1%_1.fastq.gz}_2.fastq.gz"
    fi
    [ -s "$R2" ] || { say "missing mate for $LIB, skipping"; continue; }
    DIR="$RESULTS/$LIB"; mkdir -p "$DIR"

    for TOOL in "${TOOLS[@]}"; do
        for N in $(seq 1 "$RUNS"); do
            MJ="$DIR/metrics_${TOOL}_run${N}.json"
            [ -s "$MJ" ] && { say "$LIB / $TOOL / run $N: already recorded"; continue; }

            say "$LIB / $TOOL / run $N"
            WD="$DIR/${TOOL}_run${N}.work"
            TF="$DIR/${TOOL}_run${N}.time"
            rm -rf "$WD"; mkdir -p "$WD"

            case "$TOOL" in
                hostsweep) CMD=(hostsweep -1 "$R1" -2 "$R2" -n "$LIB" -o "$WD"
                                -i "$INDEX" -t "$THREADS") ;;
                *) say "  no runner for '$TOOL' in E4"; continue ;;
            esac

            STATUS=0
            if [ -n "$TIME_BIN" ]; then
                "$TIME_BIN" -v -o "$TF" "${CMD[@]}" \
                    > "$DIR/${TOOL}_run${N}.stdout" 2> "$DIR/${TOOL}_run${N}.stderr" || STATUS=$?
            else
                "${CMD[@]}" > "$DIR/${TOOL}_run${N}.stdout" 2> "$DIR/${TOOL}_run${N}.stderr" || STATUS=$?
            fi

            if [ "$STATUS" -ne 0 ]; then
                echo "exit_status=$STATUS" > "$DIR/${TOOL}_run${N}.failed"
                say "  FAILED exit=$STATUS"
                rm -rf "$WD"; continue
            fi

            ASSEMBLY="$WD/cleaned/${LIB}_ASSEMBLY_R1.fastq.gz"
            PROFILING="$WD/cleaned/${LIB}_PROFILING.fastq.gz"
            if [ ! -s "$ASSEMBLY" ]; then
                echo "exited 0 but no assembly output" > "$DIR/${TOOL}_run${N}.failed"
                say "  FAILED: no cleaned output"; rm -rf "$WD"; continue
            fi

            python3 - "$R1" "$ASSEMBLY" "$PROFILING" "$LIB" "$TOOL" "$MJ" <<'PYEOF'
import gzip, json, sys

def count(path):
    try:
        with gzip.open(path, "rb") as fh:
            return sum(1 for i, _ in enumerate(fh) if i % 4 == 0)
    except OSError:
        return None

raw, assembly, profiling, lib, tool, out = sys.argv[1:7]
n_in, n_asm, n_prof = count(raw), count(assembly), count(profiling)
rec = {
    "library": lib,
    "tool": tool,
    "tier": "assembly",
    "truth_available": False,
    # Real libraries carry no per-read origin label. Sensitivity and false
    # positive rate are left empty deliberately: there is no ground truth to
    # score against, and an estimate here would be indistinguishable from a
    # measurement in the final table.
    "sensitivity": "",
    "false_positive_rate": "",
    "reads_in": n_in,
    "reads_assembly_tier": n_asm,
    "reads_profiling_tier": n_prof,
    "retention_assembly_pct": (round(100.0 * n_asm / n_in, 4)
                               if n_in and n_asm is not None else ""),
    "host_removed_pct": (round(100.0 * (n_in - n_asm) / n_in, 4)
                         if n_in and n_asm is not None else ""),
}
with open(out, "w") as fh:
    json.dump(rec, fh, indent=2)
print("recorded", lib, tool, "in", n_in, "assembly", n_asm, "profiling", n_prof)
PYEOF

            # Keep the cleaned tiers for E9; drop the bulky intermediates.
            KEEP="$DIR/cleaned_run${N}"
            if [ "$N" = "1" ]; then
                mkdir -p "$KEEP"
                cp "$WD/cleaned/"*.fastq.gz "$KEEP/" 2>/dev/null || true
            fi
            rm -rf "$WD"
            say "  done"
        done
    done
done

say "complete. Aggregate with aggregate_results.py"
