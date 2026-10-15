#!/usr/bin/env python3
# mx-metadata-note.py -- write the Studio Pro revision note (refs/notes/mx_metadata) for commits
# made outside Studio Pro, WITH the list of changed documents.
#
#   bin/mx-metadata-note.py changes  [<commit>]          # print the ModelChanges JSON array
#   bin/mx-metadata-note.py write    [<commit>] [--force] # write that commit's note
#   bin/mx-metadata-note.py backfill [<rev-range>] [--dry-run] [--force]
#   bin/mx-metadata-note.py sync     <remote>            # publish: fetch + merge the remote's notes, then push
#   bin/mx-metadata-note.py units    <path-to.mpr> [--hashes-only]  # working-tree unit list (app-facts.sh)
#   (git push never carries the notes -- run sync after pushing the branch)
#   (all take --mpr <path-from-git-top> when there is more than one candidate .mpr)
#   Run it as "$PY" bin/mx-metadata-note.py, PY from _common.sh's resolve_py -- never through the
#   shebang: on Windows "python3" is often the Microsoft Store stub.
#
# A note whose ModelChanges is already non-empty is Studio Pro's (or an earlier run's) and is left
# alone; --force recomputes it. sync never lets our note replace a colleague's non-empty one.
#
# WHY (2026-10-12, field project). Studio Pro's History pane does not read the changed documents
# from the commit. It reads the "ModelChanges" array of the commit's git note in
# refs/notes/mx_metadata, which Studio Pro writes when IT commits. Everything else (mxcli, agents,
# people at a shell) wrote that note by hand from platform-link.md trap 6c with
# "ModelChanges":[], so 270 of 270 notes on the field project showed "Model changes 0", and the
# "which microflow, which page" history was gone for every CLI commit.
#
# HOW. MPR v2 keeps one BSON file per document under <mpr dir>/mprcontents/xx/yy/<uuid>.mxunit,
# and the document tree (ContainerID) in the .mpr's SQLite Unit table. A commit's changed
# documents are its changed .mxunit files; $Type and Name are top-level BSON strings; the module
# is the first Projects$ModuleImpl up the ContainerID chain, in that commit's own .mpr. Entry
# shape is Studio Pro's, field for field:
#   {"Status":"Added|Modified|Deleted","UnitID":..,"UnitType":..,"UnitName":..,"Module":..}
# Project-level units (ProjectSecurity, Navigation) carry "" for UnitName and Module, as Studio
# Pro writes them.
#
# MEASURED, not assumed: against Studio Pro's own notes on 51 Studio Pro commits in 5 local apps,
# 3387 of 3389 entries reproduce exactly on all five fields. The misses: 2 entries Studio Pro
# listed whose .mxunit did not change in git, and 21 extra entries on commits whose PARENT was a
# CLI commit -- Studio Pro diffs against its own last state, not the git parent. Field run: 158
# notes backfilled on a 357-commit field app, pushed, and Studio Pro 11.15 History shows them (screenshot
# confirmed by the user, 2026-10-12).
#
# PRODUCER/CONSUMER. Reads only git objects -- no working tree, no mxcli, no mxbuild -- except
# `units`, which reads the working-tree model for project-bin/app-facts.sh (its incremental loop
# sweep and its freshness line in bin/status.sh); one UnitID -> name mapping serves both. Run by the
# post-commit / post-rewrite hooks bin/install-project-hooks.sh installs (init-project.sh and
# sync-project.sh run that installer). Studio Pro is the consumer. Never blocks a commit: every
# failure prints one warning and exits 0, because a missing note costs a History entry and a
# refused commit costs work.
#
# Stdlib only (sqlite3, json, subprocess): runs under any python3 on mac, Linux and Git Bash.

import base64, hashlib, json, os, re, sqlite3, struct, subprocess, sys, tempfile, urllib.parse

REF = "mx_metadata"
STATUS = {"A": "Added", "M": "Modified", "D": "Deleted"}
UNIT_RE = re.compile(r"([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\.mxunit$")


def git(*args, binary=False, check=True):
    r = subprocess.run(["git", *args], capture_output=True, check=check)
    return r.stdout if binary else r.stdout.decode("utf-8", "replace")


