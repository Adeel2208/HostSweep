#!/bin/bash
# HostBuster Setup Script
# This script automates the complete setup process

set -e  # Exit on error

echo "=========================================="
echo "HostBuster Setup"
echo "=========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored messages
print_status() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

# Check if running in correct directory
if [ ! -f "hostbuster.py" ]; then
    print_error "Please run this script from the hostbuster directory"
    exit 1
fi

# Step 1: Create directory structure
echo "Step 1: Creating directory structure..."
mkdir -p data
mkdir -p reference/indices
mkdir -p results
mkdir -p tests
mkdir -p docs
print_status "Directories created"
echo ""

# Step 2: Check conda environment
echo "Step 2: Checking conda environment..."
if conda env list | grep -q "^hostbuster "; then
    print_warning "Environment 'hostbuster' already exists"
    read -p "Do you want to recreate it? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        conda env remove -n hostbuster -y
        conda env create -f environment.yml
        print_status "Environment recreated"
    else
        print_status "Using existing environment"
    fi
else
    conda env create -f environment.yml
    print_status "Environment created"
fi
echo ""

# Step 3: Download reference genome
echo "Step 3: Reference genome setup..."
echo "Choose reference genome:"
echo "  1) Chromosome 1 only (~250MB, recommended for testing)"
echo "  2) Full T2T-CHM13v2.0 (~3GB, for production)"
echo "  3) Skip (already downloaded)"
read -p "Enter choice (1/2/3): " choice

case $choice in
    1)
        echo "Downloading chromosome 1..."
        cd reference
        if [ ! -f "human_chr1.fasta" ]; then
            wget -q --show-progress https://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/009/914/755/GCF_009914755.1_T2T-CHM13v2.0/GCF_009914755.1_T2T-CHM13v2.0_genomic.fna.gz
            gunzip GCF_009914755.1_T2T-CHM13v2.0_genomic.fna.gz
            head -n 5000000 GCF_009914755.1_T2T-CHM13v2.0_genomic.fna > human_chr1.fasta
            rm GCF_009914755.1_T2T-CHM13v2.0_genomic.fna
            print_status "Chromosome 1 downloaded"
        else
            print_status "Chromosome 1 already exists"
        fi
        REFERENCE="human_chr1.fasta"
        cd ..
        ;;
    2)
        echo "Downloading full genome (~3GB, this will take a while)..."
        cd reference
        if [ ! -f "human_T2T.fasta" ]; then
            wget -q --show-progress https://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/009/914/755/GCF_009914755.1_T2T-CHM13v2.0/GCF_009914755.1_T2T-CHM13v2.0_genomic.fna.gz
            gunzip GCF_009914755.1_T2T-CHM13v2.0_genomic.fna.gz
            mv GCF_009914755.1_T2T-CHM13v2.0_genomic.fna human_T2T.fasta
            print_status "Full genome downloaded"
        else
            print_status "Full genome already exists"
        fi
        REFERENCE="human_T2T.fasta"
        cd ..
        ;;
    3)
        print_status "Skipping genome download"
        # Check which reference exists
        if [ -f "reference/human_chr1.fasta" ]; then
            REFERENCE="human_chr1.fasta"
        elif [ -f "reference/human_T2T.fasta" ]; then
            REFERENCE="human_T2T.fasta"
        else
            print_error "No reference genome found!"
            exit 1
        fi
        ;;
    *)
        print_error "Invalid choice"
        exit 1
        ;;
esac
echo ""

# Step 4: Build indices
echo "Step 4: Building indices..."

# Activate conda environment for index building
eval "$(conda shell.bash hook)"
conda activate hostbuster

# Build minimap2 index
if [ ! -f "reference/indices/human.mmi" ]; then
    echo "Building minimap2 index (this may take 5-10 minutes)..."
    minimap2 -x sr -d reference/indices/human.mmi reference/$REFERENCE
    print_status "Minimap2 index built"
else
    print_status "Minimap2 index already exists"
fi

# Build Bowtie2 index
if [ ! -f "reference/indices/human_bt2.1.bt2" ]; then
    echo "Building Bowtie2 index (this may take 10-20 minutes)..."
    bowtie2-build --threads 4 reference/$REFERENCE reference/indices/human_bt2
    print_status "Bowtie2 index built"
else
    print_status "Bowtie2 index already exists"
fi
echo ""

# Step 5: Download test data (optional)
echo "Step 5: Test data (optional)..."
read -p "Download test dataset (~50MB, SRR6062009)? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    cd data
    if [ ! -f "test_R1.fastq.gz" ]; then
        echo "Downloading test R1..."
        wget -q --show-progress ftp://ftp.sra.ebi.ac.uk/vol1/fastq/SRR606/009/SRR6062009/SRR6062009_1.fastq.gz -O test_R1.fastq.gz
        print_status "Test R1 downloaded"
    else
        print_status "Test R1 already exists"
    fi
    
    if [ ! -f "test_R2.fastq.gz" ]; then
        echo "Downloading test R2..."
        wget -q --show-progress ftp://ftp.sra.ebi.ac.uk/vol1/fastq/SRR606/009/SRR6062009/SRR6062009_2.fastq.gz -O test_R2.fastq.gz
        print_status "Test R2 downloaded"
    else
        print_status "Test R2 already exists"
    fi
    cd ..
else
    print_status "Skipping test data download"
fi
echo ""

# Step 6: Make scripts executable
echo "Step 6: Setting permissions..."
chmod +x hostbuster.py
chmod +x setup.sh
print_status "Scripts are executable"
echo ""

# Step 7: Verify installation
echo "Step 7: Verifying installation..."
echo ""
echo "Checking tools..."

check_tool() {
    if command -v $1 &> /dev/null; then
        version=$($1 --version 2>&1 | head -n 1)
        print_status "$1: $version"
    else
        print_error "$1 not found!"
        return 1
    fi
}

check_tool minimap2
check_tool bowtie2
check_tool samtools
check_tool fastp
check_tool fastqc
check_tool bbduk.sh

echo ""
echo "Checking indices..."
if [ -f "reference/indices/human.mmi" ]; then
    print_status "minimap2 index exists"
else
    print_error "minimap2 index missing!"
fi

if [ -f "reference/indices/human_bt2.1.bt2" ]; then
    print_status "Bowtie2 index exists"
else
    print_error "Bowtie2 index missing!"
fi

echo ""
echo "=========================================="
echo "Setup Complete!"
echo "=========================================="
echo ""
echo "To activate the environment:"
echo "  conda activate hostbuster"
echo ""
echo "To run a test:"
echo "  ./hostbuster.py \\"
echo "      --input-r1 data/test_R1.fastq.gz \\"
echo "      --input-r2 data/test_R2.fastq.gz \\"
echo "      --output-dir results/test_run \\"
echo "      --sample-name test_sample \\"
echo "      --threads 4"
echo ""
echo "For help:"
echo "  ./hostbuster.py --help"
echo ""
