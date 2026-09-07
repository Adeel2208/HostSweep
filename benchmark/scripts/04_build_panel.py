#!/usr/bin/env python3
"""A: build a 30-library real panel from live SRA queries.

Queries SRA for each sample category, applies the inclusion criteria, and
proposes a panel spread across at least two BioProjects per category. Every
query is logged with its result count, including empty ones -- a category that
cannot be filled is demonstrated with evidence rather than asserted.

Inclusion criteria (hard):
    Illumina, PAIRED, WGS strategy, >= 1,000,000 spots
Preference (soft, used for ranking):
    2,000,000 - 8,000,000 spots

Nothing here adopts an accession. Output is a proposal for review; it is
written to a separate file and not into benchmark/accessions.csv.

Usage:
    python 04_build_panel.py --out benchmark/run/panel_proposed.csv \\
                            --log benchmark/run/logs/panel_queries.log
"""
import argparse
import csv
import io
import sys
import time
import urllib.parse
import urllib.request
from collections import defaultdict
from pathlib import Path

EUTILS = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils"
MIN_SPOTS = 1_000_000
# Practical ceiling, overridable with --max-spots. Not a scientific criterion:
# it exists because some runs carry 160 M+ spots (~100 GB of FASTQ each), which
# the disk and runtime budget cannot absorb. Blood metagenomes are inherently
# deep -- at a 20 M ceiling the category returns zero qualifying runs -- so the
# default is set where the shallowest real blood libraries sit.
MAX_SPOTS = 25_000_000
PREF_LOW, PREF_HIGH = 2_000_000, 8_000_000

RUNINFO_HEADER = (
    "Run,ReleaseDate,LoadDate,spots,bases,spots_with_mates,avgLength,size_MB,"
    "AssemblyName,download_path,Experiment,LibraryName,LibraryStrategy,"
    "LibrarySelection,LibrarySource,LibraryLayout,InsertSize,InsertDev,"
    "Platform,Model,SRAStudy,BioProject,Study_Pubmed_id,ProjectID,Sample,"
    "BioSample,SampleType,TaxID,ScientificName,SampleName,g1k_pop_code,source,"
    "g1k_analysis_group,Subject_ID,Sex,Disease,Tumor,Affection_Status,"
    "Analyte_Type,Histological_Type,Body_Site,CenterName,Submission,"
    "dbgap_study_accession,Consent,RunHash,ReadHash")

# Category -> candidate NCBI taxon names, in preference order. The manuscript's
# category names are kept as keys; the taxon actually used is recorded per row.
CATEGORIES = {
    "gut":          ["human gut metagenome", "human faecal metagenome",
                     "human feces metagenome", "gut metagenome"],
    "oral":         ["human oral metagenome", "human saliva metagenome",
                     "human subgingival plaque metagenome"],
    "skin":         ["human skin metagenome"],
    "respiratory":  ["human lung metagenome", "human nasopharyngeal metagenome",
                     "human respiratory tract metagenome", "human sputum metagenome"],
    "urogenital":   ["human vaginal metagenome", "human urinary tract metagenome",
                     "human semen metagenome", "human urogenital metagenome"],
    "blood":        ["human blood metagenome"],
    "environmental": ["soil metagenome", "wastewater metagenome",
                      "freshwater metagenome"],
}

# How many libraries to draw per category (sums to 30).
TARGET = {"gut": 6, "oral": 4, "skin": 4, "respiratory": 4,
          "urogenital": 4, "blood": 4, "environmental": 4}

LOG = []


def log(msg):
    LOG.append(msg)
    print(msg, flush=True)


def http_get(url, retries=4):
    last = None
    for attempt in range(retries):
        try:
            req = urllib.request.Request(
                url, headers={"User-Agent": "HostSweep-benchmark/1.0"})
            with urllib.request.urlopen(req, timeout=180) as r:
                return r.read().decode("utf-8", errors="replace")
        except Exception as exc:                       # noqa: BLE001
            last = exc
            time.sleep(2 * (attempt + 1))
    log("    NETWORK ERROR after %d tries: %r" % (retries, last))
    return ""


def parse_runinfo(text):
    lines = [ln for ln in text.splitlines() if ln.strip()]
    if not lines:
        return []
    if not lines[0].startswith("Run,"):
        lines.insert(0, RUNINFO_HEADER)
    return [r for r in csv.DictReader(io.StringIO("\n".join(lines))) if r.get("Run")]


