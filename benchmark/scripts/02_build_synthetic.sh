#!/usr/bin/env bash
# Build the twelve synthetic controlled-truth libraries (experiment E2).
#
# Idempotent and resumable: every step skips itself if its output already
# exists and is non-empty, so this can be re-run after an interruption.
#
# Usage:
#     bash 02_build_synthetic.sh <workdir>
#
# Environment:
#     T2T_FASTA   human reference for the nine matched libraries
#                 (default: $CONDA_PREFIX/share/hostsweep/databases/standard/human_T2T.fasta)
#     THREADS     default 8
#
# Outputs, under <workdir>:
#     refs/            downloaded background genomes
#     background_R{1,2}.fastq.gz
#     human_<src>_R{1,2}.fq
#     synthetic/<library>_R{1,2}.fastq.gz  + _manifest.json + _labels.tsv.gz
#
# ---------------------------------------------------------------------------
# Two documented deviations from benchmark/synthetic/README.md, both forced by
# this machine's 15.6 GB RAM / 574 GB disk (see benchmark/run/STATUS.md):
#
#  1. Human simulation coverage is -f 0.2, not -f 5. The largest human draw
#     any library makes is 40% of 2,000,000 pairs = 800,000 pairs. -f 5 over
#     the 3.1 Gb reference yields ~51 M pairs (~20 GB per source, four
#     sources), of which >98% would be discarded by subsampling. -f 0.2 yields
#     ~2.07 M pairs, still 2.5x the largest draw. Truth labelling is unchanged:
#     mix_spikein.py subsamples from whatever pool it is given.
#
#  2. Background community coverage is 200x total, not 50x. At 50x the pool is
#     only ~717 k pairs, but a 0.1%-human library needs ~1.998 M background
#     pairs; the pool must exceed the largest background draw or the realised
#     fraction silently misses the requested one. 200x gives ~2.9 M pairs.
# ---------------------------------------------------------------------------

set -uo pipefail

WORK="${1:?usage: 02_build_synthetic.sh <workdir>}"
THREADS="${THREADS:-8}"
TOTAL_COV="${TOTAL_COV:-200}"        # background community coverage, see note 2
HUMAN_COV="${HUMAN_COV:-0.2}"        # human simulation coverage, see note 1
TOTAL_PAIRS="${TOTAL_PAIRS:-2000000}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GENOMES_TSV="$SCRIPT_DIR/../genomes.tsv"
T2T_FASTA="${T2T_FASTA:-$CONDA_PREFIX/share/hostsweep/databases/standard/human_T2T.fasta}"

REFS="$WORK/refs"
SYN="$WORK/synthetic"
LOGS="$WORK/logs"
mkdir -p "$REFS" "$SYN" "$LOGS"

# Single-instance lock. Two concurrent runs write the same *_R1.fastq.gz and
# *_labels.tsv.gz through the same out-prefix, interleaving records and
# producing a library whose truth labels no longer match its reads -- corrupt
# but not obviously so, and it would silently poison every metric downstream.
# This happened once on this host when a suspended wsl.exe reconnected and
# re-ran its command alongside a fresh launch.
LOCK="$WORK/.e2.lock"
exec 9>"$LOCK"
if ! flock -n 9; then
    echo "[E2] another instance holds $LOCK; exiting without touching anything" >&2
    exit 0
fi

say()  { echo "[E2 $(date -u +%H:%M:%S)] $*"; }
fail() { echo "[E2 FAILED] $*" >&2; exit 1; }

for t in art_illumina python3; do
    command -v "$t" >/dev/null 2>&1 || fail "$t not on PATH"
done

# -- 1. Background genomes --------------------------------------------
say "downloading background genomes listed in $GENOMES_TSV"
while IFS=$'\t' read -r ACC ORG ABUND REST; do
    case "$ACC" in ''|'#'*|accession) continue;; esac
    OUT="$REFS/${ACC}.fna"
    if [ -s "$OUT" ]; then
        say "  have $ACC ($ORG)"
        continue
    fi
    say "  fetching $ACC ($ORG)"
    # The NCBI Datasets download endpoint returns a zip containing the FASTA;
    # it does not require knowing the assembly-name component of the FTP path.
    URL="https://api.ncbi.nlm.nih.gov/datasets/v2alpha/genome/accession/${ACC}/download?include_annotation_type=GENOME_FASTA"
    curl -fsSL --retry 3 -o "$WORK/${ACC}.zip" "$URL" || fail "download $ACC"
    python3 - "$WORK/${ACC}.zip" "$OUT" <<'PYEOF' || fail "extract $ACC"
