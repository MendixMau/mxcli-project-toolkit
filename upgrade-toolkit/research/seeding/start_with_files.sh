#!/bin/bash
# start_with_files.sh <run folder> <name> <mda> <full version> <db> [<data-snapshot.zip>]   (env: PORT_OFF, WORKDIR like runapp.py)
# runapp.py start wipes run/<name>/ (incl. data/files), so a publisher snapshot's file contents (data/files/*) must be
# copied in after EVERY start; the database rows point at them (FileNotFoundInStorageException otherwise). This wraps both.
set -euo pipefail
RUN=$1; NAME=$2; MDA=$3; VER=$4; DB=$5; SNAP=${6:-}
W=${WORKDIR:-}
source "$RUN/upg-env.sh"   # NOTE: this resets WORKDIR to <run>/work, so the caller's value is restored below
B=$(cd "$(dirname "$0")/../../bin" && pwd)
export WORKDIR=${W:-$RUN/work}
python3 "$B/runapp.py" start "$NAME" "$MDA" "$VER" "$DB"
if [ -n "$SNAP" ]; then
  python3 -I - "$SNAP" "$WORKDIR/run/$NAME/data/files" <<'PY'
import sys, zipfile, os
z = zipfile.ZipFile(sys.argv[1]); dst = sys.argv[2]; n = 0
for i in z.infolist():
    if i.filename.startswith("data/files/") and not i.is_dir() and not i.filename.endswith(".keep"):
        rel = i.filename[len("data/files/"):]
        if ".." in rel.split("/"): continue          # untrusted zip: no path escape
        p = os.path.join(dst, rel); os.makedirs(os.path.dirname(p), exist_ok=True)
        open(p, "wb").write(z.read(i)); n += 1
print("start_with_files: %d file(s) copied into %s" % (n, dst))
PY
fi
