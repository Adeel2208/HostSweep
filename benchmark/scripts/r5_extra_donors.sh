#!/usr/bin/env bash
# R5: extra reference-mismatch donors.
#
# The original mismatch arm has three donors (Han Chinese South, Puerto Rican,
# Yoruban), which is too few to say how large or how stable the reference-
# mismatch penalty is. This adds three donors from populations the first three
# do not cover, built the same way, and scores all the timing-run tools on them:
#
#     HG02080  Kinh in Ho Chi Minh City   GCA_018504085.1  HG02080.pri.mat.f1_v2
#     HG03098  Mende in Sierra Leone      GCA_018506165.1  HG03098.pri.mat.f1_v2
#     HG01358  Colombian in Medellin      GCA_018469865.1  HG01358.pri.mat.f1_v2.1
#
# Same criteria as the original three (HPRC Year 1 f1_assembly_v2, primary
# maternal haplotype, hifiasm v0.14, UCSC Genomics Institute), pinned to
# version .1 of each accession -- the later versions of the same GCA numbers
# are a different assembly (hifiasm v0.19.9, chromosome level). HG00621 (Han1,
# CHM13 gap-fill) is refused by 03_fetch_human_sources.py and is not used.
#
# Same ART settings as the panel (HS25, 150 bp paired, -m 200 -s 10, human
# coverage 0.2x), the same 200x ten-genome background, 2,000,000 pairs per
# library. Seeds continue where the panel ended (42-53):
#     54 55 56   human read simulation for HG02080, HG03098, HG01358
#     57 ...     mixing, one per library, in the order printed in r5_panel.tsv
#
# Libraries: one per (donor, host fraction). R5_FRACTIONS default "0.10 0.20"
# gives six libraries. 10% and 20% are the fractions with enough human pairs
# (200,000 and 400,000) for sensitivity to resolve at the 0.001 pp level; 1% is
# already covered by SYN-IND-01. Add 0.01 to include it:
#     R5_FRACTIONS="0.01 0.10 0.20" bash r5_extra_donors.sh
#
# Names: SYN-<KHV|MSL|CLM>-<host %>, e.g. SYN-KHV-10 (aggregate_results.py and
# run_e9.sh treat these as synthetic_mismatch).
#
# Outputs, under ~/hostsweep/out:
#     r5_donor_provenance.json     NCBI provenance of the three assemblies
#     r5_panel.tsv                 seed, library, donor, fraction
#     r5_results/<lib>/...         raw evidence, 5 tools x 3 runs each
#     r5/per_library.csv, synthetic_manifest.csv, run_details.csv,
#     r5/timing_summary.csv, r5/swap_check.txt
# Built libraries go to ~/hostsweep/bench/synthetic_r5 so the original panel
# is untouched.
#
# Run it ALONE, after R1: the scoring step is timed. It is resumable.
#
# Usage:  bash benchmark/scripts/r5_extra_donors.sh

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/r_common.sh"

R5_FRACTIONS="${R5_FRACTIONS:-0.10 0.20}"
MIX_JOBS="${MIX_JOBS:-3}"
TOTAL_PAIRS="${TOTAL_PAIRS:-2000000}"
HUMAN_COV="${HUMAN_COV:-0.2}"
SYN5="$BENCH/synthetic_r5"
R5_RES="$OUT/r5_results"; R5_OUT="$OUT/r5"
REFS="$BENCH/refs"
mkdir -p "$SYN5" "$R5_RES" "$R5_OUT" "$BENCH/logs"

exec 6>"$OUT/.r5.lock"; flock -n 6 || { rsay "R5 already running; exiting"; exit 0; }
conda activate hostsweep || { rsay "cannot activate the hostsweep env"; exit 1; }
for t in art_illumina python3; do command -v "$t" >/dev/null 2>&1 || { rsay "$t not on PATH"; exit 1; }; done
[ -s "$BENCH/background_R1.fastq.gz" ] && [ -s "$BENCH/background_R2.fastq.gz" ] \
    || { rsay "background community reads missing under $BENCH (the panel build makes them)"; exit 1; }

# donor:population code:human-sim seed
DONORS=("HG02080:KHV:54" "HG03098:MSL:55" "HG01358:CLM:56")

# --- 1. assemblies + provenance gate ------------------------------------
rsay "R5 step 1/4: fetch the three donor assemblies and check their provenance"
python "$SCRIPT_DIR/03_fetch_human_sources.py" --extra --refs "$REFS" \
    --report "$OUT/r5_donor_provenance.json" \
    || { rsay "provenance check reported problems; not going on (see above)"; exit 1; }

