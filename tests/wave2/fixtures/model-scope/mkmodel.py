#!/usr/bin/env python3
"""mkmodel.py -- build and mutate a tiny SYNTHETIC MPR v2 model in a git repo, for
tests/wave2/test-model-scope.sh: the cases the one real capture (golden-v0.27.0/) does not
cover. The unit shape (ObjectCollection/Objects[n]/Action/RetrieveSource/XpathConstraint, the
Unit table, the ContentsHash index) and the XPath strings follow that capture.

    mkmodel.py init   DIR [--sub app]     repo + model (+ first commit); --sub puts the model in DIR/app
    mkmodel.py edit   DIR NAME MODE       rewrite a unit and re-index it, as mxcli would
    mkmodel.py delete DIR NAME            remove a unit file and its Unit row
    mkmodel.py add    DIR NAME MODULE     new unit file + Unit row (left untracked)
    mkmodel.py hashes DIR                 print 'clean' or the MISMATCH ids (index vs files)

MODE: ws        XPath line breaks removed (the incident)           -> noise
      literal   whitespace inside a quoted XPath literal changed   -> real
      wsfield   XPath whitespace AND a Caption change              -> real
      field     only a Caption change                              -> real
      reorder   two keys swapped                                   -> real

Units (container in brackets): Project P, ModuleA, ModuleB [P]; folder Sub [ModuleA];
MfA1 [Sub] two XPaths, PgA [ModuleA] page data source key 'XPathConstraint', MfA2 [ModuleA] none,
MfB1, MfB2 [ModuleB] XPaths, Nav [P] none. UnitIDs are uuid5 of the name, so runs are repeatable.
"""
import base64
import hashlib
import importlib.util
import os
import sqlite3
import subprocess
import sys
import uuid

HERE = os.path.dirname(os.path.abspath(__file__))
PB = os.path.abspath(os.path.join(HERE, "..", "..", "..", "..", "project-bin"))


