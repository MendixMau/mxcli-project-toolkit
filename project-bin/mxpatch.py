#!/usr/bin/env python3
"""mxpatch.py -- the shared core of a targeted .mxunit patch (#294).

WHY THIS EXISTS. A patch for something MDL cannot express (a widget inside a pluggable
container, a workflow activity's Caption, a node mxcli never emits) needs the same layer
every time: find the unit, find the element, read or set one value, write the unit back,
and keep the .mpr's ContentsHash index in step. Field report #294: 9 of 12 Python change
scripts on one production app re-implemented that layer, and two different helper
libraries grew in one project. The toolkit's own two patchers wrote the unit and never
touched the index -- every --apply left a stale ContentsHash for Studio Pro to trip on,
which `mx check` and mxbuild cannot see (mxcli `fix hashes --help`, v0.26.0: "'mx check'
does not notice; Studio Pro uses the index to decide what changed").

THE HASH. An MPR v2 .mpr indexes each mprcontents/**/<uuid>.mxunit by
base64(SHA-256(file bytes)) in Unit.ContentsHash, keyed by the UnitID blob in .NET GUID
byte order. Verified, not assumed: identical to the stored value on all 27 units of the
captured fixture model (tests/wave2/fixtures/mxpatch/) and all 369 of mxcli's pedapp test
model, and on mxcli's expr-checker model it flags exactly the 67 units `mxcli fix hashes`
v0.26.0 flags as MISMATCH. write_unit() updates the row in the same transaction as the
file swap, so a patch never leaves the index behind. `bin/exec.sh --patch` then runs
`mxcli fix hashes` (v0.25.0+) as an independent check after the script exits 0.

LIBRARY (what a patch script imports -- it lives beside this file):

    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import mxpatch
    m = mxpatch.Model(sys.argv[1])                 # .mpr, its directory, or a unit file in it
    u = m.find_unit("Workflows$Workflow", "Approval", module="MyFirstModule")
    act = mxpatch.find_element(u.doc, "ACT_Approval_Review", "Workflows$CallMicroflowActivity")
    mxpatch.set_value(act, "Caption", "Review", expect="ACT_Approval_Review")
    m.write_unit(u, apply=args.apply)             # dry run unless apply=True

    set_value() returns "changed" or "already" (the new value is already there: a re-run is a
    no-op) and raises Drift when the current value is neither the expected old one nor the new
    one -- the model is not the one the patch was written against, so it refuses.
    write_unit() returns "written", "dry-run" or "already" (encoded bytes identical to disk).

CLI (dry run unless --apply; exit 0 ok/already/dry-run, 2 usage, 3 drift, 4 not found or
ambiguous, 5 hash index problem):

    mxpatch.py find   <model.mpr> --type T [--name N] [--module M]
    mxpatch.py get    <model.mpr> --type T --name N [--module M] [--element E [--element-type ET]] --key K
    mxpatch.py set    <model.mpr> --type T --name N [--module M] [--element E [--element-type ET]] \\
                      --key K --value V [--expect OLD] [--apply]
    mxpatch.py verify <model.mpr>           # every unit file against its ContentsHash (no mxcli needed)
    mxpatch.py rehash <model.mpr> <unit.mxunit>... [--apply]   # re-index units another tool wrote

Run a write under `./bin/exec.sh --patch <script> [args...]` -- snapshot, mxbuild gate,
`fix hashes` verify, restore on failure. It receives the .mpr as its first argument.
NEVER write while Studio Pro has the model open, or while the app runs.

SCOPE. MPR v2 only (an MPR v1 keeps units inside the .mpr; refused). Values of type string,
boolean, int32, int64 and double can be set; anything else is refused rather than guessed.
Not here yet (#294's field-data half): copying a widget's shape from a known-good sibling,
and pluggable-widget properties addressed by PropertyKey -- both wait on a captured page unit.

BACKUPS. write_unit(backup=True) keeps the old bytes of the unit OUTSIDE mprcontents/, in
$MXPATCH_BACKUP_DIR (exec.sh --patch points it into the snapshot it just took, so the backup
is pruned with it), else <tempdir>/mxpatch-bak-<uid>/<model>/ (created 0700). Until
2026-10-15 it was
<unit>.mxunit.bak beside the unit: untracked in the model folder, and one
`git add mprcontents` from being committed (field run, #390).

Stdlib only (sqlite3, hashlib, base64): runs under any python3 on mac, Linux and Git Bash.
"""
import base64
import glob
import hashlib
import os
import sqlite3
import stat
import struct
import sys
import tempfile
import time
import uuid

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mxunit_bson import dec_doc, enc_doc  # noqa: E402


