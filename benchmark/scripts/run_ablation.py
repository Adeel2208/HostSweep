#!/usr/bin/env python3
"""E5 dual-pass ablation: run HostSweep with one, the other, or both aligner passes.

The CLI has no partial-pipeline mode, so this drives `hostsweep`'s own modules
directly. Every filter parameter is taken from the same defaults `cli.py`
installs, so the only thing that varies between configurations is which
alignment pass runs.

All three configurations end at the **profiling tier** -- fastp, complexity,
length and normalisation run identically in each -- so the comparison isolates
the alignment passes rather than comparing different output tiers:

    minimap2_only  fastp -> minimap2 -> PE2SE -> complexity -> length -> normalise
    bowtie2_only   fastp ->             PE2SE -> complexity -> length -> bowtie2 -> normalise
    dual_pass      fastp -> minimap2 -> PE2SE -> complexity -> length -> bowtie2 -> normalise

`dual_pass` therefore reproduces the profiling output of a normal `hostsweep`
run, which is what the Stage 9 cross-file check compares against.

Wall clock and peak RSS come from GNU time wrapping this process; the caller is
responsible for that (see run_ablation.sh). What this script records itself is
the per-step read counts, in <outdir>/<sample>_<config>_steps.json.

Usage:
    python run_ablation.py --r1 R1.fq.gz --r2 R2.fq.gz --sample SYN-CHM13-01 \\
        --config dual_pass --outdir out/ [--index standard] [--threads 8]
"""
import argparse
import json
import logging
import os
import subprocess
import sys
import time
from pathlib import Path

from hostsweep.aligners import (extract_unmapped_pairs, extract_unmapped_single,
                                run_bowtie2, run_minimap2, sort_bam)
from hostsweep.database import DatabaseManager
from hostsweep.filters import (run_bbduk_complexity, run_bbduk_length,
                               run_bbduk_normalize, run_fastp)
from hostsweep.utils import count_reads, setup_logger

CONFIGS = ("minimap2_only", "bowtie2_only", "dual_pass")


class FastpArgs:
    """The fastp parameter block, matching cli.py's defaults exactly."""

    def __init__(self, threads, verbose):
        self.fastp_tail = 20
        self.fastp_phred = 15
        self.min_length = 50
        self.fastp_complexity = 30
        self.threads = threads
        self.verbose = verbose


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--r1", required=True)
    ap.add_argument("--r2", required=True)
    ap.add_argument("--sample", required=True)
    ap.add_argument("--config", required=True, choices=CONFIGS)
    ap.add_argument("--outdir", required=True)
    ap.add_argument("--index", default="standard")
    ap.add_argument("--threads", type=int, default=8)
    ap.add_argument("--bbduk-entropy", type=float, default=0.7)
    ap.add_argument("--bbduk-min-length", type=int, default=50)
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()

    out = Path(args.outdir)
    out.mkdir(parents=True, exist_ok=True)
    work = out / "work"
    work.mkdir(exist_ok=True)

    logger = setup_logger(
        "ablation",
        str(out / ("%s_%s.log" % (args.sample, args.config))),
        logging.DEBUG if args.verbose else logging.INFO,
    )

    index = DatabaseManager().get_index_paths(args.index)
    n, t = args.sample, args.threads
    steps = {}
    start = time.time()

    logger.info("Ablation config: %s", args.config)
    steps["step0_raw_input"] = count_reads(args.r1)

    # -- fastp (identical in all three configurations) -----------------
    trim_r1 = str(work / ("%s_trimmed_R1.fastq.gz" % n))
    trim_r2 = str(work / ("%s_trimmed_R2.fastq.gz" % n))
    run_fastp(args.r1, args.r2, trim_r1, trim_r2,
              str(out / ("%s_fastp.json" % n)), str(out / ("%s_fastp.html" % n)),
              FastpArgs(t, args.verbose), logger)
    steps["step1_fastp"] = count_reads(trim_r1)

    # -- Pass 1: minimap2 ----------------------------------------------
    if args.config in ("minimap2_only", "dual_pass"):
        raw_bam = str(work / ("%s_mm2_raw.bam" % n))
        sorted_bam = str(work / ("%s_mm2_sorted.bam" % n))
        pe_r1 = str(work / ("%s_pass1_R1.fastq.gz" % n))
        pe_r2 = str(work / ("%s_pass1_R2.fastq.gz" % n))

        run_minimap2(index["minimap2"], trim_r1, trim_r2, raw_bam, t, logger, args.verbose)
        sort_bam(raw_bam, sorted_bam, t, by_name=True, logger=logger, verbose=args.verbose)
        extract_unmapped_pairs(sorted_bam, pe_r1, pe_r2, t, logger, args.verbose)
        steps["step2_minimap2"] = count_reads(pe_r1)
    else:
        # Pass 1 skipped: the trimmed pairs go straight to PE->SE.
        pe_r1, pe_r2 = trim_r1, trim_r2
        steps["step2_minimap2"] = None

    # -- PE -> SE ------------------------------------------------------
    se_file = str(work / ("%s_SE.fastq.gz" % n))
    subprocess.run("cat %s %s > %s" % (pe_r1, pe_r2, se_file), shell=True, check=True)
    steps["step3_pe_to_se"] = count_reads(se_file)

    # -- Complexity + length -------------------------------------------
    complexity_out = str(work / ("%s_complexity.fastq.gz" % n))
    run_bbduk_complexity(se_file, complexity_out, args.bbduk_entropy, t, logger, args.verbose)
    steps["step4_complexity"] = count_reads(complexity_out)

    length_out = str(work / ("%s_length.fastq.gz" % n))
    run_bbduk_length(complexity_out, length_out, args.bbduk_min_length, t, logger, args.verbose)
    steps["step5_length"] = count_reads(length_out)

    # -- Pass 2: bowtie2 -----------------------------------------------
    if args.config in ("bowtie2_only", "dual_pass"):
        bt2_sam = str(work / ("%s_bowtie2.sam" % n))
        bt2_unmapped = str(work / ("%s_bt2_unmapped.fastq.gz" % n))
        run_bowtie2(index["bowtie2"], length_out, bt2_sam, t, logger, args.verbose)
        extract_unmapped_single(bt2_sam, bt2_unmapped, t, logger, args.verbose)
        steps["step6_bowtie2"] = count_reads(bt2_unmapped)
        pre_norm = bt2_unmapped
    else:
        steps["step6_bowtie2"] = None
        pre_norm = length_out

    # -- Normalisation -> the scored output ----------------------------
    profiling = str(out / ("%s_%s_PROFILING.fastq.gz" % (n, args.config)))
    run_bbduk_normalize(pre_norm, profiling, args.bbduk_entropy, t, logger, args.verbose)
    steps["step7_normalization"] = count_reads(profiling)

    runtime = time.time() - start
    record = {
        "sample": n,
        "config": args.config,
        "threads": t,
        "index": args.index,
        "runtime_seconds": round(runtime, 2),
        "scored_output": profiling,
        "steps": steps,
    }
    steps_path = out / ("%s_%s_steps.json" % (n, args.config))
    steps_path.write_text(json.dumps(record, indent=2), encoding="utf-8")

    logger.info("%s / %s complete in %.1f min -> %s",
                n, args.config, runtime / 60, profiling)
    print(json.dumps(record, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
