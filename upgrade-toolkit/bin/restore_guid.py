#!/usr/bin/env python3
"""restore_guid.py: give a replayed domain model element its original runtime GUID back, so its data survives.

Why (E1 19): the runtime maps tables and columns by the element's GUID field (mendixsystem$attribute.id), not by name.
A DomainModels$Attribute holds `$ID` and a separate `GUID`; MDL `ADD ATTRIBUTE` (a local-edit replay) sets both to a
new uuid, so idcheck says GUID_CHANGED and the runtime does DROP column + ADD column: the data is gone. Writing the old
GUID back makes the replay data-safe.

  restore_guid.py <app.mpr> <Module.Entity.Attribute | Module.Entity | Module.Association> (<guid> | --from <old.mpr>) [--dry-run]

--from reads the GUID the element has in the old MPR (the original app). Edits only the 16 bytes of that element's
GUID field (same length, the BSON stays valid) and updates ContentsHash (base64 sha256 of the unit, MPR v1) or the
mprcontents/*.mxunit file (MPR v2). Commit before and run idcheck after (old vs new must no longer list the element).
Exit: 0 = restored (or already equal), 1 = not done, 2 = element or GUID field not found / input error.
"""
import argparse, base64, glob, hashlib, os, sqlite3, struct, sys, uuid

import bson


def load(path):
    proj = os.path.dirname(os.path.abspath(path))
    con = sqlite3.connect(path)
    cols = {r[1] for r in con.execute("pragma table_info(Unit)")}
    v2 = {os.path.basename(f)[:-7].lower(): f
          for f in glob.glob(os.path.join(proj, "mprcontents", "**", "*.mxunit"), recursive=True)}
    rows = {}
    q = "select UnitID, ContainerID, " + ("Contents" if "Contents" in cols else "NULL") + " from Unit"
    for uid, cid, blob in con.execute(q):
        f = None
        if blob is None and v2:
            f = v2.get(str(uuid.UUID(bytes_le=bytes(uid))).lower())
            blob = open(f, "rb").read() if f else None
        if blob:
            rows[bytes(uid)] = (bytes(cid) if cid else None, bytes(blob), f)
    return con, cols, rows


def module_name(rows, cid):
    for _ in range(50):
        if cid not in rows:
            return None
        parent, blob, _ = rows[cid]
        d = bson.decode(blob)
        if d.get("$Type") in ("Projects$ModuleImpl", "Projects$Module"):
            return d.get("Name")
        cid = parent
    return None


def find(rows, qname):
    parts = qname.split(".")
    mod = parts[0]
    for uid, (cid, blob, f) in rows.items():
        d = bson.decode(blob)
        if d.get("$Type") != "DomainModels$DomainModel" or module_name(rows, cid) != mod:
            continue
        if len(parts) == 2:
            for coll in ("Entities", "Associations", "CrossAssociations"):
                for e in d.get(coll) or []:
                    if isinstance(e, dict) and e.get("Name") == parts[1]:
                        return uid, e
        if len(parts) == 3:
            for e in d.get("Entities") or []:
                if isinstance(e, dict) and e.get("Name") == parts[1]:
                    for a in e.get("Attributes") or []:
                        if isinstance(a, dict) and a.get("Name") == parts[2]:
                            return uid, a
    return None, None


def as_bytes(v):
    if isinstance(v, uuid.UUID):
        return v.bytes_le
    return bytes(v) if v is not None else None


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("mpr"); ap.add_argument("element"); ap.add_argument("guid", nargs="?")
    ap.add_argument("--from", dest="src"); ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    if bool(a.guid) == bool(a.src):
        sys.exit("restore_guid: give a guid or --from <old.mpr>")
    if a.src:
        _, _, srows = load(a.src)
        _, old = find(srows, a.element)
        if old is None or as_bytes(old.get("GUID")) is None:
            print(f"restore_guid: {a.element} (or its GUID field) not in {a.src}", file=sys.stderr); sys.exit(2)
        want = as_bytes(old["GUID"])
    else:
        try:
            want = uuid.UUID(a.guid).bytes_le
        except ValueError:
            print(f"restore_guid: {a.guid!r} is not a uuid", file=sys.stderr); sys.exit(2)
    con, cols, rows = load(a.mpr)
    uid, el = find(rows, a.element)
    if el is None:
        print(f"restore_guid: {a.element} not found in {a.mpr}", file=sys.stderr); sys.exit(2)
    have = as_bytes(el.get("GUID"))
    if have is None or len(have) != 16:
        print(f"restore_guid: {a.element} has no 16-byte GUID field", file=sys.stderr); sys.exit(2)
    show = lambda b: str(uuid.UUID(bytes_le=b))
    if have == want:
        print(f"restore_guid: {a.element} already has GUID {show(want)}"); sys.exit(0)
    _, blob, f = rows[uid]
    needle = b"\x05GUID\x00" + struct.pack("<i", 16) + b"\x00" + have
    if blob.count(needle) != 1:
        print(f"restore_guid: GUID field of {a.element} found {blob.count(needle)} times in its unit; not edited",
              file=sys.stderr); sys.exit(1)
    new = blob.replace(needle, needle[:-16] + want)
    bson.decode(new)  # still valid BSON
    print(f"{a.element}: GUID {show(have)} -> {show(want)} ($ID unchanged)")
    if a.dry_run:
        sys.exit(0)
    if f:
        open(f, "wb").write(new)
    else:
        con.execute("update Unit set Contents=? where UnitID=?", (new, uid))
    if "ContentsHash" in cols:
        con.execute("update Unit set ContentsHash=? where UnitID=?",
                    (base64.b64encode(hashlib.sha256(new).digest()).decode(), uid))
    con.commit()
    print("written; now run idcheck old vs this MPR")


if __name__ == "__main__":
    main()
