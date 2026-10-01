# HostSweep

**A modular dual-pass workflow for reducing human read content in Illumina metagenomic data**

[![Python](https://img.shields.io/badge/Python-3.9%2B-blue)](https://www.python.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Conda](https://img.shields.io/badge/Install-Conda-green)](https://docs.conda.io/)

HostSweep is a modular Python workflow that combines minimap2 and Bowtie2 in a two-pass alignment strategy against T2T-CHM13v2.0 to reduce human read content in Illumina paired-end metagenomic sequencing data. A single execution produces three tiered outputs suited to assembly, taxonomic profiling, and analyses that call for more aggressive complexity and length filtering.

> **Manuscript under revision** at *Bioinformatics Advances* (BIOADV-2026-394).
> Mukhtar, A., Tariq, U., and Khaliq, A.A. HostSweep: a modular dual-pass workflow for reducing human read content in Illumina metagenomic data.

### Scope and limitations

HostSweep is an integration and workflow tool: it sequences established
components (fastp, minimap2, Bowtie2, samtools, BBDuk) into a reproducible
pipeline. It **reduces the amount of detectable human sequence** in a dataset
under the conditions described below.

It does **not** certify that any output is free of human material, and no
output tier should be treated as establishing the absence of human sequence or
as sufficient on its own to discharge a legal, ethical, or data-protection
obligation. Decisions about data sharing remain the responsibility of the data
custodian and their governance framework.

Any alignment to a finite reference, including a pangenome, can only detect human reads that
resemble that reference. Reads carrying rare, private or population-specific variation are the
ones most likely to escape detection. This is an intrinsic limit of reference-based host removal.

---

## Key features

- **Dual-pass host removal** — minimap2 (fast approximate screening) followed by Bowtie2 (sensitive local alignment).
- **T2T-CHM13v2.0 reference** — the complete human assembly is used for both alignment passes.
- **Three tiered outputs** — assembly-grade paired-end reads, profiling-grade single-end reads, and a high-stringency complexity- and length-filtered single-end set, from one execution.
- **Automatic database management** — `hostsweep --build` downloads and indexes T2T-CHM13v2.0; custom references are supported.
- **Modular architecture** — nine focused Python modules, straightforward to extend or integrate.
- **Reproducible** — pure Python, a single conda environment, JSON statistics, complete logging, and a complete benchmark harness in [`benchmark/`](benchmark/).

---

## Benchmarks

Measured benchmark results for the revised manuscript are in
[`benchmark/run/RESULTS.md`](benchmark/run/RESULTS.md), with every departure from the
specified protocol logged in [`benchmark/run/DEVIATIONS.md`](benchmark/run/DEVIATIONS.md).
They include results that do not favour HostSweep; read the deviations file before quoting
any figure.

Summary of the synthetic benchmark (12 libraries, 3 runs per tool, 8 threads; mean across
libraries; full per-library tables and the exact definitions are in `RESULTS.md`):

| tool | sensitivity, matched arm (n = 9) | sensitivity, mismatch arm (n = 3) | microbial reads removed (FPR) | runtime, min per 2 M pairs | peak memory, GB |
|---|---|---|---|---|---|
| HostSweep | 100.0000 % | 99.9698 % | 0.0142 % | 5.68 | 11.39 |
| KneadData | 100.0000 % | 99.9692 % | 0.4255 % | 1.39 | 5.04 |
| BMTagger | 99.9999 % | 99.9456 % | 0.0002 % | 5.93 (1 thread) | 8.00 |
| Hostile (default) | 99.9998 % | 99.8665 % | 0.0000 % | 0.43 | 3.50 |
| Hostile (matched index) | 99.9998 % | 99.8646 % | 0.0000 % | 0.42 | 3.50 |

How to read this: on the matched arm every tool is at ceiling and the arm is circular for
HostSweep, so it cannot rank tools. On the mismatch arm HostSweep and KneadData are
indistinguishable on sensitivity, and both are ahead of BMTagger and Hostile. Hostile and
BMTagger are more specific, Hostile and KneadData are faster, and HostSweep uses the most memory.
FPR counts every microbial read missing from a tool's output, so it includes each tool's own
preprocessing (HostSweep: fastp; KneadData: Trimmomatic; Hostile: none). DeconSeq could not be
installed from bioconda and was not benchmarked.

---

## Requirements

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| OS | Linux (Ubuntu 20.04+) or macOS | — |
| RAM | 16 GB (measured peak 11.4–12.2 GB) | 32 GB+ |
| Storage | 50 GB free | 100 GB+ |
| CPU cores | 4 | 8+ |
| Python | 3.9+ | 3.10+ |

---

## Installation

### 1. Clone the repository

```bash
git clone https://github.com/Adeel2208/HostSweep.git
cd HostSweep
```

### 2. Create the conda environment

```bash
conda env create -f environment.yml
conda activate hostsweep
```

### 3. Install the `hostsweep` command

```bash
pip install -e .
hostsweep --version   # should print 1.0.0
```

### 4. Build the reference index

**Standard (T2T-CHM13v2.0 — downloads ~3 GB, builds in 20–40 min):**

```bash
hostsweep --build
```

**Custom reference:**

```bash
hostsweep --build --ix my_organism --ref /path/to/reference.fasta -t 8
```

**List available indices:**

```bash
hostsweep --lx
```

The name printed by `--lx` can be passed directly to `-i`.

---

## Usage

### Basic run

```bash
hostsweep \
  -1 sample_R1.fastq.gz \
  -2 sample_R2.fastq.gz \
  -n my_sample \
  -o results/my_sample \
  -t 8
```

### With a custom index

```bash
hostsweep \
  -1 sample_R1.fastq.gz \
  -2 sample_R2.fastq.gz \
  -n my_sample \
  -o results/my_sample \
  -i my_organism
```

### Keep intermediate files

```bash
hostsweep -1 R1.fq.gz -2 R2.fq.gz -n sample -o out/ --keep-intermediates
```

### All CLI options

| Flag | Description | Default |
|------|-------------|---------|
| `-1 / --r1` | R1 FASTQ (gzipped) | *required* |
| `-2 / --r2` | R2 FASTQ (gzipped) | *required* |
| `-n / --name` | Sample name | *required* |
| `-o / --output` | Output directory | *required* |
| `-i / --index` | Index name (`standard` or custom) | `standard` |
| `-t / --threads` | CPU threads | min(CPU count, 8) |
| `--tail` | fastp cut_tail_mean_quality | 20 |
| `--p` | fastp qualified_quality_phred | 15 |
| `--l` | Minimum read length | 50 |
| `--complexity` | fastp complexity threshold | 30 |
| `--bbe` | BBDuk entropy (profiling tier) | 0.70 |
| `--bbeg` | BBDuk entropy (high-stringency tier) | 0.85 |
| `--bblen` | BBDuk minimum length | 50 |
| `--stringent-minlen` | High-stringency output min length | 90 |
| `-v / --verbose` | Debug-level logging | off |
| `--keep-intermediates` | Don't delete temp files | off |

### Environment variables

| Variable | Description | Default |
|----------|-------------|---------|
| `HOSTSWEEP_BBDUK_MEM` | JVM heap passed to BBDuk as `-Xmx` | `8g` |

HostSweep's peak memory is set largely by the minimap2 index of the 3.1 Gb reference
(11.3–11.5 GB on 2 M-pair libraries, 11.3–12.2 GB on the real-library panel). On a machine with
less memory it may page heavily or fail; runtime measured under such conditions is not meaningful
(deviation D17).

Lower `HOSTSWEEP_BBDUK_MEM` on constrained machines (e.g. `export HOSTSWEEP_BBDUK_MEM=2g`) if BBDuk fails to start.

---

## Output files

All final outputs are in `<output_dir>/cleaned/`:

| File | Type | Use case |
|------|------|----------|
| `<sample>_ASSEMBLY_R1.fastq.gz` | Paired-end | Metagenome assembly, genome binning |
| `<sample>_ASSEMBLY_R2.fastq.gz` | Paired-end | (mate of above) |
| `<sample>_PROFILING.fastq.gz` | Single-end | Taxonomic profiling (Kraken2, MetaPhlAn) |
| `<sample>_STRINGENT.fastq.gz` | Single-end | Analyses calling for more aggressive complexity and length filtering |

The three tiers are nested: the high-stringency set is a subset of the
profiling set, which derives from the assembly-grade reads.

**Output 1 (assembly tier) has passed the minimap2 pass only, not the Bowtie2 pass.** In the
benchmark, minimap2 alone left about 0.09 % of simulated human reads (matched arm), whereas the
dual pass left none; Bowtie2 alone was almost as sensitive as the dual pass. If the lowest
residual human content matters more than paired-end structure, use the profiling tier. The
entropy and length thresholds of the high-stringency tier are empirical technical parameters,
not values derived from any privacy or re-identification model.

**QC & statistics:**

| File | Location | Description |
|------|----------|-------------|
| `<sample>_fastp.html` | `qc/` | Quality control report |
| `<sample>_fastp.json` | `qc/` | Machine-readable QC metrics |
| `<sample>_stats.json` | `stats/` | Per-step retention statistics |
| `hostsweep_<sample>.log` | output root | Complete execution log |

---

## Pipeline architecture

```
INPUT: Illumina Paired-end FASTQ (R1 + R2)
   │
   ▼
[Step 0] Input Validation
   │
   ▼
[Step 1] fastp — Adapter trimming, quality filtering, complexity screening
   │
   ▼
[Step 2] minimap2 (Pass 1) — Fast approximate alignment → extract unmapped pairs
   │
   ├──► OUTPUT 1: Assembly-grade PE reads (unmapped pairs) ──────────────────►
   │
   ▼
[Step 3] PE → SE Conversion — Concatenate R1 + R2 for single-end processing
   │
   ▼
[Step 4] BBDuk Complexity Filter — Entropy ≥ 0.70
   │
   ▼
[Step 5] BBDuk Length Filter — Length ≥ 50 bp
   │
   ▼
[Step 6] Bowtie2 (Pass 2) — Sensitive local alignment → extract unmapped reads
   │
   ▼
[Step 7] BBDuk Normalization — Entropy ≥ 0.70
   │
   ├──► OUTPUT 2: Profiling-grade SE reads ────────────────────────────────────►
   │
   ▼
[Step 8] BBDuk High-Stringency Filter — Entropy ≥ 0.85, Length ≥ 90 bp
   │
   └──► OUTPUT 3: High-stringency SE reads ────────────────────────────────────►
```

### Why dual-pass?

The two passes use different alignment strategies:

- **minimap2 (Pass 1):** fast minimizer-based seeding that preserves paired-end structure and
  yields the paired-end assembly-tier output.
- **Bowtie2 (Pass 2):** sensitive local alignment with dynamic programming, applied to the
  single-end reads that survive Pass 1.

What the ablation measured (12 synthetic libraries, `benchmark/run/RESULTS.md` section 3b):
minimap2 alone missed about 0.09 % of human reads on the matched arm (mean sensitivity
99.906 %); Bowtie2 alone missed about 0.0001 %; the dual pass missed none. On the mismatch arm
the mean sensitivities were 99.887 % (minimap2 only), 99.966 % (Bowtie2 only) and 99.970 % (dual).
So most of the sensitivity comes from the Bowtie2 pass, and adding minimap2 to Bowtie2 gives a
small gain on the mismatch arm. The dual pass also removed more microbial reads (FPR 0.0142 %)
than Bowtie2 alone (0.0056 %). Ablation runtimes were collected under a memory ceiling and are
not reported (deviation D17).

---

## Code architecture

```
HostSweep/                       ← Git repository root
├── setup.py                     ← pip installable package
├── environment.yml              ← conda dependencies
├── README.md                    ← this file
├── LICENSE                      ← MIT license
├── .github/
│   ├── workflows/ci.yml         ← unit, shell-lint and conda integration jobs
│   └── scripts/                 ← repository policy checks
├── benchmark/                   ← reproducibility harness (see below)
│   ├── README.md                ← how to reproduce every reported figure
│   ├── accessions.csv           ← real-library SRA panel
│   ├── scripts/                 ← mixing, download, run and scoring scripts
│   └── synthetic/               ← ART simulation protocol and seeds
├── tests/                       ← pytest suite (unit + end-to-end)
└── hostsweep/                   ← installable Python package
    ├── __init__.py              ← version, public API
    ├── __main__.py              ← python -m hostsweep
    ├── cli.py                   ← argparse command-line interface
    ├── database.py              ← reference download, indexing, versioning
    ├── pipeline.py              ← 8-step orchestrator (HostSweep class)
    ├── filters.py               ← fastp + BBDuk wrappers
    ├── aligners.py              ← minimap2, Bowtie2, samtools wrappers
    ├── stats.py                 ← JSON statistics collector
    └── utils.py                 ← logging, read counting, shell execution
```

---

## Reproducing the benchmarks

The complete harness lives in [`benchmark/`](benchmark/): scripts to build
controlled-truth spike-in libraries, download the real-library panel, run
HostSweep and each comparator, and compute sensitivity, false positive rate and
retention. See [`benchmark/README.md`](benchmark/README.md) to start, and
[`benchmark/synthetic/README.md`](benchmark/synthetic/README.md) for the ART
simulation protocol and seeds.

Moving the harness to a second machine to continue an interrupted run? See
[`benchmark/NEW_MACHINE.md`](benchmark/NEW_MACHINE.md) — one script
(`benchmark/scripts/bootstrap_new_machine.sh`) rebuilds the toolchain, the
reference index, the synthetic panel and the real-library panel from scratch,
checks that the new machine reproduces the old machine's numbers before
trusting it with anything else, and then runs whatever experiments are still
incomplete.

The clean timing run, the metaSPAdes downstream arm, CheckM2, the full Kraken2
Standard classification and the extra reference-mismatch donors run with one
command: see [`benchmark/REMAINING.md`](benchmark/REMAINING.md).

### Benchmark datasets

**Real SRA libraries (30)** — verified against SRA metadata, see [`benchmark/run/accessions_verified.csv`](benchmark/run/accessions_verified.csv) and [`benchmark/run/DEVIATIONS.md`](benchmark/run/DEVIATIONS.md). There is no per-read truth set for real libraries, so no accuracy figures are reported for them.

**Synthetic controlled-truth libraries (12)** of 2 M read pairs each, built from a
ten-genome bacterial community ([`benchmark/genomes.tsv`](benchmark/genomes.tsv)) and
ART-simulated human reads (profile `HS25`, 150 bp, seeds 42–53; human fractions 0.1–40 %).
Nine libraries use human reads simulated from T2T-CHM13v2.0, the same sequence HostSweep
screens against (*matched reference*, and therefore circular for HostSweep); three use reads
simulated from independent HPRC year-1 assemblies (HG00438, HG00733, NA19240;
*reference mismatch*). The truth label is each read's simulated origin, an operational
label from the simulation. The two arms are always reported separately.

Measured benchmark results for the revised manuscript are in
[`benchmark/run/RESULTS.md`](benchmark/run/RESULTS.md), with every departure from the
specified protocol logged in [`benchmark/run/DEVIATIONS.md`](benchmark/run/DEVIATIONS.md).
They include results that do not favour HostSweep (for example, Hostile and BMTagger
have lower false positive rates on the synthetic panel); read the deviations file
before quoting any figure.

---

## Testing

```bash
conda activate hostsweep
pip install -e .
pytest tests/ -v
```

Unit tests run anywhere. The end-to-end tests build a tiny decoy reference and
run the real pipeline; they skip automatically unless fastp, minimap2, bowtie2,
bowtie2-build, samtools and bbduk.sh are on PATH. See
[`tests/README.md`](tests/README.md) for details.

---

## Troubleshooting

**"Index 'standard' not found"**
Run `hostsweep --build` to download and index T2T-CHM13v2.0.

**"hostsweep: command not found"**
Ensure the conda environment is activated and the package is installed:
```bash
conda activate hostsweep
cd /path/to/HostSweep
pip install -e .
```

**Out of memory**
Reduce threads (`-t 2`) and lower BBDuk's heap (`export HOSTSWEEP_BBDUK_MEM=2g`).

**OUTPUT 2 / OUTPUT 3 have very few reads**
Your input may have short reads. Lower `--bblen` and `--stringent-minlen`.

**Very low retention on high-contamination samples**
Expected for blood and plasma samples, where human content is high. Use the
profiling-grade output for rare taxa.

---

## Contributing

Contributions are welcome:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/YourFeature`)
3. Commit your changes with clear messages
4. Ensure `pytest tests/ -v` passes
5. Open a Pull Request describing your changes

---

## Citation

The manuscript is under revision. Until it appears, please cite the repository:

```bibtex
@misc{mukhtar2026hostsweep,
  title        = {HostSweep: a modular dual-pass workflow for reducing human
                  read content in Illumina metagenomic data},
  author       = {Mukhtar, Adeel and Tariq, Umair and Khaliq, Awais Abdul},
  year         = {2026},
  note         = {Manuscript under revision at Bioinformatics Advances
                  (BIOADV-2026-394)},
  howpublished = {\url{https://github.com/Adeel2208/HostSweep}}
}
```

---

## License

MIT License — see [LICENSE](LICENSE) for details.

---

## Acknowledgments

- **T2T-CHM13 Consortium** for the complete human genome reference
- Developers of **minimap2** (Heng Li), **Bowtie2** (Langmead & Salzberg), **fastp** (Chen et al.), **BBTools** (Brian Bushnell), and **samtools** (Li et al.)
- **KneadData** (Huttenhower Lab), **Hostile** (Constantinides, Hunt & Crook), and the broader metagenomic decontamination community

---

## Related projects & tools

- [KneadData](https://github.com/biobakery/kneaddata) — single-pass Bowtie2 quality control
- [Hostile](https://github.com/bede/hostile) — single-pass short-read decontamination; defaults to Bowtie2 for paired short reads (minimap2 is its long-read path). Constantinides B, Hunt M, Crook DW (2023).
- [Kraken2](https://github.com/DerrickWood/kraken2) — k-mer taxonomic classification
- [MetaPhlAn](https://github.com/biobakery/MetaPhlAn) — marker-gene metagenomic profiling
- [metaSPAdes](https://github.com/ablab/spades) — metagenome assembler

---

## Contact

**Corresponding author:**
Umair Tariq — umair.tariq@bcu.ac.uk

**Contributors:**
- Adeel Mukhtar (University of Engineering and Technology, Pakistan)
- Awais Abdul Khaliq (Università degli Studi di Milano, Italy)