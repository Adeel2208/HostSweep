#!/usr/bin/env bash
# Post-install verification: prove the toolchain is present and the test suite
# passes before any measurement is attempted, and record the exact versions.
#
# Usage: bash wsl_verify.sh [out_dir]
set -uo pipefail

OUT="${1:-$HOME/hostsweep/record}"
mkdir -p "$OUT"

source "$HOME/hostsweep/miniforge3/etc/profile.d/conda.sh"
conda activate hostsweep || { echo "cannot activate env"; exit 1; }

REPO="$HOME/hostsweep/HostSweep"
cd "$REPO" || exit 1

echo "=== repo ==="
git rev-parse --short HEAD

echo
echo "=== pip install -e ==="
pip install -q -e . 2>&1 | tail -3
python -m pytest --version >/dev/null 2>&1 || pip install -q pytest

echo
echo "=== toolchain ==="
MISSING=0
for t in fastp minimap2 bowtie2 bowtie2-build samtools bbduk.sh art_illumina hostsweep seqkit; do
    if command -v "$t" >/dev/null 2>&1; then
        printf '  %-16s %s\n' "$t" "$(command -v "$t")"
    else
        printf '  %-16s ABSENT\n' "$t"
        MISSING=$((MISSING + 1))
    fi
done
echo "  missing: $MISSING"

echo
echo "=== versions.txt ==="
{
    echo "# Tool versions recorded $(date -u +%FT%TZ)"
    echo "# host: $(uname -srm)  |  repo: $(git rev-parse HEAD)"
    echo
    printf '%-14s %s\n' "hostsweep" "$(hostsweep --version 2>&1 | head -1)"
    printf '%-14s %s\n' "python"    "$(python --version 2>&1)"
    printf '%-14s %s\n' "fastp"     "$(fastp --version 2>&1 | head -1)"
    printf '%-14s %s\n' "minimap2"  "$(minimap2 --version 2>&1 | head -1)"
    printf '%-14s %s\n' "bowtie2"   "$(bowtie2 --version 2>&1 | head -1)"
    printf '%-14s %s\n' "samtools"  "$(samtools --version 2>&1 | head -1)"
    printf '%-14s %s\n' "bbduk"     "$(bbduk.sh --version 2>&1 | grep -i version | head -2 | tr '\n' ' ')"
    printf '%-14s %s\n' "art"       "$(art_illumina 2>&1 | grep -i 'Version' | head -1)"
    echo
    echo "# Not installed in this environment (recorded as unavailable):"
    for t in hostile kneaddata bmtagger deconseq.pl metaspades.py metaquast.py kraken2 checkm2; do
        command -v "$t" >/dev/null 2>&1 || echo "  $t  NOT INSTALLED"
    done
} > "$OUT/versions.txt"
cat "$OUT/versions.txt"

echo
echo "=== conda_explicit.txt ==="
conda list --explicit > "$OUT/conda_explicit.txt" 2>&1
wc -l < "$OUT/conda_explicit.txt"

echo
echo "=== pytest ==="
python -m pytest tests/ -v -rs 2>&1 | tail -22
