#!/usr/bin/env python3
"""themefiles.py: files of a Marketplace module that live OUTSIDE the model: themesource/<module>/, javascriptsource/<module>/
and the user code of javasource/<module>/ (T5-17, T3-21, T3F-9).

Why: localedits compared the model only. A publisher who changed 11 brand colours in themesource/atlas_core/web/_variables.scss
got "domain model unchanged"; stepupdate then took the --no-baseline route and replaced the file. mx check, build, data diff,
logs and the smoke walk all passed; only the screenshots showed it (13 of 14 pairs REVIEW). Nothing listed the edit before,
nothing listed the loss after.

Library (localedits.py layer 4) and a small CLI for stepupdate.sh:
  themefiles.py report <app dir> <Module> <saved dir>     files of the snapshot that differ from the working tree now:
                                                          "FILES-OVERWRITTEN <path> (saved: <file>)"; exit 1 when any
  themefiles.py snapshot <app dir> <Module> <saved dir>   copy the module's themesource/javascriptsource files (exit 0)
  themefiles.py history <app dir> <Module> --mpr <rel path of the .mpr> [--installed VER] [--json FILE]
                                                          are the files unedited since the install commit? git proves it
                                                          (QW-3, backlog #31): "FILES-UNEDITED-BY-HISTORY ..." exit 0,
                                                          "FILES-EDITED <path> (by history, since <sha7>)" exit 1, or
                                                          "FILES-UNKNOWN <Module>: <reason>" exit 2, never "clean" on a gap
  themefiles.py replay <app dir> <Module> <files.json>    emit the changed "$var: value;" lines of edited SCSS files into
                                                          theme/web/custom-variables.scss, only when that file exists

Compared (theme and JavaScript files, whole file): line ends (CRLF, CR) and trailing blanks are ignored, and so are leading
comment lines that say "generated" (a build rewrites those). A file whose first line says it is auto-generated and must
not be modified is not compared at all (F6: Studio Pro writes it whole). A file with a NUL byte is compared byte for byte.
JavaScript ACTION files (a .js file with BEGIN USER CODE / BEGIN EXTRA CODE markers, B4T2-3, B4N1-5): Studio Pro
regenerates everything but the import list and the two code blocks, so a package copy without its header, with the
imports in another order, or with other JSDoc text is not an edit (44 NanoflowCommons and 3 DataWidgets files were
FILES-EDITED, which also suggested force-ui). Compared: the import set (order, quotes, spacing and the generated
'import "mx-global"' / 'import { Big } from "big.js"' ignored) and the text of every USER CODE / EXTRA CODE block in
order (indentation and blank lines ignored). A changed line inside a block, or an added import, is still CHANGED. Java files:
bin/usercode.py (USER CODE / EXTRA CODE blocks only; a file without markers whole; proxies/ never).
Rows: {"change": CHANGED|ADDED|REMOVED, "kind": theme|javascript|java, "path": "<themesource/...>", "detail": str, "vars": [...]}
where vars lists the "$name: value;" lines of an edited SCSS file whose value differs from the package.
"""
import json, os, re, shutil, subprocess, sys, tempfile, zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

ROOTS = (("themesource", "theme"), ("javascriptsource", "javascript"))
GEN = re.compile(r"generated", re.I)
# F6 (Purchase Request 10.24, real run): Atlas_Core's web/_generated-exclusion-variables.scss is written whole by Studio
# Pro from the app's client setting ($use-modern-client), so the React-client app differed from the package in a file
# nobody edited, and the module read as FILES-EDITED. A file whose first line says it is auto-generated and must not be
# modified is the tool's output, not a person's edit: it is not compared.
WHOLEGEN = re.compile(r"auto-?generated.*do not (modify|edit)", re.I)
VAR = re.compile(r"^\s*(\$[\w-]+)\s*:\s*(.+?)\s*;\s*(?://.*)?$")


JSBLOCK = re.compile(r"//\s*BEGIN (USER|EXTRA) CODE[^\n]*\n(.*?)//\s*END \1 CODE", re.S)
JSIMPORT = re.compile(r"""\bimport\b[^"';]*?(?:"[^"]*"|'[^']*')""")
JSGEN_IMPORTS = {'import "mx-global"', 'import { Big } from "big.js"'}   # Studio Pro writes these itself


