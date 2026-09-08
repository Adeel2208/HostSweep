#!/usr/bin/env bash
# Fetch the Kraken2 Standard-8 database for E9 (deviation D5).
#
# Standard-8 is the capped 8 GB build, not Standard. Standard is ~90 GB on disk
# and wants comparable RAM; this host has 11 GB. The consequence is recorded in
# DEVIATIONS.md and must be carried into the manuscript: a capped database
# detects LESS human sequence than Standard, because capping drops minimizers.
# The residual-human figure it produces is a FLOOR, not an estimate.
#
# The build date is written to <db>/.build_date and becomes the db_build_date
# column of kraken2_human.csv -- a Kraken2 result is not reproducible without
# knowing which build produced it.
#
# Idempotent: an already-extracted database is left alone. Resumable: curl -C -
# continues a partial archive.
#
# Usage:  bash 06_fetch_kraken2_db.sh [build_date] [dest]
set -uo pipefail

BUILD="${1:-20250402}"
DEST="${2:-$HOME/hostsweep/k2_standard_08gb}"
ARCHIVE="k2_standard_08gb_${BUILD}.tar.gz"
URL="https://genome-idx.s3.amazonaws.com/kraken/${ARCHIVE}"
TMP="$HOME/hostsweep/dl"

say() { echo "[k2db $(date -u +%H:%M:%S)] $*"; }

mkdir -p "$TMP"
exec 9>"$TMP/.k2db.lock"
if ! flock -n 9; then say "another fetch holds the lock; exiting"; exit 0; fi

# hash.k2d is the large one; its presence means extraction completed.
if [ -s "$DEST/hash.k2d" ] && [ -s "$DEST/taxo.k2d" ]; then
    say "database already present at $DEST ($(du -sh "$DEST" | cut -f1))"
    [ -s "$DEST/.build_date" ] || echo "$BUILD" > "$DEST/.build_date"
    exit 0
fi

say "fetching $ARCHIVE (~8 GB, resumable)"
if ! curl -fL --retry 8 --retry-all-errors -C - -o "$TMP/$ARCHIVE" "$URL"; then
    say "download FAILED; leaving the partial file for a later resume"
    exit 1
fi

say "downloaded $(du -h "$TMP/$ARCHIVE" | cut -f1); extracting"
mkdir -p "$DEST"
if ! tar -xzf "$TMP/$ARCHIVE" -C "$DEST"; then
    say "extraction FAILED -- archive may be truncated; delete it and re-run"
    exit 1
fi

# Some builds nest the .k2d files one directory down.
if [ ! -s "$DEST/hash.k2d" ]; then
    inner="$(find "$DEST" -maxdepth 2 -name 'hash.k2d' -printf '%h\n' | head -1)"
    if [ -n "$inner" ] && [ "$inner" != "$DEST" ]; then
        say "flattening $inner"
        mv "$inner"/* "$DEST"/ && rmdir "$inner" 2>/dev/null || true
    fi
fi

if [ ! -s "$DEST/hash.k2d" ] || [ ! -s "$DEST/taxo.k2d" ]; then
    say "FAILED: hash.k2d/taxo.k2d missing after extraction"
    exit 1
fi

echo "$BUILD" > "$DEST/.build_date"
rm -f "$TMP/$ARCHIVE"
say "ready: $DEST ($(du -sh "$DEST" | cut -f1)), build $BUILD"
say "REMINDER: Standard-8 is capped; residual-human counts are a floor (D5)."