def top_level_strings(b, keys=("$Type", "Name")):
    """Read top-level string fields of a BSON document, skipping every other value by length.
    Handles every BSON element type, so no unit can make it raise on an unexpected value."""
    out, i, end = {}, 4, struct.unpack_from("<i", b, 0)[0] - 1
    fixed = {0x01: 8, 0x06: 0, 0x07: 12, 0x08: 1, 0x09: 8, 0x0A: 0, 0x10: 4, 0x11: 8, 0x12: 8,
             0x13: 16, 0x7F: 0, 0xFF: 0}
    while i < end:
        t = b[i]; i += 1
        j = b.index(b"\x00", i); k = b[i:j].decode("utf-8", "replace"); i = j + 1
        if t in (0x02, 0x0D, 0x0E):                      # string, JS code, symbol
            n = struct.unpack_from("<i", b, i)[0]
            if k in keys and t == 0x02:
                out[k] = b[i + 4:i + 3 + n].decode("utf-8", "replace")
            i += 4 + n
        elif t in (0x03, 0x04, 0x0F):                    # document, array, code-with-scope
            i += struct.unpack_from("<i", b, i)[0]
        elif t == 0x05:                                  # binary
            i += 5 + struct.unpack_from("<i", b, i)[0]
        elif t == 0x0B:                                  # regex: two cstrings
            i = b.index(b"\x00", b.index(b"\x00", i) + 1) + 1
        elif t == 0x0C:                                  # DBPointer
            i += 4 + struct.unpack_from("<i", b, i)[0] + 12
        elif t in fixed:
            i += fixed[t]
        else:
            raise ValueError(f"unknown BSON type 0x{t:02x} at key {k!r}")
    return out


def guid(blob):
    """SQLite Unit table GUIDs are .NET byte order (first three groups little-endian)."""
    b = bytes(blob)
    h = (b[3::-1] + b[5:3:-1] + b[7:5:-1] + b[8:]).hex()
    return f"{h[:8]}-{h[8:12]}-{h[12:16]}-{h[16:20]}-{h[20:]}"


def find_mpr(arg=None):
    """The .mpr path relative to the git top level, symlinks resolved (two-tree layout keeps
    app/App.mpr with a root symlink, and git stores the symlink, not the model)."""
    top = git("rev-parse", "--show-toplevel").strip()
    if arg:
        cands = [os.path.join(top, arg) if not os.path.isabs(arg) else arg]
    else:
        cands = [os.path.join(top, f) for f in sorted(os.listdir(top)) if f.endswith(".mpr")]
        if not cands and os.path.isdir(os.path.join(top, "app")):
            cands = [os.path.join(top, "app", f) for f in sorted(os.listdir(os.path.join(top, "app")))
                     if f.endswith(".mpr")]
    real = sorted({os.path.realpath(c) for c in cands if os.path.exists(c)})
    if len(real) != 1:
        raise SystemExit(f"mx-metadata-note: expected one .mpr, found {len(real)} -- pass --mpr <path>")
    return os.path.relpath(real[0], os.path.realpath(top)).replace(os.sep, "/")


def unit_table(path):
    """{UnitID: (ContainerID, ContentsHash)} from an .mpr's Unit table, opened read-only."""
    uri = "file:" + urllib.parse.quote(os.path.abspath(path).replace(os.sep, "/"), safe="/:") + "?mode=ro"
    db = sqlite3.connect(uri, uri=True)
    try:
        cols = {r[1] for r in db.execute("pragma table_info(Unit)")}
        hcol = "ContentsHash" if "ContentsHash" in cols else "NULL"
        return {guid(u): ((guid(c) if c else None), h or "")
                for u, c, h in db.execute(f"select UnitID, ContainerID, {hcol} from Unit")}
    finally:
        db.close()


class Model:
    """The document tree of one model: the .mpr Unit table plus the unit bodies. Rev reads it
    as it stood at a commit (git objects only); Tree reads the working tree (app-facts.sh's
    incremental sweep and its freshness line). module_of/qualified_name are the one mapping
    from a UnitID to the name Studio Pro and mxcli show."""

    def __init__(self, mpr):
        self.mpr = mpr
        self._units, self._table = {}, None

    def table(self):
        if self._table is None:
            self._table = self._read_table()
        return self._table

    def parent_of(self, uid):
        row = self.table().get(uid)
        return row[0] if row else None

    def unit(self, uid):
        if uid not in self._units:
            b = self._unit_bytes(uid)
            self._units[uid] = top_level_strings(b) if b else {}
        return self._units[uid]

    def module_of(self, uid):
        seen, cur = set(), uid
        while cur and cur not in seen:
            seen.add(cur)
            d = self.unit(cur)
            if d.get("$Type") == "Projects$ModuleImpl":
                return d.get("Name", "")
            cur = self.parent_of(cur)
        return ""

    def folder_path(self, uid):
        """Names of the containers between the module and the unit, outermost first."""
        names, seen, cur = [], {uid}, self.parent_of(uid)
        while cur and cur not in seen:
            seen.add(cur)
            d = self.unit(cur)
            if d.get("$Type") != "Projects$Folder":
                break
            names.append(d.get("Name", ""))
            cur = self.parent_of(cur)
        return list(reversed(names))


