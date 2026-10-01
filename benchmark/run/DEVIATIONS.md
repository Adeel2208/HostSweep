# Deviations from reviewer- and editor-specified methods

**Manuscript:** BIOADV-2026-394 (Bioinformatics Advances, major revision)
**Maintained:** from 2026-09-06, updated whenever a departure occurs. Last revised 2026-10-01.
**Contents:** 22 deviations (D1–D22) and 4 integrity incidents (I1–I4).
**Purpose:** this file accompanies the response letter. Each entry states what
was specified, what was done, why, and what it costs in interpretation.

Entries are grouped by whether they affect a reported number.

---

## Category 1 — Deviations that affect a reported number

### D1. Background community coverage: 50x specified, 200x used

**Specified.** `benchmark/synthetic/README.md` and the protocol: microbial
background simulated at 50x total community coverage.

**Done.** 200x total community coverage.

**Why.** The specification is internally inconsistent. Summing
`abundance x genome_length` over the ten-genome community gives 4.379 Mb; at
50x and 300 bp per pair that is a pool of roughly 730,000 read pairs. But a
library at 0.1% human needs about 1,998,000 background pairs out of 2,000,000.
The pool would have been a quarter of the largest draw, and `mix_spikein.py`
would have silently returned a realised fraction far from the requested one for
every low-human library. Measured pool at 200x: **2,921,080 pairs**, against a
largest draw of 2,000,000.

**Interpretation cost.** None to accuracy metrics. The background community
composition, relative abundances and per-genome identity are unchanged; only
the depth of the pool that libraries are drawn from differs. It removes an
artefact rather than introducing one. Realised fractions in
`synthetic_manifest.csv` are the authoritative values regardless.

---

### D2. Human simulation coverage: `-f 5` specified, `-f 0.2` used

**Specified.** `art_illumina ... -f 5` for the human read source.

**Done.** `-f 0.2`.

**Why.** The largest human draw any library makes is 40% of 2,000,000 =
800,000 pairs. Over the 3.1 Gb reference, `-f 5` yields roughly 51 M pairs
(~20 GB per source, four sources = ~80 GB) of which more than 98% is discarded
by subsampling. `-f 0.2` yields ~2.07 M pairs, still 2.5x the largest draw.
Forced by 574 GB total free disk.

**Interpretation cost.** Minimal. `mix_spikein.py` subsamples from whatever
pool it is given, and truth labelling is by read-name prefix, so it is
unaffected. The only consequence is that the human reads in a library are drawn
from a smaller candidate pool, which slightly reduces the diversity of genomic
positions sampled. At 2.07 M pairs over 3.1 Gb the positions remain effectively
non-overlapping, so this does not bias sensitivity.

---

### D3. Threshold sweep executes Step 8 only, not 25 full pipeline runs

**Specified.** E7: `hostsweep -1 ... --bbeg $H --stringent-minlen $L` for each
of 25 (entropy, length) combinations.

**Done.** The full pipeline runs **once** per library to produce the Step 7
profiling output; Step 8 (`bbduk.sh entropy=H minlen=L`) then runs 25 times
against that cached tier.

**Why.** `--bbeg` and `--stringent-minlen` are consumed only by Step 8, whose
input is the Step 7 profiling output. Steps 0-7 read neither parameter, so
their output is byte-identical across all 25 combinations. Running them 25
times would cost ~44 h per three libraries to recompute identical
intermediates; the cached form costs ~2 h.

**Interpretation cost.** None, provided the equivalence holds. It is asserted
rather than assumed: `VERIFY_FULL=1` performs one complete `hostsweep` run at
(H=0.85, L=90) per library and compares read counts against the cached path. A
mismatch is a hard failure and aborts the sweep. The verification result is
recorded in `results/equivalence_check.txt`.

---

### D4. Downstream assembler: metaSPAdes specified, MEGAHIT used

**Specified.** `metaspades.py -1 ... -t 8 -m 120`.

**Done.** MEGAHIT.

**Why.** `-m 120` requests a 120 GB memory cap. The host has a single 16 GB
DIMM (15.64 GiB visible; 12 GB available to WSL2). metaSPAdes on metagenomic
data of this size needs 30-120 GB. It cannot run, and swap does not rescue it:
a 60-120 GB working set paged through disk-backed swap thrashes rather than
completes.

**Interpretation cost.** Substantial and must be stated in the manuscript.
MEGAHIT and metaSPAdes are different assemblers with different contiguity
profiles — MEGAHIT typically produces **lower N50 and less total assembled
sequence** than metaSPAdes on the same metagenomic input. Absolute assembly
statistics are therefore **not comparable to any previously reported
metaSPAdes numbers**, and must not be presented as if they were. The
*comparison between cleaning methods* remains valid, because all three
cleaning methods are assembled with the identical assembler and settings —
which is what the E9 claim actually rests on.

---

### D5. Taxonomic database: Kraken2 Standard specified, Standard-8 used

**Specified.** `kraken2 --db k2_standard_<date>`.

**Done.** Kraken2 with the **Standard-8** capped database (8 GB).

**Why.** The Standard database is ~90 GB on disk and wants comparable RAM to
load. Neither fits in 12 GB RAM / 574 GB disk alongside the read data.

**Interpretation cost.** Directional and important. **A capped database
detects less human sequence than Standard**, because the capping process
removes minimizers, so some human-derived k-mers present in Standard are
absent from Standard-8. The residual-human figure in `kraken2_human.csv` is
therefore a **floor, not an estimate**: true residual human content is greater
than or equal to what is reported. It must be described that way in the
manuscript. It cannot be used to claim residual human content is *below* any
threshold.

**Addendum: the floor is now measured, not just asserted (further session,
September 2026).** The full Standard database (86 GB on disk) was obtained and
run against the same 18 (library, method) read sets already scored with
Standard-8, everything else identical (same reads, same
`--confidence 0.1 --minimum-hit-groups 3`). `kraken2_human_standard.csv` holds
the result; `kraken2_human.csv` (Standard-8) is unchanged. Every one of the 18
rows shows Standard finding **at least as many** human reads as Standard-8, as
predicted, and the gap is not uniform:

| library | method | Standard-8 human | Standard human | ratio |
|---|---|---|---|---|
| `SRR40486826` | hostile | 103 | 36,226 | **352x** |
| `SRR31641567` | hostile | 5,987 | 38,129 | 6.4x |
| `SYN-NEU-03` | hostile | 227 | 966 | 4.3x |
| `SYN-CHM13-05` | hostsweep | 139 | 344 | 2.5x |
| `SRR31641567` | hostsweep | 224 | 1,398 | 6.2x |
| `ERR15898346` | hostile | 0 | 7 | n/a (0 → 7) |

