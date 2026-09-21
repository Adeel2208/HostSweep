#!/usr/bin/env bash
# Shared setup for the remaining-experiment scripts (R1-R5). Source it:
#     . "$(dirname "$0")/r_common.sh"
#
# Defines paths, the tool environment every timing run needs, the Hostile index
# check, and the warm-up pass. Defines functions only; it does not run anything.

ROOT="${ROOT:-$HOME/hostsweep}"
REPO="${REPO:-$ROOT/HostSweep}"
OUT="${OUT:-$ROOT/out}"
BENCH="${BENCH:-$ROOT/bench}"
SYN="${SYN:-$BENCH/synthetic}"
SCRIPTS="${SCRIPTS:-$REPO/benchmark/scripts}"
CONDA_SH="${CONDA_SH:-$ROOT/miniforge3/etc/profile.d/conda.sh}"
LOGS="$ROOT/logs"
mkdir -p "$OUT" "$LOGS"

# Timing runs use one fixed thread count for every tool. 8 matches the earlier
# E3 runs, so the accuracy runs and the timing runs are the same configuration.
export THREADS="${THREADS:-8}"
export HOSTSWEEP_BBDUK_MEM="${HOSTSWEEP_BBDUK_MEM:-3g}"
export INDEX=standard
export BT2_INDEX="$ROOT/miniforge3/envs/hostsweep/share/hostsweep/databases/standard/human_bt2"
BMT_DIR="$ROOT/bmtagger_index"

# The 12 original synthetic libraries. R1 is defined on exactly these, so
# libraries added later (R5) never leak into it.
ORIGINAL_LIBS=(SYN-CHM13-01 SYN-CHM13-02 SYN-CHM13-03 SYN-CHM13-04 SYN-CHM13-05
               SYN-CHM13-06 SYN-CHM13-07 SYN-CHM13-08 SYN-CHM13-09
               SYN-IND-01 SYN-NEU-02 SYN-NEU-03)

rsay() { echo "[$(date -u +%H:%M:%S)] $*"; }

# shellcheck disable=SC1090
[ -f "$CONDA_SH" ] && . "$CONDA_SH"

# tools_for_timing -> sets TIMING_TOOLS and exports the BMTagger index paths.
tools_for_timing() {
    TIMING_TOOLS=(hostsweep hostile_default hostile_matched kneaddata)
    if [ "${SKIP_HOSTILE_DEFAULT:-0}" = 1 ]; then
        TIMING_TOOLS=(hostsweep hostile_matched kneaddata)
        rsay "SKIP_HOSTILE_DEFAULT=1: hostile_default is left out (its earlier-session results stand, D21)"
    fi
    if [ -s "$BMT_DIR/human.bitmask" ] && [ -s "$BMT_DIR/human.srprism.idx" ] && [ -s "$BMT_DIR/human.seqdb.nsq" ]; then
        export BMTAGGER_BITMASK="$BMT_DIR/human.bitmask"
        export BMTAGGER_SRPRISM="$BMT_DIR/human.srprism"
        export BMTAGGER_SEQDB="$BMT_DIR/human.seqdb"
        TIMING_TOOLS+=(bmtagger)
    else
        rsay "ERROR: BMTagger index missing under $BMT_DIR; run: bash $SCRIPTS/07_build_bmtagger_index.sh"
        return 1
    fi
    return 0
}

# Build a directory of symlinks to a chosen set of libraries, so run_e3.sh
# (which globs *_R1.fastq.gz) sees exactly those and no others.
link_libs() {   # link_libs <target_dir> <source_dir> <lib> ...
    local dir="$1" src="$2"; shift 2
    rm -rf "$dir"; mkdir -p "$dir"
    local lib
    for lib in "$@"; do
        for f in "$src/${lib}_R1.fastq.gz" "$src/${lib}_R2.fastq.gz"; do
            [ -s "$f" ] || { rsay "missing $f"; return 1; }
            ln -s "$f" "$dir/$(basename "$f")"
        done
    done
}

# --- Hostile's default index, obtained BEFORE any timing starts ------------
# hostile_default failed 12 of 12 in an earlier session because Hostile tried
# to download its index on first use and the download failed (D21); the first
# failure also burned ~350 minutes retrying. So: prove the index works with a
# tiny real run, and if it does not, get it here where a failure is cheap and
# visible instead of inside a timed run.
HOSTILE_INDEX_URL="https://objectstorage.uk-london-1.oraclecloud.com/n/lrbvkel2wjot/b/human-genome-bucket/o/human-t2t-hla.tar"

