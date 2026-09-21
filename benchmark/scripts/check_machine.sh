#!/usr/bin/env bash
# Measure what this machine can actually do, before committing days of runs to it.
#
# Everything reported is measured here and now: CPU count and a scaling test,
# RAM (including a real allocation test), swap, disk space and write speed,
# and download speed to every host the remaining experiments need. Nothing is
# assumed from the machine's spec sheet.
#
# It ends with a PASS / WARN / FAIL line for each of R1-R5:
#   R1  clean timing run      5 tools x 12 libraries x 3 runs, swap-free
#   R2  metaSPAdes            18 assemblies (up to ~120 GB RAM for the gut library)
#   R3  CheckM2               ~1.7 GB database download, then 18 assemblies
#   R4  Kraken2 Standard      ~72 GB archive download, database in RAM
#   R5  extra mismatch donors HPRC assemblies from NCBI, ART simulation
#
# Read-only apart from one temporary 4 GB test file (deleted at the end) and
# a report written to ~/hostsweep/machine_report_<timestamp>.txt.
# Takes about 4 minutes. It touches no results and no running job.
#
# Usage:  bash benchmark/scripts/check_machine.sh
#         QUICK=1 bash benchmark/scripts/check_machine.sh   # skip RAM/disk/multi-stream tests (~1.5 min)

set -uo pipefail

WORK="$HOME/hostsweep"
mkdir -p "$WORK"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
REPORT="$WORK/machine_report_${STAMP}.txt"
QUICK="${QUICK:-0}"
exec > >(tee "$REPORT") 2>&1

hr()  { printf '\n==== %s ====\n' "$*"; }
say() { printf '%s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

VERDICTS=()
verdict() {   # verdict <R-id> <PASS|WARN|FAIL> <message>
    VERDICTS+=("[$2] $1: $3")
}

say "HostSweep machine check  $STAMP"
say "report will be saved to: $REPORT"

# ------------------------------------------------------------------ platform
hr "1. Platform"
say "kernel      : $(uname -sr)"
say "os          : $(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME")"
IS_WSL=0
grep -qi microsoft /proc/version 2>/dev/null && IS_WSL=1
say "wsl         : $([ "$IS_WSL" = 1 ] && echo yes || echo no)"
[ "$(uname -s)" = Linux ] || say "WARNING: not Linux. The benchmark scripts need Linux (flock, /usr/bin/time)."
have flock          && say "flock       : ok" || say "flock       : MISSING"
[ -x /usr/bin/time ] && say "/usr/bin/time: ok" || say "/usr/bin/time: MISSING (needed for peak-memory records)"
have aria2c         && say "aria2c      : ok" || say "aria2c      : missing (needed for fast downloads; wsl_setup.sh installs it)"
have python3        && say "python3     : $(python3 --version 2>&1)" || say "python3     : MISSING"

# ---------------------------------------------------------------------- CPU
hr "2. CPU"
NPROC="$(nproc 2>/dev/null || echo 1)"
if have lscpu; then
    lscpu | grep -E "Model name|^CPU\(s\)|Thread|Core|Socket|MHz|L3 cache" | sed 's/  */ /g'
fi
say "usable logical CPUs (nproc): $NPROC"

if have python3; then
    say ""
    say "compute scaling test (SHA-256 throughput, 3 s per run):"
    CPU_OUT="$(python3 - "$NPROC" <<'PY'
import hashlib, multiprocessing as mp, sys, time
def work(_):
    buf = b"\x5a" * (32 << 20)
    t0 = time.perf_counter(); n = 0
    while time.perf_counter() - t0 < 3.0:
        hashlib.sha256(buf).digest(); n += 1
    return n * 32 / (time.perf_counter() - t0)      # MB/s
n = min(int(sys.argv[1]), 128)
single = work(0)
with mp.Pool(n) as p:
    total = sum(p.map(work, range(n)))
print(f"{single:.0f} {total:.0f} {n}")
PY
)"
    read -r SINGLE TOTAL NW <<< "$CPU_OUT"
    EFF="$(awk -v s="$SINGLE" -v t="$TOTAL" -v n="$NW" 'BEGIN{printf "%.0f", 100*t/(s*n)}')"
    say "  1 process        : ${SINGLE} MB/s"
    say "  ${NW} processes     : ${TOTAL} MB/s total"
    say "  parallel efficiency: ${EFF} %  (100 % = every logical CPU as fast as a lone one;"
    say "                         hyper-threads and shared power budgets lower this, ~40-70 % is normal)"
else
    EFF=0; SINGLE=0
fi

