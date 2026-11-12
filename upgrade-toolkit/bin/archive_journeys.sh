#!/bin/bash
# archive_journeys.sh: keep the previous journeys run before a rerun writes over it (PR-F36).
#
#   archive_journeys.sh <work dir>
#
# Purchase Request 10.24, pipe-30 -> pipe-31: a rerun --from journeys writes journeys-*.out, logs/journeys.log and
# e2e-before-picked/ in place, so pipe-30's per-journey results (79/146 baseline FAILs, the comments/attachments
# cluster) were gone before anyone had read them.
#
# When <work>/journeys-before-picked.out exists, its text evidence is copied to
# <work>/archive/journeys-<UTC mtime of that file>/: the journeys-*.out files, processes.md, processes.out,
# NEEDS-JUDGMENT.md, logs/journeys.log, and every file under journeys/, e2e-before-picked/ and e2e-after/ except
# screenshots (*.png) and the copied engine/ (the screenshots are ~50 MB per pass; the findings and logs are not).
# The same run is archived once: an existing folder is left as it is. Exit 0 always but on input error (2).
set -u
[ $# = 1 ] && [ -d "$1" ] || { echo "usage: archive_journeys.sh <work dir>" >&2; exit 2; }
W=$1; f="$W/journeys-before-picked.out"
[ -f "$f" ] || { echo "archive: no previous journeys run in $W"; exit 0; }
stamp=$(python3 -c 'import os,sys,time;print(time.strftime("%Y%m%dT%H%M%SZ",time.gmtime(os.path.getmtime(sys.argv[1]))))' "$f")
d="$W/archive/journeys-$stamp"
[ ! -e "$d" ] || { echo "archive: already kept in $d"; exit 0; }
mkdir -p "$d"
n=$(cd "$W" && { for x in journeys-before-picked.out journeys-after.out processes.md processes.out NEEDS-JUDGMENT.md logs/journeys.log; do
      [ -f "$x" ] && echo "$x"; done
    for e in journeys e2e-before-picked e2e-after; do
      [ -d "$e" ] && find "$e" -type f ! -name '*.png' ! -path "$e/engine/*"; done; } > "$d/.files"
  tar -cf - -T "$d/.files" | tar -xf - -C "$d" && wc -l < "$d/.files")
rm -f "$d/.files"
echo "archive: kept $((n)) files of the previous journeys run in $d"
