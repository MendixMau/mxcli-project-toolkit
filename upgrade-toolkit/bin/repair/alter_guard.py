#!/usr/bin/env python3
"""alter_guard.py: run an `mxcli alter page` and fail loudly when it changed nothing, instead of a silent no-op.

Why (T2-4, T2R3-7): `mxcli alter page P set DataSource = microflow M(Param = $x)` printed "Altered page" and exited 0,
twice, on Opcenter's ClientConfiguration_NewEdit, and saved nothing: M lives in a protected add-on module
(modules/*.mxmodule, not in app.mpr), so mxcli cannot read its parameters and drops the mapping. The same holds for a
page that itself sits in an add-on: there is nothing in app.mpr to alter. Both runs lost time believing the message.

  alter_guard.py <app dir|.mpr> [--check] -- <mxcli command ...>
  e.g. alter_guard.py app -- mxcli exec -p app/App.mpr fix.mdl
       alter_guard.py app -- mxcli -p app/App.mpr -c "alter page Shop.Config_NewEdit { ... }"

The targets are read from the command and from every .mdl file it names: `alter page|snippet M.Name` and
`create [or modify|replace] page|snippet M.Name` (a `describe page` script run back). Before the command runs:
  REFUSED  a target in an add-on module (exit 2, not run): a vendor binary; get the vendor's newer build
           (playbooks/10-to-11.md row 9) or call the flow from a page in an own module
  INVALID  a target whose module is not in app.mpr, an `alter` of a document that does not exist, no target (exit 2)
  WARN     a flow called with arguments, `microflow|nanoflow M.F(...)`, whose module is outside the model: mxcli cannot
           save that mapping; copy it with copy_mappings.py --page <page> --ref <publisher app> (CE1571)
--check stops there (exit 1 on a WARN, else 0). Otherwise the command runs, and after it:
  NO-OP              an altered document whose unit is byte for byte unchanged although the command exited 0
  MAPPING NOT SAVED  a warned flow that is still called with an empty mapping in a target document
  HASH STALE         (FM-4) the unit changed but Unit.ContentsHash is not base64(sha256(Contents)): mx check can pass once and
                     the model loader then crashes; mxcli's ALTER PAGE of a nanoflow action mapping did this (Expression
                     mappings without the Variable key, OutputMappings dropped, hash left stale). Restore the unit
                     (git checkout -- .) and patch it as a unit instead: steps/repair.md row 23
  OK                 the document changed and every warned call carries a mapping (still run mx check)
Exit: 0 = changed as asked, 1 = NO-OP, MAPPING NOT SAVED, or --check with a WARN, 2 = REFUSED or INVALID (not run),
3 = the command failed (its exit code and output are printed). Since mxcli v0.28.0 (#1408) `mxcli exec` is all-or-nothing: exit 3
from an `exec` of a script means NOTHING of the script was written, so rerun the whole script after fixing the failing statement
(earlier mxcli versions had applied the statements before it). Exit 0 is not "something was written": NO-OP still applies.
The comparison is before and after ONE command, so it cannot straddle mxcli versions (bin/mxcli_pin.sh pins one per run).
"""
import argparse, base64, hashlib, os, re, subprocess, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from copy_mappings import Mpr, addon_modules, maps, outside, sites  # noqa: E402  (raw units, add-ons; T2R3-7)

NAME = r"([A-Za-z_]\w*\.[A-Za-z_]\w*)"
TARGET = re.compile(r"\b(alter|create(?:\s+or\s+(?:modify|replace))?)\s+(page|snippet)\s+" + NAME, re.I)
FLOW = re.compile(r"\b(?:microflow|nanoflow)\s+" + NAME + r"\s*\(\s*[^)\s]", re.I)


def texts(cmd):
    out = [" ".join(cmd)]
    for a in cmd:
        if a.lower().endswith(".mdl") and os.path.isfile(a):
            out.append(open(a, encoding="utf-8", errors="replace").read())
    return "\n".join(out)


def stale_hash(m, uid):
    """FM-4: (stored, computed) when Unit.ContentsHash of that unit is not base64(sha256(contents)), else None."""
    if "ContentsHash" not in m.cols:
        return None
    row = m.con.execute("select ContentsHash from Unit where UnitID=?", (uid,)).fetchone()
    if not row or not row[0]:
        return None
    want = base64.b64encode(hashlib.sha256(m.rows[uid][1]).digest()).decode()
    return None if row[0] == want else (row[0], want)


