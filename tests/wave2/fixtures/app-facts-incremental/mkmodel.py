#!/usr/bin/env python3
# mkmodel.py -- build a synthetic MPR v2 model, its prepared catalog and the stub's describe
# bodies, for tests/wave2/test-app-facts-incremental.sh and tests/wave2/bench-app-sweep.sh.
#
#   python3 mkmodel.py <model-dir> <prep-catalog.db> <spec.tsv> [<captured-units-dir>]
#
# spec.tsv, one microflow per line:  <Name> <TAB> <version> <TAB> <folder or -> <TAB> <loops 1|0>
# All microflows live in MyFirstModule ($MKMODEL_MODULE renames it: same UnitID, new Name). <version> changes the unit's bytes (so its ContentsHash)
# and the MDL the stub mxcli "describes" for it; <folder> moves the unit without changing them.
#
# WHAT IS CAPTURED AND WHAT IS NOT. With <captured-units-dir> (tests/wave2/fixtures/
# mx-metadata-note), the module unit and the MyFirstLogic microflow are the real .mxunit bytes and
# real Unit-table container of a Mendix 11.15.0 model, so the UnitID -> qualified-name mapping is
# exercised on real BSON. Every other unit is synthetic BSON carrying only $Type, Name and
# Documentation. ContentsHash is base64(sha256(<unit bytes>)), the format mx-metadata-note.py units
# computes. The Unit table schema is the captured one, verbatim.
import base64, hashlib, os, shutil, sqlite3, struct, sys

md, prep, spec = sys.argv[1:4]
cap = sys.argv[4] if len(sys.argv) > 4 else None
MODNAME = os.environ.get("MKMODEL_MODULE", "MyFirstModule")   # another name = a renamed module
MOD = "16747dc6-b6b7-42ae-aabf-255dca2aeeaf"
ROOT = bytes.fromhex("4d827743a25b514b800e658754fc369b")      # the captured project root container
CAPTURED_MF = {"MyFirstLogic": "4a8475b3-14cb-4100-8963-58f2fd3a0be8"}
SCHEMA = """CREATE TABLE _MetaData (_FormatVersion INTEGER, _ProductVersion TEXT, _BuildVersion TEXT, _SchemaHash TEXT);
CREATE TABLE Unit
            (
                UnitID BLOB PRIMARY KEY NOT NULL,
                ContainerID BLOB,
                ContainmentName TEXT,
                TreeConflict LONG,
                ContentsHash TEXT,
                ContentsConflicts TEXT
            );"""


def blob(g):
    b = bytes.fromhex(g.replace("-", ""))
    return b[3::-1] + b[5:3:-1] + b[7:5:-1] + b[8:]


def uid(seed):
    h = hashlib.md5(seed.encode()).hexdigest()
    h = h[:12] + "4" + h[13:16] + "8" + h[17:]
    return f"{h[:8]}-{h[8:12]}-{h[12:16]}-{h[16:20]}-{h[20:32]}"


def bson(fields):
    body = b"".join(b"\x02" + k.encode() + b"\x00" + struct.pack("<i", len(v.encode()) + 1) + v.encode() + b"\x00"
                    for k, v in fields)
    return struct.pack("<i", len(body) + 5) + body + b"\x00"


flows = []
for line in open(spec, encoding="utf-8"):
    if not line.strip() or line.startswith("#"):
        continue
    name, ver, folder, loops = line.rstrip("\n").split("\t")
    flows.append((name, ver, None if folder == "-" else folder, loops == "1"))

units = []   # (uid, container blob, containment, bytes)
mod_bytes = open(os.path.join(cap, MOD + ".mxunit"), "rb").read() if cap and MODNAME == "MyFirstModule" else \
    bson([("$Type", "Projects$ModuleImpl"), ("Name", MODNAME)])
units.append((MOD, ROOT, "Modules", mod_bytes))
for f in sorted({f for _, _, f, _ in flows if f}):
    units.append((uid("folder:" + f), blob(MOD), "Folders", bson([("$Type", "Projects$Folder"), ("Name", f)])))
for name, ver, folder, _ in flows:
    cont = blob(uid("folder:" + folder)) if folder else blob(MOD)
    if cap and name in CAPTURED_MF:
        u, b = CAPTURED_MF[name], open(os.path.join(cap, CAPTURED_MF[name] + ".mxunit"), "rb").read()
    else:
        u, b = uid("mf:" + name), bson([("$Type", "Microflows$Microflow"), ("Name", name), ("Documentation", "v" + ver)])
    units.append((u, cont, "Documents", b))

