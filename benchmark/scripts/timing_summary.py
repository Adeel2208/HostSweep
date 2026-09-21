#!/usr/bin/env python3
"""Summarise a timing run (R1, R5) from the raw per-run evidence.

Reads only files on disk: <results>/<library>/<tool>_run<N>.time (GNU time -v),
.swap (from /proc/vmstat), .failed, and metrics_<tool>_run<N>.json. Nothing is
inferred; a run with no .time file is reported as such, never filled in.

Writes to --out-dir:

  run_details.csv     one row per (library, tool, run): wall-clock, peak RSS,
                      exit status, swap counters, page faults, CPU time,
                      sensitivity, FPR
  timing_summary.csv  one row per tool: n, means, SDs, and the split between
                      variability ACROSS RUNS (same library, same tool) and
                      ACROSS LIBRARIES (means of each library)
  swap_check.txt      plain-text verdict on whether any run paged

Usage:
    python timing_summary.py --results <dir> --out-dir <dir> [--threads N]
"""
import argparse
import csv
import json
import re
import statistics as st
import sys
from pathlib import Path


def parse_time(path):
    """GNU time -v -> dict, or None if the file is absent."""
    if not path.exists():
        return None
    d = {}
    for line in path.read_text(errors="replace").splitlines():
        line = line.strip()
        if line.startswith("Elapsed (wall clock) time"):
            raw = line.split(": ", 1)[-1].strip().split(":")
            try:
                if len(raw) == 3:
                    d["wall_s"] = int(raw[0]) * 3600 + int(raw[1]) * 60 + float(raw[2])
                elif len(raw) == 2:
                    d["wall_s"] = int(raw[0]) * 60 + float(raw[1])
                else:
                    d["wall_s"] = float(raw[0])
            except ValueError:
                pass
        elif line.startswith("Maximum resident set size"):
            m = re.search(r"(\d+)", line)
            if m:
                d["peak_rss_kb"] = int(m.group(1))
        elif line.startswith("Exit status"):
            m = re.search(r"(-?\d+)", line)
            if m:
                d["exit_status"] = int(m.group(1))
        elif line.startswith("Swaps:"):
            d["swaps"] = int(line.split(":")[1])
        elif line.startswith("Major (requiring I/O) page faults"):
            d["major_faults"] = int(line.split(":")[1])
        elif line.startswith("Minor (reclaiming a frame) page faults"):
            d["minor_faults"] = int(line.split(":")[1])
        elif line.startswith("User time"):
            d["user_s"] = float(line.split(":")[1])
        elif line.startswith("System time"):
            d["sys_s"] = float(line.split(":")[1])
        elif line.startswith("Percent of CPU"):
            m = re.search(r"(\d+)", line)
            if m:
                d["cpu_pct"] = int(m.group(1))
    return d


def parse_swap(path):
    if not path.exists():
        return None, None
    m = re.search(r"pswpin_pages=(-?\d+) pswpout_pages=(-?\d+)", path.read_text())
    return (int(m.group(1)), int(m.group(2))) if m else (None, None)


def fmt(x, nd=4):
    return "" if x is None else round(x, nd)


