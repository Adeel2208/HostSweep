#!/usr/bin/env bash
# CheckM2 completeness/contamination over every MEGAHIT assembly E9 produced.
#
# Dropped originally (D6): CheckM2 needs roughly 15 GB RAM plus its own
# reference database (a diamond .dmnd file, several GB), over the first
# host's 11 GB ceiling. Attempted here because a machine with more memory is
# available. If it still doesn't fit or won't install, this script records
# that plainly and stops -- it does not estimate what CheckM2 would have
# reported.
#
# CheckM2 is designed to score single-genome bins, not whole metagenomic
# co-assemblies. Run directly against one MEGAHIT assembly's contigs, it
# reports one completeness/contamination pair treating the whole assembly as
# a single bin -- a coarse, assembly-level proxy, not a per-organism
# breakdown. State it that way wherever this number is used; log it as a
# deviation in DEVIATIONS.md once it has actually produced a result.
#
# Idempotent: a (library, method) pair already in the output CSV is skipped.
#
# Usage:
#     bash run_checkm2.sh <downstream_results_dir> <out_csv> [db_dir]
#
#     <downstream_results_dir>/<library>/<method>/megahit/final.contigs.fa
#     is what E9 (chain_e9.sh / run_e9.sh) produces for every (library,
#     method) pair -- this script walks that same tree.
#
# Environment:  THREADS  default 8

set -uo pipefail

RESULTS="${1:?usage: run_checkm2.sh <downstream_results_dir> <out_csv> [db_dir]}"
OUT_CSV="${2:?usage: run_checkm2.sh <downstream_results_dir> <out_csv> [db_dir]}"
DB_DIR="${3:-$HOME/hostsweep/checkm2_db}"
THREADS="${THREADS:-8}"
CONDA_SH="${CONDA_SH:-$HOME/hostsweep/miniforge3/etc/profile.d/conda.sh}"

say() { echo "[checkm2 $(date -u +%H:%M:%S)] $*"; }

# shellcheck disable=SC1090
. "$CONDA_SH"

# Conda's defaults (9 s connect timeout, 3 retries) are thin for a flaky link.
# On a real run, one timeout fetching conda-forge's repodata.json
# ("CondaHTTPError: HTTP 000 CONNECTION FAILED") ended the whole CheckM2
# stage after 3.5 minutes. Longer timeouts here, plus whole-command retries.
export CONDA_REMOTE_CONNECT_TIMEOUT_SECS="${CONDA_REMOTE_CONNECT_TIMEOUT_SECS:-60}"
export CONDA_REMOTE_READ_TIMEOUT_SECS="${CONDA_REMOTE_READ_TIMEOUT_SECS:-120}"
export CONDA_REMOTE_MAX_RETRIES="${CONDA_REMOTE_MAX_RETRIES:-5}"

# retry <attempts> <seconds-between> <command...>
retry() {
    local n="$1" wait="$2" i; shift 2
    for i in $(seq 1 "$n"); do
        "$@" && return 0
        say "  attempt $i/$n failed"
        [ "$i" -lt "$n" ] && sleep "$wait"
    done
    return 1
}

ENVLOG="$HOME/hostsweep/logs/checkm2_env_create.log"
mkdir -p "$(dirname "$ENVLOG")"
create_checkm2_env() {
    conda create -y -q -n checkm2 --override-channels -c conda-forge -c bioconda checkm2 \
        > "$ENVLOG" 2>&1 || { tail -6 "$ENVLOG" | cut -c1-160; return 1; }
}

if ! conda env list | awk '{print $1}' | grep -qx checkm2; then
    say "creating checkm2 env (this pulls TensorFlow + CUDA packages even on"
    say "a CPU-only host -- several GB of download, budget time and disk)"
    retry 5 60 create_checkm2_env
    conda env list | awk '{print $1}' | grep -qx checkm2 \
        || { say "checkm2 install FAILED after 5 attempts (see $ENVLOG) -- dropping, same as the original decision (D6)"; exit 1; }