def norm_js_action(text):
    """Studio Pro JS action text -> what Studio Pro retains (B4T2-3, B4N1-5); None when it has no code-block markers."""
    first = JSBLOCK.search(text)
    if not first:
        return None
    head = re.sub(r"/\*.*?\*/", " ", text[:first.start()], flags=re.S)
    head = re.sub(r"(?m)//.*$", " ", head)
    imps = set()
    # only the import statements themselves: text after the last import (an 'export async function ...' line when no
    # EXTRA CODE block sits in between) is not part of the import set
    for st in JSIMPORT.finditer(head):
        st = " ".join(st.group(0).replace("'", '"').split()).rstrip(";").strip()
        st = re.sub(r"\{\s*", "{ ", re.sub(r"\s*\}", " }", st))
        if st not in JSGEN_IMPORTS:
            imps.add(st)
    blocks = [f"[{m.group(1)}]\n" + "\n".join(ln.strip() for ln in m.group(2).split("\n") if ln.strip())
              for m in JSBLOCK.finditer(text)]
    return "js-action:\n" + "\n".join(sorted(imps)) + "\n" + "\n".join(blocks)


def norm(data, path=""):
    """bytes -> comparable text: LF line ends, no trailing blanks, no leading 'generated' comment lines, no outer blanks.
    A .js file with USER/EXTRA CODE markers: only what Studio Pro retains (norm_js_action)."""
    if b"\0" in data:
        return "bytes:" + __import__("hashlib").sha256(data).hexdigest()
    text = data.decode("utf-8", errors="replace").replace("\r\n", "\n").replace("\r", "\n")
    if path.lower().endswith((".js", ".mjs", ".ts")):
        js = norm_js_action(text)
        if js is not None:
            return js
    lines = [ln.rstrip() for ln in text.split("\n")]
    while lines and (not lines[0] or (lines[0].lstrip().startswith(("//", "/*", "*", "#")) and GEN.search(lines[0]))):
        lines.pop(0)
    while lines and not lines[-1]:
        lines.pop()
    return "\n".join(lines)


def variables(text):
    out = {}
    for ln in text.split("\n"):
        m = VAR.match(ln)
        if m:
            out[m.group(1)] = re.sub(r"\s*!default\s*$", "", m.group(2))
    return out


def app_files(app, mod):
    """{'themesource/<dir>/web/x.scss': bytes} for the module's folders under the app (folder name matched case-blind)."""
    out = {}
    for root, _ in ROOTS:
        top = os.path.join(app, root)
        if not os.path.isdir(top):
            continue
        for d in os.listdir(top):
            if d.lower() != mod.lower() or not os.path.isdir(os.path.join(top, d)):
                continue
            for base, _, files in os.walk(os.path.join(top, d)):
                for f in files:
                    p = os.path.join(base, f)
                    out[os.path.relpath(p, app).replace(os.sep, "/")] = open(p, "rb").read()
    return out


def pkg_files(mpk, mod):
    out = {}
    with zipfile.ZipFile(mpk) as z:
        for n in z.namelist():
            parts = n.split("/")
            if len(parts) < 3 or parts[0] not in dict(ROOTS) or parts[1].lower() != mod.lower() or n.endswith("/"):
                continue
            out[n] = z.read(n)
    return out


def whole_generated(data):
    """True when the first non-blank line is a comment saying the whole file is auto-generated (do not modify)."""
    if b"\0" in data:
        return False
    for ln in data.decode("utf-8", errors="replace").splitlines():
        if ln.strip():
            t = ln.lstrip()
            return t.startswith(("//", "/*", "*", "#")) and bool(WHOLEGEN.search(t))
    return False


