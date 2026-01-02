#!/usr/bin/env python3
"""
HostBuster - Human DNA Decontamination Pipeline
Complete implementation with 3 outputs for metagenomic data

Author: HostBuster Team
Version: 1.0.0
"""

import os
import sys
import argparse
import subprocess
import gzip
import json
import time
from pathlib import Path
from datetime import datetime
import logging

class HostBuster:
    """Main pipeline class for HostBuster"""
    
    def __init__(self, args):
        self.args = args
        self.setup_logging()
        self.setup_paths()
        self.stats = {
            "sample_name": args.sample_name,
            "pipeline_start": datetime.now().isoformat(),
            "parameters": vars(args)
        }
        
    def setup_logging(self):
        """Configure logging"""
        log_file = f"{self.args.output_dir}/hostbuster_{self.args.sample_name}.log"
        Path(self.args.output_dir).mkdir(parents=True, exist_ok=True)
        
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler(log_file),
                logging.StreamHandler(sys.stdout)
            ]
        )
        self.logger = logging.getLogger(__name__)
        
    def setup_paths(self):
        """Setup all directory paths"""
        base = Path(self.args.output_dir)
        self.paths = {
            'qc_pre': base / 'qc_pre',
            'qc_post': base / 'qc_post',
            'trimmed': base / 'trimmed',
            'aligned': base / 'aligned',
            'cleaned': base / 'cleaned',
            'stats': base / 'stats'
        }
        
        for path in self.paths.values():
            path.mkdir(parents=True, exist_ok=True)
            
    def run_command(self, cmd, description, capture_output=False):
        """Execute shell command with error handling"""
        self.logger.info(f"Running: {description}")
        self.logger.debug(f"Command: {cmd}")
        
        try:
            if capture_output:
                result = subprocess.run(cmd, shell=True, capture_output=True, 
                                      text=True, check=True)
                return result.stdout
            else:
                subprocess.run(cmd, shell=True, check=True)
                return None
        except subprocess.CalledProcessError as e:
            self.logger.error(f"Failed: {description}")
            self.logger.error(f"Error: {e}")
            if capture_output and e.stderr:
                self.logger.error(f"stderr: {e.stderr}")
            raise
            
    def count_reads(self, fastq_file):
        """Count reads in FASTQ file"""
        fastq_file = str(fastq_file)  # Convert Path to string
        if not os.path.exists(fastq_file):
            return 0
            
        opener = gzip.open if fastq_file.endswith('.gz') else open
        mode = 'rt' if fastq_file.endswith('.gz') else 'r'
        
        count = 0
        with opener(fastq_file, mode) as f:
            for i, line in enumerate(f):
                if i % 4 == 0:
                    count += 1
        return count
        
    def run(self):
        """Execute complete pipeline"""
        self.logger.info("="*80)
        self.logger.info("HOSTBUSTER PIPELINE - STARTING")
        self.logger.info("="*80)
        
        start_time = time.time()
        
        try:
            # Step 0: Validation
            self.step0_validate()
            
            # Step 1: Quality Control and Trimming
            self.step1_fastp()
            
            # Step 2: Primary Host Removal (minimap2)
            self.step2_minimap2()
            
            self.logger.info("\n" + "="*80)
            self.logger.info("✅ OUTPUT 1 COMPLETE: Assembly-ready paired-end reads")
            self.logger.info("="*80)
            
            # Step 3: Convert to Single-End
            self.step3_convert_to_se()
            
            # Step 4: Complexity Filtering
            self.step4_complexity_filter()
            
            # Step 5: Length Filtering
            self.step5_length_filter()
            
            # Step 6: Secondary Host Removal (bowtie2)
            self.step6_bowtie2()
            
            # Step 7: Post-Alignment Normalization
            self.step7_normalize()
            
            self.logger.info("\n" + "="*80)
            self.logger.info("✅ OUTPUT 2 COMPLETE: Kraken2-optimized single-end reads")
            self.logger.info("="*80)
            
            # Step 8: GDPR Strict Filtering
            self.step8_gdpr_filter()
            
            self.logger.info("\n" + "="*80)
            self.logger.info("✅ OUTPUT 3 COMPLETE: GDPR-compliant publication-ready reads")
            self.logger.info("="*80)
            
            # Generate Reports
            self.generate_reports()
            
            elapsed = time.time() - start_time
            self.stats['total_runtime_seconds'] = elapsed
            
            self.logger.info("\n" + "="*80)
            self.logger.info(f"✅ PIPELINE COMPLETED SUCCESSFULLY in {elapsed/60:.1f} minutes")
            self.logger.info("="*80)
            
            self.print_summary()
            
        except Exception as e:
            self.logger.error(f"Pipeline failed: {e}")
            raise
            
    def step0_validate(self):
        """Step 0: Validate input files"""
        self.logger.info("\n→ Step 0: Validating inputs...")
        
        if not os.path.exists(self.args.input_r1):
            raise FileNotFoundError(f"R1 file not found: {self.args.input_r1}")
        if not os.path.exists(self.args.input_r2):
            raise FileNotFoundError(f"R2 file not found: {self.args.input_r2}")
            
        # Count input reads
        self.logger.info("  Counting input reads...")
        r1_count = self.count_reads(self.args.input_r1)
        r2_count = self.count_reads(self.args.input_r2)
        
        self.logger.info(f"  R1: {r1_count:,} reads")
        self.logger.info(f"  R2: {r2_count:,} reads")
        
        if r1_count != r2_count:
            self.logger.warning(f"  ⚠️  Read counts differ by {abs(r1_count-r2_count):,}")
            
        self.stats['raw_read_pairs'] = min(r1_count, r2_count)
        self.logger.info("  ✓ Input validation complete")
        
    def step1_fastp(self):
        """Step 1: Quality trimming with fastp"""
        self.logger.info("\n→ Step 1: Quality control and adapter trimming (fastp)...")
        
        out_r1 = self.paths['trimmed'] / f"{self.args.sample_name}_R1.fastq.gz"
        out_r2 = self.paths['trimmed'] / f"{self.args.sample_name}_R2.fastq.gz"
        json_out = self.paths['trimmed'] / f"{self.args.sample_name}_fastp.json"
        html_out = self.paths['trimmed'] / f"{self.args.sample_name}_fastp.html"
        
        cmd = f"""fastp \
            --in1 {self.args.input_r1} --in2 {self.args.input_r2} \
            --out1 {out_r1} --out2 {out_r2} \
            --detect_adapter_for_pe \
            --cut_tail --cut_tail_window_size 4 --cut_tail_mean_quality 20 \
            --qualified_quality_phred 20 \
            --length_required 50 \
            --low_complexity_filter --complexity_threshold 30 \
            --trim_poly_g --trim_poly_x \
            --thread {self.args.threads} \
            --json {json_out} --html {html_out} \
            2>&1"""
        
        self.run_command(cmd, "fastp trimming")
        
        # Parse fastp stats
        with open(json_out, 'r') as f:
            fastp_data = json.load(f)
            
        before = fastp_data['summary']['before_filtering']['total_reads']
        after = fastp_data['summary']['after_filtering']['total_reads']
        
        self.stats['after_fastp'] = after // 2
        self.stats['filtered_by_fastp'] = (before - after) // 2
        
        self.logger.info(f"  Input:  {before:,} reads ({before//2:,} pairs)")
        self.logger.info(f"  Output: {after:,} reads ({after//2:,} pairs)")
        self.logger.info(f"  Retention: {(after/before)*100:.1f}%")
        self.logger.info("  ✓ fastp complete")
        
        # Store paths for next step
        self.trimmed_r1 = out_r1
        self.trimmed_r2 = out_r2
        
    def step2_minimap2(self):
        """Step 2: Primary host removal with minimap2"""
        self.logger.info("\n→ Step 2: Primary host removal (minimap2)...")
        
        bam_file = self.paths['aligned'] / f"{self.args.sample_name}_minimap2.bam"
        sorted_bam = self.paths['aligned'] / f"{self.args.sample_name}_minimap2_sorted.bam"
        
        # OUTPUT 1 files
        self.output1_r1 = self.paths['cleaned'] / "NONHUMAN_PE_ASSEMBLY_R1.fastq.gz"
        self.output1_r2 = self.paths['cleaned'] / "NONHUMAN_PE_ASSEMBLY_R2.fastq.gz"
        
        # Align with minimap2
        self.logger.info("  Aligning to human reference...")
        cmd = f"""minimap2 -ax sr -t {self.args.threads} \
            {self.args.minimap2_index} \
            {self.trimmed_r1} {self.trimmed_r2} 2>/dev/null | \
            samtools view -@ {self.args.threads} -b -o {bam_file}"""
        
        self.run_command(cmd, "minimap2 alignment")
        
        # Sort by name for paired extraction
        self.logger.info("  Sorting BAM by name...")
        cmd = f"samtools sort -n -@ {self.args.threads} -o {sorted_bam} {bam_file}"
        self.run_command(cmd, "BAM sorting")
        
        # Extract unmapped pairs (non-human)
        self.logger.info("  Extracting non-human reads...")
        cmd = f"""samtools view -@ {self.args.threads} -b -f 12 -F 256 {sorted_bam} | \
            samtools fastq -@ {self.args.threads} \
            -1 {self.output1_r1} -2 {self.output1_r2} \
            -0 /dev/null -s /dev/null -n 2>&1"""
        
        self.run_command(cmd, "Extracting non-human reads")
        
        # Get alignment stats
        flagstat = self.run_command(
            f"samtools flagstat {sorted_bam}",
            "Getting alignment statistics",
            capture_output=True
        )
        
        lines = flagstat.strip().split('\n')
        total_reads = int(lines[0].split()[0])
        mapped_reads = int(lines[4].split()[0])
        
        cleaned_pairs = self.count_reads(self.output1_r1)
        
        self.stats['human_reads'] = mapped_reads
        self.stats['human_percentage'] = (mapped_reads/total_reads)*100
        self.stats['after_minimap2'] = cleaned_pairs
        
        self.logger.info(f"  Total reads:    {total_reads:>12,}")
        self.logger.info(f"  Human (mapped): {mapped_reads:>12,} ({self.stats['human_percentage']:5.1f}%)")
        self.logger.info(f"  Non-human:      {cleaned_pairs:>12,}")
        self.logger.info("  ✓ minimap2 complete")
        
        # Cleanup intermediate files
        if not self.args.keep_intermediates:
            os.remove(bam_file)
            
    def step3_convert_to_se(self):
        """Step 3: Convert paired-end to single-end (interleaved)"""
        self.logger.info("\n→ Step 3: Converting to single-end format...")
        
        self.interleaved = self.paths['cleaned'] / f"{self.args.sample_name}_interleaved.fastq.gz"
        
        # Concatenate R1 and R2
        cmd = f"cat {self.output1_r1} {self.output1_r2} > {self.interleaved}"
        self.run_command(cmd, "Concatenating paired reads")
        
        se_count = self.count_reads(self.interleaved)
        self.logger.info(f"  Single-end reads: {se_count:,}")
        self.logger.info("  ✓ Conversion complete")
        
    def step4_complexity_filter(self):
        """Step 4: Complexity filtering with BBDuk"""
        self.logger.info("\n→ Step 4: Complexity filtering (BBDuk)...")
        
        self.complex_filtered = self.paths['cleaned'] / f"{self.args.sample_name}_complex.fastq.gz"
        
        cmd = f"""bbduk.sh \
            in={self.interleaved} \
            out={self.complex_filtered} \
            entropy=0.7 \
            threads={self.args.threads} \
            -Xmx8g \
            2>&1 | grep -E "Input:|Result:" || true"""
        
        self.run_command(cmd, "BBDuk complexity filtering")
        
        count = self.count_reads(self.complex_filtered)
        self.stats['after_complexity_filter'] = count
        self.logger.info(f"  Reads after filtering: {count:,}")
        self.logger.info("  ✓ Complexity filtering complete")
        
    def step5_length_filter(self):
        """Step 5: Length filtering with BBDuk"""
        self.logger.info("\n→ Step 5: Length filtering...")
        
        self.length_filtered = self.paths['cleaned'] / f"{self.args.sample_name}_length70.fastq.gz"
        
        cmd = f"""bbduk.sh \
            in={self.complex_filtered} \
            out={self.length_filtered} \
            minlen=70 \
            threads={self.args.threads} \
            -Xmx8g \
            2>&1 | grep -E "Input:|Result:" || true"""
        
        self.run_command(cmd, "BBDuk length filtering")
        
        count = self.count_reads(self.length_filtered)
        self.stats['after_length_filter'] = count
        self.logger.info(f"  Reads after filtering: {count:,}")
        self.logger.info("  ✓ Length filtering complete")
        
    def step6_bowtie2(self):
        """Step 6: Secondary host removal with Bowtie2 (aggressive)"""
        self.logger.info("\n→ Step 6: Secondary host removal (Bowtie2 aggressive)...")
        
        sam_file = self.paths['aligned'] / f"{self.args.sample_name}_bowtie2.sam"
        bam_file = self.paths['aligned'] / f"{self.args.sample_name}_bowtie2.bam"
        sorted_bam = self.paths['aligned'] / f"{self.args.sample_name}_bowtie2_sorted.bam"
        unmapped_fq = self.paths['cleaned'] / f"{self.args.sample_name}_bt2_unmapped.fastq.gz"
        
        # Aggressive alignment - output to SAM first
        self.logger.info("  Running aggressive Bowtie2 alignment...")
        cmd = f"""bowtie2 \
            -x {self.args.bowtie2_index} \
            -U {self.length_filtered} \
            --very-sensitive-local \
            -p {self.args.threads} \
            -S {sam_file} \
            2>&1 | grep -E 'reads; of these:|aligned'
            """
        
        self.run_command(cmd, "Bowtie2 alignment")
        
        # Convert SAM to BAM
        self.logger.info("  Converting to BAM...")
        cmd = f"samtools view -@ {self.args.threads} -b -o {bam_file} {sam_file}"
        self.run_command(cmd, "SAM to BAM conversion")
        
        # Remove SAM to save space
        os.remove(sam_file)
        
        # Sort
        self.logger.info("  Sorting BAM...")
        cmd = f"samtools sort -@ {self.args.threads} -o {sorted_bam} {bam_file}"
        self.run_command(cmd, "BAM sorting")
        
        # Extract unmapped (non-human)
        self.logger.info("  Extracting non-human reads...")
        cmd = f"""samtools view -@ {self.args.threads} -b -f 4 {sorted_bam} | \
            samtools fastq -@ {self.args.threads} - | \
            gzip > {unmapped_fq}"""
        
        self.run_command(cmd, "Extracting unmapped reads")
        
        count = self.count_reads(unmapped_fq)
        self.stats['after_bowtie2'] = count
        self.logger.info(f"  Non-human reads: {count:,}")
        self.logger.info("  ✓ Bowtie2 complete")
        
        self.bt2_unmapped = unmapped_fq
        
        # Cleanup
        if not self.args.keep_intermediates:
            os.remove(bam_file)
            
    def step7_normalize(self):
        """Step 7: Post-alignment normalization"""
        self.logger.info("\n→ Step 7: Post-alignment normalization...")
        
        # OUTPUT 2 file
        self.output2 = self.paths['cleaned'] / "NONHUMAN_SE_PROFILING.fastq.gz"
        
        # BBDuk for quality filtering and length normalization
        # Note: BBDuk doesn't have maxhomopolymer, we use entropy instead
        cmd = f"""bbduk.sh \
            in={self.bt2_unmapped} \
            out={self.output2} \
            entropy=0.8 \
            minlength=75 \
            maxlength=200 \
            threads={self.args.threads} \
            -Xmx8g"""
        
        self.run_command(cmd, "BBDuk normalization")
        
        count = self.count_reads(self.output2)
        self.stats['output2_reads'] = count
        self.logger.info(f"  OUTPUT 2 reads: {count:,}")
        self.logger.info("  ✓ Normalization complete")
        
    def step8_gdpr_filter(self):
        """Step 8: GDPR-compliant strict filtering"""
        self.logger.info("\n→ Step 8: GDPR strict filtering...")
        
        # OUTPUT 3 file
        self.output3 = self.paths['cleaned'] / "NONHUMAN_STRICT_GDPR.fastq.gz"
        
        # Even stricter entropy and length filtering for GDPR compliance
        cmd = f"""bbduk.sh \
            in={self.output2} \
            out={self.output3} \
            entropy=0.85 \
            minlength=90 \
            threads={self.args.threads} \
            -Xmx8g"""
        
        self.run_command(cmd, "BBDuk GDPR filtering")
        
        count = self.count_reads(self.output3)
        self.stats['output3_reads'] = count
        self.logger.info(f"  OUTPUT 3 reads: {count:,}")
        self.logger.info("  ✓ GDPR filtering complete")
        
    def generate_reports(self):
        """Generate final reports and statistics"""
        self.logger.info("\n→ Generating reports...")
        
        # Save JSON stats
        stats_file = self.paths['stats'] / f"{self.args.sample_name}_stats.json"
        self.stats['pipeline_end'] = datetime.now().isoformat()
        
        with open(stats_file, 'w') as f:
            json.dump(self.stats, f, indent=2)
            
        self.logger.info(f"  ✓ Statistics saved: {stats_file}")
        
        # Run MultiQC if available
        try:
            cmd = f"multiqc {self.args.output_dir} -o {self.paths['stats']} " \
                  f"-n {self.args.sample_name}_multiqc --force --quiet 2>&1"
            self.run_command(cmd, "MultiQC report generation")
            self.logger.info("  ✓ MultiQC report generated")
        except:
            self.logger.warning("  ⚠️  MultiQC not available, skipping")
            
    def print_summary(self):
        """Print final summary"""
        self.logger.info("\n" + "="*80)
        self.logger.info("📊 PIPELINE SUMMARY")
        self.logger.info("="*80)
        
        self.logger.info(f"\nInput:")
        self.logger.info(f"  Raw read pairs:        {self.stats['raw_read_pairs']:>12,}")
        
        self.logger.info(f"\nOutputs:")
        self.logger.info(f"  OUTPUT 1 (Assembly):   {self.stats['after_minimap2']:>12,} pairs")
        self.logger.info(f"  OUTPUT 2 (Kraken2):    {self.stats['output2_reads']:>12,} reads")
        self.logger.info(f"  OUTPUT 3 (GDPR):       {self.stats['output3_reads']:>12,} reads")
        
        self.logger.info(f"\nContamination:")
        self.logger.info(f"  Human reads removed:   {self.stats['human_reads']:>12,}")
        self.logger.info(f"  Human percentage:      {self.stats['human_percentage']:>11.2f}%")
        
        self.logger.info(f"\nOutput Files:")
        self.logger.info(f"  {self.output1_r1}")
        self.logger.info(f"  {self.output1_r2}")
        self.logger.info(f"  {self.output2}")
        self.logger.info(f"  {self.output3}")
        
        self.logger.info(f"\nRuntime: {self.stats['total_runtime_seconds']/60:.1f} minutes")
        self.logger.info("="*80)


