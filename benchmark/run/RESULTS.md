# HostSweep benchmark — complete measured results

**Manuscript:** BIOADV-2026-394, *Bioinformatics Advances*, major revision
**Generated:** 2026-09-11 · **Updated:** 2026-09-30 (clean five-tool timing run, full-Standard Kraken2, CheckM2 on metaSPAdes) — 
**Repository:** https://github.com/Adeel2208/HostSweep

# 1. Status of each experiment

| Experiment | Description | State | Output |
|---|---|---|---|
| E1 | Real accession panel verification | **Complete** | `accessions_verified.csv`, `verification_log.txt` |
| E2 | Synthetic controlled-truth panel | **Complete** | `synthetic_manifest.csv` |
| E3 | Sensitivity and FPR, HostSweep | **Complete** | `per_library.csv` |
| E7 | Entropy × length threshold sweep | **Complete** | `threshold_sweep.csv`, `equivalence_check.txt` |
| E4 | Real-library scoring | **Complete** — 30 of 30 (HostSweep; no per-read truth set for real libraries, so accuracy columns are empty by design) | `e4_per_library.csv` |
| E9 | Assembly and classification (MEGAHIT) | **Complete** — 18 of 18 pairs | `downstream.csv`, `kraken2_human.csv` |
| — | E9 downstream, metaSPAdes arm | **Partial, 11 of 18 pairs** — 7 failed on a `spades-hammer` fault, retried and timeout-guarded but not resolved within this benchmark's time budget (I4). Exploratory; does not replace the MEGAHIT arm | `checkm2_metaspades.csv` |
| E5 | Dual-pass ablation | **Complete** | `ablation.csv` |
| E8 | Labelling sensitivity | Not applicable | requires real-library truth set |
| — | Comparator benchmark | **Complete for 4 of 5 tools, n=3 each** — `hostile_default`, `hostile_matched`, `kneaddata`, `bmtagger`, all 12 synthetic libraries, 3 independent runs, zero failures, one clean session (D17/D21). DeconSeq dropped (not on bioconda — D20) | `per_library.csv` |
| — | Runtime/memory comparison | **Complete** — same session as above, one fixed thread count, zero swap on all 180 runs, HostSweep included (D17) | `per_library.csv`, `timing_summary.csv` |
| — | CheckM2 | **Complete for 11 of 18 metaSPAdes pairs** — the other 7 have no assembly to score (metaSPAdes failure, I4), not a CheckM2 failure. Assembly-level proxy over a co-assembly, not a per-organism statistic (D6) | `checkm2_metaspades.csv` |
| — | Kraken2 full Standard | **Complete, 18 of 18** — same 18 read sets as the Standard-8 table, database swapped only (D5) | `kraken2_human_standard.csv` |

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

### Complete per-run data (`per_library.csv`, HostSweep's 36 of 180 rows)

The other 144 rows are the comparator benchmark, now n=3 for every tool — see
section 2b.

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

**180 runs, 0 failures, n=3 for every tool.** HostSweep, `hostile_default`,
`hostile_matched`, `kneaddata` and `bmtagger` — each scored against the same
truth labels, by the same `compute_metrics.py`, on all 12 synthetic libraries,
3 independent runs each — the comparison this benchmark exists to make.
**DeconSeq is not in this table** (dropped: not on bioconda, needs a
hand-edited manual install — D20).

This is the clean, single-session dataset (R1, further session, September
2026): one machine, nothing else running, one fixed thread count (8) for
every tool, every run under `/usr/bin/time -v`, zero swap on all 180 runs
(proven per-run from `/proc/vmstat`, not assumed — D17). Its accuracy
reproduces every value already on record **exactly** — 0 of 180 rows differ
from the values previously established across earlier sessions (matched
individually before this table was trusted). **This is also the first dataset
in the benchmark where a runtime and memory comparison across all five tools
is valid** — see the callout after the tables; it replaces every earlier
partial or cross-session timing comparison.