class Rev(Model):
    """The model as it stood at one commit."""

    def __init__(self, rev, mpr):
        super().__init__(mpr)
        self.rev = rev
        self.contents = (os.path.dirname(mpr) + "/mprcontents").lstrip("/")

    def _read_table(self):
        fd, path = tempfile.mkstemp(suffix=".mpr")
        try:
            with os.fdopen(fd, "wb") as f:
                f.write(git("show", f"{self.rev}:{self.mpr}", binary=True))
            return unit_table(path)
        finally:
            os.unlink(path)

    def _unit_bytes(self, uid):
        path = f"{self.contents}/{uid[:2]}/{uid[2:4]}/{uid}.mxunit"
        r = subprocess.run(["git", "show", f"{self.rev}:{path}"], capture_output=True)
        return r.stdout if r.returncode == 0 else None


class Tree(Model):
    """The model in the working tree: <mpr> and <mpr dir>/mprcontents. MPR v2 only -- a v1
    model keeps its units inside the .mpr, and the caller falls back to a full sweep."""

    def __init__(self, mpr):
        super().__init__(mpr)
        self.contents = os.path.join(os.path.dirname(os.path.abspath(mpr)), "mprcontents")
        if not os.path.isdir(self.contents):
            raise SystemExit(f"mx-metadata-note units: {self.contents} not found (MPR v1 model?)")

    def _read_table(self):
        return unit_table(self.mpr)

    def _unit_bytes(self, uid):
        try:
            with open(os.path.join(self.contents, uid[:2], uid[2:4], uid + ".mxunit"), "rb") as f:
                return f.read()
        except OSError:
            return None


def units(mpr, hashes_only=False):
    """One TSV line per unit of the working-tree model: UnitID, content hash and, unless
    hashes_only, UnitType, qualified name (Module.Name, "" for a unit outside a module) and the
    folder path (Module/Folder/.../Name).

    The hash has the Unit table's ContentsHash format, base64(sha256(<the .mxunit bytes>)), and
    is computed from the bytes. The column normally holds that same value, but nothing guarantees
    a row is rewritten in the same moment as its file (a save in progress, a checkout of the two
    at different states), and a stale row would hide a change. The bytes are what
    `mxcli describe` reads, so they win; the column is the fallback for a unit with no file, and
    each disagreement is counted on stderr."""
    t = Tree(mpr)
    out, stale = sys.stdout, 0
    for uid in sorted(t.table()):
        h = t.table()[uid][1]
        b = t._unit_bytes(uid)
        if b is not None:
            fh = base64.b64encode(hashlib.sha256(b).digest()).decode()
            stale += bool(h) and h != fh
            h = fh
        if hashes_only:
            out.write(f"{uid}\t{h}\n")
            continue
        d = t.unit(uid)
        mod, name = t.module_of(uid), d.get("Name", "")
        qn = f"{mod}.{name}" if mod and name and d.get("$Type") != "Projects$ModuleImpl" else ""
        path = "/".join([mod] + t.folder_path(uid) + [name]) if qn else ""
        out.write(f"{uid}\t{h}\t{d.get('$Type', '')}\t{qn}\t{path}\n")
    if stale:
        print(f"{stale} unit(s) whose Unit-table ContentsHash disagrees with the .mxunit bytes; the bytes were used",
              file=sys.stderr)
    return 0


