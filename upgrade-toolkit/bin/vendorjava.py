#!/usr/bin/env python3
"""vendorjava.py: was Marketplace (vendor) Java switched off by hand during the upgrade? (NS-5)

Why: after the convert to 11.12.4 the notification-service team made the build green by commenting out the bodies of
DatadogConnector.count/time/gauge (commit 076dca76, "disabled until connector is updated"). mx check, mxbuild and the
start are clean, the data diff is clean, and every Datadog metric is silently dropped. Nothing in the gate compared the
vendor Java with what it was before the upgrade.

  vendorjava.py <app dir> --base <git rev> [--modules A,B] [--md out.md]

--base is the app's pre-upgrade commit (the run's original commit, or the last commit before the convert): every
.java file under javasource/<module>/ of a Marketplace module (FromAppStore in the .mpr; --modules names them when the
.mpr cannot say, e.g. a module the plan knows is vendor code) is compared with `git show <base>:<path>`. proxies/ is
generated and skipped; a file new since the base is skipped (nothing was switched off in it).

Findings, per file:
  COMMENTED-OUT  code lines that are comments now and were not commented out at the base: a "//" or block-comment line
                 whose text ends like a statement (";", "{" or "}"), counted per text; the base's own commented code
                 is subtracted, so an old commented-out line is no finding
  EMPTIED        a method (name and parameter count) whose body had statements at the base and has none now (only
                 comments or blanks)
A file whose only commits since the base are module update commits (stepupdate's "step:" commits, or --update-commit
REGEX) is skipped and counted: the vendor shipped that change, and a person did not write it (PLM-31: the OData connector
7.1.7 package itself comments out two lines in HttpRequest.java and XPath.java). An uncommitted edit, or any later
commit that touches the file, makes it a finding again.
Each finding is a hand edit of vendor code: the feature it implemented is gone while the build stays green. Update
the module, or port the code to the new API; never ship the stub. An accepted case goes into the gate notes with its
reason (the stub is then a known, written-down loss).
Exit: 0 = none, 1 = findings (REVIEW), 2 = input error (no .mpr, no git, unknown base, no javasource/).
"""
import argparse, os, re, subprocess, sys
from collections import Counter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

CODE_END = re.compile(r"[;{}]\s*$")
METHOD = re.compile(r"(?:public|protected|private|static|final|synchronized|abstract|\s)+[\w<>\[\],.?\s]+?\s+(\w+)\s*"
                    r"\(([^;{}()]*)\)\s*(?:throws\s+[\w.,\s]+)?\{")


def strip_strings(text):
    return re.sub(r'"(?:\\.|[^"\\])*"', '""', text)


def commented_code(text):
    """Counter of comment lines that read as code (text normalised: no comment marks, single spaces)."""
    out, block = Counter(), False
    for ln in text.replace("\r\n", "\n").split("\n"):
        s = ln.strip()
        body = None
        if block:
            if "*/" in s:
                block = False
                s = s.split("*/", 1)[0]
            body = s.lstrip("*").strip()
        elif s.startswith("//"):
            body = s[2:].strip()
        elif s.startswith("/*"):
            rest = s[2:]
            if "*/" in rest:
                body = rest.split("*/", 1)[0].lstrip("*").strip()
            else:
                block, body = True, rest.lstrip("*").strip()
        if body and CODE_END.search(body) and not re.match(r"(BEGIN|END) (USER|EXTRA) CODE", body):
            out[" ".join(body.split())] += 1
    return out


def no_comments(text):
    text = strip_strings(text)
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    return re.sub(r"//[^\n]*", " ", text)


def methods(text):
    """{(name, nparams): has_statements}; the body is found by brace matching on the comment-free text."""
    clean = no_comments(text)
    out = {}
    for m in METHOD.finditer(clean):
        name = m.group(1)
        if name in ("if", "for", "while", "switch", "catch", "synchronized", "return", "new", "else"):
            continue
        params = m.group(2).strip()
        while re.search(r"<[^<>]*>", params):   # Map<String, String>: a comma inside a type argument is no separator
            params = re.sub(r"<[^<>]*>", "", params)
        n = 0 if not params else params.count(",") + 1
        depth, i = 1, m.end()
        while i < len(clean) and depth:
            depth += {"{": 1, "}": -1}.get(clean[i], 0)
            i += 1
        body = clean[m.end():i - 1]
        out.setdefault((name, n), bool(body.strip()))
    return out


def die(msg):
    print(msg, file=sys.stderr); sys.exit(2)


