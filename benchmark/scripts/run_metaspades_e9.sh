#!/usr/bin/env bash
# R2: downstream assembly with metaSPAdes (replaces MEGAHIT, closes D4).
#
# Three cleaning methods x six libraries = 18 (library, method) pairs, each
# assembled REPS times (default 2) as SEPARATE metaspades.py invocations, so
# the replicate spread measures metaSPAdes' own run-to-run behaviour and not a
# copy of one result. MEGAHIT's non-determinism is already a reported finding
# (D18); this shows whether metaSPAdes shares it.
#
# Inputs are the cleaned paired reads E9 already staged, so the cleaning step is
# NOT redone and the assemblers see the same reads:
#     <cleaned_root>/<lib>/<method>_R1.fastq.gz + _R2.fastq.gz
# The sha256 of every input is written to <results>/inputs_sha256.txt.
#
# Loop order is replicate-major (every pair once, then every pair again), so an
# interrupted run always leaves a complete first replicate first.
#
# MetaQUAST 5.3.0 afterwards: synthetic libraries against the ten-genome
# reference set (-r); real libraries with --max-ref-number 0, which stops
# MetaQUAST fetching its own references (I2). Do not remove that flag.
#
# Outputs (in <results_dir>):
#     downstream_metaspades.csv             replicate 1, same columns as downstream.csv
#     downstream_metaspades_replicates.csv  every replicate, plus wall time,
#                                           peak memory, threads, memory limit
#     <lib>/<method>/metaspades_rep<N>/     assembly + .time + stdout/stderr
#     metaquast/<lib>_<method>_rep<N>/      MetaQUAST reports
#
# Usage:
#     bash run_metaspades_e9.sh <cleaned_root> <results_dir> <refs_dir> <lib> [lib ...]
#
# Environment:
#     THREADS      default min(nproc, 32)
#     SPADES_MEM   memory limit in GB handed to metaSPAdes (-m). Default 120 or
#                  MemAvailable - 6 GB, whichever is smaller. The value used is
#                  recorded in the replicates CSV; if it is below 120, say so
#                  in the Methods (the specification asked for -m 120).
#     REPS         default 2
#     SPADES_MAX_ATTEMPTS  default 3 (I4, see below)
#     SPADES_TIMEOUT       per-attempt wall-clock limit in seconds, default
#                          10800 (3 hours). A hung attempt does not exit on its
#                          own, so it would never reach the retry logic below
#                          without this -- observed directly: one attempt ran
#                          20+ hours with no crash and no progress (I4).
#
# Idempotent: a finished assembly (SPAdes' own "Thank you for using SPAdes"
# line in spades.log) is not redone.
#
# I4: spades-hammer (metaSPAdes' BayesHammer error-correction step) fails
# intermittently at high thread counts, in two different ways -- confirmed
# non-deterministic, since the identical command on the identical pair showed
# both: (a) a segfault, inside libgomp/OpenMP during the second multithreaded
# k-mer-counting pass, anywhere from 3 minutes to ~13 hours in, and (b) a run
# that produced no crash and no progress for 20+ hours -- a hang, not a slow
# success. Memory use at the point of failure is nowhere near the -m limit in
# every case observed, ruling out a resource-limit crash. Mitigated two ways:
# each (library, method, replicate) gets up to SPADES_MAX_ATTEMPTS tries,
# halving the thread count each retry (floor 4) -- fewer threads means fewer
# possible races, the standard mitigation for this class of bug -- and each
# attempt is wrapped in SPADES_TIMEOUT, so a hang is force-killed and counted
# as a failed attempt rather than blocking the whole run indefinitely. Only
# marked FAILED if every attempt fails or times out; each failed attempt's
# stderr and spades.log are kept (metaspades_rep<N>.attempt<k>_<threads>t.*)
# as evidence.

set -uo pipefail

