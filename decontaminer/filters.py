"""Quality filtering functions"""
from .utils import run_command


def run_fastp(input_r1, input_r2, output_r1, output_r2,
              json_out, html_out, args, logger):
    """Run fastp quality trimming"""
    cmd = f"""fastp \
        --in1 {input_r1} --in2 {input_r2} \
        --out1 {output_r1} --out2 {output_r2} \
        --detect_adapter_for_pe \
        --cut_tail --cut_tail_window_size 4 --cut_tail_mean_quality {args.fastp_tail} \
        --qualified_quality_phred {args.fastp_phred} \
        --length_required {args.min_length} \
        --low_complexity_filter --complexity_threshold {args.fastp_complexity} \
        --trim_poly_g --trim_poly_x \
        --thread {args.threads} \
        --json {json_out} --html {html_out}"""

    run_command(cmd, "fastp trimming", verbose=args.verbose, logger=logger)


def run_bbduk_complexity(input_file, output_file, entropy, threads, logger, verbose=False):
    """Run BBDuk complexity filtering"""
    cmd = f"""bbduk.sh \
        in={input_file} \
        out={output_file} \
        entropy={entropy} \
        threads={threads} \
        -Xmx8g"""

    run_command(cmd, "BBDuk complexity filtering", verbose=verbose, logger=logger)


def run_bbduk_length(input_file, output_file, min_length, threads, logger, verbose=False):
    """Run BBDuk length filtering"""
    cmd = f"""bbduk.sh \
        in={input_file} \
        out={output_file} \
        minlen={min_length} \
        threads={threads} \
        -Xmx8g"""

    run_command(cmd, "BBDuk length filtering", verbose=verbose, logger=logger)


def run_bbduk_normalize(input_file, output_file, entropy, threads, logger, verbose=False):
    """Run BBDuk normalization (entropy-based)"""
    cmd = f"""bbduk.sh \
        in={input_file} \
        out={output_file} \
        entropy={entropy} \
        threads={threads} \
        -Xmx8g"""

    run_command(cmd, "BBDuk normalization", verbose=verbose, logger=logger)


def run_bbduk_gdpr(input_file, output_file, entropy, min_length, threads, logger, verbose=False):
    """Run BBDuk GDPR strict filtering (entropy + length)"""
    cmd = f"""bbduk.sh \
        in={input_file} \
        out={output_file} \
        entropy={entropy} \
        minlen={min_length} \
        threads={threads} \
        -Xmx8g"""

    run_command(cmd, "BBDuk GDPR filtering", verbose=verbose, logger=logger)