def diff(app, mpk, mod):
    """Rows for one module: app tree vs the package (.mpk). Raises zipfile.BadZipFile / OSError on an unreadable package."""
    have, want = app_files(app, mod), pkg_files(mpk, mod)
    kind = lambda p: dict(ROOTS)[p.split("/")[0]]
    rows = []
    for p in sorted(set(have) | set(want)):
        a, b = have.get(p), want.get(p)
        if a is not None and b is not None:
            if norm(a, p) == norm(b, p) or (whole_generated(a) and whole_generated(b)):
                continue
            row = {"change": "CHANGED", "kind": kind(p), "path": p, "detail": "differs from the installed package", "vars": []}
            if p.endswith(".scss"):
                av, bv = variables(norm(a)), variables(norm(b))
                ch = [f"{k}: {v};" for k, v in av.items() if bv.get(k) != v]
                row["vars"] = ch
                if ch:
                    row["detail"] = f"{len(ch)} variable(s) changed: " + ", ".join(x.split(":")[0] for x in ch[:6]) + (" ..." if len(ch) > 6 else "")
            rows.append(row)
        elif a is not None:
            rows.append({"change": "ADDED", "kind": kind(p), "path": p, "detail": "local file, not in the package (the update may remove it)", "vars": []})
        else:
            rows.append({"change": "REMOVED", "kind": kind(p), "path": p, "detail": "package file deleted locally, comes back on update", "vars": []})
    try:
        import usercode
        uh, uw = usercode.app_files(app, mod), usercode.pkg_files(mpk, mod)
    except Exception:
        uh, uw = None, {}
    if uh is not None:
        j = f"javasource/{mod.lower()}/"
        for f in sorted(set(uh) | set(uw)):
            if f in uh and f in uw:
                if uh[f] != uw[f]:
                    rows.append({"change": "CHANGED", "kind": "java", "path": j + f, "detail": "user code differs from the installed package (logic edit)", "vars": []})
            elif f in uh:
                rows.append({"change": "ADDED", "kind": "java", "path": j + f, "detail": "local Java file, not in the package", "vars": []})
            else:
                rows.append({"change": "REMOVED", "kind": "java", "path": j + f, "detail": "package Java file deleted locally", "vars": []})
    return rows


def snapshot(app, mod, dest):
    shutil.rmtree(dest, ignore_errors=True)
    n = 0
    for p, data in app_files(app, mod).items():
        t = os.path.join(dest, p)
        os.makedirs(os.path.dirname(t), exist_ok=True)
        open(t, "wb").write(data); n += 1
    return n


def report(app, mod, saved):
    """Snapshot files that are gone or different now (byte level on the normalised text: a CRLF-only change is not one)."""
    now = app_files(app, mod)
    lost = []
    for base, _, files in os.walk(saved):
        for f in files:
            sp = os.path.join(base, f)
            rel = os.path.relpath(sp, saved).replace(os.sep, "/")
            if rel not in now:
                lost.append((rel, sp, "gone"))
            elif norm(open(sp, "rb").read(), rel) != norm(now[rel], rel):
                lost.append((rel, sp, "replaced"))
    return sorted(lost)


def replay(app, mod, rows_json):
    target = os.path.join(app, "theme", "web", "custom-variables.scss")
    data = json.load(open(rows_json))   # a localedits.py --json report: one entry per module, rows under "files"
    rows = [r for e in data for r in (e.get("files") or []) if r.get("vars")] if data and isinstance(data[0], dict) and "files" in data[0] \
        else [r for r in data if r.get("vars")]
    if not rows:
        print("no SCSS variable edits to replay"); return 0
    if not os.path.isfile(target):
        print("theme/web/custom-variables.scss does not exist: variables NOT replayed (the saved copies keep them)")
        return 0
    cur = open(target, encoding="utf-8", errors="replace").read()
    have = variables(norm(cur.encode()))
    now = app_files(app, mod)
    add = []
    for r in rows:
        nv = variables(norm(now.get(r["path"], b"")))
        for line in r["vars"]:
            k, v = line.split(":", 1)
            v = v.strip().rstrip(";").strip()
            if have.get(k) == v or nv.get(k) == v:
                continue   # already overridden, or the new package carries the same value
            add.append((r["path"], f"{k}: {v};"))
    if not add:
        print("SCSS variable edits already present in custom-variables.scss or equal to the new package: nothing added"); return 0
    with open(target, "a", encoding="utf-8") as fh:
        fh.write(("" if cur.endswith("\n") or not cur else "\n") + f"\n// stepupdate: local edits of {mod} theme files, replayed after the update (T5-17)\n")
        for p, line in add:
            fh.write(f"{line}  // was changed in {p}\n")
    print(f"REPLAYED-VARS {len(add)} variable line(s) into theme/web/custom-variables.scss: " + "; ".join(l for _, l in add[:8]))
    return 0


