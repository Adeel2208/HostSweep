#!/usr/bin/env bash
# Stop every benchmark process, and VERIFY it stopped.
#
# Order matters: chain wrappers first, so nothing launches a replacement while
# the tools are being stopped, then the per-stage loops, then the tools.
#
# The verification at the end is not decoration. A previous stop attempt was
# issued as an inline shell string that hit a syntax error and executed nothing
# at all; a status probe sampled between tools, showed zeros, and the run was
# reported stopped while it was still going. Anything that survives is listed
# here explicitly.
#
# Everything is idempotent, so whatever was in flight simply recomputes on
# resume. Completed work is untouched.
#
# Usage:  bash stop_all.sh
set -uo pipefail

OUT="$HOME/hostsweep/out"
say() { echo "[stop $(date -u +%H:%M:%S)] $*"; }

before_e3=$(ls "$OUT"/results/*/metrics_*.json 2>/dev/null | wc -l)
before_e4=$(ls "$OUT"/e4_results/*/metrics_*.json 2>/dev/null | wc -l)
say "scored before stop: E3/comparators $before_e3, E4 $before_e4"

say "stopping chain wrappers"
for p in chain_all.sh chain_comparators.sh chain_e9.sh chain_e5_e9.sh \
         chain_e3.sh chain_e7_e5.sh; do
    pkill -f "$p" 2>/dev/null && say "  killed $p" || true
done
sleep 2

say "stopping stage loops"
for p in run_e3.sh run_e4.sh run_e7.sh run_ablation_panel.sh run_ablation.py \
         run_e9.sh 02_build_synthetic.sh 05_download_panel.sh; do
    pkill -f "$p" 2>/dev/null && say "  killed $p" || true
done
sleep 2

say "stopping tools"
for p in 'bin/hostsweep' minimap2 bowtie2-align 'hostile clean' kneaddata \
         megahit metaquast kraken2 bbduk fastp samtools prefetch fasterq-dump \
         art_illumina mix_spikein.py; do
    pkill -f "$p" 2>/dev/null && say "  killed $p" || true
done
sleep 3

# Anything stubborn gets one more chance, then SIGKILL.
remaining=$(ps -eo args 2>/dev/null | grep -cE '[c]hain_|[r]un_e3|[r]un_e4|[r]un_e7|[r]un_ablation|[b]in/hostsweep|[m]inimap2|[b]owtie2-align|[m]egahit|[k]raken2|[m]etaquast|[k]neaddata|[h]ostile clean' || true)
if [ "$remaining" -gt 0 ]; then
    say "$remaining process(es) still up; sending SIGKILL"
    pkill -9 -f 'chain_|run_e3|run_e4|run_e7|run_ablation|bin/hostsweep|minimap2|bowtie2-align|megahit|kraken2|metaquast|kneaddata|hostile clean' 2>/dev/null || true
    sleep 3
fi

echo
say "=== VERIFICATION ==="
left=$(ps -eo pid,etime,args 2>/dev/null \
    | grep -E '[c]hain_|[r]un_e3|[r]un_e4|[r]un_e7|[r]un_ablation|[b]in/hostsweep|[m]inimap2|[b]owtie2-align|[m]egahit|[k]raken2|[m]etaquast|[k]neaddata|[h]ostile clean|[p]refetch|[f]asterq' || true)
if [ -z "$left" ]; then
    say "nothing benchmark-related is running"
else
    say "STILL RUNNING:"
    echo "$left" | cut -c1-110 | sed 's/^/    /'
fi

after_e3=$(ls "$OUT"/results/*/metrics_*.json 2>/dev/null | wc -l)
after_e4=$(ls "$OUT"/e4_results/*/metrics_*.json 2>/dev/null | wc -l)
say "scored after stop:  E3/comparators $after_e3, E4 $after_e4"
say "resume with: bash benchmark/scripts/chain_all.sh  (completed work is skipped)"
