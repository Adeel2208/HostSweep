#!/usr/bin/env bash
# E3: score every tool configuration on the synthetic panel, N independent runs.
#
# Each run is a separate invocation of the tool under GNU `time -v`. Replicates
# are never derived from one another -- if the pipeline is deterministic and
# three runs give identical accuracy, that is the recorded result.
#
# Idempotent: a (library, tool, run) whose metrics JSON already exists is
# skipped, so the job is resumable after an interruption.
#
# Usage:
#     bash run_e3.sh <synthetic_dir> <results_dir> [runs] [tool ...]
#
#     tool = hostsweep | hostile_default | hostile_matched | kneaddata
#            | bmtagger | deconseq        (default: hostsweep only)
#
# Environment:
#     THREADS   default 8
#     INDEX     hostsweep index name, default 'standard'
#     BT2_INDEX bowtie2 index prefix for the matched comparators
#
# Outputs, per (library, tool, run):
#     <results_dir>/<library>/metrics_<tool>_run<N>.json    scored by compute_metrics.py
#     <results_dir>/<library>/<tool>_run<N>.time            GNU time -v
#     <results_dir>/<library>/<tool>_run<N>.stdout/.stderr  raw output
#
# A failed run writes a .failed marker carrying the exit status and leaves no
# metrics JSON, so Stage 9 provenance checks see the gap rather than a value.

set -uo pipefail

SYN_DIR="${1:?usage: run_e3.sh <synthetic_dir> <results_dir> [runs] [tool ...]}"
RESULTS="${2:?usage: run_e3.sh <synthetic_dir> <results_dir> [runs] [tool ...]}"
RUNS="${3:-3}"
shift 3 2>/dev/null || shift $#
TOOLS=("$@")
[ ${#TOOLS[@]} -gt 0 ] || TOOLS=(hostsweep)

THREADS="${THREADS:-8}"
INDEX="${INDEX:-standard}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$RESULTS"
say() { echo "[E3 $(date -u +%H:%M:%S)] $*"; }

if command -v gtime >/dev/null 2>&1; then TIME_BIN="gtime"
elif /usr/bin/time -v true >/dev/null 2>&1;  then TIME_BIN="/usr/bin/time"
else TIME_BIN=""; say "WARNING: GNU time absent; peak RSS will be NA"; fi

# Run <tool> on one library, one replicate. Echoes the cleaned output path(s)
# on success; returns non-zero on failure.
run_one() {
    local tool="$1" lib="$2" run="$3" r1="$4" r2="$5" dir="$6"
    local tf="$dir/${tool}_run${run}.time"
    local so="$dir/${tool}_run${run}.stdout" se="$dir/${tool}_run${run}.stderr"
    local wd="$dir/${tool}_run${run}.work"
    rm -rf "$wd"; mkdir -p "$wd"

    local -a CMD
    case "$tool" in
        hostsweep)
            CMD=(hostsweep -1 "$r1" -2 "$r2" -n "$lib" -o "$wd" -i "$INDEX" -t "$THREADS")
            ;;
        hostile_default)
            CMD=(hostile clean --fastq1 "$r1" --fastq2 "$r2" --threads "$THREADS" --output "$wd")
            ;;
        hostile_matched)
            CMD=(hostile clean --fastq1 "$r1" --fastq2 "$r2" --aligner bowtie2
                 --index "${BT2_INDEX:?set BT2_INDEX}" --threads "$THREADS" --output "$wd")
            ;;
        kneaddata)
            CMD=(kneaddata --input1 "$r1" --input2 "$r2"
                 --reference-db "${BT2_INDEX:?set BT2_INDEX}" --output "$wd"
                 --threads "$THREADS" --bypass-trf --remove-intermediate-output)
            ;;
        *)
            say "  no runner defined for '$tool'"; return 127 ;;
    esac

    if [ -n "$TIME_BIN" ]; then
        "$TIME_BIN" -v -o "$tf" "${CMD[@]}" > "$so" 2> "$se"
    else
        "${CMD[@]}" > "$so" 2> "$se"
    fi
}

# Where each tool leaves the reads that should be scored.
cleaned_paths() {
    local tool="$1" lib="$2" wd="$3"
    case "$tool" in
        hostsweep)        echo "$wd/cleaned/${lib}_PROFILING.fastq.gz" ;;
        hostile_default|hostile_matched)
                          ls "$wd"/*.clean_1.fastq.gz "$wd"/*.clean_2.fastq.gz 2>/dev/null ;;
        kneaddata)        ls "$wd"/*paired_1.fastq "$wd"/*paired_2.fastq 2>/dev/null ;;
    esac
}

shopt -s nullglob
LIBS=("$SYN_DIR"/*_R1.fastq.gz)
[ ${#LIBS[@]} -gt 0 ] || { say "no libraries in $SYN_DIR"; exit 1; }
say "${#LIBS[@]} libraries x ${#TOOLS[@]} tools x $RUNS runs"

for R1 in "${LIBS[@]}"; do
    LIB="$(basename "$R1" _R1.fastq.gz)"
    R2="${R1%_R1.fastq.gz}_R2.fastq.gz"
    [ -s "$R2" ] || { say "missing mate for $LIB, skipping"; continue; }
    DIR="$RESULTS/$LIB"; mkdir -p "$DIR"

    for TOOL in "${TOOLS[@]}"; do
        for N in $(seq 1 "$RUNS"); do
            MJ="$DIR/metrics_${TOOL}_run${N}.json"
            if [ -s "$MJ" ]; then say "$LIB / $TOOL / run $N: already scored"; continue; fi

            say "$LIB / $TOOL / run $N"
            STATUS=0
            run_one "$TOOL" "$LIB" "$N" "$R1" "$R2" "$DIR" || STATUS=$?

            WD="$DIR/${TOOL}_run${N}.work"
            if [ "$STATUS" -ne 0 ]; then
                echo "exit_status=$STATUS" > "$DIR/${TOOL}_run${N}.failed"
                say "  FAILED exit=$STATUS (see ${TOOL}_run${N}.stderr)"
                continue
            fi

            mapfile -t CLEAN < <(cleaned_paths "$TOOL" "$LIB" "$WD")
            if [ ${#CLEAN[@]} -eq 0 ]; then
                echo "exit_status=0 but no cleaned output found" > "$DIR/${TOOL}_run${N}.failed"
                say "  FAILED: tool exited 0 but produced no cleaned reads"
                continue
            fi

            python3 "$SCRIPT_DIR/compute_metrics.py" \
                --truth-r1 "$R1" \
                --cleaned "${CLEAN[@]}" \
                --tool "$TOOL" --tier profiling \
                --out "$MJ" >> "$DIR/${TOOL}_run${N}.stdout" 2>&1 \
                || { echo "scoring failed" > "$DIR/${TOOL}_run${N}.failed"
                     say "  FAILED during scoring"; continue; }

            # The work tree holds the tool's intermediates and is large; the
            # evidence that matters (metrics, .time, stdout/stderr) is kept.
            rm -rf "$WD"
            say "  done"
        done
    done
done

say "complete. Aggregate with: python3 $SCRIPT_DIR/aggregate_results.py $RESULTS"
