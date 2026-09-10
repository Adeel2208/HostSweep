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

Benchmark results will be published with the revised manuscript.

---

## Requirements

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| OS | Linux (Ubuntu 20.04+) or macOS | — |
| RAM | 8 GB | 16 GB+ |
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

`--gdpr-minlen` is retained as a hidden, deprecated alias for
`--stringent-minlen` so existing scripts keep working; it prints a deprecation
warning and will be removed in a future release.

### Environment variables

| Variable | Description | Default |
|----------|-------------|---------|
| `HOSTSWEEP_BBDUK_MEM` | JVM heap passed to BBDuk as `-Xmx` | `8g` |

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

The two passes exploit complementary algorithmic strengths:

- **minimap2 (Pass 1):** fast minimizer-based seeding detects the large
  majority of host reads and preserves paired-end structure.
- **Bowtie2 (Pass 2):** sensitive local alignment with dynamic programming
  recovers divergent, partially aligning, and polymorphic or low-complexity
  reads that minimizer seeding misses.

The size of the second pass's contribution, and the runtime it costs, will be
published with the revised manuscript.

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

### Benchmark datasets

**Real SRA libraries** — the panel is being rebuilt and verified against SRA; see [`benchmark/run/DEVIATIONS.md`](benchmark/run/DEVIATIONS.md).

**Synthetic controlled-truth libraries (12)** built from ART-simulated human
reads from T2T-CHM13v2.0 over CAMI II-style microbial backgrounds, at exact
spike-in fractions of 0.1%, 0.5%, 1%, 5%, 10%, 20% and 40%, plus libraries
covering non-European haplotype diversity from 1000 Genomes.

Benchmark results will be published with the revised manuscript.

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
