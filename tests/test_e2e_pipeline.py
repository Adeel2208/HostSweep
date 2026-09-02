"""End-to-end pipeline test against a tiny decoy reference.

The full T2T-CHM13v2.0 index is ~3 GB to download and 20-40 minutes to build,
which is not viable in CI. Instead this module simulates a ~24 kb decoy "host"
genome, draws reads from it, mixes in random non-host reads, builds real
minimap2 and Bowtie2 indices over the decoy, and runs the actual pipeline.
Every stage runs unmodified -- only the reference is small.

Skipped automatically unless fastp, minimap2, bowtie2, bowtie2-build, samtools
and bbduk.sh are all on PATH. See tests/README.md.
"""
import argparse
import gzip
import os
import random
import shutil
import sys
from pathlib import Path

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

REQUIRED_TOOLS = ("fastp", "minimap2", "bowtie2", "bowtie2-build",
                  "samtools", "bbduk.sh")

MISSING = [t for t in REQUIRED_TOOLS if shutil.which(t) is None]

requires_tools = pytest.mark.skipif(
    bool(MISSING),
    reason="external tools not on PATH: " + ", ".join(MISSING)
)

READ_LEN = 150
N_HOST_PAIRS = 40
N_OTHER_PAIRS = 40


def _revcomp(seq):
    return seq.translate(str.maketrans("ACGT", "TGCA"))[::-1]


def _write_fasta(path, seq, name="decoy_chr1"):
    with open(path, "w") as fh:
        fh.write(">" + name + "\n")
        for i in range(0, len(seq), 60):
            fh.write(seq[i:i + 60] + "\n")


def _fastq_record(name, seq):
    qual = "I" * len(seq)
    return "@" + name + "\n" + seq + "\n+\n" + qual + "\n"


def build_fixture(workdir, seed=1234):
    """Create decoy reference + a paired FASTQ mixing host and non-host reads."""
    rng = random.Random(seed)
    workdir = Path(workdir)
    workdir.mkdir(parents=True, exist_ok=True)

    # Random sequence has high entropy, so these reads clear the complexity
    # filters and are removed on alignment merit alone.
    genome = "".join(rng.choice("ACGT") for _ in range(24000))
    ref = workdir / "decoy.fasta"
    _write_fasta(ref, genome)

    r1_path = workdir / "sample_R1.fastq.gz"
    r2_path = workdir / "sample_R2.fastq.gz"

    with gzip.open(r1_path, "wt") as o1, gzip.open(r2_path, "wt") as o2:
        # Host-derived pairs: exact substrings of the decoy, so both aligners
        # map them and the pipeline should drop them.
        for i in range(N_HOST_PAIRS):
            start = rng.randrange(0, len(genome) - 400)
            frag = genome[start:start + 400]
            name = "HSh_%06d" % i
            o1.write(_fastq_record(name, frag[:READ_LEN]))
            o2.write(_fastq_record(name, _revcomp(frag[-READ_LEN:])))

        # Non-host pairs: independent random sequence, should survive.
        for i in range(N_OTHER_PAIRS):
            s1 = "".join(rng.choice("ACGT") for _ in range(READ_LEN))
            s2 = "".join(rng.choice("ACGT") for _ in range(READ_LEN))
            name = "HSb_%06d" % i
            o1.write(_fastq_record(name, s1))
            o2.write(_fastq_record(name, s2))

    return ref, r1_path, r2_path


def make_args(r1, r2, sample, outdir, index_name):
    """Mirror the defaults that cli.py installs."""
    return argparse.Namespace(
        input_r1=str(r1), input_r2=str(r2),
        sample_name=sample, output_dir=str(outdir),
        index_name=index_name,
        threads=1,
        fastp_tail=20, fastp_phred=15, min_length=50, fastp_complexity=30,
        bbduk_entropy=0.7, bbduk_stringent_entropy=0.85,
        bbduk_min_length=50, stringent_min_length=90,
        verbose=False, keep_intermediates=True,
    )


def _prepare_run(tmp_path, monkeypatch):
    """Build the decoy index and run the pipeline; return the output dir."""
    from hostsweep.database import DatabaseManager
    from hostsweep.pipeline import HostSweep

    # DatabaseManager() is constructed without arguments inside the pipeline,
    # so redirect it at the environment level.
    env_dir = tmp_path / "env"
    env_dir.mkdir()
    monkeypatch.setenv("CONDA_PREFIX", str(env_dir))
    # Keep BBDuk's JVM inside a CI-sized runner.
    monkeypatch.setenv("HOSTSWEEP_BBDUK_MEM", "1g")

    ref, r1, r2 = build_fixture(tmp_path / "fixture")
    DatabaseManager().build_custom_index("decoy", str(ref), threads=1)

    outdir = tmp_path / "results"
    HostSweep(make_args(r1, r2, "tinysample", outdir, "decoy")).run()
    return outdir


