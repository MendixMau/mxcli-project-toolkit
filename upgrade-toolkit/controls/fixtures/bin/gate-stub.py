#!/usr/bin/env python3
"""gate-stub.py: stands in for every instrument bin/gate.sh calls (N1-13 controls). Copied under each instrument's name
into a scratch folder that UPG_GATE_BIN points at. rc from GATE_STUB_RC_<name> (default 0), extra output from
GATE_STUB_OUT_<name>, a pause from GATE_STUB_SLEEP_<name> seconds; the argv of each call is appended to $GATE_STUB_LOG, so a control can prove what ran.
E2E-15: a subcommand (argv[1], - as _) has its own GATE_STUB_RC_<name>_<sub> / GATE_STUB_OUT_<name>_<sub>; `apimock.py
standin` uses only those, by default "nothing was stood in" (rc 0), so the instrument-wide values of the E2E-13/14
controls (apimock check / attribute-smoke) do not leak into it."""
import os, sys, time
a = sys.argv
stem = os.path.splitext(os.path.basename(a[0]))[0]
if os.environ.get("GATE_STUB_LOG"):
    open(os.environ["GATE_STUB_LOG"], "a").write(stem + " " + " ".join(a[1:]) + "\n")
for f in ("--md", "--out"):
    if f in a:
        open(a[a.index(f) + 1], "w").write("stub\n")
if "--shots" in a:
    os.makedirs(a[a.index("--shots") + 1], exist_ok=True)
time.sleep(float(os.environ.get("GATE_STUB_SLEEP_" + stem, "0")))
if os.environ.get("GATE_STUB_DONE_" + stem):   # reached only when not killed during the pause: a control can prove a timeout killed it
    open(os.environ["GATE_STUB_DONE_" + stem], "w").write("done\n")
sub = a[1].replace("-", "_") if len(a) > 1 and a[1][:1].isalpha() and "/" not in a[1] else ""
out = os.environ.get("GATE_STUB_OUT_" + stem, stem + ": stub ok")
rc = os.environ.get("GATE_STUB_RC_" + stem, "0")
if (stem, sub) == ("apimock", "standin"):
    out, rc = "stand-in endpoints 0 · requests answered 0", "0"
if sub:
    out = os.environ.get(f"GATE_STUB_OUT_{stem}_{sub}", out)
    rc = os.environ.get(f"GATE_STUB_RC_{stem}_{sub}", rc)
print(out)
sys.exit(int(rc))
