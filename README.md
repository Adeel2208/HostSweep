# HostBuster

**Human DNA Decontamination Pipeline for Illumina Metagenomic Data**

[![Python](https://img.shields.io/badge/Python-3.9%2B-blue)](https://www.python.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Conda](https://img.shields.io/badge/Install-Conda-green)](https://docs.conda.io/)

HostBuster is a fast, efficient Python pipeline for removing human DNA contamination from Illumina paired-end metagenomic sequencing data. It produces three specialized output formats optimized for different downstream analyses.

---

## 🚀 Features

- **Three Specialized Outputs**
  - Assembly-ready paired-end reads (conservative filtering)
  - Kraken2-optimized single-end reads (aggressive filtering)
  - GDPR-compliant publication-ready reads (maximum decontamination)

- **Dual-Pass Filtering**
  - Primary: minimap2 (conservative, maintains pairs)
  - Secondary: Bowtie2 (aggressive, removes borderline sequences)

- **Comprehensive Quality Control**
  - fastp for adapter trimming and quality filtering
  - BBDuk for complexity and entropy filtering
  - MultiQC for aggregated reporting

- **Production Ready**
  - Pure Python implementation (no Nextflow)
  - Single conda environment
  - Complete logging and statistics
  - Fast processing (7-10 minutes for 1.8M read pairs)

---

## 📋 Requirements

### System Requirements
- **OS:** Linux (Ubuntu 20.04+) or macOS
- **RAM:** Minimum 8GB, Recommended 16GB+
- **Storage:** 50-100GB free space
- **CPU:** Minimum 4 cores, Recommended 8+ cores
- **Python:** 3.9+

### Software Dependencies
All dependencies are managed through conda (see Installation).

---

## 🔧 Installation

### 1. Clone Repository
```bash
git clone https://github.com/sintetico87/hostbuster.git
cd hostbuster
```

### 2. Create Conda Environment
```bash
conda env create -f environment.yml
conda activate hostbuster
```

### 3. Download and Index Reference Genome

**Option A: Quick Test (Chromosome 1 only - ~250MB)**
```bash
cd reference
wget https://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/009/914/755/GCF_009914755.1_T2T-CHM13v2.0/GCF_009914755.1_T2T-CHM13v2.0_genomic.fna.gz
gunzip GCF_009914755.1_T2T-CHM13v2.0_genomic.fna.gz
head -n 5000000 GCF_009914755.1_T2T-CHM13v2.0_genomic.fna > human_chr1.fasta
cd ..

# Build indices
mkdir -p reference/indices
minimap2 -x sr -d reference/indices/human.mmi reference/human_chr1.fasta
bowtie2-build --threads 4 reference/human_chr1.fasta reference/indices/human_bt2
```

**Option B: Production (Full T2T-CHM13v2.0 - ~3GB)**
```bash
cd reference
wget https://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/009/914/755/GCF_009914755.1_T2T-CHM13v2.0/GCF_009914755.1_T2T-CHM13v2.0_genomic.fna.gz
gunzip GCF_009914755.1_T2T-CHM13v2.0_genomic.fna.gz
mv GCF_009914755.1_T2T-CHM13v2.0_genomic.fna human_T2T.fasta
cd ..

# Build indices (takes 20-30 minutes)
mkdir -p reference/indices
minimap2 -x sr -d reference/indices/human.mmi reference/human_T2T.fasta
bowtie2-build --threads 8 reference/human_T2T.fasta reference/indices/human_bt2
```

### 4. Download Test Data (Optional)
```bash
mkdir -p data
cd data
wget ftp://ftp.sra.ebi.ac.uk/vol1/fastq/SRR606/009/SRR6062009/SRR6062009_1.fastq.gz -O test_R1.fastq.gz
wget ftp://ftp.sra.ebi.ac.uk/vol1/fastq/SRR606/009/SRR6062009/SRR6062009_2.fastq.gz -O test_R2.fastq.gz
cd ..
```

---

## 📖 Usage

### Basic Command
```bash
./hostbuster.py \
    --input-r1 sample_R1.fastq.gz \
    --input-r2 sample_R2.fastq.gz \
    --output-dir results/my_sample \
    --sample-name my_sample \
    --threads 8
```

### Quick Test Run
```bash
./hostbuster.py \
    --input-r1 data/test_R1.fastq.gz \
    --input-r2 data/test_R2.fastq.gz \
    --output-dir results/test_run \
    --sample-name test_sample \
    --threads 4
```

### With Custom Reference Indices
```bash
./hostbuster.py \
    --input-r1 sample_R1.fastq.gz \
    --input-r2 sample_R2.fastq.gz \
    --output-dir results/my_sample \
    --sample-name my_sample \
    --minimap2-index path/to/custom.mmi \
    --bowtie2-index path/to/custom_bt2 \
    --threads 8
```

### Keep Intermediate Files
```bash
./hostbuster.py \
    --input-r1 sample_R1.fastq.gz \
    --input-r2 sample_R2.fastq.gz \
    --output-dir results/my_sample \
    --sample-name my_sample \
    --threads 8 \
    --keep-intermediates
```

---

## 📊 Output Files

HostBuster produces three main output files in `{output-dir}/cleaned/`:

### 1. Assembly-Ready Paired-End Reads
```
NONHUMAN_PE_ASSEMBLY_R1.fastq.gz
NONHUMAN_PE_ASSEMBLY_R2.fastq.gz
```
- **Use case:** Meta-assembly, genome binning
- **Filtering:** Conservative (preserves read pairs)
- **Method:** minimap2 alignment only

### 2. Kraken2-Optimized Single-End Reads
```
NONHUMAN_SE_PROFILING.fastq.gz
```
- **Use case:** Taxonomic profiling (Kraken2, MetaPhlAn)
- **Filtering:** Aggressive dual-pass
- **Length:** 75-200bp
- **Quality:** Entropy ≥0.8

### 3. GDPR-Compliant Publication-Ready Reads
```
NONHUMAN_STRICT_GDPR.fastq.gz
```
- **Use case:** Public data release (SRA, ENA)
- **Filtering:** Maximum decontamination
- **Length:** ≥90bp
- **Quality:** Entropy ≥0.85

### Additional Outputs

**Quality Reports:**
- `trimmed/sample_fastp.html` - fastp quality report
- `stats/sample_multiqc.html` - MultiQC aggregated report

**Statistics:**
- `stats/sample_stats.json` - Detailed processing statistics
- `hostbuster_sample.log` - Complete processing log

---

## 🔍 Pipeline Steps

```
INPUT: Paired-end FASTQ files (R1 + R2)
   ↓
[Step 0] Input Validation
   ↓
[Step 1] Quality Control & Adapter Trimming (fastp)
   ↓
[Step 2] Primary Host Removal (minimap2)
   ↓
   ├──→ OUTPUT 1: Assembly-ready PE reads
   ↓
[Step 3] Convert to Single-End
   ↓
[Step 4] Complexity Filtering (BBDuk, entropy 0.7)
   ↓
[Step 5] Length Filtering (≥70bp)
   ↓
[Step 6] Secondary Host Removal (Bowtie2 aggressive)
   ↓
[Step 7] Post-Alignment Normalization (BBDuk, entropy 0.8)
   ↓
   ├──→ OUTPUT 2: Kraken2-optimized SE reads
   ↓
[Step 8] GDPR Strict Filtering (BBDuk, entropy 0.85)
   ↓
   └──→ OUTPUT 3: GDPR-compliant reads
```

---

## 📈 Performance

**Test Dataset:** SRR6062009 (1,863,630 read pairs)

| Metric | Value |
|--------|-------|
| Runtime | 7.2 minutes (4 threads) |
| Input | 1,863,630 pairs |
| OUTPUT 1 | 1,812,107 pairs (97.2%) |
| OUTPUT 2 | 3,623,334 reads |
| OUTPUT 3 | 3,622,848 reads |
| Memory usage | <8GB |

**Note:** 0% human contamination in test run because chromosome 1 reference was used. Expect 1-10% contamination with full genome reference depending on sample type.

---

## 🛠️ Troubleshooting

### Issue: "Minimap2 index not found"
**Solution:** Build the minimap2 index first:
```bash
minimap2 -x sr -d reference/indices/human.mmi reference/your_reference.fasta
```

### Issue: "Bowtie2 index not found"
**Solution:** Build the Bowtie2 index:
```bash
bowtie2-build reference/your_reference.fasta reference/indices/human_bt2
```

### Issue: Out of memory
**Solutions:**
1. Reduce thread count: `--threads 2`
2. Use chromosome 1 reference for testing
3. Close other applications
4. Upgrade to 16GB+ RAM

### Issue: OUTPUT 2 or OUTPUT 3 have 0 reads
**Cause:** BBDuk length filtering too strict
**Solution:** Your reads may be longer than 200bp. Check read length distribution and adjust parameters in the code if needed.

### Issue: MultiQC warnings
**Note:** The fastp plot warnings in MultiQC are cosmetic and don't affect functionality.

---

## 🤝 Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

---

## 📝 Citation

If you use HostBuster in your research, please cite:

```
[Citation information will be added upon publication]
```

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## 🙏 Acknowledgments

- T2T-CHM13 Consortium for the reference genome
- Developers of minimap2, Bowtie2, fastp, BBTools, and samtools
- Inspired by [KneadData](https://github.com/biobakery/kneaddata) and [clean](https://github.com/rki-mf1/clean)

---

## 📧 Contact

- **Issues:** [GitHub Issues](https://github.com/sintetico87/hostbuster/issues)
- **Author:** HostBuster Team

---

## 🔗 Related Projects

- [KneadData](https://github.com/biobakery/kneaddata) - Quality control for metagenomics
- [clean](https://github.com/rki-mf1/clean) - Nextflow decontamination pipeline
- [Kraken2](https://github.com/DerrickWood/kraken2) - Taxonomic classification
- [MetaPhlAn](https://github.com/biobakery/MetaPhlAn) - Metagenomic profiling

---

**Made with ❤️ for the metagenomics community**
