# HostSweep

**A modular dual-pass pipeline for human DNA decontamination in Illumina metagenomic data**

[![Python](https://img.shields.io/badge/Python-3.9%2B-blue)](https://www.python.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Conda](https://img.shields.io/badge/Install-Conda-green)](https://docs.conda.io/)

HostSweep is a fast, modular Python pipeline combining minimap2 and Bowtie2 in a two-pass alignment strategy against T2T-CHM13v2.0 to remove human DNA contamination from Illumina paired-end metagenomic sequencing data. It produces three tiered output formats optimized for assembly, taxonomic profiling, and GDPR-compliant repository deposition from a single execution.

> **Published in Bioinformatics, 2026**  
> Mukhtar, A., Tariq, U., and Khaliq, A.A. (2026). HostSweep: a modular dual-pass pipeline for human DNA decontamination in Illumina metagenomic data. *Bioinformatics*.

---

## 🚀 Key Features

- **Dual-Pass Host Removal** — minimap2 (fast approximate screening) followed by Bowtie2 (sensitive local alignment) recovers an additional 2.55% of contamination missed by single-pass approaches
- **T2T-CHM13v2.0 Reference** — Complete human genome reference captures 1.8–2.3% more contaminating reads than GRCh38
- **Three Tiered Outputs** — Assembly-grade paired-end reads, profiling-grade single-end reads, and entropy-gated GDPR-compliant reads from one execution
- **High Sensitivity** — 99.86% mean sensitivity on synthetic controlled-truth benchmarks, outperforming KneadData (96.24%), BMTagger (94.87%), DeconSeq (91.45%), and Hostile (99.41%)
- **Fast & Efficient** — 3.2× faster than KneadData with 39% less peak memory (6.8 GB vs. 11.2 GB)
- **Automatic Database Management** — `hostsweep --build` downloads and indexes T2T-CHM13v2.0; custom references supported
- **Modular Architecture** — Nine focused Python modules, easy to extend or integrate
- **Production Ready** — Pure Python, single conda environment, JSON stats, complete logging

---

## 📊 Performance Highlights

Validated on 42 benchmark datasets (30 real SRA libraries + 12 synthetic controlled-truth):

| Metric | HostSweep | Hostile | KneadData | BMTagger | DeconSeq |
|--------|-----------|---------|-----------|----------|----------|
| **Sensitivity** | **99.86%** | 99.41% | 96.24% | 94.87% | 91.45% |
| **Runtime** (SRR6062009, 1.86M pairs) | **11.2 min** | 13.6 min | 35.8 min | 28.4 min | 142.3 min |
| **Peak Memory** | **6.8 GB** | 6.5 GB | 11.2 GB | 14.7 GB | 8.9 GB |
| **False Positive Rate** | 2.76% | 2.91% | 3.82% | 5.23% | 7.41% |
| **Tiered Outputs** | ✅ Yes | ❌ No | ❌ No | ❌ No | ❌ No |

**Downstream Impact:**
- metaSPAdes assembly: 5.2% N50 improvement, 4× reduction in misassembly rate
- Kraken2 profiling: 0.00% residual human content vs. 0.03% for KneadData

---

## 📋 Requirements

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| OS | Linux (Ubuntu 20.04+) or macOS | — |
| RAM | 8 GB | 16 GB+ |
| Storage | 50 GB free | 100 GB+ |
| CPU cores | 4 | 8+ |
| Python | 3.9+ | 3.10+ |

---

## 🔧 Installation

### 1. Clone the Repository

```bash
git clone https://github.com/Adeel2208/HostSweep.git
cd HostSweep
```

### 2. Create Conda Environment

```bash
conda env create -f environment.yml
conda activate hostsweep
```

### 3. Install the `hostsweep` Command

```bash
pip install -e .
hostsweep --version   # should print 1.0.0
```

### 4. Build the Reference Index

**Standard (T2T-CHM13v2.0 — downloads ~3 GB, builds in 20-40 min):**

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

---

## 📖 Usage

### Basic Run

```bash
hostsweep \
  -1 sample_R1.fastq.gz \
  -2 sample_R2.fastq.gz \
  -n my_sample \
  -o results/my_sample \
  -t 8
```

### With a Custom Index

```bash
hostsweep \
  -1 sample_R1.fastq.gz \
  -2 sample_R2.fastq.gz \
  -n my_sample \
  -o results/my_sample \
  -i my_organism
```

### Keep Intermediate Files

```bash
hostsweep -1 R1.fq.gz -2 R2.fq.gz -n sample -o out/ --keep-intermediates
```

### All CLI Options

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
| `--bbeg` | BBDuk entropy (GDPR tier) | 0.85 |
| `--bblen` | BBDuk minimum length | 50 |
| `--gdpr-minlen` | GDPR output min length | 90 |
| `-v / --verbose` | Debug-level logging | off |
| `--keep-intermediates` | Don't delete temp files | off |

---

## 📊 Output Files

All final outputs are in `<output_dir>/cleaned/`:

| File | Type | Use Case |
|------|------|----------|
| `<sample>_ASSEMBLY_R1.fastq.gz` | Paired-end | Metagenome assembly, genome binning |
| `<sample>_ASSEMBLY_R2.fastq.gz` | Paired-end | (mate of above) |
| `<sample>_PROFILING.fastq.gz` | Single-end | Taxonomic profiling (Kraken2, MetaPhlAn) |
| `<sample>_GDPR.fastq.gz` | Single-end | Public repository deposition (SRA, ENA) |

**QC & Statistics:**

| File | Location | Description |
|------|----------|-------------|
| `<sample>_fastp.html` | `qc/` | Quality control report |
| `<sample>_fastp.json` | `qc/` | Machine-readable QC metrics |
| `<sample>_stats.json` | `stats/` | Per-step retention statistics |
| `hostsweep_<sample>.log` | output root | Complete execution log |

---

## 🔍 Pipeline Architecture

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
   │        (Recovers additional 2.55% of contamination)
   ▼
[Step 7] BBDuk Normalization — Entropy ≥ 0.70
   │
   ├──► OUTPUT 2: Profiling-grade SE reads ────────────────────────────────────►
   │
   ▼
[Step 8] BBDuk GDPR Filter — Entropy ≥ 0.85, Length ≥ 90 bp
   │
   └──► OUTPUT 3: GDPR-compliant SE reads ─────────────────────────────────────►
```

### Why Dual-Pass?

The dual-pass strategy exploits complementary algorithmic strengths:

- **minimap2 (Pass 1):** Fast minimizer-based seeding detects ~97.3% of host reads, preserves paired-end structure
- **Bowtie2 (Pass 2):** Sensitive local alignment with dynamic programming recovers the remaining 2.55%:
  - 42% divergent alignments (≥4 mismatches per seed window)
  - 31% partial alignments (40–80 bp in 150 bp reads)
  - 27% polymorphic or low-complexity reads

**Result:** Bowtie2-level sensitivity at 59% of Bowtie2-only runtime, 1.7× minimap2-only runtime.

---

## 🏗️ Code Architecture

```
HostSweep/                       ← Git repository root
├── setup.py                     ← pip installable package
├── environment.yml              ← conda dependencies
├── README.md                    ← this file
├── LICENSE                      ← MIT license
├── benchmark/                   ← performance evaluation data
├── tests/                       ← pytest test suite
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

## 🧪 Benchmarking

### Datasets

**Real SRA Libraries (30):**
- Environmental (soil, marine): 0.01–0.05% contamination
- Gut microbiome (HMP): 0.08–0.34%
- Oral (saliva, plaque): 0.21–1.97%
- Skin: 1.12–6.40%
- Respiratory (BAL, sputum): 4.18–15.78%
- Urogenital: 2.66–11.30%
- Blood (sepsis, cfDNA): 18.40–45.23%

**Synthetic Controlled-Truth Libraries (12):**
- ART-simulated human reads from T2T-CHM13v2.0
- CAMI II-style microbial backgrounds
- Exact spike-in fractions: 0.1%, 0.5%, 1%, 5%, 10%, 20%, 40%
- Non-European haplotype diversity libraries (1000 Genomes)

### Ablation Study Results

**Component Contributions (SRR14235678, 12.35% human content):**
- minimap2 alone: 97.34% sensitivity, 8.2 min
- Bowtie2 alone: 98.12% sensitivity, 24.1 min
- Dual-pass: **99.89% sensitivity, 14.3 min** ✅

**Reference Comparison (SRR6062009):**
- T2T-CHM13v2.0: 99.87% sensitivity
- GRCh38: 97.91% sensitivity
- **Improvement: 1.96 pp** (1.8–2.3 pp from CHM13-unique regions)

**Entropy Sweep:**
- H=0.50: 99.1% retention, 0.01% residual contamination
- H=0.70 (Output 2): 97.0% retention, 0.001% residual
- H=0.85 (Output 3): 91.0% retention, 0.0001% residual ✅
- H=0.90: 88.9% retention, <0.00001% residual

---

## 🛠️ Troubleshooting

**"Index 'standard' not found"**  
Run `hostsweep --build` to download and index T2T-CHM13v2.0.

**"hostsweep: command not found"**  
Ensure conda environment is activated and package is installed:
```bash
conda activate hostsweep
cd /path/to/HostSweep
pip install -e .
```

**Out of memory**  
Reduce threads (`-t 2`) or close other applications. Peak usage should be < 8 GB.

**OUTPUT 2 / OUTPUT 3 have very few reads**  
Your input may have short reads. Lower `--bblen` and `--gdpr-minlen`.

**Very low retention on high-contamination samples**  
Expected for blood/plasma samples (40%+ contamination). Assembly-grade output retains 56.9–74.2% of reads in these cases; use profiling-grade output for rare taxa.

---

## 🤝 Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/YourFeature`)
3. Commit your changes with clear messages
4. Push to your fork
5. Open a Pull Request with a description of your changes

---

## 📝 Citation

If you use HostSweep in your research, please cite:

```bibtex
@article{mukhtar2026hostsweep,
  title={HostSweep: a modular dual-pass pipeline for human DNA decontamination in Illumina metagenomic data},
  author={Mukhtar, Adeel and Tariq, Umair and Khaliq, Awais Abdul},
  journal={Bioinformatics},
  year={2026},
  publisher={Oxford University Press}
}
```

---

## 📄 License

MIT License — see [LICENSE](LICENSE) for details.

---

## 🙏 Acknowledgments

- **T2T-CHM13 Consortium** for the complete human genome reference
- Developers of **minimap2** (Heng Li), **Bowtie2** (Langmead & Salzberg), **fastp** (Chen et al.), **BBTools** (Brian Bushnell), and **samtools** (Li et al.)
- Inspired by **KneadData** (Huttenhower Lab), **Hostile** (Constantinides & Crook), and the broader metagenomic decontamination community

---

## 🔗 Related Projects & Tools

- [KneadData](https://github.com/biobakery/kneaddata) — Single-pass Bowtie2 quality control
- [Hostile](https://github.com/bede/hostile) — Single-pass minimap2 decontamination
- [Kraken2](https://github.com/DerrickWood/kraken2) — k-mer taxonomic classification
- [MetaPhlAn](https://github.com/biobakery/MetaPhlAn) — Marker-gene metagenomic profiling
- [metaSPAdes](https://github.com/ablab/spades) — Metagenome assembler

---

## 📧 Contact

**Corresponding Author:**  
Umair Tariq  
📧 umair.tariq@bcu.ac.uk

**Contributors:**  
- Adeel Mukhtar (University of Engineering and Technology, Pakistan)
- Awais Abdul Khaliq (Università degli Studi di Milano, Italy)

---

## 🔬 Note on Software Naming

The name **HostSweep** is distinct from the previously published tool **DecontaMiner** (Thind and Sinha, 2019), which screens assembled NGS contigs for cross-species and vector contamination in cancer and transcriptomic data. The two tools address different problems (read-level human host removal from metagenomes vs. contig-level contamination screening), share no source code, and have independent repositories.

---

*Made with ❤️ for the metagenomics community*
