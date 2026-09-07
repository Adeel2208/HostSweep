#!/usr/bin/env python3
"""E1: verify the real-library SRA panel against NCBI, and find replacements.

Two modes.

**verify** (default) reads `benchmark/accessions.csv`, pulls each Run's real
metadata from the SRA Entrez `runinfo` report, applies the inclusion criteria,
and writes `accessions_verified.csv` plus `verification_log.txt`. Exits 0 only
when every row PASSes.

**search** queries SRA for candidate replacements in a named sample category
and prints the runs that satisfy the criteria, with their real metadata. It
never invents an accession: every candidate printed came back from a query.

Inclusion criteria:
    platform         Illumina
    layout           PAIRED
    strategy         WGS
    source           METAGENOMIC
    spots            >= 1,000,000
    organism         must not be a non-human host (pig, goat, cow ...)

Usage:
    python 01_verify_accessions.py verify [--csv benchmark/accessions.csv]
    python 01_verify_accessions.py search --query '"human urogenital metagenome"[Organism]'
    python 01_verify_accessions.py search --category urogenital
"""
import argparse
import csv
import io
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

EUTILS = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils"
MIN_SPOTS = 1_000_000

# Category shorthands for the three replacements the panel needs.
CATEGORY_QUERIES = {
    "urogenital": '"human urogenital metagenome"[Organism]',
    "respiratory": '"human respiratory tract metagenome"[Organism]',
    "blood": '"human blood metagenome"[Organism]',
    "gut": '"human gut metagenome"[Organism]',
    "skin": '"human skin metagenome"[Organism]',
    "oral": '"human oral metagenome"[Organism]',
}
CRITERIA_SUFFIX = ('AND "illumina"[Platform] AND "paired"[Layout] '
                   'AND "wgs"[Strategy] AND "metagenomic"[Source]')

# Organisms that disqualify a run outright: the panel is human metagenomes.
NON_HUMAN_MARKERS = ("sus scrofa", "pig", "capra", "goat", "bos taurus", "cow",
                     "mus musculus", "mouse", "gallus", "chicken", "ovis", "sheep")


def http_get(url, retries=4):
    last = None
    for attempt in range(retries):
        try:
            req = urllib.request.Request(
                url, headers={"User-Agent": "HostSweep-benchmark/1.0"})
            with urllib.request.urlopen(req, timeout=120) as r:
                return r.read().decode("utf-8", errors="replace")
        except Exception as exc:                     # noqa: BLE001 - retried
            last = exc
            time.sleep(2 * (attempt + 1))
    raise SystemExit("network error: %s (%r)" % (url[:120], last))


# NCBI's efetch runinfo currently returns the data rows with no header line.
# The column order is the documented runinfo order; it was verified field by
# field against a live SRR6062009 response before being relied on here.
RUNINFO_HEADER = (
    "Run,ReleaseDate,LoadDate,spots,bases,spots_with_mates,avgLength,size_MB,"
    "AssemblyName,download_path,Experiment,LibraryName,LibraryStrategy,"
    "LibrarySelection,LibrarySource,LibraryLayout,InsertSize,InsertDev,"
    "Platform,Model,SRAStudy,BioProject,Study_Pubmed_id,ProjectID,Sample,"
    "BioSample,SampleType,TaxID,ScientificName,SampleName,g1k_pop_code,source,"
    "g1k_analysis_group,Subject_ID,Sex,Disease,Tumor,Affection_Status,"
    "Analyte_Type,Histological_Type,Body_Site,CenterName,Submission,"
    "dbgap_study_accession,Consent,RunHash,ReadHash")


def parse_runinfo(text):
    """Parse a runinfo CSV that may or may not carry its header line."""
    lines = [ln for ln in text.splitlines() if ln.strip()]
    if not lines:
        return []
    if not lines[0].startswith("Run,"):
        lines.insert(0, RUNINFO_HEADER)
    rows = list(csv.DictReader(io.StringIO("\n".join(lines))))
    return [r for r in rows if r.get("Run")]


def runinfo(accessions):
    """Fetch the SRA runinfo CSV for a list of Run accessions."""
    if not accessions:
        return []
    url = "%s/efetch.fcgi?db=sra&id=%s&rettype=runinfo&retmode=csv" % (
        EUTILS, ",".join(accessions))
    return parse_runinfo(http_get(url))


def esearch(term, retmax=60):
    url = "%s/esearch.fcgi?db=sra&retmax=%d&term=%s" % (
        EUTILS, retmax, urllib.parse.quote(term))
    text = http_get(url)
    ids = []
    for chunk in text.split("<Id>")[1:]:
        ids.append(chunk.split("</Id>")[0].strip())
    return ids


def runinfo_for_ids(uids):
    if not uids:
        return []
    url = "%s/efetch.fcgi?db=sra&id=%s&rettype=runinfo&retmode=csv" % (
        EUTILS, ",".join(uids))
    return parse_runinfo(http_get(url))