import sys, zipfile
zp, out = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(zp) as z:
    names = [n for n in z.namelist() if n.endswith((".fna", ".fasta", ".fa"))]
    if not names:
        raise SystemExit("no FASTA inside %s: %s" % (zp, z.namelist()[:10]))
    names.sort(key=lambda n: -z.getinfo(n).file_size)
    with z.open(names[0]) as src, open(out, "wb") as dst:
        dst.write(src.read())
print("extracted", names[0])
PYEOF
    rm -f "$WORK/${ACC}.zip"
done < "$GENOMES_TSV"

# -- 2. Background reads ----------------------------------------------
if [ -s "$WORK/background_R1.fastq.gz" ] && [ -s "$WORK/background_R2.fastq.gz" ]; then
    say "background reads already built"
else
    say "simulating background at ${TOTAL_COV}x total community coverage"
    rm -f "$WORK"/bg_*_R1.fq "$WORK"/bg_*_R2.fq
    while IFS=$'\t' read -r ACC ORG ABUND REST; do
        case "$ACC" in ''|'#'*|accession) continue;; esac
        COV=$(python3 -c "print($TOTAL_COV * $ABUND)")
        say "  $ACC at ${COV}x"
        art_illumina -ss HS25 -i "$REFS/${ACC}.fna" -p -l 150 -f "$COV" \
                     -m 200 -s 10 -rs 42 -na \
                     -o "$WORK/bg_${ACC}_R" > "$LOGS/art_bg_${ACC}.log" 2>&1 \
            || fail "art_illumina on $ACC (see $LOGS/art_bg_${ACC}.log)"
    done < "$GENOMES_TSV"
    cat "$WORK"/bg_*_R1.fq | gzip > "$WORK/background_R1.fastq.gz" || fail "cat background R1"
    cat "$WORK"/bg_*_R2.fq | gzip > "$WORK/background_R2.fastq.gz" || fail "cat background R2"
    rm -f "$WORK"/bg_*_R1.fq "$WORK"/bg_*_R2.fq
fi
BG_PAIRS=$(( $(zcat "$WORK/background_R1.fastq.gz" | wc -l) / 4 ))
say "background pool: $BG_PAIRS pairs (largest draw is $TOTAL_PAIRS)"
[ "$BG_PAIRS" -ge "$TOTAL_PAIRS" ] || say "WARNING: background pool smaller than the largest library; realised fractions will drift"

# -- 3. Human reads ----------------------------------------------------
# chm13 feeds the nine matched libraries; the three haplotype sources feed the
# mismatch libraries. Each source FASTA must already be in $REFS.
simulate_human() {
    local tag="$1" fasta="$2" seed="$3"
    if [ -s "$WORK/human_${tag}_R1.fq" ]; then
        say "  human_${tag} already simulated"; return 0
    fi
    [ -s "$fasta" ] || { say "  SKIP human_${tag}: $fasta absent"; return 1; }
    say "  simulating human_${tag} at ${HUMAN_COV}x from $(basename "$fasta")"
    art_illumina -ss HS25 -i "$fasta" -p -l 150 -f "$HUMAN_COV" \
                 -m 200 -s 10 -rs "$seed" -na \
                 -o "$WORK/human_${tag}_R" > "$LOGS/art_human_${tag}.log" 2>&1 \
        || { say "  FAILED human_${tag} (see $LOGS/art_human_${tag}.log)"; return 1; }
}

say "simulating human reads"
simulate_human chm13 "$T2T_FASTA" 42
for spec in "HG00438:$REFS/HG00438_pri_mat_f1_v2.fna:51" \
            "HG00733:$REFS/HG00733_pri_mat_f1_v2.fna:52" \
            "NA19240:$REFS/NA19240_pri_mat_f1_v2.fna:53"; do
    IFS=: read -r TAG FA SEED <<<"$spec"
    simulate_human "$TAG" "$FA" "$SEED" || true
