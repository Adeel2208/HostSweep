# HostSweep benchmark — results from this machine (Ozi), 2026-09-12

Run: relaunched 07:54 UTC, finished 19:41 UTC (11 h 47 m). Zero failures after
the KneadData fix below. **Nothing here has been pushed to GitHub.**

Repo state at time of writing: `Adeel2208/HostSweep`, branch `main`, commit
`a757834`, working tree clean. Results live outside the repo, so nothing is
staged or at risk.

---

## 1. What is genuinely new (`new/`)

These do not overlap anything already committed in `benchmark/run/`.

| File | Contents | Why it is new |
|---|---|---|
| `per_library_comparators.csv` | 12 synthetic libraries × 3 tools (hostile_default, hostile_matched, kneaddata), n=1 | The repo's `per_library.csv` is **hostsweep only, runs 1–3**. Same row count (36), zero overlap. |
| `e4_real_panel.csv` | 30 real SRA libraries × hostsweep, runtime + peak memory | Only accession *metadata* for these is in the repo. No results. |
| `downstream_new_row.csv` | 1 row: `SRR31641567 / kneaddata` | The only (library, method) key absent from the repo's `downstream.csv`. |

Note on `e4_real_panel.csv`: `sensitivity_pct`, `fpr_pct` and `host_pct` are
empty by design — real libraries have no ground truth. The contribution is
runtime and peak memory on real data.

## 2. What conflicts (`CONFLICTS_repo_vs_this_machine.csv`)

17 (library, method) keys exist in both the repo and this run. **46 cells
disagree.** Do not overwrite the repo's `downstream.csv` without reading this.

Two distinct kinds of disagreement:

### a) `duplication_ratio` is empty in every one of our real-library rows

Populated in the repo (1.002, 1.014, 1.033 …), empty here. This is systematic,
not noise. Overwriting would silently blank published values. Cause not yet
diagnosed — most likely a MetaQUAST invocation difference on this machine.

### b) KneadData rows differ materially; hostsweep and hostile barely move

```
cells differing, by method:   kneaddata 34   hostile 7   hostsweep 5
```

hostsweep/hostile differences are 4th-decimal jitter (18.4978 vs 18.4975;
18389 vs 18388 contigs) — ordinary MEGAHIT thread nondeterminism. KneadData
differences are large:

```
SYN-CHM13-01  largest_contig_kb    repo 955.758   ours 689.219
SYN-CHM13-01  genome_fraction_pct  repo  86.753   ours  86.279
SRR40486826   largest_contig_kb    repo 249.890   ours 175.382
```

This is worth a look on its own terms: **KneadData assemblies reproduce across
machines far less well than HostSweep or Hostile.** That is a result, not just a
bookkeeping problem, and may belong in the paper.

Which set is canonical is a judgement call — not made here.

## 3. This machine, full output (`this-machine-full/`)

Everything this run produced, unfiltered: `downstream.csv` (18 rows),
`kraken2_human.csv` (18), `per_library.csv` (36 comparator rows),
`e4_per_library.csv` (30 real), and `AUDIT.md`.

`AUDIT.md` reports several files as ABSENT (`ablation.csv`, `threshold_sweep.csv`,
`accessions_verified.csv`). **This is not a gap in the project.** The audit was
scoped to this machine's staging directory; all three exist in the repo at
`benchmark/run/`, produced on the reference machine. The verdict reads "all
checks passed on the files that exist", and provenance passed on all 36 rows.

## 4. The KneadData fix — for Methods

KneadData failed on every library with `java.lang.OutOfMemoryError: Java heap
space` from its Trimmomatic step.

- **Cause:** bioconda ships Trimmomatic behind a Python wrapper that hardcodes
  `-Xms512m -Xmx1g`. Too small for these ~2M-pair libraries.
- KneadData's own `--max-memory` does **not** help: it is applied only on the
  `java -jar` code path, and this build invokes the wrapper executable instead.
  (This was my first attempt and it failed identically — worth knowing before
  anyone tries it again.)
- **Fix:** the wrapper drops its hardcoded default whenever `_JAVA_OPTIONS` is
  set. A shim at `envs/kneaddata/bin/kneaddata` exports `_JAVA_OPTIONS=-Xmx8g`
  and execs the real entry point (saved here as `logs/kneaddata_wrapper.sh`).
- It lives in the conda env, not in `benchmark/scripts`, so the scripts'
  `git reset` does not remove it. **A fresh machine will hit this same failure**
  unless the shim is reinstalled or `install_comparators.sh` is patched.

Record as a deviation: comparator tool given an 8 GB JVM heap; HostSweep and
Hostile unaffected.

## 5. Cross-machine check

Passed before the main run: sensitivity 100.0%, FPR 0.0142% on SYN-CHM13-01,
identical to the reference machine. Results from here are combinable.

## 6. Contents

```
new/                                 the three non-overlapping datasets
CONFLICTS_repo_vs_this_machine.csv   46 differing cells, with pct_diff
this-machine-full/                   complete unfiltered output + AUDIT.md
logs/service.log                     full run log
logs/kneaddata_wrapper.sh            the shim, for reinstalling elsewhere
```
