#!/usr/bin/env python3
"""copy_mappings.py: CE1571 "No argument has been selected": copy the call's parameter mappings from a reference page.

Why (T2-4, T2R3-7): a 9.x page calls a microflow with implicit arguments (empty ParameterMappings). `mx convert` to 10
makes them explicit, but only for a flow it can read: a flow in a protected ADD-ON module (`modules/*.mxmodule`, a vendor
binary that is not in app.mpr) keeps an empty list, and mx check says CE1571. mxcli cannot repair it either: `alter page
... set DataSource = microflow M(Param = $x)` prints "Altered page" and saves no mapping, because it cannot read M's
parameters (Opcenter, batch 1 and T2R3: ClientConfiguration_NewEdit.dataView1, twice). Both runs fixed it by copying the
ParameterMappings of the same call from the publisher's newer page with a hand-written BSON script (dvfix.py). This is
that script, for any page and any call.

  copy_mappings.py <app dir|.mpr> --page Module.Page --ref <ref dir|.mpr> [--ref-page Module.Page] [--widget NAME]
                   [--replace] [--apply]
  copy_mappings.py <app dir|.mpr> --scan

Call sites are matched like convertcheck.py --mappings keys them: the names of the named widgets down to the call, plus
the called flow or page (`ClientConfiguration_NewEdit/dataView1:EXFN_Authentication.SUB_GetDefaultClientConfiguration`).
A site is copied only when the reference calls the SAME flow at the same widget path with a non-empty mapping:
  COPY      target empty, reference mapped: the reference's mappings with fresh $IDs (--apply writes them)
  SAME      already equal (the $IDs aside)
  DIFFERS   both mapped, differently: left alone unless --replace (never overwritten silently)
  NOREF     empty to a flow outside the model and the reference maps nothing there: stays open (exit 1)
--widget limits the sites to those whose widget path holds that name. Dry run by default: nothing is written without
--apply. The page itself must be in app.mpr: a page of an add-on module is REFUSED (exit 2; a vendor binary, neither
mxcli nor this tool can change it: get the vendor's newer build, playbooks/10-to-11.md row 9). A site whose flow lives
outside the model (add-on or missing module) is marked "flow outside the model": that is the case mxcli cannot fix.
--scan lists, without a reference, every call site of the app with an empty mapping whose flow is outside the model
(the CE1571 candidates mxcli cannot repair); empty is legal for a flow without parameters, so they are CANDIDATEs only.

Writes MPR v1 (Unit.Contents + ContentsHash) and v2 (mprcontents/*.mxunit). Refuses (exit 2) a unit whose BSON does not
re-encode byte for byte, so nothing else in the page can change. Commit before; after --apply run mx check (CE1571 gone)
and convertcheck.py --mappings (the copied mapping must map the data view's object where it sits inside one).
Exit: 0 = nothing to do or all written, 1 = COPY pending (dry run), DIFFERS left alone, NOREF, or --scan candidates,
2 = input error (page or reference page not found, page in an add-on, no site matched, unsafe BSON).
"""
import argparse, base64, copy, glob, hashlib, os, re, sqlite3, sys, tempfile, uuid, zipfile

import bson
from bson.binary import Binary

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from mprunits import unit_rows  # noqa: E402

FLOW_KEYS = ("Microflow", "Nanoflow", "Form", "Page")   # the same keys as convertcheck.call_sites
DOC_TYPES = ("Forms$Page", "Forms$Snippet", "Forms$Layout")
MODULE_TYPES = ("Projects$ModuleImpl", "Projects$Module")