def esearch(term, retmax):
    text = http_get("%s/esearch.fcgi?db=sra&retmax=%d&term=%s"
                    % (EUTILS, retmax, urllib.parse.quote(term)))
    return [c.split("</Id>")[0].strip() for c in text.split("<Id>")[1:]]


def runinfo_for_ids(uids):
    if not uids:
        return []
    out = []
    for i in range(0, len(uids), 100):
        chunk = uids[i:i + 100]
        out.extend(parse_runinfo(http_get(
            "%s/efetch.fcgi?db=sra&id=%s&rettype=runinfo&retmode=csv"
            % (EUTILS, ",".join(chunk)))))
        time.sleep(0.5)
    return out


def study_of(row):
    """Study identifier, preferring BioProject.

    ENA-submitted runs (ERR*) frequently come back with an empty BioProject in
    NCBI's runinfo while carrying their study in SRAStudy (e.g. ERP203501). An
    empty field would silently read as 'another distinct project' and inflate
    the per-category BioProject count, which is exactly the confound this panel
    is trying to measure.
    """
    bp = (row.get("BioProject") or "").strip()
    if bp:
        return bp
    return (row.get("SRAStudy") or "").strip() or "UNKNOWN_STUDY"


def acceptable(row):
    """Hard criteria. LibrarySource must be METAGENOMIC: several 'human
    urinary tract metagenome' and 'human blood metagenome' runs are submitted
    as GENOMIC, which means an isolate or an amplified single genome rather
    than a community, and those are exactly the class of error that put
    SRR6062009 (a Klebsiella isolate) into the original panel.

    MAX_SPOTS is a practical ceiling, not a scientific one: some blood runs
    carry 160 M+ spots, roughly 100 GB of FASTQ each, which neither the disk
    budget nor the runtime budget can absorb. It is recorded in DEVIATIONS.md.
    """
    try:
        spots = int(row.get("spots") or 0)
    except ValueError:
        return False, 0
    ok = ((row.get("Platform", "").upper() == "ILLUMINA")
          and (row.get("LibraryLayout", "").upper() == "PAIRED")
          and (row.get("LibraryStrategy", "").upper() == "WGS")
          and (row.get("LibrarySource", "").upper() == "METAGENOMIC")
          and MIN_SPOTS <= spots <= MAX_SPOTS)
    return ok, spots


