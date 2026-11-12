#!/usr/bin/env python3
"""mksnap.py: build a snapshot JSON for the diff.py controls from a hand-made base (db/http sections, synthetic) plus,
optionally, a log file read through snapshot.log_snapshot (the same code the real snapshot uses).

  mksnap.py base.json [--log runtime.log] [--set key=json ...] > snap.json
"""
import argparse, json, os, sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "bin"))
import snapshot  # noqa: E402

ap = argparse.ArgumentParser()
ap.add_argument("base"); ap.add_argument("--log"); ap.add_argument("--set", action="append", default=[])
a = ap.parse_args()
s = json.load(open(a.base))
if a.log:
    s["log"] = snapshot.log_snapshot(f"cat {a.log}")
for kv in a.set:  # dotted path = JSON value, e.g. db.entities.Administration.Account=2 is not supported: use top keys
    k, _, v = kv.partition("=")
    s[k] = json.loads(v)
json.dump(s, sys.stdout, indent=1)
