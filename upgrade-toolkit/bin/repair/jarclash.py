#!/usr/bin/env python3
"""jarclash.py: find Java classes that two jars both carry, also when one copy hides inside another jar.

Why: jardedupe.py and test_inventory.py compare jar FILE NAMES. Academy 10.18 to 11.15 (AC-6): CommunityCommons
11.5.1 needs a newer PDF library, and the build broke on an old copy of it that no file name showed: it sat inside
an unused 20 MB Markdown library (flexmark, 2021), and in PDFReader 1.0.0, a module with no newer version. The
team removed old library files over several commits; the CLI run found them by trial. Classes are what the class
loader sees, so this reads classes.

  jarclash.py <project dir> [--min 5] [--md out.md]

Reads every .jar in userlib/ and vendorlib/, and the jars nested inside them (lib/*.jar, BOOT-INF/lib/*.jar).
Two jars clash when they carry the same class names (module-info, package-info, META-INF/versions excluded); a
relocated (shaded) copy has other names and does not clash. Per pair it prints the shared packages, the library
versions found in META-INF/maven/*/pom.properties, and the owning modules from the userlib
<jar>.<Module>.RequiredLib markers. Run it after the post-convert module updates and the dependency resync,
before the build; and at triage on the source app, where a clash is "present BEFORE the upgrade".
Each pair also says when both files are ONE artifact under a different name (same identity from
test_inventory.jar_identity: pom groupId:artifactId, else manifest module name): that is jardedupe's work (T3-3).
Exit: 0 = no clash of --min classes or more, 1 = clashes found, 2 = input error.
"""
import argparse, io, os, re, sys, zipfile
from collections import defaultdict

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from test_inventory import jar_identity  # noqa: E402  one jar identity for the toolkit

SKIP = re.compile(r"(^|/)(module-info|package-info)\.class$|^META-INF/")
NESTED = re.compile(r"(^|/)(lib|BOOT-INF/lib)/[^/]+\.jar$|^[^/]+\.jar$")


def scan(z, label, out, depth=0):
    """Fill out[label] = {"classes": set, "libs": {artifact: version}}, recursing into nested jars once."""
    rec = out.setdefault(label, {"classes": set(), "libs": {}})
    for n in z.namelist():
        if n.endswith(".class") and not SKIP.search(n):
            rec["classes"].add(n)
        elif n.startswith("META-INF/maven/") and n.endswith("/pom.properties"):
            p = dict(re.findall(r"^(\w+)=(.*?)\s*$", z.read(n).decode("utf-8", "replace"), re.M))
            if p.get("artifactId"):
                rec["libs"][p["artifactId"]] = p.get("version", "?")
        elif n.endswith(".jar") and depth == 0 and NESTED.search(n):
            try:
                with zipfile.ZipFile(io.BytesIO(z.read(n))) as inner:
                    scan(inner, f"{label}!{n}", out, depth + 1)
            except zipfile.BadZipFile:
                pass


def owners(project):
    ul = os.path.join(project, "userlib")
    own = defaultdict(list)
    for f in (os.listdir(ul) if os.path.isdir(ul) else []):
        m = re.match(r"^(.+?\.jar)\.(.+)\.RequiredLib$", f)
        if m:
            own[f"userlib/{m.group(1)}"].append(m.group(2))
    return own


def pkg(cls):
    return cls.rsplit("/", 1)[0].replace("/", ".") if "/" in cls else "(default)"


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("project"); ap.add_argument("--min", type=int, default=5); ap.add_argument("--md")
    a = ap.parse_args()
    dirs = [d for d in ("userlib", "vendorlib") if os.path.isdir(os.path.join(a.project, d))]
    if not dirs:
        print(f"jarclash: {a.project}: no userlib/ or vendorlib/", file=sys.stderr); sys.exit(2)
    jars, ident = {}, {}
    for d in dirs:
        for f in sorted(os.listdir(os.path.join(a.project, d))):
            if not f.endswith(".jar"):
                continue
            try:
                with zipfile.ZipFile(os.path.join(a.project, d, f)) as z:
                    scan(z, f"{d}/{f}", jars)
                ident[f"{d}/{f}"] = jar_identity(os.path.join(a.project, d, f))
            except zipfile.BadZipFile:
                print(f"UNREADABLE {d}/{f}: not a zip", file=sys.stderr)
    by_class = defaultdict(list)
    for label, rec in jars.items():
        for c in rec["classes"]:
            by_class[c].append(label)
    pairs = defaultdict(set)
    for c, labels in by_class.items():
        top = sorted(set(labels))
        for i in range(len(top)):
            for j in range(i + 1, len(top)):
                # a jar and the jars nested inside it are one artifact on the class path only if both are loaded,
                # which they are not; pair them anyway only when they come from different top-level files
                if top[i].split("!")[0] != top[j].split("!")[0]:
                    pairs[(top[i], top[j])].add(c)
    own = owners(a.project)
    rows = sorted(((len(cs), p, cs) for p, cs in pairs.items() if len(cs) >= a.min), key=lambda r: -r[0])
    lines = []
    for n, (x, y), cs in rows:
        pk = sorted({pkg(c) for c in cs})
        def who(lbl):
            top = lbl.split("!")[0]
            libs = ", ".join(f"{k} {v}" for k, v in sorted(jars[lbl]["libs"].items())[:3]) or "no maven metadata"
            if not jars[lbl]["libs"] and top in ident and ident[top]["src"] == "manifest":
                libs = f"manifest {ident[top]['key']} {ident[top]['ver'] or '?'}"
            mods = ",".join(own.get(top, [])) or "-"
            return f"{lbl} [{libs}; modules: {mods}]"
        lines.append(f"CLASH {n} classes in {len(pk)} packages ({', '.join(pk[:3])}{', ...' if len(pk) > 3 else ''})")
        lines.append(f"  {who(x)}")
        lines.append(f"  {who(y)}")
        ix, iy = ident.get(x.split("!")[0]), ident.get(y.split("!")[0])
        if ix and iy and ix["aliases"] & iy["aliases"]:
            lines.append(f"  same artifact {ix['key']} ({ix['ver'] or '?'} vs {iy['ver'] or '?'}) under two file names: jardedupe.py groups these")
        hidden = [l for l in (x, y) if "!" in l]
        if hidden:
            lines.append(f"  hidden copy: {hidden[0]} (no file name shows it; remove the outer jar or port its user)")
    print("\n".join(lines) if lines else f"no clash ({len(jars)} jars read)")
    if a.md:
        with open(a.md, "w") as f:
            f.write("# Java class clashes\n\n```\n" + ("\n".join(lines) or "none") + "\n```\n")
    sys.exit(1 if rows else 0)


if __name__ == "__main__":
    main()