Most rows move by a small absolute amount; a few move by orders of magnitude,
overwhelmingly on `hostile` rows — the gut library under Hostile goes from
"0.001 % human" to "0.36 % human" against the full database. **This confirms
D5's floor language was not a formality: the true residual-human figure can be
two to three orders of magnitude above what Standard-8 reported for specific
(library, method) pairs**, and the manuscript's residual-human claims should
cite the full-Standard table, not Standard-8, wherever both exist (they now
cover the same 18 pairs).

---

### D6. CheckM2 dropped originally; later run on the metaSPAdes assemblies (11 of 18 pairs)

**Specified.** "Add CheckM2 completeness/contamination if you can run it; if
not, say so explicitly."

**Done, originally.** Not run — the host at the time had 12 GB RAM.

**Why.** CheckM2 needs roughly 15 GB RAM plus its reference database (a
diamond `.dmnd` file, several GB), above that ceiling.

**Addendum: `run_checkm2.sh` now exists** and `chain_all.sh` calls it
automatically as its own stage. It installs the `checkm2` conda environment
and downloads the database on first use, then runs `checkm2 predict` against
every MEGAHIT assembly E9 has produced, one completeness/contamination pair
per (library, method) — a coarse, assembly-level proxy, since CheckM2 is
designed to score single-genome bins, not a whole metagenomic co-assembly; say
so wherever this number is used.

**The install, database download and CLI were smoke-tested end to end**
(*E. coli*, `GCF_000005845.2`, one bin) on the one machine reachable at the
time: `checkm2 database --download` (1.74 GB, CheckM2 v1.1.0) and
`checkm2 predict --database_path <dmnd file> -x fa` both completed with exit
0, and `quality_report.tsv` came back with exactly the columns
`run_checkm2.sh` reads by name (`Completeness`, `Contamination`) —
`Completeness=100.0, Contamination=0.14` for a single complete bacterial
genome, which is the expected answer and confirms the parsing is reading the
right fields, not silently misreading a different layout. **This confirms the
CLI and output format `run_checkm2.sh` depends on; it does not confirm
CheckM2's behaviour on an actual metagenomic co-assembly**, which is a
different and harder input than one clean bacterial genome, and has not been
tried. If the install or a run fails at that scale, or RAM is still
insufficient wherever this next runs, the script records `FAILED` rows and
does not block anything else in the chain.

**Outcome of the full-scale attempt (further session, September 2026).** The run
failed at environment installation, before any E9 assembly was reached:
`conda create` of the `checkm2` environment ended with
`CondaHTTPError: HTTP 000 CONNECTION FAILED` for
`https://conda.anaconda.org/conda-forge/linux-64/repodata.json` after about
3.5 minutes, and the script recorded `checkm2 install FAILED -- dropping, same
as the original decision (D6)`. Nothing was estimated in its place. The failure
was a transient network error on that machine's link, not a CheckM2 or memory
limit. `run_checkm2.sh` and `install_comparators.sh` were then changed to use
longer conda timeouts (60 s connect, 120 s read, 5 retries) and to retry
environment creation (5 attempts) and the ~1.7 GB database download (3
attempts) — commit `8cf930c` — and a second attempt was started. **At the time of this entry no CheckM2 statistic existed; the second attempt below
supersedes it.**

**Outcome of the second attempt (further session, September 2026): it ran.**
The conda-timeout retries fixed the earlier install failure, and
`checkm2 predict` completed on **11 of 18** (library, method) pairs from the
**metaSPAdes** downstream arm (R2, not the MEGAHIT arm that carries the main
E9 narrative — see D4). The other 7 pairs have no CheckM2 row because they
have no assembly to score: metaSPAdes itself failed on them, a separate,
documented issue (I4), not a CheckM2 failure. Results are in
`checkm2_metaspades.csv`:

| library | condition | completeness range | contamination range |
|---|---|---|---|
| `ERR15898346` (respiratory) | real | 99.99–100.0 % | 1.17–6.40 % |
| `SRR31641567` (blood) | real | 100.0 % | 79.18–89.43 % |
| `SRR40486826` (gut) | real | 99.91–99.96 % | 118.13–119.25 % |
| `SYN-NEU-03` (mismatch) | synthetic | 100.0 % | 114.6 % (both methods present) |

Completeness is uniformly near 100 % across every row — expected, since a
large co-assembly almost always covers *something* CheckM2's marker genes
recognise. **Contamination exceeding 100 % on the larger, more diverse
libraries (gut, blood, the synthetic mismatch library) is the direct,
expected consequence of scoring a multi-organism co-assembly as if it were one
genome bin**, exactly the caveat stated above: CheckM2 counts duplicated
marker genes as contamination, and a real community contains many organisms
each contributing their own copy of common markers. The smallest, least
diverse library (`ERR15898346`, respiratory) has correspondingly the lowest
contamination (1–6 %). **These numbers are not comparable to a per-organism
quality statistic and must not be presented as one.**

**Interpretation cost.** Completeness/contamination statistics now exist for
11 of 18 metaSPAdes (library, method) pairs; the other 7 have none, by
omission from a documented assembler failure (I4), not by estimation. Every
number here is an assembly-level proxy over a possibly-multi-organism
co-assembly, not a per-organism bin statistic, and the manuscript must state
that wherever it is used. These numbers were **not** produced against the
MEGAHIT assemblies that carry the rest of the E9 narrative (`downstream.csv`);
CheckM2 has not been run against those.

---

### D7. Sample-category names changed to match SRA taxonomy

**Specified.** Seven categories: environmental, gut, oral, skin, respiratory,
urogenital, blood.

**Done.** Category labels renamed to the NCBI taxon names that actually return
data — for example respiratory becomes *human lung metagenome* and/or *human
nasopharyngeal metagenome*; urogenital becomes *human vaginal metagenome*.

**Why.** Measured, with the queries logged in `logs/e1_search*.out`: the exact
taxon strings `"human urogenital metagenome"[Organism]` and
`"human respiratory tract metagenome"[Organism]`, combined with
`"illumina"[Platform] AND "paired"[Layout] AND "wgs"[Strategy]`, return
**zero** runs in SRA. The categories as named are not populatable.

**Interpretation cost.** The panel covers the same anatomical sites, but the
labels in the manuscript must change to the taxon names actually used, so that
a reader can reproduce the query. Any claim about "urogenital" breadth is
really a claim about vaginal metagenomes specifically.

