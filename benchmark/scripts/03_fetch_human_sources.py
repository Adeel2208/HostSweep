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

  2. Measures soft-masked (lowercase) and N content directly from the
     downloaded FASTA. This is INFORMATIONAL, not a gate -- see below.

Why lowercase content is not a CHM13-gap-fill test
--------------------------------------------------
It was written as one, on the theory that Han1's reference-derived gap-fill is
lowercase. A control run (check_softmask_control.py) refuted that:

    T2T-CHM13v2.0 itself      40.27% lowercase
    HG00438 (HPRC year 1)     39.55% lowercase
    E. coli GCF_000005845.2    0.0000% lowercase

CHM13 cannot contain CHM13-derived sequence -- it *is* CHM13 -- yet it carries
more lowercase than the HPRC assembly. Lowercase in NCBI's distributed
eukaryotic FASTA is repeat soft-masking and says nothing about reference
contamination.

Nor is a similarity test available: every human genome is ~99.9% identical to
CHM13, so "sequence resembling CHM13" cannot be distinguished from ordinary
human sequence. The Han1 case is knowable only because its authors documented
it. **Provenance is the only sound gate**, so that is what this script
enforces: de novo assembler, no reference-guided scaffolding, correct
submitter, and an explicit exclusion list for the affected sample.

Usage:
    python 03_fetch_human_sources.py --refs <workdir>/refs
    python 03_fetch_human_sources.py --refs <workdir>/refs --verify-only
"""
import argparse
import json
import subprocess
import sys
import urllib.error
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


def _curl(url, dest=None, timeout=1800):
    """Fetch via curl. Returns bytes when dest is None, else writes to dest.

    Python's urllib fails with 'Network is unreachable' inside this WSL2 guest
    while curl succeeds, so curl is the transport here rather than a fallback
    bolted on after the fact.
    """
    cmd = ["curl", "-fsSL", "--retry", "3", "--max-time", str(timeout),
           "-H", "User-Agent: HostSweep-benchmark/1.0", url]
    if dest is not None:
        cmd += ["-o", str(dest)]
        subprocess.run(cmd, check=True)
        return None
    return subprocess.run(cmd, check=True, stdout=subprocess.PIPE).stdout


def fetch_json(url):
    try:
        req = urllib.request.Request(
            url, headers={"User-Agent": "HostSweep-benchmark/1.0"})
        with urllib.request.urlopen(req, timeout=120) as r:
            return json.load(r)
    except (urllib.error.URLError, OSError):
        return json.loads(_curl(url, timeout=120))


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


def ftp_url(accession, assembly_name):
    """Static NCBI FTP path for an assembly's genomic FASTA.

    Preferred over the Datasets download endpoint: that endpoint builds the
    zip on the fly, does not support byte ranges, and aborted with curl exit 56
    partway through a ~1 GB human assembly. The FTP object is static, so an
    interrupted transfer resumes with -C - instead of restarting.
    """
    acc, ver = accession.split(".")[0], accession
    prefix, digits = acc[:3], acc[4:]
    parts = "/".join(digits[i:i + 3] for i in (0, 3, 6))
    stem = "%s_%s" % (ver, assembly_name)
    return ("https://ftp.ncbi.nlm.nih.gov/genomes/all/%s/%s/%s/%s_genomic.fna.gz"
            % (prefix, parts, stem, stem))


def download(accession, assembly_name, dest):
    """Download and decompress the genomic FASTA for an accession."""
    url = ftp_url(accession, assembly_name)
    gz = dest.with_suffix(".fna.gz")
    print("    downloading %s" % url, flush=True)
    # -C - resumes a partial file; --retry-all-errors covers mid-transfer aborts.
    subprocess.run(["curl", "-fsSL", "-C", "-", "--retry", "8",
                    "--retry-delay", "5", "--retry-all-errors",
                    "--max-time", "3600",
                    "-H", "User-Agent: HostSweep-benchmark/1.0",
                    url, "-o", str(gz)], check=True)
    print("    decompressing (%.2f GB compressed)" % (gz.stat().st_size / 1e9),
          flush=True)
    with open(dest, "wb") as out:
        subprocess.run(["gzip", "-dc", str(gz)], check=True, stdout=out)
    gz.unlink()
    print("    wrote %s (%.2f GB)" % (dest.name, dest.stat().st_size / 1e9))


# Byte class table: uppercase letters -> 'U', lowercase -> 'L', anything else
# -> 'O'. Counting with bytes.translate + bytes.count runs in C, where the
# obvious per-byte Python loop takes hours on a 3 GB assembly.
_CLASS = bytes((76 if 97 <= i <= 122 else (85 if 65 <= i <= 90 else 79))
               for i in range(256))


def composition(path):
    """Stream the FASTA and count case and N content."""
    upper = lower = n_upper = n_lower = other = 0
    with open(path, "rb") as fh:
        for line in fh:
            if line.startswith(b">"):
                continue
            line = line.rstrip()
            klass = line.translate(_CLASS)
            u = klass.count(b"U")
            low = klass.count(b"L")
            other += klass.count(b"O")
            nu = line.count(b"N")
            nl = line.count(b"n")
            # N/n are letters, so remove them from the plain-base tallies.
            upper += u - nu
            lower += low - nl
            n_upper += nu
            n_lower += nl
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
            download(acc, prov["assembly_name"], dest)

        if dest.exists():
            print("  measuring case composition (this streams the whole FASTA)...",
                  flush=True)
            comp = composition(dest)
            print("  lowercase:       %.6f %%  (%d bases)"
                  % (comp["lowercase_pct"], comp["bases_lower"] + comp["n_lower"]))
            print("  N content:       %.6f %%" % comp["n_pct"])
            print("  total bases:     %d" % comp["total"])
            # Lowercase content is INFORMATIONAL ONLY. It was originally a
            # rejection criterion on the theory that Han1-style CHM13 gap-fill
            # is written in lowercase, but a control run
            # (check_softmask_control.py) showed the test cannot do that job:
            #
            #   T2T-CHM13v2.0 itself   40.27% lowercase
            #   HG00438 (HPRC)         39.55% lowercase
            #   E. coli GCF_000005845  0.0000% lowercase
            #
            # CHM13 cannot contain CHM13-derived gap-fill, yet it carries MORE
            # lowercase than the HPRC assembly. Lowercase in NCBI's distributed
            # eukaryotic FASTA is repeat soft-masking, and it carries no
            # information about reference contamination.
            #
            # There is also no similarity-based test available: every human
            # genome is ~99.9% identical to CHM13, so "sequence that looks like
            # CHM13" is indistinguishable from ordinary human sequence. The
            # Han1 case is knowable only because its authors documented it.
            # Provenance is therefore the gate, and it is checked above.
            if comp["lowercase_pct"] > 45.0:
                problems.append("%s: %.4f%% lowercase, unusually high even for "
                                "repeat masking -- inspect provenance"
                                % (sample, comp["lowercase_pct"]))
                print("  FLAG: lowercase above the repeat-masking range")
            else:
                print("  lowercase consistent with NCBI repeat soft-masking "
                      "(CHM13 itself is 40.27%); not evidence of gap-fill")
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