# ------------------------------------------------------------------- memory
hr "3. Memory and swap"
MEM_KB="$(awk '/MemTotal/ {print $2}' /proc/meminfo)"
AVAIL_KB="$(awk '/MemAvailable/ {print $2}' /proc/meminfo)"
SWAP_KB="$(awk '/SwapTotal/ {print $2}' /proc/meminfo)"
MEM_GB=$(( MEM_KB / 1048576 )); AVAIL_GB=$(( AVAIL_KB / 1048576 )); SWAP_GB=$(( SWAP_KB / 1048576 ))
say "RAM total      : ${MEM_GB} GB"
say "RAM available  : ${AVAIL_GB} GB"
say "swap total     : ${SWAP_GB} GB   (R1 needs zero swap-in during runs)"
[ "$IS_WSL" = 1 ] && say "(inside WSL these are the limits set in C:\\Users\\<you>\\.wslconfig, not the physical machine)"

if [ "$QUICK" != 1 ] && have python3; then
    say ""
    say "real allocation test (fills RAM with data and times it):"
    python3 - "$AVAIL_KB" <<'PY'
import sys, time
avail_gb = int(sys.argv[1]) / 1048576
target = int(min(avail_gb * 0.75, 100))
def swap_used():
    d = {l.split(':')[0]: int(l.split()[1]) for l in open('/proc/meminfo')}
    return (d['SwapTotal'] - d['SwapFree']) / 1048576
s0 = swap_used()
blocks = []; t0 = time.perf_counter()
for i in range(target):
    blocks.append(b"\x01" * (1 << 30))
dt = time.perf_counter() - t0
print(f"  allocated and filled {target} GB in {dt:.1f} s  ({target/dt:.1f} GB/s)")
print(f"  swap used by the test: {swap_used()-s0:.2f} GB  (should be 0.00)")
PY
fi

