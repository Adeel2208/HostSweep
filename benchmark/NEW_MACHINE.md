# Moving the benchmark to a new machine

This covers taking the HostSweep benchmark from the machine it was started on
to a second, more capable machine (32 GB RAM), to finish the experiments that
did not fit in 11 GB. If you already have WSL2 Ubuntu set up with plenty of
memory available to it, skip to **Part 2**.

Everything after Part 1 happens inside one Ubuntu shell, driven by one script:
[`benchmark/scripts/bootstrap_new_machine.sh`](scripts/bootstrap_new_machine.sh).
It downloads its own dependencies, verifies this machine measures the same
result as the old one before producing anything new, and resumes cleanly if
interrupted — you do not need to know which stage it is on to re-run it.

---

## Part 1 — Windows-side setup (one time, ~10 minutes)

Skip any step whose result you already have.

**1. Enable WSL2 and install Ubuntu.** In PowerShell **as Administrator**:

```powershell
wsl --install -d Ubuntu
```

This installs the WSL2 feature and Ubuntu, and may ask for a reboot. After
reboot, Ubuntu launches once and asks you to create a Linux username and
password — pick anything, you won't need it again after this.

If `wsl --install` says WSL is already present, just run `wsl --install -d Ubuntu`
to add the Ubuntu distro, or `wsl -l -v` to see what's already there.

**2. Give WSL most of the machine's RAM.** By default WSL2 caps itself at half
the host's RAM, which is too tight for this benchmark. Create (or edit)
`C:\Users\<you>\.wslconfig` in a plain text editor with:

```ini
[wsl2]
memory=26GB
processors=12
swap=8GB
```

(For a 32 GB machine. If the machine has a different amount of RAM, set
`memory` to roughly RAM minus 6 GB, and `processors` to the CPU's thread
count.)

Then, in PowerShell:

```powershell
wsl --shutdown
```

**3. Keep the laptop from sleeping or throttling mid-run.** Some stages run
for hours unattended. Plug it in, set the power plan to Best Performance, and
turn off sleep (Settings → System → Power). This matters for runtime numbers
in particular — see D17 in `benchmark/run/DEVIATIONS.md`.

**4. Open an Ubuntu shell** — type `Ubuntu` in the Start menu, or run
`wsl -d Ubuntu` from PowerShell — and move to Part 2.

---

## Part 2 — everything else (inside the Ubuntu shell)

**1. Get the code.** The repo lives on the Linux filesystem
(`~/hostsweep/HostSweep`), not under `/mnt/c/...` — the Windows filesystem
mount is an order of magnitude slower for the read-heavy work here.

```bash
mkdir -p ~/hostsweep
git clone https://github.com/Adeel2208/HostSweep.git ~/hostsweep/HostSweep
```

If you already have this checkout from a previous attempt, just update it:

```bash
git -C ~/hostsweep/HostSweep pull --ff-only origin main
```

**2. Run the bootstrap script.** This is the one command that does everything
else: installs the conda toolchain, builds and verifies the reference index,
installs every comparator tool, fetches the Kraken2 database, rebuilds the
synthetic panel, checks this machine reproduces the first machine's numbers,
downloads the real-library panel, and runs every experiment still marked
incomplete in `benchmark/run/RESULTS.md`.

```bash
bash ~/hostsweep/HostSweep/benchmark/scripts/bootstrap_new_machine.sh
```

It logs everything to `~/hostsweep/logs/bootstrap_<timestamp>.log` as well as
the screen. Expect this to run for many hours — most of that is genuine
compute (the Kraken2 database alone is an 8 GB download, and 30 real
libraries plus a 12-library comparator sweep is a lot of alignment). It is
safe to close the terminal and come back; WSL processes keep running as long
as Windows itself isn't put to sleep. If it does stop, running the exact same
command again resumes from wherever it got to — nothing is recomputed.

**3. The one gate that can stop it early: the cross-machine check (stage 7).**
Partway through, the script rebuilds one synthetic library on this machine
and compares its sensitivity and false-positive rate, bit for bit, against
the values already recorded in `benchmark/run/per_library.csv` from the first
machine. HostSweep's output is deterministic given the same inputs and tool
versions (proven on the first machine: 12/12 libraries bit-identical across 3
repeat runs), so a mismatch here means this machine's environment differs in
a way that would silently invalidate every number after it — a different
minimap2/bowtie2/fastp build, for instance. If you see `CROSSCHECK: MISMATCH`,
**stop** — do not let later stages run, do not merge any of this machine's
results into the existing CSVs, and check `environment.yml`'s pinned versions
against what actually got installed (`conda list -n hostsweep`).

**4. When it finishes.** New and updated results land in `~/hostsweep/out/`
as CSV files, outside the git checkout by design (every stage force-syncs the
checkout to `origin/main` before running, so a results file tracked in git
inside the checkout would get silently overwritten by whatever was last
pushed). Copy the ones you want to keep into the checkout and commit:

```bash
cp ~/hostsweep/out/*.csv ~/hostsweep/HostSweep/benchmark/run/
cd ~/hostsweep/HostSweep
git add benchmark/run/*.csv
git commit -m "Results from the second machine: comparator benchmark, E9, remaining E4 libraries"
git push origin main
```

Then regenerate `benchmark/run/RESULTS.md`'s status table and numbers from
the new CSVs (by hand, or ask Claude Code to do it against the CSVs it now
has) — do not hand-edit numbers into it without a CSV backing them, per the
ground rule this whole benchmark has followed throughout.

Useful commands once bootstrap is running or has finished:

| Command | What it shows |
|---|---|
| `bash ~/hostsweep/HostSweep/benchmark/scripts/status.sh` | one-line-per-fact status: what's built, what's running, disk/memory |
| `cat ~/hostsweep/out/AUDIT.md` | self-audit of the results produced so far |
| `bash ~/hostsweep/HostSweep/benchmark/scripts/stop_all.sh` | gracefully stop everything if you need the machine back |
| `bash ~/hostsweep/HostSweep/benchmark/scripts/package_results.sh ~/hostsweep/HostSweep` | zip a results bundle (refuses if the audit fails) |

---

## What does NOT need to be copied from the old machine

Nothing. `bootstrap_new_machine.sh` rebuilds every input from scratch on the
new machine — the reference index, the synthetic panel (same ART seeds,
so bit-identical to the first machine, which stage 7 checks), and the real
libraries (re-downloaded from SRA by accession). The only things that
travel between machines are the git repository and, at the end, the new
result CSVs going the other direction.