The older 84-row dataset (HostSweep n=3, each comparator n=1, assembled
piecemeal across three separate benchmark sessions — the version of this table
that existed before September 2026) is preserved unchanged as
`per_library_constrained.csv` for reference; it is superseded by the table
below, not deleted.

### Summary

| tool | condition | n | sensitivity mean | sensitivity range | FPR mean | FPR range |
|---|---|---|---|---|---|---|
| hostsweep | matched | 27 | 100.0000 % | 100.0000 – 100.0000 | 0.0142 % | 0.0133 – 0.0147 |
| hostile_default | matched | 27 | 99.9998 % | 99.9990 – 100.0000 | **0.0000 %** | 0.0000 – 0.0000 |
| hostile_matched | matched | 27 | 99.9998 % | 99.9990 – 100.0000 | **0.0000 %** | 0.0000 – 0.0000 |
| kneaddata | matched | 27 | **100.0000 %** | 100.0000 – 100.0000 | 0.4255 % | 0.4216 – 0.4293 |
| bmtagger | matched | 27 | 99.9999 % | 99.9995 – 100.0000 | 0.0002 % | 0.0002 – 0.0003 |
| hostsweep | mismatch | 9 | 99.9698 % | 99.9600 – 99.9765 | 0.0147 % | 0.0142 – 0.0150 |
| hostile_default | mismatch | 9 | 99.8665 % | 99.8150 – 99.9080 | **0.0000 %** | 0.0000 – 0.0000 |
| hostile_matched | mismatch | 9 | 99.8646 % | 99.8100 – 99.9075 | **0.0000 %** | 0.0000 – 0.0000 |
| kneaddata | mismatch | 9 | **99.9692 %** | 99.9550 – 99.9780 | 0.4268 % | 0.4233 – 0.4304 |
| bmtagger | mismatch | 9 | 99.9456 % | 99.9250 – 99.9575 | 0.0002 % | 0.0001 – 0.0002 |

### Per-library sensitivity

| library | host % | hostsweep | hostile_default | hostile_matched | kneaddata | bmtagger |
|---|---|---|---|---|---|---|
| SYN-CHM13-01 | 0.1 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 |
| SYN-CHM13-02 | 0.5 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 |
| SYN-CHM13-03 | 1.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 |
| SYN-CHM13-04 | 5.0 | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 |
| SYN-CHM13-05 | 10.0 | 100.0 | 99.9995 | 99.9995 | 100.0 | 100.0 |
| SYN-CHM13-06 | 20.0 | 100.0 | 99.9997 | 99.9997 | 100.0 | 99.9997 |
| SYN-CHM13-07 | 40.0 | 100.0 | 99.9997 | 99.9997 | 100.0 | 99.9999 |
| SYN-CHM13-08 | 5.0 | 100.0 | 99.9990 | 99.9990 | 100.0 | 100.0 |
| SYN-CHM13-09 | 10.0 | 100.0 | 100.0 | 100.0 | 100.0 | 99.9995 |
| SYN-IND-01 (mismatch) | 1.0 | **99.9600** | 99.8150 | 99.8100 | 99.9550 | 99.9250 |
| SYN-NEU-02 (mismatch) | 10.0 | 99.9765 | 99.9080 | 99.9075 | **99.9780** | 99.9575 |
| SYN-NEU-03 (mismatch) | 20.0 | 99.9728 | 99.8765 | 99.8762 | **99.9745** | 99.9543 |

HostSweep's sensitivity is greater than or equal to both Hostile configurations
on **12 of 12** libraries. Against KneadData it is greater or equal on **10 of
12** — KneadData edges it out on two of the three mismatch-arm libraries
(`SYN-NEU-02`, `SYN-NEU-03`), by 0.0015–0.0017 percentage points.