# ------------------------------------------------------------------------------------------------ history (QW-3, #31)
# Producer: stepupdate.sh runs it on the FILES-UNKNOWN branch (localedits could not compare with the package, e.g. the
# package answers HTTP 500). It reads only git and the committed .mpr, so it needs no package.
# Install commit C = the newest commit touching the module's paths that also changes the module's recorded version to the
# version now recorded. The files now must equal the files at C under norm() (the same compare rules as diff()). A
# person who edited a file in the SAME commit that installed the version is invisible here: the output says so.
class Unknown(Exception):
    pass


def git(app, *args, text=True):
    r = subprocess.run(["git", "-C", app, *args], capture_output=True)
    if r.returncode != 0:
        raise Unknown(f"git {' '.join(args[:2])} failed: {r.stderr.decode(errors='replace').strip()[:120]}")
    return r.stdout.decode(errors="replace") if text else r.stdout


def module_dirs(app, mod):
    """The module's folders under themesource/, javascriptsource/, javasource/ in the work tree (case-blind)."""
    out = []
    for root in ("themesource", "javascriptsource", "javasource"):
        top = os.path.join(app, root)
        if os.path.isdir(top):
            out += [f"{root}/{d}" for d in sorted(os.listdir(top)) if d.lower() == mod.lower() and os.path.isdir(os.path.join(top, d))]
    return out


def extract(app, rev, paths, dest):
    """git archive rev -- paths (those that exist at rev) into dest. Returns the paths found."""
    have = [p for p in paths if git(app, "ls-tree", "--name-only", rev, "--", p).strip()]
    os.makedirs(dest, exist_ok=True)
    if have:
        tar = subprocess.run(["git", "-C", app, "archive", rev, "--", *have], capture_output=True)
        if tar.returncode != 0:
            raise Unknown(f"git archive {rev[:7]} failed")
        subprocess.run(["tar", "-x", "-C", dest], input=tar.stdout, check=True)
    return have


def recorded_version(app, rev, mpr, mod):
    """The module's recorded version in the .mpr at rev (None when the .mpr or the module is not there); rev None = work tree."""
    import mprmodel
    if rev is None:
        return mprmodel.Model.load(os.path.join(app, mpr)).modules.get(mod, {}).get("version") or None
    rel = os.path.dirname(mpr)
    paths = [mpr] + ([f"{rel}/mprcontents" if rel else "mprcontents"])
    with tempfile.TemporaryDirectory() as d:
        if not extract(app, rev, paths, d) or not os.path.isfile(os.path.join(d, mpr)):
            return None
        return mprmodel.Model.load(os.path.join(d, mpr)).modules.get(mod, {}).get("version") or None


