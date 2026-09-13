#!/usr/bin/env bash
# Build the BMTagger reference index against T2T-CHM13v2.0 (D20).
#
# Three files bmtagger.sh needs, built once and reused by every library:
#
#   human.bitmask     bmtool word-mask. A FIXED size for a given word size --
#                     measured at 8.1 GB for word size 18 (the default)
#                     against a 4.7 Mb test genome, and it is fixed by
#                     4^18 bits regardless of reference size, not something
#                     that scales with it. Same 8.1 GB expected here.
#   human.srprism.*   the alignment index. This ONE SCALES WITH REFERENCE
#                     SIZE. Measured at ~28x the reference length against the
#                     4.7 Mb test genome (srprism.map alone was 129 MB). Its
#                     actual size and build time against the full 3.1 Gb
#                     T2T genome were UNKNOWN before this script ran for
#                     real -- extrapolating linearly suggests tens of GB and
#                     a build that could run for hours, but that had not
#                     been measured before this.
#   human.seqdb.*     a BLAST nucleotide database (makeblastdb), needed by
#                     bmtagger's extract step.
#
# Run in the `bmtagger` conda env (created by install_comparators.sh), which
# is where bmtool / srprism / makeblastdb live.
#
# Idempotent: skips any file already present and non-empty, so an
# interrupted build resumes at whichever of the three files it stopped on.
#
# Usage:
#     conda activate bmtagger
#     bash 07_build_bmtagger_index.sh [fasta] [dest]
#
# Environment:
#     THREADS   default 8 (makeblastdb only; bmtool and srprism mkindex are
#               single-threaded)

set -uo pipefail

FASTA="${1:-$CONDA_PREFIX/share/hostsweep/databases/standard/human_T2T.fasta}"
DEST="${2:-$HOME/hostsweep/bmtagger_index}"
THREADS="${THREADS:-8}"

say() { echo "[bmtagger-index $(date -u +%H:%M:%S)] $*"; }
fail() { echo "[bmtagger-index FAILED] $*" >&2; exit 1; }

for t in bmtool srprism makeblastdb; do
    command -v "$t" >/dev/null 2>&1 || fail "$t not on PATH -- activate the bmtagger conda env first"
done
[ -s "$FASTA" ] || fail "reference FASTA not found: $FASTA"

mkdir -p "$DEST"
exec 9>"$DEST/.build.lock"
if ! flock -n 9; then say "another build holds the lock; exiting"; exit 0; fi

# --- 1. bitmask --------------------------------------------------------
if [ -s "$DEST/human.bitmask" ]; then
    say "bitmask already present ($(du -h "$DEST/human.bitmask" | cut -f1))"
else
    say "building bitmask (bmtool, word size 18 -- expect ~8.1 GB)"
    bmtool -d "$FASTA" -o "$DEST/human.bitmask" -w 18 -q \
        > "$DEST/bmtool.stdout" 2> "$DEST/bmtool.stderr" \
        || fail "bmtool -- see $DEST/bmtool.stderr"
    say "  done: $(du -h "$DEST/human.bitmask" | cut -f1)"
fi

# --- 2. srprism index ---------------------------------------------------
if [ -s "$DEST/human.srprism.idx" ]; then
    say "srprism index already present"
else
    # --memory is a working-set hint, not a hard cap; leave headroom for the
    # OS and whatever else is running rather than handing it everything free.
    FREE_MB=$(free -m | awk '/^Mem:/{print $7}')
    SRPRISM_MEM=$(( FREE_MB > 4096 ? (FREE_MB - 2048 > 24576 ? 24576 : FREE_MB - 2048) : 2048 ))
    say "building srprism index (--memory ${SRPRISM_MEM} MB)"
    say "  UNMEASURED AT THIS SCALE BEFORE NOW -- may take a long time and"
    say "  produce an index far larger than the 129 MB seen on the 4.7 Mb"
    say "  test genome. Letting it run to completion or to a hard failure;"
    say "  not estimating what it would produce."
    srprism mkindex -i "$FASTA" -o "$DEST/human.srprism" --memory "$SRPRISM_MEM" \
        > "$DEST/srprism.stdout" 2> "$DEST/srprism.stderr" \
        || fail "srprism mkindex -- see $DEST/srprism.stderr"
    say "  done: $(du -ch "$DEST"/human.srprism.* 2>/dev/null | tail -1 | cut -f1)"
fi

# --- 3. blast seqdb ------------------------------------------------------
if [ -s "$DEST/human.seqdb.nsq" ]; then
    say "blast seqdb already present"
else
    say "building blast seqdb (makeblastdb)"
    makeblastdb -in "$FASTA" -dbtype nucl -out "$DEST/human.seqdb" \
        > "$DEST/makeblastdb.stdout" 2> "$DEST/makeblastdb.stderr" \
        || fail "makeblastdb -- see $DEST/makeblastdb.stderr"
    say "  done: $(du -ch "$DEST"/human.seqdb.* 2>/dev/null | tail -1 | cut -f1)"
fi

say "BMTagger index ready at $DEST"
say "export BMTAGGER_BITMASK=$DEST/human.bitmask"
say "export BMTAGGER_SRPRISM=$DEST/human.srprism"
say "export BMTAGGER_SEQDB=$DEST/human.seqdb"
