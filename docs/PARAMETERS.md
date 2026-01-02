# HostBuster Parameter Reference

Complete guide to all HostBuster parameters and configuration options.

---

## Command-Line Parameters

### Required Arguments

#### `--input-r1`
- **Type:** String (file path)
- **Description:** Path to R1 (forward) FASTQ file
- **Formats:** `.fastq`, `.fq`, `.fastq.gz`, `.fq.gz`
- **Example:** `--input-r1 data/sample_R1.fastq.gz`

#### `--input-r2`
- **Type:** String (file path)
- **Description:** Path to R2 (reverse) FASTQ file
- **Formats:** `.fastq`, `.fq`, `.fastq.gz`, `.fq.gz`
- **Example:** `--input-r2 data/sample_R2.fastq.gz`

#### `--output-dir`
- **Type:** String (directory path)
- **Description:** Output directory for all results
- **Note:** Will be created if doesn't exist
- **Example:** `--output-dir results/my_sample`

#### `--sample-name`
- **Type:** String
- **Description:** Sample identifier for output files
- **Note:** Used in filenames and log files
- **Example:** `--sample-name sample_001`

---

### Reference Genome Arguments

#### `--minimap2-index`
- **Type:** String (file path)
- **Default:** `reference/indices/human.mmi`
- **Description:** Path to pre-built minimap2 index
- **Example:** `--minimap2-index /path/to/custom.mmi`

#### `--bowtie2-index`
- **Type:** String (file path prefix)
- **Default:** `reference/indices/human_bt2`
- **Description:** Path prefix to Bowtie2 index files
- **Note:** Don't include `.1.bt2` suffix
- **Example:** `--bowtie2-index /path/to/custom_bt2`

---

### Optional Arguments

#### `--threads`
- **Type:** Integer
- **Default:** `4`
- **Range:** 1-64
- **Description:** Number of CPU threads to use
- **Recommendation:**
  - Small datasets: 4 threads
  - Large datasets: 8-16 threads
  - Maximum: Don't exceed available cores
- **Example:** `--threads 8`

#### `--keep-intermediates`
- **Type:** Flag (boolean)
- **Default:** `False`
- **Description:** Keep intermediate BAM files for debugging
- **Storage impact:** +2-5GB per sample
- **Example:** `--keep-intermediates`

---

## Pipeline Configuration (config.py)

### Quality Filtering Parameters

#### `FASTP_MIN_LENGTH`
- **Value:** `50`
- **Description:** Minimum read length after fastp trimming
- **Unit:** base pairs

#### `FASTP_QUALITY_THRESHOLD`
- **Value:** `20`
- **Description:** Phred quality score threshold (Q20)
- **Meaning:** 99% base call accuracy

#### `FASTP_COMPLEXITY_THRESHOLD`
- **Value:** `30`
- **Description:** Complexity threshold for low-complexity filtering

---

### Complexity & Entropy Filtering (BBDuk)

#### `BBDUK_ENTROPY_STEP4`
- **Value:** `0.7`
- **Step:** Step 4 (Initial complexity filtering)
- **Description:** Minimum entropy for read retention
- **Range:** 0.0-1.0 (higher = more stringent)

#### `BBDUK_ENTROPY_STEP7`
- **Value:** `0.8`
- **Step:** Step 7 (Post-alignment normalization)
- **Description:** Entropy threshold for Kraken2 output

#### `BBDUK_ENTROPY_STEP8`
- **Value:** `0.85`
- **Step:** Step 8 (GDPR filtering)
- **Description:** Strictest entropy for public release

#### `MAX_HOMOPOLYMER_LENGTH`
- **Value:** `8`
- **Description:** Maximum homopolymer length allowed
- **Note:** Currently not used (BBDuk limitation)

---

### Length Filtering

#### `LENGTH_MIN_STEP5`
- **Value:** `70`
- **Description:** Minimum length after initial filtering
- **Reason:** Prevent ambiguous alignments

#### `LENGTH_MIN_STEP7`
- **Value:** `75`
- **Description:** Minimum length for Kraken2 output

#### `LENGTH_MAX_STEP7`
- **Value:** `200`
- **Description:** Maximum length for Kraken2 output
- **Note:** Can be adjusted for longer reads

