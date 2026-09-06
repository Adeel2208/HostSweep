# Benchmark run status

**Manuscript:** BIOADV-2026-394 (Bioinformatics Advances, major revision)
**Session:** 2026-09-06
**Command journal:** [`logs/commands.log`](logs/commands.log)
**Scope:** reduced to the synthetic arm (E2/E3/E5/E7) by decision, after the
Stage 0 hardware probe. The 30 real libraries, Kraken2 and most of E9 are out
of scope on this hardware.

---

## Headline

The toolchain is installed and verified, the reference index is building, and
the synthetic background community is simulated. **No benchmark measurement
exists yet** — no `per_library.csv`, no `ablation.csv`, no
`threshold_sweep.csv`. Those files are absent rather than empty, so nothing
here can be mistaken for a result.

---

## Stage 0 — Environment: **PASSED (reduced scope)**

### Hardware, measured

| Resource | Assumed | Windows host | WSL2 Ubuntu (used) |
|---|---|---|---|
| Threads | 8 | 12 logical | 8 |
| RAM | >= 64 GB | 15.6 GB | 11.7 GB |
| Free disk | >= 2 TB | 574.6 GB | 896 GB on the same volume |

RAM is ~4x short and disk ~3.5x short of the assumption. That is why the real
arm, Kraken2 and metaSPAdes are out of scope: `metaspades.py -m 120` asks for
120 GB, and the Kraken2 standard DB is ~90 GB on disk with comparable RAM to
load.

### Toolchain, installed and verified

Miniforge + a `hostsweep` conda env in WSL2. `conda env create` from
`environment.yml` stalled for over 14 minutes on the `defaults` channel
injected by a pre-existing `~/.condarc`; it was killed and replaced with
`conda create --override-channels -c conda-forge -c bioconda`, which solved
immediately. Recorded in `logs/commands.log`.

```
hostsweep      1.0.0          fastp     1.3.6
python         3.11.16        minimap2  2.31-r1302
samtools       1.24           BBTools   40.02
art_illumina   2.5.8          seqkit    installed
```

Full record: [`record/versions.txt`](record/versions.txt),
[`record/conda_explicit.txt`](record/conda_explicit.txt) (118 packages).

**`pytest tests/ -v` → 11 passed, 0 skipped**, including both end-to-end tests,
which skip on Windows for lack of aligners. This is the first execution of the
full pipeline against real minimap2/bowtie2/samtools/BBDuk, and it exercises
the `extract_unmapped_single` gzip fix end to end.

### Deviations from the Stage 0 install block

| Specified | Done | Why |
|---|---|---|
| `conda env create -f environment.yml` | `conda create --override-channels` | see above; same packages, minus `multiqc` |
| `multiqc>=1.14` | **not installed** | reporting-only, unused by pipeline or benchmark; it dominated the solve |
| `bowtie2 --version` in versions.txt | line captured is a loader warning | bowtie2 prints `[WARNING] Failed to launch x86-64-v3 version` first; the binary works (tests pass). To be re-captured. |
| hostile / kneaddata / bmtagger / deconseq envs | **not created yet** | out of the critical path until the index exists |

---

## Stage 1 — Repository corrections: **8 of 9 done**

| Item | Status |
|---|---|
| 1.1 Hostile 2.x comparator | DONE — `run_hostile_default` + `run_hostile_matched`, both on `--output` |
| 1.2 Peak-memory capture | DONE — `/usr/bin/time -v` on every invocation; parsers unit-tested |
| 1.3 `genomes.tsv` | DONE — all ten accessions verified live at NCBI |
| 1.4 Remove "reconstructed" notes | **NOT DONE, deliberately** — requires executed runs; see below |
| 1.5 Synthetic panel protocol | DONE — 9+3, `-m 200 -s 10`, seeds 42-53, 2.0 M pairs |
| 1.6 `tests/README.md` | DONE — prose matches the gzip pipe |
| 1.7 `.gitignore` | DONE — verified with `git check-ignore` |
| 1.8 README corrections | DONE — DecontaMiner section removed, Hostile corrected |

**1.4 remains open on purpose.** The instruction was to remove the notes *by
making them untrue*. `benchmark/accessions.csv` still holds 2 of 30 runs, so
its INCOMPLETE header is still accurate and stays. The `synthetic/README.md`
note was replaced with a precise execution-status banner rather than deleted.

### Genome conflicts: resolved

Three accessions resolved to different organisms than specified. Ruling
received: **organism names are authoritative.** Applied and re-verified — all
ten accessions now return the organism they are paired with.

| Organism | Was | Now |
|---|---|---|
| *L. acidophilus* NCFM | `GCF_000009605.1` (*Buchnera aphidicola*) | `GCF_000011985.1` |
| *B. thetaiotaomicron* VPI-5482 | `GCF_000007565.2` (*P. putida*) | `GCF_000011065.1` |
| *B. longum* NCC2705 | `GCF_000012825.1` (*P. vulgatus*) | `GCF_000007525.1` |

---

## Stage 2 — E1 real accession panel: **OUT OF SCOPE, and blocked anyway**

Dropped with the real arm. It was independently blocked: `accessions.csv` holds
2 of 30 runs and the other 28 are in Supplementary Table S1, which was not
provided. The three known-invalid accessions (SRR5947529, SRR14235720,
SRR14567890) are **not** replaced.

---

## Stage 3 — E2 synthetic panel: **IN PROGRESS**

