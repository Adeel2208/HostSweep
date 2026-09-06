#!/usr/bin/env python3
"""Fetch the mismatch-arm human assemblies and verify they are pure de novo.

The three libraries in the reference-mismatch arm must come from assemblies
that contain **no CHM13-derived sequence**. If they did, the decontamination
reference would have been injected into the very reads the arm is meant to
test, and the mismatch measurement would be meaningless.

The known hazard is the Han1 assembly (sample HG00621, JHU), which fills
intra-contig gaps with CHM13 v1.1 sequence written in lowercase. This script
therefore does two things:

  1. Records NCBI provenance -- assembly method, level, submitter, BioProject.
     A pure de novo HiFi assembly is built by hifiasm from reads alone, and is
     released at contig or scaffold level. Chromosome-level releases imply
     reference-guided scaffolding and are rejected here.

  2. Measures soft-masked (lowercase) content directly from the downloaded
     FASTA. hifiasm emits uppercase sequence throughout, so a pure assembly is
     ~0% lowercase. Han1-style reference gap-fill shows up as a non-trivial
     lowercase fraction. This is an empirical check on the actual bytes, not a
     restatement of the metadata.

Also reports N content (scaffold gaps) for completeness.

Usage:
    python 03_fetch_human_sources.py --refs <workdir>/refs
    python 03_fetch_human_sources.py --refs <workdir>/refs --verify-only
"""
import argparse
import json
import sys
import urllib.request
import zipfile
from pathlib import Path

# HPRC Year 1, f1_assembly_v2, primary/maternal haplotype. One assembly
# project, one assembler version (hifiasm v0.14), three populations -- so
# "reference mismatch" is not confounded with "different assembler".
SOURCES = {
    "HG00438": {"accession": "GCA_018471515.1", "population": "Han Chinese South (CHS)"},
    "HG00733": {"accession": "GCA_018506975.1", "population": "Puerto Rican (PUR)"},
    "NA19240": {"accession": "GCA_018503275.1", "population": "Yoruban (YRI)"},
}

# Sample whose best-known assembly (Han1, JHU) contains CHM13 v1.1 gap-fill.
# Nothing in this benchmark may use it.
FORBIDDEN_SAMPLES = {"HG00621"}
FORBIDDEN_ASSEMBLY_SUBSTRINGS = ("han1",)

API = "https://api.ncbi.nlm.nih.gov/datasets/v2alpha/genome/accession/{}"


def fetch_json(url):
    req = urllib.request.Request(url, headers={"User-Agent": "HostSweep-benchmark/1.0"})
    with urllib.request.urlopen(req, timeout=120) as r:
        return json.load(r)


def provenance(accession):
    d = fetch_json(API.format(accession) + "/dataset_report?filters.assembly_version=all_assemblies")
    reps = d.get("reports")
    if not reps:
        return None
    rep = reps[0]
    info = rep.get("assembly_info", {})
    bios = info.get("biosample", {}) or {}
    attrs = {a.get("name"): a.get("value") for a in (bios.get("attributes") or [])}
    return {
        "accession": rep.get("accession"),
        "assembly_name": info.get("assembly_name"),
        "assembly_level": info.get("assembly_level"),
        "assembly_method": info.get("assembly_method"),
        "sequencing_tech": info.get("sequencing_tech"),
        "submitter": info.get("submitter"),
        "release_date": info.get("release_date"),
        "bioproject": info.get("bioproject_accession"),
        "biosample": bios.get("accession"),
        "population": attrs.get("population", ""),
        "isolate": attrs.get("isolate", ""),
        "total_length": rep.get("assembly_stats", {}).get("total_sequence_length"),
    }


def download(accession, dest):
    """Download the genomic FASTA for an accession to dest."""
    url = (API.format(accession) +
           "/download?include_annotation_type=GENOME_FASTA")
    tmp_zip = dest.with_suffix(".zip")
    print("    downloading %s ..." % accession, flush=True)
    req = urllib.request.Request(url, headers={"User-Agent": "HostSweep-benchmark/1.0"})
    with urllib.request.urlopen(req, timeout=1800) as r, open(tmp_zip, "wb") as fh:
        while True:
            chunk = r.read(1 << 20)
            if not chunk:
                break
            fh.write(chunk)
    with zipfile.ZipFile(tmp_zip) as z:
        names = [n for n in z.namelist() if n.endswith((".fna", ".fasta", ".fa"))]
        if not names:
            raise SystemExit("no FASTA inside the archive for %s" % accession)
        names.sort(key=lambda n: -z.getinfo(n).file_size)
        with z.open(names[0]) as src, open(dest, "wb") as out:
            while True:
                chunk = src.read(1 << 20)
                if not chunk:
                    break
                out.write(chunk)
    tmp_zip.unlink()
    print("    wrote %s (%.2f GB)" % (dest.name, dest.stat().st_size / 1e9))


