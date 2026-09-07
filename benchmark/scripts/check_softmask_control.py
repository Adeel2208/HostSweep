#!/usr/bin/env python3
"""Control for the soft-mask check: is lowercase content repeat-masking or not?

The Han1 hazard is that an assembly fills gaps with CHM13 sequence written in
lowercase. A naive "reject any lowercase" test cannot tell that apart from
NCBI's own repeat soft-masking, which is applied to eukaryotic genomes in the
distributed FASTA.

This measures lowercase fraction on genomes whose provenance is not in
question, so the baseline is known:

  * T2T-CHM13v2.0 itself -- if NCBI's distributed human FASTA is soft-masked,
    the reference we align against will show a large lowercase fraction. It
    cannot contain "CHM13-derived gap fill" because it *is* CHM13.
  * A bacterial genome -- little repeat content, so a low fraction is expected
    and confirms the masking is repeat-driven rather than blanket.

If CHM13 shows a comparable fraction to the HPRC assemblies, lowercase content
is repeat-masking and carries no information about reference contamination.

Usage:
    python check_softmask_control.py <fasta> [fasta ...]
"""
import sys
from pathlib import Path

_CLASS = bytes((76 if 97 <= i <= 122 else (85 if 65 <= i <= 90 else 79))
               for i in range(256))


def composition(path):
    upper = lower = n_upper = n_lower = 0
    with open(path, "rb") as fh:
        for line in fh:
            if line.startswith(b">"):
                continue
            line = line.rstrip()
            klass = line.translate(_CLASS)
            nu, nl = line.count(b"N"), line.count(b"n")
            upper += klass.count(b"U") - nu
            lower += klass.count(b"L") - nl
            n_upper += nu
            n_lower += nl
    total = upper + lower + n_upper + n_lower
    return {
        "total": total,
        "lower": lower + n_lower,
        "lowercase_pct": round(100.0 * (lower + n_lower) / total, 4) if total else 0.0,
        "n_pct": round(100.0 * (n_upper + n_lower) / total, 6) if total else 0.0,
    }


def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    print("%-46s %14s %10s %8s" % ("file", "total bases", "lowercase", "N"))
    for arg in sys.argv[1:]:
        p = Path(arg)
        if not p.exists():
            print("%-46s %14s" % (p.name, "ABSENT"))
            continue
        c = composition(p)
        print("%-46s %14d %9.4f%% %7.4f%%"
              % (p.name[:46], c["total"], c["lowercase_pct"], c["n_pct"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
