# DecontaMiner

**Advanced Human DNA Decontamination Pipeline for Illumina Metagenomic Data**

[![Python](https://img.shields.io/badge/Python-3.9%2B-blue)](https://www.python.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Conda](https://img.shields.io/badge/Install-Conda-green)](https://docs.conda.io/)

DecontaMiner is a fast, modular Python pipeline for removing human DNA contamination from Illumina paired-end metagenomic sequencing data. It produces three specialized output formats optimized for assembly, taxonomic profiling, and GDPR-compliant publication.

> **Evolved from [HostBuster](https://github.com/Adeel2208/Host_Buster)** — refactored into a fully modular, pip-installable package with automatic database management.

---

## 🚀 Features

- **Three Specialized Outputs** — Assembly-ready PE reads, profiling-optimized SE reads, and GDPR-compliant reads
- **Dual-Pass Host Removal** — minimap2 (conservative, preserves pairs) → Bowtie2 (aggressive, catches borderline hits)
- **Automatic Database Management** — `decontaminer --build` downloads and indexes the T2T-CHM13v2.0 human reference; custom indices supported
- **Tunable Parameters** — All QC thresholds exposed via CLI flags
- **Modular Architecture** — 9 focused Python modules, easy to extend or reuse individual components
- **Production Ready** — Pure Python (no Nextflow), single conda env, JSON stats, complete logging

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

### 1. Clone

```bash
git clone https://github.com/Adeel2208/Host_Buster.git
cd Host_Buster
```

### 2. Create Conda Environment

```bash
conda env create -f environment.yml
conda activate decontaminer
```

### 3. Install the `decontaminer` Command

```bash
pip install -e .
decontaminer --version   # should print 1.0.0
```

### 4. Build the Reference Index

**Standard (full T2T-CHM13v2.0 — downloads ~3 GB, builds in 20-40 min):**

```bash
decontaminer --build
```

**Custom reference:**

```bash
decontaminer --build --ix my_organism --ref /path/to/reference.fasta -t 8
```

**List available indices at any time:**

```bash
decontaminer --lx
```

---

## 📖 Usage

### Basic Run

```bash
decontaminer \
  -1 sample_R1.fastq.gz \
  -2 sample_R2.fastq.gz \
  -n my_sample \
  -o results/my_sample \
  -t 8
```

### With a Custom Index

```bash
decontaminer \
  -1 sample_R1.fastq.gz \
  -2 sample_R2.fastq.gz \
  -n my_sample \
  -o results/my_sample \
  -i my_organism
```

### Keep Intermediate Files

```bash
decontaminer -1 R1.fq.gz -2 R2.fq.gz -n sample -o out/ --keep-intermediates
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
| `--bbe` | BBDuk entropy (complexity + norm) | 0.7 |
| `--bbeg` | BBDuk entropy (GDPR) | 0.85 |
| `--bblen` | BBDuk minimum length | 50 |
| `--gdpr-minlen` | GDPR output min length | 90 |
| `-v / --verbose` | Debug-level logging | off |
| `--keep-intermediates` | Don't delete temp files | off |

---

## 📊 Output Files

All final outputs land in `<output_dir>/cleaned/`:

| File | Type | Use Case |
|------|------|----------|
| `<sample>_ASSEMBLY_R1.fastq.gz` | Paired-end | Meta-assembly, genome binning |
| `<sample>_ASSEMBLY_R2.fastq.gz` | Paired-end | (mate of above) |
| `<sample>_PROFILING.fastq.gz` | Single-end | Taxonomic profiling (Kraken2, MetaPhlAn) |
| `<sample>_GDPR.fastq.gz` | Single-end | Public deposition (SRA, ENA) |

**QC & stats:**

| File | Location |
|------|----------|
| `<sample>_fastp.html` | `qc/` |
| `<sample>_fastp.json` | `qc/` |
| `<sample>_stats.json` | `stats/` |
| `decontaminer_<sample>.log` | output root |

---

## 🔍 Pipeline Steps

```
INPUT: Paired-end FASTQ (R1 + R2)
   │
   ▼
[Step 0] Input Validation
   │
   ▼
[Step 1] fastp — adapter trimming + quality filter
   │
   ▼
[Step 2] minimap2 — primary host alignment → extract unmapped pairs
   │
   ├──► OUTPUT 1: Assembly-ready PE reads  ──────────────────────►
   │
   ▼
[Step 3] PE → SE conversion  (cat R1 + R2)
   │
   ▼
[Step 4] BBDuk — complexity filter  (entropy 0.7)
   │
   ▼
[Step 5] BBDuk — length filter  (≥ 50 bp)
   │
   ▼
[Step 6] Bowtie2 — secondary host alignment → extract unmapped
   │
   ▼
[Step 7] BBDuk — normalization  (entropy 0.7)
   │
   ├──► OUTPUT 2: Profiling SE reads  ────────────────────────────►
   │
   ▼
[Step 8] BBDuk — GDPR strict filter  (entropy 0.85, length ≥ 90)
   │
   └──► OUTPUT 3: GDPR-compliant reads  ─────────────────────────►
```

---

## 📈 Performance

Tested on **SRR6062009** (1,863,630 read pairs, 8 threads):

| Metric | Value |
|--------|-------|
| Total runtime | ~11 min |
| OUTPUT 1 (Assembly PE) | 1,811,850 pairs (97.2% retained) |
| OUTPUT 2 (Profiling SE) | 3,623,586 reads |
| OUTPUT 3 (GDPR) | 3,623,327 reads |
| Human contamination removed | 0.02% (test with full genome) |
| Peak memory | < 8 GB |

---

## 🏗️ Architecture

```
Host_Buster/                     ← git repo root
├── setup.py                     ← pip entry-point
├── environment.yml              ← conda deps
├── benchmark/                   ← performance data
├── tests/                       ← pytest suite
└── decontaminer/                ← installable package
    ├── __init__.py              ← version, public API
    ├── __main__.py              ← python -m decontaminer
    ├── cli.py                   ← argparse CLI
    ├── database.py              ← index download / build / list
    ├── pipeline.py              ← 8-step orchestrator
    ├── filters.py               ← fastp + BBDuk wrappers
    ├── aligners.py              ← minimap2 + bowtie2 + samtools
    ├── stats.py                 ← JSON stats collector
    └── utils.py                 ← logging, read counting, shell exec
```

### Key improvements over HostBuster

| HostBuster | DecontaMiner |
|------------|--------------|
| Single monolithic `hostebuster.py` | 9 focused modules |
| Hardcoded index paths | `DatabaseManager` — auto-download, custom indices, versioning |
| No index versioning | `db_version.json` + `--lx` listing |
| Manual `setup.sh` | `pip install -e .` → global `decontaminer` command |
| Fixed parameters | All thresholds tunable via CLI |

---

## 🛠️ Troubleshooting

**"Index 'standard' not found"**
Run `decontaminer --build` to download and index T2T-CHM13v2.0.

**"decontaminer: command not found"**
Make sure you activated the env and installed the package:
```bash
conda activate decontaminer
cd /path/to/Host_Buster
pip install -e .
```

**Out of memory**
Reduce threads (`-t 2`) or close other applications. Peak usage is < 8 GB on the test set.

**OUTPUT 2 / OUTPUT 3 have 0 reads**
Your reads may be very short. Lower `--bblen` and `--gdpr-minlen`.

---

## 🧪 Running Tests

```bash
conda activate decontaminer
cd Host_Buster
pip install pytest
pytest tests/ -v
```

---

## 🤝 Contributing

1. Fork the repo
2. Create a feature branch (`git checkout -b feature/YourFeature`)
3. Commit and push
4. Open a Pull Request

---

## 📝 Citation

```
[Citation information will be added upon publication]
```

---

## 📄 License

MIT — see [LICENSE](LICENSE)

---

## 🙏 Acknowledgments

- T2T-CHM13 Consortium for the reference genome
- Developers of minimap2, Bowtie2, fastp, BBTools, samtools
- Inspired by [KneadData](https://github.com/biobakery/kneaddata) and [clean](https://github.com/rki-mf1/clean)

---

## 🔗 Related Projects

- [KneadData](https://github.com/biobakery/kneaddata) — Quality control for metagenomics
- [Kraken2](https://github.com/DerrickWood/kraken2) — Taxonomic classification
- [MetaPhlAn](https://github.com/biobakery/MetaPhlAn) — Metagenomic profiling

---

*Made with ❤️ for the metagenomics community*
