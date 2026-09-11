#!/usr/bin/env bash
# Single entry point for moving the HostSweep benchmark to a new machine and
# finishing the experiments that were still running when this one was set up.
#
# Read benchmark/NEW_MACHINE.md before running this. It covers the Windows-side
# steps (WSL2, .wslconfig) that have to happen before this script can run at
# all. This script itself only assumes it is being run as a normal user inside
# a WSL2 Ubuntu shell (or any Linux host with the same amount of free RAM).
#
# What it does, in order, and why that order:
#   0. preflight             print RAM/CPU/disk, refuse to continue if the
#                             machine cannot hold one HostSweep run
#   1. toolchain              conda env, editable install, unit tests
#                             (wsl_setup.sh)
#   2. reference index        build + verify the T2T-CHM13v2.0 index is a
#                             single minimap2 batch (check_mm2_index.sh) --
#                             a split index silently understates host content
#   3. comparator tools       Hostile, KneadData, BMTagger, MEGAHIT+QUAST,
#                             Kraken2, sra-tools, each in its own conda env
#                             (install_comparators.sh)
#   4. Kraken2 database       the same Standard-8 build used on the first
#                             machine (06_fetch_kraken2_db.sh) -- NOT a larger
#                             one, so residual-human figures from both
#                             machines stay comparable (D5)
#   5. mismatch-arm sources   HPRC haplotype assemblies + provenance check
#                             (wsl_run.sh han1)
#   6. synthetic panel        12 controlled-truth libraries, same ART seeds
#                             as before (wsl_run.sh e2)
#   7. CROSS-MACHINE CHECK    rebuild SYN-CHM13-01 and diff its sensitivity
#                             and FPR against the values already committed in
#                             benchmark/run/per_library.csv. Every number this
#                             script produces after this point is worthless if
#                             this check fails, so it stops here rather than
#                             continuing on a machine that measures
#                             differently.
#   8. real-library downloads all 30 SRA accessions (wsl_run.sh e4dl)
#   9. everything left        finishes E9, runs the comparator benchmark on
#                             the synthetic panel, scores the remaining real
#                             libraries, aggregates, audits (chain_all.sh)
#
# Every stage is idempotent -- re-running this script after Ctrl-C, a reboot,
# or a lost connection resumes exactly where it stopped and recomputes
# nothing. That property is exercised by every sub-script it calls, not
# something this wrapper adds.
#
# Usage:
#     bash bootstrap_new_machine.sh                 # run everything
#     bash bootstrap_new_machine.sh --from-stage 8   # skip 1-7 (already done)
#     bash bootstrap_new_machine.sh --stop-after 6   # stop after stage 6
#
# A stage number with no flag runs everything from stage 1 through the end.

set -uo pipefail

ROOT="$HOME/hostsweep"
REPO="$ROOT/HostSweep"
OUT="$ROOT/out"
BENCH="$ROOT/bench"
LOGS="$ROOT/logs"
REMOTE="https://github.com/Adeel2208/HostSweep.git"

mkdir -p "$ROOT" "$LOGS"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
LOGFILE="$LOGS/bootstrap_${STAMP}.log"

say()  { echo "[bootstrap $(date -u +%FT%TZ)] $*" | tee -a "$LOGFILE"; }
fail() { echo "[bootstrap FAILED] $*" | tee -a "$LOGFILE" >&2; exit 1; }

FROM=1
STOP=99
while [ $# -gt 0 ]; do
    case "$1" in
        --from-stage) FROM="$2"; shift 2 ;;
        --stop-after) STOP="$2"; shift 2 ;;
        *) fail "unknown argument: $1" ;;
    esac
done
run_stage() { [ "$1" -ge "$FROM" ] && [ "$1" -le "$STOP" ]; }

exec 8>"$ROOT/.bootstrap.lock"
if ! flock -n 8; then fail "another bootstrap_new_machine.sh is already running on this host"; fi

say "=========================================================="
say "HostSweep benchmark bootstrap starting on $(hostname), log: $LOGFILE"
say "=========================================================="

