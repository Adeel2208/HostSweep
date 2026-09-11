#!/usr/bin/env bash
# Re-run the comparator benchmark after the current chain_all finishes.
#
# The first attempt failed in five seconds: every one of the 36 runs exited 127
# with "cannot run hostile: No such file or directory". run_e3.sh executed the
# comparator commands directly while only the hostsweep environment was active,
# and hostile / kneaddata live in their own environments because their
# dependency sets conflict. run_e3.sh now activates the right environment per
# tool; this re-runs the stage.
#
# Waits for chain_all rather than racing it -- two pipelines against an 11 GB
# ceiling OOM both. The stale .failed markers from the first attempt do not
# block anything: run_e3.sh skips on the presence of a metrics JSON, not on the
# absence of a failure marker, and aggregate_results.py ignores a .failed once
# a metrics JSON exists for the same (tool, run).
#
# Usage:  bash chain_comparators.sh
set -uo pipefail

ROOT="$HOME/hostsweep"
REPO="$ROOT/HostSweep"
OUT="$ROOT/out"
SYN="$ROOT/bench/synthetic"
SCRIPTS="$REPO/benchmark/scripts"

say() { echo "[CMP $(date -u +%FT%H:%M:%SZ)] $*"; }

if [ -d "$REPO/.git" ]; then
    git -C "$REPO" fetch -q origin 2>/dev/null \
        && git -C "$REPO" reset -q --hard origin/main 2>/dev/null \
        && say "clone at $(git -C "$REPO" rev-parse --short HEAD)"
fi

# shellcheck disable=SC1091
. "$ROOT/miniforge3/etc/profile.d/conda.sh"

export THREADS="${THREADS:-8}"
export HOSTSWEEP_BBDUK_MEM="${HOSTSWEEP_BBDUK_MEM:-3g}"
export INDEX=standard
export BT2_INDEX="$ROOT/miniforge3/envs/hostsweep/share/hostsweep/databases/standard/human_bt2"

exec 4>"$OUT/.chain_cmp.lock"
if ! flock -n 4; then say "another comparator chain is running; exiting"; exit 0; fi

say "waiting for chain_all to finish"
for _ in $(seq 1 5760); do
    pgrep -f chain_all.sh >/dev/null 2>&1 || break
    sleep 30
done
say "chain_all no longer running"

# Confirm the tools resolve before spending hours discovering they do not.
for spec in "hostile:hostile" "kneaddata:kneaddata"; do
    env_name="${spec%%:*}"; bin_name="${spec##*:}"
    if conda activate "$env_name" 2>/dev/null && command -v "$bin_name" >/dev/null 2>&1; then
        say "  $bin_name resolves in env '$env_name': $(command -v "$bin_name")"
        conda deactivate
    else
        say "  WARNING: $bin_name does NOT resolve in env '$env_name'"
        conda deactivate 2>/dev/null || true
    fi
done

say "comparator benchmark: 3 configurations x 12 synthetic libraries"
bash "$SCRIPTS/run_e3.sh" "$SYN" "$OUT/results" 1 \
     hostile_matched hostile_default kneaddata \
    || say "run_e3 returned non-zero"

say "aggregating"
conda activate hostsweep 2>/dev/null || true
python "$SCRIPTS/aggregate_results.py" --results "$OUT/results" \
    --synthetic "$SYN" --out-dir "$OUT" || say "aggregate failed"

say "comparator rows now present:"
for t in hostsweep hostile_matched hostile_default kneaddata; do
    n=$(ls "$OUT"/results/*/metrics_"$t"_run*.json 2>/dev/null | wc -l)
    say "  $t: $n"
done
say "COMPARATOR STAGE COMPLETE"
