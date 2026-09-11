#!/usr/bin/env bash
# E9: downstream assembly and classification.
#
# Three cleaning methods, matched paired-end structure throughout:
#     hostsweep   Output 1 (assembly tier, PE)
#     kneaddata   paired output
#     hostile     Bowtie2, matched T2T index, paired output
#
# Hostile stays in this arm by requirement (Reviewer 3, Editor 15). If scope
# has to shrink, cut libraries, never that comparison.
#
# ---------------------------------------------------------------------------
# Deviations, both recorded in benchmark/run/DEVIATIONS.md:
#   D4  MEGAHIT replaces metaSPAdes. metaSPAdes needs 30-120 GB; this host has
#       11 GB. MEGAHIT's absolute contiguity statistics are NOT comparable to
#       metaSPAdes numbers. The comparison between cleaning methods remains
#       valid because all three are assembled identically.
#   D5  Kraken2 Standard-8 replaces Standard. A capped database detects LESS
#       human sequence, so reads_human is a FLOOR, not an estimate.
# ---------------------------------------------------------------------------
#
# Reference-based MetaQUAST metrics are produced for SYNTHETIC libraries only,
# against the ten background genomes. Real libraries are assembled
# reference-free and their reference-based columns are left EMPTY -- a
# metagenomic misassembly rate without a reference set is not interpretable.
#
# assembled_mb_ge_1kb is reported beside misassemblies so the rate has an
# explicit denominator (Editor 14).
#
# Usage:
#     bash run_e9.sh <cleaned_root> <results_dir> <refs_dir> <lib> [lib ...]
#
#   <cleaned_root>/<lib>/<method>_R1.fastq.gz + _R2.fastq.gz
#
# Environment:
#     THREADS      default 8
#     MEGAHIT_MEM  fraction of RAM for MEGAHIT, default 0.5
#     K2DB         path to the Kraken2 Standard-8 database

set -uo pipefail

CLEAN_ROOT="${1:?usage: run_e9.sh <cleaned_root> <results_dir> <refs_dir> <lib>...}"
RESULTS="${2:?}"
REFS_DIR="${3:?}"
shift 3
LIBS=("$@")
[ ${#LIBS[@]} -gt 0 ] || { echo "give at least one library" >&2; exit 1; }

THREADS="${THREADS:-8}"
MEGAHIT_MEM="${MEGAHIT_MEM:-0.5}"
K2DB="${K2DB:-$HOME/hostsweep/k2_standard_08gb}"
CONDA_SH="$HOME/hostsweep/miniforge3/etc/profile.d/conda.sh"
METHODS=(hostsweep kneaddata hostile)

mkdir -p "$RESULTS/metaquast"
say() { echo "[E9 $(date -u +%H:%M:%S)] $*"; }

DOWNSTREAM="$RESULTS/downstream.csv"
[ -s "$DOWNSTREAM" ] || printf 'library,condition,method,n50,total_length_mb,contigs_ge_1kb,largest_contig_kb,genome_fraction_pct,misassemblies,assembled_mb_ge_1kb,duplication_ratio\n' > "$DOWNSTREAM"

K2CSV="$RESULTS/kraken2_human.csv"
[ -s "$K2CSV" ] || printf 'library,method,reads_total,reads_human,pct_human,db_build_date\n' > "$K2CSV"

condition_of() {
    case "$1" in
        SYN-CHM13-*) echo synthetic_matched ;;
        SYN-NEU-*|SYN-IND-*) echo synthetic_mismatch ;;
        *) echo real ;;
    esac
}

K2_DATE="unknown"
[ -f "$K2DB/.build_date" ] && K2_DATE="$(cat "$K2DB/.build_date")"

for LIB in "${LIBS[@]}"; do
    COND="$(condition_of "$LIB")"
    for METHOD in "${METHODS[@]}"; do
        R1="$CLEAN_ROOT/$LIB/${METHOD}_R1.fastq.gz"
        R2="$CLEAN_ROOT/$LIB/${METHOD}_R2.fastq.gz"
        if [ ! -s "$R1" ] || [ ! -s "$R2" ]; then
            say "$LIB/$METHOD: cleaned reads absent, skipping"
            continue
        fi

        OUT="$RESULTS/$LIB/$METHOD"
        CONTIGS="$OUT/megahit/final.contigs.fa"
        mkdir -p "$OUT"

        # --- assembly -------------------------------------------------
        if [ -s "$CONTIGS" ]; then
            say "$LIB/$METHOD: assembly present"
        else
            say "$LIB/$METHOD: MEGAHIT"
            # shellcheck disable=SC1090
            . "$CONDA_SH"; conda activate megahit
            rm -rf "$OUT/megahit"
            /usr/bin/time -v -o "$OUT/megahit.time" \
                megahit -1 "$R1" -2 "$R2" -t "$THREADS" \
                        -m "$MEGAHIT_MEM" --min-contig-len 200 \
                        -o "$OUT/megahit" \
                > "$OUT/megahit.stdout" 2> "$OUT/megahit.stderr" \
                || { say "  MEGAHIT FAILED"; echo "megahit failed" > "$OUT/.failed"
                     printf '%s,%s,%s,FAILED,FAILED,FAILED,FAILED,,FAILED,FAILED,FAILED\n' \
                         "$LIB" "$COND" "$METHOD" >> "$DOWNSTREAM"
                     conda deactivate; continue; }
            conda deactivate
        fi
        [ -s "$CONTIGS" ] || { say "$LIB/$METHOD: no contigs"; continue; }

        # --- MetaQUAST ------------------------------------------------
        MQ="$RESULTS/metaquast/${LIB}_${METHOD}"
        # shellcheck disable=SC1090
        . "$CONDA_SH"; conda activate megahit
        if [ "$COND" = real ]; then
            # Genuinely reference-free. Omitting -r is NOT enough: without it
            # MetaQUAST BLASTs the contigs against SILVA 16S and downloads
            # reference genomes from NCBI on its own -- 46 for the gut library
            # on the first run. Worse, each method's run chose references from
            # its OWN contigs, so the three methods were scored against
            # different sets (KneadData 66.3 Mb vs HostSweep 28.7 Mb, 18 of 44
            # genomes shared). --max-ref-number 0 stops the download, so only
            # reference-free metrics (N50, lengths, contig counts) are produced.
            metaquast.py "$CONTIGS" --min-contig 1000 -t "$THREADS" \
                         --max-ref-number 0 -o "$MQ" \
                > "$MQ.stdout" 2>&1 || say "  metaquast (reference-free) failed"
        else
            metaquast.py "$CONTIGS" -r "$REFS_DIR" --min-contig 1000 \
                         -t "$THREADS" -o "$MQ" \
                > "$MQ.stdout" 2>&1 || say "  metaquast (reference-based) failed"
        fi
        conda deactivate

        python3 - "$MQ" "$LIB" "$COND" "$METHOD" "$DOWNSTREAM" <<'PYEOF'
