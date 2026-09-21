#!/usr/bin/env bash
# Run every remaining experiment with ONE command.
#
#     bash benchmark/scripts/run_remaining.sh
#
#   R1  clean timing run        5 tools x 12 libraries x 3 replicates = 180 runs,
#                               swap-free, Hostile's index proven beforehand
#                               (closes D17, D18, D21)
#   R2  metaSPAdes downstream   3 methods x 6 libraries x 2 replicates + MetaQUAST
#                               (closes D4)
#   R3  CheckM2                 on the metaSPAdes assemblies (contigs >= 1 kb)
#                               (closes D6)
#   R4  Kraken2 full Standard   18 classifications; the ~72 GB database downloads
#                               in the background while R2 runs (closes D5)
#   R5  extra mismatch donors   Kinh, Mende, Colombian; all five tools scored
#
# Order: R1 alone first (it is a timing measurement, so nothing else may run
# beside it), then the big downloads start in the background, then R2 -> R3 ->
# R4, then R5 alone (also timed).
#
# Safe to interrupt and re-run: every stage skips finished work, and a stage is
# only marked done when it really completed. A stage that fails does not stop
# the others; the summary at the end says what happened.
#
# Options:
#     --only R1,R2       run just these
#     --skip R4,R5       run everything except these
#     --dry-run          print what would run and what each needs, then stop
#
# Environment (all optional):
#     THREADS                 threads per run in the TIMED stages R1/R5 (default 8)
#     ASM_THREADS             threads for R2/R3/R4 (default min(nproc, 32))
#     SKIP_HOSTILE_DEFAULT=1  leave hostile_default out (see r_common.sh)
#     HOSTILE_INDEX_TAR=path  a local copy of Hostile's human-t2t-hla.tar
#     R5_FRACTIONS            default "0.10 0.20" (six libraries); add 0.01 for nine
#     SPADES_MEM              GB handed to metaSPAdes (default min(120, available-6))
#
# What it produces (all under ~/hostsweep/out) and how to send it back:
# a results bundle is built at the end (collect_results.sh); it prints the
# file name to copy.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$HOME/hostsweep"
OUT="$ROOT/out"
LOGS="$ROOT/logs"
mkdir -p "$OUT" "$LOGS"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
LOGFILE="$LOGS/remaining_$STAMP.log"

ONLY=""; SKIP=""; DRY=0
while [ $# -gt 0 ]; do
    case "$1" in
        --only) ONLY="$2"; shift 2 ;;
        --skip) SKIP="$2"; shift 2 ;;
        --dry-run) DRY=1; shift ;;
        -h|--help) sed -n '2,45p' "$0"; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done
selected() {   # selected R1
    local s="$1"
    if [ -n "$ONLY" ]; then echo ",$ONLY," | grep -qi ",$s,"; return; fi
    if [ -n "$SKIP" ] && echo ",$SKIP," | grep -qi ",$s,"; then return 1; fi
    return 0
}

say() { echo "[REMAINING $(date -u +%FT%TZ)] $*"; }
fail() { say "STOP: $*"; exit 1; }

# ---------------------------------------------------------------- preflight
[ "$(uname -s)" = Linux ] || fail "not a Linux shell (uname says '$(uname -s)'). On Windows open the Ubuntu (WSL2) app, not Git Bash."
command -v flock >/dev/null 2>&1 || fail "flock missing: this is not a normal Linux shell"
[ -x /usr/bin/time ] || fail "/usr/bin/time missing (sudo apt-get install time); peak memory cannot be recorded without it"
[ -f "$ROOT/miniforge3/etc/profile.d/conda.sh" ] || fail "conda not set up under $ROOT (run benchmark/scripts/bootstrap_new_machine.sh first)"

exec 5>"$OUT/.remaining.lock"
flock -n 5 || fail "another run_remaining.sh is already running (lock: $OUT/.remaining.lock)"

exec > >(tee -a "$LOGFILE") 2>&1

NPROC="$(nproc)"
export THREADS="${THREADS:-8}"
export ASM_THREADS="${ASM_THREADS:-$(( NPROC < 32 ? NPROC : 32 ))}"
MEM_GB=$(( $(awk '/MemTotal/ {print $2}' /proc/meminfo) / 1048576 ))
AVAIL_GB=$(( $(awk '/MemAvailable/ {print $2}' /proc/meminfo) / 1048576 ))
FREE_GB="$(df -Pk "$ROOT" | awk 'NR==2 {print int($4/1048576)}')"

