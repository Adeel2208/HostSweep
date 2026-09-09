#!/usr/bin/env bash
# Halt the benchmark at a clean run boundary.
#
# An immediate kill risks landing mid-write of a metrics JSON or mid-copy of a
# kept cleaned_run1 FASTQ. Resume logic treats a metrics JSON's presence as
# proof the run finished, so a truncated one would be skipped on resume and its
# half-written numbers would enter per_library.csv looking like a measurement.
#
# So: stop the chain wrappers first, so no NEW run can start, then wait for the
# in-flight run to finish scoring, then stop what remains.
#
# Downloads are stopped too. prefetch resumes from where it left off, and any
# library already written as _1/_2.fastq.gz is kept.
#
# Usage:  bash graceful_stop.sh [max_wait_minutes]
set -uo pipefail

MAXWAIT="${1:-45}"
OUT="$HOME/hostsweep/out"
say() { echo "[stop $(date -u +%H:%M:%S)] $*"; }

before=$(ls "$OUT"/results/*/metrics_*.json 2>/dev/null | wc -l)
say "scored runs before stop: $before"

# 1. Stop the wrappers so the loop cannot begin another run. run_e3.sh is left
#    alive deliberately: it is what scores the run currently in flight.
say "stopping chain wrappers (no new runs will start)"
pkill -f chain_e7_e5.sh 2>/dev/null || true
pkill -f chain_e3.sh    2>/dev/null || true
pkill -f 05_download_panel.sh 2>/dev/null || true

# 2. Wait for the in-flight run to produce its metrics JSON.
say "waiting up to ${MAXWAIT}m for the in-flight run to score"
deadline=$(( $(date +%s) + MAXWAIT * 60 ))
while [ "$(date +%s)" -lt "$deadline" ]; do
    now=$(ls "$OUT"/results/*/metrics_*.json 2>/dev/null | wc -l)
    if [ "$now" -gt "$before" ]; then
        say "in-flight run scored (now $now); clean boundary reached"
        break
    fi
    if ! pgrep -f run_e3.sh >/dev/null 2>&1; then
        say "run_e3.sh exited without scoring another run"
        break
    fi
    sleep 15
done

# 3. Stop everything that is left.
say "stopping remaining processes"
pkill -f run_e3.sh          2>/dev/null || true
pkill -f run_ablation       2>/dev/null || true
pkill -f run_e7.sh          2>/dev/null || true
sleep 2
pkill -f 'bin/hostsweep'    2>/dev/null || true
pkill -f minimap2           2>/dev/null || true
pkill -f bowtie2-align      2>/dev/null || true
pkill -f prefetch           2>/dev/null || true
pkill -f fasterq-dump       2>/dev/null || true
sleep 3

left=$(ps -eo args 2>/dev/null | grep -cE '[r]un_e3|[c]hain_|[b]in/hostsweep|[p]refetch|[m]inimap2' || true)
after=$(ls "$OUT"/results/*/metrics_*.json 2>/dev/null | wc -l)
say "processes still running: $left"
say "scored runs after stop:  $after (was $before)"
say "stopped. Resume with chain_e3.sh; completed runs are skipped."
