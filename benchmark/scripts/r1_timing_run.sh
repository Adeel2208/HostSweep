#!/usr/bin/env bash
# R1: the clean timing run.
#
#   5 tools x 12 synthetic libraries x 3 replicates = 180 runs
#   hostsweep, hostile_default, hostile_matched, kneaddata, bmtagger
#
# Identical input FASTQs, one fixed thread count for every tool (THREADS,
# default 8), every run under /usr/bin/time -v, replicates as separate
# invocations. Per run it records wall-clock, peak RSS, exit status and swap
# counters (from the time record and from /proc/vmstat), plus sensitivity and
# FPR from compute_metrics.py.
#
# Nothing else may run on the machine while this does: it is a timing
# measurement. (run_remaining.sh keeps every download and other stage out of
# its way.)
#
# Protocol details that belong in the Methods, all logged here:
#   * a discarded warm-up pass first, so a cold disk cache is not charged to
#     whichever tool touches an index first
#   * each library's FASTQ is read once before its runs (WARM_INPUT=1)
#   * BMTagger's decompression of its input happens outside its timed section
#   * Hostile's default index is proven to work BEFORE the first timed run (so
#     D21 cannot recur inside the run); if it cannot be obtained, the script
#     stops instead of recording 36 FAILED rows -- or, with
#     SKIP_HOSTILE_DEFAULT=1, leaves hostile_default out
#
# Outputs, under ~/hostsweep/out:
#     r1_results/<lib>/...        raw evidence for every run
#     r1/per_library.csv          the same 11 columns as the committed file
#     r1/synthetic_manifest.csv
#     r1/run_details.csv          exit status, swap counters, page faults, CPU time
#     r1/timing_summary.csv       n, means, SDs; across-run vs across-library spread
#     r1/swap_check.txt           did any run page?
#     r1/machine.txt              CPU, RAM, swap state, thread count
#
# Resumable: finished (library, tool, run) triples are skipped.
#
# Usage:  bash benchmark/scripts/r1_timing_run.sh

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/r_common.sh"

R1_RES="$OUT/r1_results"; R1_OUT="$OUT/r1"
mkdir -p "$R1_RES" "$R1_OUT"
exec 6>"$OUT/.r1.lock"; flock -n 6 || { rsay "R1 already running; exiting"; exit 0; }

rsay "R1: clean timing run (threads per run: $THREADS)"
conda activate hostsweep || { rsay "cannot activate the hostsweep env"; exit 1; }

# The 12 libraries must all be here, or R1 is not R1.
link_libs "$OUT/r1_syn" "$SYN" "${ORIGINAL_LIBS[@]}" || { rsay "the synthetic panel is incomplete under $SYN"; exit 1; }
tools_for_timing || exit 1
[ "${SKIP_HOSTILE_DEFAULT:-0}" = 1 ] || ensure_hostile_index || exit 1

record_swap_state "$R1_OUT/machine.txt"
SWAP_KB="$(awk '/SwapTotal/ {print $2}' /proc/meminfo)"
if [ "${SWAP_KB:-0}" -gt 0 ]; then
    rsay "NOTE: swap is on ($(( SWAP_KB/1048576 )) GB). Runs are still valid if no run touched it -- the per-run swap"
    rsay "  counters decide that, and r1/swap_check.txt reports it. To remove the question, disable swap first"
    rsay "  (WSL: swap=0 in .wslconfig then 'wsl --shutdown'; Linux: sudo swapoff -a)."
fi
AVAIL_GB=$(( $(awk '/MemAvailable/ {print $2}' /proc/meminfo) / 1048576 ))
rsay "RAM available: ${AVAIL_GB} GB (a HostSweep run peaks near 11 GB, BMTagger near 8 GB)"

warmup_tools "$OUT/r1_syn" "SYN-CHM13-01" "${TIMING_TOOLS[@]}"

rsay "starting: ${#ORIGINAL_LIBS[@]} libraries x ${#TIMING_TOOLS[@]} tools x 3 runs = $(( ${#ORIGINAL_LIBS[@]} * ${#TIMING_TOOLS[@]} * 3 ))"
KEEP_CLEANED=0 WARM_INPUT=1 bash "$SCRIPTS/run_e3.sh" "$OUT/r1_syn" "$R1_RES" 3 "${TIMING_TOOLS[@]}" \
    || rsay "run_e3.sh returned non-zero; summarising whatever completed"

conda activate hostsweep
python "$SCRIPTS/aggregate_results.py" --results "$R1_RES" --synthetic "$SYN" --out-dir "$R1_OUT" \
    || rsay "aggregate failed"
python "$SCRIPTS/timing_summary.py" --results "$R1_RES" --out-dir "$R1_OUT" --threads "$THREADS" \
    || rsay "timing summary failed"

N="$(( $(wc -l < "$R1_OUT/per_library.csv" 2>/dev/null || echo 1) - 1 ))"
F="$(grep -c ',FAILED,FAILED,' "$R1_OUT/per_library.csv" 2>/dev/null || echo 0)"
rsay "R1 complete: $N rows in r1/per_library.csv ($F FAILED); 180 expected with all five tools"