# ------------------------------------------------------------------ model access (raw units, v1 and v2)
class Mpr:
    """Raw units of one MPR: uid -> (container uid, blob, mxunit file or None)."""

    def __init__(self, path):
        if os.path.isdir(path):
            mprs = glob.glob(os.path.join(path, "*.mpr"))
            if len(mprs) != 1:
                raise ValueError(f"{path}: expected exactly one .mpr, found {len(mprs)}")
            path = mprs[0]
        if not os.path.isfile(path):
            raise ValueError(f"{path}: no such project")
        self.path, self.proj = path, os.path.dirname(os.path.abspath(path))
        self.con = sqlite3.connect(path)
        try:
            self.cols = {r[1] for r in self.con.execute("pragma table_info(Unit)")}
        except sqlite3.DatabaseError as e:
            raise ValueError(f"{path}: not an MPR ({e})")
        if not self.cols:
            raise ValueError(f"{path}: not an MPR (no Unit table)")
        v2 = {os.path.basename(f)[:-7].lower(): f
              for f in glob.glob(os.path.join(self.proj, "mprcontents", "**", "*.mxunit"), recursive=True)}
        self.rows, self.docs = {}, {}
        q = "select UnitID, ContainerID, " + ("Contents" if "Contents" in self.cols else "NULL") + " from Unit"
        for uid, cid, blob in self.con.execute(q):
            f = None
            if blob is None and v2:
                f = v2.get(str(uuid.UUID(bytes_le=bytes(uid))).lower()) or v2.get(str(uuid.UUID(bytes=bytes(uid))).lower())
                blob = open(f, "rb").read() if f else None
            if blob:
                self.rows[bytes(uid)] = (bytes(cid) if cid else None, bytes(blob), f)
        self.modules = set()
        self._dec = {}
        for uid, (cid, blob, f) in self.rows.items():
            d = self.decode(uid)
            if d is None:
                continue
            if d.get("$Type") in MODULE_TYPES:
                self.modules.add(d.get("Name"))
        for uid in self.rows:
            d = self.decode(uid)
            if d and d.get("$Type") in DOC_TYPES and d.get("Name"):
                mod = self.module_of(uid)
                if mod:
                    self.docs[f"{mod}.{d['Name']}"] = uid

    def decode(self, uid):
        if uid not in self._dec:
            try:
                self._dec[uid] = bson.decode(self.rows[uid][1])
            except Exception:
                self._dec[uid] = None
        return self._dec[uid]

    def module_of(self, uid):
        cid = self.rows[uid][0]
        for _ in range(50):
            if cid not in self.rows:
                return None
            d = self.decode(cid) or {}
            if d.get("$Type") in MODULE_TYPES:
                return d.get("Name")
            cid = self.rows[cid][0]
        return None

    def write(self, uid, new):
        cid, old, f = self.rows[uid]
        if f:
            with open(f, "wb") as fh:
                fh.write(new)
        else:
            self.con.execute("update Unit set Contents=? where UnitID=?", (new, uid))
        if "ContentsHash" in self.cols:
            self.con.execute("update Unit set ContentsHash=? where UnitID=?",
                             (base64.b64encode(hashlib.sha256(new).digest()).decode(), uid))
        self.con.commit()
        self.rows[uid] = (cid, new, f)
        self._dec.pop(uid, None)


def addon_modules(project):
    """{module name lower case: add-on file} for modules/*.mxmodule and .mendix-cache/modules/*.mxmodule (T2-2, T2R3-6).
    The file name gives the module name; a readable inner project.mpr adds the module names inside it (T2R3-2: some
    vendor add-ons hold a project.mpr that is not sqlite, so the file name is the reliable part)."""
    out = {}
    for f in sorted(glob.glob(os.path.join(project, "modules", "*.mxmodule"))
                    + glob.glob(os.path.join(project, ".mendix-cache", "modules", "*.mxmodule"))):
        rel = os.path.relpath(f, project)
        out.setdefault(os.path.basename(f)[:-9].lower(), rel)
        if not os.path.isfile(f):
            continue
        try:
            with tempfile.TemporaryDirectory() as d, zipfile.ZipFile(f) as z:
                inner = [n for n in z.namelist() if n.lower().endswith(".mpr")]
                if not inner:
                    continue
                p = os.path.join(d, "inner.mpr")
                with open(p, "wb") as fh:
                    fh.write(z.read(inner[0]))
                for n in z.namelist():  # NR2-10: a v2 package keeps its units in mprcontents/
                    if n.startswith("mprcontents/") and n.endswith(".mxunit"):
                        z.extract(n, d)
                for _uid, _cid, blob in unit_rows(p):
                    try:
                        u = bson.decode(blob) if blob else {}
                    except Exception:
                        continue
                    if u.get("$Type") in MODULE_TYPES and u.get("Name"):
                        out.setdefault(u["Name"].lower(), rel)
        except (OSError, zipfile.BadZipFile, sqlite3.Error, KeyError):
            continue
    return out


