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
RESULTS="$REPO/benchmark/run/results"

[ -f "$CONDA_SH" ] || { echo "conda.sh not found at $CONDA_SH" >&2; exit 1; }
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
             "$REPO/benchmark/run/ablation_results" "${1:-3}"
        ;;
    e7)
        bash "$SCRIPTS/run_e7.sh" "$BENCH/synthetic" \
             "$REPO/benchmark/run/sweep_results" "$@"
        ;;
    aggregate)
        python "$SCRIPTS/aggregate_results.py" \
            --results "$RESULTS" \
            --synthetic "$BENCH/synthetic" \
            --out-dir "$REPO/benchmark/run"
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