# --- 2. human read simulation --------------------------------------------
rsay "R5 step 2/4: simulate human reads (ART HS25, ${HUMAN_COV}x)"
for d in "${DONORS[@]}"; do
    IFS=: read -r DONOR POP SEED <<< "$d"
    FA="$REFS/${DONOR}_pri_mat_f1_v2.fna"
    if [ -s "$BENCH/human_${DONOR}_R1.fq" ] && [ -s "$BENCH/human_${DONOR}_R2.fq" ]; then
        rsay "  human_${DONOR} already simulated"; continue
    fi
    [ -s "$FA" ] || { rsay "  $FA missing"; exit 1; }
    rsay "  simulating human_${DONOR} (seed $SEED) from $(basename "$FA")"
    # Simulate under a temporary name and rename only when ART has finished: a
    # file that merely exists is not evidence that it is complete.
    TMPP="$BENCH/.art_${DONOR}_R"
    rm -f "${TMPP}1.fq" "${TMPP}2.fq"
    art_illumina -ss HS25 -i "$FA" -p -l 150 -f "$HUMAN_COV" -m 200 -s 10 -rs "$SEED" -na \
        -o "$TMPP" > "$BENCH/logs/art_human_${DONOR}.log" 2>&1 \
        || { rsay "  ART FAILED for $DONOR (see $BENCH/logs/art_human_${DONOR}.log)"; exit 1; }
    mv "${TMPP}2.fq" "$BENCH/human_${DONOR}_R2.fq" && mv "${TMPP}1.fq" "$BENCH/human_${DONOR}_R1.fq"
done

# --- 3. mix with the background -------------------------------------------
rsay "R5 step 3/4: mix into libraries ($TOTAL_PAIRS pairs each)"
PANEL="$R5_OUT/r5_panel.tsv"
printf 'seed\tlibrary\tdonor\tfraction\n' > "$PANEL"
MSEED=57
for FR in $R5_FRACTIONS; do
    PCT="$(awk -v f="$FR" 'BEGIN{printf "%02d", f*100+0.5}')"
    for d in "${DONORS[@]}"; do
        IFS=: read -r DONOR POP SEED <<< "$d"
        printf '%s\tSYN-%s-%s\t%s\t%s\n' "$MSEED" "$POP" "$PCT" "$DONOR" "$FR" >> "$PANEL"
        MSEED=$((MSEED+1))
    done
done
cp -f "$PANEL" "$OUT/r5_panel.tsv"

declare -a PIDS=() LABELS=()
FAILED=0
reap_one() {
    [ ${#PIDS[@]} -gt 0 ] || return 1
    local pid="${PIDS[0]}" label="${LABELS[0]}"
    PIDS=("${PIDS[@]:1}"); LABELS=("${LABELS[@]:1}")
    if wait "$pid" && [ -s "$SYN5/${label}_manifest.json" ]; then rsay "  done $label"
    else rsay "  FAILED $label (see $BENCH/logs/mix_${label}.log)"; FAILED=$((FAILED+1)); fi
    return 0
}
while IFS=$'\t' read -r SEED LABEL DONOR FR; do
    [ "$SEED" = seed ] && continue
    if [ -s "$SYN5/${LABEL}_R1.fastq.gz" ] && [ -s "$SYN5/${LABEL}_manifest.json" ]; then
        rsay "  $LABEL already built"; continue
    fi
    while [ ${#PIDS[@]} -ge "$MIX_JOBS" ]; do reap_one || break; done
    rsay "  start $LABEL (seed $SEED, $DONOR, fraction $FR)"
    python3 "$SCRIPT_DIR/mix_spikein.py" \
        --background-r1 "$BENCH/background_R1.fastq.gz" \
        --background-r2 "$BENCH/background_R2.fastq.gz" \
        --human-r1 "$BENCH/human_${DONOR}_R1.fq" --human-r2 "$BENCH/human_${DONOR}_R2.fq" \
        --fraction "$FR" --total-pairs "$TOTAL_PAIRS" --seed "$SEED" \
        --out-prefix "$SYN5/$LABEL" < /dev/null > "$BENCH/logs/mix_${LABEL}.log" 2>&1 &
    PIDS+=($!); LABELS+=("$LABEL")
done < "$PANEL"
while reap_one; do :; done
[ "$FAILED" -eq 0 ] || { rsay "$FAILED library build(s) failed; not scoring a partial set"; exit 1; }

# --- 4. score, timed -------------------------------------------------------
rsay "R5 step 4/4: score $(( $(wc -l < "$PANEL") - 1 )) libraries with all tools, 3 runs each"
tools_for_timing || exit 1
[ "${SKIP_HOSTILE_DEFAULT:-0}" = 1 ] || ensure_hostile_index || exit 1
record_swap_state "$R5_OUT/machine.txt"
FIRST="$(awk -F'\t' 'NR==2 {print $2}' "$PANEL")"
warmup_tools "$SYN5" "$FIRST" "${TIMING_TOOLS[@]}"

KEEP_CLEANED=0 WARM_INPUT=1 bash "$SCRIPTS/run_e3.sh" "$SYN5" "$R5_RES" 3 "${TIMING_TOOLS[@]}" \
    || rsay "run_e3.sh returned non-zero; summarising whatever completed"

conda activate hostsweep
python "$SCRIPTS/aggregate_results.py" --results "$R5_RES" --synthetic "$SYN5" --out-dir "$R5_OUT" \
    || rsay "aggregate failed"
python "$SCRIPTS/timing_summary.py" --results "$R5_RES" --out-dir "$R5_OUT" --threads "$THREADS" \
    || rsay "timing summary failed"
rsay "R5 complete: $(( $(wc -l < "$R5_OUT/per_library.csv" 2>/dev/null || echo 1) - 1 )) rows in r5/per_library.csv"
