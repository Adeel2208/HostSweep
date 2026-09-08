#!/usr/bin/env bash
# Marshal each tool's cleaned paired reads into the layout run_e9.sh expects.
#
#     <cleaned_root>/<library>/<method>_R1.fastq.gz
#     <cleaned_root>/<library>/<method>_R2.fastq.gz
#
# The three methods write three different structures, and E9 needs matched
# paired-end input from all of them so the assembly comparison is about
# cleaning rather than read structure:
#
#   hostsweep   <work>/cleaned/<lib>_ASSEMBLY_R1.fastq.gz   (Output 1, PE)
#   kneaddata   <work>/*paired_1.fastq / *paired_2.fastq    (uncompressed)
#   hostile     <work>/*.clean_1.fastq.gz / *.clean_2.fastq.gz
#
# Copies only what exists. A missing method is reported and skipped, never
# substituted from another method's output -- that would silently compare a
# tool against itself.
#
# Usage:
#     bash collect_cleaned.sh <results_root> <cleaned_root> [method ...]
#
#   <results_root> holds <library>/cleaned_run1/ (written by run_e3/run_e4)
#   or <library>/<method>_run1.work/ if work trees were kept.

set -uo pipefail

RESULTS="${1:?usage: collect_cleaned.sh <results_root> <cleaned_root> [method ...]}"
CLEANED="${2:?}"
shift 2
METHODS=("$@")
[ ${#METHODS[@]} -gt 0 ] || METHODS=(hostsweep kneaddata hostile)

mkdir -p "$CLEANED"
say() { echo "[collect $(date -u +%H:%M:%S)] $*"; }

# gz_copy <src> <dest.gz> -- copy, compressing if the source is plain text.
gz_copy() {
    local src="$1" dest="$2"
    [ -s "$src" ] || return 1
    if [[ "$src" == *.gz ]]; then
        cp -f "$src" "$dest"
    else
        gzip -c "$src" > "$dest"
    fi
}

# Locate a method's R1/R2 under a library's results directory.
find_pair() {
    local libdir="$1" lib="$2" method="$3"
    local r1="" r2=""
    case "$method" in
        hostsweep)
            r1=$(ls "$libdir"/cleaned_run*/"${lib}_ASSEMBLY_R1.fastq.gz" \
                    "$libdir"/*_run*.work/cleaned/"${lib}_ASSEMBLY_R1.fastq.gz" \
                    2>/dev/null | head -1)
            [ -n "$r1" ] && r2="${r1/_ASSEMBLY_R1/_ASSEMBLY_R2}"
            ;;
        kneaddata)
            r1=$(ls "$libdir"/kneaddata_run*.work/*paired_1.fastq* 2>/dev/null | head -1)
            [ -n "$r1" ] && r2="${r1/paired_1/paired_2}"
            ;;
        hostile|hostile_matched|hostile_default)
            r1=$(ls "$libdir"/hostile*_run*.work/*clean_1.fastq.gz 2>/dev/null | head -1)
            [ -n "$r1" ] && r2="${r1/clean_1/clean_2}"
            ;;
    esac
    [ -n "$r1" ] && [ -s "$r1" ] && [ -n "$r2" ] && [ -s "$r2" ] || return 1
    printf '%s\n%s\n' "$r1" "$r2"
}

FOUND=0; MISSING=0
shopt -s nullglob
for LIBDIR in "$RESULTS"/*/; do
    LIB="$(basename "$LIBDIR")"
    for METHOD in "${METHODS[@]}"; do
        DEST_R1="$CLEANED/$LIB/${METHOD}_R1.fastq.gz"
        DEST_R2="$CLEANED/$LIB/${METHOD}_R2.fastq.gz"
        if [ -s "$DEST_R1" ] && [ -s "$DEST_R2" ]; then
            FOUND=$((FOUND+1)); continue
        fi
        mapfile -t PAIR < <(find_pair "$LIBDIR" "$LIB" "$METHOD")
        if [ ${#PAIR[@]} -lt 2 ]; then
            say "  $LIB / $METHOD: no paired cleaned output found"
            MISSING=$((MISSING+1)); continue
        fi
        mkdir -p "$CLEANED/$LIB"
        if gz_copy "${PAIR[0]}" "$DEST_R1" && gz_copy "${PAIR[1]}" "$DEST_R2"; then
            say "  $LIB / $METHOD: staged"
            FOUND=$((FOUND+1))
        else
            say "  $LIB / $METHOD: copy FAILED"
            rm -f "$DEST_R1" "$DEST_R2"
            MISSING=$((MISSING+1))
        fi
    done
done

say "staged $FOUND method-library pairs; $MISSING missing"
say "E9 input root: $CLEANED"
[ "$FOUND" -gt 0 ]
