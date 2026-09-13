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
            # D19: bioconda's Trimmomatic wrapper hardcodes -Xmx1g, too small
            # for ~2,000,000-pair libraries -- every run failed identically
            # with java.lang.OutOfMemoryError. KneadData's own --max-memory
            # does not help (it is honoured only on the `java -jar` path, and
            # this build calls the wrapper executable instead). The wrapper
            # drops its hardcoded default whenever _JAVA_OPTIONS is already
            # set, so shim the entry point rather than patch the package.
            # Idempotent: skip if the shim is already installed.
            KDBIN="$(dirname "$(command -v kneaddata)")"
            if [ -x "$KDBIN/kneaddata" ] && [ ! -e "$KDBIN/kneaddata-real" ]; then
                mv "$KDBIN/kneaddata" "$KDBIN/kneaddata-real"
                cat > "$KDBIN/kneaddata" <<'SHIM'
#!/usr/bin/env bash
# See benchmark/run/DEVIATIONS.md D19. Installed by install_comparators.sh.
export _JAVA_OPTIONS="-Xmx8g"
exec "$(dirname "$0")/kneaddata-real" "$@"
SHIM
                chmod +x "$KDBIN/kneaddata"
                say "  kneaddata: installed the -Xmx8g heap shim (D19)"
            else
                say "  kneaddata: heap shim already present or binary layout unexpected, left alone"
            fi
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
            #
            # python<3.12 is required, not preferred: QUAST 5.3.0 imports
            # distutils (quast_libs/qconfig.py), which was removed from the
            # standard library in Python 3.12. Left unpinned the solve picks
            # 3.13 and metaquast.py dies at import with ModuleNotFoundError,
            # which would surface only once E9 tried to score an assembly.
            create_env megahit megahit quast "python<3.12" \
                || { say "megahit install FAILED"; continue; }
            conda activate megahit
            { megahit --version; metaquast.py --version 2>&1 | head -2; } \
                > "$RECORD/megahit_version.txt" 2>&1
            say "megahit -> $(head -1 "$RECORD/megahit_version.txt")"
            conda deactivate
            ;;
        sra)
            # E4 panel download. pigz alongside, because fasterq-dump writes
            # uncompressed and 30 libraries of plain FASTQ is wasteful on disk.
            create_env sra sra-tools pigz || { say "sra install FAILED"; continue; }
            conda activate sra
            { fasterq-dump --version 2>&1 | head -3
              prefetch --version 2>&1 | head -3; } > "$RECORD/sra_version.txt" 2>&1
            say "sra-tools -> $(grep -m1 -i 'version' "$RECORD/sra_version.txt" || echo '?')"
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
