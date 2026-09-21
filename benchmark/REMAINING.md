# Running the remaining experiments (R1–R5)

One command, on a Linux machine (WSL2 Ubuntu is fine) that already has the
benchmark toolchain from `NEW_MACHINE.md`:

```bash
cd ~/hostsweep/HostSweep
git -c http.version=HTTP/1.1 pull origin main
bash benchmark/scripts/run_remaining.sh
```

Before committing days to a machine, check what it can do:
`bash benchmark/scripts/check_machine.sh` (about 4 minutes).

Run it inside `nohup` or `tmux` so closing the window does not stop it:

```bash
nohup bash benchmark/scripts/run_remaining.sh > ~/hostsweep/logs/remaining.out 2>&1 & disown
tail -f ~/hostsweep/logs/remaining.out
```

Safe to interrupt and re-run: finished work is skipped and a stage is marked
done only after its own completeness checks pass.

## What runs, in order

| | Stage | What it does | Closes |
|---|---|---|---|
| R1 | Clean timing run | 5 tools × 12 libraries × 3 replicates = 180 runs, one fixed thread count, every run under `/usr/bin/time -v`, swap counters recorded, Hostile's index proven beforehand. **Nothing else runs beside it.** | D17, D18, D21 |
| — | Downloads | The ~72 GB Kraken2 Standard database and the 1.7 GB CheckM2 database start in the background once R1 is finished | |
| R2 | metaSPAdes | 3 methods × 6 libraries × 2 replicates, then MetaQUAST | D4 |
| R3 | CheckM2 | on the metaSPAdes assemblies, contigs ≥ 1 kb | D6 |
| R4 | Kraken2 full Standard | the same 18 read sets as the Standard-8 table | D5 |
| R5 | Extra donors | Kinh, Mende, Colombian assemblies → six mismatch libraries → all five tools scored (timed, runs alone) | Editor 8 |

At the end it builds a small results bundle (`~/hostsweep/results_bundle_*.tar.gz`)
and prints its path; copy that back to be merged.

## Options

```bash
bash benchmark/scripts/run_remaining.sh --dry-run          # show the plan and what each stage needs
bash benchmark/scripts/run_remaining.sh --only R1          # just the timing run
bash benchmark/scripts/run_remaining.sh --skip R4,R5       # everything except these
```

| Variable | Default | Meaning |
|---|---|---|
| `THREADS` | 8 | threads per run in the **timed** stages (R1, R5). Keep it identical across tools. |
| `ASM_THREADS` | min(nproc, 32) | threads for R2, R3, R4 |
| `SKIP_HOSTILE_DEFAULT=1` | off | leave `hostile_default` out (its earlier-session results then stand, D21) |
| `HOSTILE_INDEX_TAR=/path` | | a local copy of Hostile's `human-t2t-hla.tar` (3.9 GB) |
| `R5_FRACTIONS` | `"0.10 0.20"` | host fractions per donor; `"0.01 0.10 0.20"` builds nine libraries |
| `SPADES_MEM` | min(120, available − 6) GB | memory limit given to metaSPAdes; if below 120, say so in the Methods |

## Needs

* **R1** — 12 synthetic libraries, the BMTagger index, and Hostile's default
  index. If Hostile's index cannot be downloaded the stage stops with two ways
  out (a local tar, or `SKIP_HOSTILE_DEFAULT=1`) rather than recording 36 failures.
* **R2** — about 120 GB of RAM for the gut library. `check_machine.sh` says
  whether the machine has it.
* **R4** — about 190 GB of free disk during the download and unpacking.
* **R5** — three ~0.9 GB assemblies from NCBI (pinned to version `.1`).

## Things to know

* **Swap.** If swap is on, R1 still runs; `r1/swap_check.txt` states whether any
  run touched it. To remove the question, turn swap off first (WSL: `swap=0` in
  `.wslconfig`, then `wsl --shutdown`).
* **R4's input.** The specification said "profiling-tier output". The existing
  Standard-8 table classified the paired assembly-tier reads for all three
  methods, so R4 does the same, to make the Standard-8 / Standard pair a
  like-for-like comparison.
* **R2 replicates** are separate `metaspades.py` invocations, not copies.
* **Nothing is estimated.** A failed run is recorded as `FAILED` with its error,
  never filled in.

## Outputs (under `~/hostsweep/out`)

```
r1/    per_library.csv  synthetic_manifest.csv  run_details.csv  timing_summary.csv  swap_check.txt  machine.txt
r2/    downstream_metaspades.csv  downstream_metaspades_replicates.csv  inputs_sha256.txt
r3/    checkm2_metaspades.csv
r4/    kraken2_human_standard.csv  (+ one k2.report per classification)
r5/    per_library.csv  synthetic_manifest.csv  run_details.csv  timing_summary.csv  r5_panel.tsv
```
