#!/usr/bin/env bash
# R4: classify the E9 reads against the FULL Kraken2 Standard database (D5).
#
# The existing kraken2_human.csv was produced with Standard-8, a capped build
# that drops minimizers and therefore detects LESS human sequence -- so its
# residual-human counts are floors. This produces the same table against the
# full Standard database, so the pair (Standard-8, Standard) is itself evidence
# of how much the cap suppressed.
#
# To make that pair a like-for-like comparison, everything except the database
# is identical to run_e9.sh's Kraken2 step: the same cleaned paired reads
# (R1 and R2 concatenated, as run_e9.sh does), the same options
# (--confidence 0.1 --minimum-hit-groups 3) and the same columns. Parsing is the
# corrected one (kraken2_report_to_csv.py, I3): reads_total = unclassified +
# root clade. NOTE for the Methods: the specification said "profiling-tier
# output"; the existing Standard-8 numbers classified the paired assembly-tier
# reads for all three methods, and this run does the same so the two files
# compare. That difference from the specification is deliberate.
#
# Output: <out_dir>/kraken2_human_standard.csv
#         library,method,reads_total,reads_human,pct_human,db_build_date
# plus <out_dir>/<lib>_<method>.k2.report and .time for every classification.
#
# Usage:
#     bash run_kraken2_standard.sh <cleaned_root> <out_dir> <lib> [lib ...]
#
# Environment:
#     K2DB       default ~/hostsweep/k2_standard_full
#     THREADS    default min(nproc, 32)
#
# The database is ~75+ GB. If RAM is not comfortably larger than that, Kraken2
# is run with --memory-mapping (slower per run, but it does not need the whole
# database resident); the choice is logged.

set -uo pipefail

CLEAN_ROOT="${1:?usage: run_kraken2_standard.sh <cleaned_root> <out_dir> <lib>...}"
OUT_DIR="${2:?}"
shift 2
LIBS=("$@")
[ ${#LIBS[@]} -gt 0 ] || { echo "give at least one library" >&2; exit 1; }

NPROC="$(nproc 2>/dev/null || echo 8)"
THREADS="${THREADS:-$(( NPROC < 32 ? NPROC : 32 ))}"
K2DB="${K2DB:-$HOME/hostsweep/k2_standard_full}"
CONDA_SH="${CONDA_SH:-$HOME/hostsweep/miniforge3/etc/profile.d/conda.sh}"
METHODS=(hostsweep kneaddata hostile)
CSV="$OUT_DIR/kraken2_human_standard.csv"
mkdir -p "$OUT_DIR"

say() { echo "[R4 $(date -u +%H:%M:%S)] $*"; }

[ -s "$K2DB/hash.k2d" ] && [ -s "$K2DB/taxo.k2d" ] || { say "no Kraken2 database at $K2DB (bash 06_fetch_kraken2_db.sh with K2_FLAVOR=standard)"; exit 1; }
K2_DATE="unknown"; [ -f "$K2DB/.build_date" ] && K2_DATE="$(cat "$K2DB/.build_date")"

DB_KB="$(du -Lk "$K2DB/hash.k2d" | awk '{print $1}')"
MEM_KB="$(awk '/MemTotal/ {print $2}' /proc/meminfo)"
MMAP=()
if [ "$MEM_KB" -lt $(( DB_KB + 10*1048576 )) ]; then
    MMAP=(--memory-mapping)
    say "RAM ($(( MEM_KB/1048576 )) GB) is not comfortably above the database ($(( DB_KB/1048576 )) GB): using --memory-mapping"
else
    say "RAM $(( MEM_KB/1048576 )) GB, database $(( DB_KB/1048576 )) GB: loading it normally"
fi
say "database: $K2DB (build $K2_DATE); threads $THREADS"

# shellcheck disable=SC1090
. "$CONDA_SH"
conda env list | awk '{print $1}' | grep -qx kraken2 || { say "no 'kraken2' conda env"; exit 1; }

[ -s "$CSV" ] || printf 'library,method,reads_total,reads_human,pct_human,db_build_date\n' > "$CSV"

for LIB in "${LIBS[@]}"; do
    for METHOD in "${METHODS[@]}"; do
        R1="$CLEAN_ROOT/$LIB/${METHOD}_R1.fastq.gz"; R2="$CLEAN_ROOT/$LIB/${METHOD}_R2.fastq.gz"
        if [ ! -s "$R1" ] || [ ! -s "$R2" ]; then
            say "$LIB/$METHOD: cleaned reads absent, skipping"; continue
        fi
        if grep -q "^$LIB,$METHOD," "$CSV" 2>/dev/null; then
            say "$LIB/$METHOD: already recorded"; continue
        fi
        REP="$OUT_DIR/${LIB}_${METHOD}.k2.report"
        SE="$OUT_DIR/.${LIB}_${METHOD}.se.fastq.gz"
        cat "$R1" "$R2" > "$SE"
        say "$LIB/$METHOD: kraken2"
        conda activate kraken2
        /usr/bin/time -v -o "$OUT_DIR/${LIB}_${METHOD}.time" \
            kraken2 --db "$K2DB" --threads "$THREADS" "${MMAP[@]}" \
                    --confidence 0.1 --minimum-hit-groups 3 \
                    --report "$REP" --output /dev/null "$SE" \
            > "$OUT_DIR/${LIB}_${METHOD}.stdout" 2> "$OUT_DIR/${LIB}_${METHOD}.stderr"
        RC=$?
        conda deactivate
        rm -f "$SE"
        if [ "$RC" -ne 0 ] || [ ! -s "$REP" ]; then
            say "  FAILED (exit $RC); see ${LIB}_${METHOD}.stderr"
            printf '%s,%s,FAILED,FAILED,FAILED,%s\n' "$LIB" "$METHOD" "$K2_DATE" >> "$CSV"
            continue
        fi
        python3 "$(dirname "${BASH_SOURCE[0]}")/kraken2_report_to_csv.py" \
            --report "$REP" --library "$LIB" --method "$METHOD" \
            --db-build-date "$K2_DATE" --csv "$CSV"
    done
done

say "done. $(( $(wc -l < "$CSV") - 1 )) rows in kraken2_human_standard.csv"