---

### D17. Runtime and peak-memory figures from this host are not comparable

**Specified.** Report runtime and peak memory per tool, so the comparator table
carries a performance column alongside accuracy.

**Done.** The measurements are taken and reported, but they must **not** be used
to compare tools, and the manuscript should say so.

**Why.** Every HostSweep run on this host peaks at **11.05-11.12 GB against an
11 GB ceiling** and completes only by paging into swap. The resulting timings
are dominated by swap behaviour, not by the method. Measured, same library,
same inputs, same parameters:

| Library | run 1 | run 2 | run 3 |
|---|---|---|---|
| SYN-CHM13-04 (5%) | 45.34 min | 39.84 min | 25.53 min |
| SYN-CHM13-05 (10%) | 30.96 min | **69.40 min** | 35.84 min |

A 2.2x spread between replicates of an identical, deterministic computation is
the machine, not the pipeline. A comparator ranking built on these numbers
would rank whichever tool happened to run when the page cache was warm.

**Interpretation cost.** Accuracy is unaffected: sensitivity and false positive
rate are byte-identical across replicates, because the pipeline is
deterministic and the arithmetic does not care how long it took. Those figures
stand. But:

- **No runtime claim should be made from this data**, including "faster than",
  "comparable to", or a runtime column in the comparator table.
- **Peak memory is a floor set by the ceiling**, not a measurement of demand: a
  tool that would use 20 GB on a larger machine records ~11 GB here or fails.
  The numbers say what fitted, not what was wanted.
- Runtime and memory must be re-measured on unconstrained hardware before any
  performance claim enters the manuscript. Everything needed is in
  `benchmark/scripts/`; the runs are idempotent and would reproduce there.

This is the single largest limitation of running the benchmark on this host,
and it is a hardware limitation rather than a methodological one.

**Addendum: resolved (further session, September 2026, R1).** A dedicated,
clean timing run — nothing else running on the machine, one fixed thread count
(8) for every tool, every run under `/usr/bin/time -v` — scored all five
tools (HostSweep, Hostile default, Hostile matched, KneadData, BMTagger) on
all 12 synthetic libraries, **3 independent runs each, 180 runs total, zero
failures.** Swap was proven not to be a factor rather than assumed: every run
carries its own system-wide pswpin/pswpout delta (`run_details.csv`), and
**`swap_check.txt` reports zero runs with any swap activity, out of 180.**
This is the first dataset in the benchmark where a runtime and memory
comparison across tools is actually valid, and it supersedes the "no runtime
claim" restriction above for these five tools specifically. Mean values,
n=36 runs per tool:

| tool | runtime mean (range) | peak memory mean (range) |
|---|---|---|
| hostile_matched | 0.42 min (0.36–0.48) | 3.50 GB (3.48–3.57) |
| hostile_default | 0.43 min (0.37–0.52) | 3.50 GB (2.96–3.63) |
| kneaddata | 1.39 min (0.91–2.71) | 5.04 GB (4.67–6.10) |
| hostsweep | 5.68 min (4.51–6.00) | 11.39 GB (11.33–11.47) |
| bmtagger | 5.93 min (4.96–6.45) | 8.00 GB (8.00–8.00) |

The HostSweep runtime was recomputed from `r1_r3_r4_raw/csv/r1/run_details.csv` (36 runs,
`wall_clock_s`); it equals `timing_summary.csv` (mean 5.683 min, range 4.507–6.002).
**Correction (2026-10-01):** an earlier revision of this table listed HostSweep as
"2.68 min (1.51–3.00)". That value is not supported by either file and is withdrawn.
Machine: AMD EPYC 9554, 125 GiB RAM, 32 GiB swap (unused), 8 threads per run
(`machine.txt`). BMTagger is single-threaded (99 % CPU) although the harness passed 8.

### D18. Comparator benchmark, E4 and the last E9 pair completed in a later benchmark run

**Specified.** Finish the comparator sensitivity/FPR benchmark, score the
remaining real libraries, and complete E9.

**Done.** A later benchmark run completed: the comparator benchmark
(`hostile_default`, `hostile_matched`, `kneaddata` × 12 synthetic libraries,
n=1), all 30 real libraries for HostSweep (`e4_per_library.csv`), and the
missing E9 pair (`SRR31641567` / `kneaddata`).

**Before any of it was trusted:** one synthetic library (`SYN-CHM13-01`) was
independently rebuilt and its sensitivity and FPR diffed against the
`per_library.csv` already on record. **Passed — identical to the fourth
decimal** (sensitivity 100.0000 %, FPR 0.0142 %). Accuracy figures from both
runs are therefore combinable, and are combined in `per_library.csv`,
`downstream.csv` and `kraken2_human.csv`.

Two things are **not** combinable, and must not be presented as if they were:

**a) Runtime and peak memory, across the two runs, are not one dataset.**
HostSweep's own E3 timings (15–70 min, ~11.05–11.15 GB peak) come from the
original run, at an 11 GB memory ceiling (D17). The comparator and E4 timings
in this correction (Hostile ~0.6–1.5 min, KneadData ~2–6 min, HostSweep on
real libraries ~5–40 min, all under ~5.2 GB peak for comparators and
~11.3–12.2 GB for HostSweep) come from the later run, which had substantially
more memory available — the observed HostSweep peak of ~11.3 GB there sits
comfortably inside that headroom, not pinned against a ceiling the way the
original run was. **A runtime or memory comparison between HostSweep and a
comparator built from these two datasets would be comparing a constrained run
against an unconstrained one, on top of D17's existing warning that timings
aren't comparable between tools even within one run.** No runtime or memory
column may appear in any comparator table built from **this run's** timings.
(A separate, later run — R1, five tools, one fixed thread count, zero swap,
see D17's addendum — supplies a runtime/memory comparison that *is* valid;
use that one, not the numbers described in this entry, for any performance
claim.) A second narrow exception here: numbers within `e4_per_library.csv` are internally
comparable to each other, and to the comparator table, because all of it came
from the same later run — HostSweep's *own* E3 numbers are the ones that don't
cross over.)

**b) MEGAHIT assemblies are not bit-identical across independent runs.** The
same cleaned reads, same MEGAHIT version, assembled independently, disagree by
a few percent on contig-level statistics — expected, since MEGAHIT's de Bruijn
graph construction is thread-scheduling-dependent and is not guaranteed to
produce identical output run to run. Measured directly by re-running the six
E9 libraries already scored in the original run and diffing against an
independent re-run (kept alongside this file as evidence):