hostile_probe() {   # returns 0 if `hostile clean` (default index) works offline-ready
    local lib1 lib2 p="$OUT/.hostile_probe"
    lib1="$(ls "$SYN"/*_R1.fastq.gz 2>/dev/null | head -1)"
    [ -n "$lib1" ] || { rsay "no synthetic library to probe with"; return 1; }
    lib2="${lib1%_R1.fastq.gz}_R2.fastq.gz"
    rm -rf "$p"; mkdir -p "$p"
    { zcat "$lib1" | head -n 4000 | gzip > "$p/a_1.fastq.gz"; } 2>/dev/null || true
    { zcat "$lib2" | head -n 4000 | gzip > "$p/a_2.fastq.gz"; } 2>/dev/null || true
    conda activate hostile 2>/dev/null || return 1
    timeout 900 hostile clean --fastq1 "$p/a_1.fastq.gz" --fastq2 "$p/a_2.fastq.gz" \
        --threads 2 --output "$p/out" > "$p/stdout" 2> "$p/stderr"
    local rc=$?
    conda deactivate
    return $rc
}

ensure_hostile_index() {
    rsay "checking Hostile's default index (a tiny real run, not a guess)"
    if hostile_probe; then rsay "  Hostile default index works"; return 0; fi
    rsay "  it does not work yet: $(tail -n 2 "$OUT/.hostile_probe/stderr" 2>/dev/null | tr '\n' ' ' | cut -c1-200)"

    local dl="$ROOT/dl" tar="${HOSTILE_INDEX_TAR:-$ROOT/dl/human-t2t-hla.tar}"
    mkdir -p "$dl"
    if [ ! -s "$tar" ] || [ -f "$tar.aria2" ]; then
        rsay "  downloading the index (3.9 GB, resumable): $HOSTILE_INDEX_URL"
        if command -v aria2c >/dev/null 2>&1; then
            aria2c -x4 -s4 -k4M -c --file-allocation=none --auto-file-renaming=false \
                --max-tries=20 --retry-wait=15 --timeout=60 \
                -d "$(dirname "$tar")" -o "$(basename "$tar")" "$HOSTILE_INDEX_URL" \
                || rsay "  download did not complete (re-run to resume)"
        else
            curl -fL --retry 8 --retry-all-errors -C - -o "$tar" "$HOSTILE_INDEX_URL" \
                || rsay "  download did not complete (re-run to resume)"
        fi
    fi
    if [ -s "$tar" ] && [ ! -f "$tar.aria2" ]; then
        conda activate hostile 2>/dev/null
        local cache
        cache="$(python3 -c 'from hostile.util import CACHE_DIR; print(CACHE_DIR)' 2>/dev/null)"
        conda deactivate
        [ -n "$cache" ] || cache="${XDG_DATA_HOME:-$HOME/.local/share}/hostile"
        rsay "  unpacking into Hostile's cache: $cache"
        mkdir -p "$cache" && tar -xf "$tar" -C "$cache" || rsay "  unpack failed"
        if hostile_probe; then rsay "  Hostile default index works now"; return 0; fi
    fi
    rsay "ERROR: Hostile's default index is not usable. Options:"
    rsay "  * put a copy of human-t2t-hla.tar on this machine and run with"
    rsay "      HOSTILE_INDEX_TAR=/path/to/human-t2t-hla.tar"
    rsay "    (it is 3.9 GB: $HOSTILE_INDEX_URL)"
    rsay "  * or run with SKIP_HOSTILE_DEFAULT=1 to leave hostile_default out; its"
    rsay "    earlier-session results then stand and D21 stays open"
    return 1
}

# Warm-up: one discarded pass of every tool on the smallest library, so the first
# real run of each tool does not also pay to read a multi-GB index from a cold
# disk cache. The warm-up results are kept for the record but never aggregated.
warmup_tools() {   # warmup_tools <syn_dir> <lib> <tool> ...
    local synd="$1" lib="$2"; shift 2
    local w="$OUT/.warm_syn"
    link_libs "$w" "$synd" "$lib" || return 1
    rm -rf "$OUT/r_warmup"
    rsay "warm-up pass (discarded): $* on $lib"
    KEEP_CLEANED=0 bash "$SCRIPTS/run_e3.sh" "$w" "$OUT/r_warmup" 1 "$@" > "$LOGS/warmup.log" 2>&1 \
        || rsay "  warm-up returned non-zero (see $LOGS/warmup.log); continuing"
}

# Swap state, recorded so the timing claims can cite it.
record_swap_state() {   # record_swap_state <file>
    {
        echo "date: $(date -u +%FT%TZ)"
        echo "SwapTotal_kB: $(awk '/SwapTotal/ {print $2}' /proc/meminfo)"
        echo "SwapFree_kB:  $(awk '/SwapFree/ {print $2}' /proc/meminfo)"
        echo "MemTotal_kB:  $(awk '/MemTotal/ {print $2}' /proc/meminfo)"
        echo "nproc: $(nproc)"
        echo "threads_per_run: $THREADS"
        echo "cpu: $(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | sed 's/^ //')"
        echo "swapon:"; swapon --show 2>/dev/null | sed 's/^/  /'
    } > "$1"
}