@requires_tools
def test_end_to_end_produces_three_tiers(tmp_path, monkeypatch):
    """Paired FASTQ in, four cleaned output files out."""
    from hostsweep.utils import count_reads

    outdir = _prepare_run(tmp_path, monkeypatch)
    cleaned = outdir / "cleaned"

    expected = [
        cleaned / "tinysample_ASSEMBLY_R1.fastq.gz",
        cleaned / "tinysample_ASSEMBLY_R2.fastq.gz",
        cleaned / "tinysample_PROFILING.fastq.gz",
        cleaned / "tinysample_STRINGENT.fastq.gz",
    ]
    for path in expected:
        assert path.exists(), "missing expected output: %s" % path
        # Every cleaned output is named .fastq.gz, so every one must be real
        # gzip: the PE tier gets compression from samtools' own suffix handling,
        # the SE tiers from an explicit gzip stage and from BBDuk.
        with open(path, "rb") as fh:
            assert fh.read(2) == b"\x1f\x8b", "%s is not gzip-compressed" % path

    # No output may carry the retired GDPR name.
    assert not list(cleaned.glob("*GDPR*"))

    # The pipeline must actually do something: keep non-host reads and drop
    # host-derived ones.
    assembly = count_reads(expected[0])
    assert assembly > 0, "assembly tier is empty; nothing survived"
    assert assembly < N_HOST_PAIRS + N_OTHER_PAIRS, "nothing was removed"

    # Tiers are nested by construction.
    profiling = count_reads(expected[2])
    stringent = count_reads(expected[3])
    assert stringent <= profiling


@requires_tools
def test_bowtie2_intermediate_is_real_gzip(tmp_path, monkeypatch):
    """Regression test for the samtools fastq / .gz mismatch.

    The Bowtie2 unmapped intermediate is named *.fastq.gz. It previously held
    plain text, so count_reads() raised BadGzipFile here. This asserts on the
    bytes actually written, so it holds however the command compresses them.
    """
    from hostsweep.utils import count_reads

    outdir = _prepare_run(tmp_path, monkeypatch)
    intermediate = outdir / "filtered" / "tinysample_bt2_unmapped.fastq.gz"
    assert intermediate.exists()

    # Must be a real gzip member, not text behind a .gz suffix.
    with open(intermediate, "rb") as fh:
        assert fh.read(2) == b"\x1f\x8b", "intermediate is not gzip-compressed"

    # And the function that used to crash must now succeed.
    count_reads(intermediate)


def test_extract_unmapped_single_compresses_gz_output():
    """Unit-level guard for the fix; runs without any external tools.

    A .gz destination must go through an explicit gzip stage. The old command
    shell-redirected samtools' uncompressed stdout straight into the .gz name.
    """
    cmd = _capture_extract_single("/out/sample_bt2_unmapped.fastq.gz")

    assert "samtools fastq" in cmd, cmd
    assert cmd.rstrip().endswith("| gzip > /out/sample_bt2_unmapped.fastq.gz"), cmd


def test_extract_unmapped_single_plain_output_is_not_gzipped():
    """A destination without .gz must stay uncompressed."""
    cmd = _capture_extract_single("/out/sample_bt2_unmapped.fastq")

    assert "gzip" not in cmd, cmd
    assert cmd.rstrip().endswith("> /out/sample_bt2_unmapped.fastq"), cmd


def _capture_extract_single(output_path):
    """Run extract_unmapped_single with run_command stubbed; return the command."""
    from hostsweep import aligners

    captured = {}

    def fake_run_command(cmd, description, **kwargs):
        captured["cmd"] = cmd
        return None

    original = aligners.run_command
    aligners.run_command = fake_run_command
    try:
        aligners.extract_unmapped_single("in.sam", output_path, 4, logger=None)
    finally:
        aligners.run_command = original

    return captured["cmd"]


def test_no_gdpr_in_cli_help(capsys):
    """CLI help must not mention GDPR (journal requirement)."""
    from hostsweep import cli

    argv = sys.argv
    sys.argv = ["hostsweep", "--help"]
    try:
        with pytest.raises(SystemExit):
            cli.main()
    finally:
        sys.argv = argv

    help_text = capsys.readouterr().out
    assert "gdpr" not in help_text.lower()
    assert "--stringent-minlen" in help_text


def test_stringent_output_name_has_no_gdpr():
    """The Step 8 output filename must be _STRINGENT, not _GDPR."""
    source = Path(__file__).resolve().parent.parent / "hostsweep" / "pipeline.py"
    text = source.read_text()
    assert "_STRINGENT.fastq.gz" in text
    assert "GDPR" not in text


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