CLEAN_ROOT="${1:?usage: run_metaspades_e9.sh <cleaned_root> <results_dir> <refs_dir> <lib>...}"
RESULTS="${2:?}"
REFS_DIR="${3:?}"
shift 3
LIBS=("$@")
[ ${#LIBS[@]} -gt 0 ] || { echo "give at least one library" >&2; exit 1; }

NPROC="$(nproc 2>/dev/null || echo 8)"
THREADS="${THREADS:-$(( NPROC < 32 ? NPROC : 32 ))}"
REPS="${REPS:-2}"
AVAIL_GB=$(( $(awk '/MemAvailable/ {print $2}' /proc/meminfo) / 1048576 ))
DEFAULT_MEM=$(( AVAIL_GB - 6 )); [ "$DEFAULT_MEM" -gt 120 ] && DEFAULT_MEM=120
SPADES_MEM="${SPADES_MEM:-$DEFAULT_MEM}"
[ "$SPADES_MEM" -ge 16 ] || { echo "only ${AVAIL_GB} GB RAM available; metaSPAdes cannot run sensibly" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONDA_SH="${CONDA_SH:-$HOME/hostsweep/miniforge3/etc/profile.d/conda.sh}"
METHODS=(hostsweep kneaddata hostile)
DS="$RESULTS/downstream_metaspades.csv"
REPS_CSV="$RESULTS/downstream_metaspades_replicates.csv"
mkdir -p "$RESULTS/metaquast"

say() { echo "[R2 $(date -u +%H:%M:%S)] $*"; }
condition_of() {
    case "$1" in
        SYN-CHM13-*) echo synthetic_matched ;;
        SYN-NEU-*|SYN-IND-*|SYN-KHV-*|SYN-MSL-*|SYN-CLM-*) echo synthetic_mismatch ;;
        *) echo real ;;
    esac
}

# shellcheck disable=SC1090
. "$CONDA_SH"
conda env list | awk '{print $1}' | grep -qx spades || { say "no 'spades' conda env (bash install_comparators.sh spades)"; exit 1; }
conda env list | awk '{print $1}' | grep -qx megahit || { say "no 'megahit' conda env (it provides MetaQUAST)"; exit 1; }

say "metaSPAdes: ${#LIBS[@]} libraries x ${#METHODS[@]} methods x $REPS replicates; threads=$THREADS, -m $SPADES_MEM (of ${AVAIL_GB} GB available)"
[ "$SPADES_MEM" -lt 120 ] && say "NOTE: -m $SPADES_MEM is below the specified 120; record this in the Methods"

# Provenance of the inputs.
SHA="$RESULTS/inputs_sha256.txt"
for LIB in "${LIBS[@]}"; do
    for METHOD in "${METHODS[@]}"; do
        for f in "$CLEAN_ROOT/$LIB/${METHOD}_R1.fastq.gz" "$CLEAN_ROOT/$LIB/${METHOD}_R2.fastq.gz"; do
            [ -s "$f" ] || continue
            grep -q "  $f\$" "$SHA" 2>/dev/null || sha256sum "$f" >> "$SHA"
        done
    done
done