def evaluate(row):
    """Return (verdict, [reasons]) for one runinfo row."""
    reasons = []
    platform = (row.get("Platform") or "").strip()
    layout = (row.get("LibraryLayout") or "").strip().upper()
    strategy = (row.get("LibraryStrategy") or "").strip().upper()
    source = (row.get("LibrarySource") or "").strip().upper()
    organism = (row.get("ScientificName") or "").strip()
    try:
        spots = int(row.get("spots") or 0)
    except ValueError:
        spots = 0

    if platform.upper() != "ILLUMINA":
        reasons.append("platform is %r, not Illumina" % platform)
    if layout != "PAIRED":
        reasons.append("layout is %r, not PAIRED" % layout)
    if strategy != "WGS":
        reasons.append("strategy is %r, not WGS" % strategy)
    if source != "METAGENOMIC":
        reasons.append("source is %r, not METAGENOMIC" % source)
    if spots < MIN_SPOTS:
        reasons.append("%s spots, below the %s minimum" % (f"{spots:,}", f"{MIN_SPOTS:,}"))
    low = organism.lower()
    for marker in NON_HUMAN_MARKERS:
        if marker in low:
            reasons.append("organism %r is a non-human host" % organism)
            break
    return ("PASS" if not reasons else "FAIL"), reasons


def to_record(row, verdict, reasons):
    return {
        "run": row.get("Run", ""),
        "verdict": verdict,
        # ENA runs often return an empty BioProject while carrying the
        # study in SRAStudy; an empty field would read as a distinct
        # project and inflate per-category study counts.
        "bioproject": (row.get("BioProject") or "").strip()
                      or (row.get("SRAStudy") or "").strip(),
        "biosample": row.get("BioSample", ""),
        "organism": row.get("ScientificName", ""),
        "library_strategy": row.get("LibraryStrategy", ""),
        "library_source": row.get("LibrarySource", ""),
        "layout": row.get("LibraryLayout", ""),
        "platform": row.get("Platform", ""),
        "instrument": row.get("Model", ""),
        "spots": row.get("spots", ""),
        "bases": row.get("bases", ""),
        "notes": "; ".join(reasons),
    }


