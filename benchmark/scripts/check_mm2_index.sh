#!/usr/bin/env bash
# Confirm the minimap2 index covers the whole reference in ONE batch.
#
# hostsweep --build runs `minimap2 -x sr -d <mmi> <fasta>` with no -I. If the
# reference exceeds minimap2's default batch size, the .mmi holds several
# indexes and an alignment run silently uses each in turn -- which for host
# removal means reads are compared against part of the genome per pass. A
# multi-part index would understate host content.
#
# The check is empirical, not a reading of the default: align one tiny read
# against the built index and count how many times minimap2 reports loading an
# index. One line means one batch, so the whole reference is in play at once.
#
# Usage:  bash check_mm2_index.sh [mmi] [fasta]
set -uo pipefail

DB="$HOME/hostsweep/miniforge3/envs/hostsweep/share/hostsweep/databases/standard"
MMI="${1:-$DB/human.mmi}"
FASTA="${2:-$DB/human_T2T.fasta}"

[ -s "$MMI" ] || { echo "index absent: $MMI" >&2; exit 1; }

echo "index : $MMI ($(du -h "$MMI" | cut -f1))"
echo "ref   : $FASTA ($(du -h "$FASTA" | cut -f1))"
echo
echo "minimap2 version: $(minimap2 --version)"
echo "default -I     : $(minimap2 --help 2>&1 | grep -E '^\s*-I' | head -1 | sed 's/^ *//')"
echo

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# A single 100 bp read is enough: minimap2 loads every index batch regardless.
printf '@probe\n%s\n+\n%s\n' \
    "$(head -c 100000 "$FASTA" | grep -v '^>' | tr -d '\n' | head -c 100)" \
    "$(printf 'I%.0s' $(seq 1 100))" > "$TMP/probe.fq"

minimap2 -ax sr -t 1 "$MMI" "$TMP/probe.fq" > /dev/null 2> "$TMP/mm2.err"

echo "--- minimap2 index-load messages ---"
grep -E 'loaded/built the index|Real time|inconsistent' "$TMP/mm2.err" || true
echo

BATCHES=$(grep -c 'loaded/built the index' "$TMP/mm2.err" || true)
echo "index batches loaded: $BATCHES"
if [ "$BATCHES" = "1" ]; then
    echo "RESULT: PASS -- single-batch index; the whole reference is searched in one pass."
elif [ "$BATCHES" = "0" ]; then
    echo "RESULT: INCONCLUSIVE -- minimap2 printed no index-load line; see stderr below."
    cat "$TMP/mm2.err"
else
    echo "RESULT: FAIL -- $BATCHES batches. The index is split, so each alignment pass"
    echo "        sees only part of the reference. Rebuild with -I large enough to"
    echo "        hold the reference in one batch (e.g. -I 8G for T2T-CHM13v2.0)."
fi