def outside(m, addons, qn):
    """'' when the module of qualified name qn is in the model, else why mxcli cannot read it."""
    mod = (qn or "").split(".")[0]
    if not mod or mod in m.modules or mod == "System":
        return ""
    if mod.lower() in addons:
        return f"flow outside the model: {mod} is an add-on ({addons[mod.lower()]})"
    return f"flow outside the model: module {mod} is not in app.mpr"


# ------------------------------------------------------------------ call sites
def sites(doc):
    """[(key, dict holding ParameterMappings, target)] in one page/snippet/layout; keys as convertcheck.call_sites."""
    out, seen = [], set()

    def walk(o, names):
        if isinstance(o, dict):
            n = o.get("Name") if isinstance(o.get("Name"), str) else None
            names2 = names + [n] if n else names
            if "ParameterMappings" in o:
                tgt = next((str(o[k]) for k in FLOW_KEYS if o.get(k)), "?")
                key = "/".join(names2) + ":" + tgt
                i = 1
                while key in seen:
                    i += 1
                    key = "/".join(names2) + ":" + tgt + f"#{i}"
                seen.add(key)
                out.append((key, o, tgt))
            for v in o.values():
                walk(v, names2)
        elif isinstance(o, list):
            for v in o:
                walk(v, names)

    walk(doc, [])
    return out


def maps(o):
    return [x for x in (o.get("ParameterMappings") or []) if isinstance(x, dict)]


def strip_ids(x):
    if isinstance(x, dict):
        return {k: strip_ids(v) for k, v in x.items() if k != "$ID"}
    if isinstance(x, list):
        return [strip_ids(v) for v in x]
    return x


def fresh_ids(x):
    if isinstance(x, dict):
        for k, v in list(x.items()):
            if k == "$ID":
                raw = uuid.uuid4().bytes
                x[k] = Binary(raw, v.subtype) if isinstance(v, Binary) else raw
            else:
                fresh_ids(v)
    elif isinstance(x, list):
        for v in x:
            fresh_ids(v)
    return x


def show(pms):
    parts = []
    for p in pms:
        par = str(p.get("Parameter", "?")).split(".")[-1]
        var = p.get("Variable") if isinstance(p.get("Variable"), dict) else {}
        val = p.get("Argument") or p.get("Expression") or var.get("PageParameter") or var.get("Widget") or "?"
        if var.get("PageParameter") and not p.get("Argument"):
            val = "$" + str(val).split(".")[-1]
        parts.append(f"{par} = {val}")
    return ", ".join(parts) or "(none)"


# ------------------------------------------------------------------ main
def die(msg):
    print(f"copy_mappings: {msg}", file=sys.stderr)
    sys.exit(2)


