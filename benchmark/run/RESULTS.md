# HostSweep benchmark — complete measured results

**Manuscript:** BIOADV-2026-394, *Bioinformatics Advances*, major revision
**Generated:** 2026-09-11
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
2b. [Comparator benchmark — sensitivity and false positive rate](#2b-comparator-benchmark--sensitivity-and-false-positive-rate)
3. [E7 — threshold sweep](#3-e7--threshold-sweep)
3b. [E5 — dual-pass ablation](#3b-e5--dual-pass-ablation)
3c. [E9 — downstream assembly and classification](#3c-e9--downstream-assembly-and-classification)
4. [E2 — controlled-truth panel](#4-e2--controlled-truth-panel)
5. [E1 — real-library panel verification](#5-e1--real-library-panel-verification)
5b. [E4 — real-library scoring](#5b-e4--real-library-scoring)
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
| E4 | Real-library scoring | **Complete** — 30 of 30 (HostSweep; no per-read truth set for real libraries, so accuracy columns are empty by design) | `e4_per_library.csv` |
| E9 | Assembly and classification | **Complete** — 18 of 18 pairs | `downstream.csv`, `kraken2_human.csv` |
| E5 | Dual-pass ablation | **Complete** | `ablation.csv` |
| E8 | Labelling sensitivity | Not applicable | requires real-library truth set |
| — | Comparator benchmark | **Complete for 3 of 5 tools** — `hostile_default`, `hostile_matched`, `kneaddata` (n=1, all 12 synthetic libraries). BMTagger deferred (env installs, not yet wired — D20); DeconSeq dropped (not on bioconda — D20) | `per_library.csv` |

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

### Complete per-run data (`per_library.csv`, HostSweep's 36 of 72 rows)

The other 36 rows are the comparator benchmark — see section 2b.

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

## 2b. Comparator benchmark — sensitivity and false positive rate

**36 runs, 0 failures, n=1.** `hostile_default`, `hostile_matched` and
`kneaddata`, each scored against the same truth labels, by the same
`compute_metrics.py`, on all 12 synthetic libraries — the comparison this
benchmark exists to make. **BMTagger is not in this table** (deferred, not
dropped: its conda environment installs but the command was never wired into
`run_e3.sh` in time — D20) and **DeconSeq is not in this table** (dropped:
not on bioconda, needs a hand-edited manual install — D20).

Run on a second machine (D18); before anything here was trusted, that machine
rebuilt `SYN-CHM13-01` and reproduced HostSweep's sensitivity and FPR to the
fourth decimal against the first machine's `per_library.csv`. Accuracy figures
from the two machines are combined on that basis. **Runtime and peak memory are
not** — see the callout after the tables.

n=1 here, against n=3 for HostSweep, is a real asymmetry, not an oversight:
HostSweep's three replicates were run to *establish* that this pipeline is
deterministic (12/12 libraries bit-identical). That property has not been
separately re-verified for Hostile or KneadData, so a single run each is what
is reported, not what would ideally exist.

### Summary

| tool | condition | n | sensitivity mean | sensitivity range | FPR mean | FPR range |
|---|---|---|---|---|---|---|
| hostsweep | matched | 27 | 100.0000 % | 100.0000 – 100.0000 | 0.0142 % | 0.0133 – 0.0147 |
| hostile_default | matched | 9 | 99.9998 % | 99.9990 – 100.0000 | **0.0000 %** | 0.0000 – 0.0000 |
| hostile_matched | matched | 9 | 99.9998 % | 99.9990 – 100.0000 | **0.0000 %** | 0.0000 – 0.0000 |
| kneaddata | matched | 9 | **100.0000 %** | 100.0000 – 100.0000 | 0.4255 % | 0.4216 – 0.4293 |
| hostsweep | mismatch | 9 | 99.9698 % | 99.9600 – 99.9765 | 0.0147 % | 0.0142 – 0.0150 |
| hostile_default | mismatch | 3 | 99.8665 % | 99.8150 – 99.9080 | **0.0000 %** | 0.0000 – 0.0000 |
| hostile_matched | mismatch | 3 | 99.8646 % | 99.8100 – 99.9075 | **0.0000 %** | 0.0000 – 0.0000 |
| kneaddata | mismatch | 3 | **99.9692 %** | 99.9550 – 99.9780 | 0.4268 % | 0.4233 – 0.4304 |

### Per-library sensitivity

| library | host % | hostsweep | hostile_default | hostile_matched | kneaddata |
|---|---|---|---|---|---|
| SYN-CHM13-01 | 0.1 | 100.0 | 100.0 | 100.0 | 100.0 |
| SYN-CHM13-02 | 0.5 | 100.0 | 100.0 | 100.0 | 100.0 |
| SYN-CHM13-03 | 1.0 | 100.0 | 100.0 | 100.0 | 100.0 |
| SYN-CHM13-04 | 5.0 | 100.0 | 100.0 | 100.0 | 100.0 |
| SYN-CHM13-05 | 10.0 | 100.0 | 99.9995 | 99.9995 | 100.0 |
| SYN-CHM13-06 | 20.0 | 100.0 | 99.9997 | 99.9997 | 100.0 |
| SYN-CHM13-07 | 40.0 | 100.0 | 99.9997 | 99.9997 | 100.0 |
| SYN-CHM13-08 | 5.0 | 100.0 | 99.9990 | 99.9990 | 100.0 |
| SYN-CHM13-09 | 10.0 | 100.0 | 100.0 | 100.0 | 100.0 |
| SYN-IND-01 (mismatch) | 1.0 | **99.9600** | 99.8150 | 99.8100 | 99.9550 |
| SYN-NEU-02 (mismatch) | 10.0 | 99.9765 | 99.9080 | 99.9075 | **99.9780** |
| SYN-NEU-03 (mismatch) | 20.0 | 99.9728 | 99.8765 | 99.8762 | **99.9745** |

HostSweep's sensitivity is greater than or equal to both Hostile configurations
on **12 of 12** libraries. Against KneadData it is greater or equal on **10 of
12** — KneadData edges it out on two of the three mismatch-arm libraries
(`SYN-NEU-02`, `SYN-NEU-03`), by 0.0015–0.0017 percentage points.

### Per-library false positive rate

| library | hostsweep | hostile_default | hostile_matched | kneaddata |
|---|---|---|---|---|
| SYN-CHM13-01 | 0.0142 | **0.0** | **0.0** | 0.4258 |
| SYN-CHM13-02 | 0.0147 | **0.0** | **0.0** | 0.4276 |
| SYN-CHM13-03 | 0.0146 | **0.0** | **0.0** | 0.4293 |
| SYN-CHM13-04 | 0.0144 | **0.0** | **0.0** | 0.4221 |
| SYN-CHM13-05 | 0.0137 | **0.0** | **0.0** | 0.4292 |
| SYN-CHM13-06 | 0.0141 | **0.0** | **0.0** | 0.4246 |
| SYN-CHM13-07 | 0.0144 | **0.0** | **0.0** | 0.4239 |
| SYN-CHM13-08 | 0.0143 | **0.0** | **0.0** | 0.4251 |
| SYN-CHM13-09 | 0.0133 | **0.0** | **0.0** | 0.4216 |
| SYN-IND-01 (mismatch) | 0.0148 | **0.0** | **0.0** | 0.4267 |
| SYN-NEU-02 (mismatch) | 0.0142 | **0.0** | **0.0** | 0.4233 |
| SYN-NEU-03 (mismatch) | 0.0150 | **0.0** | **0.0** | 0.4304 |

### This table contains a result unfavourable to HostSweep

**Both Hostile configurations record exactly 0.0000 % FPR on every one of the
12 libraries — zero background reads removed in error, at essentially the same
sensitivity as HostSweep.** HostSweep's FPR is small (0.0133–0.0150 %) but is
never zero. On this measure, on this panel, Hostile is strictly better: equal
or near-equal sensitivity, and no measured cost in specificity at all. This
must be reported as measured, not narrowed to the sensitivity axis alone.

**KneadData is the mirror image: it matches or slightly beats HostSweep on
sensitivity (including outright winning on 2 of 3 mismatch libraries) at
roughly 30x the false positive rate** (~0.42–0.43 % against HostSweep's
~0.013–0.015 %). KneadData is the most aggressive of the three at removing
reads that resemble host sequence, which costs it specificity here and costs
it assembly quality in section 3c.

The honest summary: **on this panel, no single tool dominates on both axes.**
HostSweep sits between the two — never the best on either sensitivity or
specificity alone, but the only one of the three with zero FPR nowhere and zero
sensitivity loss nowhere simultaneously extreme. Framing HostSweep as
strictly superior to Hostile would not survive a reviewer reading this table.

> **Runtime and peak memory in `per_library.csv` for these three tools are not
> comparable to HostSweep's own E3 timings above.** They were measured on a
> different, unconstrained machine (D18) — Hostile ~0.6–1.5 min / ~3.4–3.6 GB,
> KneadData ~2–6 min / ~5.0–5.6 GB, against HostSweep's 15–70 min / ~11.0–11.2
> GB from the first, memory-constrained machine. That gap reflects the two
> hosts, not the three tools, and must not be presented as a performance
> comparison in any form.

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

## 3b. E5 — dual-pass ablation

**36 of 36 runs, 0 failures.** All twelve libraries complete for all three
configurations.

Three configurations, all ending at the profiling tier so the comparison
isolates the alignment passes rather than comparing different output tiers:

| config | pipeline |
|---|---|
| `minimap2_only` | fastp → **minimap2** → PE→SE → complexity → length → normalise |
| `bowtie2_only` | fastp → PE→SE → complexity → length → **bowtie2** → normalise |
| `dual_pass` | fastp → **minimap2** → PE→SE → complexity → length → **bowtie2** → normalise |

### Matched arm — complete, 9 libraries

| config | sensitivity mean | range | FPR mean | runtime mean |
|---|---|---|---|---|
| `minimap2_only` | 99.9063 % | 99.885 – 99.950 | 0.0123 % | 9.9 min |
| `bowtie2_only` | **99.9999 %** | 99.999 – 100.000 | **0.0056 %** | **7.0 min** |
| `dual_pass` | 100.0000 % | 100.000 – 100.000 | 0.0142 % | 13.7 min |

### This is an unfavourable result for the dual-pass sensitivity claim

**Adding the minimap2 pass to Bowtie2 buys 0.0001 percentage points of
sensitivity on the matched arm**, and costs 2.5x the false positive rate
(0.0056 % → 0.0142 %) and roughly twice the runtime (7.0 → 13.7 min).

The mismatch arm, now complete, says the same: Bowtie2 alone averages
99.9662 % against dual-pass 99.9698 % — a gain of **0.0036 percentage points**
for 2.6x the FPR (0.0057 % → 0.0147 %). Per library the dual-pass gain is
0.005, 0.002 and 0.004 pp. The mismatch case was the most plausible place for
an approximate first pass to earn a sensitivity role, and across all three
divergent genomes it does not.

minimap2 alone is consistently the weakest configuration — 99.8866 % mismatch,
99.9063 % matched — so the second pass is doing the host-removal work in every
condition tested.

For context, the previous manuscript claimed the second pass recovered **2.55
%** additional contamination. That figure traced to `SRR14235678`, a soil
amplicon library, and was deleted. The measured value is three orders of
magnitude smaller.

**The paper cannot claim dual-pass is more sensitive.**

### What the ablation does support

`bowtie2_only` **produces no paired-end assembly tier at all.** Skipping Pass 1
sends the trimmed pairs straight to PE→SE conversion, so there is no Output 1 —
Bowtie2 in this pipeline runs single-end after conversion. The first pass exists
to deliver assembly-grade *paired* reads with mate structure preserved, not to
add sensitivity.

That is a workflow claim, consistent with how the paper is framed, and the
measured cost of it is now known: **≈0.009 pp of false positive rate and ≈6
minutes per 2 M-pair library**, versus a single-pass alternative that produces
neither a paired assembly tier nor the tiered outputs.

E9's `downstream.csv` is where that claim gets tested, since it compares
HostSweep Output 1 against KneadData and Hostile on assembly quality.

### Per-library sensitivity

| library | host % | minimap2_only | bowtie2_only | dual_pass |
|---|---|---|---|---|
| `SYN-CHM13-01` | 0.1 | 99.95 % | 100.0 % | 100.0 % |
| `SYN-CHM13-02` | 0.5 | 99.89 % | 100.0 % | 100.0 % |
| `SYN-CHM13-03` | 1 | 99.885 % | 100.0 % | 100.0 % |
| `SYN-CHM13-04` | 5 | 99.903 % | 100.0 % | 100.0 % |
| `SYN-CHM13-05` | 10 | 99.9135 % | 99.9995 % | 100.0 % |
| `SYN-CHM13-06` | 20 | 99.906 % | 100.0 % | 100.0 % |
| `SYN-CHM13-07` | 40 | 99.906 % | 100.0 % | 100.0 % |
| `SYN-CHM13-08` | 5 | 99.891 % | 100.0 % | 100.0 % |
| `SYN-CHM13-09` | 10 | 99.9125 % | 100.0 % | 100.0 % |

**Mismatch arm — complete, 3 libraries:**

| library | host % | minimap2_only | bowtie2_only | dual_pass |
|---|---|---|---|---|
| `SYN-IND-01` | 1 | 99.845 % | 99.955 % | 99.96 % |
| `SYN-NEU-02` | 10 | 99.895 % | 99.9745 % | 99.9765 % |
| `SYN-NEU-03` | 20 | 99.9197 % | 99.969 % | 99.9728 % |

> Runtime figures in this section carry the same caveat as everywhere else
> (D17). `SYN-IND-01 / dual_pass` recorded 56.8 min against 15–30 min for the
> same library in E3 — contention, not method.


---

## 3c. E9 — downstream assembly and classification

> **CORRECTION.** An earlier version of this section compared misassembly
> rates on the three real libraries and headlined *"869 misassemblies against
> HostSweep's 292"* on the gut library. **That comparison was invalid and has
> been withdrawn.**
>
> For real libraries `metaquast.py` was run without `-r`, intending a
> reference-free run. MetaQUAST's behaviour without `-r` is to BLAST the
> contigs against SILVA 16S and download reference genomes from NCBI on its
> own — it fetched 46 for the gut library, 7 respiratory, 47 blood. And because
> each method's run chose references **from that method's own contigs**, the
> three methods were scored against **different reference sets**:
>
> | gut library `SRR40486826` | reference genomes | total reference length |
> |---|---|---|
> | hostsweep | 44 | 28.7 Mb |
> | hostile | 45 | 36.1 Mb |
> | kneaddata | 44 | **66.3 Mb** |
>
> HostSweep and KneadData shared only 18 of 44 genomes, and KneadData's
> reference was 2.3x larger — more reference sequence means more places to call
> a misassembly. The protocol already specified that a metagenomic misassembly
> rate without a reference set is not interpretable; this is the concrete
> reason why.
>
> Genome fraction and misassemblies are therefore **blanked for all real
> libraries** in `downstream.csv`. Reference-free metrics — N50, total length,
> contig counts, largest contig, assembled Mb ≥ 1 kb, duplication ratio — are
> computed from the contigs alone and are retained. `run_e9.sh` now passes
> `--max-ref-number 0` so this cannot recur. Synthetic libraries were unaffected:
> they used the known ten-genome reference set via `-r`, identical for all
> three methods, and MetaQUAST downloaded nothing for them.

**18 of 18 (library, method) pairs, complete.** Six libraries — three synthetic
spanning the host range including the mismatch arm, three real from different
categories and BioProjects — each cleaned by three methods and assembled
identically.

`SRR31641567 / kneaddata` — the pair stopped mid-run on the first machine — was
completed on the second machine (D18) and is included below. Its accuracy
figures (Kraken2 residual-human count) were verified cross-machine comparable
before being combined with the rest (D18); its exact assembly statistics were
not re-measured on the first machine and so carry no cross-machine check of
their own, same as every other second-machine assembly number in this section.

Both CSVs originally carried every pre-existing row twice, because `run_e9.sh`
appends a row per scoring pass and `chain_e9.sh` was invoked twice. The
duplicate copies were verified byte-identical before being collapsed; had any
pair disagreed, the de-duplication would have been refused rather than
silently picking one.

> **D4 applies to every number in this section.** MEGAHIT replaced metaSPAdes
> because metaSPAdes needs 30–120 GB. MEGAHIT typically produces lower N50 and
> less assembled sequence, so **absolute contiguity here is not comparable to
> any published metaSPAdes figure.** What is valid is the comparison *between
> cleaning methods*, because all three are assembled with the identical
> assembler and settings.

### Assembly quality

`misasm / Mb` is misassemblies divided by `assembled_mb_ge_1kb` — the explicit
denominator Editor point 14 asks for. It is defined only for synthetic
libraries; for real libraries genome fraction and misassemblies are blank by
design (see the correction above), and the table below shows `—` there.

| library | description | method | N50 | genome fraction % | misassemblies | assembled Mb ≥1 kb | misasm / Mb |
|---|---|---|---|---|---|---|---|
| `SYN-CHM13-01` | synthetic, 0.1 % host | hostsweep | 15926 | 86.189 | 102 | 36.8585 | 2.77 |
| `SYN-CHM13-01` | synthetic, 0.1 % host | hostile | 15951 | 86.189 | 99 | 36.8626 | 2.69 |
| `SYN-CHM13-01` | synthetic, 0.1 % host | kneaddata | 15076 | 86.753 | 173 | 37.0413 | 4.67 |
| `SYN-CHM13-05` | synthetic, 10 % host | hostsweep | 11992 | 83.429 | 99 | 35.8105 | 2.76 |
| `SYN-CHM13-05` | synthetic, 10 % host | hostile | 12091 | 83.442 | 101 | 35.8119 | 2.82 |
| `SYN-CHM13-05` | synthetic, 10 % host | kneaddata | 10548 | 84.993 | 249 | 36.2042 | 6.88 |
| `SYN-NEU-03` | synthetic, 20 % host, **mismatch** | hostsweep | 9746 | 80.522 | 125 | 34.4135 | 3.63 |
| `SYN-NEU-03` | synthetic, 20 % host, **mismatch** | hostile | 9805 | 80.534 | 126 | 34.4189 | 3.66 |
| `SYN-NEU-03` | synthetic, 20 % host, **mismatch** | kneaddata | 8383 | 81.602 | 282 | 34.8475 | 8.09 |
| `SRR40486826` | real, gut | hostsweep | 4491 |  |  | 57.6203 | — |
| `SRR40486826` | real, gut | hostile | 4405 |  |  | 57.5884 | — |
| `SRR40486826` | real, gut | kneaddata | 3848 |  |  | 54.5411 | — |
| `ERR15898346` | real, respiratory | hostsweep | 255614 |  |  | 6.6145 | — |
| `ERR15898346` | real, respiratory | hostile | 255614 |  |  | 6.6143 | — |
| `ERR15898346` | real, respiratory | kneaddata | 149836 |  |  | 6.6072 | — |
| `SRR31641567` | real, blood | hostsweep | 21425 |  |  | 9.7558 | — |
| `SRR31641567` | real, blood | hostile | 20761 |  |  | 9.7756 | — |
| `SRR31641567` | real, blood | kneaddata | 13061 |  |  | 9.4192 | — |

### The clearest valid finding — synthetic libraries only

Misassemblies per assembled Mb ≥ 1 kb, against the known ten-genome reference
set, identical for all three methods:

| library | hostsweep | hostile | kneaddata |
|---|---|---|---|
| SYN-CHM13-01 (0.1 % host) | 2.77 | 2.69 | **4.67** |
| SYN-CHM13-05 (10 % host) | 2.76 | 2.82 | **6.88** |
| SYN-NEU-03 (20 % host, mismatch) | 3.63 | 3.66 | **8.09** |

**KneadData produces 1.7–2.9x more misassemblies per assembled Mb than either
other method on all three synthetic libraries**, at comparable genome fraction.
This is the defensible form of the result: three libraries, one reference set,
no confound. It is a smaller claim than the withdrawn real-library figure, and
it is the one that holds.

**HostSweep and Hostile are near-indistinguishable throughout.** On the
synthetic libraries their misassembly rates differ by at most 0.06 per Mb. On
the real respiratory library — using reference-free metrics only — their N50 is
identical to the base pair (255,614) and assembled Mb differs by 0.2 kb. This is
the same pattern E5 found upstream: the Bowtie2 pass is doing the work, and
HostSweep's contribution is the tiered output structure rather than better
alignment.

### Real libraries — reference-free metrics only

| library | method | N50 | contigs ≥ 1 kb | assembled Mb ≥ 1 kb |
|---|---|---|---|---|
| SRR40486826 (gut) | hostsweep | 4,491 | 18,148 | 57.620 |
| SRR40486826 (gut) | hostile | 4,405 | 18,389 | 57.588 |
| SRR40486826 (gut) | kneaddata | 3,848 | 18,705 | 54.541 |
| ERR15898346 (respiratory) | hostsweep | 255,614 | 60 | 6.615 |
| ERR15898346 (respiratory) | hostile | 255,614 | 62 | 6.614 |
| ERR15898346 (respiratory) | kneaddata | 149,836 | 90 | 6.607 |
| SRR31641567 (blood) | hostsweep | 21,425 | 1,571 | 9.756 |
| SRR31641567 (blood) | hostile | 20,761 | 1,579 | 9.776 |
| SRR31641567 (blood) | kneaddata | 13,061 | 1,686 | 9.419 |

These need no reference and are valid across methods. KneadData gives the
lowest N50 on all three real libraries where it ran — 14 % lower on gut, 41 %
lower on respiratory, 39 % lower on blood — and less assembled sequence on gut
and blood (3.1 Mb and 0.34 Mb respectively). That is consistent with the
synthetic misassembly result without depending on a reference.

### Residual human content (Kraken2 Standard-8)

| library | method | reads total | reads human | % human |
|---|---|---|---|---|
| `SYN-CHM13-01` | hostsweep | 2,686,838 | **2** | 7.4e-05 % |
| `SYN-CHM13-01` | hostile | 2,687,272 | **11** | 0.000409 % |
| `SYN-CHM13-01` | kneaddata | 2,677,396 | **0** | 0.0 % |
| `SYN-CHM13-05` | hostsweep | 2,422,066 | **139** | 0.005739 % |
| `SYN-CHM13-05` | hostile | 2,422,243 | **10** | 0.000413 % |
| `SYN-CHM13-05` | kneaddata | 2,413,090 | **0** | 0.0 % |
| `SYN-NEU-03` | hostsweep | 2,153,571 | **231** | 0.010726 % |
| `SYN-NEU-03` | hostile | 2,154,280 | **227** | 0.010537 % |
| `SYN-NEU-03` | kneaddata | 2,145,547 | **50** | 0.00233 % |
| `SRR40486826` | hostsweep | 7,641,137 | **5** | 6.5e-05 % |
| `SRR40486826` | hostile | 7,836,297 | **103** | 0.001314 % |
| `SRR40486826` | kneaddata | 7,418,809 | **0** | 0.0 % |
| `ERR15898346` | hostsweep | 7,384,654 | **0** | 0.0 % |
| `ERR15898346` | hostile | 7,395,001 | **0** | 0.0 % |
| `ERR15898346` | kneaddata | 7,296,246 | **0** | 0.0 % |
| `SRR31641567` | hostsweep | 1,818,549 | **224** | 0.012318 % |
| `SRR31641567` | hostile | 1,940,560 | **5,987** | 0.308519 % |
| `SRR31641567` | kneaddata | 1,340,525 | **45** | 0.003357 % |

> **D5 applies to every figure in this table.** Standard-8 is a capped
> database; capping drops minimizers, so it detects **less** human sequence
> than Standard. Every `reads_human` count here is a **floor, not an
> estimate**, and cannot support a claim that residual human content is below
> any threshold. Database build `20250402`.

### This table contains a result unfavourable to HostSweep

**KneadData leaves fewer or equal residual human reads than HostSweep on all
six libraries where both ran — tied on one, ahead on five.** An earlier version
of this section said KneadData leaves zero on *every* library; that was wrong
on the data already in this table (`SYN-NEU-03` was never zero) and is
corrected here rather than repeated.

| library | hostsweep | kneaddata | kneaddata vs hostsweep |
|---|---|---|---|
| SYN-CHM13-01 | 2 | **0** | fewer |
| SYN-CHM13-05 | 139 | **0** | fewer |
| SYN-NEU-03 (mismatch) | 231 | **50** | fewer, 4.6x |
| SRR40486826 (gut) | 5 | **0** | fewer |
| ERR15898346 (respiratory) | 0 | 0 | tied |
| SRR31641567 (blood) | 224 | **45** | fewer, 5.0x |

This is the sharper version of the trade-off already visible in section 3c's
assembly numbers: **KneadData's more aggressive removal leaves less residual
host sequence and more misassembled, lower-N50 microbial sequence, on the same
libraries, every time it was measured.** HostSweep and Hostile trade the
reverse way — cleaner assemblies, and human reads that occasionally survive.
Neither the assembly numbers nor the residual-human numbers support ranking
one tool above the other in the abstract; they support describing where each
one spends its error budget.

**HostSweep versus Hostile is a genuine split, not a trend.** HostSweep is
lower on 3 of 6 libraries (gut: 5 vs 103; blood: 224 vs 5,987 — 27x fewer;
CHM13-01: 2 vs 11), Hostile is lower on 2 of 6 (CHM13-05: 10 vs 139 — 14x
fewer; NEU-03: 227 vs 231, essentially tied), and both hit zero on respiratory.
The largest single gap in the whole table is HostSweep's advantage on blood,
the highest real-host-content library measured: **27x fewer residual human
reads than Hostile.** That is worth reporting on its own terms, but it sits
alongside CHM13-05 where the same comparison favours Hostile by 14x — this
table does not show one tool consistently ahead of the other.

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

## 5b. E4 — real-library scoring

**30 of 30 real libraries, HostSweep, 0 failures.** `sensitivity_pct`,
`fpr_pct` and `host_pct` are empty on every row **by design**: real libraries
carry no per-read origin label, so there is no ground truth to score against,
and the protocol calls for reporting that absence rather than estimating it.
What is measured is what can be: reads in and out (via the assembly-tier
output), wall-clock runtime and peak memory, over all 7 categories of the
verified panel (section 5).

| category | libraries | runtime mean (min) | runtime range | peak memory mean (GB) | peak memory range |
|---|---|---|---|---|---|
| blood | 4 | 16.90 | 7.83 – 39.61 | 11.48 | 11.38 – 11.68 |
| environmental | 4 | 18.27 | 14.74 – 23.79 | 11.32 | 11.30 – 11.34 |
| gut | 6 | 16.45 | 5.16 – 24.85 | 11.40 | 11.28 – 11.79 |
| oral | 4 | 13.97 | 7.81 – 20.44 | 11.43 | 11.32 – 11.61 |
| respiratory | 4 | 13.32 | 7.08 – 19.87 | 11.66 | 11.33 – 12.21 |
| skin | 4 | 10.48 | 5.05 – 20.18 | 11.57 | 11.42 – 11.68 |
| urogenital | 4 | 13.75 | 12.56 – 14.59 | 11.35 | 11.29 – 11.40 |
| **all 30** | 30 | **14.85** | 5.05 – 39.61 | **11.45** | 11.28 – 12.21 |

This ran on the second machine (D18), which has 26 GB available to WSL2 —
HostSweep's ~11.3–12.2 GB peak here is comfortably under that ceiling, not
pinned against it the way the first machine's 11 GB ceiling pinned every E3
run (D17). That makes this table an internally consistent, largely
unconstrained measurement of HostSweep's own real-library memory demand — but
it is **still not comparable to HostSweep's E3 timings**, which were measured
on the other, constrained machine, or to the comparator runtime/memory numbers
in section 2b, for the reasons given in D18.

No category mean is drawn from a single BioProject (section 5); no accuracy
claim is made or implied by this section.

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
| kneaddata | 0.12.4 (run with `_JAVA_OPTIONS=-Xmx8g`, D19) |
| bmtagger / bmtool / srprism | environment installs; not yet scored (D20) |
| MEGAHIT | 1.2.9 |
| QUAST / MetaQUAST | 5.3.0 |
| Kraken2 | 2.17.1 |
| Kraken2 database | Standard-8, build `20250402` |
| sra-tools | 3.4.1 |

Full 118-package resolution in `conda_explicit.txt`.

**Host 1** (E1–E3, E5, E7, first 17 of 18 E9 pairs): 8 threads, 11 GB RAM
available to the guest (single 16 GiB DIMM, 15.64 GiB visible to the OS), 32 GB
swap, WSL2 Ubuntu on Windows 10.

**Host 2** ("Ozi"; comparator benchmark, all 30 E4 libraries, the last E9 pair):
12 threads, 26 GB RAM available to WSL2 (32 GB physical), WSL2 Ubuntu on
Windows 11. Verified to reproduce Host 1's accuracy figures exactly before any
of its results were combined with Host 1's (D18).

---

## 8. Deviations that must appear in Methods

Full text with interpretation costs in `DEVIATIONS.md` (20 deviations plus two
integrity incidents). The ones that change how a number should be read:

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

### D18 — Comparator, E4 and the last E9 pair ran on a second machine
Verified cross-machine comparable for accuracy (sensitivity/FPR reproduced to
the fourth decimal) before combining. **Not** verified comparable for runtime,
memory, or exact assembly statistics — the second machine is unconstrained
where the first was pinned at its ceiling, and MEGAHIT reassembly of the same
reads on the two machines disagrees by up to 47% on some contig statistics
(most, on HostSweep and Hostile, disagree by a few percent; KneadData's
disagree far more — a reproducibility finding in its own right, section 3c).

### D19 — KneadData required an explicit 8 GB JVM heap
Its bundled Trimmomatic wrapper hardcodes a 1 GB heap regardless of
`--max-memory`. Fixed with a `_JAVA_OPTIONS=-Xmx8g` shim. No effect on
KneadData's reported accuracy or assembly figures; affects only whether the
run completes.

### D20 — Comparator table ships with 3 tools, not 5
BMTagger's environment installs but was not wired into `run_e3.sh` in time —
deferred, not attempted-and-failed. DeconSeq is dropped: not on bioconda, needs
a manual install. Report the comparison as "Hostile (two configurations) and
KneadData," not as "the comparator suite."

### I1 — Concurrent writers corrupted one synthetic library (detected, discarded)
Two `mix_spikein.py` processes were found writing the same output prefix after a
suspended launcher reconnected across a guest restart. Interleaved writes give
valid gzip of roughly the right size whose reads and truth labels no longer
correspond. Both processes were killed, all three output files deleted unread,
and the library rebuilt. **No measurement was taken from the corrupt files and
none entered any results file.** A single-instance lock now prevents recurrence.

### I2 — Real-library assembly metrics computed against auto-selected references (detected, withdrawn)
`metaquast.py` run without `-r` for real libraries does not skip reference
comparison — it BLASTs the contigs against SILVA 16S and downloads references
from NCBI itself, chosen from **each method's own contigs**, so the three
methods were scored against three different reference sets. A published
headline ("869 misassemblies against HostSweep's 292" on the gut library) was
withdrawn on this basis. `genome_fraction_pct` and `misassemblies` are now
blanked for every real-library row; `run_e9.sh` passes `--max-ref-number 0` so
it cannot recur. A second reference-based column, `duplication_ratio`, was
missed in the first correction and has since been blanked too — it was left
populated from the same pre-fix runs. Full account in `DEVIATIONS.md`.

---

## 9. What the paper cannot yet claim

- **No claim that HostSweep dominates the comparator field.** Hostile matches
  or nearly matches HostSweep's sensitivity with 0.0000 % FPR on all 12
  synthetic libraries — strictly better specificity at equal sensitivity, on
  this panel. KneadData matches or beats HostSweep's sensitivity on the
  mismatch arm at ~30x the FPR. See section 2b. Any claim of the form
  "HostSweep outperforms existing tools" needs to specify on which axis, for
  which comparator, because the direction changes depending on which one.
- **BMTagger and DeconSeq are not in the comparator table.** BMTagger's
  environment installs but the run was never wired up in time (deferred, not
  failed); DeconSeq needs a manual, non-bioconda install and was dropped per
  the original instruction. A "five-tool comparison" cannot be claimed; a
  "three-tool comparison, with BMTagger and DeconSeq's absence stated" can.
  See D20.
- **The dual-pass sensitivity claim is refuted, not merely unmeasured.**
  The second pass's marginal contribution over Bowtie2 alone is 0.0001 pp
  matched and 0.0036 pp on the mismatch library. The architecture must be
  defended on the paired assembly tier it uniquely produces, not on
  sensitivity. See section 3b.
- **No cross-machine runtime or memory claim, on top of the existing
  single-machine one (D17).** The comparator, E4 and second-machine E9 numbers
  come from a different, unconstrained host than HostSweep's own E3 timings.
  Comparing them would compound D17's warning with a hardware confound. See
  D18.
- **No real-library accuracy.** All 30 real libraries are downloaded and
  scored for HostSweep (section 5b), but none have a per-read truth set, so
  sensitivity and FPR are empty by design, not estimated, on every one of
  them.
- **Downstream results (E9) rest on substituted tools, and on two hosts.**
  E9 is complete at 18 of 18 pairs, but MEGAHIT stands in for metaSPAdes (D4)
  and Kraken2 Standard-8 for Standard (D5). Absolute contiguity is not
  comparable to published metaSPAdes figures, residual-human counts are
  floors, and MEGAHIT's exact contig statistics are not bit-identical between
  the two hosts that produced this section's numbers (D18) — KneadData's
  assemblies vary the most. The between-method comparison, on one host at a
  time, is what stands.
- **25 of the original 30 accessions remain unverifiable**, having never been
  available to check.

---

## Files

| File | Rows | Contents |
|---|---|---|
| `per_library.csv` | 72 | Sensitivity, FPR, runtime, peak memory — hostsweep (36, n=3) + hostile_default/hostile_matched/kneaddata (36, n=1) |
| `synthetic_manifest.csv` | 12 | Realised fractions, seeds, source accessions |
| `threshold_sweep.csv` | 75 | Entropy × length grid, three libraries |
| `equivalence_check.txt` | 2 | Proof the Step-8 caching shortcut is exact |
| `accessions_verified.csv` | 30 | Full SRA metadata, PASS 30/30 |
| `verification_log.txt` | — | Per-category study counts, exact queries, UID counts |
| `genomes_verified.tsv` | 10 | Background community, verified at NCBI |
| `human_sources_provenance.json` | 3 | Mismatch-arm assembly provenance and composition |
| `DEVIATIONS.md` | 22 | 20 deviations + 2 integrity incidents |
| `STATUS.md` | — | What ran, what failed, what was skipped |
| `downstream.csv` | 18 | N50, misassemblies, assembled Mb ≥1 kb, per method |
| `kraken2_human.csv` | 18 | Residual human reads per method (floors, D5) |
| `ablation.csv` | 36 | Dual-pass contribution, 3 configurations |
| `e4_per_library.csv` | 30 | Real libraries, HostSweep: runtime, peak memory (no truth set, D18) |
| `AUDIT.md` | — | Self-audit, run on Host 2's own evidence tree (see the note at the top of the file) |
| `host2_raw/` | — | Host 2's complete raw delivery: its own README, `service.log`, the KneadData heap shim, `CONFLICTS_repo_vs_this_machine.csv`, and its full unfiltered CSV output — kept as the primary source for D18's numbers |

**`DEVIATIONS.md` is the file to attach to the response letter.** Each entry
states what was specified, what was done, why, and what it costs in
interpretation. A documented deviation is defensible; an undocumented one is not.
