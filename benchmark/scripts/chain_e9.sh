#!/usr/bin/env bash
# E9 end to end: clean with three methods, marshal, assemble, score.
#
# Waits for E7 to finish, then for each selected library runs HostSweep,
# KneadData and Hostile (Bowtie2, matched T2T index), stages their cleaned
# paired reads into one layout, and hands them to run_e9.sh for MEGAHIT +
# MetaQUAST + Kraken2.
#
# ---------------------------------------------------------------------------
# SCOPE: libraries are cut, the three-way comparison is not.
#
# The protocol asks for 6 real + 12 synthetic libraries x 3 methods = 54
# assemblies, which is roughly 50 hours here. The instruction when scope has
# to shrink is explicit: cut libraries, never the HostSweep/KneadData/Hostile
# comparison, because Reviewer 3 asked for Hostile and Editor 15 requires it.
#
# So this runs 6 libraries x 3 methods = 18 assemblies:
#
#   synthetic, spanning the host-fraction range and both conditions:
#     SYN-CHM13-01   0.1%  matched, lowest host
#     SYN-CHM13-05   10%   matched, mid host
#     SYN-NEU-03     20%   MISMATCH, so the arm is represented downstream
#
#   real, one per category, smallest run in each to bound assembly time,
#   each from a different BioProject:
#     SRR40486826    gut          PRJNA1522489
#     ERR15898346    respiratory  PRJEB103799
#     SRR31641567    blood        PRJNA1195412
#
# Widening is a matter of adding names to SYN_LIBS / REAL_LIBS and re-running;
# every stage skips work already done.
# ---------------------------------------------------------------------------
#
# Usage:  bash chain_e9.sh
set -uo pipefail

ROOT="$HOME/hostsweep"
REPO="$ROOT/HostSweep"
OUT="$ROOT/out"
BENCH="$ROOT/bench"
SYN="$BENCH/synthetic"
E4="$ROOT/e4_fastq"
SCRIPTS="$REPO/benchmark/scripts"
CLEAN_ROOT="$OUT/e9_cleaned"
E9_RESULTS="$OUT/downstream_results"
REFS="$BENCH/refs"

SYN_LIBS=(SYN-CHM13-01 SYN-CHM13-05 SYN-NEU-03)
REAL_LIBS=(SRR40486826 ERR15898346 SRR31641567)

export THREADS="${THREADS:-8}"
export HOSTSWEEP_BBDUK_MEM="${HOSTSWEEP_BBDUK_MEM:-3g}"
BT2_INDEX="$ROOT/miniforge3/envs/hostsweep/share/hostsweep/databases/standard/human_bt2"
export BT2_INDEX
export K2DB="$ROOT/k2_standard_08gb"

CONDA_SH="$ROOT/miniforge3/etc/profile.d/conda.sh"
mkdir -p "$OUT" "$CLEAN_ROOT" "$E9_RESULTS"
say() { echo "[E9chain $(date -u +%H:%M:%S)] $*"; }

exec 7>"$OUT/.e9chain.lock"
if ! flock -n 7; then say "another E9 chain is running; exiting"; exit 0; fi

# --- wait for E7 ------------------------------------------------------
say "waiting for E7 to finish"
for _ in $(seq 1 2880); do
    pgrep -f run_e7.sh >/dev/null 2>&1 || break
    sleep 30
done
say "E7 no longer running"

if [ -s "$OUT/sweep_results/threshold_sweep.csv" ]; then
    cp "$OUT/sweep_results/threshold_sweep.csv" "$OUT/threshold_sweep.csv"
    say "threshold_sweep.csv: $(( $(wc -l < "$OUT/threshold_sweep.csv") - 1 )) rows"
fi

# --- clean each library with each method -------------------------------
# r1_of / r2_of resolve either naming convention.
r1_of() {
    case "$1" in
        SYN-*) echo "$SYN/$1_R1.fastq.gz" ;;
        *)     echo "$E4/$1_1.fastq.gz" ;;
    esac
}
r2_of() {
    case "$1" in
        SYN-*) echo "$SYN/$1_R2.fastq.gz" ;;
        *)     echo "$E4/$1_2.fastq.gz" ;;
    esac
}

run_hostsweep() {
    local lib="$1" r1="$2" r2="$3"
    local dest="$CLEAN_ROOT/$lib"
    [ -s "$dest/hostsweep_R1.fastq.gz" ] && { say "  $lib hostsweep: present"; return 0; }
    local wd="$E9_RESULTS/$lib/hostsweep.work"
    rm -rf "$wd"; mkdir -p "$wd" "$dest"
    # shellcheck disable=SC1090
    . "$CONDA_SH"; conda activate hostsweep
    /usr/bin/time -v -o "$E9_RESULTS/$lib/hostsweep.time" \
        hostsweep -1 "$r1" -2 "$r2" -n "$lib" -o "$wd" -i standard -t "$THREADS" \
        > "$E9_RESULTS/$lib/hostsweep.stdout" 2> "$E9_RESULTS/$lib/hostsweep.stderr"
    local rc=$?
    conda deactivate
    if [ "$rc" -ne 0 ] || [ ! -s "$wd/cleaned/${lib}_ASSEMBLY_R1.fastq.gz" ]; then
        say "  $lib hostsweep: FAILED (exit $rc)"; rm -rf "$wd"; return 1
    fi
    cp "$wd/cleaned/${lib}_ASSEMBLY_R1.fastq.gz" "$dest/hostsweep_R1.fastq.gz"
    cp "$wd/cleaned/${lib}_ASSEMBLY_R2.fastq.gz" "$dest/hostsweep_R2.fastq.gz"
    rm -rf "$wd"
    say "  $lib hostsweep: done"
}

