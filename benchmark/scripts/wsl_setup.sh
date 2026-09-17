#!/usr/bin/env bash
# Provision the benchmark toolchain inside WSL2 Ubuntu.
#
# Idempotent and resumable: every step checks for its own output first, so
# re-running after a failure or a reboot picks up where it stopped.
#
# Working tree lives on the WSL native filesystem (~/hostsweep), not /mnt/c --
# the 9p mount is an order of magnitude slower for the read-heavy work here.
# Results are copied back to the Windows checkout at the end of each stage.
#
# Usage:  bash wsl_setup.sh 2>&1 | tee ~/hostsweep/logs/setup.log

set -uo pipefail

ROOT="${HOSTSWEEP_BENCH_ROOT:-$HOME/hostsweep}"
CONDA_DIR="$ROOT/miniforge3"
REPO="$ROOT/HostSweep"
LOGS="$ROOT/logs"
REMOTE="https://github.com/Adeel2208/HostSweep.git"

mkdir -p "$ROOT" "$LOGS"

say() { echo "[setup $(date -u +%H:%M:%S)] $*"; }
fail() { echo "[setup FAILED] $*" >&2; exit 1; }

# --- 1. Miniforge ----------------------------------------------------
if [ -x "$CONDA_DIR/bin/conda" ]; then
    say "miniforge already present: $($CONDA_DIR/bin/conda --version)"
else
    say "downloading miniforge"
    URL="https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh"
    curl -fsSL --retry 3 -o "$ROOT/miniforge.sh" "$URL" \
        || fail "miniforge download"
    say "installing miniforge to $CONDA_DIR"
    bash "$ROOT/miniforge.sh" -b -p "$CONDA_DIR" || fail "miniforge install"
    rm -f "$ROOT/miniforge.sh"
    say "installed: $($CONDA_DIR/bin/conda --version)"
fi

export PATH="$CONDA_DIR/bin:$PATH"
# shellcheck disable=SC1091
source "$CONDA_DIR/etc/profile.d/conda.sh"

# conda-forge and bioconda only. The repo's environment.yml lists `defaults`,
# which is Anaconda's licensed channel; miniforge deliberately omits it and
# including it can block the solve on a ToS prompt in a non-interactive shell.
conda config --system --set channel_priority strict 2>/dev/null || true

# --- 2. Repository ---------------------------------------------------
if [ -d "$REPO/.git" ]; then
    say "repo present, fetching"
    git -C "$REPO" fetch --quiet origin && git -C "$REPO" checkout --quiet main \
        && git -C "$REPO" pull --quiet --ff-only origin main \
        || say "WARNING: could not update repo; continuing with what is on disk"
else
    say "cloning $REMOTE"
    git clone --quiet "$REMOTE" "$REPO" || fail "git clone"
fi
say "repo at $(git -C "$REPO" rev-parse --short HEAD)"

# --- 3. hostsweep environment ----------------------------------------
if conda env list | grep -qE "^hostsweep\s"; then
    say "conda env 'hostsweep' already exists"
else
    say "creating conda env 'hostsweep' (this is the slow step)"
    # Strip the `defaults` channel; see note above.
    sed '/^  - defaults$/d' "$REPO/environment.yml" > "$ROOT/environment.nodefaults.yml"
    conda env create -q -f "$ROOT/environment.nodefaults.yml" || fail "conda env create"
fi

conda activate hostsweep || fail "conda activate hostsweep"

# --- 4. Benchmark-only tools -----------------------------------------
# art (read simulator) and sra-tools are not in environment.yml because they
# are benchmark dependencies, not runtime dependencies of the pipeline.
# pytest likewise -- only needed to run the unit test suite in step 6 below.
NEED=()
command -v art_illumina >/dev/null 2>&1 || NEED+=("art")
command -v seqkit       >/dev/null 2>&1 || NEED+=("seqkit")
python -c "import pytest" >/dev/null 2>&1 || NEED+=("pytest")
if [ ${#NEED[@]} -gt 0 ]; then
    say "installing benchmark tools: ${NEED[*]}"
    conda install -q -y -c conda-forge -c bioconda "${NEED[@]}" \
        || say "WARNING: could not install ${NEED[*]}; recorded as unavailable"
fi

# --- 5. Editable install of HostSweep --------------------------------
# Checking bare `import hostsweep` here is not enough to prove the editable
# install happened: on at least one real run this returned success in a
# freshly created env where `pip install -e .` had never been run, and the
# `hostsweep` CLI script and `hostsweep.database` submodule genuinely were
# not installed -- stage 2 of bootstrap_new_machine.sh then failed with
# `ModuleNotFoundError: No module named 'hostsweep.database'` despite this
# step having printed "hostsweep importable" moments earlier. Root cause not
# pinned down (no conflicting PyPI package by that name exists, so it is not
# a name collision with something else).
#
# Checking the module alone is STILL not enough: on another real run, after
# the fix below for that first problem, `hostsweep.database` was importable
# but the `hostsweep` CLI script (setup.py's console_scripts entry point,
# which every stage from here on invokes directly -- `hostsweep -1 ...`) was
# absent from the env's bin/ -- almost certainly the leftover of a `pip
# install -e .` interrupted partway (the tab running bootstrap was closed
# mid-install on that machine). setup.py's entry_points are correctly
# configured, so this is not a packaging bug; it is an install that did not
# finish. Check for both what the module check would miss and what the
# earlier module-only check missed, and force a real (re-)install if either
# is absent, rather than trusting either signal alone.
install_ok() {
    python -c "from hostsweep.database import DatabaseManager" 2>/dev/null \
        && command -v hostsweep >/dev/null 2>&1
}
if install_ok; then
    say "hostsweep.database importable and hostsweep CLI present -- editable install already in place"
else
    say "pip install -e (module and/or CLI script missing -- see step 5's comment)"
    (cd "$REPO" && pip install -q -e .) || fail "pip install -e"
    install_ok || fail "pip install -e reported success but hostsweep.database and/or the hostsweep CLI script are still missing -- something is wrong with this environment, not just an interrupted install"
fi

# --- 6. Prove the toolchain ------------------------------------------
say "toolchain check"
MISSING=()
for t in fastp minimap2 bowtie2 bowtie2-build samtools bbduk.sh hostsweep art_illumina; do
    if command -v "$t" >/dev/null 2>&1; then
        printf '  %-16s %s\n' "$t" "$(command -v "$t")"
    else
        printf '  %-16s ABSENT\n' "$t"
        MISSING+=("$t")
    fi
done
[ ${#MISSING[@]} -eq 0 ] || say "WARNING: missing ${MISSING[*]}"

say "running the unit test suite"
(cd "$REPO" && python -m pytest tests/ -v -rs) 2>&1 | tail -25

say "DONE. conda: $CONDA_DIR   repo: $REPO"