os.makedirs(md, exist_ok=True)
mpr = os.path.join(md, "App.mpr")
if os.path.exists(mpr):
    os.unlink(mpr)
db = sqlite3.connect(mpr)
db.executescript(SCHEMA)
db.execute("insert into _MetaData values (2,'11.15.0','11.15.0','')")
shutil.rmtree(os.path.join(md, "mprcontents"), ignore_errors=True)
for u, c, n, b in units:
    db.execute("insert into Unit (UnitID, ContainerID, ContainmentName, ContentsHash) values (?,?,?,?)",
               (blob(u), c, n, base64.b64encode(hashlib.sha256(b).digest()).decode()))
    d = os.path.join(md, "mprcontents", u[:2], u[2:4])
    os.makedirs(d, exist_ok=True)
    open(os.path.join(d, u + ".mxunit"), "wb").write(b)
db.commit(); db.close()

# What the stub mxcli prints for `describe <qn>`: a function of the unit's version, nothing else.
bodies = os.path.join(md, "stub-bodies")
shutil.rmtree(bodies, ignore_errors=True); os.makedirs(bodies)
for name, ver, _, loops in flows:
    qn = MODNAME + "." + name
    inner = ("  loop $Item in $List\n    retrieve $Line from %s.Line;\n    log info node 'v%s' 'step';\n  end loop;\n"
             % (MODNAME, ver)) if loops else "  log info node 'v%s' 'no loop';\n" % ver
    open(os.path.join(bodies, qn + ".mdl"), "w").write(
        "create or modify microflow %s ()\nbegin\n%send;\n/\n" % (qn, inner))

# The prepared catalog the stub's graph-report drops in place: every table app-facts reads.
if os.path.exists(prep):
    os.unlink(prep)
c = sqlite3.connect(prep)
c.executescript("""
CREATE TABLE catalog_meta (Key TEXT, Value TEXT);
CREATE TABLE modules_data (Name TEXT, Source TEXT, AppStoreVersion TEXT, AppStoreGuid TEXT);
CREATE TABLE entities_data (QualifiedName TEXT, ModuleName TEXT, EntityType TEXT, AttributeCount INTEGER);
CREATE TABLE microflows_data (QualifiedName TEXT, ModuleName TEXT, Name TEXT, ActivityCount INTEGER, MicroflowType TEXT);
CREATE TABLE activities_data (MicroflowQualifiedName TEXT, ModuleName TEXT, ActivityType TEXT);
CREATE TABLE pages_data (QualifiedName TEXT, ModuleName TEXT);
CREATE TABLE scheduled_events_data (QualifiedName TEXT, ModuleName TEXT, Microflow TEXT, Enabled TEXT, IntervalSeconds INTEGER, RepeatDescription TEXT);
CREATE TABLE refs (SourceType TEXT, SourceName TEXT, TargetName TEXT, RefKind TEXT, ModuleName TEXT);
CREATE TABLE objects (QualifiedName TEXT, ModuleName TEXT, ObjectType TEXT);
CREATE TABLE projects (ProjectName TEXT, MendixVersion TEXT);
CREATE TABLE graph_dead_assets (QualifiedName TEXT, ObjectType TEXT, ModuleName TEXT);
INSERT INTO catalog_meta VALUES ('build_mode','full');
INSERT INTO modules_data VALUES ('MyFirstModule','','','');
INSERT INTO projects VALUES ('App','11.15.0');
INSERT INTO entities_data VALUES ('MyFirstModule.Line','MyFirstModule','PERSISTENT',3);
""")
names = [MODNAME + "." + n for n, _, _, _ in flows]
for (n, _, _, loops), qn in zip(flows, names):
    c.execute("INSERT INTO microflows_data VALUES (?,?,?,?,?)", (qn, MODNAME, n, 4, "MICROFLOW"))
    c.execute("INSERT INTO objects VALUES (?,?,?)", (qn, MODNAME, "MICROFLOW"))
    c.execute("INSERT INTO activities_data VALUES (?,?,?)", (qn, MODNAME, "ActionActivity"))
    if loops:
        c.execute("INSERT INTO activities_data VALUES (?,?,?)", (qn, MODNAME, "LoopedActivity"))
for a, b in zip(names, names[1:]):
    c.execute("INSERT INTO refs VALUES ('MICROFLOW',?,?,'call',?)", (a, b, MODNAME))
c.commit(); c.close()
