#!/usr/bin/env bash
# Run E5 (dual-pass ablation), then resume E9.
#
# ---------------------------------------------------------------------------
# WHY n=1 RATHER THAN n=3
#
# E3 ran twelve libraries three times each and produced bit-identical
# sensitivity AND false positive rate in 12 of 12 libraries. The replicates
# bought proof of determinism; they bought no accuracy information, because the
# second and third runs reproduced the first to the digit.
#
# The only quantity that did vary was runtime, by up to 3.7x within a library,
# and that variance is an artifact of paging against an 11 GB ceiling rather
# than a property of the method (deviation D17) -- so it is not reportable
# either.
#
# Accuracy standard deviation for a deterministic pipeline is exactly 0, and
# that is now demonstrated across 36 runs rather than asserted. Running three
# replicates here to emit three identical numbers, and presenting their spread
# as a confidence interval, would be worse practice than reporting n=1 with the
# determinism evidence cited.
#
# The two configurations E5 adds -- minimap2_only and bowtie2_only -- are
# strict subsets of the same code path E3 exercised, driven through the same
# modules with the same parameters, so the determinism argument covers them.
# dual_pass is the full pipeline and is directly covered by E3's own runs.
# ---------------------------------------------------------------------------
#
# Usage:  bash chain_e5_e9.sh [runs]
set -uo pipefail

RUNS="${1:-1}"
ROOT="$HOME/hostsweep"
REPO="$ROOT/HostSweep"
OUT="$ROOT/out"
SYN="$ROOT/bench/synthetic"
SCRIPTS="$REPO/benchmark/scripts"

say() { echo "[chain59 $(date -u +%H:%M:%S)] $*"; }

# shellcheck disable=SC1091
. "$ROOT/miniforge3/etc/profile.d/conda.sh"
conda activate hostsweep || { echo "cannot activate hostsweep" >&2; exit 1; }

export THREADS="${THREADS:-8}"
export HOSTSWEEP_BBDUK_MEM="${HOSTSWEEP_BBDUK_MEM:-3g}"

exec 6>"$OUT/.chain59.lock"
if ! flock -n 6; then say "another E5/E9 chain is running; exiting"; exit 0; fi

# --- E5 ---------------------------------------------------------------
say "E5 dual-pass ablation, $RUNS run(s) per configuration, 12 libraries"
bash "$SCRIPTS/run_ablation_panel.sh" "$SYN" "$OUT/ablation_results" "$RUNS" \
    || say "E5 returned non-zero; continuing"

if [ -s "$OUT/ablation_results/ablation.csv" ]; then
    cp "$OUT/ablation_results/ablation.csv" "$OUT/ablation.csv"
    say "ablation.csv: $(( $(wc -l < "$OUT/ablation.csv") - 1 )) rows"
else
    say "ablation.csv NOT produced"
fi

# --- E9 resume --------------------------------------------------------
say "resuming E9 (staged libraries are skipped)"
bash "$SCRIPTS/chain_e9.sh" || say "E9 returned non-zero"

say "chain complete"
