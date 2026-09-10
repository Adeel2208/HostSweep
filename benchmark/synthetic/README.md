# Synthetic controlled-truth libraries

Twelve libraries with exactly known human content, used for the sensitivity and
false-positive-rate figures (experiment E2, scored in E3/E5/E7).

Nine libraries draw their human reads from **T2T-CHM13v2.0** — the same
assembly HostSweep and every comparator filter against, so host removal is
tested under a matched reference. Three draw from **haplotype-resolved
assemblies of individuals not represented by CHM13** (HG00438, HG00733,
NA19240), which tests the mismatch case where the reads to be removed come from
a genome the reference does not describe.

All three mismatch sources are HPRC Year 1 `f1_assembly_v2`, primary/maternal
haplotype, hifiasm v0.14, UCSC Genomics Institute — one assembly project and one
assembler version across three populations, so *reference mismatch* is not
confounded with *different assembler*. HG00514 was originally specified but has
no HPRC assembly; HG00438 (Han Chinese South) replaces it. Recorded as deviation
D9.

The microbial background is the ten-genome community in
[`../genomes.tsv`](../genomes.tsv). Because both components are simulated, the
origin of every read is known before any tool sees it.

> **Execution status.** All twelve libraries were built and scored. The
> realised human fraction equals the requested fraction to all reported digits
> for every library — see [`../run/synthetic_manifest.csv`](../run/synthetic_manifest.csv),
> which is the authoritative record and what results tables must cite.
> Measured background pool: 2,921,080 pairs.
>
> Three accession/organism conflicts in `../genomes.tsv` were found and
> resolved; that file's header records what was corrected and why.

---

## Tools

```bash
conda install -c bioconda art          # provides art_illumina
```

All simulations use the `HS25` error profile (HiSeq 2500), 150 bp paired-end,
**mean fragment length 200 bp, s.d. 10 bp** (`-m 200 -s 10`).

---

## Step 1 — Human reads

Nine matched libraries simulate from T2T-CHM13v2.0:

```bash
REF=$CONDA_PREFIX/share/hostsweep/databases/standard/human_T2T.fasta

art_illumina \
    -ss HS25 -i "$REF" -p -l 150 -f 0.2 \
    -m 200 -s 10 -rs 42 -na \
    -o human_chm13_seed42_R
```

`-f 0.2` is what the panel was actually built with, and is what this command
shows. It yields roughly 2.07 M pairs, still 2.5x the largest single human draw
any library makes (40% of 2,000,000 = 800,000). `mix_spikein.py` subsamples to
the exact target count, so one simulation per seed is enough.

The protocol originally specified `-f 5`. Over the 3.1 Gb reference that yields
~51 M pairs per source, about 20 GB each across four sources, of which more than
98% is discarded by subsampling. The reduction is recorded as deviation D2 in
`../run/DEVIATIONS.md`; truth labelling is unaffected, because subsampling draws
from whatever pool it is given.

The three mismatch libraries simulate identically but from the assemblies
below. `source_accession` is recorded per library in `synthetic_manifest.csv`
and is not optional: "an HPRC assembly of HG00438" is not a reproducible input.

| Sample | Accession | Assembly name | Population |
|---|---|---|---|
| HG00438 | `GCA_018471515.1` | `HG00438.pri.mat.f1_v2` | Han Chinese South |
| HG00733 | `GCA_018506975.1` | `HG00733.pri.mat.f1_v2` | Puerto Rican |
| NA19240 | `GCA_018503275.1` | `NA19240.pri.mat.f1_v2` | Yoruban |

## Step 2 — Microbial background

Simulate each community member at coverage proportional to its abundance, then
concatenate. `../genomes.tsv` holds `accession<TAB>organism<TAB>abundance`;
download each accession to a FASTA first.

```bash
while IFS=$'\t' read -r ACC ORG ABUND REST; do
    case "$ACC" in ''|'#'*|accession) continue;; esac
    GENOME="refs/${ACC}.fna"
    COV=$(python -c "print(200 * $ABUND)")    # 200x total community coverage
    art_illumina -ss HS25 -i "$GENOME" -p -l 150 -f "$COV" \
                 -m 200 -s 10 -rs 42 -na \
                 -o "bg_${ACC}_R"
done < ../genomes.tsv

cat bg_*_R1.fq | gzip > background_R1.fastq.gz
cat bg_*_R2.fq | gzip > background_R2.fastq.gz
```