class PatchError(Exception):
    code = 1


class Drift(PatchError):
    code = 3


class NotFound(PatchError):
    code = 4


class IndexProblem(PatchError):
    code = 5


_UNSET = object()


def contents_hash(data):
    """Unit.ContentsHash for a unit file's bytes: base64(SHA-256(bytes))."""
    return base64.b64encode(hashlib.sha256(data).digest()).decode("ascii")


def uid_blob(unit_path):
    """The Unit.UnitID blob for a unit file: its file-name UUID in .NET GUID byte order."""
    name = os.path.basename(unit_path)
    if not name.endswith(".mxunit"):
        raise PatchError("not a .mxunit file: %s" % unit_path)
    return uuid.UUID(name[: -len(".mxunit")]).bytes_le


def _atomic_write(path, data):
    """Write `data` to `path` through <path>.mxpatch-tmp + os.replace, so `path` is always
    either the old bytes or the new ones. A failed temp write removes the temp file."""
    tmp = path + ".mxpatch-tmp"
    try:
        with open(tmp, "wb") as fh:
            fh.write(data)
        os.replace(tmp, path)
    except BaseException:
        if os.path.exists(tmp):
            os.remove(tmp)
        raise


def _private_tmp():
    """<tempdir>/mxpatch-bak-<uid>, created 0700 and checked to be ours and not a symlink; a
    shared, predictable /tmp/mxpatch-bak is open to other local users (#374 review). Anything
    else found there: a fresh mkdtemp (0700) instead."""
    me = os.getuid() if hasattr(os, "getuid") else None
    tag = str(me) if me is not None else (os.environ.get("USERNAME") or os.environ.get("USER") or "user")
    base = os.path.join(tempfile.gettempdir(), "mxpatch-bak-%s" % tag)
    try:
        os.mkdir(base, 0o700)
    except FileExistsError:
        pass
    st = os.lstat(base)
    if stat.S_ISDIR(st.st_mode) and not stat.S_ISLNK(st.st_mode) and (me is None or st.st_uid == me):
        if me is not None and (st.st_mode & 0o077):
            os.chmod(base, 0o700)
        return base
    return tempfile.mkdtemp(prefix="mxpatch-bak-")


def _bson_str(t, key, value):
    e = value.encode("utf-8")
    return bytes([t]) + key.encode("utf-8") + b"\x00" + struct.pack("<i", len(e) + 1) + e + b"\x00"


def get(doc, key, default=None):
    """Value of `key` in an order-preserving [(type, key, value)] document."""
    for _t, k, v in doc:
        if k == key:
            return v
    return default


def is_doc(x):
    return isinstance(x, list) and all(isinstance(e, tuple) and len(e) == 3 for e in x)


def walk(node):
    """Every document inside `node`, depth first, `node` itself included."""
    if is_doc(node):
        yield node
        for _t, _k, v in node:
            for d in walk(v):
                yield d
    elif isinstance(node, list):
        for v in node:
            for d in walk(v):
                yield d


def find_elements(doc, name=None, type_=None):
    """Every element below the unit root whose Name / $Type match (None = any)."""
    out = []
    for d in walk(doc):
        if d is doc:
            continue
        if name is not None and get(d, "Name") != name:
            continue
        if type_ is not None and get(d, "$Type") != type_:
            continue
        out.append(d)
    return out


def find_element(doc, name, type_=None):
    """Exactly one element named `name` (optionally of `type_`), else NotFound."""
    hits = find_elements(doc, name, type_)
    what = name + (" (%s)" % type_ if type_ else "")
    if not hits:
        raise NotFound("no element named %s in this unit" % what)
    if len(hits) > 1:
        types = sorted({get(h, "$Type") for h in hits})
        raise NotFound("%d elements named %s (%s) -- narrow it with an element type"
                       % (len(hits), what, ", ".join(types)))
    return hits[0]


