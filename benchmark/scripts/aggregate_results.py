#!/usr/bin/env python3
"""Aggregate the raw per-run evidence into the deliverable CSVs.

Reads only files that exist on disk. Nothing is inferred, interpolated or
carried over: a run with no metrics JSON becomes a FAILED row citing its
.failed marker, never a plausible-looking value.

Inputs (produced by run_e3.sh / run_ablation.py / 02_build_synthetic.sh):
    <results>/<library>/metrics_<tool>_run<N>.json
    <results>/<library>/<tool>_run<N>.time
    <results>/<library>/<tool>_run<N>.failed
    <synthetic>/<library>_manifest.json

Outputs:
    synthetic_manifest.csv
    per_library.csv

Usage:
    python aggregate_results.py --results benchmark/run/results \\
        --synthetic <workdir>/synthetic --out-dir benchmark/run
"""
import argparse
import csv
import json
import re
import sys
from pathlib import Path

# Human sources for the mismatch arm, recorded so the manifest CSV carries the
# exact assembly each library was built from.
# All three are HPRC Year 1 f1_assembly_v2, primary/maternal haplotype,
# hifiasm v0.14, UCSC Genomics Institute -- one assembly project and one
# assembler version, so "reference mismatch" is not confounded with
# "different assembler". Only the population differs (CHS / PUR / YRI).
HUMAN_SOURCE = {
    "SYN-IND-01": ("HG00438", "GCA_018471515.1"),   # Han Chinese South
    "SYN-NEU-02": ("HG00733", "GCA_018506975.1"),   # Puerto Rican
    "SYN-NEU-03": ("NA19240", "GCA_018503275.1"),   # Yoruban
}


def condition_of(library):
    if library.startswith("SYN-CHM13"):
        return "synthetic_matched"
    if library.startswith("SYN-NEU") or library.startswith("SYN-IND"):
        return "synthetic_mismatch"
    return "real"


def parse_time_file(path):
    """Return (runtime_min, peak_mem_gb) from a GNU time -v file, or (None, None)."""
    if not path.exists():
        return None, None
    runtime = mem = None
    for line in path.read_text(errors="replace").splitlines():
        if "Elapsed (wall clock) time" in line:
            raw = line.split(": ")[-1].strip()
            parts = raw.split(":")
            try:
                if len(parts) == 3:
                    secs = int(parts[0]) * 3600 + int(parts[1]) * 60 + float(parts[2])
                elif len(parts) == 2:
                    secs = int(parts[0]) * 60 + float(parts[1])
                else:
                    secs = float(parts[0])
                runtime = round(secs / 60, 4)
            except ValueError:
                pass
        elif "Maximum resident set size" in line:
            m = re.search(r"(\d+)", line)
            if m:
                mem = round(int(m.group(1)) / (1024 * 1024), 4)   # kB -> GiB
    return runtime, mem


