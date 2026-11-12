#!/usr/bin/env python3
"""fakemxdiff.py: stands in for `mxcli marketplace diff ... --json` in the localedits controls (offline, no mxbuild).

  FAKE_DIFF=<localedits --json report> fakemxdiff.py marketplace diff <cid> --module NAME --json -p PROJECT

Replays what a real --mxcli-diff run recorded for that module: its "elements" as JSON on stdout (exit 0), or its
"elements_error" on stderr (exit 1). A module the report does not hold gives a clean, verified result.
"""
import json, os, sys

name = sys.argv[sys.argv.index("--module") + 1]
rep = {e["name"]: e for e in json.load(open(os.environ["FAKE_DIFF"]))} if os.environ.get("FAKE_DIFF") else {}
e = rep.get(name)
if e is None:
    print(json.dumps({"module": name, "locallyModified": False, "verified": True, "unchangedCount": 3}))
elif e.get("elements"):
    print(json.dumps(e["elements"]))
else:
    print(e.get("elements_error") or "no result", file=sys.stderr); sys.exit(1)