say "log: $LOGFILE"
say "machine: $NPROC CPUs, ${MEM_GB} GB RAM (${AVAIL_GB} GB available), ${FREE_GB} GB free on $(df -P "$ROOT" | awk 'NR==2{print $1}')"
say "threads: timed stages $THREADS, assembly/classification stages $ASM_THREADS"

# Refresh the checkout so the scripts run are the ones on GitHub.
REPO="$ROOT/HostSweep"
if [ -d "$REPO/.git" ]; then
    git -C "$REPO" -c http.version=HTTP/1.1 pull --ff-only -q origin main 2>/dev/null \
        && say "repo at $(git -C "$REPO" rev-parse --short HEAD)" \
        || say "WARNING: could not update the checkout; running what is on disk ($(git -C "$REPO" rev-parse --short HEAD 2>/dev/null))"
fi
SCRIPTS="$REPO/benchmark/scripts"
[ -f "$SCRIPTS/r1_timing_run.sh" ] || fail "$SCRIPTS/r1_timing_run.sh not found: the checkout is older than this script"

E9_LIBS=(SYN-CHM13-01 SYN-CHM13-05 SYN-NEU-03 SRR40486826 ERR15898346 SRR31641567)
E9_CLEAN="$OUT/e9_cleaned"
STATE="$OUT/.remaining_state"; mkdir -p "$STATE"
declare -A RESULT

# ------------------------------------------------------------- dry-run plan
if [ "$DRY" = 1 ]; then
    say "DRY RUN -- nothing will be executed"
    for s in R1 R2 R3 R4 R5; do selected "$s" && say "  would run $s$( [ -f "$STATE/$s.done" ] && echo '  (already marked done; would be skipped)')"; done
    selected R4 && say "  R4 needs ~190 GB free for the database; have ${FREE_GB} GB"
    selected R2 && say "  R2 wants ~120 GB RAM for the gut library; have ${AVAIL_GB} GB available"
    exit 0
fi

# -------------------------------------------------------- toolchain present?
# shellcheck disable=SC1091
. "$ROOT/miniforge3/etc/profile.d/conda.sh"
env_present() { conda env list | awk '{print $1}' | grep -qx "$1"; }