def scan(m, addons):
    n = 0
    for qn, uid in sorted(m.docs.items()):
        for key, o, tgt in sites(m.decode(uid)):
            why = outside(m, addons, tgt)
            if why and not maps(o):
                n += 1
                print(f"CANDIDATE {qn}: {key} (empty mapping; {why})")
    print(f"summary: {n} call site(s) with an empty mapping to a flow outside the model"
          + ("; mx check CE1571 names the ones that need arguments: copy_mappings.py --page ... --ref <publisher app>" if n else ""))
    return 1 if n else 0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("app"); ap.add_argument("--page"); ap.add_argument("--ref"); ap.add_argument("--ref-page")
    ap.add_argument("--widget"); ap.add_argument("--replace", action="store_true")
    ap.add_argument("--apply", action="store_true"); ap.add_argument("--scan", action="store_true")
    a = ap.parse_args()
    try:
        m = Mpr(a.app)
    except (ValueError, sqlite3.Error) as e:
        die(str(e))
    addons = addon_modules(m.proj)
    if a.scan:
        sys.exit(scan(m, addons))
    if not a.page or not a.ref:
        die("give --page Module.Page and --ref <reference app or .mpr> (or --scan)")
    mod = a.page.split(".")[0]
    if mod not in m.modules:
        if mod.lower() in addons:
            die(f"REFUSED {a.page}: module {mod} is a protected add-on ({addons[mod.lower()]}), not in {os.path.basename(m.path)}; "
                "a vendor binary cannot be changed by mxcli or by this tool: get the vendor's newer build "
                "(playbooks/10-to-11.md row 9) or call the flow from a page in an own module")
        die(f"{a.page}: module {mod} is not in {os.path.basename(m.path)}")
    if a.page not in m.docs:
        die(f"{a.page}: no page, snippet or layout of that name in {m.path}")
    try:
        r = Mpr(a.ref)
    except (ValueError, sqlite3.Error) as e:
        die(f"--ref {e}")
    rpage = a.ref_page or a.page
    if rpage not in r.docs:
        die(f"{rpage}: not in the reference {r.path}")
    uid = m.docs[a.page]
    orig = m.rows[uid][1]
    doc = m.decode(uid)
    if bson.encode(doc) != orig:
        die(f"{a.page}: its unit does not re-encode byte for byte; not edited (report it with the Mendix version)")
    ref_sites = {k: (o, t) for k, o, t in sites(r.decode(r.docs[rpage]))}
    mine = [(k, o, t) for k, o, t in sites(doc) if not a.widget or a.widget in k.split(":")[0].split("/")]
    if not mine:
        die(f"{a.page}: no call site" + (f" under a widget named {a.widget}" if a.widget else ""))
    todo, differs, noref = [], 0, 0
    for key, o, tgt in mine:
        why = outside(m, addons, tgt)
        note = f" ({why})" if why else ""
        ro = ref_sites.get(key, (None,))[0]
        rm, tm = (maps(ro) if ro is not None else []), maps(o)
        if not rm:
            if not tm and why:   # the CE1571 case with nothing to copy from: stays open, never a silent pass
                noref += 1
                print(f"NOREF     {key}: empty, and the reference has " + ("no mapping either" if ro is not None else
                      f"no call to {tgt} at this widget path") + f"{note}; a flow without parameters is fine, "
                      "else find a reference that maps it or call it from an own wrapper flow")
            continue
        if strip_ids(rm) == strip_ids(tm):
            print(f"SAME      {key}: {show(tm)}")
            continue
        if tm and not a.replace:
            differs += 1
            print(f"DIFFERS   {key}: app {show(tm)} | reference {show(rm)}; left alone (--replace to take the reference's)")
            continue
        print(f"COPY      {key}: {show(tm)} -> {show(rm)}{note}")
        todo.append((key, o, ro))
    if a.apply and todo:
        for _, o, ro in todo:
            # keep the list's leading type marker (2/3); take the reference's when the app's list has none
            marker = [x for x in (o.get("ParameterMappings") or []) + (ro.get("ParameterMappings") or [])
                      if not isinstance(x, dict)][:1]
            o["ParameterMappings"] = marker + [fresh_ids(copy.deepcopy(x)) for x in maps(ro)]
        new = bson.encode(doc)
        bson.decode(new)  # still valid BSON
        m.write(uid, new)
        check = Mpr(m.path)
        got = {k: maps(o) for k, o, _ in sites(check.decode(check.docs[a.page]))}
        bad = [k for k, _, ro in todo if strip_ids(got.get(k)) != strip_ids(maps(ro))]
        if bad:
            print(f"copy_mappings: written but re-read differs at {', '.join(bad)}", file=sys.stderr); sys.exit(1)
        print(f"written: {len(todo)} site(s) in {a.page}; now mx check (CE1571 gone) and convertcheck.py --mappings")
    print(f"summary: {len(todo)} to copy, {differs} differ, {noref} empty to a flow outside the model without a reference mapping"
          + ("" if a.apply or not todo else "; dry run, nothing written (--apply)"))
    sys.exit(1 if (todo and not a.apply) or differs or noref else 0)


if __name__ == "__main__":
    main()