def main():
    argv = sys.argv[1:]
    cut = argv.index("--") if "--" in argv else len(argv)
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("app"); ap.add_argument("--check", action="store_true")
    a = ap.parse_args(argv[:cut])
    cmd = argv[cut + 1:]
    if not cmd:
        print("alter_guard: give the mxcli command after --", file=sys.stderr); sys.exit(2)
    try:
        m = Mpr(a.app)
    except Exception as e:
        print(f"alter_guard: {e}", file=sys.stderr); sys.exit(2)
    addons = addon_modules(m.proj)
    text = texts(cmd)
    targets = {}
    for verb, _, qn in TARGET.findall(text):
        targets.setdefault(qn, verb.lower().startswith("alter"))
    flows = sorted({qn for qn in FLOW.findall(text)})
    bad = 0
    if not targets:
        print("INVALID   no `alter page|snippet M.Name` (or create [or modify|replace]) in the command or its .mdl files"); bad = 1
    for qn, must_exist in sorted(targets.items()):
        mod = qn.split(".")[0]
        if mod not in m.modules and mod.lower() in addons:
            print(f"REFUSED   {qn}: module {mod} is a protected add-on ({addons[mod.lower()]}), not in "
                  f"{os.path.basename(m.path)}; mxcli would print 'Altered page' and change nothing (T2R3-7). Get the "
                  "vendor's newer build (playbooks/10-to-11.md row 9) or call the flow from a page in an own module"); bad = 1
        elif mod not in m.modules:
            print(f"INVALID   {qn}: module {mod} is not in {os.path.basename(m.path)}"); bad = 1
        elif must_exist and qn not in m.docs:
            print(f"INVALID   {qn}: no page or snippet of that name to alter"); bad = 1
    warned = {}
    for f in flows:
        why = outside(m, addons, f)
        if why:
            warned[f] = why
            pages = ", ".join(sorted(targets)) or "<page>"
            print(f"WARN      {f}(...): {why}; mxcli cannot read its parameters and saves NO mapping although it says "
                  f"'Altered page' (T2-4, T2R3-7). Copy the mapping instead: copy_mappings.py {a.app} --page {pages} "
                  "--ref <publisher app>")
    if bad:
        print("alter_guard: not run (REFUSED/INVALID above)"); sys.exit(2)
    if a.check:
        print(f"summary: {len(targets)} target(s), {len(warned)} warning(s); --check, not run")
        sys.exit(1 if warned else 0)
    before = {qn: m.rows[m.docs[qn]][1] for qn in targets if qn in m.docs}
    p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    sys.stdout.write(p.stdout)
    if p.returncode != 0:
        print(f"TOOL ERROR the command exited {p.returncode}; nothing checked"); sys.exit(3)
    m2 = Mpr(m.path)
    fail = 0
    for qn in sorted(targets):
        uid = m2.docs.get(qn)
        if uid is None:
            print(f"NO-OP     {qn}: still not in the model after the command"); fail += 1
            continue
        if qn in before and m2.rows[uid][1] == before[qn]:
            print(f"NO-OP     {qn}: the command exited 0 but the unit is byte for byte unchanged; nothing was saved"); fail += 1
            continue
        bad_hash = stale_hash(m2, uid)
        if bad_hash:
            print(f"HASH STALE {qn}: the unit changed but ContentsHash is {bad_hash[0][:12]}..., not the sha256 of its contents "
                  f"({bad_hash[1][:12]}...): the command wrote a unit the model loader may reject (FM-4). Restore it "
                  "(git checkout -- .) and patch the unit instead (steps/repair.md row 23)"); fail += 1
            continue
        lost = [k for k, o, t in sites(m2.decode(uid)) if t in warned and not maps(o)]
        for k in lost:
            print(f"MAPPING NOT SAVED {qn}: {k} still has an empty mapping ({warned[k.split(':', 1)[1].split('#')[0]]}); "
                  f"use copy_mappings.py --page {qn} --ref <publisher app>")
        fail += len(lost)
        if not lost:
            print(f"OK        {qn}: changed; now mx check")
    print(f"summary: {len(targets)} target(s), {fail} problem(s)")
    sys.exit(1 if fail else 0)


if __name__ == "__main__":
    main()
