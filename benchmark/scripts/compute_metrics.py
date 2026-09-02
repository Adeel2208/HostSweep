#!/usr/bin/env python3
"""Score a decontamination run against a controlled-truth spike-in library.

Reads produced by mix_spikein.py carry their origin in the read name (``HSh_``
= human, ``HSb_`` = microbial background), so this script scores any tool whose
output preserves read names -- HostSweep, Hostile, KneadData, BMTagger and
DeconSeq all do.

Definitions (host removal is the positive class):
    TP  human read absent from the cleaned output      (correctly removed)
    FN  human read present in the cleaned output       (missed contamination)
    TN  background read present in the cleaned output  (correctly kept)
    FP  background read absent from the cleaned output (over-filtering)

    sensitivity = TP / (TP + FN)
    false positive rate = FP / (FP + TN)
    background retention = TN / (TN + FP)

Example
-------
    python compute_metrics.py \
        --truth-r1 synthetic/spike_05pct_R1.fastq.gz \
        --cleaned results/spike_05pct/cleaned/spike_05pct_ASSEMBLY_R1.fastq.gz \
        --tool hostsweep --tier assembly \
        --out results/spike_05pct/metrics_assembly.json
"""
import argparse
import gzip
import json
import sys
from pathlib import Path

HUMAN_PREFIX = "HSh"
BACKGROUND_PREFIX = "HSb"


def open_maybe_gzip(path, mode="rt"):
    path = str(path)
    if path.endswith(".gz"):
        return gzip.open(path, mode)
    return open(path, mode)


def read_names(path):
    """Return the set of read names in a FASTQ, ignoring /1 /2 suffixes."""
    names = set()
    with open_maybe_gzip(path) as fh:
        for i, line in enumerate(fh):
            if i % 4 != 0:
                continue
            name = line[1:].split()[0] if len(line) > 1 else ""
            if name.endswith("/1") or name.endswith("/2"):
                name = name[:-2]
            if name:
                names.add(name)
    return names


def origin_of(name):
    if name.startswith(HUMAN_PREFIX):
        return "human"
    if name.startswith(BACKGROUND_PREFIX):
        return "background"
    return None


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--truth-r1", required=True,
                    help="R1 of the mixed library produced by mix_spikein.py")
    ap.add_argument("--truth-r2",
                    help="Optional R2; names are identical to R1 so this is only "
                         "needed if the two files were filtered independently")
    ap.add_argument("--cleaned", nargs="+", required=True,
                    help="One or more cleaned FASTQ files from the tool under test")
    ap.add_argument("--tool", default="hostsweep")
    ap.add_argument("--tier", default="assembly",
                    help="assembly | profiling | stringent (HostSweep) or the "
                         "comparator's single output tier")
    ap.add_argument("--out", help="Write JSON here (default: stdout)")
    args = ap.parse_args()

    truth = read_names(args.truth_r1)
    if args.truth_r2:
        truth |= read_names(args.truth_r2)

    unlabelled = sum(1 for n in truth if origin_of(n) is None)
    if unlabelled:
        sys.exit(f"{unlabelled} truth reads lack an {HUMAN_PREFIX}_/{BACKGROUND_PREFIX}_ "
                 "prefix; regenerate the library with mix_spikein.py")

    kept = set()
    for path in args.cleaned:
        if not Path(path).exists():
            sys.exit(f"cleaned file not found: {path}")
        kept |= read_names(path)

    human_total = sum(1 for n in truth if origin_of(n) == "human")
    background_total = len(truth) - human_total

    human_kept = sum(1 for n in kept if origin_of(n) == "human")
    background_kept = sum(1 for n in kept if origin_of(n) == "background")

    tp = human_total - human_kept
    fn = human_kept
    tn = background_kept
    fp = background_total - background_kept

    def ratio(num, den):
        return (num / den) if den else 0.0

    metrics = {
        "tool": args.tool,
        "tier": args.tier,
        "truth_r1": args.truth_r1,
        "cleaned_files": list(args.cleaned),
        "human_total": human_total,
        "background_total": background_total,
        "true_positives_human_removed": tp,
        "false_negatives_human_retained": fn,
        "true_negatives_background_retained": tn,
        "false_positives_background_removed": fp,
        "sensitivity": round(ratio(tp, tp + fn) * 100, 4),
        "false_positive_rate": round(ratio(fp, fp + tn) * 100, 4),
        "background_retention": round(ratio(tn, tn + fp) * 100, 4),
        "residual_human_fraction": round(ratio(fn, max(1, len(kept))) * 100, 6),
    }

    text = json.dumps(metrics, indent=2)
    if args.out:
        Path(args.out).parent.mkdir(parents=True, exist_ok=True)
        with open(args.out, "w") as fh:
            fh.write(text + "\n")
        print(f"[compute_metrics] wrote {args.out}")
    print(text)


if __name__ == "__main__":
    main()
