"""Command-line interface for DecontaMiner"""
import sys
import os
import argparse
import logging
import multiprocessing
from pathlib import Path
from . import __version__
from .database import DatabaseManager
from .pipeline import DecontaMiner


def main():
    parser = argparse.ArgumentParser(
        description=f'DecontaMiner v{__version__} - Advanced Human DNA Decontamination Pipeline',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Basic usage (standard index, auto-download if needed)
  decontaminer -1 sample_R1.fq.gz -2 sample_R2.fq.gz -n my_sample -o results/

  # With custom index
  decontaminer -1 sample_R1.fq.gz -2 sample_R2.fq.gz -n my_sample -o results/ -i custom_ref

  # Build custom index
  decontaminer --build --ix my_custom --ref my_reference.fasta -t 32

  # List available indices
  decontaminer --lx

For more information: https://github.com/Adeel2208/Host_Buster
        """
    )

    # ── Mode selection ────────────────────────────────────
    mode_group = parser.add_mutually_exclusive_group()
    mode_group.add_argument('--build', action='store_true',
                           help='Build custom index database')
    mode_group.add_argument('--list-index', '--lx', action='store_true',
                           help='List available index databases')

    # ── Core I/O ─────────────────────────────────────────
    parser.add_argument('-1', '--r1', dest='input_r1', metavar='FILE',
                       help='Input R1 FASTQ file (gzipped)')
    parser.add_argument('-2', '--r2', dest='input_r2', metavar='FILE',
                       help='Input R2 FASTQ file (gzipped)')
    parser.add_argument('-n', '--name', dest='sample_name', metavar='NAME',
                       help='Sample name (used in output filenames)')
    parser.add_argument('-o', '--output', dest='output_dir', metavar='DIR',
                       help='Output directory')

    # ── Index selection ──────────────────────────────────
    parser.add_argument('-i', '--index', dest='index_name', default='standard',
                       help='Index database name (default: standard)')
    parser.add_argument('--ix', dest='custom_index_name', metavar='NAME',
                       help='Name for new custom index (use with --build)')
    parser.add_argument('--ref', dest='ref_fasta', metavar='FASTA',
                       help='Reference FASTA for custom index build')

    # ── Threading ────────────────────────────────────────
    parser.add_argument('-t', '--threads', type=int,
                       default=min(multiprocessing.cpu_count(), 8),
                       help=f'Number of threads (default: {min(multiprocessing.cpu_count(), 8)})')

    # ── fastp parameters ─────────────────────────────────
    parser.add_argument('--tail', dest='fastp_tail', type=int, default=20,
                       help='fastp cut_tail_mean_quality (default: 20)')
    parser.add_argument('--p', dest='fastp_phred', type=int, default=15,
                       help='fastp qualified_quality_phred (default: 15)')
    parser.add_argument('--l', dest='min_length', type=int, default=50,
                       help='Minimum read length (default: 50)')
    parser.add_argument('--complexity', dest='fastp_complexity', type=int, default=30,
                       help='fastp complexity threshold (default: 30)')

    # ── BBDuk parameters ─────────────────────────────────
    parser.add_argument('--bbe', dest='bbduk_entropy', type=float, default=0.7,
                       help='BBDuk entropy for complexity/normalization (default: 0.7)')
    parser.add_argument('--bbeg', dest='bbduk_gdpr_entropy', type=float, default=0.85,
                       help='BBDuk entropy for GDPR filter (default: 0.85)')
    parser.add_argument('--bblen', dest='bbduk_min_length', type=int, default=50,
                       help='BBDuk minimum length filter (default: 50)')
    parser.add_argument('--gdpr-minlen', dest='gdpr_min_length', type=int, default=90,
                       help='GDPR output minimum read length (default: 90)')

    # ── Misc ─────────────────────────────────────────────
    parser.add_argument('-v', '--verbose', action='store_true',
                       help='Verbose output (debug logging)')
    parser.add_argument('--keep-intermediates', action='store_true',
                       help='Keep intermediate files (default: clean up)')
    parser.add_argument('--version', action='version', version=f'%(prog)s {__version__}')

    args = parser.parse_args()

    # ── Handle --lx (list indices) ───────────────────────
    if args.list_index:
        db = DatabaseManager()
        indices = db.list_indices()
        if not indices:
            print("No index databases found.")
            print("  Build standard:  decontaminer --build")
            print("  Build custom:    decontaminer --build --ix myname --ref ref.fa")
        else:
            print(f"{'Name':<20} {'Minimap2':<10} {'Bowtie2':<10} {'Reference'}")
            print("-" * 60)
            for idx in indices:
                print(f"{idx['name']:<20} {'Yes' if idx['minimap2'] else 'No':<10} "
                      f"{'Yes' if idx['bowtie2'] else 'No':<10} {idx['reference']}")
        sys.exit(0)

    # ── Handle --build ───────────────────────────────────
    if args.build:
        db = DatabaseManager()
        if args.custom_index_name and args.ref_fasta:
            # Custom index build
            if not os.path.exists(args.ref_fasta):
                print(f"Error: reference FASTA not found: {args.ref_fasta}")
                sys.exit(1)
            print(f"Building custom index '{args.custom_index_name}'...")
            db.build_custom_index(args.custom_index_name, args.ref_fasta, args.threads)
            print("Done.")
        else:
            # Standard index build (download T2T + build)
            print("Building standard index (T2T-CHM13v2.0)...")
            print("This will download ~3GB and may take 30-60 minutes.")
            db.build_standard_index(args.threads)
            print("Done.")
        sys.exit(0)

    # ── Validate required args for pipeline run ──────────
    required = ['input_r1', 'input_r2', 'sample_name', 'output_dir']
    missing = [r for r in required if getattr(args, r) is None]
    if missing:
        parser.print_help()
        print(f"\nError: missing required arguments: {', '.join(missing)}")
        sys.exit(1)

    # Validate input files exist
    for fkey in ('input_r1', 'input_r2'):
        fpath = getattr(args, fkey)
        if not os.path.exists(fpath):
            print(f"Error: input file not found: {fpath}")
            sys.exit(1)

    # ── Launch pipeline ──────────────────────────────────
    pipeline = DecontaMiner(args)
    pipeline.run()
