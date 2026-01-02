"""
HostBuster Configuration
Pipeline parameters and constants
"""

# ============================================================================
# QUALITY FILTERING PARAMETERS
# ============================================================================

# fastp parameters
FASTP_MIN_LENGTH = 50
FASTP_QUALITY_THRESHOLD = 20
FASTP_COMPLEXITY_THRESHOLD = 30

# ============================================================================
# COMPLEXITY AND ENTROPY FILTERING (BBDuk)
# ============================================================================

# Step 4: Initial complexity filtering
BBDUK_ENTROPY_STEP4 = 0.7

# Step 7: Post-alignment normalization
BBDUK_ENTROPY_STEP7 = 0.8
MAX_HOMOPOLYMER_LENGTH = 8

# Step 8: GDPR strict filtering
BBDUK_ENTROPY_STEP8 = 0.85

# ============================================================================
# LENGTH FILTERING
# ============================================================================

# Step 5: Minimum length after primary filtering
LENGTH_MIN_STEP5 = 70

# Step 7: Length range for Kraken2 optimization
LENGTH_MIN_STEP7 = 75
LENGTH_MAX_STEP7 = 200

# Step 8: Minimum length for GDPR compliance
LENGTH_MIN_STEP8 = 90

# ============================================================================
# ALIGNMENT PARAMETERS
# ============================================================================

# minimap2 parameters
MINIMAP2_PRESET = "sr"  # short-read preset

# Bowtie2 parameters
BOWTIE2_MODE = "--very-sensitive-local"  # aggressive alignment

# ============================================================================
# OUTPUT FILE NAMES
# ============================================================================

OUTPUT_ASSEMBLY_R1 = "NONHUMAN_PE_ASSEMBLY_R1.fastq.gz"
OUTPUT_ASSEMBLY_R2 = "NONHUMAN_PE_ASSEMBLY_R2.fastq.gz"
OUTPUT_PROFILING = "NONHUMAN_SE_PROFILING.fastq.gz"
OUTPUT_GDPR = "NONHUMAN_STRICT_GDPR.fastq.gz"

# ============================================================================
# RESOURCE LIMITS
# ============================================================================

# Memory limits for BBTools (adjust based on available RAM)
BBDUK_MEMORY = "8g"  # 8GB for systems with 16GB RAM
BBDUK_MEMORY_LOW = "4g"  # 4GB for systems with 8GB RAM

# Default thread count
DEFAULT_THREADS = 4

# ============================================================================
# REFERENCE GENOME
# ============================================================================

# T2T-CHM13v2.0 (most complete human reference)
REFERENCE_GENOME_URL = "https://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/009/914/755/GCF_009914755.1_T2T-CHM13v2.0/GCF_009914755.1_T2T-CHM13v2.0_genomic.fna.gz"

# Alternative: GRCh38 (if T2T not available)
REFERENCE_GENOME_ALT_URL = "https://ftp.ncbi.nlm.nih.gov/genomes/all/GCA/000/001/405/GCA_000001405.15_GRCh38/GCA_000001405.15_GRCh38_genomic.fna.gz"

# ============================================================================
# TESTING MODE
# ============================================================================

# Test dataset
TEST_DATASET_R1 = "ftp://ftp.sra.ebi.ac.uk/vol1/fastq/SRR606/009/SRR6062009/SRR6062009_1.fastq.gz"
TEST_DATASET_R2 = "ftp://ftp.sra.ebi.ac.uk/vol1/fastq/SRR606/009/SRR6062009/SRR6062009_2.fastq.gz"

# ============================================================================
# LOGGING
# ============================================================================

LOG_FORMAT = '%(asctime)s - %(levelname)s - %(message)s'
LOG_LEVEL = 'INFO'