def _coerce(t, key, value):
    if t == 0x02:
        return str(value)
    if t == 0x08:
        if isinstance(value, bool):
            return value
        s = str(value).lower()
        if s in ("true", "false"):
            return s == "true"
    elif t in (0x10, 0x12):
        if not isinstance(value, bool):
            try:
                return int(value)
            except (TypeError, ValueError):
                pass
    elif t == 0x01:
        try:
            return float(value)
        except (TypeError, ValueError):
            pass
    else:
        raise PatchError("key %r holds BSON type 0x%02x, which mxpatch does not set" % (key, t))
    raise PatchError("key %r is BSON type 0x%02x; cannot store %r there" % (key, t, value))


def get_entry(doc, key):
    for i, (t, k, v) in enumerate(doc):
        if k == key:
            return i, t, v
    raise NotFound("no key %r on this element (%s)" % (key, get(doc, "$Type")))


def set_value(doc, key, new, expect=_UNSET):
    """Set `key` to `new` in place, keeping its position and BSON type.

    Returns "changed" or "already". Raises Drift when `expect` is given and the current
    value is neither `expect` nor `new`: the model is not the one the patch was written for."""
    i, t, cur = get_entry(doc, key)
    new = _coerce(t, key, new)
    if cur == new:
        return "already"
    if expect is not _UNSET and cur != _coerce(t, key, expect):
        raise Drift("refusing: %s.%s is %r, the patch expected %r (to set %r) -- the model "
                    "differs from the one this patch was written against"
                    % (get(doc, "$Type"), key, cur, expect, new))
    doc[i] = (t, key, new)
    return "changed"


class Unit(object):
    __slots__ = ("path", "uid", "raw", "doc")

    def __init__(self, path, raw):
        self.path, self.uid, self.raw = path, uid_blob(path), raw
        self.doc, end = dec_doc(raw, 0)
        if end != len(raw):
            raise PatchError("trailing bytes after the BSON document in %s" % path)

    @property
    def type(self):
        return get(self.doc, "$Type")

    @property
    def name(self):
        return get(self.doc, "Name")


