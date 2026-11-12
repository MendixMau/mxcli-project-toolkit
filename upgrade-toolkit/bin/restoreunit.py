#!/usr/bin/env python3
"""restoreunit.py BASELINE.mpr TARGET.mpr Module.Doc [Module.Doc ...] [--apply] [--force]

Put documents back from a baseline copy of the model (PLM-30). A module update, or an `--accept-unsaved` update, can
reset a document you had edited locally (a Marketplace layout, a page, a microflow). localedits tells you which; this
tool restores them: the Contents of each named document in the baseline replace the Contents of the same-named
document in the target, KEEPING the target's unit id and containment (so nothing else in the project moves).

Works on MPR v1 (Contents column) and v2 (mprcontents/**/*.mxunit); baseline and target must be the same Mendix
version. Dry run unless --apply. Guards, each a refusal (exit 2) unless --force:
  - a document missing on either side, or of a different type on the two sides
  - a baseline document that names (Module.Name) a document the target does not have: the update removed or renamed
    it, and the restored content would hold a broken reference
  - the target app is open in Studio Pro (a .mpr.lock or Studio Pro's lock file beside it)
The restored content is re-read and compared after --apply. Exit 0 = done (or dry run shows what it would do),
1 = nothing to do (identical), 2 = refused. Make a git commit of the target before --apply; the change is one unit each."""
import base64, glob, hashlib, os, re, sqlite3, sys, uuid
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mprmodel
from mprmodel import Model, norm, strings
import bson

QN_ONLY = re.compile(r"^[A-Za-z_]\w*\.[A-Za-z_]\w*$")


def uid_of(model, doc):
    for uid, (_, _, d) in model.units.items():
        if d is doc.data:
            return uid
    return None


def unit_file(mpr, uid):
    base = os.path.join(os.path.dirname(os.path.abspath(mpr)), "mprcontents")
    for u in (str(uuid.UUID(bytes_le=uid)), str(uuid.UUID(bytes=uid))):
        for f in glob.glob(os.path.join(base, "**", u + ".mxunit"), recursive=True):
            return f
    return None


def write_unit(mpr, uid, data):
    con = sqlite3.connect(mpr)
    cols = [r[1] for r in con.execute("pragma table_info(Unit)")]
    blob = bson.encode(data)
    f = unit_file(mpr, uid)
    if f:
        open(f, "wb").write(blob)
        if "Contents" in cols:
            con.execute("update Unit set Contents=NULL where UnitID=?", (uid,))
    else:
        con.execute("update Unit set Contents=? where UnitID=?", (blob, uid))
    if "ContentsHash" in cols:
        con.execute("update Unit set ContentsHash=? where UnitID=?",
                    (base64.b64encode(hashlib.sha256(blob).digest()).decode(), uid))
    con.commit(); con.close()


def main(argv):
    flags = {a for a in argv if a in ("--apply", "--force")}
    a = [x for x in argv if x not in flags]
    if len(a) < 3:
        sys.exit(__doc__)
    old_p, new_p, names = a[0], a[1], a[2:]
    for p in (old_p, new_p):
        if not os.path.isfile(p):
            print(f"restoreunit: {p} is not a file"); return 2
    if os.path.realpath(old_p) == os.path.realpath(new_p):
        print("restoreunit: baseline and target are the same file"); return 2
    old, new = Model.load(old_p), Model.load(new_p)
    refused = 0; todo = []
    lock = [f for f in (new_p + ".lock", os.path.join(os.path.dirname(os.path.abspath(new_p)), ".mendix-cache", "lock"))
            if os.path.exists(f)]
    if lock and "--force" not in flags:
        print(f"REFUSED target looks open in Studio Pro ({lock[0]}); close it or --force"); refused += 1
    for qn in names:
        o, n = old.docs.get(qn), new.docs.get(qn)
        if not o or not n:
            print(f"REFUSED {qn}: baseline={'yes' if o else 'no'} target={'yes' if n else 'no'}"); refused += 1; continue
        if o.type != n.type:
            print(f"REFUSED {qn}: type {o.type} in the baseline, {n.type} in the target"); refused += 1; continue
        if o.hash == n.hash:
            print(f"SAME    {qn}: already identical (version neutral compare)"); continue
        broken = sorted({s for s in strings(o.data) if QN_ONLY.match(s) and s.split(".")[0] in new.modules
                         and s not in new.docs and f"{s.split('.')[0]}.$DomainModel" in new.docs
                         and not _in_domain(new, s)})
        if broken and "--force" not in flags:
            print(f"REFUSED {qn}: names {', '.join(broken[:5])} which the target does not have (the update removed or "
                  f"renamed them); restore those first or --force"); refused += 1; continue
        todo.append((qn, o, n)); print(f"RESTORE {qn}: {o.type}, baseline content replaces the target's")
    if refused:
        print(f"restoreunit: refused, nothing written ({refused})"); return 2
    if not todo:
        print("restoreunit: nothing to do"); return 1
    if "--apply" not in flags:
        print(f"restoreunit: dry run, {len(todo)} document(s); rerun with --apply"); return 0
    for qn, o, n in todo:
        uid = uid_of(new, n)
        data = dict(o.data); data["$ID"] = n.data["$ID"]
        write_unit(new_p, uid, data)
    chk = Model.load(new_p)
    bad = [qn for qn, o, _ in todo if chk.docs[qn].hash != o.hash]
    if bad:
        print(f"restoreunit: FAILED to verify {', '.join(bad)}"); return 2
    print(f"restoreunit: restored {len(todo)} document(s), re-read and verified; run idcheck and mx check, then commit")
    return 0


def _in_domain(model, qn):
    """Module.Entity names live in the domain model, not in docs."""
    mod, name = qn.split(".", 1)
    dm = model.docs.get(f"{mod}.$DomainModel")
    return bool(dm) and any(e.get("Name") == name for e in (dm.data.get("Entities") or []) if isinstance(e, dict))


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