def read_panel(csv_path):
    """Read the Run accessions from accessions.csv, ignoring comments."""
    runs = []
    with open(csv_path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            first = next(csv.reader([line]))[0].strip()
            if first.lower() == "run":
                continue
            if first:
                runs.append(first)
    return runs


def _panel_metadata(csv_path):
    """Map run -> its row in accessions.csv, for category and notes."""
    out = {}
    try:
        with open(csv_path, encoding="utf-8") as fh:
            body = [ln for ln in fh if not ln.lstrip().startswith("#")]
        for row in csv.DictReader(body):
            if row.get("run"):
                out[row["run"]] = row
    except (OSError, csv.Error):
        pass
    return out


def _shortfall_evidence(queries_log):
    """Extract the queries and UID counts behind each shortfall.

    The panel builder logs every query it ran, including the ones that returned
    nothing. Reproducing those lines here means verification_log.txt carries
    its own evidence: a reader can re-run the exact query string and see the
    same counts, rather than taking a shortfall claim on trust.
    """
    lines = ["", "=" * 70,
             "SHORTFALL AND CONFOUND EVIDENCE",
             "(verbatim from the panel construction log: %s)" % queries_log,
             "=" * 70]
    try:
        with open(queries_log, encoding="utf-8") as fh:
            text = fh.read().splitlines()
    except OSError:
        lines.append("  panel query log not found; no evidence to reproduce.")
        return lines

    current, keep = None, {}
    for ln in text:
        if ln.startswith("CATEGORY "):
            current = ln.split()[1]
            keep.setdefault(current, []).append(ln)
        elif current and (ln.startswith("  query:") or ln.startswith("    esearch")
                          or ln.startswith("    runinfo") or ln.startswith("    EMPTY")
                          or ln.startswith("  NOTE:") or ln.startswith("  SHORTFALL:")
                          or ln.startswith("  ") and "acceptable runs" in ln):
            keep[current].append(ln)

    flagged = [c for c, ls in keep.items()
               if any("SHORTFALL" in x or "NOTE:" in x for x in ls)]
    if not flagged:
        lines.append("  No category reported a shortfall or a single-study confound.")
        return lines
    for cat in flagged:
        lines.append("")
        lines.extend(keep[cat])
    return lines


def cmd_verify(args):
    runs = read_panel(args.csv)
    log = []
    log.append("E1 accession verification")
    log.append("source file : %s" % args.csv)
    log.append("run count   : %d" % len(runs))
    log.append("criteria    : Illumina / PAIRED / WGS / METAGENOMIC / >= %s spots"
               % f"{MIN_SPOTS:,}")
    log.append("")

    if not runs:
        log.append("No Run accessions found. Nothing to verify.")
        Path(args.log).write_text("\n".join(log) + "\n", encoding="utf-8")
        print("\n".join(log))
        return 1

    records = []
    fetched = {r["Run"]: r for r in runinfo(runs)}
    for run in runs:
        row = fetched.get(run)
        if row is None:
            rec = {"run": run, "verdict": "FAIL", "bioproject": "", "biosample": "",
                   "organism": "", "library_strategy": "", "library_source": "",
                   "layout": "", "platform": "", "instrument": "", "spots": "",
                   "bases": "", "notes": "accession returned no runinfo from SRA"}
            log.append("  FAIL  %-12s no runinfo returned" % run)
        else:
            verdict, reasons = evaluate(row)
            rec = to_record(row, verdict, reasons)
            log.append("  %-4s  %-12s %-34s %12s spots  %s"
                       % (verdict, run, rec["organism"][:34], rec["spots"],
                          rec["notes"]))
        records.append(rec)

    # A duplicated spot count between two runs almost always means the wrong
    # accession was pasted twice.
    seen = {}
    for rec in records:
        s = rec["spots"]
        if s and s != "0":
            seen.setdefault(s, []).append(rec["run"])
    dupes = {s: r for s, r in seen.items() if len(r) > 1}
    if dupes:
        log.append("")
        for spots, group in dupes.items():
            log.append("  WARNING: identical spot count %s shared by %s -- "
                       "verify these are genuinely distinct runs"
                       % (spots, ", ".join(group)))

    passed = sum(1 for r in records if r["verdict"] == "PASS")
    log.append("")
    log.append("PASS %d / %d" % (passed, len(records)))
    if len(records) < args.expect:
        log.append("INCOMPLETE: the panel needs %d runs; %d are listed in %s."
                   % (args.expect, len(records), args.csv))

    # Per-category study counts, so single-study confounds are visible in the
    # log itself and not only in the CSV's notes column.
    by_cat = {}
    panel_rows = _panel_metadata(args.csv)
    for rec in records:
        cat = panel_rows.get(rec["run"], {}).get("category", "")
        if cat:
            by_cat.setdefault(cat, []).append(rec)
    if by_cat:
        log.append("")
        log.append("Per-category composition:")
        for cat in sorted(by_cat):
            studies = {r["bioproject"] for r in by_cat[cat] if r["bioproject"]}
            flag = ""
            if len(studies) == 1:
                flag = "   <-- SINGLE STUDY: category confounded with study; " \
                       "describe, do not average"
            log.append("  %-14s n=%d, %d study/studies: %s%s"
                       % (cat, len(by_cat[cat]), len(studies),
                          ", ".join(sorted(studies)), flag))

    # Shortfall evidence: the exact query and UID counts behind any category
    # that could not be filled. Reviewers are entitled to see the query, not a
    # claim about it.
    log.extend(_shortfall_evidence(args.queries_log))

    cols = list(records[0].keys())
    with open(args.out, "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=cols)
        w.writeheader()
        w.writerows(records)

    Path(args.log).write_text("\n".join(log) + "\n", encoding="utf-8")
    print("\n".join(log))
    print("\nWrote %s and %s" % (args.out, args.log))

    return 0 if (passed == len(records) == args.expect) else 1


def cmd_search(args):
    term = args.query or CATEGORY_QUERIES.get(args.category)
    if not term:
        raise SystemExit("give --query, or --category from: %s"
                         % ", ".join(sorted(CATEGORY_QUERIES)))
    full = "%s %s" % (term, CRITERIA_SUFFIX)
    print("query: %s\n" % full)
    uids = esearch(full, retmax=args.retmax)
    print("esearch returned %d UIDs" % len(uids))
    if not uids:
        print("No runs matched. Nothing to propose.")
        return 1

    rows = runinfo_for_ids(uids)
    print("runinfo returned %d rows\n" % len(rows))
    passing = []
    for row in rows:
        verdict, reasons = evaluate(row)
        if verdict == "PASS":
            passing.append(to_record(row, verdict, reasons))

    passing.sort(key=lambda r: -int(r["spots"] or 0))
    print("%-12s %-14s %-32s %14s  %s" % ("RUN", "BIOPROJECT", "ORGANISM", "SPOTS", "INSTRUMENT"))
    for rec in passing[: args.top]:
        print("%-12s %-14s %-32s %14s  %s"
              % (rec["run"], rec["bioproject"], rec["organism"][:32],
                 f"{int(rec['spots']):,}", rec["instrument"]))
    print("\n%d of %d candidates satisfy every criterion." % (len(passing), len(rows)))
    return 0 if passing else 1


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="mode")

    v = sub.add_parser("verify")
    v.add_argument("--csv", default="benchmark/accessions.csv")
    v.add_argument("--out", default="benchmark/run/accessions_verified.csv")
    v.add_argument("--log", default="benchmark/run/verification_log.txt")
    v.add_argument("--expect", type=int, default=30)
    v.add_argument("--queries-log",
                   default="benchmark/run/logs/panel_queries.log",
                   help="panel construction log, for shortfall evidence")
    v.set_defaults(func=cmd_verify)

    s = sub.add_parser("search")
    s.add_argument("--query")
    s.add_argument("--category", choices=sorted(CATEGORY_QUERIES))
    s.add_argument("--retmax", type=int, default=60)
    s.add_argument("--top", type=int, default=15)
    s.set_defaults(func=cmd_search)

    args = ap.parse_args()
    if not getattr(args, "func", None):
        ap.print_help()
        return 2
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