def rank(spots):
    """Lower is better. Preferred band first, then closeness to the band."""
    if PREF_LOW <= spots <= PREF_HIGH:
        return (0, abs(spots - (PREF_LOW + PREF_HIGH) // 2))
    return (1, min(abs(spots - PREF_LOW), abs(spots - PREF_HIGH)))


def collect(category, taxa, retmax):
    """Query every taxon for a category; return accepted rows and a taxon map."""
    accepted = []
    for taxon in taxa:
        term = ('"%s"[Organism] AND "illumina"[Platform] AND "paired"[Layout] '
                'AND "wgs"[Strategy]' % taxon)
        log('  query: %s' % term)
        uids = esearch(term, retmax)
        log("    esearch -> %d UIDs" % len(uids))
        if not uids:
            log("    EMPTY: this taxon returns no Illumina/paired/WGS runs")
            continue
        rows = runinfo_for_ids(uids)
        good = 0
        for row in rows:
            ok, spots = acceptable(row)
            if ok:
                row["_taxon"] = taxon
                row["_spots"] = spots
                accepted.append(row)
                good += 1
        log("    runinfo -> %d rows, %d meet the criteria" % (len(rows), good))
    return accepted


def choose(category, accepted, want):
    """Pick `want` runs, spreading across BioProjects (>=2 where possible)."""
    by_project = defaultdict(list)
    for row in accepted:
        by_project[study_of(row)].append(row)
    for rows in by_project.values():
        rows.sort(key=lambda r: rank(r["_spots"]))

    # Round-robin across projects so no single study dominates a category.
    order = sorted(by_project, key=lambda p: rank(by_project[p][0]["_spots"]))
    chosen, idx = [], 0
    while len(chosen) < want and order:
        progressed = False
        for proj in list(order):
            if len(chosen) >= want:
                break
            if idx < len(by_project[proj]):
                chosen.append(by_project[proj][idx])
                progressed = True
        idx += 1
        if not progressed:
            break

    projects = {study_of(c) for c in chosen}
    note = ""
    if len(projects) < 2:
        note = ("only %d BioProject available for this category -- category is "
                "confounded with study" % len(projects))
        log("  NOTE: %s" % note)
    return chosen, note


def main():
    global MAX_SPOTS                                    # noqa: PLW0603
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="benchmark/run/panel_proposed.csv")
    ap.add_argument("--log", default="benchmark/run/logs/panel_queries.log")
    ap.add_argument("--retmax", type=int, default=120)
    ap.add_argument("--max-spots", type=int, default=MAX_SPOTS,
                    help="practical download ceiling (default %d)" % MAX_SPOTS)
    ap.add_argument("--categories", nargs="+", choices=sorted(CATEGORIES),
                    help="restrict to these categories (default: all). Use to "
                         "re-probe a shortfall at higher --retmax without "
                         "re-querying the whole panel.")
    args = ap.parse_args()
    MAX_SPOTS = args.max_spots

    log("A: real-library panel construction")
    log("criteria: Illumina / PAIRED / WGS / >= %s spots; prefer %s-%s"
        % (f"{MIN_SPOTS:,}", f"{PREF_LOW:,}", f"{PREF_HIGH:,}"))
    log("target: %d libraries across %d categories" % (sum(TARGET.values()), len(TARGET)))
    log("")

    panel, shortfalls = [], []
    wanted = set(args.categories) if args.categories else set(CATEGORIES)
    for category, taxa in CATEGORIES.items():
        if category not in wanted:
            continue
        want = TARGET[category]
        log("=" * 74)
        log("CATEGORY %s (target %d)" % (category, want))
        accepted = collect(category, taxa, args.retmax)
        log("  %d acceptable runs across %d BioProjects"
            % (len(accepted), len({study_of(r) for r in accepted})))
        if not accepted:
            shortfalls.append((category, want, 0,
                               "no taxon for this category returned any qualifying run"))
            log("  SHORTFALL: category cannot be filled")
            continue
        chosen, note = choose(category, accepted, want)
        if len(chosen) < want:
            shortfalls.append((category, want, len(chosen),
                               "only %d qualifying runs found" % len(chosen)))
            log("  SHORTFALL: %d of %d" % (len(chosen), want))
        for row in chosen:
            panel.append({
                "category": category,
                "taxon_used": row["_taxon"],
                "run": row["Run"],
                "bioproject": study_of(row),
                "biosample": row.get("BioSample", ""),
                "organism": row.get("ScientificName", ""),
                "library_strategy": row.get("LibraryStrategy", ""),
                "library_source": row.get("LibrarySource", ""),
                "layout": row.get("LibraryLayout", ""),
                "platform": row.get("Platform", ""),
                "instrument": row.get("Model", ""),
                "spots": row["_spots"],
                "notes": note,
            })

    log("=" * 74)
    log("PANEL: %d of %d" % (len(panel), sum(TARGET.values())))
    per_cat = defaultdict(set)
    for r in panel:
        per_cat[r["category"]].add(r["bioproject"])
    for cat in CATEGORIES:
        n = sum(1 for r in panel if r["category"] == cat)
        log("  %-14s %d libraries, %d BioProject(s)" % (cat, n, len(per_cat[cat])))
    if shortfalls:
        log("")
        log("SHORTFALLS (evidenced by the queries above):")
        for cat, want, got, why in shortfalls:
            log("  %-14s wanted %d, got %d -- %s" % (cat, want, got, why))

    # Duplicate spot counts almost always mean a pasted-twice accession.
    seen = defaultdict(list)
    for r in panel:
        seen[r["spots"]].append(r["run"])
    for spots, runs in seen.items():
        if len(runs) > 1:
            log("  WARNING: identical spot count %s shared by %s" % (spots, ", ".join(runs)))

    if panel:
        with open(args.out, "w", newline="", encoding="utf-8") as fh:
            w = csv.DictWriter(fh, fieldnames=list(panel[0].keys()))
            w.writeheader()
            w.writerows(panel)
        log("")
        log("Wrote %s" % args.out)
    Path(args.log).parent.mkdir(parents=True, exist_ok=True)
    Path(args.log).write_text("\n".join(LOG) + "\n", encoding="utf-8")
    print("Wrote %s" % args.log)
    return 0 if len(panel) == sum(TARGET.values()) else 1


if __name__ == "__main__":
    sys.exit(main())
