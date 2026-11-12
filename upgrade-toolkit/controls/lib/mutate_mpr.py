#!/usr/bin/env python3
"""mutate_mpr.py: apply ONE seeded fault to a copy of an app's model (quality plan item 8, the replay harness).

    mutate_mpr.py FAULT SRC_APP_DIR OUT_DIR

FAULT is a JSON object (or the path of a file holding one), the format of faults.jsonl (one fault per line):
    {"id": "F01", "app": "...", "doc": "Module.Document", "op": "set" | "delete" | "replace_text",
     "path": "Attributes[Name=Qty]/Value/DefaultValue", "value": ..., "find": "...", "replace": "..."}

Path syntax: "/"-separated keys. A segment is KEY or KEY[Name=Value] (a list element whose Name is Value; more than one
[k=v] selects by all of them). The element must match exactly one list entry, or the path does not resolve. A path
through a value that is not there does not resolve either: nothing is created on the way, so a typo cannot silently
seed a fault somewhere else.

A path is resolved on the model a reader sees, bin/mprmodel.py's norm() projection: keys in SKIP_KEYS ($ID, GUID,
Location, ...) are not addressable, and a list's leading type marker is not an element. The change is then written into
the RAW BSON at the raw index, which counts the marker. A path through a list element is therefore tested by the
seeded-mutate-list-element control: the change must land on the element named in the path, not on its neighbour. The last segment of a "set" may be a missing key of an existing object: that creates the
key (a page that had no AllowedModuleRoles can gain one). Nothing else is created.

Ops:
  set           the value at PATH becomes VALUE. A Mendix list (a leading type marker, e.g. [3, ...]) keeps its marker;
                a new list gets marker 3, the one mkmodel.py writes.
  delete        the key or list element at PATH is removed.
  replace_text  every string under PATH: FIND becomes REPLACE. FIND must occur at least once.

Copy: only the .mpr and mprcontents/ (MPR v2 unit files) are copied, never javasource or the theme. OUT_DIR must not
exist. Read the document through bin/mprmodel.py (MPR v1 Unit.Contents, or MPR v2 mprcontents/ files), mutate the
decoded BSON, write it back in the same storage (the v1 row, or the v2 .mxunit file), then read the copy again and check
that the change is visible. A fault that changes nothing is an error, never a mutated copy.

Output on success:  mutated <id>: <doc> <path>: <old> -> <new>      (exit 0)
Exit: 0 mutated and verified; 1 the fault cannot be applied (no such document, path does not resolve, find text not
present, no change, or the re-read did not show the change; OUT_DIR is removed again); 2 usage (bad arguments, a fault
that is not a JSON object with the required fields, a source that holds no .mpr).
"""
import glob, json, os, re, shutil, sqlite3, sys, uuid

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "bin"))
try:
    import bson
    import mprmodel
except ImportError as e:  # noqa: BLE001
    sys.exit(f"mutate_mpr: needs the bson module and bin/mprmodel.py ({e})")

MISSING = object()
SEG = re.compile(r"^([^\[\]]+)((?:\[[^\[\]=]+=[^\[\]]*\])*)$")
SEL = re.compile(r"\[([^\[\]=]+)=([^\[\]]*)\]")
OPS = ("set", "delete", "replace_text")


class Fail(Exception):
    """The fault cannot be applied: exit 1, never a mutated copy."""


class Usage(Exception):
    """A bad fault or bad arguments: exit 2."""


def show(x, n=120):
    if x is MISSING:
        return "(absent)"
    s = json.dumps(x, default=str, sort_keys=True, ensure_ascii=False)
    return s if len(s) <= n else s[: n - 3] + "..."


def same(a, b):
    return json.dumps(a, default=str, sort_keys=True) == json.dumps(b, default=str, sort_keys=True)


def parse_path(p):
    if not isinstance(p, str) or not p:
        raise Usage("path must be a non-empty string")
    out = []
    for seg in p.split("/"):
        m = SEG.match(seg)
        if not m:
            raise Usage(f"path segment {seg!r} is not KEY or KEY[Name=Value]")
        out.append((m.group(1), SEL.findall(m.group(2))))
    return out


def is_marker(x):
    return isinstance(x, int) and not isinstance(x, bool)


def select(lst, sels, seg):
    """Index into the RAW list of the one element matching sels. The leading markers are not elements (norm drops
    them), so the candidates are the non-marker entries; the index returned is the raw one, the one to write."""
    hits = [i for i, x in enumerate(lst)
            if not is_marker(x) and isinstance(x, dict) and all(str(x.get(k)) == v for k, v in sels)]
    if len(hits) != 1:
        raise Fail(f"{seg}: {len(hits)} list elements match {sels} (need exactly one)")
    return hits[0]


