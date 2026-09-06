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
#     tool = hostile_default | hostile_matched | kneaddata | bmtagger | deconseq
#            (default: all of them; each skips itself if not installed)
#
# Environment:
#     T2T_FASTA          path to T2T-CHM13v2.0 FASTA (uncompressed)
#     BT2_INDEX          bowtie2 index prefix built from $T2T_FASTA
#     BMTAGGER_BITMASK   bmtool bitmask built from $T2T_FASTA
#     BMTAGGER_SRPRISM   srprism index prefix built from $T2T_FASTA
#     DECONSEQ_DB        DeconSeqConfig.pm database id (default: hsref)
#     THREADS            default 8
#
# Each tool lives in its own conda environment; this script assumes the
# relevant environment is already active, or that the binaries are on PATH.
#
# Every tool invocation is wrapped in GNU `time -v`, which writes a .time file
# beside the tool's output directory. Peak RSS and wall clock are parsed from
# those files -- they are the record of what was measured, so they are kept and
# shipped rather than being reduced to the summary table alone.

set -euo pipefail

FASTQ_DIR="${1:?usage: run_comparators.sh <fastq_dir> <results_dir> [tool ...]}"
RESULTS_DIR="${2:?usage: run_comparators.sh <fastq_dir> <results_dir> [tool ...]}"
shift 2 || true
TOOLS=("$@")

THREADS="${THREADS:-8}"
T2T_FASTA="${T2T_FASTA:-}"
BT2_INDEX="${BT2_INDEX:-}"