for REP in $(seq 1 "$REPS"); do
    for LIB in "${LIBS[@]}"; do
        COND="$(condition_of "$LIB")"
        for METHOD in "${METHODS[@]}"; do
            R1="$CLEAN_ROOT/$LIB/${METHOD}_R1.fastq.gz"; R2="$CLEAN_ROOT/$LIB/${METHOD}_R2.fastq.gz"
            if [ ! -s "$R1" ] || [ ! -s "$R2" ]; then
                say "$LIB/$METHOD rep$REP: cleaned reads absent, skipping"; continue
            fi
            D="$RESULTS/$LIB/$METHOD/metaspades_rep$REP"
            CONTIGS="$D/contigs.fasta"
            mkdir -p "$RESULTS/$LIB/$METHOD"

            # Clear any row already recorded for this exact key before deciding
            # what to do. Without this, a pair that previously exhausted its
            # retries and got a FAILED row -- then succeeds on a later restart
            # -- has its fresh, real result silently dropped: parse_metaquast.py
            # and the FAILED-row writer below both treat "a row already exists
            # for this key" as "already recorded, nothing to do", which was
            # meant for true reruns of a still-good result, not for replacing a
            # stale failure. Confirmed by test: a pair seeded with a FAILED row
            # that then succeeds keeps showing FAILED without this.
            if [ -s "$DS" ]; then
                grep -v "^$LIB,$COND,$METHOD," "$DS" > "$DS.tmp" && mv "$DS.tmp" "$DS"
            fi
            if [ -s "$REPS_CSV" ]; then
                grep -v "^$LIB,$COND,$METHOD,$REP," "$REPS_CSV" > "$REPS_CSV.tmp" && mv "$REPS_CSV.tmp" "$REPS_CSV"
            fi

            if [ -s "$CONTIGS" ] && grep -q "Thank you for using SPAdes" "$D/spades.log" 2>/dev/null; then
                say "$LIB/$METHOD rep$REP: assembly present"
                ASM_THREADS_USED="$THREADS"
            else
                MAX_ATTEMPTS="${SPADES_MAX_ATTEMPTS:-3}"
                ATT_THREADS="$THREADS"
                ATTEMPT=1
                RC=1
                TIMEOUT_S="${SPADES_TIMEOUT:-10800}"
                while [ "$ATTEMPT" -le "$MAX_ATTEMPTS" ]; do
                    say "$LIB/$METHOD rep$REP: metaspades.py (attempt $ATTEMPT/$MAX_ATTEMPTS, $ATT_THREADS threads, timeout ${TIMEOUT_S}s)"
                    rm -rf "$D"
                    conda activate spades
                    /usr/bin/time -v -o "$RESULTS/$LIB/$METHOD/metaspades_rep$REP.time" \
                        timeout -k 60 "$TIMEOUT_S" \
                        metaspades.py -1 "$R1" -2 "$R2" -t "$ATT_THREADS" -m "$SPADES_MEM" -o "$D" \
                        > "$RESULTS/$LIB/$METHOD/metaspades_rep$REP.stdout" \
                        2> "$RESULTS/$LIB/$METHOD/metaspades_rep$REP.stderr"
                    RC=$?
                    conda deactivate
                    # `timeout` sends its signal only to metaspades.py itself; the
                    # C++ binaries it launches (spades-hammer, spades-core, ...) are
                    # not guaranteed to receive it and were observed surviving a kill
                    # of their python parent. Clean up anything still referencing this
                    # exact output directory before deciding the attempt is over.
                    pkill -9 -f "$D/corrected" 2>/dev/null
                    pkill -9 -f "$D/K[0-9]" 2>/dev/null
                    TIMED_OUT=""
                    if [ "$RC" -eq 124 ] || [ "$RC" -eq 137 ]; then
                        TIMED_OUT=" -- timed out after ${TIMEOUT_S}s, killed (I4)"
                    fi
                    if [ "$RC" -eq 0 ] && [ -s "$CONTIGS" ]; then
                        break
                    fi
                    # Evidence from this attempt, kept before the next attempt overwrites $D.
                    SUF=".attempt${ATTEMPT}_${ATT_THREADS}t"
                    cp -f "$RESULTS/$LIB/$METHOD/metaspades_rep$REP.stderr" \
                        "$RESULTS/$LIB/$METHOD/metaspades_rep$REP$SUF.stderr" 2>/dev/null
                    [ -f "$D/spades.log" ] && cp -f "$D/spades.log" \
                        "$RESULTS/$LIB/$METHOD/metaspades_rep$REP$SUF.spades.log"
                    SEGV="$TIMED_OUT"
                    [ -z "$SEGV" ] && grep -qi "segmentation fault" "$RESULTS/$LIB/$METHOD/metaspades_rep$REP$SUF.spades.log" 2>/dev/null \
                        && SEGV=" -- segfault in spades-hammer (I4)"
                    say "  attempt $ATTEMPT failed (exit $RC)$SEGV"
                    ATTEMPT=$((ATTEMPT+1))
                    ATT_THREADS=$(( ATT_THREADS / 2 )); [ "$ATT_THREADS" -lt 4 ] && ATT_THREADS=4
                done
                ASM_THREADS_USED="$ATT_THREADS"
                if [ "$RC" -ne 0 ] || [ ! -s "$CONTIGS" ]; then
                    say "  metaSPAdes FAILED after $MAX_ATTEMPTS attempts (last exit $RC); see metaspades_rep$REP.attempt*.spades.log"
                    echo "exit_status=$RC attempts=$MAX_ATTEMPTS" > "$RESULTS/$LIB/$METHOD/metaspades_rep$REP.failed"
                    # A failed assembly is a FAILED row, never an omission.
                    if [ "$REP" = 1 ] && ! grep -q "^$LIB,$COND,$METHOD," "$DS" 2>/dev/null; then
                        [ -s "$DS" ] || printf 'library,condition,method,n50,total_length_mb,contigs_ge_1kb,largest_contig_kb,genome_fraction_pct,misassemblies,assembled_mb_ge_1kb,duplication_ratio\n' > "$DS"
                        printf '%s,%s,%s,FAILED,FAILED,FAILED,FAILED,,FAILED,FAILED,FAILED\n' "$LIB" "$COND" "$METHOD" >> "$DS"
                    fi
                    if ! grep -q "^$LIB,$COND,$METHOD,$REP," "$REPS_CSV" 2>/dev/null; then
                        [ -s "$REPS_CSV" ] || printf 'library,condition,method,replicate,n50,total_length_mb,contigs_ge_1kb,largest_contig_kb,genome_fraction_pct,misassemblies,assembled_mb_ge_1kb,duplication_ratio,assembly_wall_min,assembly_peak_mem_gb,threads,spades_mem_limit_gb\n' > "$REPS_CSV"
                        printf '%s,%s,%s,%s,FAILED,FAILED,FAILED,FAILED,,FAILED,FAILED,FAILED,,,%s,%s\n' "$LIB" "$COND" "$METHOD" "$REP" "$ATT_THREADS" "$SPADES_MEM" >> "$REPS_CSV"
                    fi
                    continue
                fi
                say "  succeeded on attempt $ATTEMPT/$MAX_ATTEMPTS ($ATT_THREADS threads)"
                rm -f "$RESULTS/$LIB/$METHOD/metaspades_rep$REP.failed"
                # Bulky intermediates: the contigs and logs are the evidence.
                rm -rf "$D/corrected" "$D/tmp" "$D/misc" "$D"/K*/ 2>/dev/null
            fi

            # wall-clock and peak memory of the assembly, from GNU time
            TF="$RESULTS/$LIB/$METHOD/metaspades_rep$REP.time"
            WALL="$(python3 - "$TF" <<'PY'