#### `LENGTH_MIN_STEP8`
- **Value:** `90`
- **Description:** Minimum length for GDPR output

---

### Alignment Parameters

#### `MINIMAP2_PRESET`
- **Value:** `"sr"`
- **Description:** Short-read preset for minimap2
- **Alternatives:**
  - `sr` - Illumina short reads (recommended)
  - `map-ont` - Oxford Nanopore (not supported)
  - `map-pb` - PacBio (not supported)

#### `BOWTIE2_MODE`
- **Value:** `"--very-sensitive-local"`
- **Description:** Aggressive local alignment mode
- **Purpose:** Catch borderline human sequences
- **Alternatives:**
  - `--sensitive-local` - Less aggressive
  - `--very-sensitive` - Global alignment

---

### Memory Limits

#### `BBDUK_MEMORY`
- **Value:** `"8g"`
- **Description:** Memory limit for BBDuk operations
- **Recommendation:**
  - 8GB RAM system: `"4g"`
  - 16GB RAM system: `"8g"`
  - 32GB+ RAM system: `"16g"`

#### `BBDUK_MEMORY_LOW`
- **Value:** `"4g"`
- **Description:** Low-resource mode memory limit
- **Note:** Not currently implemented

---

## Output File Names

Configured in `config.py`:

```python
OUTPUT_ASSEMBLY_R1 = "NONHUMAN_PE_ASSEMBLY_R1.fastq.gz"
OUTPUT_ASSEMBLY_R2 = "NONHUMAN_PE_ASSEMBLY_R2.fastq.gz"
OUTPUT_PROFILING = "NONHUMAN_SE_PROFILING.fastq.gz"
OUTPUT_GDPR = "NONHUMAN_STRICT_GDPR.fastq.gz"
```

---

## Performance Tuning

### For Fast Processing
```bash
./hostbuster.py \
    --input-r1 sample_R1.fastq.gz \
    --input-r2 sample_R2.fastq.gz \
    --output-dir results/sample \
    --sample-name sample \
    --threads 16
```

### For Low Memory Systems
Edit `config.py`:
```python
BBDUK_MEMORY = "4g"
```

Then run:
```bash
./hostbuster.py \
    --input-r1 sample_R1.fastq.gz \
    --input-r2 sample_R2.fastq.gz \
    --output-dir results/sample \
    --sample-name sample \
    --threads 2
```

### For Debugging
```bash
./hostbuster.py \
    --input-r1 sample_R1.fastq.gz \
    --input-r2 sample_R2.fastq.gz \
    --output-dir results/sample \
    --sample-name sample \
    --threads 4 \
    --keep-intermediates
```

---

## Customizing Filtering Thresholds

To adjust filtering parameters, edit `config.py`:

### Less Stringent Filtering
```python
BBDUK_ENTROPY_STEP4 = 0.6  # Instead of 0.7
BBDUK_ENTROPY_STEP7 = 0.7  # Instead of 0.8
BBDUK_ENTROPY_STEP8 = 0.75 # Instead of 0.85
LENGTH_MIN_STEP8 = 80      # Instead of 90
```

### More Stringent Filtering
```python
BBDUK_ENTROPY_STEP4 = 0.75  # Instead of 0.7
BBDUK_ENTROPY_STEP7 = 0.85  # Instead of 0.8
BBDUK_ENTROPY_STEP8 = 0.90  # Instead of 0.85
LENGTH_MIN_STEP8 = 100      # Instead of 90
```

---

## Reference Genome Options

### T2T-CHM13v2.0 (Recommended)
- **Size:** ~3GB
- **Completeness:** Most complete human reference
- **Best for:** Production use

### GRCh38
- **Size:** ~3GB
- **Standard:** Widely used reference
- **Best for:** Comparison with other studies

### Chromosome 1 Only
- **Size:** ~250MB
- **Purpose:** Quick testing and validation
- **Best for:** Development and debugging

---

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error |
| 2 | File not found |
| 3 | Invalid parameters |

---

## Environment Variables

None required. All configuration in `config.py` and command-line arguments.

---

## See Also

- [README.md](../README.md) - Main documentation
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Common issues
- [config.py](../config.py) - Configuration file