if [ ${#TOOLS[@]} -eq 0 ]; then
    TOOLS=(hostile_default hostile_matched kneaddata bmtagger deconseq)
fi

mkdir -p "$RESULTS_DIR"

have() { command -v "$1" >/dev/null 2>&1; }

# -- Resource measurement ---------------------------------------------
# GNU time reports peak RSS; macOS /usr/bin/time does not, so fall back to
# gtime and, failing that, record NA rather than a fabricated number.
if have gtime; then
    TIME_BIN="gtime"
elif /usr/bin/time -v true >/dev/null 2>&1; then
    TIME_BIN="/usr/bin/time"
else
    TIME_BIN=""
    echo "[run_comparators] NOTE: GNU time not found; peak RSS will be recorded as NA." >&2
fi

# timed <time_file> <command...>
timed() {
    local tf="$1"; shift
    if [ -n "$TIME_BIN" ]; then
        "$TIME_BIN" -v -o "$tf" "$@"
    else
        rm -f "$tf"
        "$@"
    fi
}

# Max "Maximum resident set size" across the .time files given, in kB.
peak_rss_kb() {
    local max=NA v tf
    for tf in "$@"; do
        [ -s "$tf" ] || continue
        v=$(grep -i 'Maximum resident set size' "$tf" | grep -oE '[0-9]+' | tail -1 || true)
        [ -n "$v" ] || continue
        if [ "$max" = NA ] || [ "$v" -gt "$max" ]; then max="$v"; fi
    done
    echo "$max"
}

# Summed "Elapsed (wall clock) time" across the .time files given, in seconds.
elapsed_s() {
    local total=NA raw s tf
    for tf in "$@"; do
        [ -s "$tf" ] || continue
        raw=$(grep -i 'Elapsed (wall clock) time' "$tf" | sed 's/.*: //' || true)
        [ -n "$raw" ] || continue
        # h:mm:ss.ss or m:ss.ss
        s=$(echo "$raw" | awk -F: '{ if (NF==3) print $1*3600+$2*60+$3; else if (NF==2) print $1*60+$2; else print $1 }')
        if [ "$total" = NA ]; then
            total="$s"
        else
            total=$(awk -v a="$total" -v b="$s" 'BEGIN{print a+b}')
        fi
    done
    echo "$total"
}

TIMING="$RESULTS_DIR/timing.tsv"
printf 'sample\ttool\twall_clock_seconds\tpeak_rss_kb\texit_status\n' > "$TIMING"

# -- Tools ------------------------------------------------------------

# Hostile 2.x as a user would run it out of the box: no --index, so it fetches
# and uses its own default human-t2t-hla index, and it selects Bowtie2
# automatically for paired short-read input. That is the configuration the
# tool's authors intend, and it is scored as such.
run_hostile_default() {
    local r1="$1" r2="$2" sample="$3" out="$RESULTS_DIR/hostile_default/$sample"
    have hostile || { echo "[skip] hostile not installed"; return 127; }
    mkdir -p "$out"
    timed "$out.time" \
        hostile clean \
            --fastq1 "$r1" --fastq2 "$r2" \
            --threads "$THREADS" \
            --output "$out"
}

# The same tool pointed at the identical T2T-CHM13v2.0 Bowtie2 index every
# other method in the comparison uses, so what is left is method rather than
# reference.
run_hostile_matched() {
    local r1="$1" r2="$2" sample="$3" out="$RESULTS_DIR/hostile_matched/$sample"
    have hostile || { echo "[skip] hostile not installed"; return 127; }
    mkdir -p "$out"
    timed "$out.time" \
        hostile clean \
            --fastq1 "$r1" --fastq2 "$r2" \
            --aligner bowtie2 \
            --index "${BT2_INDEX:?set BT2_INDEX for hostile_matched}" \
            --threads "$THREADS" \
            --output "$out"
}

run_kneaddata() {
    local r1="$1" r2="$2" sample="$3" out="$RESULTS_DIR/kneaddata/$sample"
    have kneaddata || { echo "[skip] kneaddata not installed"; return 127; }
    mkdir -p "$out"
    # KneadData drives Trimmomatic + Bowtie2; --bypass-trf keeps the comparison
    # to host removal rather than tandem-repeat masking.
    timed "$out.time" \
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
    have bmtagger.sh || { echo "[skip] bmtagger not installed"; return 127; }
    mkdir -p "$out"
    # BMTagger needs uncompressed FASTQ plus bmtool/srprism indices built once:
    #     bmtool -d $T2T_FASTA -o t2t.bitmask -A 0 -w 18
    #     srprism mkindex -i $T2T_FASTA -o t2t.srprism -M 7168
    # Decompression sits outside the timed region: it is a format requirement
    # of this wrapper, not work the method itself does.
    local u1="$out/${sample}_1.fastq" u2="$out/${sample}_2.fastq"
    gzip -dc "$r1" > "$u1"; gzip -dc "$r2" > "$u2"
    local rc=0
    timed "$out.time" \
        bmtagger.sh \
            -b "${BMTAGGER_BITMASK:?set BMTAGGER_BITMASK}" \
            -x "${BMTAGGER_SRPRISM:?set BMTAGGER_SRPRISM}" \
            -T "$out/tmp" -q1 \
            -1 "$u1" -2 "$u2" \
            -o "$out/${sample}_clean" -X || rc=$?
    rm -f "$u1" "$u2"
    return $rc
}

run_deconseq() {
    local r1="$1" r2="$2" sample="$3" out="$RESULTS_DIR/deconseq/$sample"
    have deconseq.pl || { echo "[skip] deconseq not installed"; return 127; }
    mkdir -p "$out"
    # DeconSeq is single-end only; mates are processed independently and
    # recombined before scoring. Requires a BWA-SW database identifier
    # configured in DeconSeqConfig.pm (here: 'hsref'). Each mate gets its own
    # .time file; the loop sums the wall clock and takes the max RSS.
    local rc=0 mate src
    for mate in 1 2; do
        if [ "$mate" = 1 ]; then src="$r1"; else src="$r2"; fi
        gzip -dc "$src" > "$out/${sample}_${mate}.fastq"
        timed "$out.time.$mate" \
            deconseq.pl \
                -f "$out/${sample}_${mate}.fastq" \
                -dbs "${DECONSEQ_DB:-hsref}" \
                -i 94 -c 90 \
                -out_dir "$out" \
                -id "${sample}_${mate}" || rc=$?
        rm -f "$out/${sample}_${mate}.fastq"
    done
    return $rc
}

# -- Panel loop -------------------------------------------------------
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
        # A tool that crashes is recorded as a failure rather than skipped, so
        # its exit status goes into timing.tsv instead of aborting the panel.
        STATUS=0
        "run_${tool}" "$R1" "$R2" "$SAMPLE" || STATUS=$?

        TIMEFILES=("$RESULTS_DIR/$tool/$SAMPLE".time*)
        if [ ${#TIMEFILES[@]} -eq 0 ]; then
            WALL=NA; RSS=NA
        else
            WALL=$(elapsed_s "${TIMEFILES[@]}")
            RSS=$(peak_rss_kb "${TIMEFILES[@]}")
        fi

        printf '%s\t%s\t%s\t%s\t%s\n' "$SAMPLE" "$tool" "$WALL" "$RSS" "$STATUS" >> "$TIMING"
        echo "[run_comparators] $SAMPLE $tool wall=${WALL}s peak_rss=${RSS}kB exit=$STATUS"
    done
done

echo "[run_comparators] timings written to $TIMING"
echo "[run_comparators] done. Score with:"
echo "  python compute_metrics.py --truth-r1 <mixed_R1> --cleaned <tool output> --tool <name>"