ensure_toolchain() {
    local missing=0
    for e in hostsweep hostile kneaddata bmtagger megahit kraken2; do env_present "$e" || { say "  conda env '$e' missing"; missing=1; }; done
    ls "$ROOT/bench/synthetic"/*_R1.fastq.gz >/dev/null 2>&1 || { say "  synthetic panel missing"; missing=1; }
    if [ "$missing" = 1 ]; then
        say "toolchain incomplete: running the bootstrap stages that build it (1-6)"
        bash "$SCRIPTS/bootstrap_new_machine.sh" --stop-after 6 || fail "bootstrap stages 1-6 failed"
    fi
    if [ ! -s "$ROOT/bmtagger_index/human.bitmask" ] || [ ! -s "$ROOT/bmtagger_index/human.seqdb.nsq" ]; then
        say "BMTagger index missing: building it (once)"
        T2T="$ROOT/miniforge3/envs/hostsweep/share/hostsweep/databases/standard/human_T2T.fasta"
        [ -s "$T2T" ] || fail "T2T FASTA missing at $T2T"
        conda activate bmtagger && bash "$SCRIPTS/07_build_bmtagger_index.sh" "$T2T" "$ROOT/bmtagger_index"; conda deactivate
    fi
}
say "checking the toolchain"
ensure_toolchain

# E9 inputs (cleaned reads for the 6 libraries x 3 methods) -- reused, not redone.
ensure_e9_inputs() {
    local need=0 lib m
    for lib in "${E9_LIBS[@]}"; do for m in hostsweep kneaddata hostile; do
        [ -s "$E9_CLEAN/$lib/${m}_R1.fastq.gz" ] || need=1
    done; done
    if [ "$need" = 1 ]; then
        say "cleaned E9 reads incomplete: running chain_e9.sh to produce them (idempotent)"
        bash "$SCRIPTS/chain_e9.sh" || say "  chain_e9.sh returned non-zero"
    fi
    for lib in "${E9_LIBS[@]}"; do for m in hostsweep kneaddata hostile; do
        [ -s "$E9_CLEAN/$lib/${m}_R1.fastq.gz" ] || { say "  still missing: $lib / $m"; return 1; }
    done; done
    return 0
}

# ---------------------------------------------------------- stage machinery
run_stage() {   # run_stage <R-id> <description> <command...>
    local id="$1" desc="$2"; shift 2
    if ! selected "$id"; then RESULT[$id]="not selected"; return 0; fi
    if [ -f "$STATE/$id.done" ]; then RESULT[$id]="already done"; say "$id: already done ($desc)"; return 0; fi
    say "================================================================"
    say "$id: $desc"
    say "================================================================"
    local t0; t0=$(date +%s)
    if "$@"; then
        RESULT[$id]="done in $(( ($(date +%s) - t0) / 60 )) min"
        touch "$STATE/$id.done"
    else
        RESULT[$id]="FAILED after $(( ($(date +%s) - t0) / 60 )) min (re-run to resume)"
        say "$id FAILED; continuing with the other stages"
    fi
}

start_bg() {   # start_bg <name> <command...>   (logs to its own file)
    local name="$1"; shift
    if [ -f "$OUT/.bg_$name.pid" ] && kill -0 "$(cat "$OUT/.bg_$name.pid")" 2>/dev/null; then
        say "background job '$name' already running (pid $(cat "$OUT/.bg_$name.pid"))"; return 0
    fi
    nohup "$@" > "$LOGS/bg_$name.log" 2>&1 &
    echo $! > "$OUT/.bg_$name.pid"
    say "started background job '$name' (pid $!, log $LOGS/bg_$name.log)"
}
wait_bg() {   # wait_bg <name>  -> waits for the job, if there is one
    local name="$1" pid
    [ -f "$OUT/.bg_$name.pid" ] || return 0
    pid="$(cat "$OUT/.bg_$name.pid")"
    if kill -0 "$pid" 2>/dev/null; then
        say "waiting for background job '$name' (pid $pid); progress: tail -f $LOGS/bg_$name.log"
        while kill -0 "$pid" 2>/dev/null; do sleep 60; done
    fi
    rm -f "$OUT/.bg_$name.pid"
}

k2_ready()  { [ -s "$ROOT/k2_standard_full/hash.k2d" ] && [ -s "$ROOT/k2_standard_full/taxo.k2d" ]; }
cm2_ready() { [ -n "$(find "$ROOT/checkm2_db" -name '*.dmnd' 2>/dev/null | head -1)" ]; }

# ---------------------------------------------------------------------- R1
stage_r1() {
    bash "$SCRIPTS/r1_timing_run.sh" || return 1
    # complete = every (library, tool, run) has a scored row, none FAILED
    local ntools=5; [ "${SKIP_HOSTILE_DEFAULT:-0}" = 1 ] && ntools=4
    local want=$(( 12 * ntools * 3 )) have
    have="$(( $(wc -l < "$OUT/r1/per_library.csv" 2>/dev/null || echo 1) - 1 ))"
    if [ "$have" -ne "$want" ] || grep -q ',FAILED,FAILED,' "$OUT/r1/per_library.csv"; then
        say "R1 incomplete: $have rows of $want expected, or FAILED rows present (see $OUT/r1/run_details.csv)"
        return 1
    fi
}
run_stage R1 "clean timing run (5 tools x 12 libraries x 3 runs), nothing else running" stage_r1

# Downloads start only now, so they cannot disturb R1's timings.
if selected R4 && [ ! -f "$STATE/R4.done" ] && ! k2_ready; then
    if [ "$FREE_GB" -ge 190 ]; then
        say "starting the Kraken2 Standard download in the background (~72 GB, resumable)"
        start_bg k2db env K2_FLAVOR=standard bash "$SCRIPTS/06_fetch_kraken2_db.sh"
    else
        say "R4: only ${FREE_GB} GB free, needs ~190 GB. Not downloading; R4 will be skipped."
    fi
fi
if selected R3 && [ ! -f "$STATE/R3.done" ] && ! cm2_ready; then
    start_bg checkm2db bash "$SCRIPTS/08_fetch_checkm2_db.sh"
fi

# ---------------------------------------------------------------------- R2
stage_r2() {
    ensure_e9_inputs || return 1
    env_present spades || bash "$SCRIPTS/install_comparators.sh" spades
    env_present spades || { say "spades env could not be installed"; return 1; }
    THREADS="$ASM_THREADS" bash "$SCRIPTS/run_metaspades_e9.sh" "$E9_CLEAN" "$OUT/r2_results" "$OUT/e9_refs" "${E9_LIBS[@]}"
    mkdir -p "$OUT/r2"
    cp -f "$OUT/r2_results"/downstream_metaspades*.csv "$OUT/r2_results/inputs_sha256.txt" "$OUT/r2/" 2>/dev/null
    # complete = every pair has a row for replicate 1 that is not FAILED
    [ -s "$OUT/r2/downstream_metaspades.csv" ] || return 1
    ! grep -q ',FAILED,' "$OUT/r2/downstream_metaspades.csv"
}
run_stage R2 "metaSPAdes on 18 pairs x 2 replicates, then MetaQUAST" stage_r2

# ---------------------------------------------------------------------- R3
stage_r3() {
    wait_bg checkm2db
    cm2_ready || bash "$SCRIPTS/08_fetch_checkm2_db.sh" || return 1
    [ -s "$OUT/r2_results/downstream_metaspades.csv" ] || { say "no metaSPAdes assemblies to score (R2 first)"; return 1; }
    mkdir -p "$OUT/r3"
    ASSEMBLER=metaspades MIN_CONTIG=1000 REP=1 THREADS="$ASM_THREADS" \
        bash "$SCRIPTS/run_checkm2.sh" "$OUT/r2_results" "$OUT/r3/checkm2_metaspades.csv" "$ROOT/checkm2_db"
    [ -s "$OUT/r3/checkm2_metaspades.csv" ] && ! grep -q ',FAILED,' "$OUT/r3/checkm2_metaspades.csv"
}
run_stage R3 "CheckM2 on the metaSPAdes assemblies (contigs >= 1 kb)" stage_r3

# ---------------------------------------------------------------------- R4
stage_r4() {
    wait_bg k2db
    k2_ready || K2_FLAVOR=standard bash "$SCRIPTS/06_fetch_kraken2_db.sh" || return 1
    k2_ready || return 1
    ensure_e9_inputs || return 1
    mkdir -p "$OUT/r4"
    K2DB="$ROOT/k2_standard_full" THREADS="$ASM_THREADS" \
        bash "$SCRIPTS/run_kraken2_standard.sh" "$E9_CLEAN" "$OUT/r4" "${E9_LIBS[@]}"
    [ -s "$OUT/r4/kraken2_human_standard.csv" ] && ! grep -q ',FAILED,' "$OUT/r4/kraken2_human_standard.csv"
}
run_stage R4 "Kraken2 full Standard on the 18 E9 pairs" stage_r4

# ---------------------------------------------------------------------- R5
stage_r5() {
    wait_bg k2db; wait_bg checkm2db      # nothing may be running beside a timed stage
    bash "$SCRIPTS/r5_extra_donors.sh" || return 1
    [ "$(( $(wc -l < "$OUT/r5/per_library.csv" 2>/dev/null || echo 1) - 1 ))" -ge 1 ] \
        && ! grep -q ',FAILED,FAILED,' "$OUT/r5/per_library.csv"
}
run_stage R5 "extra mismatch donors, all tools scored (timed; runs alone)" stage_r5

# ------------------------------------------------------------------- bundle
say "================================================================"
say "building the results bundle"
bash "$SCRIPTS/collect_results.sh" || say "collect_results.sh failed (results are still under $OUT)"

say "================================================================"
say "SUMMARY"
for s in R1 R2 R3 R4 R5; do say "  $s: ${RESULT[$s]:-not run}"; done
say "log: $LOGFILE"
BAD=0; for s in R1 R2 R3 R4 R5; do case "${RESULT[$s]:-}" in FAILED*) BAD=1 ;; esac; done
[ "$BAD" = 0 ] && say "ALL SELECTED STAGES COMPLETE" || say "some stages failed: re-run the same command to resume them"
exit "$BAD"
