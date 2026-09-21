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
#
# Idempotent: a finished assembly (SPAdes' own "Thank you for using SPAdes"
# line in spades.log) is not redone.

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

            if [ -s "$CONTIGS" ] && grep -q "Thank you for using SPAdes" "$D/spades.log" 2>/dev/null; then
                say "$LIB/$METHOD rep$REP: assembly present"
            else
                say "$LIB/$METHOD rep$REP: metaspades.py"
                rm -rf "$D"
                conda activate spades
                /usr/bin/time -v -o "$RESULTS/$LIB/$METHOD/metaspades_rep$REP.time" \
                    metaspades.py -1 "$R1" -2 "$R2" -t "$THREADS" -m "$SPADES_MEM" -o "$D" \
                    > "$RESULTS/$LIB/$METHOD/metaspades_rep$REP.stdout" \
                    2> "$RESULTS/$LIB/$METHOD/metaspades_rep$REP.stderr"
                RC=$?
                conda deactivate
                if [ "$RC" -ne 0 ] || [ ! -s "$CONTIGS" ]; then
                    say "  metaSPAdes FAILED (exit $RC); see metaspades_rep$REP.stderr and $D/spades.log"
                    echo "exit_status=$RC" > "$RESULTS/$LIB/$METHOD/metaspades_rep$REP.failed"
                    # A failed assembly is a FAILED row, never an omission.
                    if [ "$REP" = 1 ] && ! grep -q "^$LIB,$COND,$METHOD," "$DS" 2>/dev/null; then
                        [ -s "$DS" ] || printf 'library,condition,method,n50,total_length_mb,contigs_ge_1kb,largest_contig_kb,genome_fraction_pct,misassemblies,assembled_mb_ge_1kb,duplication_ratio\n' > "$DS"
                        printf '%s,%s,%s,FAILED,FAILED,FAILED,FAILED,,FAILED,FAILED,FAILED\n' "$LIB" "$COND" "$METHOD" >> "$DS"
                    fi
                    if ! grep -q "^$LIB,$COND,$METHOD,$REP," "$REPS_CSV" 2>/dev/null; then
                        [ -s "$REPS_CSV" ] || printf 'library,condition,method,replicate,n50,total_length_mb,contigs_ge_1kb,largest_contig_kb,genome_fraction_pct,misassemblies,assembled_mb_ge_1kb,duplication_ratio,assembly_wall_min,assembly_peak_mem_gb,threads,spades_mem_limit_gb\n' > "$REPS_CSV"
                        printf '%s,%s,%s,%s,FAILED,FAILED,FAILED,FAILED,,FAILED,FAILED,FAILED,,,%s,%s\n' "$LIB" "$COND" "$METHOD" "$REP" "$THREADS" "$SPADES_MEM" >> "$REPS_CSV"
                    fi
                    continue
                fi
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
                --threads "$THREADS" --mem-limit-gb "$SPADES_MEM" \
                || say "  no MetaQUAST report found for $LIB/$METHOD rep$REP"
        done
    done
done

say "done. $(( $(wc -l < "$DS" 2>/dev/null || echo 1) - 1 )) rows in downstream_metaspades.csv, $(( $(wc -l < "$REPS_CSV" 2>/dev/null || echo 1) - 1 )) in the replicates file"
