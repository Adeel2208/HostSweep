# Synthetic controlled-truth libraries

Twelve libraries with exactly known human content, used for the sensitivity and
false-positive-rate figures. Human reads are simulated from T2T-CHM13v2.0 with
ART; the microbial background follows a CAMI II-style community.

Because both components are simulated, the origin of every read is known
before any tool sees it — the basis for the metrics in `../README.md`.

---

## Tools

```bash
conda install -c bioconda art          # provides art_illumina
```

All simulations use the `HS25` error profile (HiSeq 2500), 150 bp paired-end,
mean fragment length 350 bp, s.d. 50 bp.

---

## Step 1 — Human reads from T2T-CHM13v2.0

```bash
REF=$CONDA_PREFIX/share/hostsweep/databases/standard/human_T2T.fasta

art_illumina \
    -ss HS25 \
    -i "$REF" \
    -p \
    -l 150 \
    -f 5 \
    -m 350 \
    -s 50 \
    -rs 42 \
    -na \
    -o human_seed42_R
```

`-f 5` (5× coverage) yields far more human reads than any library needs;
`mix_spikein.py` subsamples down to the exact target count, so one simulation
per seed is enough.

## Step 2 — Microbial background

Simulate each community member separately at its target abundance, then
concatenate. With a genome list in `genomes.tsv` (`path<TAB>relative_abundance`):

```bash
while IFS=$'\t' read -r GENOME ABUND; do
    [ -z "$GENOME" ] && continue
    COV=$(python -c "print(50 * $ABUND)")     # 50x total community coverage
    art_illumina -ss HS25 -i "$GENOME" -p -l 150 -f "$COV" \
                 -m 350 -s 50 -rs 42 -na \
                 -o "bg_$(basename "${GENOME%.*}")_R"
done < genomes.tsv

cat bg_*_R1.fq | gzip > background_R1.fastq.gz
cat bg_*_R2.fq | gzip > background_R2.fastq.gz
```

> **To be completed from the manuscript.** `genomes.tsv` — the accession list
> and relative abundances of the CAMI II-style background community — is
> specified in the manuscript's supplementary material and is not reproduced
> here. Add it to this directory before running the panel.

## Step 3 — Mix at a known human fraction

```bash
python ../scripts/mix_spikein.py \
    --background-r1 background_R1.fastq.gz \
    --background-r2 background_R2.fastq.gz \
    --human-r1 human_seed42_R1.fq --human-r2 human_seed42_R2.fq \
    --fraction 0.05 --total-pairs 2000000 --seed 45 \
    --out-prefix ../data/synthetic/spike_05pct
```

The realised fraction is written to `*_manifest.json`; it differs from the
requested fraction only when the source pool is smaller than the request, in
which case the script warns.

---

## Library panel

Twelve libraries across seeds 42–53. Seven vary the spike-in fraction against a
fixed background; five vary human haplotype background using 1000 Genomes
samples from non-European populations.

| Seed | Library | Human fraction |
|------|---------|----------------|
| 42 | `spike_001pct` | 0.1% |
| 43 | `spike_005pct` | 0.5% |
| 44 | `spike_01pct`  | 1% |
| 45 | `spike_05pct`  | 5% |
| 46 | `spike_10pct`  | 10% |
| 47 | `spike_20pct`  | 20% |
| 48 | `spike_40pct`  | 40% |
| 49–53 | `haplo_1` … `haplo_5` | 5% (non-European haplotype panels) |

> **Confirm before publishing.** The seed range (42–53) and the twelve-library
> split are fixed, but the seed-to-fraction assignment above is a
> reconstruction from the fractions and library count reported in the
> manuscript. Reconcile this table with the supplementary material — and the
> five 1000 Genomes sample identifiers for seeds 49–53 — before treating it as
> the published protocol.

### Generating the whole panel

```bash
set -euo pipefail
declare -A FRACTION=( [42]=0.001 [43]=0.005 [44]=0.01 [45]=0.05
                      [46]=0.10  [47]=0.20  [48]=0.40 )
declare -A LABEL=( [42]=spike_001pct [43]=spike_005pct [44]=spike_01pct
                   [45]=spike_05pct  [46]=spike_10pct  [47]=spike_20pct
                   [48]=spike_40pct )

for SEED in 42 43 44 45 46 47 48; do
    python ../scripts/mix_spikein.py \
        --background-r1 background_R1.fastq.gz \
        --background-r2 background_R2.fastq.gz \
        --human-r1 human_seed42_R1.fq \
        --human-r2 human_seed42_R2.fq \
        --fraction "${FRACTION[$SEED]}" \
        --total-pairs 2000000 \
        --seed "$SEED" \
        --out-prefix "../data/synthetic/${LABEL[$SEED]}"
done
```

---

## Determinism

`mix_spikein.py` seeds a private `random.Random(seed)` and uses reservoir
sampling, so a given (seed, inputs, fraction, total-pairs) always yields a
byte-identical library. ART is seeded with `-rs`. Re-running the panel on a
different machine reproduces the same libraries provided the input genomes and
tool versions match; record those versions with `conda list --explicit`.