run_kneaddata() {
    local lib="$1" r1="$2" r2="$3"
    local dest="$CLEAN_ROOT/$lib"
    [ -s "$dest/kneaddata_R1.fastq.gz" ] && { say "  $lib kneaddata: present"; return 0; }
    local wd="$E9_RESULTS/$lib/kneaddata.work"
    rm -rf "$wd"; mkdir -p "$wd" "$dest"
    # shellcheck disable=SC1090
    . "$CONDA_SH"; conda activate kneaddata
    /usr/bin/time -v -o "$E9_RESULTS/$lib/kneaddata.time" \
        kneaddata --input1 "$r1" --input2 "$r2" --reference-db "$BT2_INDEX" \
                  --output "$wd" --threads "$THREADS" --bypass-trf \
                  --remove-intermediate-output \
        > "$E9_RESULTS/$lib/kneaddata.stdout" 2> "$E9_RESULTS/$lib/kneaddata.stderr"
    local rc=$?
    conda deactivate
    local k1 k2
    k1=$(ls "$wd"/*paired_1.fastq 2>/dev/null | head -1)
    k2=$(ls "$wd"/*paired_2.fastq 2>/dev/null | head -1)
    if [ "$rc" -ne 0 ] || [ -z "$k1" ] || [ -z "$k2" ]; then
        say "  $lib kneaddata: FAILED (exit $rc)"; rm -rf "$wd"; return 1
    fi
    gzip -c "$k1" > "$dest/kneaddata_R1.fastq.gz"
    gzip -c "$k2" > "$dest/kneaddata_R2.fastq.gz"
    rm -rf "$wd"
    say "  $lib kneaddata: done"
}

run_hostile() {
    local lib="$1" r1="$2" r2="$3"
    local dest="$CLEAN_ROOT/$lib"
    [ -s "$dest/hostile_R1.fastq.gz" ] && { say "  $lib hostile: present"; return 0; }
    local wd="$E9_RESULTS/$lib/hostile.work"
    rm -rf "$wd"; mkdir -p "$wd" "$dest"
    # shellcheck disable=SC1090
    . "$CONDA_SH"; conda activate hostile
    # Matched configuration: the same T2T Bowtie2 index every other method uses,
    # so the comparison is method rather than reference.
    /usr/bin/time -v -o "$E9_RESULTS/$lib/hostile.time" \
        hostile clean --fastq1 "$r1" --fastq2 "$r2" --aligner bowtie2 \
                      --index "$BT2_INDEX" --threads "$THREADS" --output "$wd" \
        > "$E9_RESULTS/$lib/hostile.stdout" 2> "$E9_RESULTS/$lib/hostile.stderr"
    local rc=$?
    conda deactivate
    local h1 h2
    h1=$(ls "$wd"/*clean_1.fastq.gz 2>/dev/null | head -1)
    h2=$(ls "$wd"/*clean_2.fastq.gz 2>/dev/null | head -1)
    if [ "$rc" -ne 0 ] || [ -z "$h1" ] || [ -z "$h2" ]; then
        say "  $lib hostile: FAILED (exit $rc)"; rm -rf "$wd"; return 1
    fi
    cp "$h1" "$dest/hostile_R1.fastq.gz"
    cp "$h2" "$dest/hostile_R2.fastq.gz"
    rm -rf "$wd"
    say "  $lib hostile: done"
}

ALL_LIBS=("${SYN_LIBS[@]}" "${REAL_LIBS[@]}")
say "cleaning ${#ALL_LIBS[@]} libraries with 3 methods"
for LIB in "${ALL_LIBS[@]}"; do
    R1="$(r1_of "$LIB")"; R2="$(r2_of "$LIB")"
    if [ ! -s "$R1" ] || [ ! -s "$R2" ]; then
        say "  $LIB: reads absent, skipping"; continue
    fi
    mkdir -p "$E9_RESULTS/$LIB"
    say " $LIB"
    run_hostsweep "$LIB" "$R1" "$R2" || true
    run_kneaddata "$LIB" "$R1" "$R2" || true
    run_hostile   "$LIB" "$R1" "$R2" || true
done

# --- reference set for the synthetic arm -------------------------------
MQ_REFS="$OUT/e9_refs"
mkdir -p "$MQ_REFS"
for f in "$REFS"/GCF_*.fna; do
    [ -e "$f" ] && cp -n "$f" "$MQ_REFS/" 2>/dev/null
done
say "MetaQUAST reference set: $(ls "$MQ_REFS" | wc -l) genomes"

# --- assemble and score ------------------------------------------------
say "running E9 over $(ls "$CLEAN_ROOT" | wc -l) staged libraries"
bash "$SCRIPTS/run_e9.sh" "$CLEAN_ROOT" "$E9_RESULTS" "$MQ_REFS" "${ALL_LIBS[@]}"

for f in downstream.csv kraken2_human.csv; do
    if [ -s "$E9_RESULTS/$f" ]; then
        cp "$E9_RESULTS/$f" "$OUT/$f"
        say "$f: $(( $(wc -l < "$OUT/$f") - 1 )) rows"
    else
        say "$f: NOT produced"
    fi
done
say "E9 chain complete"