class Model(object):
    """An MPR v2 model: the .mpr (sqlite, the ContentsHash index) plus mprcontents/."""

    def __init__(self, path):
        self.mpr = self._locate(os.path.abspath(path))
        self.root = os.path.dirname(self.mpr)
        self.contents = os.path.join(self.root, "mprcontents")
        if not os.path.isdir(self.contents):
            raise PatchError("%s has no mprcontents/ beside it: an MPR v1 model keeps its units inside "
                             "the .mpr, and mxpatch patches MPR v2 only" % self.mpr)
        self._parents = None

    @staticmethod
    def _locate(p):
        if os.path.isfile(p) and p.lower().endswith(".mpr"):
            return p
        d = p if os.path.isdir(p) else os.path.dirname(p)
        if p.lower().endswith(".mxunit"):        # a unit file: the model is beside its mprcontents/
            while d and os.path.basename(d) != "mprcontents":
                up = os.path.dirname(d)
                d = "" if up == d else up
            if not d:
                raise PatchError("%s is not under an mprcontents/ directory" % p)
            d = os.path.dirname(d)
        mprs = sorted(glob.glob(os.path.join(d, "*.mpr")))
        if len(mprs) != 1:
            raise PatchError("expected one .mpr in %s, found %d" % (d, len(mprs)))
        return mprs[0]

    # -- the index -----------------------------------------------------------------------
    def _db(self):
        return sqlite3.connect(self.mpr, timeout=5)

    def unit_path(self, uid):
        u = str(uuid.UUID(bytes_le=bytes(uid)))
        return os.path.join(self.contents, u[:2], u[2:4], u + ".mxunit")

    def unit_files(self):
        return sorted(glob.glob(os.path.join(self.contents, "*", "*", "*.mxunit")))

    def stored_hash(self, uid):
        db = self._db()
        try:
            row = db.execute("SELECT ContentsHash FROM Unit WHERE UnitID = ?", (bytes(uid),)).fetchone()
        finally:
            db.close()
        if row is None:
            raise IndexProblem("unit %s has no row in %s" % (uuid.UUID(bytes_le=bytes(uid)), self.mpr))
        return row[0]

    def verify(self):
        """[(kind, uuid, detail)] for every MISMATCH / MISSING / ORPHAN, mxcli fix hashes' kinds."""
        db = self._db()
        try:
            rows = [(bytes(u), h) for u, h in db.execute("SELECT UnitID, ContentsHash FROM Unit")]
        finally:
            db.close()
        out, indexed = [], set()
        for uid, stored in rows:
            p = self.unit_path(uid)
            indexed.add(os.path.normcase(p))
            name = str(uuid.UUID(bytes_le=uid))
            if not os.path.isfile(p):
                # The project root row and similar index-only rows have no file in some models;
                # mxcli reports those as MISSING too, so the same rule applies here.
                out.append(("MISSING", name, "indexed, no file"))
                continue
            have = contents_hash(open(p, "rb").read())
            if have != stored:
                out.append(("MISMATCH", name, "stored %s, file %s" % (stored, have)))
        for p in self.unit_files():
            if os.path.normcase(p) not in indexed:
                out.append(("ORPHAN", os.path.basename(p)[:-7], "file, not indexed"))
        return out

    # -- lookup ----------------------------------------------------------------------------
    def load(self, path):
        return Unit(path, open(path, "rb").read())

    def units(self, type_=None, name=None):
        """Units whose top-level $Type / Name match. A byte search on the encoded strings runs
        first, so only candidate files are decoded (a 17,500-unit model decodes a handful)."""
        needles = []
        if type_ is not None:
            needles.append(_bson_str(0x02, "$Type", type_))
        if name is not None:
            needles.append(_bson_str(0x02, "Name", name))
        for p in self.unit_files():
            raw = open(p, "rb").read()
            if any(n not in raw for n in needles):
                continue
            u = Unit(p, raw)
            if (type_ is None or u.type == type_) and (name is None or u.name == name):
                yield u

    def module_of(self, unit):
        """The name of the module a unit sits in (walks Unit.ContainerID), or None."""
        if self._parents is None:
            db = self._db()
            try:
                self._parents = {bytes(u): (bytes(c) if c is not None else None, n)
                                 for u, c, n in db.execute("SELECT UnitID, ContainerID, ContainmentName FROM Unit")}
            finally:
                db.close()
        cur, seen = unit.uid, set()
        while cur is not None and cur not in seen:
            seen.add(cur)
            parent, containment = self._parents.get(cur, (None, None))
            if containment == "Modules":
                p = self.unit_path(cur)
                return self.load(p).name if os.path.isfile(p) else None
            cur = parent
        return None

    def find_unit(self, type_, name, module=None):
        """Exactly one unit of `type_` named `name` (in `module`, when given), else NotFound."""
        hits = [u for u in self.units(type_, name) if module is None or self.module_of(u) == module]
        where = "%s %s%s" % (type_, (module + ".") if module else "", name)
        if not hits:
            raise NotFound("no unit %s in %s" % (where, self.mpr))
        if len(hits) > 1:
            mods = sorted(str(self.module_of(u)) for u in hits)
            raise NotFound("%d units %s (modules: %s) -- pass the module" % (len(hits), where, ", ".join(mods)))
        return hits[0]

    # -- write -------------------------------------------------------------------------------
    def backup_dir(self):
        """Where write_unit(backup=True) keeps a unit's old bytes: $MXPATCH_BACKUP_DIR, else a
        private per-user dir under the temp dir (_private_tmp). Never inside mprcontents/
        (refused), where a backup is an untracked file in the model tree that
        `git add mprcontents` would commit."""
        model = os.path.splitext(os.path.basename(self.mpr))[0]
        d = os.environ.get("MXPATCH_BACKUP_DIR") or os.path.join(_private_tmp(), model)
        # realpath on both sides, so a symlink into mprcontents/ is seen through, and compared
        # lower-cased: on macOS and Windows "MPRCONTENTS/x" IS mprcontents/. Lower-casing on Linux
        # too only refuses more (a sibling spelled MPRCONTENTS), never less (#374 review).
        def key(p):
            return os.path.normcase(os.path.join(os.path.realpath(p), "")).lower()
        if key(d).startswith(key(self.contents)):
            raise PatchError("MXPATCH_BACKUP_DIR %s is inside %s: a backup there is an untracked file "
                             "in the model tree. Point it outside mprcontents/." % (d, self.contents))
        return os.path.abspath(d)

    def write_unit(self, unit, apply=False, backup=False, log=None):
        """Encode `unit.doc`, write it and set its ContentsHash, as one step.

        Returns "already" (encodes to the bytes on disk), "dry-run" or "written". The new hash
        is committed first and the file swapped in after it; see the ORDER comment below for
        the one crash window left and why a re-run repairs it."""
        log = log or (lambda s: print(s))
        blob = enc_doc(unit.doc)                 # encode first: an encoder error touches nothing
        if blob == unit.raw:
            log("already applied: %s is unchanged" % os.path.basename(unit.path))
            return "already"
        stored = self.stored_hash(unit.uid)
        if stored != contents_hash(unit.raw):
            log("note: the index was already stale for %s before this patch (stored %s); "
                "this write corrects it" % (os.path.basename(unit.path), stored))
        new_hash = contents_hash(blob)
        if not apply:
            log("dry run: would write %s (%d bytes, was %d) and set its ContentsHash to %s"
                % (os.path.basename(unit.path), len(blob), len(unit.raw), new_hash))
            return "dry-run"
        bak = None
        if backup:
            bdir = self.backup_dir()
            os.makedirs(bdir, exist_ok=True)
            # Timestamp + pid + a counter: two writes to one unit within a second must not
            # overwrite the first backup (#374 review).
            n = 0
            while True:
                bak = os.path.join(bdir, "%s.%s-%d-%d.bak" % (os.path.basename(unit.path),
                                   time.strftime("%Y%m%d-%H%M%S"), os.getpid(), n))
                if not os.path.exists(bak):
                    break
                n += 1
            _atomic_write(bak, unit.raw)
        # ORDER, chosen so that every crash state is one `mxcli fix hashes` reports and a re-run
        # repairs (#374 review): (1) commit the NEW hash to the index, (2) swap the file in with
        # os.replace. If (2) fails, the index row is put back to the old hash. The remaining
        # window is a kill between (1) and (2): the index then names bytes that are not on disk
        # yet, the file still holds the OLD unit intact. `fix hashes` reports that as MISMATCH
        # (exec.sh --patch restores the snapshot on it), and a re-run of the same patch finds the
        # old value and rewrites the file and the hash together (it logs "the index was already
        # stale"), so the model converges. The reverse order would leave the NEW file with the
        # old hash, which a re-run reads as "already applied" and never repairs.
        db = self._db()
        try:
            cur = db.execute("UPDATE Unit SET ContentsHash = ? WHERE UnitID = ?", (new_hash, unit.uid))
            if cur.rowcount != 1:
                db.rollback()
                raise IndexProblem("unit %s: %d index rows matched, expected 1"
                                   % (os.path.basename(unit.path), cur.rowcount))
            db.commit()
            try:
                _atomic_write(unit.path, blob)
            except BaseException:
                # The file is untouched (os.replace is atomic): put the index back with it.
                db.execute("UPDATE Unit SET ContentsHash = ? WHERE UnitID = ?", (stored, unit.uid))
                db.commit()
                raise
        finally:
            db.close()
        unit.raw = blob
        log("wrote %s (%d bytes) and its ContentsHash %s" % (os.path.basename(unit.path), len(blob), new_hash))
        if bak:
            log("backup (outside mprcontents/): %s" % bak)
        return "written"

    def rehash(self, paths, apply=False, log=None):
        """Set ContentsHash from the file on disk for units some other tool wrote."""
        log = log or (lambda s: print(s))
        n = 0
        db = self._db()
        try:
            for p in paths:
                uid, h = uid_blob(p), contents_hash(open(p, "rb").read())
                row = db.execute("SELECT ContentsHash FROM Unit WHERE UnitID = ?", (uid,)).fetchone()
                if row is None:
                    raise IndexProblem("%s has no row in the index" % os.path.basename(p))
                if row[0] == h:
                    continue
                n += 1
                log("%s %s: %s -> %s" % ("rehash" if apply else "would rehash", os.path.basename(p), row[0], h))
                if apply:
                    db.execute("UPDATE Unit SET ContentsHash = ? WHERE UnitID = ?", (h, uid))
            if apply:
                db.commit()
        finally:
            db.close()
        return n