| Step | Status |
|---|---|
| Background genomes downloaded | **DONE** — all 10 via the NCBI Datasets API |
| Background reads simulated | **DONE** — ART HS25, 150 bp PE, `-m 200 -s 10`, 200x community coverage |
| T2T-CHM13v2.0 download + index | **RUNNING** — `hostsweep --build -t 8` |
| Human reads simulated | pending the reference |
| 12 libraries mixed | pending |
| `synthetic_manifest.csv` | pending |

### Deviations, both forced by the hardware and both documented in the script

1. **Human coverage `-f 0.2`, not `-f 5`.** The largest human draw any library
   makes is 40% of 2,000,000 = 800,000 pairs. `-f 5` over the 3.1 Gb reference
   yields ~51 M pairs per source (~20 GB each, four sources) and discards over
   98%. `-f 0.2` yields ~2.07 M pairs, still 2.5x the largest draw. Truth
   labelling is unaffected — `mix_spikein.py` subsamples from whatever pool it
   is given.
2. **Background coverage 200x, not 50x.** At 50x the pool holds only ~717 k
   pairs, but a 0.1%-human library needs ~1.998 M background pairs. A pool
   smaller than the largest draw makes the realised fraction silently miss the
   requested one. 200x yields ~2.9 M pairs.

### Mismatch arm: assumption made, flag for correction

The instruction said "haplotype-resolved assemblies for HG00514, HG00733,
NA19240 (HPRC)". **HG00514 has no HPRC assembly** — it is an HGSVC sample
(Chaisson et al. 2019). Candidates found and verified at NCBI
(`logs/00_haplotype_assembly_search.log`):

| Sample | Chosen | Note |
|---|---|---|
| HG00514 | `GCA_056691535.1` (HG00514_hap1, UPenn, chromosome-level, 3.09 Gb) | **not HPRC**; no HPRC assembly exists |
| HG00733 | `GCA_018506955.2` (HG00733_pat_hprc_f2, UCSC) | genuine HPRC |
| NA19240 | `GCA_018503265.2` (NA19240_pat_hprc_f2, UCSC) | genuine HPRC |

These were chosen rather than confirmed, to avoid blocking the whole mismatch
arm. Each is recorded in `synthetic_manifest.csv` as `source_accession`, so
substituting a different assembly is a re-run of three libraries. **Confirm
before publication.**

---

## Stages 4-10

| Stage | Status |
|---|---|
| 4 — E3 (synthetic only) | NOT STARTED — driver `run_e3.sh` written and syntax-checked |
| 4 — E4 real libraries | OUT OF SCOPE |
| 5 — E5 ablation | NOT STARTED — driver `run_ablation.py` written |
| 6 — E7 threshold sweep | NOT STARTED — driver `run_e7.sh` written |
| 7 — E8 labelling | NOT APPLICABLE (needs the real arm) |
| 8 — E9 downstream | OUT OF SCOPE (metaSPAdes/Kraken2 exceed 15.6 GB RAM) |
| 9 — Self-audit | **HARNESS READY AND TESTED** |
| 10 — Package | NOT STARTED |

### The audit harness is verified, not just written

`audit.py` was run against deliberately fabricated input — three "replicates"
made by perturbing one value by +/-0.05 — and correctly **exited 1**, reporting:

- the shared gap pattern `[0.05, 0.05]` across 12 of 12 varying groups,
- 18/18 rows with no metrics JSON and no `.time` file,
- a mean landing exactly on the published 6.8 GB figure.

Run now against the real (empty) run directory, it reports that no result file
exists.

---

## Realistic remaining time

Measured rates on this machine: T2T downloads at ~15 MB/min, so the reference
alone is ~1 hour, then minimap2 indexing and `bowtie2-build` on 3.1 Gb.

| Work | Estimate |
|---|---|
| T2T download + both indices | 4-6 h |
| Human ART + 12 mixes | ~2 h |
| E3, hostsweep only, 12 x 3 runs | 18-27 h |
| E3, plus 3 comparator configs | +3-4 days |
| E5 ablation, 12 x 3 x 3 | ~18 h |
| E7 sweep, 3 libraries | ~2 h (Step-8 caching; see below) |

**The full reduced scope is several days of continuous compute, not a
session.** Everything is checkpointed and idempotent, so the job resumes.

`run_e7.sh` cuts the sweep from ~44 h to ~2 h: `--bbeg` and
`--stringent-minlen` are read only by Step 8, whose input is the Step 7
profiling output, so steps 0-7 are byte-identical across all 25 combinations.
The pipeline runs once per library and Step 8 runs 25 times against the cached
tier. `VERIFY_FULL=1` asserts that equivalence against a complete run instead
of assuming it.

---

## Carried-over values to watch

The `README.md` benchmark table (99.84 / 99.41 / 96.24 / 94.87 / 91.45 %
sensitivity; 11.2 min; 6.8 GB; 2.76 % FPR) is **not** reproduced by anything in
this session and is untouched. `audit.py` check 5 treats any computed mean
landing on one of these as a failure.

---

## Open items for the authors

1. **Confirm the HG00514 assembly** (`GCA_056691535.1`) — no HPRC assembly
   exists for that sample.
2. **The 28 missing SRA accessions**, if the real arm is ever run.
3. **Which comparators to install** — each needs its own env and index; Hostile
   also downloads its own ~5 GB default index.