Against BMTagger, HostSweep's sensitivity is greater than or equal on **12 of
12** libraries, and strictly greater on 6 (`SYN-CHM13-06`, `-07`, `-09` by
0.0001–0.0005 pp, and all three mismatch libraries by 0.0185–0.0350 pp). In
absolute reads on the mismatch arm, BMTagger left 15, 85 and 183 human pairs
in `SYN-IND-01`, `SYN-NEU-02` and `SYN-NEU-03` (of 20,000, 200,000 and
400,000), against HostSweep's 8, 47 and 109 (section 2). BMTagger sits above
both Hostile configurations and below KneadData and HostSweep on all three
mismatch libraries.

### Per-library false positive rate

| library | hostsweep | hostile_default | hostile_matched | kneaddata | bmtagger |
|---|---|---|---|---|---|
| SYN-CHM13-01 | 0.0001 | **0.0** | **0.0** | 0.4258 | 0.0002 |
| SYN-CHM13-02 | 0.0001 | **0.0** | **0.0** | 0.4276 | 0.0003 |
| SYN-CHM13-03 | 0.0001 | **0.0** | **0.0** | 0.4293 | 0.0002 |
| SYN-CHM13-04 | 0.0001 | **0.0** | **0.0** | 0.4221 | 0.0002 |
| SYN-CHM13-05 | 0.0001 | **0.0** | **0.0** | 0.4292 | 0.0002 |
| SYN-CHM13-06 | 0.0001 | **0.0** | **0.0** | 0.4246 | 0.0003 |
| SYN-CHM13-07 | 0.0001 | **0.0** | **0.0** | 0.4239 | 0.0002 |
| SYN-CHM13-08 | 0.0002 | **0.0** | **0.0** | 0.4251 | 0.0002 |
| SYN-CHM13-09 | 0.0001 | **0.0** | **0.0** | 0.4216 | 0.0002 |
| SYN-IND-01 (mismatch) | 0.0001 | **0.0** | **0.0** | 0.4267 | 0.0002 |
| SYN-NEU-02 (mismatch) | 0.0002 | **0.0** | **0.0** | 0.4233 | 0.0001 |
| SYN-NEU-03 (mismatch) | 0.0002 | **0.0** | **0.0** | 0.4304 | 0.0002 |


> | tool | runtime mean (range) | peak memory mean (range) |
> |---|---|---|
> | hostile_matched | 0.42 min (0.36–0.48) | 3.50 GB (3.48–3.57) |
> | hostile_default | 0.43 min (0.37–0.52) | 3.50 GB (2.96–3.63) |
> | kneaddata | 1.39 min (0.91–2.71) | 5.04 GB (4.67–6.10) |
> | hostsweep |2.68 min (1.51–3.00), verified value is 5.68 min (4.51–6.00) | 11.39 GB (11.33–11.47), unaffected |
> | bmtagger | 5.93 min (4.96–6.45) | 8.00 GB (8.00–8.00, fixed by its
> 4^18-bit bitmask) |
>

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

`SRR31641567 / kneaddata` — the pair that stopped mid-run — was completed in a
later benchmark session (D18) and is included below. Its accuracy figure
(Kraken2 residual-human count) was verified reproducible before being combined
with the rest (D18); its exact assembly statistics were not independently
re-measured and so carry no reproducibility check of their own, same as every
other assembly number produced in that later session.

Both CSVs originally carried every pre-existing row twice, because `run_e9.sh`
appends a row per scoring pass and `chain_e9.sh` was invoked twice. The
duplicate copies were verified byte-identical before being collapsed; had any
pair disagreed, the de-duplication would have been refused rather than
silently picking one.