def composition(path):
    """Stream the FASTA and count case and N content."""
    upper = lower = n_upper = n_lower = other = 0
    with open(path, "rb") as fh:
        for line in fh:
            if line.startswith(b">"):
                continue
            for byte in line.rstrip():
                if 65 <= byte <= 90:          # A-Z
                    if byte == 78:
                        n_upper += 1
                    else:
                        upper += 1
                elif 97 <= byte <= 122:       # a-z
                    if byte == 110:
                        n_lower += 1
                    else:
                        lower += 1
                else:
                    other += 1
    total = upper + lower + n_upper + n_lower
    return {
        "bases_upper": upper, "bases_lower": lower,
        "n_upper": n_upper, "n_lower": n_lower,
        "other": other, "total": total,
        "lowercase_pct": round(100.0 * (lower + n_lower) / total, 6) if total else 0.0,
        "n_pct": round(100.0 * (n_upper + n_lower) / total, 6) if total else 0.0,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--refs", required=True)
    ap.add_argument("--verify-only", action="store_true")
    ap.add_argument("--report", default=None)
    args = ap.parse_args()

    refs = Path(args.refs)
    refs.mkdir(parents=True, exist_ok=True)
    findings = []
    problems = []

    for sample, spec in SOURCES.items():
        acc = spec["accession"]
        print("=" * 78)
        print("%s  %s  (%s)" % (sample, acc, spec["population"]))

        if sample in FORBIDDEN_SAMPLES:
            problems.append("%s is on the forbidden list (Han1 CHM13 gap-fill)" % sample)
            print("  REJECTED: forbidden sample")
            continue

        prov = provenance(acc)
        if prov is None:
            problems.append("%s: accession %s does not resolve" % (sample, acc))
            print("  FAIL: does not resolve at NCBI")
            continue

        for key in ("assembly_name", "assembly_level", "assembly_method",
                    "sequencing_tech", "submitter", "release_date",
                    "bioproject", "biosample", "population", "total_length"):
            print("  %-16s %s" % (key + ":", prov[key]))

        name_lc = (prov["assembly_name"] or "").lower()
        if any(bad in name_lc for bad in FORBIDDEN_ASSEMBLY_SUBSTRINGS):
            problems.append("%s: assembly name looks like Han1" % sample)
            print("  REJECTED: assembly name matches the Han1 pattern")
            continue

        # A pure de novo release is contig- or scaffold-level. Chromosome-level
        # implies reference-guided scaffolding.
        if prov["assembly_level"] not in ("Contig", "Scaffold"):
            problems.append("%s: assembly level is %s, not Contig/Scaffold "
                            "(suggests reference-guided scaffolding)"
                            % (sample, prov["assembly_level"]))
            print("  WARN: assembly level %s" % prov["assembly_level"])

        method = (prov["assembly_method"] or "").lower()
        if "hifiasm" not in method:
            problems.append("%s: assembly method '%s' is not hifiasm"
                            % (sample, prov["assembly_method"]))
            print("  WARN: unexpected assembly method")

        dest = refs / ("%s_pri_mat_f1_v2.fna" % sample)
        if not dest.exists() and not args.verify_only:
            download(acc, dest)

        if dest.exists():
            print("  measuring case composition (this streams the whole FASTA)...",
                  flush=True)
            comp = composition(dest)
            print("  lowercase:       %.6f %%  (%d bases)"
                  % (comp["lowercase_pct"], comp["bases_lower"] + comp["n_lower"]))
            print("  N content:       %.6f %%" % comp["n_pct"])
            print("  total bases:     %d" % comp["total"])
            # hifiasm emits uppercase throughout. Anything beyond a rounding
            # trace of lowercase means soft-masked or reference-derived bases.
            if comp["lowercase_pct"] > 0.01:
                problems.append("%s: %.4f%% of bases are lowercase -- possible "
                                "reference-derived (Han1-style) gap-fill"
                                % (sample, comp["lowercase_pct"]))
                print("  REJECTED: lowercase content above threshold")
            else:
                print("  OK: no meaningful soft-masked content")
            prov.update(comp)
        else:
            print("  (not downloaded; composition check pending)")
            prov["lowercase_pct"] = None

        prov["sample"] = sample
        findings.append(prov)

    print("=" * 78)
    if problems:
        print("\n%d PROBLEM(S):" % len(problems))
        for p in problems:
            print("  - %s" % p)
    else:
        measured = [f for f in findings if f.get("lowercase_pct") is not None]
        print("\nMetadata checks pass for %d source(s): hifiasm de novo, "
              "contig/scaffold level, not Han1." % len(findings))
        if findings and len(measured) == len(findings):
            print("Sequence composition measured for all %d: no meaningful "
                  "soft-masked content." % len(measured))
        else:
            print("Sequence composition NOT yet measured for %d of %d source(s) "
                  "(FASTA not downloaded). The no-CHM13-sequence claim is "
                  "incomplete until it is."
                  % (len(findings) - len(measured), len(findings)))

    if args.report:
        Path(args.report).write_text(json.dumps(
            {"sources": findings, "problems": problems}, indent=2), encoding="utf-8")
        print("Wrote %s" % args.report)

    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
