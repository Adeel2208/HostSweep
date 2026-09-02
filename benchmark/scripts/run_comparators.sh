#!/usr/bin/env bash
# Run the comparator host-removal tools on the same FASTQ panel used for
# HostSweep, so compute_metrics.py can score them identically.
#
# Every tool is pointed at the SAME T2T-CHM13v2.0 reference to keep the
# comparison about the method rather than the reference. Set the environment
# variables below to match your installation.
#
# Usage:
#     bash run_comparators.sh <fastq_dir> <results_dir> [tool ...]
#
#     tool = hostile | kneaddata | bmtagger | deconseq   (default: all installed)
#
# Environment:
#     T2T_FASTA    path to T2T-CHM13v2.0 FASTA (uncompressed)
#     BT2_INDEX    bowtie2 index prefix built from $T2T_FASTA
#     MM2_INDEX    minimap2 .mmi built from $T2T_FASTA
#     THREADS      default 8
#
# Each tool lives in its own conda environment; this script assumes the
# relevant environment is already active, or that the binaries are on PATH.

set -euo pipefail

FASTQ_DIR="${1:?usage: run_comparators.sh <fastq_dir> <results_dir> [tool ...]}"
RESULTS_DIR="${2:?usage: run_comparators.sh <fastq_dir> <results_dir> [tool ...]}"
shift 2 || true
TOOLS=("$@")

THREADS="${THREADS:-8}"
T2T_FASTA="${T2T_FASTA:-}"
BT2_INDEX="${BT2_INDEX:-}"
MM2_INDEX="${MM2_INDEX:-}"

if [ ${#TOOLS[@]} -eq 0 ]; then
    TOOLS=(hostile kneaddata bmtagger deconseq)
fi

mkdir -p "$RESULTS_DIR"

have() { command -v "$1" >/dev/null 2>&1; }

run_hostile() {
    local r1="$1" r2="$2" sample="$3" out="$RESULTS_DIR/hostile/$sample"
    have hostile || { echo "[skip] hostile not installed"; return; }
    mkdir -p "$out"
    # Hostile v1.x, single-pass minimap2 against a custom index.
    hostile clean \
        --fastq1 "$r1" --fastq2 "$r2" \
        --index "${MM2_INDEX:?set MM2_INDEX for hostile}" \
        --threads "$THREADS" \
        --out-dir "$out"
}

run_kneaddata() {
    local r1="$1" r2="$2" sample="$3" out="$RESULTS_DIR/kneaddata/$sample"
    have kneaddata || { echo "[skip] kneaddata not installed"; return; }
    mkdir -p "$out"
    # KneadData drives Trimmomatic + Bowtie2; --bypass-trf keeps the comparison
    # to host removal rather than tandem-repeat masking.
    kneaddata \
        --input1 "$r1" --input2 "$r2" \
        --reference-db "${BT2_INDEX:?set BT2_INDEX for kneaddata}" \
        --output "$out" \
        --threads "$THREADS" \
        --bypass-trf \
        --remove-intermediate-output
}

run_bmtagger() {
    local r1="$1" r2="$2" sample="$3" out="$RESULTS_DIR/bmtagger/$sample"
    have bmtagger.sh || { echo "[skip] bmtagger not installed"; return; }
    mkdir -p "$out"
    # BMTagger needs uncompressed FASTQ plus bmtool/srprism indices built once:
    #     bmtool -d $T2T_FASTA -o t2t.bitmask -A 0 -w 18
    #     srprism mkindex -i $T2T_FASTA -o t2t.srprism -M 7168
    local u1="$out/${sample}_1.fastq" u2="$out/${sample}_2.fastq"
    gzip -dc "$r1" > "$u1"; gzip -dc "$r2" > "$u2"
    bmtagger.sh \
        -b "${BMTAGGER_BITMASK:?set BMTAGGER_BITMASK}" \
        -x "${BMTAGGER_SRPRISM:?set BMTAGGER_SRPRISM}" \
        -T "$out/tmp" -q1 \
        -1 "$u1" -2 "$u2" \
        -o "$out/${sample}_clean" -X
    rm -f "$u1" "$u2"
}

run_deconseq() {
    local r1="$1" r2="$2" sample="$3" out="$RESULTS_DIR/deconseq/$sample"
    have deconseq.pl || { echo "[skip] deconseq not installed"; return; }
    mkdir -p "$out"
    # DeconSeq is single-end only; mates are processed independently and
    # recombined before scoring. Requires a BWA-SW database identifier
    # configured in DeconSeqConfig.pm (here: 'hsref').
    for mate in 1 2; do
        local src; [ "$mate" = 1 ] && src="$r1" || src="$r2"
        gzip -dc "$src" > "$out/${sample}_${mate}.fastq"
        deconseq.pl \
            -f "$out/${sample}_${mate}.fastq" \
            -dbs "${DECONSEQ_DB:-hsref}" \
            -i 94 -c 90 \
            -out_dir "$out" \
            -id "${sample}_${mate}"
        rm -f "$out/${sample}_${mate}.fastq"
    done
}

shopt -s nullglob
for R1 in "$FASTQ_DIR"/*_1.fastq.gz "$FASTQ_DIR"/*_R1.fastq.gz; do
    if [[ "$R1" == *_R1.fastq.gz ]]; then
        SAMPLE="$(basename "$R1" _R1.fastq.gz)"; R2="${R1%_R1.fastq.gz}_R2.fastq.gz"
    else
        SAMPLE="$(basename "$R1" _1.fastq.gz)";  R2="${R1%_1.fastq.gz}_2.fastq.gz"
    fi
    [ -s "$R2" ] || { echo "[run_comparators] missing mate for $R1, skipping" >&2; continue; }

    for tool in "${TOOLS[@]}"; do
        echo "[run_comparators] === $SAMPLE / $tool ==="
        START=$(date +%s)
        "run_${tool}" "$R1" "$R2" "$SAMPLE"
        echo "[run_comparators] $SAMPLE $tool took $(( $(date +%s) - START ))s"
    done
done

echo "[run_comparators] done. Score with:"
echo "  python compute_metrics.py --truth-r1 <mixed_R1> --cleaned <tool output> --tool <name>"