def main():
    parser = argparse.ArgumentParser(
        description='HostBuster - Human DNA Decontamination Pipeline for Metagenomic Data',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Basic usage
  %(prog)s --input-r1 sample_R1.fq.gz --input-r2 sample_R2.fq.gz \\
           --output-dir results/ --sample-name my_sample

  # With custom indices
  %(prog)s --input-r1 sample_R1.fq.gz --input-r2 sample_R2.fq.gz \\
           --output-dir results/ --sample-name my_sample \\
           --minimap2-index ref/human.mmi \\
           --bowtie2-index ref/human_bt2
        """
    )
    
    # Required arguments
    required = parser.add_argument_group('required arguments')
    required.add_argument('--input-r1', required=True,
                         help='Input R1 FASTQ file (can be gzipped)')
    required.add_argument('--input-r2', required=True,
                         help='Input R2 FASTQ file (can be gzipped)')
    required.add_argument('--output-dir', required=True,
                         help='Output directory for results')
    required.add_argument('--sample-name', required=True,
                         help='Sample name for output files')
    
    # Reference genome arguments
    ref_group = parser.add_argument_group('reference genome')
    ref_group.add_argument('--minimap2-index', 
                          default='reference/indices/human.mmi',
                          help='Path to minimap2 index (default: reference/indices/human.mmi)')
    ref_group.add_argument('--bowtie2-index',
                          default='reference/indices/human_bt2',
                          help='Path to Bowtie2 index prefix (default: reference/indices/human_bt2)')
    
    # Optional arguments
    optional = parser.add_argument_group('optional arguments')
    optional.add_argument('--threads', type=int, default=4,
                         help='Number of CPU threads (default: 4)')
    optional.add_argument('--keep-intermediates', action='store_true',
                         help='Keep intermediate BAM files (default: delete)')
    
    args = parser.parse_args()
    
    # Validate indices exist
    if not os.path.exists(args.minimap2_index):
        parser.error(f"Minimap2 index not found: {args.minimap2_index}")
    if not any(os.path.exists(f"{args.bowtie2_index}.{i}.bt2") for i in [1, 2, 3, 4]):
        parser.error(f"Bowtie2 index not found: {args.bowtie2_index}.*")
    
    # Run pipeline
    pipeline = HostBuster(args)
    pipeline.run()


if __name__ == '__main__':
    main()
