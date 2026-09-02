#!/usr/bin/env python3
"""Build a controlled-truth spike-in library from a microbial background and a
human read set.

Origin is encoded in the read name (``HSb_`` for background, ``HSh_`` for
human), so downstream metrics survive every tool in the comparison: fastp,
samtools fastq, BBDuk, Hostile and KneadData all preserve the read name up to
the first whitespace. compute_metrics.py relies on that prefix and needs no
side-car mapping, though one is written anyway for auditing.

Example
-------
    python mix_spikein.py \
        --background-r1 cami_R1.fastq.gz --background-r2 cami_R2.fastq.gz \
        --human-r1 art_human_R1.fastq.gz --human-r2 art_human_R2.fastq.gz \
        --fraction 0.05 --total-pairs 2000000 --seed 42 \
        --out-prefix synthetic/spike_05pct
"""
import argparse
import gzip
import json
import random
import sys
from pathlib import Path

BACKGROUND_PREFIX = "HSb"
HUMAN_PREFIX = "HSh"


def open_maybe_gzip(path, mode="rt"):
    path = str(path)
    if path.endswith(".gz"):
        return gzip.open(path, mode)
    return open(path, mode)


def read_pairs(r1_path, r2_path):
    """Yield (r1_record, r2_record) as 4-line lists."""
    with open_maybe_gzip(r1_path) as f1, open_maybe_gzip(r2_path) as f2:
        while True:
            rec1 = [f1.readline() for _ in range(4)]
            rec2 = [f2.readline() for _ in range(4)]
            if not rec1[0] or not rec2[0]:
                break
            yield rec1, rec2


def reservoir_sample_pairs(r1_path, r2_path, k, rng):
    """Uniform sample of k pairs in one pass, without holding the file in RAM."""
    reservoir = []
    for i, pair in enumerate(read_pairs(r1_path, r2_path)):
        if i < k:
            reservoir.append(pair)
        else:
            j = rng.randrange(i + 1)
            if j < k:
                reservoir[j] = pair
    return reservoir


def relabel(rec1, rec2, prefix, idx):
    name = f"{prefix}_{idx:09d}"
    rec1 = [f"@{name}\n", rec1[1], "+\n", rec1[3]]
    rec2 = [f"@{name}\n", rec2[1], "+\n", rec2[3]]
    return rec1, rec2


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--background-r1", required=True)
    ap.add_argument("--background-r2", required=True)
    ap.add_argument("--human-r1", required=True)
    ap.add_argument("--human-r2", required=True)
    ap.add_argument("--fraction", type=float, required=True,
                    help="Human fraction of the final library, e.g. 0.05 for 5%%")
    ap.add_argument("--total-pairs", type=int, required=True,
                    help="Total read pairs in the mixed library")
    ap.add_argument("--seed", type=int, required=True,
                    help="RNG seed; the manuscript uses 42-53 (see ../synthetic/README.md)")
    ap.add_argument("--out-prefix", required=True)
    args = ap.parse_args()

    if not 0.0 <= args.fraction <= 1.0:
        sys.exit("--fraction must be between 0 and 1")

    rng = random.Random(args.seed)
    n_human = int(round(args.total_pairs * args.fraction))
    n_background = args.total_pairs - n_human

    print(f"[mix_spikein] seed={args.seed} target={args.total_pairs:,} pairs "
          f"({n_human:,} human / {n_background:,} background)")

    human = reservoir_sample_pairs(args.human_r1, args.human_r2, n_human, rng)
    background = reservoir_sample_pairs(args.background_r1, args.background_r2,
                                        n_background, rng)

    if len(human) < n_human:
        print(f"[mix_spikein] WARNING: only {len(human):,} human pairs available "
              f"(requested {n_human:,})", file=sys.stderr)
    if len(background) < n_background:
        print(f"[mix_spikein] WARNING: only {len(background):,} background pairs "
              f"available (requested {n_background:,})", file=sys.stderr)

    tagged = ([(HUMAN_PREFIX, p) for p in human] +
              [(BACKGROUND_PREFIX, p) for p in background])
    rng.shuffle(tagged)

    out_prefix = Path(args.out_prefix)
    out_prefix.parent.mkdir(parents=True, exist_ok=True)
    r1_out = f"{out_prefix}_R1.fastq.gz"
    r2_out = f"{out_prefix}_R2.fastq.gz"
    labels_out = f"{out_prefix}_labels.tsv.gz"

    counts = {HUMAN_PREFIX: 0, BACKGROUND_PREFIX: 0}
    with gzip.open(r1_out, "wt") as o1, gzip.open(r2_out, "wt") as o2, \
            gzip.open(labels_out, "wt") as lab:
        lab.write("read_name\torigin\n")
        for idx, (prefix, (rec1, rec2)) in enumerate(tagged, start=1):
            rec1, rec2 = relabel(rec1, rec2, prefix, idx)
            o1.writelines(rec1)
            o2.writelines(rec2)
            origin = "human" if prefix == HUMAN_PREFIX else "background"
            lab.write(f"{rec1[0][1:].strip()}\t{origin}\n")
            counts[prefix] += 1

    manifest = {
        "seed": args.seed,
        "requested_fraction": args.fraction,
        "requested_total_pairs": args.total_pairs,
        "human_pairs": counts[HUMAN_PREFIX],
        "background_pairs": counts[BACKGROUND_PREFIX],
        "realised_fraction": (counts[HUMAN_PREFIX] /
                              max(1, counts[HUMAN_PREFIX] + counts[BACKGROUND_PREFIX])),
        "inputs": {
            "background_r1": args.background_r1,
            "background_r2": args.background_r2,
            "human_r1": args.human_r1,
            "human_r2": args.human_r2,
        },
        "outputs": {"r1": r1_out, "r2": r2_out, "labels": labels_out},
    }
    with open(f"{out_prefix}_manifest.json", "w") as fh:
        json.dump(manifest, fh, indent=2)

    print(f"[mix_spikein] wrote {r1_out}")
    print(f"[mix_spikein] wrote {r2_out}")
    print(f"[mix_spikein] realised human fraction: {manifest['realised_fraction']:.6f}")


if __name__ == "__main__":
    main()
