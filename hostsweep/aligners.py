"""Alignment wrapper functions"""
import os
from .utils import run_command


def run_minimap2(ref_index, input_r1, input_r2, output_bam, threads, logger, verbose=False):
    """Run minimap2 alignment"""
    cmd = f"""minimap2 -ax sr -t {threads} \
        {ref_index} {input_r1} {input_r2} | \
        samtools view -@ {threads} -b -o {output_bam}"""

    run_command(cmd, "minimap2 alignment", verbose=verbose, logger=logger)


def run_bowtie2(ref_index, input_fastq, output_sam, threads, logger, verbose=False):
    """Run bowtie2 alignment"""
    cmd = f"""bowtie2 \
        -x {ref_index} \
        -U {input_fastq} \
        --very-sensitive-local \
        -p {threads} \
        -S {output_sam}"""

    run_command(cmd, "Bowtie2 alignment", verbose=verbose, logger=logger)


def sort_bam(input_bam, output_bam, threads, by_name=False, logger=None, verbose=False):
    """Sort BAM file"""
    sort_flag = "-n" if by_name else ""
    cmd = f"samtools sort {sort_flag} -@ {threads} -o {output_bam} {input_bam}"
    run_command(cmd, "BAM sorting", verbose=verbose, logger=logger)


def extract_unmapped_pairs(sorted_bam, output_r1, output_r2, threads, logger, verbose=False):
    """Extract unmapped read pairs from a name-sorted BAM.

    samtools opens the -1/-2 paths through hts_open, which turns on gzip
    compression when the filename ends in .gz or .bgzf. These paths therefore
    receive genuinely compressed FASTQ, matching the .fastq.gz names the
    pipeline gives them -- no mismatch here (verified against samtools >=1.17,
    the floor set in environment.yml).
    """
    cmd = f"""samtools view -@ {threads} -b -f 12 -F 256 {sorted_bam} | \
        samtools fastq -@ {threads} \
        -1 {output_r1} -2 {output_r2} \
        -0 /dev/null -s /dev/null -n"""

    run_command(cmd, "Extract unmapped pairs", verbose=verbose, logger=logger)


def extract_unmapped_single(input_sam, output_fastq, threads, logger, verbose=False):
    """Extract unmapped reads from a single-end SAM into a FASTQ.

    The original `samtools fastq - > out.fastq.gz` redirect wrote plain text
    behind a .gz name, which made count_reads() and BBDuk fail on the result.
    Compression is now explicit -- an external gzip stage whenever the
    destination ends in .gz, a plain redirect otherwise. Doing it in the shell
    rather than leaning on samtools' filename-suffix detection keeps the
    behaviour identical across samtools builds.

    -n keeps read names verbatim (no /1 or /2 suffix), which the benchmark's
    origin labels depend on.
    """
    view  = f"samtools view -@ {threads} -b -f 4 {input_sam}"
    fastq = f"samtools fastq -@ {threads} -n -"

    if str(output_fastq).endswith('.gz'):
        full_cmd = f"{view} | {fastq} | gzip > {output_fastq}"
    else:
        full_cmd = f"{view} | {fastq} > {output_fastq}"

    run_command(full_cmd, "Extract unmapped single-end", verbose=verbose, logger=logger)


def get_alignment_stats(bam_file, logger=None, verbose=False):
    """Get alignment statistics from BAM using samtools flagstat"""
    from .utils import run_command as rc
    output = rc(f"samtools flagstat {bam_file}", "samtools flagstat",
                capture_output=True, verbose=verbose, logger=logger)
    return output
