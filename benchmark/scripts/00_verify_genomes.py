#!/usr/bin/env python3
"""Verify every accession in benchmark/genomes.tsv resolves at NCBI.

Queries the NCBI Datasets v2 REST API (the same data the `datasets summary
genome accession ...` CLI returns) and reports, per accession, the organism
name NCBI holds, the assembly level and the total sequence length. Exits
non-zero if any accession fails to resolve or if the abundances do not sum
to 1.0, so it can gate the download step.

Usage:
    python benchmark/scripts/00_verify_genomes.py [--tsv benchmark/genomes.tsv]
                                                  [--out genomes_verified.tsv]
"""
import argparse
import json
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

API = "https://api.ncbi.nlm.nih.gov/datasets/v2alpha/genome/accession/{}/dataset_report"


def load_rows(tsv_path):
    rows = []
    with open(tsv_path, encoding="utf-8") as fh:
        for line in fh:
            line = line.rstrip("\n")
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            parts = line.split("\t")
            if parts[0] == "accession":          # header
                continue
            if len(parts) < 3:
                raise SystemExit("malformed row (need 3 tab-separated fields): %r" % line)
            rows.append({"accession": parts[0].strip(),
                         "organism": parts[1].strip(),
                         "abundance": float(parts[2])})
    return rows


def query(accession, retries=3):
    """Return the first dataset report for an accession, or None."""
    last = None
    for attempt in range(retries):
        try:
            req = urllib.request.Request(
                API.format(accession),
                headers={"User-Agent": "HostSweep-benchmark/1.0"},
            )
            with urllib.request.urlopen(req, timeout=60) as resp:
                payload = json.load(resp)
            reports = payload.get("reports")
            return reports[0] if reports else None
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
            last = exc
            time.sleep(2 * (attempt + 1))
    raise SystemExit("network error querying %s: %r" % (accession, last))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tsv", default="benchmark/genomes.tsv")
    ap.add_argument("--out", default=None,
                    help="optional TSV of the verified metadata")
    args = ap.parse_args()

    rows = load_rows(args.tsv)
    print("Verifying %d accessions from %s\n" % (len(rows), args.tsv))

    failures = []
    verified = []
    for row in rows:
        acc = row["accession"]
        rep = query(acc)
        if rep is None:
            print("  FAIL   %-18s does not resolve at NCBI" % acc)
            failures.append(acc)
            continue

        got_acc = rep.get("accession", "")
        organism = rep.get("organism", {}).get("organism_name", "")
        strain = rep.get("organism", {}).get("infraspecific_names", {}).get("strain", "")
        info = rep.get("assembly_info", {})
        stats = rep.get("assembly_stats", {})
        level = info.get("assembly_level", "")
        name = info.get("assembly_name", "")
        length = stats.get("total_sequence_length", "")

        # The API redirects suppressed/replaced accessions, so confirm we were
        # handed back the version we asked for rather than a substitute.
        exact = got_acc == acc
        status = "OK  " if exact else "WARN"
        if not exact:
            failures.append("%s -> returned %s" % (acc, got_acc))

        print("  %s   %-18s %-12s %-10s %12s bp  %s%s"
              % (status, acc, name, level, length, organism,
                 (" str. " + strain) if strain else ""))
        verified.append({**row, "returned_accession": got_acc,
                         "ncbi_organism": organism, "strain": strain,
                         "assembly_name": name, "assembly_level": level,
                         "total_sequence_length": length})

    total = sum(r["abundance"] for r in rows)
    print("\nAbundance sum: %.4f" % total)
    if abs(total - 1.0) > 1e-9:
        print("  FAIL   abundances must sum to 1.0")
        failures.append("abundance sum %.4f" % total)

    if args.out and verified:
        cols = ["accession", "returned_accession", "organism", "ncbi_organism",
                "strain", "assembly_name", "assembly_level",
                "total_sequence_length", "abundance"]
        with open(args.out, "w", encoding="utf-8", newline="") as fh:
            fh.write("\t".join(cols) + "\n")
            for v in verified:
                fh.write("\t".join(str(v.get(c, "")) for c in cols) + "\n")
        print("Wrote %s" % args.out)

    if failures:
        print("\n%d problem(s): %s" % (len(failures), ", ".join(map(str, failures))))
        return 1
    print("\nAll %d accessions resolve." % len(rows))
    return 0


if __name__ == "__main__":
    sys.exit(main())
