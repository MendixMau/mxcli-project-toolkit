#!/usr/bin/env python3
"""model-scope.py -- find, and put back, model units whose bytes changed but whose meaning did not.

    python3 -I bin/model-scope.py report  [--against REF] [--mpr FILE] [-v]
    python3 -I bin/model-scope.py restore [--against REF] [--mpr FILE]
    python3 -I bin/model-scope.py check --staged [--project DIR]

WHY. mxcli v0.27.0 on a Mendix 10.24.18 app (MPR v2): one `alter entity ... rename attribute`
rewrote 135 units in 20 modules that never referenced the attribute. In each one the only change
was whitespace in XPath constraint strings: the line breaks between bracketed conditions were
removed (mendixlabs/mxcli#1596). `mxcli diff-local` renders MDL, which was identical, so it showed
nothing; the reviewer found the units in the branch diff. Captured on a public model
(tests/wave2/fixtures/model-scope/golden-v0.27.0/): renaming an unused attribute turned
"[Label = 'A']\\n[Flag != 'B']" into "[Label = 'A'][Flag != 'B']" in a microflow of another module.

NOISE vs REAL. A changed unit is noise when both versions decode to the same fields in the same
order, and every field that differs is an XPath constraint whose old and new strings are equal
once whitespace OUTSIDE string literals is removed. Anything else is real: another field, a
changed structure, whitespace inside a quoted literal, a unit that cannot be decoded, an added or
deleted unit. A newly proven kind of noise goes into same_meaning(), nowhere else.

MODES
  report   Classify every unit file changed in the working tree against REF (default HEAD).
           Prints the real changes per module and the noise count. Changes nothing. -v lists
           every unit.
  restore  report, then put each noise unit back from REF (`git checkout REF -- <files>`) and
           set its ContentsHash row in the .mpr from the restored file (mxpatch.py's rehash), so
           the index Studio Pro reads stays in step. bin/exec.sh runs this after every write.
  check    --staged: the staged index against HEAD, for the pre-commit hook. Exit 1 when a
           noise unit is staged, printing the restore command. MODEL_SCOPE_OK=1 lets that one
           commit through with a warning.

EXIT  0 ok   1 check: noise is staged   2 usage or environment problem (a tool fault, never a verdict)

MPR v2 only: a v1 .mpr keeps its units inside itself, so there is nothing to scope (exit 0).
Stdlib plus mxpatch.py and mxunit_bson.py from this directory; run it with `python3 -I`.
"""
import argparse
import collections
import os
import sqlite3
import subprocess
import sys
import tempfile
import uuid

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mxpatch  # noqa: E402  (beside this file)
from mxunit_bson import dec_doc  # noqa: E402


def decode(raw):
    doc, end = dec_doc(raw, 0)
    if end != len(raw):
        raise ValueError("trailing bytes after the BSON document")
    return doc


class ScopeError(Exception):
    pass


# --------------------------------------------------------------------------------------------
# Is a changed unit noise?
# --------------------------------------------------------------------------------------------
def strip_ws_outside_literals(s):
    """s without the whitespace that sits outside '...' and "..." literals. A backslash inside a
    literal escapes the next character. An unterminated literal runs to the end, so a doubtful
    case keeps its whitespace and can only come out REAL, never noise."""
    out, quote, i = [], None, 0
    while i < len(s):
        c = s[i]
        if quote:
            out.append(c)
            if c == "\\" and i + 1 < len(s):
                i += 1
                out.append(s[i])
            elif c == quote:
                quote = None
        elif c in "'\"":
            quote = c
            out.append(c)
        elif not c.isspace():
            out.append(c)
        i += 1
    return "".join(out)


def same_meaning(key, old, new):
    """True when this one differing leaf field means the same in both versions. Microflows store
    the key as XpathConstraint, page data sources as XPathConstraint."""
    return (key.lower() == "xpathconstraint" and isinstance(old, str) and isinstance(new, str)
            and strip_ws_outside_literals(old) == strip_ws_outside_literals(new))


def _leaves(doc, path=()):
    """[(path, type, value)] for every field, depth first; documents and arrays carry no value."""
    out = []
    for t, k, v in doc:
        if t in (0x03, 0x04):
            out.append((path + (k,), t, None))
            out.extend(_leaves(v, path + (k,)))
        else:
            out.append((path + (k,), t, (v.sub, bytes(v.data)) if t == 0x05 else v))
    return out