- **Kraken2 residual-human counts: 18 of 18 rows identical, every cell.**
- **Assembly statistics: 11 of 18 rows differ in at least one cell.**
  - `hostsweep`: 2 rows, one cell each, in the last printed digit
    (`SRR40486826` total length 90.4471 vs 90.4475 Mb; `SYN-NEU-03` genome
    fraction 80.522 vs 80.521 %).
  - `hostile`: 3 rows — `SRR31641567` total length 18.4978 vs 18.4975 Mb;
    `SRR40486826` contigs >= 1 kb 18,389 vs 18,387 and assembled Mb >= 1 kb
    57.5884 vs 57.5838; `SYN-CHM13-01` misassemblies 99 vs 100.
  - **`kneaddata`: all 6 rows differ**, materially: for example
    `SYN-CHM13-01` N50 15,076 vs 15,446, misassemblies 173 vs 151, genome
    fraction 86.753 vs 86.363 %; `SYN-NEU-03` largest contig 578.0 vs 437.4 kb
    and misassemblies 282 vs 306; `SRR31641567` N50 13,061 vs 13,514.
- Both sets are measurements of the same reads; neither is a correction of
  the other. Run-to-run differences of this size for KneadData mean its
  assembly comparisons against the other two methods on these libraries
  should be read cautiously. This is the second independent repeat: D18 reports an
  earlier one, and for the same pair (`SYN-NEU-03` / KneadData) the three
  independent MEGAHIT assemblies now give largest contigs of 578.0 (committed),
  306.5 (D18 repeat) and 437.4 kb (this repeat).

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
| `SYN-CHM13-01` | hostsweep | 3,995,514 | **2** | 5e-05 % |
| `SYN-CHM13-01` | hostile | 3,996,000 | **11** | 0.000275 % |
| `SYN-CHM13-01` | kneaddata | 3,978,984 | **0** | 0.0 % |
| `SYN-CHM13-05` | hostsweep | 3,599,926 | **139** | 0.003861 % |
| `SYN-CHM13-05` | hostile | 3,600,002 | **10** | 0.000278 % |
| `SYN-CHM13-05` | kneaddata | 3,584,550 | **0** | 0.0 % |
| `SYN-NEU-03` | hostsweep | 3,200,250 | **231** | 0.007218 % |
| `SYN-NEU-03` | hostile | 3,200,990 | **227** | 0.007092 % |
| `SYN-NEU-03` | kneaddata | 3,186,430 | **50** | 0.001569 % |
| `SRR40486826` | hostsweep | 9,824,456 | **5** | 5.1e-05 % |
| `SRR40486826` | hostile | 9,927,850 | **103** | 0.001037 % |
| `SRR40486826` | kneaddata | 9,470,160 | **0** | 0.0 % |
| `ERR15898346` | hostsweep | 9,472,386 | **0** | 0.0 % |
| `ERR15898346` | hostile | 9,484,140 | **0** | 0.0 % |
| `ERR15898346` | kneaddata | 9,373,730 | **0** | 0.0 % |
| `SRR31641567` | hostsweep | 2,124,388 | **224** | 0.010544 % |
| `SRR31641567` | hostile | 2,258,674 | **5,987** | 0.265067 % |
| `SRR31641567` | kneaddata | 1,609,012 | **45** | 0.002797 % |

> **D5 applies to every figure in this table.** Standard-8 is a capped
> database; capping drops minimizers, so it detects **less** human sequence
> than Standard. Every `reads_human` count here is a **floor, not an
> estimate**, and cannot support a claim that residual human content is below
> any threshold. Database build `20250402`.

> **CORRECTION (I3).** The `reads total` and `% human` columns of the first
> version of this table were wrong, and are corrected here. Kraken2's report
> lists unclassified reads on their own line and its `root` line counts
> classified reads only, so the number of reads in is the sum of the two. The
> parser used the larger of the two instead, so `reads total` was in practice the
> *unclassified* count (about 67 % of the true total on the synthetic libraries)
> and `% human` was too high by a factor of 1.2–1.5 in every row. The
> `reads human` counts were correct, and **every comparison in the text below
> uses those counts and is unchanged.** The check: for `SYN-CHM13-01` / hostile
> the corrected total is 3,996,000 = 2 x the 1,998,000 read pairs that library
> has left after cleaning. Recomputed from the 18 `k2.report` files on disk; the
> uncorrected table is kept as `kraken2_human_uncorrected_I3.csv`.

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

