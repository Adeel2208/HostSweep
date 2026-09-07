# Deviations from reviewer- and editor-specified methods

**Manuscript:** BIOADV-2026-394 (Bioinformatics Advances, major revision)
**Maintained:** from 2026-09-06, updated whenever a departure occurs.
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

---

### D6. CheckM2 dropped

**Specified.** "Add CheckM2 completeness/contamination if you can run it; if
not, say so explicitly."

**Done.** Not run.

**Why.** CheckM2 needs roughly 15 GB RAM plus its reference database, above
the 12 GB ceiling.

**Interpretation cost.** No completeness or contamination statistics are
reported. The specification explicitly permitted this outcome provided it is
stated. It is stated here and in `STATUS.md`.

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

**Interpretation cost.** Corrects a misconfiguration that would have
understated the comparator. `hostile --version` is asserted to be 2.x before
any comparator run; a 1.x resolution invalidates the comparison and is treated
as a hard failure.

---

## Category 4 — Scope reductions

### D15. Reduced scope on constrained hardware

**Specified.** Full matrix: 6 tool configurations x 12 synthetic x 3 runs, plus
30 real x 3 runs, plus the downstream arm.

**Done.** Sequenced: synthetic arm first (HostSweep only), then comparators,
then real arm and downstream as hardware and time permit.

**Why.** 8 threads, 12 GB RAM, 574 GB free disk against an assumed 8 threads /
64 GB / 2 TB. The full matrix is multiple weeks of continuous compute here.

**Interpretation cost.** Any arm not completed is reported as absent, never
estimated. `STATUS.md` records exactly what ran. Row counts in the CSVs reflect
what was attempted; failures appear as `FAILED` rows with their exit status,
not as omissions.

---

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

There is also no similarity-based substitute: every human genome is ~99.9%
identical to CHM13, so "sequence that resembles CHM13" is indistinguishable
from ordinary human sequence. The Han1 contamination is knowable only because
its authors documented it.

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

---

*No entry in this file describes a number that was estimated, interpolated or
carried over. Where a measurement does not exist, the corresponding cell is
absent or `FAILED`.*
