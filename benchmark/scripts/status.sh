#!/usr/bin/env bash
# One-line-per-fact status of the benchmark working tree and running jobs.
#
# Exists because quoting a multi-command status probe through
# PowerShell -> wsl.exe -> bash mangles reliably. Invoke by absolute path.
#
# Usage:  bash status.sh
set -uo pipefail

BENCH="$HOME/hostsweep/bench"
REPO="$HOME/hostsweep/HostSweep"

count() { ps -eo args 2>/dev/null | grep -c "$1" || true; }

echo "=== running jobs ==="
printf '  %-22s %s\n' "02_build_synthetic"  "$(count '[0]2_build_synthetic')"
printf '  %-22s %s\n' "mix_spikein"         "$(count '[m]ix_spikein')"
printf '  %-22s %s\n' "03_fetch_human"      "$(count '[0]3_fetch_human')"
printf '  %-22s %s\n' "art_illumina"        "$(count '[a]rt_illumina')"
printf '  %-22s %s\n' "conda create"        "$(count '[c]onda create')"
printf '  %-22s %s\n' "hostsweep"           "$(count '[h]ostsweep ')"
printf '  %-22s %s\n' "run_e3/ablation"     "$(count '[r]un_e3\|[r]un_ablation')"

echo
echo "=== repo ==="
echo "  WSL clone HEAD: $(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo '?')"
echo "  has e2 flock:   $(grep -c 'e2.lock' "$REPO/benchmark/scripts/02_build_synthetic.sh" 2>/dev/null || echo 0)"

echo
echo "=== synthetic panel ==="
if [ -d "$BENCH/synthetic" ]; then
    n=$(ls "$BENCH/synthetic"/*_manifest.json 2>/dev/null | wc -l)
    echo "  complete libraries (manifest written): $n / 12"
    ls -lh "$BENCH/synthetic"/ 2>/dev/null | tail -6 | sed 's/^/    /'
else
    echo "  (no synthetic dir)"
fi

echo
echo "=== human sources ==="
for s in HG00438 HG00733 NA19240; do
    f="$BENCH/refs/${s}_pri_mat_f1_v2.fna"
    if [ -s "$f" ]; then
        printf '  %-9s FASTA %s\n' "$s" "$(du -h "$f" | cut -f1)"
    elif [ -s "$f.gz" ]; then
        printf '  %-9s downloading %s\n' "$s" "$(du -h "$f.gz" | cut -f1)"
    else
        printf '  %-9s absent\n' "$s"
    fi
done

echo
echo "=== conda envs ==="
"$HOME/hostsweep/miniforge3/bin/conda" env list 2>/dev/null | grep -v '^#' | awk 'NF{print "  " $1}'

echo
echo "=== disk / memory ==="
df -h / | tail -1 | sed 's/^/  /'
free -g | sed -n '2p;3p' | sed 's/^/  /'