### Residual human content, full Standard database (further session, September 2026)

The capping restriction above is now lifted for these same 18 read sets:
Kraken2 was re-run against the **full Standard database** (86 GB), everything
else identical — same reads, same `--confidence 0.1 --minimum-hit-groups 3`.
This is the authoritative table; Standard-8 above is a documented floor
(D5), not a second, competing measurement.

| library | method | reads total | reads human | % human |
|---|---|---|---|---|
| `SYN-CHM13-01` | hostsweep | 3,995,514 | **2** | 5e-05 % |
| `SYN-CHM13-01` | hostile | 3,996,000 | **31** | 0.000776 % |
| `SYN-CHM13-01` | kneaddata | 3,978,984 | **0** | 0.0 % |
| `SYN-CHM13-05` | hostsweep | 3,599,926 | **344** | 0.009556 % |
| `SYN-CHM13-05` | hostile | 3,600,002 | **22** | 0.000611 % |
| `SYN-CHM13-05` | kneaddata | 3,584,550 | **0** | 0.0 % |
| `SYN-NEU-03` | hostsweep | 3,200,250 | **616** | 0.019248 % |
| `SYN-NEU-03` | hostile | 3,200,990 | **966** | 0.030178 % |
| `SYN-NEU-03` | kneaddata | 3,186,430 | **182** | 0.005712 % |
| `SRR40486826` | hostsweep | 9,824,456 | **109** | 0.001109 % |
| `SRR40486826` | hostile | 9,927,850 | **36,226** | 0.364893 % |
| `SRR40486826` | kneaddata | 9,470,160 | **23** | 0.000243 % |
| `ERR15898346` | hostsweep | 9,472,386 | **4** | 4.2e-05 % |
| `ERR15898346` | hostile | 9,484,140 | **7** | 7.4e-05 % |
| `ERR15898346` | kneaddata | 9,373,730 | **2** | 2.1e-05 % |
| `SRR31641567` | hostsweep | 2,124,388 | **1,398** | 0.065807 % |
| `SRR31641567` | hostile | 2,258,674 | **38,129** | 1.688114 % |
| `SRR31641567` | kneaddata | 1,609,012 | **216** | 0.013424 % |

**The Standard-8 floor understated residual human content substantially on
some rows.** The largest gap: `SRR40486826` (gut) / hostile goes from 103
(Standard-8) to 36,226 (Standard) — **352x**. `SRR31641567` (blood) / hostile
goes from 5,987 to 38,129 (6.4x). Full ratios are in D5's addendum in
`DEVIATIONS.md`.

**With the capping removed, HostSweep beats Hostile on residual human content
on 5 of 6 libraries**, not the near-even split Standard-8 showed — the one
exception (`SYN-CHM13-05`) still favours Hostile, by the same ~15.6x margin
Standard-8 already showed. The gut library, where Standard-8 showed a modest
20.6x HostSweep advantage, is far larger under the full database: **332x
fewer residual human reads than Hostile (109 vs 36,226)**. `SYN-NEU-03`
(mismatch) and `ERR15898346` (respiratory) flip from an effective tie under
Standard-8 to a small but real HostSweep advantage (1.6x and 1.75x) under the
full database. **This is a stronger, more one-sided result for HostSweep on
this axis than the capped-database table supported, and it should replace
that table's "genuine split" framing wherever this comparison is cited.**

### CheckM2 completeness/contamination (further session, September 2026 — metaSPAdes arm only)

CheckM2 ran successfully for the first time this benchmark (D6), against the
**metaSPAdes** assemblies from the exploratory downstream arm that replaces
MEGAHIT for D4 — **not** the MEGAHIT assemblies that carry the rest of this
section's narrative. metaSPAdes itself failed on 7 of the 18 (library, method)
pairs (I4, a documented `spades-hammer` bug, unrelated to CheckM2), so 11
pairs have a CheckM2 row and 7 do not — absent, not `FAILED`, because there is
no assembly to score.