import csv, os, sys
mq, lib, cond, method, out = sys.argv[1:6]

def find_report(root):
    for name in ("combined_reference/report.tsv", "report.tsv"):
        p = os.path.join(root, name)
        if os.path.exists(p):
            return p
    return None

path = find_report(mq)
vals = {}
if path:
    with open(path) as fh:
        for line in fh:
            parts = line.rstrip("\n").split("\t")
            if len(parts) >= 2:
                vals[parts[0].strip()] = parts[1].strip()

def num(*keys):
    for k in keys:
        v = vals.get(k)
        if v not in (None, "", "-"):
            return v
    return ""

def mb(key):
    v = num(key)
    try:
        return round(float(v) / 1e6, 4)
    except (TypeError, ValueError):
        return ""

def kb(key):
    v = num(key)
    try:
        return round(float(v) / 1e3, 3)
    except (TypeError, ValueError):
        return ""

row = [
    lib, cond, method,
    num("N50"),
    mb("Total length (>= 0 bp)") or mb("Total length"),
    num("# contigs (>= 1000 bp)"),
    kb("Largest contig"),
    num("Genome fraction (%)"),
    num("# misassemblies"),
    mb("Total length (>= 1000 bp)"),     # explicit denominator, Editor 14
    num("Duplication ratio"),
]
# Belt and braces: reference-based columns are blank for real libraries no
# matter what the report contains. The comments here once claimed these would
# be "empty for reference-free runs" -- they were not, because MetaQUAST
# fetched its own references, and the claim went unchecked into a results
# table. Enforced in code now rather than asserted in a comment.
if cond == "real":
    row[7] = ""    # genome_fraction_pct
    row[8] = ""    # misassemblies

# Idempotent: one row per (library, method). run_e9.sh appends, and being
# invoked twice once doubled every row in this file.
existing = set()
if os.path.exists(out):
    with open(out, newline="") as fh:
        for r in csv.reader(fh):
            if len(r) >= 3:
                existing.add((r[0], r[2]))
if (lib, method) in existing:
    print("already recorded", lib, method, "- not appending a duplicate")
else:
    with open(out, "a", newline="") as fh:
        csv.writer(fh).writerow(row)
    print("recorded", lib, method, "report:", path or "NONE")
PYEOF

        # --- Kraken2 --------------------------------------------------
        if [ -d "$K2DB" ]; then
            # shellcheck disable=SC1090
            . "$CONDA_SH"; conda activate kraken2
            SE="$OUT/se_for_k2.fastq.gz"
            cat "$R1" "$R2" > "$SE"
            /usr/bin/time -v -o "$OUT/kraken2.time" \
                kraken2 --db "$K2DB" --threads "$THREADS" \
                        --confidence 0.1 --minimum-hit-groups 3 \
                        --report "$OUT/k2.report" --output /dev/null \
                        "$SE" > "$OUT/kraken2.stdout" 2> "$OUT/kraken2.stderr" \
                || say "  kraken2 FAILED"
            rm -f "$SE"
            conda deactivate

            python3 - "$OUT/k2.report" "$LIB" "$METHOD" "$K2_DATE" "$K2CSV" <<'PYEOF'
import csv, os, sys
rep, lib, method, dbdate, out = sys.argv[1:6]
total = human = 0
if os.path.exists(rep):
    with open(rep) as fh:
        for line in fh:
            f = line.rstrip("\n").split("\t")
            if len(f) < 6:
                continue
            try:
                clade = int(f[1])
            except ValueError:
                continue
            rank, taxid, name = f[3].strip(), f[4].strip(), f[5].strip()
            if rank == "R" and name == "root":
                total = max(total, clade)
            if rank == "U":
                total += clade
            if taxid == "9606":
                human = clade
pct = round(100.0 * human / total, 6) if total else ""
existing = set()
if os.path.exists(out):
    with open(out, newline="") as fh:
        for r in csv.reader(fh):
            if len(r) >= 2:
                existing.add((r[0], r[1]))
if (lib, method) in existing:
    print("kraken2 already recorded", lib, method, "- not appending a duplicate")
else:
    with open(out, "a", newline="") as fh:
        csv.writer(fh).writerow([lib, method, total, human, pct, dbdate])
    print("kraken2", lib, method, "total", total, "human", human)
PYEOF
        else
            say "  Kraken2 DB absent at $K2DB; kraken2_human.csv row not written"
        fi
    done
done

say "downstream.csv and kraken2_human.csv written under $RESULTS"
