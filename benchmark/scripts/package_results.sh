#!/usr/bin/env bash
# Stage 10: assemble results_bundle/ and zip it.
#
# Copies only files that exist. A deliverable that was never produced is listed
# in the bundle's MANIFEST.txt as ABSENT rather than being fabricated as an
# empty file -- an empty CSV reads like "measured, found nothing", which is a
# different claim from "never ran".
#
# Runs audit.py first and refuses to package if the audit fails, unless
# --force is given (which is itself recorded in the manifest).
#
# Usage:
#     bash package_results.sh <repo_root> [--force]

set -uo pipefail

REPO="${1:?usage: package_results.sh <repo_root> [--force]}"
FORCE="${2:-}"
RUN="$REPO/benchmark/run"
BUNDLE="$RUN/results_bundle"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"

say() { echo "[package $(date -u +%H:%M:%S)] $*"; }

# --- audit gate -------------------------------------------------------
say "running audit"
AUDIT_RC=0
python3 "$RUN/audit.py" --run-dir "$RUN" --out "$RUN/AUDIT.md" \
    > "$RUN/logs/audit.out" 2>&1 || AUDIT_RC=$?
say "audit exit=$AUDIT_RC (see $RUN/AUDIT.md)"
if [ "$AUDIT_RC" -ne 0 ] && [ "$FORCE" != "--force" ]; then
    say "REFUSING to package: audit reported failures. Fix them, or re-run"
    say "with --force if you intend to ship a bundle with known problems."
    exit 1
fi

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/logs" "$BUNDLE/metaquast"

MANIFEST="$BUNDLE/MANIFEST.txt"
{
    echo "HostSweep benchmark results bundle"
    echo "built:  $STAMP"
    echo "commit: $(git -C "$REPO" rev-parse HEAD 2>/dev/null || echo unknown)"
    echo "audit:  exit $AUDIT_RC$([ "$FORCE" = "--force" ] && echo '  (PACKAGED WITH --force DESPITE FAILURES)')"
    echo
    echo "Contents (PRESENT = produced by a run in this session;"
    echo "          ABSENT  = never produced, and deliberately not faked):"
    echo
} > "$MANIFEST"

# copy_in <source> <dest-relative>
copy_in() {
    local src="$1" rel="$2"
    if [ -e "$src" ]; then
        mkdir -p "$BUNDLE/$(dirname "$rel")"
        cp -r "$src" "$BUNDLE/$rel"
        local size
        size="$(du -sh "$BUNDLE/$rel" 2>/dev/null | cut -f1)"
        printf '  PRESENT  %-34s %s\n' "$rel" "$size" >> "$MANIFEST"
    else
        printf '  ABSENT   %-34s (never produced)\n' "$rel" >> "$MANIFEST"
    fi
}

copy_in "$RUN/record/versions.txt"          versions.txt
copy_in "$RUN/record/conda_explicit.txt"    conda_explicit.txt
copy_in "$RUN/accessions_verified.csv"      accessions_verified.csv
copy_in "$RUN/verification_log.txt"         verification_log.txt
copy_in "$RUN/accession_candidates.csv"     accession_candidates.csv
copy_in "$RUN/synthetic_manifest.csv"       synthetic_manifest.csv
copy_in "$RUN/per_library.csv"              per_library.csv
copy_in "$RUN/ablation.csv"                 ablation.csv
copy_in "$RUN/threshold_sweep.csv"          threshold_sweep.csv
copy_in "$RUN/downstream.csv"               downstream.csv
copy_in "$RUN/kraken2_human.csv"            kraken2_human.csv
copy_in "$RUN/labelling_sensitivity.csv"    labelling_sensitivity.csv
copy_in "$RUN/AUDIT.md"                     AUDIT.md
copy_in "$RUN/STATUS.md"                    STATUS.md
copy_in "$RUN/DEVIATIONS.md"                DEVIATIONS.md
copy_in "$RUN/panel_proposed.csv"           panel_proposed.csv
copy_in "$RUN/genomes_verified.tsv"         genomes_verified.tsv
copy_in "$RUN/human_sources_provenance.json" human_sources_provenance.json

# MetaQUAST per-sample reports
if [ -d "$RUN/downstream_results/metaquast" ]; then
    cp -r "$RUN/downstream_results/metaquast/." "$BUNDLE/metaquast/" 2>/dev/null
    n=$(find "$BUNDLE/metaquast" -mindepth 1 -maxdepth 1 -type d | wc -l)
    printf '  PRESENT  %-34s %d report(s)\n' "metaquast/" "$n" >> "$MANIFEST"
else
    printf '  ABSENT   %-34s (E9 not run)\n' "metaquast/" >> "$MANIFEST"
fi

# Raw evidence: stdout, stderr, .time files, metrics JSON, command journal.
say "collecting raw logs and per-run evidence"
cp -r "$RUN/logs/." "$BUNDLE/logs/" 2>/dev/null
for d in results ablation_results sweep_results downstream_results; do
    [ -d "$RUN/$d" ] || continue
    mkdir -p "$BUNDLE/logs/$d"
    # Evidence only; the bulk FASTQ intermediates are not shipped.
    find "$RUN/$d" \( -name '*.json' -o -name '*.time' -o -name '*.stdout' \
        -o -name '*.stderr' -o -name '*.failed' -o -name '*.log' \) \
        -exec cp --parents {} "$BUNDLE/logs/$d/" \; 2>/dev/null
done
printf '  PRESENT  %-34s %s\n' "logs/" "$(du -sh "$BUNDLE/logs" | cut -f1)" >> "$MANIFEST"

{
    echo
    echo "Not included, by design:"
    echo "  - FASTQ, BAM/SAM and index files (regenerate from benchmark/scripts)"
    echo "  - tool work trees (deleted after each run to bound disk use)"
} >> "$MANIFEST"

# --- zip --------------------------------------------------------------
ZIP="$RUN/hostsweep_results_bundle_${STAMP}.zip"
say "zipping"
( cd "$RUN" && zip -q -r "$ZIP" "results_bundle" ) \
    || { say "zip failed -- is zip installed?"; exit 1; }

say "wrote $ZIP ($(du -h "$ZIP" | cut -f1))"
cat "$MANIFEST"