done

# -- 4. Mix ------------------------------------------------------------
# seed:library:human_source:fraction
PANEL="42:SYN-CHM13-01:chm13:0.001
43:SYN-CHM13-02:chm13:0.005
44:SYN-CHM13-03:chm13:0.01
45:SYN-CHM13-04:chm13:0.05
46:SYN-CHM13-05:chm13:0.10
47:SYN-CHM13-06:chm13:0.20
48:SYN-CHM13-07:chm13:0.40
49:SYN-CHM13-08:chm13:0.05
50:SYN-CHM13-09:chm13:0.10
51:SYN-IND-01:HG00438:0.01
52:SYN-NEU-02:HG00733:0.10
53:SYN-NEU-03:NA19240:0.20"

# Mixing is the slowest stage and is single-core, so libraries are built
# concurrently. Each job writes its own --out-prefix, so unlike the earlier
# duplicate-instance incident there is no shared-file hazard: two jobs never
# touch the same path. MIX_JOBS is capped by memory, not cores -- each mixer
# holds its reservoir in RAM (~2.9 GB measured for 2 M pairs), so 2 concurrent
# jobs sit near 6 GB against an 11 GB ceiling.
MIX_JOBS="${MIX_JOBS:-2}"

say "mixing the panel ($MIX_JOBS concurrent)"
BUILT=0; SKIPPED=0
declare -a PIDS=() LABELS=()

reap_one() {
    # Wait for any running job, record its outcome. Returns 1 if none ran.
    [ ${#PIDS[@]} -gt 0 ] || return 1
    local pid="${PIDS[0]}" label="${LABELS[0]}"
    PIDS=("${PIDS[@]:1}"); LABELS=("${LABELS[@]:1}")
    if wait "$pid"; then
        # A job that exits 0 without a manifest did not finish the library.
        if [ -s "$SYN/${label}_manifest.json" ]; then
            say "  done $label"; BUILT=$((BUILT+1))
        else
            say "  FAILED $label (no manifest; see $LOGS/mix_${label}.log)"
            SKIPPED=$((SKIPPED+1))
        fi
    else
        say "  FAILED $label (see $LOGS/mix_${label}.log)"
        SKIPPED=$((SKIPPED+1))
    fi
    return 0
}

while IFS= read -r ENTRY; do
    [ -n "$ENTRY" ] || continue
    IFS=: read -r SEED LABEL SRC FRACTION <<<"$ENTRY"

    if [ -s "$SYN/${LABEL}_R1.fastq.gz" ] && [ -s "$SYN/${LABEL}_manifest.json" ]; then
        say "  $LABEL already built"; BUILT=$((BUILT+1)); continue
    fi
    if [ ! -s "$WORK/human_${SRC}_R1.fq" ]; then
        say "  SKIP $LABEL: human source '$SRC' was not simulated"
        SKIPPED=$((SKIPPED+1)); continue
    fi

    while [ ${#PIDS[@]} -ge "$MIX_JOBS" ]; do reap_one || break; done

    say "  start $LABEL (seed $SEED, $SRC, fraction $FRACTION)"
    python3 "$SCRIPT_DIR/mix_spikein.py" \
        --background-r1 "$WORK/background_R1.fastq.gz" \
        --background-r2 "$WORK/background_R2.fastq.gz" \
        --human-r1 "$WORK/human_${SRC}_R1.fq" \
        --human-r2 "$WORK/human_${SRC}_R2.fq" \
        --fraction "$FRACTION" \
        --total-pairs "$TOTAL_PAIRS" \
        --seed "$SEED" \
        --out-prefix "$SYN/${LABEL}" > "$LOGS/mix_${LABEL}.log" 2>&1 &
    PIDS+=($!); LABELS+=("$LABEL")
done <<< "$PANEL"

while reap_one; do :; done

say "panel: $BUILT built, $SKIPPED not built"
say "manifests are in $SYN/*_manifest.json -- realised fractions come from there"
