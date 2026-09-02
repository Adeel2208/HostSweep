# Tests

```bash
conda activate hostsweep
pip install -e ..
pytest tests/ -v
```

## Two tiers of test

**Unit tests** (`test_pipeline.py`, plus the non-gated tests in
`test_e2e_pipeline.py`) need only Python. They cover the stats collector, the
database manager, read counting, the CLI surface, and the shape of the
`samtools fastq` command. These run everywhere, including CI.

**End-to-end tests** (`test_end_to_end_produces_three_tiers`,
`test_bowtie2_intermediate_is_real_gzip`) run the real pipeline and are skipped
unless all of `fastp`, `minimap2`, `bowtie2`, `bowtie2-build`, `samtools` and
`bbduk.sh` are on PATH. `conda env create -f ../environment.yml` provides all
six.

## How the e2e test avoids the 3 GB reference

Building the T2T-CHM13v2.0 index takes a ~3 GB download and 20-40 minutes, so
the e2e test generates a **~24 kb decoy host genome** instead, then builds real
minimap2 and Bowtie2 indices over it via `DatabaseManager.build_custom_index`.
`CONDA_PREFIX` is monkeypatched to a `tmp_path` so nothing touches the user's
real index directory.

The fixture is 80 read pairs: 40 drawn as exact substrings of the decoy (these
should be removed) and 40 of independent random sequence (these should
survive). Read names carry an `HSh_`/`HSb_` origin prefix, the same convention
`benchmark/scripts/mix_spikein.py` uses. Every pipeline stage runs unmodified —
only the reference is small — so the test exercises fastp, both aligners,
samtools extraction and all four BBDuk passes.

`HOSTSWEEP_BBDUK_MEM=1g` is set so BBDuk's JVM fits a CI runner; the pipeline
defaults to `8g`.

## Running the e2e test locally

```bash
conda env create -f ../environment.yml
conda activate hostsweep
pip install -e ..
pytest tests/test_e2e_pipeline.py -v
```

Expect roughly a minute; almost all of it is `bowtie2-build`.

## Regression coverage for the samtools/gzip bug

`extract_unmapped_single` used to shell-redirect uncompressed `samtools fastq`
stdout into a `*.fastq.gz` path, so the next `count_reads()` call raised
`BadGzipFile` and the pipeline died at Step 6. Two tests guard the fix:

- `test_extract_unmapped_single_writes_named_output` — no external tools
  needed; asserts the output path is passed to samtools as `-0 <path>` rather
  than shell-redirected, so samtools applies gzip from the `.gz` suffix.
- `test_bowtie2_intermediate_is_real_gzip` — full run; asserts the
  intermediate starts with the gzip magic bytes `1f 8b` and that
  `count_reads()` reads it without error.

A full-scale run against the real T2T index is not automated; verify it as
described in the repository README before a release.
