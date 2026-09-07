#!/usr/bin/env bash
# Install each comparator into its own conda environment.
#
# Separate environments because their dependency sets conflict; installing them
# together resolves to versions none of the tools was tested against.
#
# Idempotent: an environment that already exists is left alone.
#
# Every environment uses --override-channels. A pre-existing ~/.condarc on this
# host injects Anaconda's `defaults`, which stalled a solve past 14 minutes.
#
# Usage:  bash install_comparators.sh [tool ...]
#         default: hostile kneaddata bmtagger megahit kraken2
#
# DeconSeq is deliberately absent: it is not on bioconda and needs a manual
# install plus a hand-edited DeconSeqConfig.pm. It is attempted separately and
# dropped-with-reason if it will not run.

set -uo pipefail

CONDA_DIR="$HOME/hostsweep/miniforge3"
# shellcheck disable=SC1091
. "$CONDA_DIR/etc/profile.d/conda.sh"

RECORD="$HOME/hostsweep/record"
mkdir -p "$RECORD"

TOOLS=("$@")
[ ${#TOOLS[@]} -gt 0 ] || TOOLS=(hostile kneaddata bmtagger megahit kraken2)

say() { echo "[install $(date -u +%H:%M:%S)] $*"; }

have_env() { conda env list | awk '{print $1}' | grep -qx "$1"; }

# create_env <env name> <package...>
create_env() {
    local env="$1"; shift
    if have_env "$env"; then
        say "env '$env' already exists"
        return 0
    fi
    say "creating env '$env': $*"
    conda create -y -q -n "$env" --override-channels \
        -c conda-forge -c bioconda "$@" 2>&1 | tail -5
    return "${PIPESTATUS[0]}"
}

for tool in "${TOOLS[@]}"; do
    echo "============================================================"
    case "$tool" in
        hostile)
            create_env hostile hostile || { say "hostile install FAILED"; continue; }
            conda activate hostile
            V="$(hostile --version 2>&1 | tr -d '\r' | head -1)"
            say "hostile --version -> $V"
            echo "$V" > "$RECORD/hostile_version.txt"
            # A 1.x resolution means the environment resolved wrong and the
            # whole comparison would be invalid. Fail loudly rather than run.
            case "$V" in
                *2.*) say "OK: hostile is 2.x" ;;
                *)    say "FATAL: hostile is not 2.x (got '$V') -- comparison would be invalid"
                      echo "INVALID: expected 2.x, got $V" >> "$RECORD/hostile_version.txt" ;;
            esac
            conda deactivate
            ;;
        kneaddata)
            create_env kneaddata kneaddata || { say "kneaddata install FAILED"; continue; }
            conda activate kneaddata
            kneaddata --version > "$RECORD/kneaddata_version.txt" 2>&1
            say "kneaddata -> $(head -1 "$RECORD/kneaddata_version.txt")"
            conda deactivate
            ;;
        bmtagger)
            create_env bmtagger bmtagger srprism || { say "bmtagger install FAILED"; continue; }
            conda activate bmtagger
            { command -v bmtagger.sh; command -v bmtool; command -v srprism; } \
                > "$RECORD/bmtagger_version.txt" 2>&1
            say "bmtagger binaries: $(tr '\n' ' ' < "$RECORD/bmtagger_version.txt")"
            conda deactivate
            ;;
        megahit)
            # D4: MEGAHIT replaces metaSPAdes; 120 GB is not available here.
            create_env megahit megahit quast || { say "megahit install FAILED"; continue; }
            conda activate megahit
            { megahit --version; metaquast.py --version 2>&1 | head -2; } \
                > "$RECORD/megahit_version.txt" 2>&1
            say "megahit -> $(head -1 "$RECORD/megahit_version.txt")"
            conda deactivate
            ;;
        kraken2)
            # D5: Standard-8 capped database replaces Standard.
            create_env kraken2 kraken2 || { say "kraken2 install FAILED"; continue; }
            conda activate kraken2
            kraken2 --version > "$RECORD/kraken2_version.txt" 2>&1
            say "kraken2 -> $(head -1 "$RECORD/kraken2_version.txt")"
            conda deactivate
            ;;
        *)
            say "unknown tool: $tool" ;;
    esac
done

echo "============================================================"
say "environments now present:"
conda env list
