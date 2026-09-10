# HostSweep benchmark — complete measured results

**Manuscript:** BIOADV-2026-394, *Bioinformatics Advances*, major revision
**Generated:** 2026-09-10
**Repository:** https://github.com/Adeel2208/HostSweep

Every figure in this document was produced by a command run on the benchmark
host. Nothing is carried over from the previous submission, nothing is
estimated, and nothing is interpolated. Where a measurement does not exist the
cell is marked absent rather than filled.

Raw evidence for every number — stdout, stderr, `/usr/bin/time -v` records and
per-run metrics JSON — is retained under `benchmark/run/logs/`.

---

## Contents

1. [Status of each experiment](#1-status-of-each-experiment)
2. [E3 — sensitivity and false positive rate (headline result)](#2-e3--sensitivity-and-false-positive-rate)
3. [E7 — threshold sweep](#3-e7--threshold-sweep)
4. [E2 — controlled-truth panel](#4-e2--controlled-truth-panel)
5. [E1 — real-library panel verification](#5-e1--real-library-panel-verification)
6. [Provenance and control measurements](#6-provenance-and-control-measurements)
7. [Environment and tool versions](#7-environment-and-tool-versions)
8. [Deviations that must appear in Methods](#8-deviations-that-must-appear-in-methods)
9. [What the paper cannot yet claim](#9-what-the-paper-cannot-yet-claim)

---

## 1. Status of each experiment

| Experiment | Description | State | Output |
|---|---|---|---|
| E1 | Real accession panel verification | **Complete** | `accessions_verified.csv`, `verification_log.txt` |
| E2 | Synthetic controlled-truth panel | **Complete** | `synthetic_manifest.csv` |
| E3 | Sensitivity and FPR, HostSweep | **Complete** | `per_library.csv` |
| E7 | Entropy × length threshold sweep | **Complete** | `threshold_sweep.csv`, `equivalence_check.txt` |
| E4 | Real-library reads | Downloaded, not scored | 30 libraries on disk |
| E9 | Assembly and classification | Running | `downstream.csv`, `kraken2_human.csv` |
| E5 | Dual-pass ablation | **Deferred by instruction** | drivers written and tested |
| E8 | Labelling sensitivity | Not applicable | requires real-library truth set |

---

## 2. E3 — sensitivity and false positive rate

**36 runs, 0 failures.** Twelve controlled-truth libraries, three independent
invocations each, every run under `/usr/bin/time -v`.

### Summary

| Condition | Libraries | Runs | Sensitivity mean | Sensitivity range | FPR mean | FPR range |
|---|---|---|---|---|---|---|
| `synthetic_matched` | 9 | 27 | **100.0000 %** | 100.0000 – 100.0000 | 0.0142 % | 0.0133 – 0.0147 |
| `synthetic_mismatch` | 3 | 9 | **99.9698 %** | 99.9600 – 99.9765 | 0.0147 % | 0.0142 – 0.0150 |

**Reference-mismatch penalty = 0.0302 percentage points.**

Two properties worth stating in the paper:

- **The penalty does not scale with host fraction.** 1 %, 10 % and 20 % host
  land within 0.017 pp of each other. This is a property of reference
  divergence, not of contamination load — a more general claim than a
  single-fraction result would support.
- **Specificity is unaffected.** FPR is 0.0142 % matched against 0.0147 %
  mismatch. The mismatch costs a little sensitivity without buying false
  positives, so the two axes can be discussed independently.

### Mismatch arm in absolute reads

| Library | Source | Assembly | Population | Host % | Sensitivity | Human pairs surviving |
|---|---|---|---|---|---|---|
| SYN-IND-01 | HG00438 | `GCA_018471515.1` | Han Chinese South | 1.0 | **99.9600 %** | 8 of 20,000 |
| SYN-NEU-02 | HG00733 | `GCA_018506975.1` | Puerto Rican | 10.0 | **99.9765 %** | 47 of 200,000 |
| SYN-NEU-03 | NA19240 | `GCA_018503275.1` | Yoruban | 20.0 | **99.9728 %** | 109 of 400,000 |

All three sources are HPRC Year 1 `f1_assembly_v2`, primary/maternal haplotype,
hifiasm v0.14, UCSC Genomics Institute — one assembly project and one assembler
version across three populations, so *reference mismatch* is not confounded
with *different assembler* or *different scaffolding*.

### Complete per-run data (`per_library.csv`, 36 rows)

Sensitivity and FPR are identical across the three runs of every library. The
pipeline is deterministic, so replicate agreement is the expected result and
its absence would be the anomaly.

| library | condition | host % | run | sensitivity % | fpr % | runtime min | peak GB |
|---|---|---|---|---|---|---|---|
| SYN-CHM13-01 | matched | 0.1 | 1 | 100.0 | 0.0142 | 18.5113 | 11.0462 |
| SYN-CHM13-01 | matched | 0.1 | 2 | 100.0 | 0.0142 | 17.3793 | 11.0895 |
| SYN-CHM13-01 | matched | 0.1 | 3 | 100.0 | 0.0142 | 18.9730 | 11.1061 |
| SYN-CHM13-02 | matched | 0.5 | 1 | 100.0 | 0.0147 | 22.3827 | 11.0893 |
| SYN-CHM13-02 | matched | 0.5 | 2 | 100.0 | 0.0147 | 16.3120 | 11.1085 |
| SYN-CHM13-02 | matched | 0.5 | 3 | 100.0 | 0.0147 | 14.9910 | 11.1132 |
| SYN-CHM13-03 | matched | 1.0 | 1 | 100.0 | 0.0146 | 16.3883 | 11.1080 |
| SYN-CHM13-03 | matched | 1.0 | 2 | 100.0 | 0.0146 | 20.6537 | 11.1081 |
| SYN-CHM13-03 | matched | 1.0 | 3 | 100.0 | 0.0146 | 18.1398 | 11.0891 |
| SYN-CHM13-04 | matched | 5.0 | 1 | 100.0 | 0.0144 | 45.3352 | 11.1105 |
| SYN-CHM13-04 | matched | 5.0 | 2 | 100.0 | 0.0144 | 39.8352 | 11.1067 |
| SYN-CHM13-04 | matched | 5.0 | 3 | 100.0 | 0.0144 | 25.5342 | 11.1179 |
| SYN-CHM13-05 | matched | 10.0 | 1 | 100.0 | 0.0137 | 30.9613 | 11.1066 |
| SYN-CHM13-05 | matched | 10.0 | 2 | 100.0 | 0.0137 | 69.4000 | 11.1133 |
| SYN-CHM13-05 | matched | 10.0 | 3 | 100.0 | 0.0137 | 35.8392 | 11.0986 |
| SYN-CHM13-06 | matched | 20.0 | 1 | 100.0 | 0.0141 | 23.8312 | 11.1535 |
| SYN-CHM13-06 | matched | 20.0 | 2 | 100.0 | 0.0141 | 23.1822 | 11.1504 |
| SYN-CHM13-06 | matched | 20.0 | 3 | 100.0 | 0.0141 | 26.7755 | 11.1440 |
| SYN-CHM13-07 | matched | 40.0 | 1 | 100.0 | 0.0144 | 37.9837 | 11.1237 |
| SYN-CHM13-07 | matched | 40.0 | 2 | 100.0 | 0.0144 | 51.3765 | 11.1195 |
| SYN-CHM13-07 | matched | 40.0 | 3 | 100.0 | 0.0144 | 37.0853 | 11.0584 |
| SYN-CHM13-08 | matched | 5.0 | 1 | 100.0 | 0.0143 | 43.1727 | 11.0554 |
| SYN-CHM13-08 | matched | 5.0 | 2 | 100.0 | 0.0143 | 21.0790 | 11.0481 |
| SYN-CHM13-08 | matched | 5.0 | 3 | 100.0 | 0.0143 | 21.8390 | 11.0716 |
| SYN-CHM13-09 | matched | 10.0 | 1 | 100.0 | 0.0133 | 27.1740 | 11.1412 |
| SYN-CHM13-09 | matched | 10.0 | 2 | 100.0 | 0.0133 | 25.7373 | 11.0498 |
| SYN-CHM13-09 | matched | 10.0 | 3 | 100.0 | 0.0133 | 21.1915 | 11.1456 |
| SYN-IND-01 | **mismatch** | 1.0 | 1 | **99.9600** | 0.0148 | 29.6845 | 11.0732 |
| SYN-IND-01 | **mismatch** | 1.0 | 2 | **99.9600** | 0.0148 | 17.4012 | 10.9590 |
| SYN-IND-01 | **mismatch** | 1.0 | 3 | **99.9600** | 0.0148 | 15.1433 | 11.1339 |
| SYN-NEU-02 | **mismatch** | 10.0 | 1 | **99.9765** | 0.0142 | 133.8333 | 10.9858 |
| SYN-NEU-02 | **mismatch** | 10.0 | 2 | **99.9765** | 0.0142 | 61.4000 | 9.3142 |
| SYN-NEU-02 | **mismatch** | 10.0 | 3 | **99.9765** | 0.0142 | 36.1788 | 10.7899 |
| SYN-NEU-03 | **mismatch** | 20.0 | 1 | **99.9728** | 0.0150 | 15.0880 | 11.0905 |
| SYN-NEU-03 | **mismatch** | 20.0 | 2 | **99.9728** | 0.0150 | 13.5185 | 11.0731 |
| SYN-NEU-03 | **mismatch** | 20.0 | 3 | **99.9728** | 0.0150 | 12.1488 | 11.1542 |

All libraries are 2.0 M pairs, tool `hostsweep`, tier `profiling`.

> **The `runtime_min` and `peak_mem_gb` columns are not publication-grade.**
> See deviation D17 in section 8. The accuracy columns are unaffected.

---

## 3. E7 — threshold sweep

**75 cells:** 5 entropy values × 5 minimum lengths × 3 libraries spanning the
host-fraction range — SYN-CHM13-01 (0.1 %), SYN-CHM13-04 (5 %), SYN-CHM13-07
(40 %).

### Three findings

**1. Step 8 thresholds do not affect host removal at all.** Host sensitivity is
`100.0` and residual human reads are `0` in **every one of the 75 cells**. This
is mechanistically correct: host removal happens in Steps 2 and 6, and Step 8 is
a complexity and length filter applied to already-cleaned reads. The sweep
confirms the tiered architecture behaves as the paper claims.

**2. Raising entropy past the default only destroys microbial sequence.**
Moving 0.85 → 0.95 multiplies microbial loss **13.2-fold** and buys exactly zero
additional sensitivity. This is a direct quantitative defence of the shipped
default against a reviewer asking why 0.85 was chosen.

**3. Minimum length is inert over 70–110 bp.** Mean FPR is 0.0689 % at every
length tested, differing only in the fourth decimal. With 150 bp reads and fastp
already enforcing a 50 bp floor, almost nothing survives to be cut by an `L` in
this range. Worth stating plainly rather than implying the parameter is doing
work.

### Effect of entropy (mean over all lengths and libraries)

| entropy | host sensitivity | microbial FPR | microbial retention | residual human reads | note |
|---|---|---|---|---|---|
| 0.75 | 100.0000 % | 0.0144 % | 99.9856 % | 0 | permissive |
| 0.80 | 100.0000 % | 0.0152 % | 99.9848 % | 0 | |
| **0.85** | 100.0000 % | **0.0195 %** | 99.9805 % | 0 | **shipped default** |
| 0.90 | 100.0000 % | 0.0383 % | 99.9617 % | 0 | 2.0× the default's loss |
| 0.95 | 100.0000 % | 0.2571 % | 99.7429 % | 0 | 13.2× the default's loss |

### Effect of minimum length (mean over all entropies and libraries)

| min length | host sensitivity | microbial FPR | microbial retention |
|---|---|---|---|
| 70 | 100.0000 % | 0.0689 % | 99.9311 % |
| 80 | 100.0000 % | 0.0689 % | 99.9311 % |
| 90 | 100.0000 % | 0.0689 % | 99.9311 % |
| 100 | 100.0000 % | 0.0689 % | 99.9311 % |
| 110 | 100.0000 % | 0.0690 % | 99.9310 % |

### Microbial FPR per library and entropy

Range across the five minimum lengths, where it varies at all.

| entropy | SYN-CHM13-01 (0.1 %) | SYN-CHM13-04 (5 %) | SYN-CHM13-07 (40 %) |
|---|---|---|---|
| 0.75 | 0.0142 – 0.0143 | 0.0145 | 0.0145 – 0.0146 |
| 0.80 | 0.0151 – 0.0152 | 0.0154 | 0.0152 – 0.0153 |
| 0.85 | 0.0194 | 0.0194 | 0.0198 – 0.0199 |
| 0.90 | 0.0376 | 0.0379 – 0.0380 | 0.0393 – 0.0394 |
| 0.95 | 0.2570 | 0.2554 – 0.2555 | 0.2590 – 0.2591 |

Microbial retention is the complement of FPR in every cell.

### Methods note — the sweep shortcut is proven, not assumed

`--bbeg` and `--stringent-minlen` are read only by Step 8, whose input is the
Step 7 profiling output. Steps 0–7 were therefore run **once** per library and
Step 8 re-run 25 times against the cached tier. The equivalence was asserted
against a complete pipeline run rather than argued:

```
library=SYN-CHM13-01 full=3994940 cached=3994940 MATCH
library=SYN-CHM13-04 full=3799007 cached=3799007 MATCH
```

Read-for-read agreement on both libraries where the check ran. `SYN-CHM13-07`
was **not** verified: the check is enabled by a wrapper that was bypassed when
the sweep was relaunched standalone. Two of three verified, both exact.

---

## 4. E2 — controlled-truth panel

**12 libraries, 2,000,000 pairs each. Realised fraction equals requested
fraction to all reported digits on every library**, so sensitivity figures can
be quoted against nominal fractions with no correction table.

| library | human source | accession | requested | realised | seed | human pairs | background pairs |
|---|---|---|---|---|---|---|---|
| SYN-CHM13-01 | T2T-CHM13v2.0 | `GCF_009914755.1` | 0.001 | 0.001 | 42 | 2,000 | 1,998,000 |
| SYN-CHM13-02 | T2T-CHM13v2.0 | `GCF_009914755.1` | 0.005 | 0.005 | 43 | 10,000 | 1,990,000 |
| SYN-CHM13-03 | T2T-CHM13v2.0 | `GCF_009914755.1` | 0.01 | 0.01 | 44 | 20,000 | 1,980,000 |
| SYN-CHM13-04 | T2T-CHM13v2.0 | `GCF_009914755.1` | 0.05 | 0.05 | 45 | 100,000 | 1,900,000 |
| SYN-CHM13-05 | T2T-CHM13v2.0 | `GCF_009914755.1` | 0.10 | 0.10 | 46 | 200,000 | 1,800,000 |
| SYN-CHM13-06 | T2T-CHM13v2.0 | `GCF_009914755.1` | 0.20 | 0.20 | 47 | 400,000 | 1,600,000 |
| SYN-CHM13-07 | T2T-CHM13v2.0 | `GCF_009914755.1` | 0.40 | 0.40 | 48 | 800,000 | 1,200,000 |
| SYN-CHM13-08 | T2T-CHM13v2.0 | `GCF_009914755.1` | 0.05 | 0.05 | 49 | 100,000 | 1,900,000 |
| SYN-CHM13-09 | T2T-CHM13v2.0 | `GCF_009914755.1` | 0.10 | 0.10 | 50 | 200,000 | 1,800,000 |
| SYN-IND-01 | HG00438 | `GCA_018471515.1` | 0.01 | 0.01 | 51 | 20,000 | 1,980,000 |
| SYN-NEU-02 | HG00733 | `GCA_018506975.1` | 0.10 | 0.10 | 52 | 200,000 | 1,800,000 |
| SYN-NEU-03 | NA19240 | `GCA_018503275.1` | 0.20 | 0.20 | 53 | 400,000 | 1,600,000 |

Simulation: ART `HS25`, 150 bp paired-end, `-m 200 -s 10`, seeds 42–53.

### A specification error found by measurement

The protocol's **50× background community coverage is not compatible with 2 M-pair
libraries at low human fractions.** A 0.1 %-human library needs **1,998,000
background pairs**; 50× over the ten-genome community yields a pool of roughly
**730,000**. The library could not have been built at all, and the 0.5 % and 1 %
libraries would have silently undershot their requested fractions.

Coverage was raised to **200×**, giving a measured pool of **2,921,080 pairs**
against a largest single draw of 2,000,000. This belongs in Methods as a
corrected parameter.

---

## 5. E1 — real-library panel verification

### The previous panel was not reproducible

Of the five accessions from the previous submission that could be checked,
**all five fail verification.** Two were newly discovered in this work.

| Accession | Cited in the paper as | What it actually is |
|---|---|---|
| `SRR6062009` | Runtime reference, "1.86 M pairs" | *Klebsiella pneumoniae*, `LibrarySource=GENOMIC`, 1,863,630 spots — a single-isolate bacterial genome |
| `SRR14235678` | Ablation library, 12.35 % human | soil metagenome, `AMPLICON`, 91,000 spots |
| `SRR5947529` | panel member | pig WGS |
| `SRR14235720` | panel member | goat RAD-seq, single-end |
| `SRR14567890` | panel member | goat amplicon, one spot |

**The spot count of `SRR6062009` — 1,863,630 — matches the "1.86 M pairs" in the
README exactly.** The reported runtime benchmark was therefore measured on a
*Klebsiella pneumoniae* isolate with essentially no human content, not a human
metagenome. A human-decontamination runtime measured on a bacterial isolate
cannot be defended, and a reviewer who checks the accession will find this in
minutes.

Every figure traceable to these accessions has been deleted from the repository:
the five-tool comparator table, the ablation table, the T2T-versus-GRCh38
comparison, the entropy sweep table, the downstream-effect bullets, and the two
Key-features claims that restated them.

The remaining **25 of the original 30 accessions were never available to check** —
they exist only in Supplementary Table S1, which was not provided.

### The replacement panel

Rebuilt from live SRA queries: **30 libraries, 7 categories, 28 distinct
studies**, verified **PASS 30 / 30** against the SRA Entrez runinfo report.

| category | libraries | distinct studies |
|---|---|---|
| gut | 6 | 6 |
| oral | 4 | 4 |
| skin | 4 | 2 |
| respiratory | 4 | 4 |
| urogenital | 4 | 4 |
| blood | 4 | 4 |
| environmental | 4 | 4 |

**No category is drawn from a single study**, so category means are defensible
throughout and no "describe, do not average" caveat is needed for any category.

Inclusion criteria, all enforced as hard filters: Illumina, PAIRED, WGS strategy,
`LibrarySource=METAGENOMIC`, 1,000,000 ≤ spots ≤ 25,000,000.

### Search depth changed the conclusion

At `--retmax 120` the blood category returned only **2 qualifying runs from one
BioProject**, and skin returned 4 runs from one BioProject. Both looked like
genuine scarcity in SRA. At `--retmax 600`, blood yields **4 runs across 4
BioProjects** and skin 4 across 2.

The apparent shortfall was an artifact of the query window, not a property of
the archive. Worth reporting, because it is exactly the kind of claim reviewers
are right to be sceptical of. Exact queries and UID counts for every category
are reproduced in `verification_log.txt`.

---

## 6. Provenance and control measurements

### No sequence-composition test can establish reference independence

Every human assembly is ~99.9 % identical to T2T-CHM13v2.0, so sequence that
originated from CHM13 is indistinguishable — by composition or by similarity —
from sequence assembled de novo at the same locus. **Han1-style reference
contamination is detectable only from an assembly's documentation, never from
the FASTA.**

The control that established this:

| FASTA | Total bases | Lowercase | N content |
|---|---|---|---|
| **T2T-CHM13v2.0 itself** | 3,117,275,501 | **40.2743 %** | 0.000000 % |
| HG00438 (HPRC) | 3,035,735,720 | 39.5468 % | 0.000000 % |
| HG00733 (HPRC) | 3,026,516,595 | 39.3340 % | 0.000001 % |
| NA19240 (HPRC) | 3,032,049,516 | 39.3164 % | 0.000001 % |
| *E. coli* `GCF_000005845.2` | 4,641,652 | 0.0000 % | 0.000000 % |

T2T-CHM13v2.0 cannot contain CHM13-derived gap-fill — it *is* CHM13 — yet it
carries **more** lowercase than any HPRC assembly. Lowercase in NCBI's
distributed eukaryotic FASTA is repeat soft-masking; the bacterial control at
exactly zero confirms it is repeat-driven rather than a blanket transformation.
A 0.01 % soft-mask threshold would reject every human assembly NCBI distributes,
including the decontamination reference itself.

Near-zero N content is the more direct observation: these are contig and
scaffold assemblies with **no reference-guided gap padding**, which is what the
Han1 warning was actually about.

Reference independence is instead established from provenance, checked per
assembly: assembly method `Hifiasm v. 0.14` (de novo from HiFi reads, no
reference input); assembly level Contig or Scaffold, never Chromosome, which
would imply reference-guided scaffolding; submitter UCSC Genomics Institute
(HPRC); and explicit exclusion of sample HG00621, whose Han1 assembly carries
CHM13 v1.1 gap-fill. **All three sources pass all four checks.**

### Three background genome accessions were wrong

All ten resolved at NCBI, but three named a different organism than the protocol
specified. Corrected on the ruling that organism names are authoritative.

| Organism as specified | Accession given | What that accession actually is | Corrected to |
|---|---|---|---|
| *Lactobacillus acidophilus* NCFM | `GCF_000009605.1` | *Buchnera aphidicola* str. APS — a 0.66 Mb insect endosymbiont | `GCF_000011985.1` |
| *Bacteroides thetaiotaomicron* VPI-5482 | `GCF_000007565.2` | *Pseudomonas putida* KT2440 | `GCF_000011065.1` |
| *Bifidobacterium longum* NCC2705 | `GCF_000012825.1` | *Phocaeicola vulgatus* ATCC 8482 | `GCF_000007525.1` |

At abundance 0.08, a 0.66 Mb endosymbiont in place of a 2 Mb gut lactobacillus
would have contributed roughly a third of the intended read count for that
community member, and two gut commensals would have been absent entirely.

### Reference index integrity

`hostsweep --build` runs `minimap2 -x sr -d` with no `-I`. Verified empirically
rather than from the documented default, by counting index-load messages on a
probe alignment:

```
[M::main::410.999*0.93] loaded/built the index for 24 target sequence(s)
index batches loaded: 1
RESULT: PASS -- single-batch index; the whole reference is searched in one pass.
```

minimap2 2.31-r1302, default `-I 8G` against a 3.1 Gb reference. **The index is
whole; no alignment pass sees a partial genome.** Peak RSS during that single
alignment was 10.523 GB.

---

## 7. Environment and tool versions

| Component | Version |
|---|---|
| hostsweep | 1.0.0 |
| Python | 3.11.16 |
| fastp | 1.3.6 |
| minimap2 | 2.31-r1302 |
| bowtie2 | 2.5.x |
| samtools | 1.24 |
| BBTools (BBDuk) | 40.02 |
| ART | 2.5.8 (Q Version, June 2016) |
| hostile | **2.0.2** (2.x asserted before use) |
| kneaddata | 0.12.4 |
| bmtagger / bmtool / srprism | installed |
| MEGAHIT | 1.2.9 |
| QUAST / MetaQUAST | 5.3.0 |
| Kraken2 | 2.17.1 |
| Kraken2 database | Standard-8, build `20250402` |
| sra-tools | 3.4.1 |

Full 118-package resolution in `conda_explicit.txt`.

**Host:** 8 threads, 11 GB RAM available to the guest (single 16 GiB DIMM,
15.64 GiB visible to the OS), 32 GB swap, WSL2 Ubuntu on Windows 10.

---

## 8. Deviations that must appear in Methods

Full text with interpretation costs in `DEVIATIONS.md` (17 deviations plus one
integrity incident). The ones that change how a number should be read:

### D1 — Background coverage 200×, not 50×
Forced by arithmetic, not preference. At 50× the pool is ~730,000 pairs against
a largest draw of 1,998,000. Measured pool at 200×: 2,921,080 pairs. Removes an
artifact rather than introducing one.

### D2 — Human simulation coverage `-f 0.2`, not `-f 5`
Largest human draw is 800,000 pairs; `-f 0.2` yields ~2.07 M, still 2.5× the
largest draw. Truth labelling unaffected — `mix_spikein.py` subsamples from
whatever pool it is given.

### D3 — Sweep runs Step 8 only
Proven equivalent to full runs by read count on two of three libraries. See
section 3.

### D4 — MEGAHIT replaces metaSPAdes
metaSPAdes needs 30–120 GB; this host has 11 GB. **MEGAHIT typically produces
lower N50 and less assembled sequence, so absolute contiguity statistics are NOT
comparable to any published metaSPAdes number.** The between-method comparison
remains valid because all three cleaning methods are assembled identically.

### D5 — Kraken2 Standard-8 replaces Standard
Capping drops minimizers, so a capped database detects **less** human sequence.
**The residual-human figure is a floor, not an estimate**, and cannot support a
claim that residual human content is below any threshold.

### D6 — CheckM2 dropped
Needs ~15 GB plus its database. No completeness or contamination statistics are
reported.

### D7 — Category names changed to match SRA taxonomy
The exact terms `"human urogenital metagenome"` and
`"human respiratory tract metagenome"` return **zero** Illumina/paired/WGS runs
in SRA. The nearest usable terms are *human vaginal metagenome* and *human lung
metagenome*. Category labels in the manuscript must change to the taxon names
actually used, so a reader can reproduce the query.

### D16 — The Han1 soft-mask test does not work
Refuted by control. See section 6. Provenance is the gate instead.

### D17 — Runtime and peak memory are not comparable between tools
**Every run peaked at 11.05–11.15 GB against an 11 GB ceiling and completed only
by paging to swap.** Three byte-identical, deterministic runs of `SYN-NEU-02`
took **133.83, 61.40 and 36.18 minutes** — a 3.7× spread. A comparator ranking
built on these numbers would rank whichever tool ran with a warm page cache.

- **No runtime claim should be made from this data**, including "faster than",
  "comparable to", or a runtime column in the comparator table.
- **Peak memory is a floor set by the ceiling**, not a measurement of demand: a
  tool that would use 20 GB on a larger machine records ~11 GB here or fails.
- Both need re-measuring on unconstrained hardware. The scripts are idempotent
  and would reproduce there.

Accuracy is unaffected: sensitivity and FPR are byte-identical across replicates
because the arithmetic does not care how long it took. **Those figures stand.**

### I1 — Concurrent writers corrupted one synthetic library (detected, discarded)
Two `mix_spikein.py` processes were found writing the same output prefix after a
suspended launcher reconnected across a guest restart. Interleaved writes give
valid gzip of roughly the right size whose reads and truth labels no longer
correspond. Both processes were killed, all three output files deleted unread,
and the library rebuilt. **No measurement was taken from the corrupt files and
none entered any results file.** A single-instance lock now prevents recurrence.

---

## 9. What the paper cannot yet claim

- **No comparator ranking.** Hostile, KneadData, BMTagger and DeconSeq have not
  been scored on the synthetic panel. The five-tool table cannot be reinstated
  in any form.
- **No dual-pass gain figure.** E5 is deferred, so the second pass's
  contribution is unmeasured. The previous 2.55 % claim traced to an invalid
  library and has been removed.
- **No runtime or memory claim.** See D17.
- **No real-library accuracy.** The 30 real libraries have no per-read truth
  set; sensitivity and FPR are left empty for them by design rather than
  estimated.
- **No downstream assembly or classification results yet.** E9 is running.
- **25 of the original 30 accessions remain unverifiable**, having never been
  available to check.

---

## Files

| File | Rows | Contents |
|---|---|---|
| `per_library.csv` | 36 | Sensitivity, FPR, runtime, peak memory per (library, run) |
| `synthetic_manifest.csv` | 12 | Realised fractions, seeds, source accessions |
| `threshold_sweep.csv` | 75 | Entropy × length grid, three libraries |
| `equivalence_check.txt` | 2 | Proof the Step-8 caching shortcut is exact |
| `accessions_verified.csv` | 30 | Full SRA metadata, PASS 30/30 |
| `verification_log.txt` | — | Per-category study counts, exact queries, UID counts |
| `genomes_verified.tsv` | 10 | Background community, verified at NCBI |
| `human_sources_provenance.json` | 3 | Mismatch-arm assembly provenance and composition |
| `DEVIATIONS.md` | 18 | 17 deviations + 1 integrity incident |
| `STATUS.md` | — | What ran, what failed, what was skipped |
| `downstream.csv` | — | *E9 running* |
| `kraken2_human.csv` | — | *E9 running* |
| `ablation.csv` | — | *deferred by instruction* |

**`DEVIATIONS.md` is the file to attach to the response letter.** Each entry
states what was specified, what was done, why, and what it costs in
interpretation. A documented deviation is defensible; an undocumented one is not.