def build_manifest(synthetic_dir, out_dir, source_accessions):
    rows = []
    for mf in sorted(Path(synthetic_dir).glob("*_manifest.json")):
        library = mf.name[: -len("_manifest.json")]
        d = json.loads(mf.read_text())
        src, acc = HUMAN_SOURCE.get(library, ("T2T-CHM13v2.0", "GCF_009914755.1"))
        acc = source_accessions.get(library, acc)
        rows.append({
            "library": library,
            "human_source": src,
            "source_accession": acc,
            "requested_fraction": d.get("requested_fraction"),
            "realised_fraction": round(d.get("realised_fraction", 0), 8),
            "seed": d.get("seed"),
            "total_pairs": d.get("human_pairs", 0) + d.get("background_pairs", 0),
            "human_pairs": d.get("human_pairs"),
            "background_pairs": d.get("background_pairs"),
        })

    out = Path(out_dir) / "synthetic_manifest.csv"
    if not rows:
        print("no *_manifest.json under %s; synthetic_manifest.csv not written"
              % synthetic_dir)
        return {}
    with open(out, "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)
    print("wrote %s (%d rows)" % (out, len(rows)))
    return {r["library"]: r for r in rows}


def build_per_library(results_dir, out_dir, manifest):
    results_dir = Path(results_dir)
    rows = []
    for lib_dir in sorted(p for p in results_dir.iterdir() if p.is_dir()):
        library = lib_dir.name
        man = manifest.get(library, {})
        total_pairs = man.get("total_pairs")
        pairs_m = round(total_pairs / 1e6, 4) if total_pairs else ""
        realised = man.get("realised_fraction")
        host_pct = round(realised * 100, 6) if realised is not None else ""

        seen = set()
        for mj in sorted(lib_dir.glob("metrics_*_run*.json")):
            m = re.match(r"metrics_(.+)_run(\d+)\.json$", mj.name)
            if not m:
                continue
            tool, run = m.group(1), int(m.group(2))
            seen.add((tool, run))
            d = json.loads(mj.read_text())
            runtime, mem = parse_time_file(lib_dir / ("%s_run%d.time" % (tool, run)))
            rows.append({
                "library": library,
                "category": "synthetic" if library.startswith("SYN-") else "",
                "condition": condition_of(library),
                "tool": tool, "run": run,
                "pairs_m": pairs_m, "host_pct": host_pct,
                "sensitivity_pct": d.get("sensitivity", ""),
                "fpr_pct": d.get("false_positive_rate", ""),
                "runtime_min": runtime if runtime is not None else "NA",
                "peak_mem_gb": mem if mem is not None else "NA",
            })

        # Runs that failed leave a marker and no metrics. They are recorded as
        # FAILED rather than omitted, so the row count reflects what was tried.
        for marker in sorted(lib_dir.glob("*_run*.failed")):
            m = re.match(r"(.+)_run(\d+)\.failed$", marker.name)
            if not m:
                continue
            tool, run = m.group(1), int(m.group(2))
            if (tool, run) in seen:
                continue
            runtime, mem = parse_time_file(lib_dir / ("%s_run%d.time" % (tool, run)))
            rows.append({
                "library": library,
                "category": "synthetic" if library.startswith("SYN-") else "",
                "condition": condition_of(library),
                "tool": tool, "run": run,
                "pairs_m": pairs_m, "host_pct": host_pct,
                "sensitivity_pct": "FAILED", "fpr_pct": "FAILED",
                "runtime_min": runtime if runtime is not None else "FAILED",
                "peak_mem_gb": mem if mem is not None else "FAILED",
            })

    out = Path(out_dir) / "per_library.csv"
    cols = ["library", "category", "condition", "tool", "run", "pairs_m",
            "host_pct", "sensitivity_pct", "fpr_pct", "runtime_min", "peak_mem_gb"]
    if not rows:
        print("no metrics JSON under %s; per_library.csv not written" % results_dir)
        return
    rows.sort(key=lambda r: (r["library"], r["tool"], r["run"]))
    with open(out, "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=cols)
        w.writeheader()
        w.writerows(rows)
    failed = sum(1 for r in rows if r["sensitivity_pct"] == "FAILED")
    print("wrote %s (%d rows, %d FAILED)" % (out, len(rows), failed))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--results", required=True)
    ap.add_argument("--synthetic", required=True)
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--source-accessions", default=None,
                    help="optional JSON mapping library -> assembly accession, "
                         "for the mismatch arm")
    args = ap.parse_args()

    src = {}
    if args.source_accessions and Path(args.source_accessions).exists():
        src = json.loads(Path(args.source_accessions).read_text())

    Path(args.out_dir).mkdir(parents=True, exist_ok=True)
    manifest = build_manifest(args.synthetic, args.out_dir, src)
    if Path(args.results).is_dir():
        build_per_library(args.results, args.out_dir, manifest)
    else:
        print("results dir %s absent; per_library.csv not written" % args.results)
    return 0


if __name__ == "__main__":
    sys.exit(main())