# --------------------------------------------------------------------- disk
hr "4. Disk"
say "work directory : $WORK"
df -hT "$WORK" | sed 's/^/  /'
FREE_GB="$(df -Pk "$WORK" | awk 'NR==2 {print int($4/1048576)}')"
FSTYPE="$(df -PT "$WORK" | awk 'NR==2 {print $2}')"
say "free space     : ${FREE_GB} GB"
case "$WORK" in /mnt/*) say "WARNING: the work directory is on a Windows drive (/mnt/...). It will be much slower than the Linux filesystem." ;; esac

WSPEED=0
if [ "$QUICK" != 1 ]; then
    if [ "$FREE_GB" -gt 20 ]; then
        say ""
        say "write test (4 GB, flushed to disk):"
        WOUT="$(dd if=/dev/zero of="$WORK/.disktest" bs=1M count=4096 conv=fdatasync 2>&1 | tail -1)"
        say "  $WOUT"
        WSPEED="$(echo "$WOUT" | awk '{for(i=1;i<=NF;i++) if($i ~ /^(MB|GB)\/s$/) {v=$(i-1); if($i=="GB/s") v*=1000; print int(v)}}')"
        WSPEED="${WSPEED:-0}"
        ROUT="$(dd if="$WORK/.disktest" of=/dev/null bs=1M 2>&1 | tail -1)"
        say "  read (may be served from cache): $ROUT"
        rm -f "$WORK/.disktest"
    else
        say "  skipped: not enough free space for a 4 GB test file"
    fi
fi

# ------------------------------------------------------------------ network
hr "5. Network: download speed to every host the experiments use"
say "(each test downloads for a few seconds and throws the data away)"

# <label> <url> <size in bytes, 0 = unknown>
ENDPOINTS=(
"Kraken2 Standard (S3)|https://genome-idx.s3.amazonaws.com/kraken/k2_standard_20250402.tar.gz|71785839271"
"Hostile T2T+HLA index|https://objectstorage.uk-london-1.oraclecloud.com/n/lrbvkel2wjot/b/human-genome-bucket/o/human-t2t-hla.tar|3934284979"
"CheckM2 database (Zenodo)|https://zenodo.org/api/records/14897628/files/checkm2_database.tar.gz/content|1735095710"
"NCBI genomes (T2T-CHM13)|https://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/009/914/755/GCF_009914755.1_T2T-CHM13v2.0/GCF_009914755.1_T2T-CHM13v2.0_genomic.fna.gz|932691275"
"conda-forge|https://conda.anaconda.org/conda-forge/linux-64/current_repodata.json|0"
"GitHub|https://github.com/Adeel2208/HostSweep|0"
)

declare -A SPEED1 SPEEDN CODE SIZE
for e in "${ENDPOINTS[@]}"; do
    IFS='|' read -r LABEL URL SZ <<< "$e"
    SIZE["$LABEL"]="$SZ"
    OUT="$(curl -sL -r 0- --max-time 10 -o /dev/null -w '%{http_code} %{speed_download}' "$URL" 2>/dev/null || true)"
    CODE["$LABEL"]="$(echo "$OUT" | awk '{print $1}')"
    SPEED1["$LABEL"]="$(echo "$OUT" | awk '{printf "%.0f", $2/1024}')"      # KiB/s
    printf '  %-28s HTTP %-4s %8s KiB/s (1 stream)\n' "$LABEL" "${CODE[$LABEL]:-000}" "${SPEED1[$LABEL]:-0}"
done

if [ "$QUICK" != 1 ]; then
    say ""
    say "parallel streams (does the host give more speed for more connections?):"
    for e in "${ENDPOINTS[@]}"; do
        IFS='|' read -r LABEL URL SZ <<< "$e"
        [ "$SZ" -gt 1000000000 ] || continue
        N=8; STEP=$(( SZ / (N + 1) ))
        T="$(mktemp -d)"
        for i in $(seq 0 $((N-1))); do
            ( curl -sL -r "$((i*STEP))-" --max-time 8 -o /dev/null -w '%{speed_download}\n' "$URL" > "$T/$i" 2>/dev/null || true ) &
        done
        wait
        TOT="$(cat "$T"/* 2>/dev/null | awk '{s+=$1} END{printf "%.0f", s/1024}')"
        rm -rf "$T"
        SPEEDN["$LABEL"]="${TOT:-0}"
        printf '  %-28s %8s KiB/s total over %d streams  (x%s vs 1 stream)\n' "$LABEL" "$TOT" "$N" \
            "$(awk -v a="$TOT" -v b="${SPEED1[$LABEL]:-0}" 'BEGIN{ if (b>0) printf "%.1f", a/b; else print "n/a"}')"
    done
fi

eta_hours() {   # eta_hours <bytes> <KiB/s>
    awk -v b="$1" -v k="$2" 'BEGIN{ if (k<=0) print 99999; else printf "%.1f", b/(k*1024)/3600 }'
}

# -------------------------------------------------------------------- state
hr "6. What is already installed / built here"
CONDA_SH="$WORK/miniforge3/etc/profile.d/conda.sh"
if [ -f "$CONDA_SH" ]; then
    # shellcheck disable=SC1090
    . "$CONDA_SH"
    ENVS="$(conda env list 2>/dev/null | awk 'NR>2 && $1 !~ /^#/ {print $1}' | tr '\n' ' ')"
    say "conda envs: $ENVS"
    for e in hostsweep hostile kneaddata bmtagger megahit kraken2 checkm2 spades; do
        echo " $ENVS " | grep -q " $e " && say "  [x] $e" || say "  [ ] $e"
    done
else
    say "conda not installed under $WORK/miniforge3 yet (bootstrap_new_machine.sh installs it)"
    ENVS=""
fi
NSYN="$(ls "$WORK"/bench/synthetic/*_R1.fastq.gz 2>/dev/null | wc -l)"
say "synthetic libraries present: $NSYN  (12 needed for R1)"
HOSTILE_IDX="$(find "$HOME/.local/share/hostile" -name '*.tar' -o -name '*.bt2' 2>/dev/null | head -1)"
say "Hostile index present locally: $([ -n "$HOSTILE_IDX" ] && echo "yes ($HOSTILE_IDX)" || echo no)"
say "repo checkout: $(cd "$(dirname "$0")/../.." 2>/dev/null && git log --oneline -1 2>/dev/null || echo unknown)"

# ----------------------------------------------------------------- verdicts
hr "7. Verdict per experiment"

# R1 -------------------------------------------------------------------
R1=PASS; R1M=""
[ "$NPROC" -ge 8 ] || { R1=FAIL; R1M="$R1M only $NPROC CPUs;"; }
[ "$MEM_GB" -ge 32 ] || { R1=FAIL; R1M="$R1M RAM ${MEM_GB} GB < 32;"; }
[ "$FREE_GB" -ge 150 ] || { [ "$R1" = PASS ] && R1=WARN; R1M="$R1M free disk ${FREE_GB} GB < 150;"; }
if [ "$SWAP_GB" -gt 0 ]; then [ "$R1" = PASS ] && R1=WARN; R1M="$R1M swap is ON (${SWAP_GB} GB) -- turn it off or R1 must prove zero swap-in from the .time files;"; fi
[ "$NSYN" -ge 12 ] || { [ "$R1" = PASS ] && R1=WARN; R1M="$R1M synthetic panel not built here yet ($NSYN/12);"; }
if [ -z "$HOSTILE_IDX" ]; then
    H="$(eta_hours 3934284979 "${SPEED1[Hostile T2T+HLA index]:-0}")"
    if awk -v h="$H" 'BEGIN{exit !(h>6)}'; then
        [ "$R1" = PASS ] && R1=WARN
        R1M="$R1M Hostile index download ETA ${H} h ($(( ${SPEED1[Hostile T2T+HLA index]:-0} )) KiB/s) -- copy it in from another machine instead;"
    fi
fi
[ "${EFF:-0}" -ge 25 ] 2>/dev/null || { [ "$R1" = PASS ] && R1=WARN; R1M="$R1M poor CPU scaling (${EFF}%);"; }
verdict R1 "$R1" "${R1M:-ready: ${NPROC} CPUs, ${MEM_GB} GB RAM, no swap, ${FREE_GB} GB free}"

# R2 -------------------------------------------------------------------
R2=PASS; R2M=""
if   [ "$AVAIL_GB" -lt 64 ];  then R2=FAIL; R2M="$R2M only ${AVAIL_GB} GB RAM available; metaSPAdes needs 30-120 GB;"
elif [ "$AVAIL_GB" -lt 120 ]; then R2=WARN; R2M="$R2M ${AVAIL_GB} GB RAM available; the gut library (SRR40486826) may exceed it -- metaSPAdes is asked for -m 120;"
fi
[ "$NPROC" -ge 16 ] || { [ "$R2" = PASS ] && R2=WARN; R2M="$R2M only $NPROC CPUs (assemblies will be slow);"; }
[ "$FREE_GB" -ge 300 ] || { [ "$R2" = PASS ] && R2=WARN; R2M="$R2M free disk ${FREE_GB} GB < 300 (metaSPAdes temp files are large);"; }
verdict R2 "$R2" "${R2M:-${AVAIL_GB} GB RAM available, ${NPROC} CPUs, ${FREE_GB} GB free}"

# R3 -------------------------------------------------------------------
R3=PASS; R3M=""
[ "$AVAIL_GB" -ge 32 ] || { R3=FAIL; R3M="$R3M RAM ${AVAIL_GB} GB < 32;"; }
Z="$(eta_hours 1735095710 "${SPEEDN[CheckM2 database (Zenodo)]:-${SPEED1[CheckM2 database (Zenodo)]:-0}}")"
awk -v h="$Z" 'BEGIN{exit !(h>6)}' && { [ "$R3" = PASS ] && R3=WARN; R3M="$R3M database download ETA ${Z} h;"; }
[ "$FREE_GB" -ge 20 ] || { R3=FAIL; R3M="$R3M free disk ${FREE_GB} GB < 20;"; }
verdict R3 "$R3" "${R3M:-database download ETA ${Z} h, ${AVAIL_GB} GB RAM}"

# R4 -------------------------------------------------------------------
R4=PASS; R4M=""
K="$(eta_hours 71785839271 "${SPEEDN[Kraken2 Standard (S3)]:-${SPEED1[Kraken2 Standard (S3)]:-0}}")"
if   awk -v h="$K" 'BEGIN{exit !(h>96)}'; then R4=FAIL; R4M="$R4M 72 GB download ETA ${K} h;"
elif awk -v h="$K" 'BEGIN{exit !(h>24)}'; then R4=WARN; R4M="$R4M 72 GB download ETA ${K} h;"
fi
[ "$FREE_GB" -ge 200 ] || { R4=FAIL; R4M="$R4M free disk ${FREE_GB} GB < 200 (72 GB archive + extracted database);"; }
[ "$MEM_GB" -ge 100 ] || { [ "$R4" = PASS ] && R4=WARN; R4M="$R4M RAM ${MEM_GB} GB < 100 (the Standard database is ~75+ GB; needs --memory-mapping otherwise);"; }
verdict R4 "$R4" "${R4M:-download ETA ${K} h, ${MEM_GB} GB RAM, ${FREE_GB} GB free}"

# R5 -------------------------------------------------------------------
R5=PASS; R5M=""
N5="$(eta_hours 3000000000 "${SPEED1[NCBI genomes (T2T-CHM13)]:-0}")"
awk -v h="$N5" 'BEGIN{exit !(h>6)}' && { R5=WARN; R5M="$R5M NCBI download ETA ~${N5} h for three donor assemblies;"; }
[ "$FREE_GB" -ge 100 ] || { R5=FAIL; R5M="$R5M free disk ${FREE_GB} GB < 100;"; }
[ "${CODE[NCBI genomes (T2T-CHM13)]:-000}" = 200 ] || { R5=FAIL; R5M="$R5M NCBI not reachable;"; }
verdict R5 "$R5" "${R5M:-NCBI reachable, ETA ~${N5} h for three assemblies, ${FREE_GB} GB free}"

for v in "${VERDICTS[@]}"; do say "$v"; done

say ""
say "Reading the verdicts: PASS = go. WARN = will probably run, read the note first."
say "FAIL = do not start it on this machine as configured."
say ""
say "Please send the whole output above (or the file $REPORT)."
