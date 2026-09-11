#!/usr/bin/env bash
# For each real library, did the three cleaning methods get the SAME reference
# set from MetaQUAST, or different ones?
#
# Each metaquast.py run does its own SILVA 16S search against its OWN contigs,
# so each method's assembly may be scored against references chosen from that
# method's output. If the sets differ, the between-method comparison is invalid
# on real libraries -- not merely uninterpretable in absolute terms.
set -uo pipefail

MQ="$HOME/hostsweep/out/downstream_results/metaquast"

for lib in SRR40486826 ERR15898346 SRR31641567; do
    echo "=== $lib ==="
    for m in hostsweep hostile kneaddata; do
        d="$MQ/${lib}_${m}"
        [ -d "$d" ] || { echo "  $m: no MetaQUAST run"; continue; }
        n=$(ls "$d/quast_downloaded_references" 2>/dev/null | grep -c '\.fasta$' || true)
        rl=$(grep '^Reference length' "$d/combined_reference/report.tsv" 2>/dev/null | cut -f2)
        printf '  %-10s %3s reference genomes, total reference length %s\n' "$m" "$n" "$rl"
        ls "$d/quast_downloaded_references" 2>/dev/null | grep '\.fasta$' | sort > "/tmp/refs_${lib}_${m}.txt"
    done
    # Pairwise overlap of the reference sets.
    for pair in "hostsweep hostile" "hostsweep kneaddata" "hostile kneaddata"; do
        set -- $pair
        a="/tmp/refs_${lib}_$1.txt"; b="/tmp/refs_${lib}_$2.txt"
        [ -s "$a" ] && [ -s "$b" ] || continue
        shared=$(comm -12 "$a" "$b" | wc -l)
        only_a=$(comm -23 "$a" "$b" | wc -l)
        only_b=$(comm -13 "$a" "$b" | wc -l)
        printf '  %-22s shared %3d   only-%s %3d   only-%s %3d\n' \
               "$1 vs $2" "$shared" "$1" "$only_a" "$2" "$only_b"
    done
    echo
done
rm -f /tmp/refs_*.txt