def model_changes(commit, mpr):
    parents = git("rev-list", "--parents", "-n1", commit).split()[1:]
    if not parents:
        return []
    contents = (os.path.dirname(mpr) + "/mprcontents").lstrip("/")
    diff = git("diff", "--name-status", "--no-renames", parents[0], commit, "--", contents)
    revs, out = {}, []
    for line in diff.splitlines():
        st, path = line.split("\t", 1)
        m = UNIT_RE.search(path)
        if not m:
            continue
        uid = m.group(1)
        side = parents[0] if st == "D" else commit       # a deleted unit is read where it last lived
        rev = revs.setdefault(side, Rev(side, mpr))
        d = rev.unit(uid)
        out.append({"Status": STATUS.get(st[0], "Modified"), "UnitID": uid,
                    "UnitType": d.get("$Type", ""), "UnitName": d.get("Name", ""),
                    "Module": rev.module_of(uid)})
    return out


def modeler_version(commit, mpr):
    fd, path = tempfile.mkstemp(suffix=".mpr")
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(git("show", f"{commit}:{mpr}", binary=True))
        db = sqlite3.connect(path)
        try:
            return db.execute("select * from _MetaData").fetchone()[1]
        finally:
            db.close()
    finally:
        os.unlink(path)


def touches_model(commit, mpr):
    contents = (os.path.dirname(mpr) + "/mprcontents").lstrip("/")
    return bool(git("diff-tree", "--no-commit-id", "--name-only", "-r", "--root", commit, "--", mpr, contents).strip())


def write_note(commit, mpr, dry=False, force=False):
    """Keep every key an existing note has (Studio Pro reads ModelerVersion from it); fill
    ModelChanges. A note that already lists changes is left alone unless force: Studio Pro diffs
    against its own last state, not the git parent, so its list is the authoritative one. A commit with no note gets one only if it touches the model -- a docs commit
    then shows in History exactly as Studio Pro would show it (Studio Pro falls back to the
    newest note for the version, platform-link.md trap 6c)."""
    commit = git("rev-parse", commit).strip()
    r = subprocess.run(["git", "notes", f"--ref={REF}", "show", commit], capture_output=True)
    if r.returncode == 0:
        try:
            note = json.loads(r.stdout)
        except ValueError:
            return f"{commit[:7]} existing note is not JSON -- left alone"
        if note.get("ModelChanges") and not force:
            return None
    elif touches_model(commit, mpr):
        branch = git("rev-parse", "--abbrev-ref", "HEAD", check=False).strip()
        note = {"BranchName": "" if branch == "HEAD" else branch,
                "ModelerVersion": modeler_version(commit, mpr), "ModelChanges": [],
                "RelatedStories": [], "isWebModelerCommit": False}
    else:
        return None
    changes = model_changes(commit, mpr)
    if note.get("ModelChanges") == changes and r.returncode == 0:
        return None
    note["ModelChanges"] = changes
    if not dry:
        subprocess.run(["git", "notes", f"--ref={REF}", "add", "-f", "-m",
                        json.dumps(note, separators=(",", ":")), commit], check=True, capture_output=True)
    return f"{commit[:7]} {len(changes):4} model changes"


def _ref_ok(ref):
    return subprocess.run(["git", "rev-parse", "-q", "--verify", ref], capture_output=True).returncode == 0


def _show(ref, commit):
    r = subprocess.run(["git", "notes", f"--ref={ref}", "show", commit], capture_output=True)
    return r.stdout if r.returncode == 0 else None


def _changes(raw):
    try:
        return bool(json.loads(raw).get("ModelChanges"))
    except (ValueError, AttributeError, TypeError):
        return False


def _fetch_remote(remote):
    """Fetch the remote's notes into refs/notes/<REF>-remote. True when the remote has notes,
    False when it has none (a fresh Team Server app, or no CLI/Studio Pro note pushed yet)."""
    git("update-ref", "-d", f"refs/notes/{REF}-remote", check=False)    # never merge a stale copy
    r = subprocess.run(["git", "fetch", "-q", remote, f"+refs/notes/{REF}:refs/notes/{REF}-remote"],
                       capture_output=True)
    if r.returncode == 0:
        return True
    ls = subprocess.run(["git", "ls-remote", "--exit-code", remote, f"refs/notes/{REF}"], capture_output=True)
    if ls.returncode == 2:                               # reachable, and no such ref
        return False
    raise SystemExit(f"mx-metadata-note sync: cannot fetch notes from {remote}: "
                     + r.stderr.decode("utf-8", "replace").strip())


