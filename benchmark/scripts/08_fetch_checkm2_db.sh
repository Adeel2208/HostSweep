#!/usr/bin/env bash
# Fetch the CheckM2 reference database (Zenodo 10.5281/zenodo.14897628).
#
# `checkm2 database --download` cannot resume and, over a slow link, restarts
# from zero on every dropped connection (it ran at ~24 KiB/s and failed three
# times). This uses aria2c instead: parallel, resumable, and the archive is
# checked against Zenodo's published md5 before it is unpacked.
#
#     file   checkm2_database.tar.gz       1,735,095,710 bytes
#     md5    07c10655620843b517d0df0c160d911f
#
# Ends with uniref100.KO.1.dmnd under <dest>/CheckM2_database/, which is where
# run_checkm2.sh looks. Idempotent: does nothing if a .dmnd file is present.
#
# Usage:  bash 08_fetch_checkm2_db.sh [dest_dir]        default ~/hostsweep/checkm2_db
set -uo pipefail

DEST="${1:-$HOME/hostsweep/checkm2_db}"
URL="https://zenodo.org/api/records/14897628/files/checkm2_database.tar.gz/content"
ARCHIVE="checkm2_database.tar.gz"
MD5="07c10655620843b517d0df0c160d911f"
say() { echo "[checkm2db $(date -u +%H:%M:%S)] $*"; }

mkdir -p "$DEST"
if [ -n "$(find "$DEST" -name '*.dmnd' 2>/dev/null | head -1)" ]; then
    say "database already present: $(find "$DEST" -name '*.dmnd' | head -1)"; exit 0
fi

exec 9>"$DEST/.dl.lock"
flock -n 9 || { say "another fetch is running; exiting"; exit 0; }

CONNS="${CHECKM2_CONNECTIONS:-4}"
if [ ! -s "$DEST/$ARCHIVE" ] || [ -f "$DEST/$ARCHIVE.aria2" ]; then
    say "downloading (resumable, $CONNS connections)"
    if command -v aria2c >/dev/null 2>&1; then
        aria2c -x"$CONNS" -s"$CONNS" -k4M -c --file-allocation=none --auto-file-renaming=false \
            --max-tries=30 --retry-wait=10 --summary-interval=60 \
            -d "$DEST" -o "$ARCHIVE" "$URL" \
            || { say "download did not finish; re-run to resume"; exit 1; }
    else
        curl -fL --retry 8 --retry-all-errors -C - -o "$DEST/$ARCHIVE" "$URL" \
            || { say "download did not finish; re-run to resume"; exit 1; }
    fi
fi

say "checking md5"
GOT="$(md5sum "$DEST/$ARCHIVE" | cut -d' ' -f1)"
if [ "$GOT" != "$MD5" ]; then
    say "md5 MISMATCH (got $GOT, expected $MD5). The archive is damaged or incomplete;"
    say "  delete $DEST/$ARCHIVE and $DEST/$ARCHIVE.aria2 and re-run."
    exit 1
fi
say "md5 ok; unpacking"
tar -xzf "$DEST/$ARCHIVE" -C "$DEST" || { say "unpack failed"; exit 1; }
DMND="$(find "$DEST" -name '*.dmnd' | head -1)"
[ -n "$DMND" ] || { say "no .dmnd found after unpacking"; exit 1; }
rm -f "$DEST/$ARCHIVE" "$DEST/$ARCHIVE.aria2"
say "ready: $DMND"
