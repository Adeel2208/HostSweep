#!/usr/bin/env python3
"""Turn Kraken2 --report files into rows of a kraken2_human*.csv.

    reads_total  = unclassified reads + reads assigned to the root clade
    reads_human  = reads in the Homo sapiens clade (taxid 9606)
    pct_human    = 100 * reads_human / reads_total

Kraken2 writes the unclassified reads on their own "U" line, and the "root"
line's clade count covers CLASSIFIED reads only. The total number of reads
classified-or-not is therefore U + root, not either one alone.

(I3: an earlier inline version of this parser set
    total = max(total, root_clade)  then  total += unclassified
in an order that left reads_total equal to whichever of the two was larger --
in practice the unclassified count -- so reads_total and pct_human were wrong
in every row of the first kraken2_human.csv. reads_human was always right.)

Usage:
    # one report -> append one row
    python kraken2_report_to_csv.py --report R --library L --method M \\
        --db-build-date D --csv OUT.csv
    # every <root>/<library>/<method>/k2.report -> a new CSV
    python kraken2_report_to_csv.py --reports-root ROOT --db-build-date D --csv OUT.csv
"""
import argparse
import csv
import os
import sys
from pathlib import Path

COLS = ["library", "method", "reads_total", "reads_human", "pct_human", "db_build_date"]


def parse_report(path):
    """Return (reads_total, reads_human) from a Kraken2 report."""
    unclassified = root = human = 0
    with open(path) as fh:
        for line in fh:
            f = line.rstrip("\n").split("\t")
            if len(f) < 6:
                continue
            try:
                clade = int(f[1])
            except ValueError:
                continue
            rank, taxid, name = f[3].strip(), f[4].strip(), f[5].strip()
            if rank == "U":
                unclassified += clade
            elif rank == "R" and name == "root":
                root = clade
            if taxid == "9606":
                human = clade
    return unclassified + root, human


def row_for(report, library, method, dbdate):
    total, human = parse_report(report)
    pct = round(100.0 * human / total, 6) if total else ""
    return [library, method, total, human, pct, dbdate]


def append_row(csv_path, row):
    new = not os.path.exists(csv_path) or os.path.getsize(csv_path) == 0
    if not new:
        with open(csv_path, newline="") as fh:
            rd = csv.reader(fh)
            next(rd, None)
            if any(r[:2] == [str(row[0]), str(row[1])] for r in rd if len(r) >= 2):
                print("already recorded", row[0], row[1])
                return
    with open(csv_path, "a", newline="") as fh:
        w = csv.writer(fh)
        if new:
            w.writerow(COLS)
        w.writerow(row)
    print("kraken2", row[0], row[1], "total", row[2], "human", row[3])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--report")
    ap.add_argument("--library")
    ap.add_argument("--method")
    ap.add_argument("--reports-root")
    ap.add_argument("--db-build-date", default="unknown")
    ap.add_argument("--csv", required=True)
    a = ap.parse_args()
    if a.reports_root:
        rows = []
        for rep in sorted(Path(a.reports_root).glob("*/*/k2.report")):
            rows.append(row_for(rep, rep.parent.parent.name, rep.parent.name, a.db_build_date))
        with open(a.csv, "w", newline="") as fh:
            w = csv.writer(fh)
            w.writerow(COLS)
            w.writerows(rows)
        print("wrote %s (%d rows)" % (a.csv, len(rows)))
    else:
        if not (a.report and a.library and a.method):
            ap.error("give --report, --library and --method (or --reports-root)")
        append_row(a.csv, row_for(a.report, a.library, a.method, a.db_build_date))
    return 0


if __name__ == "__main__":
    sys.exit(main())