def _load(name):
    spec = importlib.util.spec_from_file_location(name, os.path.join(PB, name + ".py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


bson = _load("mxunit_bson")
NS = uuid.UUID("6f1c1c1e-0000-4000-8000-000000000001")
XP_OLD = "[Label = 'A']\n[Flag != 'B']"   # verbatim from golden-v0.27.0/ (before / after the rename)
XP_NEW = "[Label = 'A'][Flag != 'B']"
LIT_OLD = "[Note = 'two  words']\n[Open = true]\n"
LIT_NEW = "[Note = 'two words'][Open = true]"


def uid(name):
    return uuid.uuid5(NS, name)


def S(k, v):
    return (0x02, k, v)


def D(k, v):
    return (0x03, k, v)


def A(k, items):
    return (0x04, k, [(0x10, "0", 3)] + [(0x03, str(i + 1), d) for i, d in enumerate(items)])


def mf(name, xpaths):
    objs = []
    for x in xpaths:
        objs.append([S("$Type", "Microflows$ActionActivity"),
                     D("Action", [S("$Type", "Microflows$RetrieveAction"),
                                  D("RetrieveSource", [S("$Type", "Microflows$DatabaseRetrieveSource"),
                                                       S("XpathConstraint", x)])])])
    return [S("$Type", "Microflows$Microflow"), S("Name", name),
            D("ObjectCollection", [S("$Type", "Microflows$MicroflowObjectCollection"), A("Objects", objs)]),
            S("Caption", name + " caption"), S("Documentation", "")]


def page(name, x):
    return [S("$Type", "Pages$Page"), S("Name", name), S("Caption", name),
            D("Content", [D("DataSource", [S("$Type", "Pages$ListViewXPathSource"), S("XPathConstraint", x)])])]


UNITS = [  # name, container, containment, doc
    ("P", "P", "", [S("$Type", "Projects$Project"), S("Name", "P")]),
    ("ModuleA", "P", "Modules", [S("$Type", "Projects$ModuleImpl"), S("Name", "ModuleA")]),
    ("ModuleB", "P", "Modules", [S("$Type", "Projects$ModuleImpl"), S("Name", "ModuleB")]),
    ("Sub", "ModuleA", "Folders", [S("$Type", "Projects$Folder"), S("Name", "Sub")]),
    ("MfA1", "Sub", "Documents", mf("MfA1", [XP_OLD, LIT_OLD])),
    ("PgA", "ModuleA", "Documents", page("PgA", XP_OLD)),
    ("MfA2", "ModuleA", "Documents", mf("MfA2", [])),
    ("MfB1", "ModuleB", "Documents", mf("MfB1", [XP_OLD])),
    ("MfB2", "ModuleB", "Documents", mf("MfB2", [XP_OLD, XP_OLD])),
    ("Nav", "P", "ProjectDocuments", [S("$Type", "Navigation$NavigationDocument"), S("Name", "Nav")]),
]


def h(data):
    return base64.b64encode(hashlib.sha256(data).digest()).decode()


def paths(root):
    mpr = [f for f in os.listdir(root) if f.endswith(".mpr")][0]
    return os.path.join(root, mpr), os.path.join(root, "mprcontents")


def unit_file(root, name):
    u = str(uid(name))
    return os.path.join(paths(root)[1], u[:2], u[2:4], u + ".mxunit")


def model_root(top):
    return os.path.join(top, "app") if os.path.isdir(os.path.join(top, "app")) else top


def git(top, *a):
    subprocess.check_call(["git", "-c", "user.email=t@t", "-c", "user.name=t"] + list(a), cwd=top,
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def put(root, name, doc, container, containment, db):
    p = unit_file(root, name)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    raw = bson.enc_doc(doc)
    with open(p, "wb") as fh:
        fh.write(raw)
    db.execute("INSERT OR REPLACE INTO Unit VALUES (?,?,?,?,?,?)",
               (uid(name).bytes_le, uid(container).bytes_le, containment, 0, h(raw), ""))


def cmd_init(top, sub):
    os.makedirs(top, exist_ok=True)
    root = os.path.join(top, sub) if sub else top
    os.makedirs(root, exist_ok=True)
    subprocess.check_call(["git", "init", "-q", top])
    db = sqlite3.connect(os.path.join(root, "App.mpr"))
    db.execute("CREATE TABLE _MetaData (_FormatVersion INTEGER, _ProductVersion TEXT, _BuildVersion TEXT, _SchemaHash TEXT)")
    db.execute("INSERT INTO _MetaData VALUES (2,'10.24.18','10.24.18.1','x')")
    db.execute("CREATE TABLE Unit (UnitID BLOB PRIMARY KEY NOT NULL, ContainerID BLOB, ContainmentName TEXT, "
               "TreeConflict LONG, ContentsHash TEXT, ContentsConflicts TEXT)")
    for name, cont, containment, doc in UNITS:
        put(root, name, doc, cont, containment, db)
    db.commit()
    db.close()
    git(top, "add", "-A")
    git(top, "commit", "-qm", "model")


def mutate(doc, mode):
    """In place; returns True when something changed."""
    changed = False
    for i, (t, k, v) in enumerate(doc):
        if t in (0x03, 0x04):
            changed |= mutate(v, mode)
        elif k.lower() == "xpathconstraint" and t == 0x02:
            if mode in ("ws", "wsfield") and v == XP_OLD:
                doc[i] = (t, k, XP_NEW)
                changed = True
            elif mode == "literal" and v == LIT_OLD:
                doc[i] = (t, k, LIT_NEW)
                changed = True
        elif k == "Caption" and mode in ("wsfield", "field") and t == 0x02:
            doc[i] = (t, k, v + " changed")
            changed = True
    if mode == "reorder" and len(doc) >= 4 and doc[0][1] == "$Type" and doc[-1][1] == "Documentation":
        doc[-2], doc[-1] = doc[-1], doc[-2]
        changed = True
    return changed


def cmd_edit(root, name, mode):
    p = unit_file(root, name)
    doc = bson.load(p)
    if not mutate(doc, mode):
        sys.exit("mode %s changes nothing in %s" % (mode, name))
    raw = bson.enc_doc(doc)
    with open(p, "wb") as fh:
        fh.write(raw)
    db = sqlite3.connect(paths(root)[0])
    db.execute("UPDATE Unit SET ContentsHash=? WHERE UnitID=?", (h(raw), uid(name).bytes_le))
    db.commit()
    db.close()


def cmd_delete(root, name):
    os.remove(unit_file(root, name))
    db = sqlite3.connect(paths(root)[0])
    db.execute("DELETE FROM Unit WHERE UnitID=?", (uid(name).bytes_le,))
    db.commit()
    db.close()


def cmd_add(root, name, module):
    db = sqlite3.connect(paths(root)[0])
    put(root, name, mf(name, []), module, "Documents", db)
    db.commit()
    db.close()


def cmd_hashes(root):
    db = sqlite3.connect(paths(root)[0])
    bad = []
    for u, hh in db.execute("SELECT UnitID, ContentsHash FROM Unit"):
        s = str(uuid.UUID(bytes_le=bytes(u)))
        p = os.path.join(paths(root)[1], s[:2], s[2:4], s + ".mxunit")
        if os.path.isfile(p) and h(open(p, "rb").read()) != hh:
            bad.append(s)
    print("clean" if not bad else " ".join(sorted(bad)))


def main(a):
    cmd, top = a[0], a[1]
    if cmd == "init":
        return cmd_init(top, a[3] if len(a) > 3 and a[2] == "--sub" else "")
    root = model_root(top)
    if cmd == "edit":
        return cmd_edit(root, a[2], a[3])
    if cmd == "delete":
        return cmd_delete(root, a[2])
    if cmd == "add":
        return cmd_add(root, a[2], a[3])
    if cmd == "hashes":
        return cmd_hashes(root)
    sys.exit("unknown command " + cmd)


if __name__ == "__main__":
    main(sys.argv[1:])