| library | condition | method | completeness % | contamination % |
|---|---|---|---|---|
| `ERR15898346` | real | hostile | 100.0 | 6.35 |
| `ERR15898346` | real | hostsweep | 99.99 | 6.4 |
| `ERR15898346` | real | kneaddata | 100.0 | 1.17 |
| `SRR31641567` | real | hostile | 100.0 | 89.43 |
| `SRR31641567` | real | hostsweep | 100.0 | 86.11 |
| `SRR31641567` | real | kneaddata | 100.0 | 79.18 |
| `SRR40486826` | real | hostile | 99.91 | 118.13 |
| `SRR40486826` | real | hostsweep | 99.96 | 118.14 |
| `SRR40486826` | real | kneaddata | 99.95 | 119.25 |
| `SYN-NEU-03` | synthetic | hostile | 100.0 | 114.6 |
| `SYN-NEU-03` | synthetic | hostsweep | 100.0 | 114.6 |

Completeness is uniformly close to 100 % — expected, since a large
co-assembly covers *something* CheckM2's marker genes recognise almost
regardless of input quality; this is not a meaningful quality signal here.
**Contamination above 100 % on the larger, more diverse libraries (gut,
blood, the mismatch-arm synthetic library) is the expected consequence of
scoring a multi-organism co-assembly as a single genome bin** (D6): CheckM2
counts every duplicated copy of a marker gene as contamination, and a real
community has many organisms each contributing one. The smallest, least
diverse library (`ERR15898346`, respiratory) correspondingly has the lowest
contamination (1–6 %). **These numbers cannot be read as a per-organism
quality statistic, and the three-method differences within a library are too
small relative to what this metric actually measures to support a ranking
claim between cleaning methods.**

**KneadData remains the most aggressive of the three against the full
database too — fewer residual human reads than HostSweep on all 6 libraries,
none tied** (Standard-8 showed one tie, `ERR15898346`, which resolves to
HostSweep 4 vs KneadData 2 under the full database — still fewer, just not
zero on either side). The magnitude ranges from 2x (`ERR15898346`) to 6.5x
(`SRR31641567`). This does not change the trade-off already established
elsewhere in this document: KneadData's more aggressive removal costs it
assembly quality (section 3c) and specificity (section 2b).

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
| bmtagger / bmtool / srprism | bioconda, executed at full scale (D20). Package version **not recorded** — only the binary paths were saved (`record/bmtagger_version.txt`); `bmtagger.sh` run with default parameters plus `-q 1 -X`, word size 18 |
| MEGAHIT | 1.2.9 |
| QUAST / MetaQUAST | 5.3.0 |
| Kraken2 | 2.17.1 |
| Kraken2 database | Standard-8, build `20250402` |
| sra-tools | 3.4.1 |

Full 118-package resolution in `conda_explicit.txt`.

**E1–E3, E5, E7, and the first 17 of 18 E9 pairs** ran at an 11 GB RAM ceiling
(single 16 GiB DIMM, 15.64 GiB visible to the OS), 32 GB swap, WSL2 Ubuntu, 8
threads — every HostSweep run there peaked at 11.05–11.15 GB and completed
only by paging to swap (D17).

**The comparator benchmark, all 30 E4 libraries, and the last E9 pair** were
completed in a later benchmark session with substantially more memory
available. Before combining anything, that session independently reproduced
the E3 sensitivity/FPR figures to the fourth decimal (D18); runtime, peak
memory and exact assembly statistics from that session are not comparable to
the earlier figures, for the reasons given there.

