#!/usr/bin/env bash
# Single entry point for running a benchmark stage inside WSL.
#
# Exists because passing a compound `source ... && conda activate ... && cmd`
# string through wsl.exe from PowerShell mangles the quoting. Invoking one
# script by absolute path avoids every layer of that.
#
# Usage:  bash wsl_run.sh <stage> [args...]
#
# Stages:
#   e2         build the synthetic panel (human ART + mixes)
#   han1       download the three HPRC assemblies and run the soft-mask check
#   e3         HostSweep-only E3 over the synthetic panel
#   ablation   E5 dual-pass ablation
#   e7         E7 threshold sweep
#   aggregate  build synthetic_manifest.csv and per_library.csv
#   shell      run an arbitrary command with the env activated

set -uo pipefail

ROOT="$HOME/hostsweep"
CONDA_SH="$ROOT/miniforge3/etc/profile.d/conda.sh"
REPO="$ROOT/HostSweep"
BENCH="$ROOT/bench"
SCRIPTS="$REPO/benchmark/scripts"

# Measurements live OUTSIDE the clone. Every stage hard-resets the clone to
# origin/main before running, and once a results file is tracked in git that
# reset would silently replace a freshly computed measurement with whatever
# was last committed. Keeping outputs in $ROOT/out makes that impossible.
# They are copied into the checkout deliberately, when they are ready to commit.
OUT="$ROOT/out"
RESULTS="$OUT/results"
mkdir -p "$OUT" "$RESULTS"

[ -f "$CONDA_SH" ] || { echo "conda.sh not found at $CONDA_SH" >&2; exit 1; }

# Stages run the WSL clone's copy of each script, not /mnt/c, because the 9p
# mount is far slower for read-heavy work. That means the clone must be current
# before anything runs: a stale clone once executed a version of
# 02_build_synthetic.sh that predated its single-instance lock, and three
# concurrent builders corrupted a library. Refresh first, always.
if [ -d "$REPO/.git" ]; then
    git -C "$REPO" fetch -q origin 2>/dev/null \
        && git -C "$REPO" reset -q --hard origin/main 2>/dev/null \
        || echo "[wsl_run] WARNING: could not refresh $REPO; running what is on disk" >&2
fi
# shellcheck disable=SC1090
. "$CONDA_SH"
conda activate hostsweep || { echo "cannot activate hostsweep env" >&2; exit 1; }

export THREADS="${THREADS:-8}"
export HOSTSWEEP_BBDUK_MEM="${HOSTSWEEP_BBDUK_MEM:-3g}"

STAGE="${1:?usage: wsl_run.sh <stage> [args...]}"
shift || true

echo "[wsl_run] stage=$STAGE  repo=$(git -C "$REPO" rev-parse --short HEAD)  threads=$THREADS"
echo "[wsl_run] started $(date -u +%FT%TZ)"

case "$STAGE" in
    e2)
        bash "$SCRIPTS/02_build_synthetic.sh" "$BENCH"
        ;;
    han1)
        python "$SCRIPTS/03_fetch_human_sources.py" \
            --refs "$BENCH/refs" \
            --report "$BENCH/human_sources_provenance.json"
        ;;
    e3)
        bash "$SCRIPTS/run_e3.sh" "$BENCH/synthetic" "$RESULTS" "${1:-3}" "${@:2}"
        ;;
    ablation)
        bash "$SCRIPTS/run_ablation_panel.sh" "$BENCH/synthetic" \
             "$OUT/ablation_results" "${1:-3}"
        ;;
    e7)
        bash "$SCRIPTS/run_e7.sh" "$BENCH/synthetic" \
             "$OUT/sweep_results" "$@"
        ;;
    aggregate)
        python "$SCRIPTS/aggregate_results.py" \
            --results "$RESULTS" \
            --synthetic "$BENCH/synthetic" \
            --out-dir "$OUT"
        ;;
    e4dl)
        # Runs in the sra env, not hostsweep. Kept as a stage rather than an
        # inline "source ... && conda activate sra && ..." string because that
        # form is mangled passing through PowerShell to wsl.exe and fails with
        # "source: filename argument required" -- silently, having done nothing.
        conda activate sra || { echo "sra env missing; install it first" >&2; exit 1; }
        # Lean by default: E4 (all 30 real libraries, HostSweep) is already in
        # the committed results, and what is still open -- E9's assemblies for
        # BMTagger/CheckM2 -- needs only these three real libraries (~1.6 GB
        # against 25-30 GB for the panel). MUST match REAL_LIBS in
        # chain_e9.sh. FULL=1 fetches all 30. An explicit RUNS_ONLY wins.
        if [ "${FULL:-0}" != 1 ] && [ -z "${RUNS_ONLY:-}" ]; then
            export RUNS_ONLY="SRR40486826 ERR15898346 SRR31641567"
            echo "[wsl_run] e4dl: lean mode -- the 3 real libraries E9 needs (FULL=1 for all 30)"
        fi
        bash "$SCRIPTS/05_download_panel.sh" "${1:-$ROOT/e4_fastq}" "${2:-2}"
        ;;
    e4)
        bash "$SCRIPTS/run_e4.sh" "${1:-$ROOT/e4_fastq}" "$OUT/e4_results" \
             "${2:-3}" "${@:3}"
        ;;
    shell)
        "$@"
        ;;
    *)
        echo "unknown stage: $STAGE" >&2; exit 2 ;;
esac

RC=$?
echo "[wsl_run] finished $(date -u +%FT%TZ) rc=$RC"
exit $RC