def resolve_unit(args, type_):
    """A patcher's positional arguments -> (Model, Unit). Either `<unit.mxunit>` (run by hand),
    or `<model.mpr> <unit.mxunit | Module.Name>` -- the form `bin/exec.sh --patch` produces,
    since it passes the model first."""
    if len(args) == 1 and args[0].lower().endswith(".mxunit"):
        m = Model(args[0])
        u = m.load(os.path.abspath(args[0]))
    elif len(args) == 2 and args[0].lower().endswith(".mpr"):
        m = Model(args[0])
        if args[1].lower().endswith(".mxunit"):
            if os.path.normcase(Model(args[1]).mpr) != os.path.normcase(m.mpr):
                raise PatchError("%s is not a unit of %s" % (args[1], m.mpr))
            u = m.load(os.path.abspath(args[1]))
        elif "." in args[1]:
            mod, name = args[1].split(".", 1)
            u = m.find_unit(type_, name, mod)
        else:
            raise PatchError("%r is neither a .mxunit path nor a Module.Name" % args[1])
    else:
        raise PatchError("expected <unit.mxunit>, or <model.mpr> <unit.mxunit | Module.Name>")
    if u.type != type_:
        raise PatchError("%s is a %s, not a %s" % (os.path.basename(u.path), u.type, type_))
    return m, u