fi
conda activate checkm2 || { say "cannot activate checkm2 env"; exit 1; }

mkdir -p "$DB_DIR"
DB_FILE=$(find "$DB_DIR" -name "*.dmnd" 2>/dev/null | head -1)
if [ -z "$DB_FILE" ]; then
    say "downloading CheckM2 reference database to $DB_DIR (about 1.7 GB, from Zenodo)"
    # The archive is not resumable, so a failed attempt restarts it; a few
    # attempts still beat abandoning the stage over one dropped connection.
    retry 3 60 checkm2 database --download --path "$DB_DIR" \
        || { say "database download FAILED after 3 attempts"; exit 1; }
    DB_FILE=$(find "$DB_DIR" -name "*.dmnd" 2>/dev/null | head -1)
fi
[ -n "$DB_FILE" ] || { say "no .dmnd database file found under $DB_DIR after download attempt"; exit 1; }
say "using database: $DB_FILE"

[ -s "$OUT_CSV" ] || printf 'library,condition,method,completeness_pct,contamination_pct\n' > "$OUT_CSV"

already_scored() {
    python3 -c "
import csv, sys
lib, method, path = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    with open(path, newline='') as fh:
        for row in csv.DictReader(fh):
            if row['library'] == lib and row['method'] == method:
                sys.exit(0)
except FileNotFoundError:
    pass
sys.exit(1)
" "$1" "$2" "$OUT_CSV"
}

shopt -s nullglob
N=0
for CONTIGS in "$RESULTS"/*/*/megahit/final.contigs.fa; do
    [ -s "$CONTIGS" ] || continue
    METHOD_DIR="$(dirname "$(dirname "$CONTIGS")")"
    LIB_DIR="$(dirname "$METHOD_DIR")"
    METHOD="$(basename "$METHOD_DIR")"
    LIB="$(basename "$LIB_DIR")"
    case "$LIB" in SYN-*) COND=synthetic ;; *) COND=real ;; esac

    if already_scored "$LIB" "$METHOD"; then
        say "$LIB/$METHOD: already scored"; continue
    fi

    WD="$METHOD_DIR/checkm2.work"
    rm -rf "$WD"
    say "$LIB/$METHOD: running checkm2 predict"
    checkm2 predict --threads "$THREADS" --input "$CONTIGS" \
        --output-directory "$WD" --database_path "$DB_FILE" -x fa \
        > "$METHOD_DIR/checkm2.stdout" 2> "$METHOD_DIR/checkm2.stderr"
    RC=$?
    REPORT="$WD/quality_report.tsv"

    python3 - "$REPORT" "$LIB" "$COND" "$METHOD" "$OUT_CSV" "$RC" <<'PYEOF'
import csv, os, sys
report, lib, cond, method, out, rc = sys.argv[1:7]
rc = int(rc)
if rc != 0 or not os.path.exists(report):
    row = [lib, cond, method, "FAILED", "FAILED"]
else:
    with open(report, newline="") as fh:
        rows = list(csv.DictReader(fh, delimiter="\t"))
    if not rows:
        row = [lib, cond, method, "FAILED", "FAILED"]
    else:
        r = rows[0]
        row = [lib, cond, method, r.get("Completeness", ""), r.get("Contamination", "")]
with open(out, "a", newline="") as fh:
    csv.writer(fh).writerow(row)
print("recorded" if row[3] != "FAILED" else "FAILED", lib, method,
      "completeness", row[3], "contamination", row[4])
PYEOF
    N=$((N+1))
    # Work tree can be large (diamond alignments); the report and raw
    # stdout/stderr are the evidence kept, not the intermediate files.
    rm -rf "$WD"
done

say "processed $N (library, method) pair(s) this run"
say "checkm2_results.csv: $(( $(wc -l < "$OUT_CSV") - 1 )) rows total"
