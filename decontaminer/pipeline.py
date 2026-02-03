"""Main DecontaMiner pipeline class"""
import os
import sys
import time
import json
import logging
from pathlib import Path
from . import __version__
from .utils import count_reads, setup_logger
from .stats import StatsCollector
from .database import DatabaseManager
from .filters import (run_fastp, run_bbduk_complexity, run_bbduk_length,
                      run_bbduk_normalize, run_bbduk_gdpr)
from .aligners import (run_minimap2, run_bowtie2, sort_bam,
                       extract_unmapped_pairs, extract_unmapped_single,
                       get_alignment_stats)


class DecontaMiner:
    """Main pipeline orchestrator — 8-step human DNA decontamination"""

    def __init__(self, args):
        self.args = args
        self.setup_logging()
        self.setup_paths()
        self.stats = StatsCollector(args.sample_name, __version__)

    # ── Setup ──────────────────────────────────────────────
    def setup_logging(self):
        """Configure logging"""
        Path(self.args.output_dir).mkdir(parents=True, exist_ok=True)
        log_file = os.path.join(self.args.output_dir,
                                f"decontaminer_{self.args.sample_name}.log")
        level = logging.DEBUG if self.args.verbose else logging.INFO
        self.logger = setup_logger('decontaminer', log_file, level)
        self.logger.info(f"DecontaMiner v{__version__} started")
        self.logger.info(f"Sample: {self.args.sample_name}")
        self.logger.info(f"Threads: {self.args.threads}")

    def setup_paths(self):
        """Create output directory structure"""
        base = Path(self.args.output_dir)
        self.paths = {
            'qc':        base / 'qc',
            'trimmed':   base / 'trimmed',
            'aligned':   base / 'aligned',
            'converted': base / 'converted',
            'filtered':  base / 'filtered',
            'cleaned':   base / 'cleaned',
            'stats':     base / 'stats',
        }
        for p in self.paths.values():
            p.mkdir(parents=True, exist_ok=True)

    def _p(self, subdir, filename):
        """Shorthand: return full path inside a subdirectory"""
        return str(self.paths[subdir] / filename)

    # ── Index resolution ──────────────────────────────────
    def resolve_index(self):
        """Get minimap2 and bowtie2 index paths"""
        db = DatabaseManager()
        try:
            return db.get_index_paths(self.args.index_name)
        except FileNotFoundError:
            self.logger.error(f"Index '{self.args.index_name}' not found.")
            self.logger.error("Run:  decontaminer --build")
            sys.exit(1)

    # ── Main entry ─────────────────────────────────────────
    def run(self):
        """Execute the full 8-step pipeline"""
        start_time = time.time()
        self.logger.info("=" * 60)
        self.logger.info("PIPELINE START")
        self.logger.info("=" * 60)

        index = self.resolve_index()
        n = self.args.sample_name
        t = self.args.threads

        # ── Step 0: Input validation ─────────────────────
        self.logger.info("\n[Step 0] Input validation")
        raw_pairs = count_reads(self.args.input_r1)
        self.stats.log_step("step0_raw_input", raw_pairs, raw_pairs)
        self.logger.info(f"  Raw read pairs: {raw_pairs:,}")

        # ── Step 1: fastp QC ─────────────────────────────
        self.logger.info("\n[Step 1] Quality control & adapter trimming (fastp)")
        trim_r1 = self._p('trimmed', f'{n}_trimmed_R1.fastq.gz')
        trim_r2 = self._p('trimmed', f'{n}_trimmed_R2.fastq.gz')

        run_fastp(
            self.args.input_r1, self.args.input_r2,
            trim_r1, trim_r2,
            self._p('qc', f'{n}_fastp.json'),
            self._p('qc', f'{n}_fastp.html'),
            self.args, self.logger
        )

        trimmed_pairs = count_reads(trim_r1)
        step1 = self.stats.log_step("step1_fastp_qc", raw_pairs, trimmed_pairs)
        self.logger.info(f"  After fastp: {trimmed_pairs:,} pairs "
                         f"(retained {step1['retention']:.2f}%)")

        # ── Step 2: minimap2 primary host removal ────────
        self.logger.info("\n[Step 2] Primary host removal (minimap2)")
        raw_bam   = self._p('aligned', f'{n}_minimap2_raw.bam')
        sorted_bam = self._p('aligned', f'{n}_minimap2_sorted.bam')
        assembly_r1 = self._p('cleaned', f'{n}_ASSEMBLY_R1.fastq.gz')
        assembly_r2 = self._p('cleaned', f'{n}_ASSEMBLY_R2.fastq.gz')

        run_minimap2(index['minimap2'], trim_r1, trim_r2,
                     raw_bam, t, self.logger, self.args.verbose)
        sort_bam(raw_bam, sorted_bam, t, by_name=True,
                 logger=self.logger, verbose=self.args.verbose)
        extract_unmapped_pairs(sorted_bam, assembly_r1, assembly_r2,
                               t, self.logger, self.args.verbose)

        assembly_pairs = count_reads(assembly_r1)
        step2 = self.stats.log_step("step2_minimap2", trimmed_pairs, assembly_pairs)
        self.logger.info(f"  After minimap2: {assembly_pairs:,} pairs "
                         f"(retained {step2['retention']:.2f}%)")
        self.logger.info(f"  >>> OUTPUT 1 (Assembly PE): {assembly_pairs:,} pairs")

        # ── Step 3: PE → SE conversion ───────────────────
        self.logger.info("\n[Step 3] PE → SE conversion")
        se_file = self._p('converted', f'{n}_SE_combined.fastq.gz')

        # Interleave R1+R2 into single file
        import subprocess
        subprocess.run(
            f"cat {assembly_r1} {assembly_r2} > {se_file}",
            shell=True, check=True
        )

        se_reads = count_reads(se_file)
        self.stats.log_step("step3_pe_to_se", assembly_pairs * 2, se_reads)
        self.logger.info(f"  SE reads: {se_reads:,}")

        # ── Step 4: BBDuk complexity filter ──────────────
        self.logger.info("\n[Step 4] Complexity filter (BBDuk)")
        complexity_out = self._p('filtered', f'{n}_complexity.fastq.gz')

        run_bbduk_complexity(se_file, complexity_out,
                             self.args.bbduk_entropy, t,
                             self.logger, self.args.verbose)

        complexity_reads = count_reads(complexity_out)
        step4 = self.stats.log_step("step4_complexity", se_reads, complexity_reads)
        self.logger.info(f"  After complexity filter: {complexity_reads:,} "
                         f"(retained {step4['retention']:.2f}%)")

        # ── Step 5: BBDuk length filter ──────────────────
        self.logger.info("\n[Step 5] Length filter (BBDuk)")
        length_out = self._p('filtered', f'{n}_length.fastq.gz')

        run_bbduk_length(complexity_out, length_out,
                         self.args.bbduk_min_length, t,
                         self.logger, self.args.verbose)

        length_reads = count_reads(length_out)
        step5 = self.stats.log_step("step5_length", complexity_reads, length_reads)
        self.logger.info(f"  After length filter: {length_reads:,} "
                         f"(retained {step5['retention']:.2f}%)")

        # ── Step 6: Bowtie2 secondary host removal ───────
        self.logger.info("\n[Step 6] Secondary host removal (Bowtie2)")
        bt2_sam = self._p('aligned', f'{n}_bowtie2.sam')

        run_bowtie2(index['bowtie2'], length_out, bt2_sam,
                    t, self.logger, self.args.verbose)

        # Extract unmapped
        bt2_unmapped = self._p('filtered', f'{n}_bt2_unmapped.fastq.gz')
        extract_unmapped_single(bt2_sam, bt2_unmapped,
                                t, self.logger, self.args.verbose)

        bt2_reads = count_reads(bt2_unmapped)
        step6 = self.stats.log_step("step6_bowtie2", length_reads, bt2_reads)
        self.logger.info(f"  After Bowtie2: {bt2_reads:,} "
                         f"(retained {step6['retention']:.2f}%)")

        # ── Step 7: BBDuk normalization → OUTPUT 2 ───────
        self.logger.info("\n[Step 7] Normalization (BBDuk)")
        profiling_out = self._p('cleaned', f'{n}_PROFILING.fastq.gz')

        run_bbduk_normalize(bt2_unmapped, profiling_out,
                            self.args.bbduk_entropy, t,
                            self.logger, self.args.verbose)

        profiling_reads = count_reads(profiling_out)
        step7 = self.stats.log_step("step7_normalization", bt2_reads, profiling_reads)
        self.logger.info(f"  After normalization: {profiling_reads:,} "
                         f"(retained {step7['retention']:.2f}%)")
        self.logger.info(f"  >>> OUTPUT 2 (Profiling SE): {profiling_reads:,} reads")

        # ── Step 8: BBDuk GDPR filter → OUTPUT 3 ─────────
        self.logger.info("\n[Step 8] GDPR strict filter (BBDuk)")
        gdpr_out = self._p('cleaned', f'{n}_GDPR.fastq.gz')

        run_bbduk_gdpr(profiling_out, gdpr_out,
                       self.args.bbduk_gdpr_entropy,
                       self.args.gdpr_min_length, t,
                       self.logger, self.args.verbose)

        gdpr_reads = count_reads(gdpr_out)
        step8 = self.stats.log_step("step8_gdpr", profiling_reads, gdpr_reads)
        self.logger.info(f"  After GDPR filter: {gdpr_reads:,} "
                         f"(retained {step8['retention']:.2f}%)")
        self.logger.info(f"  >>> OUTPUT 3 (GDPR): {gdpr_reads:,} reads")

        # ── Cleanup intermediates ─────────────────────────
        if not self.args.keep_intermediates:
            self._cleanup()

        # ── Finalize stats ────────────────────────────────
        runtime = time.time() - start_time
        final_stats = self.stats.finalize(runtime)
        stats_path = self.stats.save(self._p('stats', f'{n}_stats.json'))

        # ── Summary ───────────────────────────────────────
        self.logger.info("\n" + "=" * 60)
        self.logger.info("PIPELINE COMPLETE")
        self.logger.info("=" * 60)
        self.logger.info(f"  Total runtime: {runtime/60:.1f} minutes")
        self.logger.info(f"  Stats saved:   {stats_path}")
        self.logger.info(f"  OUTPUT 1 (Assembly PE):  {assembly_r1}")
        self.logger.info(f"                           {assembly_r2}")
        self.logger.info(f"  OUTPUT 2 (Profiling SE): {profiling_out}")
        self.logger.info(f"  OUTPUT 3 (GDPR):         {gdpr_out}")
        self.logger.info("=" * 60)

    def _cleanup(self):
        """Remove intermediate files to save space"""
        import shutil
        for subdir in ('aligned', 'converted', 'filtered', 'trimmed'):
            p = self.paths[subdir]
            if p.exists():
                shutil.rmtree(p)
                self.logger.debug(f"Cleaned up: {p}")