def git(app, *args):
    return subprocess.run(["git", "-C", app, *args], capture_output=True, text=True)


def update_only(app, base, rel_repo, pattern):
    """True when the file has commits since base, every one of them a module update commit, and no uncommitted change
    (PLM-31). Anything else (no commit: a working-tree edit; a hand commit among them) is a hand edit."""
    if git(app, "status", "--porcelain", "--", rel_repo).stdout.strip():
        return False
    subj = [x for x in git(app, "log", "--format=%s", f"{base}..HEAD", "--", rel_repo).stdout.split("\n") if x.strip()]
    return bool(subj) and all(pattern.search(x) for x in subj)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("app"); ap.add_argument("--base", required=True)
    ap.add_argument("--modules", default="", help="vendor modules, comma list (default: Marketplace modules of the .mpr)")
    ap.add_argument("--md")
    ap.add_argument("--update-commit", default=r"^step:", help="regex for the subject of a module update commit "
                    "(default: stepupdate's 'step: <Module> <version>'); a file changed only by those is the vendor's edit")
    a = ap.parse_args()
    upd = re.compile(a.update_commit)
    app = os.path.abspath(a.app)
    js = os.path.join(app, "javasource")
    if not os.path.isdir(js):
        die(f"vendorjava: {app}: no javasource/ folder")
    if git(app, "rev-parse", "--verify", "--quiet", f"{a.base}^{{commit}}").returncode != 0:
        die(f"vendorjava: {a.base}: not a commit in the git repository of {app}")
    vendor = {m.strip().lower() for m in a.modules.split(",") if m.strip()}
    src = "--modules"
    if not vendor:
        import mprmodel
        try:
            mdl = mprmodel.Model.load(app)
        except (SystemExit, Exception) as e:
            die(f"vendorjava: cannot read the .mpr ({e}); name the vendor modules with --modules")
        vendor = {n.lower() for n, i in mdl.modules.items() if n and i.get("from_appstore")}
        src = "Marketplace modules of the .mpr"
    rel_app = git(app, "rev-parse", "--show-prefix").stdout.strip() or "."   # the app folder inside the repository
    lines, nfiles, ncom, nemp, nupd = [], 0, 0, 0, 0
    for mod in sorted(d for d in os.listdir(js) if d.lower() in vendor and os.path.isdir(os.path.join(js, d))):
        for root, dirs, files in os.walk(os.path.join(js, mod)):
            dirs[:] = sorted(d for d in dirs if d != "proxies")
            for f in sorted(files):
                if not f.endswith(".java"):
                    continue
                path = os.path.join(root, f)
                rel = os.path.relpath(path, app)
                old = git(app, "show", f"{a.base}:{os.path.normpath(os.path.join(rel_app, rel))}")
                if old.returncode != 0:
                    continue   # new since the base: nothing was switched off in it
                nfiles += 1
                new = open(path, errors="replace").read()
                if update_only(app, a.base, os.path.normpath(os.path.join(rel_app, rel)), upd):
                    if commented_code(new) - commented_code(old.stdout) or methods(old.stdout) != methods(new):
                        nupd += 1
                    continue
                added = commented_code(new) - commented_code(old.stdout)
                n = sum(added.values())
                if n:
                    ncom += 1
                    ex = next(iter(added))
                    lines.append(f"COMMENTED-OUT {rel} ({mod}): {n} code line(s) newly commented out, e.g. \"{ex}\"")
                om, nm = methods(old.stdout), methods(new)
                for (name, k), had in sorted(om.items()):
                    if had and nm.get((name, k)) is False:
                        nemp += 1
                        lines.append(f"EMPTIED       {rel} ({mod}): {name}({k} parameter{'s' if k != 1 else ''}) had statements "
                                     f"at {a.base}, its body is empty now")
    head = (f"vendorjava: {len(vendor)} vendor modules ({src}), {nfiles} Java files compared with {a.base}: "
            f"{ncom} with newly commented-out code, {nemp} emptied methods"
            + (f"; {nupd} skipped: changed only by a module update commit (the vendor's own edit)" if nupd else ""))
    verdict = ("verdict: REVIEW (vendor code switched off by hand: the feature is gone while the build stays green; "
               "update the module or port the code, never ship the stub)" if lines else "verdict: PASS")
    out = "\n".join([head] + lines + [verdict])
    print(out)
    if a.md:
        open(a.md, "w").write(out + "\n")
    sys.exit(1 if lines else 0)


if __name__ == "__main__":
    main()