| method | cells differing (of 46 compared) | typical size |
|---|---|---|
| hostsweep | 5 | 4th-decimal jitter (18.4978 vs 18.4975 Mb; 18389 vs 18388 contigs) |
| hostile | 7 | same order |
| kneaddata | 34 | **up to 47 %** (`largest_contig_kb`: SYN-NEU-03 578.0 vs 306.5) |

**This asymmetry is itself a result, not just a bookkeeping problem: KneadData's
assemblies reproduce far less well across independent runs than HostSweep's or
Hostile's.** It is consistent with, and adds weight to, the misassembly-rate
finding in section 3c (KneadData produces 1.7–2.5x more misassemblies per Mb) —
an assembly downstream of noisier cleaning is less stable, not just worse on
average. `downstream.csv` keeps the **original run's** values as canonical for
all rows measured in both (first-recorded, and already the basis of the E9
narrative); the independent re-run's measurements are the evidence for this
reproducibility finding, not a replacement dataset.

**Further repeat of E9 (further session, September 2026).** A third independent E9 run, on
all 18 pairs, was compared cell by cell against the committed `downstream.csv`
and `kraken2_human.csv` (neither was changed; the repeat is in
`bmtagger_run_raw/csv/`). Kraken2 residual-human counts: **18 of 18 rows
identical**. Assembly statistics: 11 of 18 rows differ — hostsweep 2 rows (one
cell each, last digit: `SRR40486826` total length 90.4471 vs 90.4475 Mb;
`SYN-NEU-03` genome fraction 80.522 vs 80.521 %), hostile 3 rows
(`SRR31641567` total length 18.4978 vs 18.4975 Mb; `SRR40486826` contigs ≥ 1 kb
18,389 vs 18,387 and assembled Mb ≥ 1 kb 57.5884 vs 57.5838; `SYN-CHM13-01`
misassemblies 99 vs 100), **kneaddata all 6 rows**, materially (`SYN-CHM13-01`
N50 15,076 vs 15,446, misassemblies 173 vs 151, genome fraction 86.753 vs
86.363 %; `SYN-NEU-03` largest contig 578.0 vs 437.4 kb, misassemblies 282 vs
306; `SRR31641567` N50 13,061 vs 13,514). This confirms the asymmetry above
with an independent third measurement: for `SYN-NEU-03` / KneadData the
largest contig is now 578.0 (committed), 306.5 (first repeat) and 437.4 kb.
That session's E4 scoring was **not** repeated: it downloaded only the three
real libraries E9 needs (`SRR40486826`, `ERR15898346`, `SRR31641567`), not the
30-library panel, so `e4_per_library.csv` is unchanged.

**Interpretation cost.** Accuracy (sensitivity, FPR, reads-human counts) is
established as reproducible across independent runs by the check above, and
combining it is the point of running the check at all. Runtime, memory and
exact assembly statistics are not, for the reasons given.

---

### D22. Comparators were not given a common preprocessing stage, and HostSweep was scored on single-end output

**Specified.** Reviewer and editor requests: equivalent preprocessing, thread counts, input data and
resource measurement across tools; avoid comparing paired-end with single-end outputs without
control.

