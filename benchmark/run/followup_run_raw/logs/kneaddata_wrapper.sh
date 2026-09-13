#!/usr/bin/env bash
# KneadData drives Trimmomatic through bioconda"s Java wrapper, which hardcodes
# -Xmx1g -- too small for the 2M-pair libraries here, so Trimmomatic dies with
# an OutOfMemoryError. KneadData"s own --max-memory does NOT help: it only
# applies on the "java -jar" code path, and this build calls the wrapper
# executable instead. The wrapper drops its default whenever _JAVA_OPTIONS is
# set, which is the supported override. Lives in the conda env rather than in
# benchmark/scripts so it survives the scripts git reset.
export _JAVA_OPTIONS="-Xmx8g"
exec "$(dirname "$0")/kneaddata-real" "$@"
