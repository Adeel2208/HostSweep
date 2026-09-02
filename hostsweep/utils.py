"""Utility functions for HostSweep"""
import os
import gzip
import shutil
import subprocess
import logging

# Every alignment/extraction step is a shell pipeline. POSIX sh reports only the
# exit status of the last stage, so a failing samtools upstream of a succeeding
# samtools downstream would go unnoticed and leave a valid-but-empty file.
# bash's pipefail surfaces the first failure instead. Falls back to plain sh if
# bash is unavailable.
#
# Restricted to POSIX: on Windows, shell=True builds "%COMSPEC% /c <cmd>" and
# `executable` replaces COMSPEC, which would hand bash cmd.exe's flags. The
# pipeline's external tools are Linux/macOS-only anyway.
_BASH = shutil.which("bash") if os.name != "nt" else None


def count_reads(fastq_file):
    """Count reads in FASTQ file"""
    fastq_file = str(fastq_file)
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


def run_command(cmd, description, capture_output=False, verbose=False, logger=None):
    """Execute shell command with error handling"""
    if logger:
        logger.info(f"Running: {description}")
        logger.debug(f"Command: {cmd}")

    run_kwargs = {}
    if _BASH:
        cmd = f"set -o pipefail; {cmd}"
        run_kwargs['executable'] = _BASH

    try:
        if capture_output:
            result = subprocess.run(cmd, shell=True, capture_output=True,
                                  text=True, check=True, **run_kwargs)
            return result.stdout
        else:
            result = subprocess.run(cmd, shell=True, capture_output=True,
                                  text=True, check=True, **run_kwargs)
            if verbose and result.stdout and logger:
                logger.debug(f"stdout: {result.stdout}")
            if result.stderr and logger:
                logger.debug(f"stderr: {result.stderr}")
            return result
    except subprocess.CalledProcessError as e:
        if logger:
            logger.error(f"FAILED: {description}")
            logger.error(f"  stdout: {e.stdout}")
            logger.error(f"  stderr: {e.stderr}")
        raise SystemExit(f"Error in {description}: {e.stderr}")


def setup_logger(name, log_file, level=logging.INFO):
    """Create and configure logger"""
    logger = logging.getLogger(name)
    logger.setLevel(level)

    # Loggers are process-global, so a second HostSweep instance in the same
    # process would otherwise stack handlers and duplicate every line.
    for handler in list(logger.handlers):
        logger.removeHandler(handler)
        handler.close()

    # File handler
    fh = logging.FileHandler(log_file)
    fh.setLevel(level)

    # Console handler
    ch = logging.StreamHandler()
    ch.setLevel(logging.INFO)

    formatter = logging.Formatter(
        '%(asctime)s [%(levelname)s] %(message)s',
        datefmt='%Y-%m-%d %H:%M:%S'
    )
    fh.setFormatter(formatter)
    ch.setFormatter(formatter)

    logger.addHandler(fh)
    logger.addHandler(ch)
    return logger