**Done.** Identical input FASTQs, one fixed thread count (8; BMTagger is single-threaded) and one
resource-measurement procedure for every tool. **Preprocessing was not equalised.** Each tool was run
as it is normally invoked (`run_e3.sh`): HostSweep applies fastp (quality, adapters, complexity,
minimum length 50 bp); KneadData applies Trimmomatic with default settings; Hostile and BMTagger
apply no trimming (Hostile's output retains every read that does not align). Accuracy was scored per
read pair against the truth labels by the same `compute_metrics.py`; HostSweep was scored on its
single-end profiling-tier output and the comparators on their paired output.

**Why.** A common preprocessing stage would have changed the tools from their standard use and was
not part of the run; the consequence was not noticed until the results were reviewed.

**Interpretation cost.** The false positive rate counts every microbial read absent from a tool's
output, so it includes losses from that tool's own preprocessing and is not a pure host-alignment
false positive. In particular KneadData's 0.43 % and HostSweep's 0.014 % are not decomposed into
preprocessing and alignment components, and Hostile's 0.00 % reflects, in part, the absence of any
trimming. Downstream assembly differences between methods (section 3c) cannot be attributed to host
removal alone for the same reason. The comparison is between tools as invoked, not between host-removal
algorithms. Resolving this needs a rerun with a shared preprocessing stage ahead of every tool.

---

## Category 2 — Deviations in inputs and provenance

### D8. Three background genome accessions corrected

**Specified.** Ten accessions with organism names.

**Done.** Three accessions replaced, on the authors' ruling that the organism
names are authoritative:

| Organism | Specified accession (actually is) | Used |
|---|---|---|
| *Lactobacillus acidophilus* NCFM | `GCF_000009605.1` (*Buchnera aphidicola* APS, 0.66 Mb) | `GCF_000011985.1` |
| *Bacteroides thetaiotaomicron* VPI-5482 | `GCF_000007565.2` (*Pseudomonas putida* KT2440) | `GCF_000011065.1` |
| *Bifidobacterium longum* NCC2705 | `GCF_000012825.1` (*Phocaeicola vulgatus* ATCC 8482) | `GCF_000007525.1` |

**Why.** All ten accessions resolve, but three named a different organism than
specified. Verified live against the NCBI Datasets API
(`logs/00_verify_genomes.log`).

**Interpretation cost.** The background community is the one the manuscript
*describes*. Had the accessions been used as given, *Buchnera aphidicola* — a
0.66 Mb insect endosymbiont — would have sat at abundance 0.08, contributing
roughly a third of the intended read count for that member, and two gut
commensals would have been absent entirely.

---

### D9. Mismatch-arm sample HG00514 replaced by HG00438

**Specified (originally).** Haplotype-resolved assemblies for HG00514,
HG00733, NA19240, described as HPRC.

**Done.** HG00514 dropped; **HG00438** used, library renamed **SYN-IND-01**.
All three sources are HPRC Year 1 `f1_assembly_v2`, primary/maternal
haplotype, hifiasm v0.14, UCSC Genomics Institute, PacBio Sequel, May 2021:

| Library | Sample | Accession | Population |
|---|---|---|---|
| SYN-IND-01 | HG00438 | `GCA_018471515.1` | Han Chinese South (CHS) |
| SYN-NEU-02 | HG00733 | `GCA_018506975.1` | Puerto Rican (PUR) |
| SYN-NEU-03 | NA19240 | `GCA_018503275.1` | Yoruban (YRI) |

**Why.** HG00514 has no HPRC assembly — it is an HGSVC sample. Note this also
changed HG00733 and NA19240, which were previously pointed at their `hprc_f2`
releases (hifiasm **v0.19.9**, chromosome-level).

**Interpretation cost.** Positive. Using one assembly project and one assembler
version means "reference mismatch" is not confounded with "different assembler"
or "different scaffolding". The variable that differs across the arm is
population ancestry, which is the intended variable.

---

### D10. Original 30-library panel could not be verified as such

**Specified.** Verify the 30 original accessions; keep those that pass.

**Done.** Only **2** of the 30 were ever available in the repository
(`benchmark/accessions.csv`); the other 28 are in Supplementary Table S1, which
was not provided to this work. Both available accessions were verified and
**both FAIL**:

| Run | Reported as | Actually is |
|---|---|---|
| `SRR6062009` | runtime reference, "1.86 M pairs" | *Klebsiella pneumoniae*, `LibrarySource=GENOMIC`, 1,863,630 spots — a single-isolate bacterial genome |
| `SRR14235678` | ablation library, 12.35% human | *soil metagenome*, `AMPLICON`, 91,000 spots |

Together with the three already known invalid (SRR5947529 pig WGS,
SRR14235720 goat RAD-seq, SRR14567890 goat amplicon), **5 of 30 are
demonstrably invalid and 25 are unverifiable because they were never
supplied.**

**Why.** An accession cannot be verified if it is not known, and accessions
must never be guessed.

**Interpretation cost.** The real-library panel is rebuilt from fresh SRA
queries rather than repaired. No original accession is carried into the new
panel unless it passes verification. `verification_log.txt` records the
outcome for every accession considered.

---

## Category 3 — Environment and tooling

### D11. Conda environment created with `--override-channels`

**Specified.** `conda env create -f environment.yml`.

**Done.** `conda create --override-channels -c conda-forge -c bioconda ...`
with the same package list, python pinned to 3.11.

**Why.** A pre-existing `~/.condarc` injects Anaconda's `defaults` channel. The
specified command ran for over 14 minutes in "Solving environment" with no
progress and was killed; the override form solved immediately.

**Interpretation cost.** None. Same packages from the same two channels.
`conda_explicit.txt` records the exact 118-package resolution.

---

### D12. `multiqc` not installed

**Specified.** Listed in `environment.yml`.

**Done.** Omitted.

**Why.** Reporting-only; not invoked by the pipeline or by any benchmark
script. It dominated the dependency solve.

**Interpretation cost.** None. No result depends on it.

---

### D13. WSL memory cap not raised; swap raised instead

**Specified.** "If the host has more, raise the cap in `.wslconfig` with
`memory=<host RAM minus 4GB>` and `swap=32GB`."

**Done.** `memory` left at 12 GB; `swap` raised 4 GB to 32 GB.

**Why.** The host has **one 16.00 GiB DIMM**, 15.64 GiB visible to Windows.
The pre-existing `.wslconfig` already capped memory at 12 GB. "Host RAM minus
4 GB" = 11.64 GB, which is **less** than the cap already in place, so applying
the instruction literally would have *reduced* available memory. There is no
hidden capacity to unlock.

**Interpretation cost.** None to any measurement, but it is the root cause of
D4, D5 and D6. Peak-memory figures reported in `per_library.csv` are measured
under a 12 GB ceiling; a tool that would have used more on a larger machine is
recorded either at its constrained peak or as a failure, never extrapolated.

---

### D14. Hostile comparator configuration corrected

**Specified (in the repository as found).** `hostile clean --index $MM2_INDEX
--out-dir ...`, described as "single-pass minimap2 decontamination".

**Done.** Two configurations: `hostile_default` (no `--index`; Hostile's own
`human-t2t-hla` index; Bowtie2 auto-selected for paired short reads) and
`hostile_matched` (`--aligner bowtie2 --index $BT2_INDEX`, the same
T2T-CHM13v2.0 index every other method uses). Both use `--output`.

**Why.** This is the configuration the reviewers objected to. `--out-dir` was
removed in Hostile 2.0.0 and the command would not have run at all. Hostile
defaults to Bowtie2 for paired short reads; minimap2 is its long-read path.

**Configuration actually run** (`benchmark/scripts/run_e3.sh`): `hostile clean --fastq1 R1 --fastq2 R2
--threads 8 --output wd` (default) and the same command with `--aligner bowtie2 --index $BT2_INDEX`
(matched). KneadData: `kneaddata --input1 R1 --input2 R2 --reference-db $BT2_INDEX --threads 8
--bypass-trf --remove-intermediate-output`, i.e. the same T2T-CHM13v2.0 Bowtie2 index, default
Trimmomatic settings and TRF bypassed.

**Interpretation cost.** Corrects a misconfiguration that would have
understated the comparator. `hostile --version` is asserted to be 2.x before
any comparator run; a 1.x resolution invalidates the comparison and is treated
as a hard failure.

---

### D19. KneadData given an explicit 8 GB JVM heap

**Specified.** Run KneadData with its packaged defaults.

**Done.** `_JAVA_OPTIONS=-Xmx8g` set before every KneadData invocation.

**Why.** Every KneadData run failed identically with
`java.lang.OutOfMemoryError: Java heap space` inside its Trimmomatic step.
Cause: the bioconda build of Trimmomatic ships a Python wrapper executable
that hardcodes `-Xms512m -Xmx1g`, too small for a ~2,000,000-pair library.
KneadData's own `--max-memory` flag does **not** fix this — it is only honoured
on the `java -jar trimmomatic.jar` code path, and this build's wrapper never
takes it. (Tried first; failed identically.) The wrapper drops its hardcoded
default whenever `_JAVA_OPTIONS` is already set in the environment, so a one-line
shim at `envs/kneaddata/bin/kneaddata` exports it and execs the real entry
point.

**Interpretation cost.** None to KneadData's reported accuracy or assembly
figures — a heap ceiling failure has no partial output to be biased by, it
either completes normally afterward or is absent. HostSweep and Hostile are
unaffected; neither runs a JVM. The shim lives in the conda environment, not in
`benchmark/scripts/`, so a fresh machine (including a third one) will hit this
same failure unless `install_comparators.sh`'s `kneaddata` case installs the
shim as part of environment creation.

---

## Category 4 — Scope reductions

### D15. Reduced scope on constrained hardware

**Specified.** Full matrix: 6 tool configurations x 12 synthetic x 3 runs, plus
30 real x 3 runs, plus the downstream arm.

**Done.** Sequenced: synthetic arm first (HostSweep only), then comparators,
then real arm and downstream as hardware and time permit.

**Why.** 8 threads, 12 GB RAM, 574 GB free disk against an assumed 8 threads /
64 GB / 2 TB. The full matrix is multiple weeks of continuous compute here.

---

### D20. Comparator benchmark ships with four tools, not five: BMTagger executed at full scale, DeconSeq dropped

**Specified.** Five-tool comparator table: `hostile_matched`, `hostile_default`,
`kneaddata`, `bmtagger`, `deconseq`, dropping a tool only if it will not
install, and only with a documented reason.

**Done.** `hostile_matched`, `hostile_default` and `kneaddata` were scored
against truth on all 12 synthetic libraries in the earlier session (n=1).
**BMTagger was then executed at full scale in a further session (September 2026):
12 of 12 libraries completed, exit status 0, zero failures** (`per_library.csv`;
primary evidence in `bmtagger_run_raw/`). DeconSeq is dropped outright.

**BMTagger — how it was run.** Environment `bmtagger` from bioconda
(`bmtagger`, `srprism`; package version **not recorded** — only the binary paths
were saved to `record/bmtagger_version.txt`). Index built once against the
full T2T-CHM13v2.0 genome, the same reference used by `hostile_matched` and
HostSweep:
```
bmtool      -d ref.fasta -o ref.bitmask -w 18
srprism mkindex -i ref.fasta -o ref.srprism --memory <MB>
makeblastdb -in ref.fasta -dbtype nucl -out ref.seqdb
bmtagger.sh -b ref.bitmask -x ref.srprism -d ref.seqdb \
            -q 1 -1 r1.fastq -2 r2.fastq -o out -T tmpdir -X
```
No parameter other than `-q 1` (FASTQ input) and `-X` (write the non-matching
reads) was set; BMTagger's defaults were used, and no tuning was attempted for
this panel. The command line was first smoke-tested on a small reference
(*E. coli*, `GCF_000005845.2`), which established two things built into
`run_e3.sh`: **`bmtagger.sh` does not accept gzipped FASTQ**, so each pair is
decompressed to a temporary file first, *outside* the timed section; and its
`-X` output is plain-text `<out>_1.fastq` / `<out>_2.fastq` containing the
human-free reads directly. Every run used one CPU thread (99 % CPU in all 12
`/usr/bin/time` records) and a peak of 8.00 GB, fixed by the bitmask size.

**Result (section 2b of RESULTS.md).** Matched arm: sensitivity 99.9995–100.0000 %
(mean 99.9999 %), FPR 0.0002–0.0003 %. Mismatch arm: sensitivity 99.9250,
99.9575, 99.9543 %, FPR 0.0001–0.0002 %. Background reads removed in error:
2–5 per library. Human read pairs left: 15 of 20,000 (`SYN-IND-01`), 85 of
200,000 (`SYN-NEU-02`), 183 of 400,000 (`SYN-NEU-03`), against HostSweep's 8,
47 and 109. **This is unfavourable to HostSweep on specificity** (BMTagger's FPR
is roughly two orders of magnitude lower than HostSweep's 0.013–0.015 %) and
favourable to HostSweep on mismatch-arm sensitivity (HostSweep is greater or
equal on 12 of 12 libraries, strictly greater on 6). Both facts are reported.

**Check before it was trusted.** The same session regenerated the synthetic
libraries and re-ran `hostile_matched` and `kneaddata` on all 12. Their
sensitivity and FPR are **identical in every digit to the committed rows on 24
of 24** (BMTagger's rows are new; nothing was compared for them). The
regenerated `synthetic_manifest.csv` is also identical to the committed one.

**Timing is not comparable to the other rows of the table (D17/D18).** The
BMTagger rows were timed in that further session; the other comparator rows in
`per_library.csv` were timed in an earlier one. The same-session numbers for
the three tools re-run together are in `bmtagger_run_raw/csv/per_library.csv`
(BMTagger 4.9–6.4 min, KneadData 0.8–2.0, Hostile 0.24–0.31). Against the
earlier session's timings for the same tools and libraries these differ by
1.9–4.8x, so no runtime column should be built across the two. The valid five-tool runtime and
memory comparison is the single-session R1 run (D17 addendum).

**DeconSeq — dropped, per the original instruction.** Not on bioconda; the
project's own install path is a manual download plus a hand-edited
`DeconSeqConfig.pm` pointing at local BLAST/bwa binaries and reference
databases. Given the instruction to drop rather than hand-roll a fragile
install, it is excluded rather than attempted.

**Interpretation cost.** The comparator table has four tools. A claim of the
form "HostSweep versus every requested comparator" is not supportable: DeconSeq
is absent and must be named as absent. Describe the comparison as "Hostile (two
configurations), KneadData and BMTagger," not as "the comparator suite." Any arm
not completed is reported as absent, never estimated. `STATUS.md` records what
ran; failures appear as `FAILED` rows with their exit status, not as omissions
(with the one exception recorded in D21, where the rows are kept out of
`per_library.csv` to avoid colliding with measured rows, but preserved
unaltered in `bmtagger_run_raw/`).

---

### D21. `hostile_default` could not be re-run in that session (index download failed); resolved in R1

**Specified.** Re-run every comparator on the regenerated libraries alongside
BMTagger.

**Done.** `hostile_matched` and `kneaddata` were re-run and reproduced. All 12
`hostile_default` attempts **failed with exit status 1**: `hostile` (v2.0.2)
tries to download its default T2T+HLA index, and the request to
`https://objectstorage.uk-london-1.oraclecloud.com/n/lrbvkel2wjot/b/human-genome-bucket/o/human-t2t-hla.tar`
raised `httpx.HTTPError: Failed to download ... Ensure you are connected to the
internet, or provide a valid path to a local index`. The failure is a network
failure on that machine's link, not a Hostile fault.

**Handling.** Nothing was substituted and nothing estimated. The 12 FAILED
records (`hostile_default_run1.failed`, `.stderr`, `.time`) are preserved
unaltered in `bmtagger_run_raw/evidence/results/<library>/`. They were **not**
appended to `per_library.csv`: that file already holds a measured
`hostile_default` row for every one of these (library, run) keys from the
earlier session, and adding FAILED duplicates would make the file
self-contradictory. The measured rows are unchanged. That session's
self-audit accordingly reports "12/48 rows have no metrics JSON" — an expected
consequence, and it is preserved with the raw delivery (`bmtagger_run_raw/csv/AUDIT.md`).

**Interpretation cost (at the time this was written).** `hostile_default`
rested on a single (earlier) session, n=1, and was not independently
reproduced. Its sibling `hostile_matched` was reproduced exactly on all 12
libraries, and the two configurations were identical or near-identical on
every library, but that was an inference and not a re-measurement of
`hostile_default` itself.

**Resolved (further session, September 2026, R1).** A local copy of Hostile's
default T2T+HLA index was obtained (the objectstorage.uk-london-1 host was
reachable that time) and proven with a real `hostile clean` invocation before
any timed run started. `hostile_default` then completed **all 36 of 36 runs**
(12 libraries × 3 replicates, n=3) with zero failures, in the same clean
session as the other four tools. Its accuracy reproduces the earlier n=1
measurement exactly on all 12 libraries (0 mismatches). `hostile_default` no
longer rests on a single session — it now has the same n=3 evidence base as
every other tool in `per_library.csv`. See D17's addendum for the resulting
runtime/memory comparison.

---

### D16. The requested Han1 soft-mask test does not work; provenance used instead

**Specified.** "Verify that the HG00733 and NA19240 assemblies you're using are
pure de novo with no CHM13-derived sequence... stream each of the three HPRC
FASTAs and reject anything above 0.01% soft-masked."

**Done.** The measurement was taken and is reported, but it is **not** used as
a rejection criterion. The gate is provenance instead.

**Why.** The premise — that Han1-style CHM13 gap-fill shows up as lowercase and
a clean assembly does not — does not survive a control. Measured with
`check_softmask_control.py`:

| FASTA | Total bases | Lowercase |
|---|---|---|
| **T2T-CHM13v2.0 itself** | 3,117,275,501 | **40.2743%** |
| HG00438 HPRC year 1 | 3,035,735,720 | **39.5468%** |
| *E. coli* GCF_000005845.2 | 4,641,652 | **0.0000%** |

T2T-CHM13v2.0 cannot contain CHM13-derived gap-fill — it *is* CHM13 — yet it
carries **more** lowercase than the HPRC assembly. Lowercase in NCBI's
distributed eukaryotic FASTA is repeat soft-masking, applied by NCBI's own
pipeline; the bacterial control at 0.0000% confirms it is repeat-driven rather
than a blanket transformation. A 0.01% threshold would reject every human
assembly ever distributed by NCBI, including the decontamination reference.

**No sequence-composition test can establish reference independence.** Every
human assembly is ~99.9% identical to T2T-CHM13v2.0, so sequence that
originated from CHM13 is indistinguishable, by composition or by similarity,
from sequence assembled de novo from the same locus in another individual.
Han1-style reference contamination is therefore detectable only from an
assembly's documentation — its assembly method, its release notes, and the
submitter's own description of how gaps were filled — and never from the
FASTA alone. This applies to the lowercase test specifically and to any
substitute for it.

The threshold is dropped entirely; lowercase is retained as descriptive
metadata only.

**What is checked instead**, per assembly, before use:
- assembly method is `Hifiasm v. 0.14` — de novo from HiFi reads, no reference input;
- assembly level is Contig or Scaffold, never Chromosome — chromosome-level
  release would imply reference-guided scaffolding, and is rejected;
- submitter is UCSC Genomics Institute (HPRC), not JHU;
- sample is not HG00621, which is on an explicit exclusion list, and the
  assembly name is checked against the Han1 pattern.

All three sources pass all four. Lowercase percentages are recorded in
`human_sources_provenance.json` as descriptive metadata.

**Interpretation cost.** The assurance against reference contamination rests on
documented provenance rather than on a sequence measurement. That is weaker in
form but it is the strongest claim the data can support, and it is stated
plainly rather than dressed up as an empirical test that in fact measures
repeat content.

---

## Category 5 — Incidents affecting data integrity

### I1. Concurrent writers corrupted one synthetic library (detected, discarded)

**What happened.** Two `mix_spikein.py` processes were found running
simultaneously against the same `--out-prefix`
(`.../synthetic/SYN-CHM13-01`), PIDs 497 and 925. Both were writing
`SYN-CHM13-01_R1.fastq.gz`, `_R2.fastq.gz` and `_labels.tsv.gz` at once. The
cause was a suspended `wsl.exe` invocation reconnecting after the WSL2 guest
restarted and re-running its command alongside a freshly launched one.

**Why it matters.** Interleaved writes from two processes produce a library
whose reads and truth labels no longer correspond. It would not have looked
broken — the files are valid gzip and roughly the right size — but every
sensitivity and false-positive-rate number computed from it would have been
meaningless. This is precisely the failure mode that is invisible in a summary
table.

**Action.** Both processes were killed, all three output files were deleted
unread, and the library was rebuilt from scratch. **No measurement was taken
from the corrupt files, and none entered any results file.**

**Prevention.** `02_build_synthetic.sh` now takes an exclusive `flock` on
`<workdir>/.e2.lock` and exits without touching anything if another instance
holds it. The lock semantics were tested directly (a second instance correctly
declines).

**Interpretation cost.** None, provided the rebuild is clean. It is recorded
because the reader is entitled to know that the pipeline's outputs were
checked for this class of corruption rather than assumed free of it.

### I2. Real-library assembly metrics computed against auto-selected references (detected, withdrawn)

**What happened.** For the three real libraries in E9, `metaquast.py` was run
without `-r`, intending a reference-free assessment. MetaQUAST's documented
behaviour without `-r` is to BLAST the contigs against SILVA 16S and download
matching reference genomes from NCBI itself. It did — 46 genomes for the gut
library, 7 for respiratory, 47 for blood — and reported genome fraction and
misassemblies against them.

**Why it matters.** Each method's MetaQUAST run chose references from **that
method's own contigs**, so the three cleaning methods were scored against
different reference sets:

| gut library `SRR40486826` | reference genomes | total reference length |
|---|---|---|
| HostSweep | 44 | 28.7 Mb |
| Hostile | 45 | 36.1 Mb |
| KneadData | 44 | 66.3 Mb |

HostSweep and KneadData shared 18 of 44 genomes, and KneadData's reference was
2.3x larger. More reference sequence means more places to call a
misassembly, so a comparison across these sets measures the reference, not the
cleaning method. The protocol had already required reference-based columns to
be empty for real libraries; this is the mechanism behind that rule.

**Consequence before detection.** A results summary reported *"869
misassemblies against HostSweep's 292"* on the gut library as the headline
downstream finding. That figure was withdrawn.

**Action.** Genome fraction and misassemblies were blanked for all real
libraries in `downstream.csv` (16 cells across 8 rows). Reference-free metrics —
N50, total length, contig counts, largest contig, assembled Mb ≥ 1 kb,
duplication ratio — depend only on the contigs and were retained.
`run_e9.sh` now passes `--max-ref-number 0` for real libraries so MetaQUAST
cannot fetch references, and additionally blanks the two columns in code for
any real library, so the rule no longer rests on a comment.

**What survives.** The synthetic arm was unaffected — it used the known
ten-genome set via `-r`, identical across methods, and MetaQUAST downloaded
nothing. There, KneadData still produces 1.7–2.5x more misassemblies per
assembled Mb than HostSweep or Hostile (the earlier "2.9x" was an arithmetic
error; the ratios are 1.69, 2.49 and 2.23 against HostSweep). The reference-free
real-library metrics also point the same way: KneadData gives the lowest N50 on
all three real libraries (when this entry was first written it had run on two). The finding holds; it is smaller than first stated.

**How it was caught.** The script's own comment claimed the reference-based
columns would be "empty for reference-free runs". They were populated. The
contradiction between that comment and the data it produced was the signal.

**Addendum, 2026-09-13: a second reference-based column was missed the first
time.** `duplication_ratio` — the fraction of aligned contig length that maps
more than once to the reference — is computed the same way genome fraction and
misassemblies are: from an alignment to a reference. It requires exactly the
mechanism this incident withdrew, and it was left populated on all 8
real-library rows when the first correction blanked only `genome_fraction_pct`
and `misassemblies`. Confirmed empirically before touching anything: a later,
independent re-run of E9 with the already-fixed `run_e9.sh`
(`--max-ref-number 0`) came back with `duplication_ratio` blank on every
real-library row, because MetaQUAST has no reference to compute it against.
The repo's `downstream.csv` has now been corrected to match —
`duplication_ratio` blank on all real-library rows, synthetic rows untouched.

---

### I3. Kraken2 `reads_total` and `pct_human` were mis-computed in `kraken2_human.csv` (detected, corrected)

**What happened.** For each (library, method) pair `run_e9.sh` reduced the Kraken2
report to `reads_total`, `reads_human` and `pct_human`. Kraken2 writes the
unclassified reads on their own `U` line, and the `root` line's clade count covers
**classified** reads only, so the number of reads that went in is the sum of the
two. The parser did

    total = max(total, root_clade)     # on the root line
    total += unclassified              # on the U line

in the order the lines appear (U first), which leaves `total` equal to whichever of
the two counts is larger. On these libraries that is the unclassified count, about
67 % of the true total on the synthetic libraries and 78-86 % on the real ones.
`reads_total` was therefore wrong in every row, and `pct_human = reads_human /
reads_total` was too high by a factor of 1.2 to 1.5. `reads_human` (the Homo
sapiens clade) was correct throughout.

**How it was caught.** Not by inspecting the results. While writing a test for the
Kraken2 step of the full-Standard run (R4), the test's expected total for a fake
report with 100 unclassified and 900 in the root was 1,000; the parser returned 900.
Reading the real reports confirmed the same fault: `SYN-CHM13-01` / hostile has
2,687,272 unclassified and 1,308,728 in the root, and the committed `reads_total`
was 2,687,272.

**Check on the fix.** With total = unclassified + root, `SYN-CHM13-01` / hostile is
3,996,000 = 2 x 1,998,000, exactly the number of read pairs that library has left
after cleaning (2,000,000 pairs less the 2,000 human pairs it was built with).

**Consequence before detection.** `kraken2_human.csv` and the "Residual human
content" table in RESULTS.md carried the wrong `reads total` and `% human` columns.
No claim in the text depended on them: every comparison (KneadData leaves fewer
human reads than HostSweep on five of six libraries; HostSweep 27x fewer than
Hostile on the blood library; and so on) is made on the `reads_human` counts, which
were correct.

**Action.** The parser is now `kraken2_report_to_csv.py`, used by both the E9 step
and the new R4 step, and `run_e9.sh`'s inline copy was corrected the same way.
`kraken2_human.csv` was recomputed from the 18 `k2.report` files kept as evidence
(all 18 `reads_human` values and all 18 `db_build_date` values identical to the
committed ones; only `reads_total` and `pct_human` changed) and the RESULTS.md table
was rewritten from it. The uncorrected file is kept unchanged as
`kraken2_human_uncorrected_I3.csv`, and the raw delivery in `bmtagger_run_raw/`
still contains the uncorrected `kraken2_human.csv` exactly as the run wrote it.

**Interpretation cost.** Anything quoted from the old `% human` column should be
replaced by the corrected value. The direction of every comparison is unchanged
because it depends on counts.

---

---

### I4. metaSPAdes `spades-hammer` failures: 7 of 18 pairs have no metaSPAdes assembly (detected, unresolved)

**What happened.** In the exploratory metaSPAdes downstream arm (`run_metaspades_e9.sh`, R2), the
BayesHammer error-correction step (`spades-hammer`) failed intermittently at high thread counts, in
two ways. The identical command on the identical read pair produced both, so the failure is not
deterministic. (a) A segmentation fault inside libgomp/OpenMP during the second multithreaded k-mer
counting pass, occurring anywhere from about 3 minutes to about 13 hours into a run. (b) A run that
produced no crash and no progress for more than 20 hours, a hang and not a slow success. Memory use
at the point of failure was far below the `-m` limit in every case observed, which rules out a
resource-limit crash as the cause.

**Mitigation attempted.** Each (library, method, replicate) was given up to three attempts, halving
the thread count after each failure (floor 4), and each attempt was wrapped in a three-hour
wall-clock limit so that a hang is force-killed and counted as a failed attempt. Child processes that
survived the kill were removed. A pair is marked FAILED only if every attempt fails or times out.
The stderr and `spades.log` of every failed attempt are kept as evidence.

**Outcome.** The cause was not found and the problem was not resolved within the time budget of the
benchmark. **11 of 18 (library, method) pairs produced a metaSPAdes assembly; 7 did not.** The 7
failed pairs are recorded as FAILED rows in the metaSPAdes CSVs and have no CheckM2 row, because there
is no assembly to score; they are absent, not estimated.

**Interpretation cost.** The metaSPAdes arm is exploratory and does not replace the MEGAHIT arm that
carries the main downstream comparison (D4). CheckM2 results (D6) exist only for the 11 pairs that
assembled, and the failures are not random with respect to the comparison of interest if they
cluster on particular libraries or methods; no analysis of that was done. The failure is in
metaSPAdes, not in any cleaning method.