def classify(old_raw, new_raw):
    """("noise" | "real", reason) for a unit present on both sides whose bytes differ."""
    try:
        old, new = _leaves(decode(old_raw)), _leaves(decode(new_raw))
    except Exception as e:  # an unknown BSON type, a truncated file, ...
        return "real", "cannot decode (%s)" % e
    if [(p, t) for p, t, _ in old] != [(p, t) for p, t, _ in new]:
        return "real", "structure changed"
    diffs = [(p, a, b) for (p, _, a), (_, _, b) in zip(old, new) if a != b]
    for p, a, b in diffs:
        if not same_meaning(p[-1], a, b):
            return "real", "field changed: /" + "/".join(p)
    if not diffs:
        return "real", "bytes differ, decoded fields equal"
    return "noise", "%d XPath constraint(s), whitespace only" % len(diffs)


# --------------------------------------------------------------------------------------------
# git
# --------------------------------------------------------------------------------------------
def pin_git_env():
    """A hook may export GIT_DIR / GIT_INDEX_FILE as relative paths. Make them absolute before
    any chdir, and pin the work tree, so every later git call sees the git that called us."""
    for k in ("GIT_INDEX_FILE", "GIT_DIR", "GIT_WORK_TREE"):
        if os.environ.get(k):
            os.environ[k] = os.path.abspath(os.environ[k])
    if os.environ.get("GIT_DIR") and not os.environ.get("GIT_WORK_TREE"):
        os.environ["GIT_WORK_TREE"] = git(".", "rev-parse", "--show-toplevel").strip()