def _merge_remote():
    """3-way merge refs/notes/<REF>-remote into ours. A note only one side changed takes that
    side's version. A note BOTH sides changed keeps ours (-s ours) -- unless theirs lists model
    changes: then theirs wins, so our computed notes never replace a colleague's non-empty one."""
    base = None
    if _ref_ok(f"refs/notes/{REF}"):
        base = git("merge-base", f"refs/notes/{REF}", f"refs/notes/{REF}-remote", check=False).strip() or None
    if base:
        git("update-ref", f"refs/notes/{REF}-base", base)
    try:
        subprocess.run(["git", "notes", f"--ref={REF}", "merge", "-q", "-s", "ours",
                        f"refs/notes/{REF}-remote"], check=True)
        kept = 0
        for line in git("notes", f"--ref={REF}-remote", "list").splitlines():
            blob, commit = line.split()
            theirs = git("cat-file", "blob", blob, binary=True)
            if not _changes(theirs) or _show(REF, commit) == theirs:
                continue
            if base and _show(f"{REF}-base", commit) == theirs:
                continue                                 # only we changed it (write --force): ours stands
            subprocess.run(["git", "notes", f"--ref={REF}", "add", "-f", "-C", blob, commit],
                           check=True, capture_output=True)
            kept += 1
        if kept:
            print(f"mx_metadata sync: kept {kept} colleague note(s) that list model changes over ours")
    finally:
        if base:
            git("update-ref", "-d", f"refs/notes/{REF}-base", check=False)


def sync(remote):
    """Publish the notes: fetch the remote's, merge, push ours -- never a force push. This is the
    ONLY way notes reach the remote; `git push` is left exactly as git and Studio Pro do it. A push
    rejected because the remote moved on in between is retried once after a fresh fetch + merge."""
    for attempt in (1, 2):
        if _fetch_remote(remote):
            _merge_remote()
        if not _ref_ok(f"refs/notes/{REF}"):
            print(f"mx_metadata sync: no notes on either side -- nothing to publish to {remote}")
            return 0
        r = subprocess.run(["git", "push", "-q", remote, f"refs/notes/{REF}:refs/notes/{REF}"],
                           capture_output=True)
        if r.returncode == 0:
            print(f"mx_metadata sync: refs/notes/{REF} published to {remote}")
            return 0
        err = r.stderr.decode("utf-8", "replace").strip()
        if attempt == 1:
            print(f"mx_metadata sync: notes push to {remote} rejected -- re-fetching and merging once more",
                  file=sys.stderr)
    raise SystemExit(f"mx-metadata-note sync: notes push to {remote} rejected twice; the branch push is "
                     f"unaffected. Run sync again in a moment. git said:\n{err}")


def main(argv):
    args = list(argv)
    dry, force = "--dry-run" in args, "--force" in args
    args = [a for a in args if a not in ("--dry-run", "--force")]
    mpr_arg = None
    if "--mpr" in args:
        i = args.index("--mpr"); mpr_arg = args[i + 1]; del args[i:i + 2]
    cmd = args.pop(0) if args else "help"
    if cmd == "units":
        hashes = "--hashes-only" in args
        args = [a for a in args if a != "--hashes-only"]
        if not args:
            raise SystemExit("usage: mx-metadata-note.py units <path-to.mpr> [--hashes-only]")
        return units(args[0], hashes)
    if cmd == "sync":
        if not args:
            raise SystemExit("usage: mx-metadata-note.py sync <remote>")
        return sync(args[0])
    if cmd not in ("changes", "write", "backfill"):
        print("usage: mx-metadata-note.py changes|write [<commit>] [--force] | backfill [<range>] [--dry-run] [--force] | sync <remote>  [--mpr <path>] | units <path-to.mpr> [--hashes-only]")
        return 2
    mpr = find_mpr(mpr_arg)
    if cmd == "changes":
        print(json.dumps(model_changes(git("rev-parse", args[0] if args else "HEAD").strip(), mpr), indent=1))
    elif cmd == "write":
        msg = write_note(args[0] if args else "HEAD", mpr, dry, force)
        if msg:
            print(f"mx_metadata note: {msg}")
    else:
        n = 0
        for c in git("rev-list", "--reverse", args[0] if args else "HEAD").split():
            msg = write_note(c, mpr, dry, force)
            if msg:
                n += 1; print(msg)
        print(f"{'would update' if dry else 'updated'} {n} notes")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except SystemExit:
        raise
    except Exception as e:  # never break a commit over a note
        print(f"⚠ mx-metadata-note: {type(e).__name__}: {e}", file=sys.stderr)
        sys.exit(0 if os.environ.get("MXTK_HOOK") else 1)
