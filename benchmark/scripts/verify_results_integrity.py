#!/usr/bin/env python3
"""Verify every recorded result is complete and well-formed before it is trusted.

Run this after any interruption, and again before packaging.

A benchmark that is stopped and resumed can leave artifacts that *look*
complete but are not: a metrics JSON truncated mid-write, a .time file with no
peak-RSS line, a cleaned_run1 copy cut short. Resume logic treats the presence
of a metrics JSON as proof a run finished, so a truncated one would be skipped
on resume and its half-written numbers would flow into per_library.csv
indistinguishable from a real measurement.

Checks, per (library, tool, run):
  1. metrics JSON parses as JSON
  2. it carries the fields the aggregator reads
  3. sensitivity and FPR are numbers in [0, 100], or explicitly empty for
     real libraries that have no truth set
  4. a matching .time file exists and carries both wall clock and max RSS
  5. any kept cleaned_run1 FASTQ is non-empty and is real gzip

Anything that fails is reported and, with --quarantine, moved aside so the
next run recomputes it instead of trusting it.

Usage:
    python verify_results_integrity.py --results <dir> [--quarantine]
"""
import argparse
import gzip
import json
import re
import shutil
import sys
from pathlib import Path

REQUIRED = ("tool",)
NUMERIC = ("sensitivity", "false_positive_rate")


def check_time_file(path):
    if not path.exists():
        return "no .time file"
    text = path.read_text(errors="replace")
    if "Elapsed (wall clock) time" not in text:
        return ".time file has no wall-clock line (process killed mid-run?)"
    if "Maximum resident set size" not in text:
        return ".time file has no max-RSS line"
    return None


def check_gzip(path):
    try:
        with open(path, "rb") as fh:
            if fh.read(2) != b"\x1f\x8b":
                return "not gzip"
        with gzip.open(path, "rb") as fh:
            while fh.read(1 << 20):
                pass
    except OSError as exc:
        return "unreadable gzip (%s)" % exc.__class__.__name__
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--results", required=True)
    ap.add_argument("--quarantine", action="store_true",
                    help="move bad artifacts to <results>/.quarantine so they recompute")
    ap.add_argument("--check-cleaned", action="store_true",
                    help="also decompress kept cleaned_run1 FASTQ (slow but thorough)")
    args = ap.parse_args()

    root = Path(args.results)
    if not root.is_dir():
        print("results dir not found: %s" % root)
        return 2

    problems = []
    ok = 0
    for lib_dir in sorted(p for p in root.iterdir() if p.is_dir()):
        for mj in sorted(lib_dir.glob("metrics_*_run*.json")):
            m = re.match(r"metrics_(.+)_run(\d+)\.json$", mj.name)
            if not m:
                continue
            tool, run = m.group(1), int(m.group(2))
            tag = "%s/%s/run%d" % (lib_dir.name, tool, run)

            try:
                d = json.loads(mj.read_text())
            except (json.JSONDecodeError, OSError) as exc:
                problems.append((mj, tag, "metrics JSON does not parse (%s)"
                                 % exc.__class__.__name__))
                continue

            missing = [k for k in REQUIRED if k not in d]
            if missing:
                problems.append((mj, tag, "missing field(s): %s" % ", ".join(missing)))
                continue

            bad_num = None
            for key in NUMERIC:
                v = d.get(key, "")
                if v == "" or v is None:
                    continue          # legitimately empty: no truth set
                try:
                    f = float(v)
                except (TypeError, ValueError):
                    bad_num = "%s is not numeric: %r" % (key, v)
                    break
                if not (0.0 <= f <= 100.0):
                    bad_num = "%s out of range: %r" % (key, v)
                    break
            if bad_num:
                problems.append((mj, tag, bad_num))
                continue

            terr = check_time_file(lib_dir / ("%s_run%d.time" % (tool, run)))
            if terr:
                problems.append((mj, tag, terr))
                continue

            ok += 1

        if args.check_cleaned:
            for fq in sorted(lib_dir.glob("cleaned_run*/*.fastq.gz")):
                gerr = check_gzip(fq)
                if gerr:
                    problems.append((fq, "%s/%s" % (lib_dir.name, fq.name), gerr))

    print("verified %d complete run(s)" % ok)
    if not problems:
        print("No malformed artifacts. Safe to resume or package.")
        return 0

    print("\n%d PROBLEM(S):" % len(problems))
    for path, tag, why in problems:
        print("  %-34s %s" % (tag, why))

    if args.quarantine:
        qroot = root / ".quarantine"
        qroot.mkdir(exist_ok=True)
        for path, tag, _ in problems:
            dest = qroot / ("%s__%s" % (path.parent.name, path.name))
            shutil.move(str(path), str(dest))
        print("\nMoved %d artifact(s) to %s; they will recompute on resume."
              % (len(problems), qroot))
    else:
        print("\nRe-run with --quarantine to move these aside so they recompute.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
