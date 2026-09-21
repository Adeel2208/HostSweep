#!/usr/bin/env bash
# Package what a finished run produced into ONE small tarball, so it can be
# copied off the machine and merged.
#
# Takes the result CSVs, the audit, and the per-run evidence (metrics JSON,
# GNU time files, failure markers and the stderr of failed runs, Kraken2
# reports, CheckM2 output, MetaQUAST reports) plus the logs. Deliberately
# leaves out everything bulky -- FASTQ, contigs, BAMs, indexes, work trees --
# so the bundle is a few MB, not hundreds of GB.
#
# Read-only with respect to the run: nothing under ~/hostsweep/out is moved
# or deleted.
#
# Usage:  bash collect_results.sh
set -uo pipefail

ROOT="$HOME/hostsweep"
OUT="$ROOT/out"
REPO="$ROOT/HostSweep"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
NAME="results_bundle_$STAMP"
B="$ROOT/$NAME"

say() { echo "[collect] $*"; }
[ -d "$OUT" ] || { echo "no results directory at $OUT" >&2; exit 1; }

mkdir -p "$B/csv" "$B/evidence" "$B/logs"

# 1. result tables and the audit
cp -f "$OUT"/*.csv "$B/csv/" 2>/dev/null
cp -f "$OUT"/AUDIT.md "$B/csv/" 2>/dev/null
say "tables: $(ls "$B/csv" | tr '\n' ' ')"

# 2. per-run evidence, with paths kept relative to $OUT
cd "$OUT" || exit 1
find results downstream_results e4_results 2>/dev/null \( \
        -name 'metrics_*.json' -o -name '*.time' -o -name '*.failed' \
        -o -name 'k2.report' -o -name 'checkm2.stdout' -o -name 'checkm2.stderr' \
        -o -name 'megahit.stdout' -o -name 'report.tsv' \) -type f -print0 \
    | xargs -0 -r cp --parents -t "$B/evidence"

# a failed run's stderr says WHY it failed -- keep it, and only it
find results downstream_results e4_results -name '*.failed' -type f 2>/dev/null | while read -r f; do
    s="${f%.failed}.stderr"
    [ -f "$s" ] && cp --parents "$s" "$B/evidence"
done
say "evidence files: $(find "$B/evidence" -type f | wc -l)"

# 3. logs and the tool-version record
cp -f "$ROOT"/logs/*.log "$B/logs/" 2>/dev/null
[ -d "$ROOT/record" ] && cp -rf "$ROOT/record" "$B/logs/record"
"$ROOT/miniforge3/bin/conda" list -n hostsweep --explicit > "$B/logs/conda_hostsweep_explicit.txt" 2>/dev/null || true

# 4. a manifest, so the receiver can see what is and is not here
{
    echo "bundle:   $NAME"
    echo "built:    $STAMP"
    echo "commit:   $(git -C "$REPO" rev-parse HEAD 2>/dev/null || echo unknown)"
    echo
    echo "metrics JSON per tool (run 1):"
    ls "$B"/evidence/results/*/metrics_*_run1.json 2>/dev/null | sed 's/.*metrics_//' | sort | uniq -c
    echo
    echo "failed runs:"
    find "$B/evidence" -name '*.failed' 2>/dev/null | sed "s#$B/evidence/##" | sort
    echo
    echo "NOT included: FASTQ, contigs, alignments, indexes, work trees."
} > "$B/MANIFEST.txt"

tar -czf "$ROOT/$NAME.tar.gz" -C "$ROOT" "$NAME"
say "bundle:  $ROOT/$NAME.tar.gz  ($(du -h "$ROOT/$NAME.tar.gz" | cut -f1))"
echo
echo "Copy it to Windows so it can be sent on, e.g.:"
echo "    ls /mnt/c/Users/                       # find your Windows user folder"
echo "    cp $ROOT/$NAME.tar.gz /mnt/c/Users/<that folder>/Desktop/"
