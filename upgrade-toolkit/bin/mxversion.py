#!/usr/bin/env python3
"""mxversion.py: print the FULL Mendix version (10.24.16.96987) of a toolset, runtime, project or package.

mxcli refuses a near match ("10.24.16" is not "10.24.16.96987"), and a log line or a report that says only "10.24"
cannot be reproduced. Every step records the full string.

  mxversion.py <path> [--short]

  mxbuild dir     runtime/bundles/com.mendix.public-api.jar  MANIFEST Implementation-Version
  runtime dir     runtime/launcher/runtimelauncher.jar (or the public-api bundle)  MANIFEST; also the CDN layout
                  <dir>/<full version>/runtime/... (one version only; S4: the 11.x
                  tarball extracts to <dir>/11.12.2/runtime, a 3-part folder name, the full version is read from the jar)
  app.mpr / dir   _MetaData._ProductVersion
  app.mda         model/metadata.json RuntimeVersion, else the version in the model file name
  x.mxmodule      add-on module (a zip holding project.mpr): the Studio Pro version that BUILT it (T2-2). Mendix 11
                  refuses one built before 10.21 (CE1893) and a vendor binary cannot be reopened.
--short prints major.minor.patch. Exit 0, or 2 when no version is found.
"""
import glob, json, os, re, sqlite3, sys, tempfile, zipfile


def manifest(jar):
    try:
        with zipfile.ZipFile(jar) as z:
            m = z.read("META-INF/MANIFEST.MF").decode("utf-8", "replace")
    except (OSError, KeyError, zipfile.BadZipFile):
        return None
    for key in ("Implementation-Version", "Bundle-Version"):
        r = re.search(rf"^{key}:\s*(\S+)", m, re.M)
        if r and re.match(r"^\d+\.\d+\.\d+", r.group(1)):
            return r.group(1)
    return None


def mxmodule_version(path):
    """Studio Pro version inside an add-on module (.mxmodule = zip with project.mpr; T2-2). None when unreadable."""
    try:
        with zipfile.ZipFile(path) as z:
            mprs = [n for n in z.namelist() if n.lower().endswith(".mpr")]
            if not mprs:
                return None
            mprs.sort(key=lambda n: (os.path.basename(n).lower() != "project.mpr", n.count("/"), n))
            with tempfile.TemporaryDirectory() as d:
                out = os.path.join(d, "inner.mpr")
                with open(out, "wb") as f:
                    f.write(z.read(mprs[0]))
                return version(out)
    except (OSError, zipfile.BadZipFile, sqlite3.Error):
        return None


def addons(project):
    """[(file name, version or None)] for <project dir>/modules/*.mxmodule, sorted. Shared by triage and missing_deps."""
    return [(os.path.basename(f), mxmodule_version(f))
            for f in sorted(glob.glob(os.path.join(project, "modules", "*.mxmodule")))]


def below(v, major, minor):
    """True when version string v is older than major.minor (10.21 -> (10, 21)); unreadable is not below."""
    m = re.match(r"^(\d+)\.(\d+)", v or "")
    return bool(m) and (int(m.group(1)), int(m.group(2))) < (major, minor)


def version(p):
    if p.endswith(".mxmodule"):
        return mxmodule_version(p)
    if os.path.isdir(p):
        for rel in ("runtime/bundles/com.mendix.public-api.jar", "runtime/launcher/runtimelauncher.jar",
                    "bundles/com.mendix.public-api.jar", "launcher/runtimelauncher.jar"):
            if os.path.exists(os.path.join(p, rel)):
                v = manifest(os.path.join(p, rel))
                if v:
                    return v
        # the CDN runtime layout: runtime-9.24.32/9.24.32.58223/runtime/... (runapp.py reads it the same way; E7-10)
        subs = [d for d in glob.glob(os.path.join(p, "*")) if os.path.isdir(d)
                and re.match(r"^\d+\.\d+\.\d+(\.\d+)?$", os.path.basename(d))]
        found = {v for v in (version(d) for d in subs) if v}
        if len(found) == 1:
            return found.pop()
        if len(found) > 1:
            print(f"mxversion: {p} holds several runtimes ({', '.join(sorted(found))}): name one", file=sys.stderr)
            return None
        mprs = glob.glob(os.path.join(p, "*.mpr"))
        if len(mprs) == 1:
            p = mprs[0]
    if p.endswith(".mpr"):
        con = sqlite3.connect(f"file:{p}?mode=ro", uri=True)
        try:
            return con.execute("select _ProductVersion from _MetaData").fetchone()[0]
        except sqlite3.Error:
            return None
    if p.endswith(".mda"):
        with zipfile.ZipFile(p) as z:
            try:
                meta = json.loads(z.read("model/metadata.json"))
                if meta.get("RuntimeVersion"):
                    return meta["RuntimeVersion"]
            except KeyError:
                pass
            for n in z.namelist():
                r = re.search(r"(\d+\.\d+\.\d+\.\d+)", n)
                if r:
                    return r.group(1)
    return None


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    v = version(sys.argv[1])
    if not v:
        print(f"mxversion: no Mendix version found in {sys.argv[1]}", file=sys.stderr); sys.exit(2)
    print(".".join(v.split(".")[:3]) if "--short" in sys.argv else v)