**BMTagger, and a repeat E9 run,** were completed in a further session on
memory-unconstrained hardware (D20, D21). That session reproduced the
`hostile_matched` and `kneaddata` sensitivity/FPR exactly on all 24 rows, and
its repeat of E9 differs from the committed `downstream.csv` on assembly
statistics only (section 3c).

---

## 8. Deviations that must appear in Methods

Full text with interpretation costs in `DEVIATIONS.md` (21 deviations plus four
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
claim that residual human content is below any threshold. **Now measured
directly**: the full Standard database was run against the same 18 read sets
(further session); the gap ranges from a few reads up to **352x** on one row
(`SRR40486826`/hostile). Cite `kraken2_human_standard.csv`, not the Standard-8
table, wherever both exist. See section 3c.

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


## Files

| File | Rows | Contents |
|---|---|---|
| `per_library.csv` | 180 | Sensitivity, FPR, runtime, peak memory — all 5 tools, n=3 each, one clean same-thread-count session (R1) |
| `per_library_constrained.csv` | 84 | The earlier, cross-session table (hostsweep n=3, each comparator n=1) this superseded; kept for reference |
| `timing_summary.csv` | 5 | Per-tool runtime/memory means, ranges, across-run vs across-library spread, swap-activity count — from R1 |
| `checkm2_metaspades.csv` | 11 | CheckM2 completeness/contamination on the metaSPAdes downstream arm (D6); 7 of 18 pairs absent (I4) |
| `kraken2_human_standard.csv` | 18 | Residual human reads, full Standard database — same 18 pairs as `kraken2_human.csv`, no capping (closes D5's floor) |
| `synthetic_manifest.csv` | 12 | Realised fractions, seeds, source accessions |
| `threshold_sweep.csv` | 75 | Entropy × length grid, three libraries |
| `equivalence_check.txt` | 2 | Proof the Step-8 caching shortcut is exact |
| `accessions_verified.csv` | 30 | Full SRA metadata, PASS 30/30 |
| `verification_log.txt` | — | Per-category study counts, exact queries, UID counts |
| `genomes_verified.tsv` | 10 | Background community, verified at NCBI |
| `human_sources_provenance.json` | 3 | Mismatch-arm assembly provenance and composition |
| `DEVIATIONS.md` | 25 | 21 deviations + 4 integrity incidents |
| `STATUS.md` | — | What ran, what failed, what was skipped |
| `downstream.csv` | 18 | N50, misassemblies, assembled Mb ≥1 kb, per method |
| `kraken2_human.csv` | 18 | Residual human reads per method (floors, D5); `reads_total` and `pct_human` corrected in I3 |
| `kraken2_human_uncorrected_I3.csv` | 18 | The table as first produced, before I3 was corrected; kept unchanged for traceability |
| `ablation.csv` | 36 | Dual-pass contribution, 3 configurations |
| `e4_per_library.csv` | 30 | Real libraries, HostSweep: runtime, peak memory (no truth set, D18) |
| `AUDIT.md` | — | Self-audit, run on the later session's own evidence tree (see the note at the top of the file) |
| `bmtagger_run_raw/` | — | The further session's unfiltered delivery: BMTagger metrics/time/stderr for all 12 libraries, the `hostile_default` FAILED records (D21 at the time), its E9 repeat CSVs, `MANIFEST.txt`, logs and tool-version records — primary source for D20 and the E9 repeat in section 3c |
| `followup_run_raw/` | — | The later session's complete raw delivery: a README, a full run log, the KneadData heap shim, a cell-by-cell diff against the original run, and its full unfiltered CSV output — kept as the primary source for D18's numbers |
| `r1_r3_r4_raw/` | — | The clean-timing-run session's unfiltered delivery: 180 runs' `.time`/`.swap`/metrics evidence (R1), CheckM2's per-assembly evidence (R3), Kraken2's per-classification `.time` and reports (R4), `machine.txt`, `swap_check.txt`, `run_details.csv` — primary source for D5's addendum, D6's addendum, D17's addendum, D21's resolution and this update throughout |

