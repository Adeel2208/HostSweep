# HostSweep benchmark & reproducibility

Everything needed to regenerate the evaluation reported in the manuscript:
the synthetic controlled-truth libraries, the real-library panel, the
comparator commands, and the scoring code.

Large inputs and outputs are not tracked by git — the repository `.gitignore`
excludes `data/` and `results/` at any depth, along with FASTQ, BAM/SAM and
index files. Everything is regenerated from the scripts here.

---

## Layout

```
benchmark/
├── README.md               ← this file
├── accessions.csv          ← real-library panel (SRA Run accessions)
├── data/                   ← downloaded / generated FASTQ (git-ignored)
├── synthetic/
│   └── README.md           ← ART simulation protocol, seeds, abundances
└── scripts/
    ├── download_sra.sh     ← prefetch + fasterq-dump for accessions.csv
    ├── mix_spikein.py      ← build controlled-truth spike-in libraries
    ├── run_hostsweep.sh    ← run HostSweep, record runtime and peak RSS
    ├── run_comparators.sh  ← Hostile / KneadData / BMTagger / DeconSeq
    └── compute_metrics.py  ← sensitivity, FPR, retention from truth labels
```

---

## Prerequisites

```bash
conda env create -f ../environment.yml
conda activate hostsweep
pip install -e ..
hostsweep --build            # T2T-CHM13v2.0, ~3 GB download + 20-40 min index build
```

Additional tools used only by the benchmark:

```bash
conda install -c bioconda sra-tools pigz art          # download + simulation
conda create -n hostile   -c bioconda hostile         # comparators live in
conda create -n kneaddata -c bioconda kneaddata       # separate environments to
conda create -n bmtagger  -c bioconda bmtagger        # avoid dependency clashes
```

---

## How truth labels work

`mix_spikein.py` rewrites every read name with an origin prefix — `HSh_` for
human, `HSb_` for microbial background — before writing the mixed library.
Every tool in the comparison preserves the read name up to the first
whitespace, so `compute_metrics.py` can recover the origin of any surviving
read without a side-car mapping. A `_labels.tsv.gz` and a `_manifest.json` are
written alongside each library for auditing.

Because the label travels in the read name, the same scoring code applies
unchanged to HostSweep's three tiers and to every comparator.

---

## Track 1 — Synthetic controlled-truth libraries

Full simulation protocol, seeds and abundance tables: [`synthetic/README.md`](synthetic/README.md).

```bash
# 1. Simulate human reads from T2T-CHM13v2.0 and a microbial background
#    (exact ART commands and seeds: synthetic/README.md)

# 2. Mix at a known human fraction
python scripts/mix_spikein.py \
    --background-r1 data/synthetic/background_R1.fastq.gz \
    --background-r2 data/synthetic/background_R2.fastq.gz \
    --human-r1      data/synthetic/human_R1.fastq.gz \
    --human-r2      data/synthetic/human_R2.fastq.gz \
    --fraction 0.05 --total-pairs 2000000 --seed 45 \
    --out-prefix data/synthetic/spike_05pct

# 3. Run HostSweep
hostsweep -1 data/synthetic/spike_05pct_R1.fastq.gz \
          -2 data/synthetic/spike_05pct_R2.fastq.gz \
          -n spike_05pct -o results/spike_05pct -t 8

# 4. Score each tier
for tier in ASSEMBLY_R1 PROFILING STRINGENT; do
    python scripts/compute_metrics.py \
        --truth-r1 data/synthetic/spike_05pct_R1.fastq.gz \
        --cleaned  results/spike_05pct/cleaned/spike_05pct_${tier}.fastq.gz \
        --tool hostsweep --tier "$tier" \
        --out results/spike_05pct/metrics_${tier}.json
done
```

For the assembly tier, pass both mates:

```bash
python scripts/compute_metrics.py \
    --truth-r1 data/synthetic/spike_05pct_R1.fastq.gz \
    --cleaned  results/spike_05pct/cleaned/spike_05pct_ASSEMBLY_R1.fastq.gz \
               results/spike_05pct/cleaned/spike_05pct_ASSEMBLY_R2.fastq.gz \
    --tool hostsweep --tier assembly
```

### Metric definitions

Host removal is the positive class:

| Term | Meaning |
|------|---------|
| TP | human read absent from the cleaned output (correctly removed) |
| FN | human read present in the cleaned output (missed contamination) |
| TN | background read present in the cleaned output (correctly kept) |
| FP | background read absent from the cleaned output (over-filtering) |

- **Sensitivity** = TP / (TP + FN)
- **False positive rate** = FP / (FP + TN)
- **Background retention** = TN / (TN + FP)

---

## Track 2 — Real SRA libraries

Real libraries have no ground truth, so they are used for runtime, peak memory
and retention — not for sensitivity.

```bash
bash scripts/download_sra.sh accessions.csv data/real
THREADS=8 bash scripts/run_hostsweep.sh data/real results/real standard
```

`run_hostsweep.sh` writes `results/real/timing.tsv` with wall-clock seconds and
peak RSS per sample (peak RSS requires GNU `time`; on macOS install `gtime`
via `brew install gnu-time`).

> `accessions.csv` currently lists only the two runs named in the repository's
> own documentation. Populate it from Supplementary Table S1 before running the
> full panel.

---

## Track 3 — Comparators

```bash
export T2T_FASTA=$CONDA_PREFIX/share/hostsweep/databases/standard/human_T2T.fasta
export BT2_INDEX=$CONDA_PREFIX/share/hostsweep/databases/standard/human_bt2
export MM2_INDEX=$CONDA_PREFIX/share/hostsweep/databases/standard/human.mmi

bash scripts/run_comparators.sh data/synthetic results/comparators hostile kneaddata
```

All comparators are pointed at the **same** T2T-CHM13v2.0 reference so the
comparison reflects the method rather than the reference. Index-construction
commands for BMTagger and DeconSeq are documented inline in
`run_comparators.sh`.

Score them with the same script:

```bash
python scripts/compute_metrics.py \
    --truth-r1 data/synthetic/spike_05pct_R1.fastq.gz \
    --cleaned results/comparators/hostile/spike_05pct/*.clean_1.fastq.gz \
    --tool hostile --tier single
```

---

## Reporting

Metrics land as one JSON per (sample, tool, tier). Collate however you prefer;
the fields are stable:

```bash
python - <<'PY'
import json, glob, csv, sys
rows = [json.load(open(f)) for f in glob.glob("results/**/metrics_*.json", recursive=True)]
w = csv.DictWriter(sys.stdout, fieldnames=list(rows[0]), extrasaction="ignore")
w.writeheader(); w.writerows(rows)
PY
```

---

## Scope note

These benchmarks measure how much detectable human sequence a workflow removes
under stated conditions. They do not establish that any output is free of human
material, and no tier should be treated as certifying absence of human sequence.
