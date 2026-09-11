#!/usr/bin/env bash
# Where did MetaQUAST get reference genomes for the REAL libraries?
#
# run_e9.sh calls metaquast.py WITHOUT -r for real libraries, intending a
# reference-free run. But downstream.csv carries genome_fraction and
# misassemblies for them, and those metrics need a reference. MetaQUAST's
# documented behaviour without -r is to search SILVA 16S and download
# reference genomes from NCBI itself. If it did, the real-library figures were
# computed against references MetaQUAST chose on its own -- not a known set.
set -uo pipefail

MQROOT="$HOME/hostsweep/out/downstream_results/metaquast"

for d in "$MQROOT"/SRR40486826_hostsweep "$MQROOT"/ERR15898346_hostsweep \
         "$MQROOT"/SRR31641567_hostsweep "$MQROOT"/SYN-CHM13-01_hostsweep; do
    [ -d "$d" ] || continue
    echo "=== $(basename "$d") ==="
    echo "  top-level entries: $(ls "$d" | tr '\n' ' ')"
    dl="$d/quast_downloaded_references"
    if [ -d "$dl" ]; then
        echo "  quast_downloaded_references: $(ls "$dl" | wc -l) entries"
        ls "$dl" | head -6 | sed 's/^/      /'
    else
        echo "  quast_downloaded_references: none"
    fi
    for rep in "$d/combined_reference/report.tsv" "$d/report.tsv"; do
        [ -f "$rep" ] || continue
        echo "  report used: ${rep#$d/}"
        grep -E '^(Genome fraction|# misassemblies|Reference length)' "$rep" | sed 's/^/      /'
        break
    done
    log="$d/metaquast.log"
    [ -f "$log" ] && grep -iE 'download|silva|blast|reference genomes' "$log" | head -4 | sed 's/^/  log: /'
    echo
done
