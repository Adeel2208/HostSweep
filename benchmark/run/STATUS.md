# Benchmark run status

**Manuscript:** BIOADV-2026-394 (Bioinformatics Advances, major revision)
**Session started:** 2026-09-06
**Command journal:** [`logs/commands.log`](logs/commands.log)

---

## Headline

**The benchmark has not been run. No measurement exists in this directory, and
none of the deliverable CSVs have been created.** Stage 0 did not pass: this
machine has no bioinformatics toolchain installed and its hardware is below the
stated assumption by roughly 4x on RAM and 3.5x on disk.

Stage 1 (repository corrections) is complete except for the two items that
require executed runs. Details below.

---

## Stage 0 — Environment: **FAILED (gate)**

Measured 2026-09-06, logged in `logs/commands.log`.

### Hardware vs. the stated assumption

| Resource | Assumed | Measured (Windows host) | Measured (WSL2 Ubuntu) |
|---|---|---|---|
| Threads | 8 | 12 logical CPUs | 8 |
| RAM | >= 64 GB | **15.6 GB total, 1.5 GB free** | **11 GB available** |
| Free disk | >= 2 TB | **574.6 GB free of 953.0 GB** | same volume |
| OS | Linux implied | Windows 10 Pro (MINGW64) | Ubuntu, kernel 6.6.87.2-WSL2 |

Threads are fine. RAM and disk are not.

### Toolchain

`conda`, `mamba`, `micromamba` and `docker`: **all absent.** Without a package
manager the Stage 0 install block cannot start.

All 21 tools the protocol invokes are absent from PATH:

```
fastp minimap2 bowtie2 bowtie2-build samtools bbduk.sh
hostile kneaddata bmtagger srprism bmtool
metaspades.py metaquast.py kraken2 checkm2
esearch efetch datasets prefetch fasterq-dump art_illumina blastn
```

WSL2 Ubuntu is present, starts, and has working outbound network (HTTP 200 to
`repo.anaconda.com`). It is a viable Linux target for an install, but it shares
the same 574 GB volume and has less RAM than the Windows host.

### Consequences for specific stages, if run here anyway

- **`metaspades.py -m 120`** requests a 120 GB memory cap on a 15.6 GB machine.
  Stage 8 specifies 54 assemblies (18 libraries x 3 methods).
- **Kraken2 standard DB** is ~90 GB on disk and wants comparable RAM to load.
  Both exceed what is available alongside the read data.
- **Disk**: 30 real SRA libraries at 3 runs each, plus 12 synthetic libraries
  across 6 tool configurations at 3 runs each, plus the T2T indices, the
  Kraken2 DB and 54 metaSPAdes working directories does not fit in 574 GB.
- **Wall clock**: ~306 cleaning runs plus 54 assemblies on 8 threads is a
  multi-week job, not a session.

**Nothing was installed.** Building ~10 GB of conda environments on a machine
that cannot finish the job would waste hours and disk for no measurement, so
this is left for your decision — see *What I need from you*.

---

## Stage 1 — Repository corrections: **7 of 9 done**

| Item | Status | Notes |
|---|---|---|
| 1.1 Hostile 2.x comparator | **DONE** | `run_hostile()` replaced by `run_hostile_default` (no `--index`, default `human-t2t-hla`, Bowtie2 auto-selected for paired input) and `run_hostile_matched` (`--aligner bowtie2 --index $BT2_INDEX`). Both use `--output`, not the removed `--out-dir`. `hostile_version.txt` **not** written — hostile is not installed, so the 2.x assertion is unverified. |
| 1.2 Peak-memory capture | **DONE** | Every tool invocation wrapped in `/usr/bin/time -v -o <out>.time` with a `gtime` fallback, mirroring `run_hostsweep.sh`. `timing.tsv` now carries `wall_clock_seconds`, `peak_rss_kb` and `exit_status` per (sample, tool). Parsers unit-tested against synthetic `time -v` files: max RSS across files, summed elapsed, `NA` when absent. |
| 1.3 `genomes.tsv` | **DONE, with an unresolved conflict** | Committed and all ten accessions verified live against the NCBI Datasets v2 API. **Three accessions are not the organism they were paired with** — see below. |
| 1.4 Remove "reconstructed" notes | **NOT DONE — deliberately** | The instruction is to remove them *by making them untrue*, which requires a real accession list, genome list and seed table from executed runs. Nothing has been executed, so removing the notes would replace an accurate caveat with a false claim. The `accessions.csv` INCOMPLETE header stands. |
| 1.5 Synthetic panel protocol | **DONE (spec only)** | Rewritten to 9 CHM13-matched + 3 haplotype (HG00514, HG00733, NA19240), `-m 200 -s 10`, seeds 42-53, 2.0 M pairs, fractions 0.1/0.5/1/5/10/20/40/5/10 % then 1/10/20 %. Carries an explicit "not a record of a completed run" banner instead of the old vague hedge. |
| 1.6 `tests/README.md` | **DONE** | Prose now matches the code: the command ends in `\| gzip > <path>`. Also documents the new negative-case test and the magic-byte check on all four cleaned outputs. |
| 1.7 `.gitignore` | **DONE** | Bulk data still excluded (FASTQ/BAM/SAM/CRAM/indices/bitmask/srprism/references). Un-ignored: `*.csv`, `*.tsv`, `*.json`, `*.time`, MetaQUAST reports, and `benchmark/run/logs/**` (the blanket `*.log` rule would otherwise have dropped the raw stdout). Verified with `git check-ignore`: metrics JSON, `.time` and logs track; `.fastq.gz` stays ignored. |
| 1.8 README corrections | **DONE** | DecontaMiner naming section deleted. Hostile re-described as short-read decontamination defaulting to Bowtie2 for paired short reads (minimap2 is its long-read path), cited as Constantinides B, Hunt M, Crook DW (2023). Acknowledgements updated to include Hunt. |

