#!/usr/bin/env bash
# Fetch the real-library benchmark panel from the SRA.
#
# Requires sra-tools (prefetch, fasterq-dump) and pigz:
#     conda install -c bioconda sra-tools pigz
#
# Reads accessions from benchmark/accessions.csv (columns: Run,Category,BioProject,Notes)
# and writes <outdir>/<Run>_1.fastq.gz and <Run>_2.fastq.gz.
#
# Usage:
#     bash download_sra.sh [accessions.csv] [outdir]

set -euo pipefail

ACCESSIONS="${1:-$(dirname "$0")/../accessions.csv}"
OUTDIR="${2:-$(dirname "$0")/../data/real}"
THREADS="${THREADS:-8}"

for tool in prefetch fasterq-dump pigz; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "ERROR: '$tool' not on PATH. conda install -c bioconda sra-tools pigz" >&2
        exit 1
    }
done

mkdir -p "$OUTDIR"
cd "$OUTDIR"

# Skip the header, skip blank lines and '#' comments, take the first column.
tail -n +2 "$ACCESSIONS" \
  | grep -v '^[[:space:]]*#' \
  | grep -v '^[[:space:]]*$' \
  | cut -d, -f1 \
  | while read -r RUN; do
        RUN="$(echo "$RUN" | tr -d '[:space:]')"
        [ -z "$RUN" ] && continue

        if [ -s "${RUN}_1.fastq.gz" ] && [ -s "${RUN}_2.fastq.gz" ]; then
            echo "[download_sra] $RUN already present, skipping"
            continue
        fi

        echo "[download_sra] prefetch $RUN"
        prefetch "$RUN" --max-size 100G

        echo "[download_sra] fasterq-dump $RUN"
        fasterq-dump "$RUN" --split-files --threads "$THREADS" --progress

        echo "[download_sra] compressing $RUN"
        pigz -p "$THREADS" "${RUN}_1.fastq" "${RUN}_2.fastq"

        rm -rf "$RUN"
    done

echo "[download_sra] done; FASTQ in $(pwd)"