import re, sys
w = m = ""
try:
    for l in open(sys.argv[1]):
        l = l.strip()
        if l.startswith("Elapsed (wall clock)"):
            p = l.split(": ", 1)[-1].split(":")
            s = (int(p[0]) * 3600 + int(p[1]) * 60 + float(p[2])) if len(p) == 3 else (int(p[0]) * 60 + float(p[1]))
            w = round(s / 60, 3)
        elif l.startswith("Maximum resident set size"):
            m = round(int(re.search(r"(\d+)", l).group(1)) / 1048576, 3)
except Exception:
    pass
print(w, m)
PY
)"
            read -r WALL_MIN PEAK_GB <<< "$WALL"

            # --- MetaQUAST ------------------------------------------------
            MQ="$RESULTS/metaquast/${LIB}_${METHOD}_rep$REP"
            conda activate megahit
            if [ -s "$MQ/report.tsv" ] || [ -s "$MQ/combined_reference/report.tsv" ]; then
                say "  MetaQUAST report present"
            elif [ "$COND" = real ]; then
                # --max-ref-number 0: reference-free for real. Without it
                # MetaQUAST BLASTs SILVA and downloads its own references,
                # different for each method (I2).
                metaquast.py "$CONTIGS" --min-contig 1000 -t "$THREADS" \
                    --max-ref-number 0 -o "$MQ" > "$MQ.stdout" 2>&1 \
                    || say "  metaquast (reference-free) failed"
            else
                metaquast.py "$CONTIGS" -r "$REFS_DIR" --min-contig 1000 \
                    -t "$THREADS" -o "$MQ" > "$MQ.stdout" 2>&1 \
                    || say "  metaquast (reference-based) failed"
            fi
            conda deactivate

            python3 "$SCRIPT_DIR/parse_metaquast.py" "$MQ" "$LIB" "$COND" "$METHOD" "$DS" \
                --replicate "$REP" --replicates-csv "$REPS_CSV" \
                --wall-min "${WALL_MIN:-}" --peak-mem-gb "${PEAK_GB:-}" \
                --threads "$ASM_THREADS_USED" --mem-limit-gb "$SPADES_MEM" \
                || say "  no MetaQUAST report found for $LIB/$METHOD rep$REP"
        done
    done
done

say "done. $(( $(wc -l < "$DS" 2>/dev/null || echo 1) - 1 )) rows in downstream_metaspades.csv, $(( $(wc -l < "$REPS_CSV" 2>/dev/null || echo 1) - 1 )) in the replicates file"