def sd(v):
    return st.stdev(v) if len(v) > 1 else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--results", required=True)
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--threads", default="")
    a = ap.parse_args()
    res, out = Path(a.results), Path(a.out_dir)
    out.mkdir(parents=True, exist_ok=True)

    rows = []
    for lib in sorted(p for p in res.iterdir() if p.is_dir()):
        seen = set()
        for pat in ("*_run*.time", "*_run*.failed", "metrics_*_run*.json"):
            for f in lib.glob(pat):
                m = re.match(r"(?:metrics_)?(.+)_run(\d+)\.(?:time|failed|json)$", f.name)
                if m:
                    seen.add((m.group(1), int(m.group(2))))
        for tool, run in sorted(seen):
            t = parse_time(lib / f"{tool}_run{run}.time")
            pin, pout = parse_swap(lib / f"{tool}_run{run}.swap")
            mj = lib / f"metrics_{tool}_run{run}.json"
            failed = (lib / f"{tool}_run{run}.failed").exists()
            sens = fpr = ""
            if mj.exists():
                d = json.loads(mj.read_text())
                sens, fpr = d.get("sensitivity", ""), d.get("false_positive_rate", "")
            exit_status = (t or {}).get("exit_status")
            if exit_status is None and failed:
                mm = re.search(r"exit_status=(-?\d+)",
                               (lib / f"{tool}_run{run}.failed").read_text())
                exit_status = int(mm.group(1)) if mm else "FAILED"
            rows.append({
                "library": lib.name, "tool": tool, "run": run,
                "threads": a.threads,
                "exit_status": "" if exit_status is None else exit_status,
                "scored": "yes" if mj.exists() else "no",
                "wall_clock_s": fmt((t or {}).get("wall_s"), 2),
                "peak_rss_gb": fmt(((t or {}).get("peak_rss_kb") or 0) / 1048576 if t and "peak_rss_kb" in t else None),
                "time_swaps": "" if not t or "swaps" not in t else t["swaps"],
                "major_page_faults": "" if not t or "major_faults" not in t else t["major_faults"],
                "pswpin_pages": "" if pin is None else pin,
                "pswpout_pages": "" if pout is None else pout,
                "user_s": fmt((t or {}).get("user_s"), 2),
                "sys_s": fmt((t or {}).get("sys_s"), 2),
                "cpu_pct": "" if not t or "cpu_pct" not in t else t["cpu_pct"],
                "sensitivity_pct": sens, "fpr_pct": fpr,
                "time_file": "yes" if t else "MISSING",
            })
    cols = list(rows[0].keys()) if rows else []
    with open(out / "run_details.csv", "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=cols)
        w.writeheader()
        w.writerows(rows)
    print("wrote %s (%d rows)" % (out / "run_details.csv", len(rows)))

    # ---- per tool summary ------------------------------------------------
    ok = [r for r in rows if r["scored"] == "yes" and r["wall_clock_s"] != ""]
    tools = sorted({r["tool"] for r in rows})
    scols = ["tool", "n_runs_attempted", "n_runs_ok", "n_libraries",
             "wall_min_mean", "wall_min_sd_all_runs",
             "wall_min_sd_within_library_mean", "wall_min_sd_between_library_means",
             "wall_min_min", "wall_min_max",
             "peak_rss_gb_mean", "peak_rss_gb_max",
             "runs_with_swap_activity"]
    srows = []
    for tool in tools:
        allr = [r for r in rows if r["tool"] == tool]
        good = [r for r in ok if r["tool"] == tool]
        by_lib = {}
        for r in good:
            by_lib.setdefault(r["library"], []).append(r["wall_clock_s"] / 60)
        wall = [r["wall_clock_s"] / 60 for r in good]
        mem = [r["peak_rss_gb"] for r in good if r["peak_rss_gb"] != ""]
        within = [sd(v) for v in by_lib.values() if len(v) > 1]
        within = [x for x in within if x is not None]
        libmeans = [st.mean(v) for v in by_lib.values()]
        swapped = [r for r in allr
                   if (isinstance(r["pswpin_pages"], int) and r["pswpin_pages"] > 0)
                   or (isinstance(r["pswpout_pages"], int) and r["pswpout_pages"] > 0)
                   or (isinstance(r["time_swaps"], int) and r["time_swaps"] > 0)]
        srows.append({
            "tool": tool, "n_runs_attempted": len(allr), "n_runs_ok": len(good),
            "n_libraries": len(by_lib),
            "wall_min_mean": fmt(st.mean(wall)) if wall else "",
            "wall_min_sd_all_runs": fmt(sd(wall)) if wall else "",
            "wall_min_sd_within_library_mean": fmt(st.mean(within)) if within else "",
            "wall_min_sd_between_library_means": fmt(sd(libmeans)) if libmeans else "",
            "wall_min_min": fmt(min(wall)) if wall else "",
            "wall_min_max": fmt(max(wall)) if wall else "",
            "peak_rss_gb_mean": fmt(st.mean(mem)) if mem else "",
            "peak_rss_gb_max": fmt(max(mem)) if mem else "",
            "runs_with_swap_activity": len(swapped),
        })
    with open(out / "timing_summary.csv", "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=scols)
        w.writeheader()
        w.writerows(srows)
    print("wrote %s" % (out / "timing_summary.csv"))

    # ---- swap verdict ----------------------------------------------------
    missing_swap = [r for r in rows if r["pswpin_pages"] == ""]
    swapped = [r for r in rows
               if (isinstance(r["pswpin_pages"], int) and r["pswpin_pages"] > 0)
               or (isinstance(r["pswpout_pages"], int) and r["pswpout_pages"] > 0)
               or (isinstance(r["time_swaps"], int) and r["time_swaps"] > 0)]
    lines = ["runs recorded: %d" % len(rows),
             "runs with a .swap record: %d" % (len(rows) - len(missing_swap)),
             "runs showing ANY swap activity (system-wide pswpin/pswpout during the run,"
             " or a non-zero 'Swaps:' in the time record): %d" % len(swapped)]
    for r in swapped[:20]:
        lines.append("  %s / %s / run %s: pswpin=%s pswpout=%s time_swaps=%s"
                     % (r["library"], r["tool"], r["run"], r["pswpin_pages"],
                        r["pswpout_pages"], r["time_swaps"]))
    lines.append("NOTE: the system-wide counters also move if some OTHER process on the "
                 "machine swapped during a run; they are evidence, not proof of cause.")
    (out / "swap_check.txt").write_text("\n".join(lines) + "\n")
    print("\n".join(lines))
    return 0


if __name__ == "__main__":
    sys.exit(main())