# --- stage 0: preflight -------------------------------------------------
if run_stage 0 || true; then   # always shown, never skipped
    say "STAGE 0  preflight"
    RAM_GB=$(free -g | awk '/^Mem:/{print $2}')
    CPU_N=$(nproc)
    DISK_GB=$(df -BG --output=avail "$HOME" 2>/dev/null | tail -1 | tr -dc '0-9')
    say "  RAM available to this shell : ${RAM_GB} GB"
    say "  CPU threads                 : ${CPU_N}"
    say "  free disk at \$HOME           : ${DISK_GB} GB"
    [ "${RAM_GB:-0}" -ge 10 ] || fail "under 10 GB RAM visible; every HostSweep-class run needs ~11 GB peak. If this is WSL, raise memory= in .wslconfig on the Windows side and run 'wsl --shutdown', then retry."
    [ "${DISK_GB:-0}" -ge 120 ] || say "  WARNING: under 120 GB free. The full benchmark (index + synthetic panel + 30 real libraries + comparator work trees) has used ~135 GB on the reference machine."
    export THREADS="${THREADS:-$(( CPU_N > 12 ? 12 : CPU_N ))}"
    say "  THREADS set to ${THREADS}"
fi

# --- stage 1: toolchain --------------------------------------------------
if run_stage 1; then
    say "STAGE 1/9  toolchain setup (conda env, repo, editable install, tests)"
    # wsl_setup.sh clones the repo itself if $REPO does not exist yet, so this
    # is also how the checkout gets here in the first place.
    if [ ! -f "$REPO/benchmark/scripts/wsl_setup.sh" ]; then
        say "  repo not present yet at $REPO; cloning directly so wsl_setup.sh exists to run"
        git clone --quiet "$REMOTE" "$REPO" || fail "initial clone"
    fi
    bash "$REPO/benchmark/scripts/wsl_setup.sh" 2>&1 | tee -a "$LOGFILE" \
        || fail "wsl_setup.sh (see $LOGFILE)"
fi

# shellcheck disable=SC1091
. "$ROOT/miniforge3/etc/profile.d/conda.sh"
conda activate hostsweep || fail "cannot activate hostsweep env"
SCRIPTS="$REPO/benchmark/scripts"

# --- stage 2: reference index --------------------------------------------
if run_stage 2; then
    say "STAGE 2/9  T2T-CHM13v2.0 index (auto-downloads + builds on first use)"
    python3 -c "
from hostsweep.database import DatabaseManager
import logging
logging.basicConfig(level=logging.INFO)
DatabaseManager().build_standard_index(threads=${THREADS})
" 2>&1 | tee -a "$LOGFILE" || fail "index build"
    say "  verifying the index is a single minimap2 batch"
    bash "$SCRIPTS/check_mm2_index.sh" 2>&1 | tee -a "$LOGFILE" \
        | grep -q "RESULT: PASS" || fail "minimap2 index is split into multiple batches -- host content would be understated. See check_mm2_index.sh output above."
fi

# --- stage 3: comparator tools --------------------------------------------
if run_stage 3; then
    say "STAGE 3/9  comparator conda environments"
    bash "$SCRIPTS/install_comparators.sh" sra hostile kneaddata bmtagger megahit kraken2 \
        2>&1 | tee -a "$LOGFILE" || say "  some comparator installs failed; see $LOGFILE -- continuing, run_e3.sh probes tool availability per environment"
fi

# --- stage 4: Kraken2 database ---------------------------------------------
if run_stage 4; then
    say "STAGE 4/9  Kraken2 Standard-8 database (same build as the first machine, D5)"
    bash "$SCRIPTS/06_fetch_kraken2_db.sh" 20250402 "$ROOT/k2_standard_08gb" \
        2>&1 | tee -a "$LOGFILE" || fail "Kraken2 DB fetch"
fi

# --- stage 5: mismatch-arm human sources -----------------------------------
if run_stage 5; then
    say "STAGE 5/9  HPRC mismatch-arm assemblies + provenance check (Han1 excluded)"
    bash "$SCRIPTS/wsl_run.sh" han1 2>&1 | tee -a "$LOGFILE" || fail "han1 stage"
fi