def git(cwd, *args):
    p = subprocess.run(("git",) + args, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if p.returncode != 0:
        raise ScopeError("git %s failed: %s" % (" ".join(args[:2]), p.stderr.decode("utf-8", "replace").strip()))
    return p.stdout.decode("utf-8", "replace")


def blobs(top, specs):
    """{spec: bytes or None} for `REV:path` / `:path` specs, in one `git cat-file --batch`."""
    if not specs:
        return {}
    p = subprocess.run(["git", "cat-file", "--batch"], cwd=top, input="".join(s + "\n" for s in specs).encode(),
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    out, i, data = {}, 0, p.stdout
    for s in specs:
        j = data.index(b"\n", i)
        head = data[i:j].split()
        i = j + 1
        if len(head) == 3 and head[1] == b"blob":
            n = int(head[2])
            out[s], i = data[i:i + n], i + n + 1
        else:
            out[s] = None
    return out


def find_mpr(explicit):
    for p in (explicit, os.environ.get("MPR_FILE")):
        if p:
            return os.path.abspath(p)
    for d in (".", "app"):
        found = sorted(f for f in os.listdir(d) if f.lower().endswith(".mpr")) if os.path.isdir(d) else []
        if len(found) > 1:
            raise ScopeError("more than one .mpr in %s; name one with --mpr" % os.path.abspath(d))
        if found:
            return os.path.abspath(os.path.join(d, found[0]))
    return None


# --------------------------------------------------------------------------------------------
# The changed units
# --------------------------------------------------------------------------------------------
Item = collections.namedtuple("Item", "status rel verdict reason module")


class Scope(object):
    """The changed units of one model: working tree (or index, staged=True) against ref."""

    def __init__(self, mpr, ref, staged):
        self.mpr, self.ref, self.staged = os.path.realpath(mpr), ref, staged
        model_dir = os.path.dirname(self.mpr)
        self.top = os.path.realpath(git(model_dir, "rev-parse", "--show-toplevel").strip())
        prefix = os.path.relpath(model_dir, self.top).replace(os.sep, "/")
        self.prefix = "" if prefix == "." else prefix + "/"
        if subprocess.run(["git", "rev-parse", "-q", "--verify", ref + "^{commit}"], cwd=self.top,
                          stdout=subprocess.DEVNULL).returncode != 0:
            raise ScopeError("%s is not a commit in this repository" % ref)

    def changed(self):
        """[(status, repo-relative path)] of unit files that differ from the ref."""
        spec = ":(literal)" + self.prefix + "mprcontents"
        args = ["diff", "--cached"] if self.staged else ["diff"]
        tok = git(self.top, *(args + ["--name-status", "-z", "--no-renames", self.ref, "--", spec])).split("\0")
        out = [(tok[i][:1], tok[i + 1]) for i in range(0, len(tok) - 1, 2)]
        if not self.staged:  # an untracked unit file is an addition too
            out += [("A", f) for f in git(self.top, "ls-files", "-z", "--others", "--exclude-standard",
                                          "--", spec).split("\0") if f]
        return [(s, f) for s, f in out if f.endswith(".mxunit")]

    def new_bytes(self, rels):
        if self.staged:
            return blobs(self.top, [":" + r for r in rels])
        out = {}
        for r in rels:
            p = os.path.join(self.top, r)
            out[":" + r] = open(p, "rb").read() if os.path.isfile(p) else None
        return out

    def modules(self):
        """{unit id: (container id, containment)} from the .mpr's Unit table, new side first; the
        ref's table adds the units this change deleted."""
        name = self.prefix + os.path.basename(self.mpr)
        sides = [blobs(self.top, [":" + name])[":" + name] if self.staged else self.mpr,
                 blobs(self.top, ["%s:%s" % (self.ref, name)])["%s:%s" % (self.ref, name)]]
        parents = {}
        for side in sides:
            path = side
            if isinstance(side, bytes):
                fd, path = tempfile.mkstemp(suffix=".mpr")
                with os.fdopen(fd, "wb") as fh:
                    fh.write(side)
            try:
                if path:
                    db = sqlite3.connect("file:%s?mode=ro" % path, uri=True, timeout=5)
                    for u, c, n in db.execute("SELECT UnitID, ContainerID, ContainmentName FROM Unit"):
                        parents.setdefault(bytes(u), (bytes(c) if c is not None else None, n))
                    db.close()
            except sqlite3.Error:
                pass
            finally:
                if isinstance(side, bytes):
                    os.remove(path)
        return parents

    def module_of(self, uid, parents, names):
        cur, seen = uid, set()
        while cur is not None and cur not in seen:
            seen.add(cur)
            parent, containment = parents.get(cur, (None, None))
            if containment == "Modules":
                if cur not in names:
                    rel = self.unit_rel(cur)
                    raw = self.new_bytes([rel])[":" + rel] or blobs(self.top, ["%s:%s" % (self.ref, rel)]).popitem()[1]
                    try:
                        names[cur] = mxpatch.get(decode(raw), "Name")
                    except Exception:
                        names[cur] = None
                return names[cur]
            cur = parent
        return None

    def unit_rel(self, uid):
        u = str(uuid.UUID(bytes_le=uid))
        return "%smprcontents/%s/%s/%s.mxunit" % (self.prefix, u[:2], u[2:4], u)

    def scan(self):
        """[Item] for every changed unit file."""
        changed = self.changed()
        old = blobs(self.top, ["%s:%s" % (self.ref, r) for s, r in changed if s == "M"])
        new = self.new_bytes([r for s, r in changed if s == "M"])
        parents, names, items = self.modules(), {}, []
        for status, rel in changed:
            if status == "M":
                a, b = old["%s:%s" % (self.ref, rel)], new[":" + rel]
                if a == b:
                    continue
                verdict, reason = classify(a, b) if a is not None and b is not None else ("real", "unreadable")
            else:
                verdict, reason = "real", {"A": "added", "D": "deleted"}.get(status, "git status " + status)
            try:
                mod = self.module_of(mxpatch.uid_blob(rel), parents, names)
            except Exception:
                mod = None
            items.append(Item(status, rel, verdict, reason, mod or "(project)"))
        return items


def summary(items, against):
    real = [i for i in items if i.verdict == "real"]
    noise = [i for i in items if i.verdict == "noise"]
    lines = ["model scope vs %s: %d unit file(s) changed, %d real, %d noise"
             % (against, len(items), len(real), len(noise))]
    if real:
        per = collections.Counter(i.module for i in real)
        lines.append("  real changes by module: " + ", ".join(
            "%s %d" % (k, n) for k, n in sorted(per.items(), key=lambda kv: (-kv[1], kv[0]))))
    if noise:
        lines.append("  noise: %d unit(s) in %d module(s), XPath whitespace only"
                     % (len(noise), len(set(i.module for i in noise))))
    return lines


# --------------------------------------------------------------------------------------------
# Modes
# --------------------------------------------------------------------------------------------
def report(scope, verbose):
    items = scope.scan()
    print("\n".join(summary(items, scope.ref)))
    if verbose:
        for i in sorted(items, key=lambda i: (i.verdict, i.module, i.rel)):
            print("  %-5s %s %-20s %s  [%s]" % (i.verdict, i.status, i.module, i.rel, i.reason))
    return items


def restore(scope):
    noise = [i for i in report(scope, False) if i.verdict == "noise"]
    if not noise:
        return 0
    files = [i.rel for i in noise]
    failed = None
    try:
        for k in range(0, len(files), 100):
            git(scope.top, "checkout", scope.ref, "--", *files[k:k + 100])
    except ScopeError as e:
        failed = e
    finally:
        # Every listed file, restored or not: rehash sets each row from the bytes on disk, so a
        # checkout that stopped part-way never leaves a restored file with a stale row.
        try:
            mxpatch.Model(scope.mpr).rehash([os.path.join(scope.top, f) for f in files],
                                            apply=True, log=lambda s: None)
        except Exception as e:
            raise ScopeError("some of the %d noise unit file(s) may be back from %s, and their "
                             "ContentsHash rows were not updated (%s). Repair the index: "
                             "./mxcli fix hashes -p %s --repair"
                             % (len(files), scope.ref, e, os.path.basename(scope.mpr)))
    if failed:
        raise ScopeError("restore stopped part-way (%s). The index matches every unit file; "
                         "units not yet restored are as the write left them. Run restore again."
                         % failed)
    print("  restored %d noise unit(s) from %s, ContentsHash rows updated" % (len(files), scope.ref))
    return 0


def check_staged(scope):
    items = scope.scan()
    noise = [i for i in items if i.verdict == "noise"]
    if not noise:
        return 0
    override = os.environ.get("MODEL_SCOPE_OK") == "1"
    err = sys.stderr.write
    err("\n".join(summary(items, "HEAD (staged)")) + "\n\n")
    err("  %s: %d staged unit file(s) changed only in XPath whitespace, not in meaning:\n"
        % ("WARNING" if override else "commit refused", len(noise)))
    for i in noise[:8]:
        err("      %-20s %s\n" % (i.module, i.rel))
    if len(noise) > 8:
        err("      ... and %d more\n" % (len(noise) - 8))
    err("  A reviewer would have to open every one of them. From the project root, put them back:\n"
        "      python3 -I bin/model-scope.py restore\n"
        "  then stage the model again. To commit them anyway, for this one commit:\n"
        "      MODEL_SCOPE_OK=1 git commit ...\n"
        "  (the right choice when you reformatted those XPaths on purpose, e.g. in Studio Pro).\n")
    if override:
        err("  MODEL_SCOPE_OK=1: committing the noise units anyway.\n")
        return 0
    return 1


def main(argv):
    ap = argparse.ArgumentParser(prog="model-scope.py", description=__doc__.split("\n\n")[0])
    ap.add_argument("mode", choices=("report", "restore", "check"))
    ap.add_argument("--against", default="HEAD", metavar="REF")
    ap.add_argument("--mpr", metavar="FILE")
    ap.add_argument("--staged", action="store_true", help="check: compare the index with HEAD")
    ap.add_argument("--project", metavar="DIR", help="run as if from this directory (the hook passes it)")
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args(argv)
    if args.mode == "check" and not args.staged:
        ap.error("check needs --staged")
    try:
        pin_git_env()
        if args.project:
            os.chdir(args.project)
        mpr = find_mpr(args.mpr)
        if mpr is None or not os.path.isfile(mpr):
            if args.mode == "check":
                return 0  # no model yet: nothing to check
            raise ScopeError("no .mpr found (run from the project root, or pass --mpr)")
        if not os.path.isdir(os.path.join(os.path.dirname(mpr), "mprcontents")):
            print("model scope: %s is MPR v1 (units inside the .mpr): nothing to scope" % os.path.basename(mpr))
            return 0
        if args.mode == "check":
            # Nothing to compare to on an unborn branch.
            if subprocess.run(["git", "rev-parse", "-q", "--verify", "HEAD"], stdout=subprocess.DEVNULL,
                              cwd=os.path.dirname(mpr)).returncode != 0:
                return 0
            return check_staged(Scope(mpr, "HEAD", staged=True))
        scope = Scope(mpr, args.against, staged=False)
        if args.mode == "restore":
            return restore(scope)
        report(scope, args.verbose)
        return 0
    except ScopeError as e:
        sys.stderr.write("model-scope.py: %s\n" % e)
        return 2
    except Exception as e:  # a tool fault must never read as "noise found" (1) or as a pass
        sys.stderr.write("model-scope.py: internal error: %s: %s\n" % (type(e).__name__, e))
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
