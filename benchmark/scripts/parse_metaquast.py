#!/usr/bin/env python3
"""Turn one MetaQUAST report into rows of downstream_*.csv.

Same fields, same rules as the inline parser in run_e9.sh, kept in one place
for the metaSPAdes arm (R2):

  * real libraries: genome_fraction_pct and misassemblies are blanked no matter
    what the report says. MetaQUAST without a reference set is run with
    --max-ref-number 0 so it cannot fetch its own references (I2); the blanking
    is a second guard, enforced in code rather than asserted in a comment.
  * assembled_mb_ge_1kb is reported beside misassemblies so a rate has an
    explicit denominator (Editor 14).

Usage:
    python parse_metaquast.py <mq_dir> <library> <condition> <method> \\
        <downstream_csv> [--replicate N --replicates-csv FILE --wall-min X
                          --peak-mem-gb Y --threads T --mem-limit-gb M]

Idempotent: one row per (library, method) in <downstream_csv> (replicate 1
only), and one per (library, method, replicate) in the replicates CSV.
"""
import argparse
import csv
import os
import sys

COLS = ["library", "condition", "method", "n50", "total_length_mb",
        "contigs_ge_1kb", "largest_contig_kb", "genome_fraction_pct",
        "misassemblies", "assembled_mb_ge_1kb", "duplication_ratio"]
REP_COLS = COLS[:3] + ["replicate"] + COLS[3:] + \
    ["assembly_wall_min", "assembly_peak_mem_gb", "threads", "spades_mem_limit_gb"]


def find_report(root):
    for name in ("combined_reference/report.tsv", "report.tsv"):
        p = os.path.join(root, name)
        if os.path.exists(p):
            return p
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mq_dir")
    ap.add_argument("library")
    ap.add_argument("condition")
    ap.add_argument("method")
    ap.add_argument("downstream_csv")
    ap.add_argument("--replicate", type=int, default=1)
    ap.add_argument("--replicates-csv", default=None)
    ap.add_argument("--wall-min", default="")
    ap.add_argument("--peak-mem-gb", default="")
    ap.add_argument("--threads", default="")
    ap.add_argument("--mem-limit-gb", default="")
    a = ap.parse_args()

    path = find_report(a.mq_dir)
    vals = {}
    if path:
        with open(path) as fh:
            for line in fh:
                parts = line.rstrip("\n").split("\t")
                if len(parts) >= 2:
                    vals[parts[0].strip()] = parts[1].strip()

    def num(*keys):
        for k in keys:
            v = vals.get(k)
            if v not in (None, "", "-"):
                return v
        return ""

    def scaled(key, div, nd):
        v = num(key)
        try:
            return round(float(v) / div, nd)
        except (TypeError, ValueError):
            return ""

    row = [a.library, a.condition, a.method,
           num("N50"),
           scaled("Total length (>= 0 bp)", 1e6, 4) or scaled("Total length", 1e6, 4),
           num("# contigs (>= 1000 bp)"),
           scaled("Largest contig", 1e3, 3),
           num("Genome fraction (%)"),
           num("# misassemblies"),
           scaled("Total length (>= 1000 bp)", 1e6, 4),
           num("Duplication ratio")]
    if a.condition == "real":
        row[7] = ""
        row[8] = ""

    def existing_keys(csv_path, idx):
        s = set()
        if os.path.exists(csv_path):
            with open(csv_path, newline="") as fh:
                rd = csv.reader(fh)
                next(rd, None)
                for r in rd:
                    if len(r) > max(idx):
                        s.add(tuple(r[i] for i in idx))
        return s

    def append(csv_path, header, values, key_idx, key):
        new = not os.path.exists(csv_path) or os.path.getsize(csv_path) == 0
        if not new and key in existing_keys(csv_path, key_idx):
            print("already recorded", key, "in", os.path.basename(csv_path))
            return
        with open(csv_path, "a", newline="") as fh:
            w = csv.writer(fh)
            if new:
                w.writerow(header)
            w.writerow(values)
        print("recorded", key, "in", os.path.basename(csv_path),
              "| report:", path or "NONE")

    if a.replicate == 1:
        append(a.downstream_csv, COLS, row, (0, 2), (a.library, a.method))
    if a.replicates_csv:
        rep_row = row[:3] + [a.replicate] + row[3:] + \
            [a.wall_min, a.peak_mem_gb, a.threads, a.mem_limit_gb]
        append(a.replicates_csv, REP_COLS, rep_row, (0, 2, 3),
               (a.library, a.method, str(a.replicate)))
    return 0 if path else 2


if __name__ == "__main__":
    sys.exit(main())