def history(app, mod, mpr, installed=None, limit=300):
    """-> (status, lines, rows): status 'unedited' | 'edited' | 'unknown'."""
    try:
        if subprocess.run(["git", "-C", app, "rev-parse", "--is-inside-work-tree"], capture_output=True).returncode != 0:
            raise Unknown("not a git work tree")
        if git(app, "rev-parse", "--is-shallow-repository").strip() == "true":
            raise Unknown("shallow clone: the history before the clone is not there to prove anything")
        dirs = module_dirs(app, mod)
        if not dirs:
            raise Unknown("no themesource/javascriptsource/javasource folder of the module in the work tree")
        st = git(app, "status", "--porcelain", "--untracked-files=all", "--ignored", "--", *dirs).strip()
        if st:
            raise Unknown(f"untracked, ignored or uncommitted files under the module's folders ({len(st.splitlines())}, "
                          f"first: {st.splitlines()[0][3:]})")
        try:
            now_v = installed or recorded_version(app, None, mpr, mod)
        except Exception as e:
            raise Unknown(f"cannot read the module's version from {mpr}: {e}")
        if not now_v:
            raise Unknown(f"{mpr} records no version for {mod}")
        revs = git(app, "log", f"-{limit}", "--full-history", "--format=%H", "--", *dirs).split()
        if not revs:
            raise Unknown("no commit touches the module's folders")
        inst = None
        for c in revs:
            parents = git(app, "rev-list", "--parents", "-n", "1", c).split()[1:]
            vc = recorded_version(app, c, mpr, mod)
            vp = recorded_version(app, parents[0], mpr, mod) if parents else None
            if vc != vp:
                if not parents:
                    raise Unknown("the module is already in the first commit: the history shows no install of it")
                if len(parents) > 1:
                    raise Unknown(f"the install commit {c[:7]} is a merge: which side installed the files is not provable")
                inst = (c, vc)
                break
        if not inst:
            raise Unknown(f"no commit in the last {len(revs)} touching the folders changes the recorded version of {mod}")
        c, vc = inst
        if vc != now_v:
            raise Unknown(f"the newest commit that changes {mod}'s version ({c[:7]}) records {vc}, now {now_v}")
        subj = git(app, "log", "-1", "--format=%s", c).strip()
        date = git(app, "log", "-1", "--format=%cs", c).strip()
        prov = "toolkit step" if re.match(rf"^step: {re.escape(mod)} \S+ \(stepupdate", subj) else "person commit"
        with tempfile.TemporaryDirectory() as d:
            extract(app, c, dirs, d)
            have, want = app_files(app, mod), app_files(d, mod)
            n = len(set(have) | set(want))
            try:
                import usercode
                uh, uw = usercode.app_files(app, mod), usercode.app_files(d, mod)
            except Exception:
                uh, uw = None, None
            if n == 0 and not uh and not uw:
                raise Unknown("no file to compare (0 files at the install commit and now)")
            rows = []
            for p in sorted(set(have) | set(want)):
                a, b = have.get(p), want.get(p)
                if a is not None and b is not None:
                    if norm(a, p) == norm(b, p) or (whole_generated(a) and whole_generated(b)):
                        continue
                    rows.append({"change": "CHANGED", "kind": dict(ROOTS)[p.split("/")[0]], "path": p, "detail": "edited after the install", "vars": []})
                    if p.endswith(".scss"):
                        av, bv = variables(norm(a)), variables(norm(b))
                        rows[-1]["vars"] = [f"{k}: {v};" for k, v in av.items() if bv.get(k) != v]
                elif a is not None:
                    rows.append({"change": "ADDED", "kind": dict(ROOTS)[p.split("/")[0]], "path": p, "detail": "added after the install", "vars": []})
                else:
                    rows.append({"change": "REMOVED", "kind": dict(ROOTS)[p.split("/")[0]], "path": p, "detail": "deleted after the install", "vars": []})
            if uh is not None or uw is not None:
                uh, uw = uh or {}, uw or {}
                n += len(set(uh) | set(uw))
                j = f"javasource/{mod.lower()}/"
                for f in sorted(set(uh) | set(uw)):
                    if uh.get(f) != uw.get(f):
                        rows.append({"change": "CHANGED" if f in uh and f in uw else ("ADDED" if f in uh else "REMOVED"),
                                     "kind": "java", "path": j + f, "detail": "user code edited after the install", "vars": []})
        short = c[:7]
        if rows:
            return "edited", [f"FILES-EDITED {r['path']} (by history, since {short})" for r in rows], rows
        return "unedited", [f'FILES-UNEDITED-BY-HISTORY {mod} since {short} {date} "{subj[:70]}" ({n} files, provenance: {prov}; '
                            f"an edit inside the install commit itself would be invisible)"], []
    except Unknown as e:
        return "unknown", [f"FILES-UNKNOWN {mod}: {e}"], []


def main():
    a = sys.argv[1:]
    if a and a[0] == "history":
        import argparse
        ap = argparse.ArgumentParser(prog="themefiles.py history")
        ap.add_argument("cmd"); ap.add_argument("app"); ap.add_argument("module")
        ap.add_argument("--mpr", required=True); ap.add_argument("--installed"); ap.add_argument("--json")
        o = ap.parse_args(a)
        status, lines, rows = history(o.app, o.module, o.mpr, o.installed)
        print("\n".join(lines))
        if o.json:
            json.dump(rows, open(o.json, "w"), indent=1)
        sys.exit({"unedited": 0, "edited": 1, "unknown": 2}[status])
    if len(a) < 4 or a[0] not in ("report", "snapshot", "replay"):
        print(__doc__); sys.exit(2)
    cmd, app, mod, x = a[:4]
    if cmd == "snapshot":
        print(f"snapshot: {snapshot(app, mod, x)} file(s) of {mod} under {x}"); sys.exit(0)
    if cmd == "replay":
        sys.exit(replay(app, mod, x))
    lost = report(app, mod, x)
    for rel, sp, how in lost:
        print(f"FILES-OVERWRITTEN {rel} (saved: {sp}; {how} by the update)")
    sys.exit(1 if lost else 0)


if __name__ == "__main__":
    main()
