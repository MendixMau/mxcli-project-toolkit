#!/usr/bin/env python3
"""usercode.py: is the Java code of a Marketplace module the code of its installed package? (T5-9, T8-12)

Why: after mx convert, `mxcli marketplace update` refuses MendixSSO ("16 element(s) have been changed locally", every
one a JAVA_ACTION) and AWSAuthentication ("2 JAVA_ACTIONs") although nobody touched them: the convert rewrote the
Java action parameter metadata in the model. The code a person would edit lives in javasource/<module>/, between the
"// BEGIN USER CODE" and "// END USER CODE" (and EXTRA CODE) markers. When those blocks equal the installed package,
the refused JAVA_ACTION rows are convert-made, not a person's edit; stepupdate.sh then forces the update.

Usage:
  usercode.py <app dir> <Module> [--cid ID] [--version V] [--localedits localedits.json] [--cache DIR]
Installed content id and version: from the app's MPR (Marketplace module), else --cid / --version, else the module's
entry in --localedits. The package is the cached <cid>-<version>.mpk (UPG_CACHE, the localedits.py cache), downloaded
with mxcli when absent.

Compared: every .java file under javasource/<module>/ on both sides, except proxies/ (generated). A file with USER CODE
or EXTRA CODE markers is compared on those blocks only (the rest is a generated stub that mxbuild rewrites); a file
without markers is compared whole. Line ends and trailing blanks are ignored, nothing else.
Exit: 0 IDENTICAL, 1 DIFFERENT (files listed), 2 cannot compare (no package, no javasource folder, input error).
"""
import argparse, json, os, re, sys, zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

BLOCK = re.compile(r"//\s*BEGIN (USER|EXTRA) CODE\s*\n(.*?)//\s*END \1 CODE", re.S)


def norm(text):
    lines = [ln.rstrip() for ln in text.replace("\r\n", "\n").replace("\r", "\n").split("\n")]
    while lines and not lines[0]:
        lines.pop(0)
    while lines and not lines[-1]:
        lines.pop()
    return "\n".join(lines)


def code(text):
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    blocks = BLOCK.findall(text)
    if blocks:
        return "\n----\n".join(f"{k}:{norm(b)}" for k, b in blocks)
    return norm(text)


def keep(rel):
    return rel.endswith(".java") and not rel.startswith("proxies/")


def app_files(app, mod):
    js = os.path.join(app, "javasource")
    d = next((x for x in (os.listdir(js) if os.path.isdir(js) else []) if x.lower() == mod.lower()), None)
    if not d:
        return None
    root, out = os.path.join(js, d), {}
    for base, _, files in os.walk(root):
        for f in files:
            rel = os.path.relpath(os.path.join(base, f), root).replace(os.sep, "/")
            if keep(rel):
                out[rel] = code(open(os.path.join(base, f), encoding="utf-8", errors="replace").read())
    return out


def pkg_files(mpk, mod):
    out = {}
    with zipfile.ZipFile(mpk) as z:
        for n in z.namelist():
            parts = n.split("/")
            if len(parts) < 3 or parts[0] != "javasource" or parts[1].lower() != mod.lower() or n.endswith("/"):
                continue
            rel = "/".join(parts[2:])
            if keep(rel):
                out[rel] = code(z.read(n).decode("utf-8", errors="replace"))
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("app"); ap.add_argument("module")
    ap.add_argument("--cid"); ap.add_argument("--version"); ap.add_argument("--localedits")
    ap.add_argument("--cache", default=os.environ.get("UPG_CACHE") or os.path.expanduser("~/.cache/upgrade-toolkit/mpk"))
    a = ap.parse_args()
    if not os.path.isdir(a.app):
        print(f"usercode: no app dir {a.app}", file=sys.stderr); sys.exit(2)
    cid, ver, src = None, None, ""
    mprs = [f for f in os.listdir(a.app) if f.endswith(".mpr")]
    if len(mprs) == 1:
        try:
            import localedits
            m = next((x for x in localedits.modules(os.path.join(a.app, mprs[0])) if x["name"] == a.module), None)
            if m and m.get("version"):
                cid, ver, src = m.get("cid"), m["version"], "the MPR"
        except Exception:
            pass
    if not ver and a.localedits:
        try:
            e = next((x for x in json.load(open(a.localedits)) if x.get("name") == a.module), None)
        except Exception as ex:
            print(f"usercode: {a.localedits}: not a localedits.py --json file ({ex})", file=sys.stderr); sys.exit(2)
        if e and e.get("version"):
            cid, ver, src = e.get("cid"), e["version"], a.localedits
    cid, ver = a.cid or cid, a.version or ver
    if not cid or not ver:
        print(f"CANNOT COMPARE: installed content id or version of {a.module} unknown (give --cid and --version)"); sys.exit(2)
    mpk = os.path.join(a.cache, f"{cid}-{ver}.mpk")
    if not os.path.exists(mpk):
        try:
            import localedits
            _, err = localedits.fetch_pkg(cid, ver, a.cache)
        except Exception as ex:
            err = [str(ex)]
        if not os.path.exists(mpk):
            print(f"CANNOT COMPARE: installed package {a.module} {ver} not cached and not downloadable ({'; '.join(err or [])})"); sys.exit(2)
    have = app_files(a.app, a.module)
    if have is None:
        print(f"CANNOT COMPARE: no javasource folder for {a.module} in {a.app}"); sys.exit(2)
    try:
        want = pkg_files(mpk, a.module)
    except zipfile.BadZipFile:
        print(f"CANNOT COMPARE: {mpk} is not a package (zip)"); sys.exit(2)
    if not want:
        print(f"CANNOT COMPARE: the package {mpk} has no javasource/{a.module.lower()}/ Java files"); sys.exit(2)
    diff = sorted(f for f in set(have) & set(want) if have[f] != want[f])
    only_app = sorted(set(have) - set(want))
    only_pkg = sorted(set(want) - set(have))
    where = f"{a.module} {ver} (content {cid}, version from {src or 'the arguments'})"
    if diff or only_app or only_pkg:
        print(f"DIFFERENT: Java code of {where} is not the package's: {len(diff)} changed, "
              f"{len(only_app)} only in the app, {len(only_pkg)} only in the package")
        for f in diff[:10]:
            print(f"   changed user code: javasource/{a.module.lower()}/{f}")
        for f in only_app[:10]:
            print(f"   only in the app:   javasource/{a.module.lower()}/{f}")
        for f in only_pkg[:10]:
            print(f"   only in the package: javasource/{a.module.lower()}/{f}")
        sys.exit(1)
    print(f"IDENTICAL: user code of {len(have)} Java files of {where} equals the installed package {os.path.basename(mpk)}")
    sys.exit(0)


if __name__ == "__main__":
    main()