# -- CLI -----------------------------------------------------------------------------------
def _opts(argv):
    pos, kv, flags = [], {}, set()
    i = 0
    while i < len(argv):
        a = argv[i]
        if a in ("--apply",):
            flags.add(a)
        elif a.startswith("--") and i + 1 < len(argv):
            kv[a] = argv[i + 1]
            i += 1
        elif a.startswith("--"):
            raise PatchError("%s needs a value" % a)
        else:
            pos.append(a)
        i += 1
    return pos, kv, flags


def _target(m, kv):
    if "--type" not in kv or "--name" not in kv:
        raise PatchError("--type and --name are required")
    u = m.find_unit(kv["--type"], kv["--name"], kv.get("--module"))
    el = u.doc
    if "--element" in kv:
        el = find_element(u.doc, kv["--element"], kv.get("--element-type"))
    return u, el


def main(argv):
    if len(argv) < 2 or argv[0] in ("-h", "--help"):
        print(__doc__)
        return 0 if argv[:1] in (["-h"], ["--help"]) else 2
    cmd = argv[0]
    pos, kv, flags = _opts(argv[1:])
    apply_ = "--apply" in flags
    if not pos or not pos[0].lower().endswith((".mpr", ".mxunit")) and not os.path.isdir(pos[0]):
        raise PatchError("usage: mxpatch.py %s <model.mpr> ... (no model path given; --help for all forms)" % cmd)
    m = Model(pos[0])
    if cmd == "find":
        hits = list(m.units(kv.get("--type"), kv.get("--name")))
        if "--module" in kv:
            hits = [u for u in hits if m.module_of(u) == kv["--module"]]
        for u in hits:
            print("%s\t%s.%s\t%s" % (u.type, m.module_of(u), u.name, os.path.relpath(u.path, m.root)))
        return 0 if hits else 4
    if cmd == "get":
        _u, el = _target(m, kv)
        _i, t, v = get_entry(el, kv["--key"])
        print(v if t != 0x08 else ("true" if v else "false"))
        return 0
    if cmd == "set":
        u, el = _target(m, kv)
        if "--value" not in kv or "--key" not in kv:
            raise PatchError("set needs --key and --value")
        _i, _t, old = get_entry(el, kv["--key"])
        r = set_value(el, kv["--key"], kv["--value"], kv.get("--expect", _UNSET))
        if r == "already":
            print("already applied, skipped: %s is already %r" % (kv["--key"], old))
            return 0
        print("%s: %r -> %r" % (kv["--key"], old, get(el, kv["--key"])))
        r = m.write_unit(u, apply=apply_)
        if r == "dry-run":
            print("Dry run. Re-run with --apply to write.")
        return 0
    if cmd == "verify":
        probs = m.verify()
        for kind, name, detail in probs:
            print("  %-9s %s  %s" % (kind, name, detail))
        c = lambda k: sum(1 for p in probs if p[0] == k)  # noqa: E731
        print("%d mismatch(es), %d missing file(s), %d orphan file(s)." % (c("MISMATCH"), c("MISSING"), c("ORPHAN")))
        return 5 if probs else 0
    if cmd == "rehash":
        n = m.rehash(pos[1:], apply=apply_)
        print("%d unit(s) %s" % (n, "rehashed" if apply_ else "to rehash (dry run; --apply writes)"))
        return 0
    raise PatchError("unknown command %r (find, get, set, verify, rehash)" % cmd)


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except PatchError as e:
        sys.stderr.write("mxpatch: %s\n" % e)
        sys.exit(e.code if e.code != 1 else 2)