def resolve(root, segs, path):
    """(container, key) addressed by the path, resolved the way mprmodel.norm projects a document (the model a fault
    path is written against): keys in SKIP_KEYS are not part of it, list markers are not elements. The container is
    the RAW dict or list the change must be written into. Raises Fail."""
    node = root
    for depth, (key, sels) in enumerate(segs):
        last = depth == len(segs) - 1
        if not isinstance(node, dict):
            raise Fail(f"path does not resolve: {path} (no object before {key})")
        if key in mprmodel.SKIP_KEYS:
            raise Fail(f"path does not resolve: {path} ({key} is not part of the model: mprmodel drops it)")
        if key not in node:
            if last and not sels:
                return node, key  # a missing last key: set creates it, delete / replace_text refuse it later
            raise Fail(f"path does not resolve: {path} ({key} is not there)")
        val = node[key]
        if sels:
            if not isinstance(val, list):
                raise Fail(f"path does not resolve: {path} ({key} is not a list)")
            i = select(val, sels, key)
            if last:
                return val, i
            node = val[i]
        else:
            if last:
                return node, key
            node = val
    raise Usage("empty path")


def get_value(root, segs, path):
    try:
        c, k = resolve(root, segs, path)
    except Fail:
        return MISSING
    if isinstance(c, dict):
        return c.get(k, MISSING)
    return c[k]


def encode_like(new, old):
    """A Mendix list keeps its type marker: [3, ...] (mkmodel.py's lst()). A list given without one gets the old one's,
    or 3 when there was none."""
    if isinstance(new, list) and not (new and is_marker(new[0])):
        marker = old[0] if isinstance(old, list) and old and is_marker(old[0]) else 3
        return [marker] + new
    return new


def strings_replaced(x, find, repl):
    """(new value, occurrences replaced) for every string under x."""
    if isinstance(x, dict):
        n, out = 0, {}
        for k, v in x.items():
            out[k], c = strings_replaced(v, find, repl)
            n += c
        return out, n
    if isinstance(x, list):
        n, out = 0, []
        for v in x:
            nv, c = strings_replaced(v, find, repl)
            out.append(nv)
            n += c
        return out, n
    if isinstance(x, str):
        c = x.count(find)
        return (x.replace(find, repl), c) if c else (x, 0)
    return x, 0


def first_string_with(x, find):
    if isinstance(x, dict):
        for v in x.values():
            s = first_string_with(v, find)
            if s is not None:
                return s
    elif isinstance(x, list):
        for v in x:
            s = first_string_with(v, find)
            if s is not None:
                return s
    elif isinstance(x, str) and find in x:
        return x
    return None


def snippet(s, find, width=40):
    i = s.find(find)
    lo, hi = max(0, i - width), min(len(s), i + len(find) + width)
    return ("..." if lo else "") + s[lo:hi] + ("..." if hi < len(s) else "")


def mpr_path(proj_dir):
    mprs = glob.glob(os.path.join(proj_dir, "*.mpr"))
    if len(mprs) != 1:
        raise Usage(f"{proj_dir}: expected exactly one .mpr, found {len(mprs)}")
    return mprs[0]


def v2_file(proj_dir, uid):
    want = {str(uuid.UUID(bytes_le=bytes(uid))).lower(), str(uuid.UUID(bytes=bytes(uid))).lower()}
    for f in glob.glob(os.path.join(proj_dir, "mprcontents", "**", "*.mxunit"), recursive=True):
        if os.path.basename(f)[:-7].lower() in want:
            return f
    return None


def write_unit(mpr, proj_dir, uid, data):
    """Write the unit back where mprmodel reads it: the v1 Contents column, else the v2 .mxunit file."""
    con = sqlite3.connect(mpr)
    try:
        cols = {r[1] for r in con.execute("pragma table_info(Unit)")}
        if "Contents" in cols:
            row = con.execute("select Contents from Unit where UnitID=?", (bytes(uid),)).fetchone()
            if row is not None and row[0] is not None:
                con.execute("update Unit set Contents=? where UnitID=?", (bson.encode(data), bytes(uid)))
                con.commit()
                return "v1 Unit.Contents"
    finally:
        con.close()
    f = v2_file(proj_dir, uid)
    if not f:
        raise Fail("the document's unit is in neither Unit.Contents nor an mprcontents/ file")
    with open(f, "wb") as fh:
        fh.write(bson.encode(data))
    return "v2 " + os.path.relpath(f, proj_dir)


def copy_app(src, out):
    if os.path.isfile(src) and src.endswith(".mpr"):
        src_dir, mpr_src = os.path.dirname(os.path.abspath(src)), src
    elif os.path.isdir(src):
        src_dir, mpr_src = os.path.abspath(src), mpr_path(src)
    else:
        raise Usage(f"{src}: no such app dir or .mpr")
    if os.path.exists(out):
        raise Usage(f"{out} exists: give a fresh OUT_DIR")
    os.makedirs(out)
    shutil.copy2(mpr_src, os.path.join(out, os.path.basename(mpr_src)))
    if os.path.isdir(os.path.join(src_dir, "mprcontents")):
        shutil.copytree(os.path.join(src_dir, "mprcontents"), os.path.join(out, "mprcontents"))
    return os.path.join(out, os.path.basename(mpr_src))