**200x, not the 50x originally specified.** A 0.1%-human library needs 1,998,000
background pairs; summing `abundance x genome_length` over the ten-genome
community gives 4.379 Mb, so 50x at 300 bp per pair yields a pool of roughly
730,000 — a quarter of the largest draw. The 0.1% library could not have been
built at all, and the 0.5% and 1% libraries would have silently undershot their
requested fractions. Measured pool at 200x: **2,921,080 pairs**. Recorded as
deviation D1.

## Step 3 — Mix at a known human fraction

```bash
python ../scripts/mix_spikein.py \
    --background-r1 background_R1.fastq.gz \
    --background-r2 background_R2.fastq.gz \
    --human-r1 human_chm13_seed42_R1.fq --human-r2 human_chm13_seed42_R2.fq \
    --fraction 0.05 --total-pairs 2000000 --seed 45 \
    --out-prefix ../data/synthetic/SYN-CHM13-04
```

The realised fraction is written to `*_manifest.json`; it differs from the
requested fraction only when the source pool is smaller than the request, in
which case the script warns. **Results tables cite the realised fraction**, not
the requested one.

---

## Library panel

Twelve libraries, 2,000,000 pairs each, seeds 42-53 assigned in order.

| Seed | Library | Human source | Requested fraction |
|------|---------|--------------|--------------------|
| 42 | `SYN-CHM13-01` | T2T-CHM13v2.0 | 0.1% |
| 43 | `SYN-CHM13-02` | T2T-CHM13v2.0 | 0.5% |
| 44 | `SYN-CHM13-03` | T2T-CHM13v2.0 | 1% |
| 45 | `SYN-CHM13-04` | T2T-CHM13v2.0 | 5% |
| 46 | `SYN-CHM13-05` | T2T-CHM13v2.0 | 10% |
| 47 | `SYN-CHM13-06` | T2T-CHM13v2.0 | 20% |
| 48 | `SYN-CHM13-07` | T2T-CHM13v2.0 | 40% |
| 49 | `SYN-CHM13-08` | T2T-CHM13v2.0 | 5% |
| 50 | `SYN-CHM13-09` | T2T-CHM13v2.0 | 10% |
| 51 | `SYN-IND-01` | HG00438 (haplotype-resolved) | 1% |
| 52 | `SYN-NEU-02` | HG00733 (haplotype-resolved) | 10% |
| 53 | `SYN-NEU-03` | NA19240 (haplotype-resolved) | 20% |

`SYN-CHM13-08` and `-09` repeat the 5% and 10% fractions under different seeds,
which separates seed-to-seed variation from fraction effects.

In `per_library.csv` the nine `SYN-CHM13-*` libraries are `condition =
synthetic_matched`; `SYN-IND-01`, `SYN-NEU-02` and `SYN-NEU-03` are
`synthetic_mismatch`.

### Generating the whole panel

```bash
set -euo pipefail

# seed:library:human_source:fraction
PANEL="
42:SYN-CHM13-01:chm13:0.001
43:SYN-CHM13-02:chm13:0.005
44:SYN-CHM13-03:chm13:0.01
45:SYN-CHM13-04:chm13:0.05
46:SYN-CHM13-05:chm13:0.10
47:SYN-CHM13-06:chm13:0.20
48:SYN-CHM13-07:chm13:0.40
49:SYN-CHM13-08:chm13:0.05
50:SYN-CHM13-09:chm13:0.10
51:SYN-IND-01:HG00438:0.01
52:SYN-NEU-02:HG00733:0.10
53:SYN-NEU-03:NA19240:0.20
"

for ENTRY in $PANEL; do
    IFS=: read -r SEED LABEL SRC FRACTION <<<"$ENTRY"
    python ../scripts/mix_spikein.py \
        --background-r1 background_R1.fastq.gz \
        --background-r2 background_R2.fastq.gz \
        --human-r1 "human_${SRC}_seed42_R1.fq" \
        --human-r2 "human_${SRC}_seed42_R2.fq" \
        --fraction "$FRACTION" \
        --total-pairs 2000000 \
        --seed "$SEED" \
        --out-prefix "../data/synthetic/${LABEL}"
done
```

---

## Determinism

`mix_spikein.py` seeds a private `random.Random(seed)` and uses reservoir
sampling, so a given (seed, inputs, fraction, total-pairs) always yields a
byte-identical library. ART is seeded with `-rs`. Re-running the panel on a
different machine reproduces the same libraries provided the input genomes and
tool versions match; record those versions with `conda list --explicit`.

Because the panel is deterministic, the three replicate runs in E3/E5 differ
only in tool runtime and memory. Replicate accuracy columns being *identical*
is the expected result, not a defect — see the replicate-spacing check in
`../run/audit.py`.