# --- stage 6: synthetic panel ------------------------------------------------
if run_stage 6; then
    say "STAGE 6/9  synthetic controlled-truth panel (12 libraries)"
    bash "$SCRIPTS/wsl_run.sh" e2 2>&1 | tee -a "$LOGFILE" || fail "e2 stage"
    N=$(ls "$BENCH/synthetic"/*_manifest.json 2>/dev/null | wc -l)
    [ "$N" -eq 12 ] || fail "only $N/12 synthetic libraries built; check $LOGFILE"
fi

# --- stage 7: cross-machine determinism check --------------------------------
if run_stage 7; then
    say "STAGE 7/9  cross-machine check: does this host measure the same accuracy?"
    CHK="$OUT/.crosscheck"
    rm -rf "$CHK"; mkdir -p "$CHK"
    bash "$SCRIPTS/run_e3.sh" "$BENCH/synthetic" "$CHK" 1 hostsweep \
        2>&1 | tee -a "$LOGFILE" || fail "cross-check run failed outright"
    JSON="$CHK/SYN-CHM13-01/metrics_hostsweep_run1.json"
    [ -s "$JSON" ] || fail "cross-check produced no metrics JSON at $JSON"
    python3 - "$JSON" "$REPO/benchmark/run/per_library.csv" <<'PYEOF' | tee -a "$LOGFILE"
import csv, json, sys
new = json.load(open(sys.argv[1]))
got_sens, got_fpr = new["sensitivity"], new["false_positive_rate"]
want_sens = want_fpr = None
with open(sys.argv[2], newline="") as fh:
    for row in csv.DictReader(fh):
        if row["library"] == "SYN-CHM13-01" and row["tool"] == "hostsweep":
            want_sens = float(row["sensitivity_pct"])
            want_fpr = float(row["fpr_pct"])
            break
if want_sens is None:
    print("CROSSCHECK: no reference row for SYN-CHM13-01/hostsweep in per_library.csv -- cannot compare")
    sys.exit(1)
print(f"CROSSCHECK this machine : sensitivity={got_sens}  fpr={got_fpr}")
print(f"CROSSCHECK reference    : sensitivity={want_sens}  fpr={want_fpr}")
if got_sens == want_sens and got_fpr == want_fpr:
    print("CROSSCHECK: PASS -- identical to the reference machine")
    sys.exit(0)
print("CROSSCHECK: MISMATCH -- this machine measures different accuracy for the")
print("same library. Do not merge its results with the existing CSVs. Stop and")
print("investigate a tool-version or environment difference (see environment.yml")
print("pinned versions) before running anything else.")
sys.exit(1)
PYEOF
    RC=$?
    rm -rf "$CHK"
    [ "$RC" -eq 0 ] || fail "cross-machine check did not pass (see above) -- stopping before any more results are produced on this host"
fi

# --- stage 8: real-library downloads ----------------------------------------
if run_stage 8; then
    say "STAGE 8/9  downloading the 30-accession real-library panel from SRA"
    bash "$SCRIPTS/wsl_run.sh" e4dl "$ROOT/e4_fastq" 2 \
        2>&1 | tee -a "$LOGFILE" || say "  some accessions failed; see $ROOT/e4_fastq/failures.tsv -- continuing with what downloaded"
    N=$(ls "$ROOT/e4_fastq"/*_1.fastq.gz 2>/dev/null | wc -l)
    say "  $N/30 real libraries present"
fi

# --- stage 9: everything that is still left ---------------------------------
if run_stage 9; then
    say "STAGE 9/9  finishing E9, the comparator benchmark, and E4 scoring"
    bash "$SCRIPTS/chain_all.sh" 2>&1 | tee -a "$LOGFILE" || say "  chain_all.sh reported a non-zero stage; see $LOGFILE -- it is resumable, re-run this script to continue"
fi

say "=========================================================="
say "bootstrap finished. Next:"
say "  bash $SCRIPTS/status.sh                       -- what ran, what's left"
say "  cat $OUT/AUDIT.md                             -- self-audit output"
say "  bash $SCRIPTS/package_results.sh $REPO         -- build the results bundle"
say "Copy the updated CSVs from \$HOME/hostsweep/out/*.csv into"
say "$REPO/benchmark/run/ before committing -- this script does not commit anything."
say "=========================================================="
