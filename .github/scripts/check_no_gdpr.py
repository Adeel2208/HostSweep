#!/usr/bin/env python3
"""Fail if GDPR terminology reappears on a user-facing surface.

The journal requires the term to be absent from code, CLI, output filenames
and documentation. One deliberate exception remains: the hidden, deprecated
``--gdpr-minlen`` CLI alias in cli.py, kept so existing scripts keep working.
It is suppressed from ``--help`` output.

Run from the repository root:  python .github/scripts/check_no_gdpr.py
"""
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

# (path, set of allowed line numbers) -- allowances are deliberate and narrow.
ALLOWED_SUBSTRINGS = (
    "--gdpr-minlen",              # deprecated alias definition + warning
    "gdpr-minlen is deprecated",
)

SEARCH_PATHS = ["hostsweep", "benchmark", "tests", "README.md"]

failures = []

for rel in SEARCH_PATHS:
    target = ROOT / rel
    paths = [target] if target.is_file() else [
        p for p in target.rglob("*")
        if p.is_file() and p.suffix in {".py", ".md", ".sh", ".csv", ".yml"}
    ]
    for path in paths:
        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        for lineno, line in enumerate(text.splitlines(), start=1):
            if "gdpr" not in line.lower():
                continue
            if any(allowed in line for allowed in ALLOWED_SUBSTRINGS):
                continue
            # tests assert on the absence of the term, so they may name it.
            if path.name.startswith("test_"):
                continue
            failures.append(f"{path.relative_to(ROOT)}:{lineno}: {line.strip()}")

# Output filenames must never carry the term.
pipeline = (ROOT / "hostsweep" / "pipeline.py").read_text(encoding="utf-8")
if "_GDPR.fastq" in pipeline:
    failures.append("hostsweep/pipeline.py: output filename still uses _GDPR")
if "_STRINGENT.fastq.gz" not in pipeline:
    failures.append("hostsweep/pipeline.py: expected _STRINGENT.fastq.gz output name")

# The rendered CLI help is the surface reviewers will look at.
help_text = subprocess.run(
    [sys.executable, "-m", "hostsweep", "--help"],
    capture_output=True, text=True, cwd=ROOT,
).stdout
if "gdpr" in help_text.lower():
    failures.append("`hostsweep --help` output mentions GDPR")
if "--stringent-minlen" not in help_text:
    failures.append("`hostsweep --help` is missing --stringent-minlen")

def emit(text):
    """Print without exploding on a Windows cp1252 console."""
    encoding = sys.stdout.encoding or "utf-8"
    sys.stdout.write(text.encode(encoding, "replace").decode(encoding) + "\n")


if failures:
    emit("User-facing GDPR terminology found:\n")
    for f in failures:
        emit("  " + f)
    sys.exit(1)

emit("OK: no user-facing GDPR terminology; --stringent-minlen present.")