### Unresolved: three accession/organism conflicts in `genomes.tsv`

All ten accessions resolve, but three name a different organism than specified
(`logs/00_verify_genomes.log`):

| Accession | Specified as | NCBI returns |
|---|---|---|
| `GCF_000009605.1` | Lactobacillus acidophilus NCFM | **Buchnera aphidicola APS** (655,725 bp) |
| `GCF_000007565.2` | Bacteroides thetaiotaomicron VPI-5482 | **Pseudomonas putida KT2440** |
| `GCF_000012825.1` | Bifidobacterium longum NCC2705 | **Phocaeicola vulgatus ATCC 8482** |

Verified accessions for the organisms as named: `GCF_000011985.1`,
`GCF_000011065.1`, `GCF_000007525.1`. Which is authoritative changes the
background community and the MetaQUAST reference set, so `genomes.tsv` records
both and picks neither.

`GCF_000009605.1` matters most: *Buchnera aphidicola* is a 0.66 Mb insect
endosymbiont, not a 2 Mb gut lactobacillus, so at abundance 0.08 it would
contribute roughly a third of the intended read count.

---

## Stages 2-10: **NOT STARTED**

| Stage | Status | Blocker |
|---|---|---|
| 2 — E1 accession panel | **BLOCKED** | Two blockers. (a) No `esearch`/`efetch`. (b) **`accessions.csv` holds 2 of 30 runs.** The other 28 are in Supplementary Table S1, which is not in this repository and was not provided. A panel cannot be verified without the list, and accessions must not be invented. |
| 3 — E2 synthetic panel | BLOCKED | No `art_illumina`; genome conflicts unresolved; HPRC assembly accessions for HG00514/HG00733/NA19240 not specified. |
| 4 — E3/E4 main benchmark | BLOCKED | No tools; depends on stages 2 and 3. |
| 5 — E5 dual-pass ablation | BLOCKED | Depends on stage 3. |
| 6 — E7 threshold sweep | BLOCKED | Depends on stage 3. |
| 7 — E8 labelling sensitivity | NOT APPLICABLE YET | Conditional on stage 4 producing real-library accuracy. |
| 8 — E9 downstream | BLOCKED | Also infeasible on 15.6 GB RAM as specified (`-m 120`). |
| 9 — Self-audit | NOT STARTED | Nothing to audit. `audit.py` not written. |
| 10 — Package | NOT STARTED | No `results_bundle/`, no zip. |

**No deliverable CSV has been created**: `accessions_verified.csv`,
`synthetic_manifest.csv`, `per_library.csv`, `ablation.csv`,
`threshold_sweep.csv`, `labelling_sensitivity.csv`, `downstream.csv`,
`kraken2_human.csv`, `versions.txt`, `conda_explicit.txt` — none exist. They
are absent rather than empty or placeholder, so nothing here can be mistaken
for a result.

---

## Carried-over values to watch

The benchmark table in `README.md` (sensitivity 99.84 / 99.41 / 96.24 / 94.87 /
91.45 %, runtime 11.2 min, peak memory 6.8 GB, FPR 2.76 %) is **not** reproduced
by anything in this session. These are the figures the reviewers found
irreproducible. They are left untouched, and the Stage 9 audit must treat any
computed mean landing exactly on one of them as a red flag rather than a
confirmation.

---

## What I need from you

1. **A machine that fits the job**, or an explicit decision to cut scope. As
   specified the run needs >= 64 GB RAM and ~2 TB disk; this host has 15.6 GB
   and 574 GB.
2. **The 28 missing SRA accessions** (Supplementary Table S1). Stage 2 cannot
   start without them, on any hardware.
3. **A ruling on the three genome conflicts** — accession authoritative, or
   organism name authoritative?
4. **The HPRC assembly accessions and versions** for HG00514, HG00733 and
   NA19240.