def apply(fault, out):
    """Mutate the copy in out. Returns the success line. Raises Fail (exit 1) or Usage (exit 2)."""
    fid = fault.get("id", "-")
    qn, op, path = fault["doc"], fault["op"], fault["path"]
    segs = parse_path(path)
    m = mprmodel.Model.load(out)
    doc = m.docs.get(qn)
    if doc is None:
        raise Fail(f"no document {qn} in the model ({len(m.docs)} documents read)")
    twins = [d for d in m.all_docs if d.qn == qn]
    note = f" (shares its name with {len(twins)} documents; the primary one is changed)" if len(twins) > 1 else ""
    uid = next((u for u, (_, _, d) in m.units.items() if d is doc.data), None)
    if uid is None:
        raise Fail(f"{qn}: its unit is not addressable")
    root = doc.data

    if op == "set":
        c, k = resolve(root, segs, path)
        old = c.get(k, MISSING) if isinstance(c, dict) else c[k]
        new = encode_like(fault["value"], old)
        if old is not MISSING and same(old, new):
            raise Fail(f"set changes nothing: {path} is already {show(old)}")
        c[k] = new
        expect = new
        line_old, line_new = show(old), show(new)
    elif op == "delete":
        c, k = resolve(root, segs, path)
        if isinstance(c, dict):
            if k not in c:
                raise Fail(f"delete: nothing at {path}")
            old = c.pop(k)
        else:
            old = c.pop(k)
        expect = MISSING
        line_old, line_new = show(old), "(deleted)"
    elif op == "replace_text":
        find, repl = fault["find"], fault["replace"]
        if not find:
            raise Usage("replace_text: find must not be empty")
        c, k = resolve(root, segs, path)
        target = c.get(k, MISSING) if isinstance(c, dict) else c[k]
        if target is MISSING:
            raise Fail(f"path does not resolve: {path}")
        new_target, count = strings_replaced(target, find, repl)
        if count == 0:
            raise Fail(f"find text not present under {path}: {find!r}")
        s = first_string_with(target, find)
        line_old, line_new = snippet(s, find), snippet(s.replace(find, repl), repl)
        c[k] = new_target
        expect = new_target
    else:
        raise Usage(f"unknown op {op!r}")

    # root is the decoded unit itself (the object m.units holds), so the mutation is already in it
    write_unit(out, os.path.dirname(os.path.abspath(out)), uid, root)

    # re-read the copy and check the change is visible
    m2 = mprmodel.Model.load(out)
    d2 = m2.docs.get(qn)
    if d2 is None:
        raise Fail(f"verify: {qn} is gone after the write")
    got = get_value(d2.data, segs, path)
    if op == "delete":
        ok = got is MISSING
    else:
        ok = got is not MISSING and same(got, expect)
    if not ok:
        raise Fail(f"verify: the re-read copy does not show the change at {path} (reads {show(got)})")
    return f"mutated {fid}: {qn} {path}: {line_old} -> {line_new}{note}"


def main(argv):
    if len(argv) != 4:
        raise Usage("usage: mutate_mpr.py FAULT_JSON|FAULT_FILE SRC_APP_DIR OUT_DIR")
    raw, src, out = argv[1], argv[2], argv[3]
    text = open(raw, encoding="utf-8").read() if os.path.isfile(raw) else raw
    try:
        fault = json.loads(text)
    except json.JSONDecodeError as e:
        raise Usage(f"fault is not JSON: {e}")
    if not isinstance(fault, dict):
        raise Usage("fault must be a JSON object")
    for key in ("doc", "op", "path"):
        if not isinstance(fault.get(key), str):
            raise Usage(f"fault has no string {key!r}")
    if fault["op"] not in OPS:
        raise Usage(f"fault op {fault['op']!r} is not one of {', '.join(OPS)}")
    if fault["op"] == "set" and "value" not in fault:
        raise Usage("a set fault needs a value")
    if fault["op"] == "replace_text" and not (isinstance(fault.get("find"), str) and isinstance(fault.get("replace"), str)):
        raise Usage("a replace_text fault needs string find and replace")
    mpr = copy_app(src, out)
    try:
        line = apply(fault, mpr)
    except Fail as e:
        shutil.rmtree(out, ignore_errors=True)
        print(f"mutate_mpr: {fault.get('id', '-')}: cannot apply: {e}", file=sys.stderr)
        return 1
    except Usage as e:
        shutil.rmtree(out, ignore_errors=True)
        print(f"mutate_mpr: {e}", file=sys.stderr)
        return 2
    print(line)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
