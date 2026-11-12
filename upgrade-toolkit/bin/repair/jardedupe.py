#!/usr/bin/env python3
"""jardedupe.py: deterministic jar cleanup for userlib/ and vendorlib/ after module updates.

Why: module updates never resync jars. Old module versions leave their jars in userlib/ (with <jar>.<Module>.RequiredLib
markers), vendorlib/ gets the new ones, and nothing removes the old copies: the runtime loads two versions of one library
(bcprov 1.78 and 1.85 broke SAML in E1; PDFBox 2 shadowing PDFBox 3 broke javac in E6-19; pdfbox 2.0.30 + 3.0.7,
commons-logging 1.2 + 1.3.5, guava, lang3 side by side in N1-6). `mx sync-java-dependencies` is the official fix but
cannot run behind the agent proxy (T2-9), so this tool does the cleanup from the files.

  jardedupe.py <project dir> [--apply] [--tsv out.tsv] [--log out.txt] [--modules A,B] [--vendorlib-synced]
               [--updated A,B] [--updated-from-git] [--cid Module=ID ...]

Three rules, all dry-run unless --apply (commit first: git is the undo). Every jar gets a line with its reason.
 1. DUPLICATE artifacts (same artifact, different versions, within userlib, within vendorlib or across them). "Same
    artifact" is the identity of test_inventory.jar_identity, not the file name (T3-3, T3-17): pom.properties
    groupId:artifactId, else the manifest module name, else the file-name key; the version comes from the file name,
    else from pom/manifest. So 'commons-codec-1.15.jar' and 'commons-codec.commons-codec-1.15.jar' are one artifact,
    'org.apache.commons.io-2.3.0.jar' is older than 'commons-io-2.11.0.jar', and an unversioned
    'org.apache.commons.lang3.jar' is read as the 3.1 its pom/manifest says.
    keep the highest version, remove the older ones with their markers. Equal versions in both dirs: vendorlib wins.
    The version a present module declares through a marker is named in the reason; the highest always includes it
    (a marker only says what an OLD module version needed), EXCEPT an older copy of another MAJOR version declared by a
    present module that declares no newer copy and was not just updated (--updated): kept as CONFLICT (pdfbox 2 vs 3
    is an API break; a just-updated module's marker is a leftover of its old version). Which modules were updated
    (B4T2-10, B4N1-7): --updated, plus with --updated-from-git every module with a "step: <Module> <version>" commit
    in the app's git history (stepupdate passes both: a module committed by an EARLIER pass, or a hand rerun of this
    tool, left CommunityCommons 10's pdfbox/fontbox 2.0.24 as CONFLICT and javac failed at Misc.java:643). Stronger
    than both, when it can be read: the module's INSTALLED package, <content id>-<version>.mpk in the localedits cache
    (UPG_CACHE; the id from the .mpr, or --cid Module=ID, which stepupdate passes from the plan because an 11.x .mpr
    records none). The jar is in the package's userlib/: the marker is current, CONFLICT even for an updated module;
    it is not: the marker is a leftover of an older version (named in the REMOVE line). Unversioned markers
    ('*.CommunityCommons.RequiredLib') say nothing about the version, so this is the only proof for them besides git.
    An older vendorlib jar next to a newer userlib one is
    KEPT (managed dependency, the userlib copy is a local override: review by hand). A group with a jar whose version
    cannot be read is AMBIGUOUS: everything is kept.
 2. STALE userlib jars: every marker names a module that is provably not in the app (no javasource/<module>/ folder, no
    add-on of that name, and the name occurs nowhere in the .mpr / mprcontents) -> remove (T2-14: OIDC markers with no
    OIDC module). A jar without a marker is the app's own and is kept. No .mpr found, or --modules naming it, means
    "cannot prove": kept. ADD-ON JAVA (T2R3-6): add-on modules (modules/*.mxmodule, unpacked by Studio Pro into
    .mendix-cache/modules/<name>.mxmodule/) carry their own javasource that is NOT under javasource/ and reuse jars of
    modules the app does not have (EXFN_Authentication's DecodeJWT.java imports com.auth0.jwt from the OIDC-marked
    java-jwt jar: removing it failed the build twice). A jar whose classes add-on Java imports is kept as "NEEDED BY
    ADD-ON", and with it every jar of the same absent module (its runtime dependencies, jackson and codec, show in no
    import line); when an add-on's Java cannot be read (unreadable zip, or classes/jars and no .java), no STALE jar is
    removed: kept as UNPROVEN, review by hand.
 3. OLD-VERSION markers (N3-17, T1R-13): some modules version their markers, <jar>.<Module>.<version>.RequiredLib
    ('*.MendixSSO.4.1.0'). A module's version is the one installed in the .mpr (AppStoreVersion, read with mprmodel)
    when that is newer than its markers, else its newest marker version; a marker of an older version is a leftover. A
    jar whose markers are ALL leftovers (or name absent modules) is removed with them (same import protection as rule
    2; a newer copy of the artifact is rule 1's business); a leftover marker on a jar that a current marker still claims
    is removed alone (OLD-MARKER). When NO userlib marker carries the installed version, the module took its jars to
    vendorlib, so those removals rest on vendorlib (the T5-16 gate below). Unversioned markers are never compared. A
    marker whose jar is not in userlib is removed (ORPHAN).
 UNMATCHED (NS-3): a userlib jar of a module that moved its jars to vendorlib (rule 1 removes another of its userlib jars
    as a duplicate of a vendorlib copy) but with no copy of its own anywhere: never removed, listed for a human. Typical
    cause: a renamed or split artifact (netty 4.2 split netty-codec into netty-codec-base and others); a vendorlib jar of
    the same group whose artifact name extends the old one is named as the likely replacement.
 The project path may be relative to the current directory; a path that is no folder, or a folder with neither userlib/
 nor vendorlib/, is an input error that names the resolved path (T1R-13). A folder with vendorlib/ only is checked.
 VENDORLIB MUST BE CURRENT (T5-16): a userlib jar removed because vendorlib has a newer copy is only safe when vendorlib
 is what `mx sync-java-dependencies` produces NOW. After a failed sync (Maven 429, no proxy route) vendorlib still holds
 the set of the OLD module version and the removal deletes the only copy that fits (35 AWSAuth jars in T5). --apply
 therefore refuses (exit 2, "vendorlib is stale") when it would remove such a jar unless it finds proof: a vendorlib
 SBOM (vendorlib-sbom.json, vendorlib/vendorlib-sbom.json, vendorlib/sbom.json, .stepupdate/vendorlib-sbom.json) newer
 than the last module-set change (newest userlib *.RequiredLib marker, the .mpr, mprcontents), or the caller states it
 with --vendorlib-synced (a host-Maven fallback sync); the proof used is printed. Removals that need no vendorlib (older
 copy inside userlib, modules provably gone, vendorlib copies) are not held back; the report mode always lists the verdict.
 Never removed: a jar whose classes the app's own javasource or an add-on's Java imports, unless a newer copy of the
 same artifact remains (rules 2 and 3 keep it as IMPORTED / NEEDED BY ADD-ON; rule 1 always leaves the newer copy). A
 jar that cannot be opened as a zip has no known packages, so that check cannot protect it.

A REMOVE line whose removal rests on vendorlib says "(rests on vendorlib)": with no sync possible (the cloud proxy,
 B4T2-9) those are the jars whose newer copy must be in vendorlib/ before --vendorlib-synced is a true statement.

Exit: 0 = nothing to remove (or all removed with --apply), 1 = removals found (report mode), 2 = input error or stale vendorlib.
"""
import argparse, os, re, sys, zipfile

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from test_inventory import jar_identity, group_by_identity  # noqa: E402  one jar identity for the toolkit


SIDECAR = re.compile(r"(?i)[-_.](sources|javadoc)(?=\.jar$)")


def classifier_identity(name, ident):
    """-sources and -javadoc jars are their own artifact: 'hamcrest-library-1.3-sources.jar' is not a newer or older
    'hamcrest-library-1.3.jar'. Its key gets the classifier and it meets no alias of the class jar (a version of
    '1.3-sources' also made it sort above '1.3', so the class jar was removed as older and the sources kept)."""
    m = SIDECAR.search(name)
    if not m:
        return ident
    kind = m.group(1).lower()
    ver = re.sub(r"(?i)[-_.]" + kind + r"$", "", ident["ver"])
    key = f"{ident['key']}:{kind}"
    return {"key": key, "aliases": {key}, "ver": ver, "src": ident["src"]}


def vkey(v):
    """'2.12.2-sp1' -> ((2,12,2), 1) ; numeric parts compare as numbers, any suffix ranks above none."""
    m = re.match(r"^(\d+(?:\.\d+)*)(.*)$", v or "")
    if not m:
        return ((), 0, v or "")
    return (tuple(int(x) for x in m.group(1).split(".")), 1 if m.group(2) else 0, m.group(2))


MARKER = re.compile(r"^([A-Za-z_]\w*)\.(\d+(?:\.\d+)+)$")   # '<Module>.<version>' (N3-17: 'MendixSSO.4.1.0')


def markers_of(files, j):
    """(marker files, module names, [(file, module, version or '')]). '<jar>.MendixSSO.4.1.0.RequiredLib' names module
    MendixSSO at 4.1.0 (N3-17, T1R-13); before, 'MendixSSO.4.1.0' was taken as a module name that no .mpr contains."""
    ms = sorted(f for f in files if f.startswith(j + ".") and f.endswith(".RequiredLib"))
    mv = []
    for m in ms:
        tok = m[len(j) + 1:-len(".RequiredLib")]
        v = MARKER.match(tok)
        mv.append((m, v.group(1), v.group(2)) if v else (m, tok, ""))
    return ms, sorted({mod for _, mod, _ in mv}), mv


IMPORT = re.compile(r"\s*import\s+(?:static\s+)?([\w.]+?)(?:\.\*|\.\w+)?\s*;")


def java_imports(text):
    return {m.group(1) for m in (IMPORT.match(line) for line in text.splitlines()) if m}


ADDONS = None   # (packages -> add-on names, unreadable add-ons, add-on module names); filled once per run


def addon_java(project):
    """Imports of add-on module Java (T2R3-6). Add-ons are modules/*.mxmodule zips; Studio Pro unpacks them into
    .mendix-cache/modules/<name>.mxmodule/ and compiles THAT javasource, which never appears under javasource/.
    Returns ({package: {add-on}}, [add-on whose Java cannot be read], {add-on module names, lower case})."""
    global ADDONS
    if ADDONS is not None:
        return ADDONS
    pk, unreadable, names, seen = {}, [], set(), set()
    cache = os.path.join(project, ".mendix-cache", "modules")
    for d in sorted(os.listdir(cache)) if os.path.isdir(cache) else []:
        base = d[:-len(".mxmodule")] if d.lower().endswith(".mxmodule") else d
        names.add(base.lower()); seen.add(base.lower())
        for root, _, fs in os.walk(os.path.join(cache, d)):
            for f in fs:
                if f.endswith(".java"):
                    try:
                        for i in java_imports(open(os.path.join(root, f), errors="replace").read()):
                            pk.setdefault(i, set()).add(base)
                    except OSError:
                        unreadable.append(f"{base} ({os.path.join(root, f)} unreadable)")
    mods = os.path.join(project, "modules")
    for f in sorted(os.listdir(mods)) if os.path.isdir(mods) else []:
        if not f.lower().endswith(".mxmodule"):
            continue
        base = f[:-len(".mxmodule")]
        names.add(base.lower())
        try:
            with zipfile.ZipFile(os.path.join(mods, f)) as z:
                ents = z.namelist()
                java = [n for n in ents if n.endswith(".java")]
                for n in java:
                    for i in java_imports(z.read(n).decode("utf-8", "replace")):
                        pk.setdefault(i, set()).add(base)
                if not java and base.lower() not in seen and any(n.endswith((".class", ".jar")) for n in ents):
                    unreadable.append(f"{base} (modules/{f} holds compiled Java and no source)")
        except (zipfile.BadZipFile, OSError, KeyError, RuntimeError):
            if base.lower() not in seen:   # the unpacked cache is what Studio Pro compiles: it is enough
                unreadable.append(f"{base} (modules/{f} is not a readable zip and has no .mendix-cache copy)")
    ADDONS = (pk, unreadable, names)
    return ADDONS


def addon_users(path, project):
    """Add-ons whose Java imports a package of this jar (T2R3-6)."""
    pk, _, _ = addon_java(project)
    jp = jar_packages(path)
    return sorted({a for i, adds in pk.items() for p in jp if i == p or i.startswith(p + ".") or p.startswith(i + ".")
                   for a in adds})


INSTALLED = None   # {module: {"version", "package_id"}} from the .mpr, read once


def installed_modules(project):
    global INSTALLED
    if INSTALLED is None:
        try:
            sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
            import mprmodel
            INSTALLED = {k: (v or {}) for k, v in mprmodel.Model.load(project).modules.items()}
        except (SystemExit, Exception):
            INSTALLED = {}
    return INSTALLED


def installed_versions(project):
    """{module: version} from the .mpr (Projects$ModuleImpl AppStoreVersion, via mprmodel); {} when it cannot be read
    (no bson, no .mpr, unreadable): rule 3 then compares markers with each other only."""
    return {k: v.get("version") or "" for k, v in installed_modules(project).items()}


CIDS = {}       # --cid Module=ID (lower-case module name): content ids the .mpr does not record (11.x, B4N1-4)
PKGLIB = {}     # module -> (set of userlib file names, "cid-version.mpk") or None


def package_userlib(project, mod):
    """The userlib/ file names of the module's INSTALLED package (B4N1-7), from the localedits .mpk cache; None when
    the package is not there or cannot be read (then git and --updated decide). Never downloads."""
    if mod in PKGLIB:
        return PKGLIB[mod]
    info = next((v for k, v in installed_modules(project).items() if k.lower() == mod.lower()), {})
    ver, cid = info.get("version") or "", CIDS.get(mod.lower()) or info.get("package_id") or 0
    res = None
    if ver and str(cid) not in ("", "0"):
        cache = os.environ.get("UPG_CACHE") or os.path.expanduser("~/.cache/upgrade-toolkit/mpk")
        mpk = os.path.join(cache, f"{cid}-{ver}.mpk")
        try:
            with zipfile.ZipFile(mpk) as z:
                res = ({n.split("/", 1)[1] for n in z.namelist() if n.startswith("userlib/") and not n.endswith("/")},
                       os.path.basename(mpk))
        except (OSError, zipfile.BadZipFile, KeyError, RuntimeError):
            res = None
    PKGLIB[mod] = res
    return res


def module_known(project, mod, extra):
    """True when the module may be in the app. False only when provably absent. None source = cannot prove = True."""
    if mod.lower() in extra or os.path.isdir(os.path.join(project, "javasource", mod.lower())):
        return True
    if mod.lower() in addon_java(project)[2]:
        return True
    mprs = [f for f in os.listdir(project) if f.endswith(".mpr")]
    if not mprs:
        return True
    needle = mod.encode()
    paths = [os.path.join(project, m) for m in mprs]
    for root, _, fs in os.walk(os.path.join(project, "mprcontents")):
        paths += [os.path.join(root, f) for f in fs]
    for p in paths:
        try:
            with open(p, "rb") as f:
                if needle in f.read():
                    return True
        except OSError:
            return True
    return False


def imported_packages(project):
    """Every package that the app's own javasource imports (dotted prefixes)."""
    pk = set()
    for root, _, fs in os.walk(os.path.join(project, "javasource")):
        for f in fs:
            if f.endswith(".java"):
                try:
                    pk |= java_imports(open(os.path.join(root, f), errors="replace").read())
                except OSError:
                    pass
    return pk


def jar_packages(path):
    try:
        with zipfile.ZipFile(path) as z:
            return {os.path.dirname(n).replace("/", ".") for n in z.namelist() if n.endswith(".class") and "/" in n}
    except (zipfile.BadZipFile, OSError):
        return set()


def has_classes(path):
    """True when the jar holds at least one .class file (PLM-23: okio-3.5.0.jar is a Kotlin multiplatform metadata jar,
    okio-jvm-3.5.0.jar holds the classes). False for an unreadable file too, so fake empty jars behave as before."""
    return bool(jar_packages(path))


def is_imported(path, imports):
    pk = jar_packages(path)
    return any(i == p or i.startswith(p + ".") or p.startswith(i + ".") for p in pk for i in imports)


NEEDS_VENDORLIB = set()   # ids of userlib jars whose removal rests on a vendorlib copy (T5-16)
SBOMS = ("vendorlib-sbom.json", "vendorlib/vendorlib-sbom.json", "vendorlib/sbom.json", ".stepupdate/vendorlib-sbom.json")
SHADOWED = []  # (older userlib jar, newer vendorlib jar, owners): two majors of one library on the classpath (PLM-24)
UPDATED = {}   # --updated / --updated-from-git: module (lower case) -> where it was seen; their markers on older copies are leftovers


def needs_older_major(project, extra, r, g, top):
    """(owners, notes). owners: present modules that declare this older copy, declare no newer copy, and whose version
    differs in MAJOR from the one kept: removing it could break that module (pdfbox 2 -> 3), so the copy is kept; ''
    when none. A module whose installed package can be read is an owner only when that package ships the jar; else
    one that was updated (--updated, --updated-from-git) is not (its marker is the old version's). notes: why a
    declaring module is no owner (B4N1-7, B4T2-10)."""
    if vkey(r["ver"])[0][:1] == vkey(top["ver"])[0][:1]:
        return "", []
    newer = {m for x in g if vkey(x["ver"]) > vkey(r["ver"]) for m in x["mods"]}
    owners, notes = [], []
    for m in sorted(r["mods"]):
        if not module_known(project, m, extra) or m in newer:
            continue
        pk = package_userlib(project, m)
        if pk is not None:
            if r["name"] in pk[0]:
                owners.append(m)
            else:
                notes.append(f"leftover marker: {m}'s installed package {pk[1]} ships no {r['name']}")
        elif m.lower() in UPDATED:
            notes.append(f"leftover marker: {m} was updated ({UPDATED[m.lower()]})")
        else:
            owners.append(m)
    return ",".join(owners), notes


def lone_class_packages(r, top):
    """Packages (sorted) that jar r holds classes for and the kept jar top does not (PLM-23). Only when r is the same
    version as top, or top holds no classes at all: a newer version may legitimately drop a package (a split artifact is
    UNMATCHED's business). Empty for jars that are not zips."""
    mine = jar_packages(r["path"])
    if not mine:
        return []
    theirs = jar_packages(top["path"])
    if vkey(r["ver"]) == vkey(top["ver"]) or not theirs:
        return sorted(mine - theirs)
    return []


def newest(paths):
    t = 0
    for p in paths:
        try:
            t = max(t, os.path.getmtime(p))
        except OSError:
            pass
    return t


def module_set_changed(project):
    """(mtime, what) of the last change to the set of modules: newest RequiredLib marker, .mpr, mprcontents file."""
    ul = os.path.join(project, "userlib")
    cand = [(os.path.join(ul, f), "userlib marker " + f) for f in (os.listdir(ul) if os.path.isdir(ul) else [])
            if f.endswith(".RequiredLib")]
    cand += [(os.path.join(project, f), f) for f in os.listdir(project) if f.endswith(".mpr")]
    for root, _, fs in os.walk(os.path.join(project, "mprcontents")):
        cand += [(os.path.join(root, f), "mprcontents") for f in fs]
    best = (0, "no module marker or .mpr")
    for p, what in cand:
        t = newest([p])
        if t > best[0]:
            best = (t, what)
    return best


def vendorlib_proof(project, synced):
    """(current?, text). Current = stated by the caller, or an SBOM newer than the last module-set change (T5-16)."""
    if synced:
        return True, "vendorlib current: stated with --vendorlib-synced"
    changed, what = module_set_changed(project)
    for rel in SBOMS:
        t = newest([os.path.join(project, rel)])
        if t and os.path.getsize(os.path.join(project, rel)) > 0 and t >= changed:
            return True, f"vendorlib current: {rel} is newer than the last module change ({what})"
    found = [rel for rel in SBOMS if os.path.exists(os.path.join(project, rel))]
    return False, ("vendorlib is stale: " + (f"{found[0]} is older than the last module change ({what})" if found else
                   f"no vendorlib SBOM ({', '.join(SBOMS[:2])}) and the last module change is {what}")
                   + "; run mx sync-java-dependencies (or sync by hand) and rerun, or pass --vendorlib-synced")


def plan(project, extra=frozenset()):
    ul, vl = os.path.join(project, "userlib"), os.path.join(project, "vendorlib")
    if not os.path.isdir(project):
        print(f"jardedupe: {project}: not a folder (resolved from {os.getcwd()}); give the app folder that holds the .mpr",
              file=sys.stderr); sys.exit(2)
    if not os.path.isdir(ul) and not os.path.isdir(vl):
        print(f"jardedupe: {project}: no userlib/ and no vendorlib/: not a Mendix app folder (give the folder that holds "
              f"the .mpr)", file=sys.stderr); sys.exit(2)
    jars = {}   # "dir/name" -> dict
    for d, p in (("userlib", ul), ("vendorlib", vl)):
        fs = os.listdir(p) if os.path.isdir(p) else []
        for j in sorted(f for f in fs if f.endswith(".jar")):
            ident = classifier_identity(j, jar_identity(os.path.join(p, j)))
            ms, mods, mv = markers_of(fs, j) if d == "userlib" else ([], [], [])
            jars[f"{d}/{j}"] = dict(id=f"{d}/{j}", dir=d, name=j, art=ident["key"], ver=ident["ver"], ident=ident,
                                    markers=ms, mods=mods, mv=mv, path=os.path.join(p, j))
    out = []    # (action, jar, reason, rule)
    imports = None
    gone = set()
    copies = {i: len(ids) for _, ids in group_by_identity([(r["id"], r["ident"]) for r in jars.values()]) for i in ids}
    # rule 3 input (N3-17, T1R-13): a module's version = the installed one in the .mpr when it can be read, else its
    # newest versioned marker. top = newest marker version; when the .mpr says newer, no userlib marker is current:
    # the module moved its jars to vendorlib, and removing the old userlib copies rests on vendorlib (T5-16).
    top = {}
    for r in jars.values():
        for _, mod, v in r["mv"]:
            if v and (mod not in top or vkey(v) > vkey(top[mod])):
                top[mod] = v
    inst = installed_versions(project) if top else {}
    cur = {m: (inst[m] if inst.get(m) and vkey(inst[m])[0] and vkey(inst[m]) > vkey(v) else v) for m, v in top.items()}
    src = {m: ("installed in the .mpr" if cur[m] != top[m] else "newest marker") for m in cur}

    def protected(r, why):
        """KEEP line when app or add-on Java may need the jar (T2R3-6); None when it may go. A jar with another copy of
        its artifact is left to rule 1 (which always keeps the newest): ('DEFER', ...)."""
        nonlocal imports
        if imports is None:
            imports = imported_packages(project)
        users = addon_users(r["path"], project)
        bad = addon_java(project)[1]
        if is_imported(r["path"], imports):
            k = f"IMPORTED by javasource although {why}: review by hand"
        elif users:
            k = f"NEEDED BY ADD-ON {','.join(users)} (its Java imports this jar's packages) although {why}"
        elif bad:
            k = f"UNPROVEN: {why}, but the Java of add-on(s) {'; '.join(bad)} cannot be read: review by hand"
        else:
            return None
        return ("DEFER", k) if copies.get(r["id"], 1) > 1 else ("KEEP", k)

    # rules 2 and 3: userlib jars no present module version claims
    cand = []
    for r in jars.values():
        if r["dir"] != "userlib" or not r["mods"]:
            continue
        gone_m = sorted({mod for _, mod, _ in r["mv"] if not module_known(project, mod, extra)})
        old = [(f, mod, v) for f, mod, v in r["mv"] if mod not in gone_m and v and vkey(v) < vkey(cur[mod])]
        live = [x for x in r["mv"] if x[1] not in gone_m and x not in old]
        if live:
            for f, mod, v in old:   # a leftover marker on a jar that a current marker still claims: the marker goes alone
                out.append(("REMOVE", dict(id=f"userlib/{f}", dir="userlib", name=f, art=r["art"], ver=r["ver"], markers=[f],
                                           mods=[mod], mv=[], path=None),
                            f"OLD-MARKER: {mod} {v}, the module is {cur[mod]} ({src[mod]}); {r['name']} stays "
                            f"({', '.join(x[1] + (' ' + x[2] if x[2] else '') for x in live)})", 3))
            continue
        parts = ([f"module(s) {','.join(gone_m)} not in the app"] if gone_m else []) + \
                [f"{mod} {v} is an old version (now {cur[mod]}, {src[mod]})" for mod, v in sorted({(m, v) for _, m, v in old})]
        cand.append((r, "; ".join(parts), 2 if not old else 3, gone_m))
        if any(cur[m] != top[m] for _, m, _ in old):
            NEEDS_VENDORLIB.add(r["id"])
    # orphan markers: a RequiredLib file whose jar is not in userlib says nothing any more (T1R-13, N3-17)
    ufs = os.listdir(ul) if os.path.isdir(ul) else []
    for f in sorted(ufs):
        m = re.match(r"^(.+?\.jar)\.(.+)\.RequiredLib$", f)
        if m and m.group(1) not in ufs:
            out.append(("REMOVE", dict(id=f"userlib/{f}", dir="userlib", name=f, art="", ver="", markers=[f], mods=[],
                                       mv=[], path=None), f"ORPHAN marker: {m.group(1)} is not in userlib", 3))
    # a gone module's jars are one dependency set: when add-on Java imports one of them (java-jwt), the rest (jackson,
    # codec) are its runtime dependencies, which no import line shows. The whole set stays (T2R3-6: all 6 OIDC jars).
    dec = [(r, why, rule, gm, protected(r, why)) for r, why, rule, gm in cand]
    need = {}
    for r, _, _, gm, p in dec:
        if p and p[1].startswith("NEEDED BY ADD-ON"):
            for m in gm:
                need.setdefault(m, []).append(r["name"])
    for r, why, rule, gm, p in dec:
        via = sorted({m for m in gm if m in need})
        if p is None and via:
            p = ("KEEP", f"NEEDED BY ADD-ON: {', '.join(via)} jar set that add-on Java uses "
                         f"({', '.join(sorted({n for m in via for n in need[m]}))}); kept as its dependency although {why}")
        if p and p[0] == "KEEP":
            out.append(("KEEP", r, p[1], rule))
        elif p:
            continue   # rule 1 decides between the copies; the jar is not 'gone'
        else:
            out.append(("REMOVE", r, ("STALE: " if rule == 2 else "OLD-VERSION: ") + why, rule)); gone.add(r["id"])
    # rule 1: duplicates among what is left
    left = [r for r in jars.values() if r["id"] not in gone]
    for art, ids in group_by_identity([(r["id"], r["ident"]) for r in left]):
        g = [jars[i] for i in ids]
        if len(g) < 2:
            continue
        if any(not r["ver"] or not vkey(r["ver"])[0] for r in g):
            for r in g:
                out.append(("KEEP", r, f"AMBIGUOUS: {art} has {len(g)} copies and a version that cannot be read", 1))
            continue
        top = max(g, key=lambda r: (vkey(r["ver"]), r["dir"] == "vendorlib", has_classes(r["path"])))   # PLM-23: same version, the one with classes wins
        decl = sorted({f"{m} {r['ver']}" for r in g if r["dir"] == "userlib" for m in r["mods"] if module_known(project, m, extra)})
        dn = f"; declared by present modules: {', '.join(decl)}" if decl else ""
        out.append(("KEEP", top, f"newest of {len(g)} copies of {art} ({top['ver']}){dn}", 1))
        for r in g:
            if r is top:
                continue
            sole = lone_class_packages(r, top)
            if sole:   # PLM-23: never drop the only jar that holds the classes of a package
                out.append(("KEEP", r, f"ONLY COPY WITH CLASSES for {', '.join(sole[:3])}{' ...' if len(sole) > 3 else ''}: "
                                       f"{top['id']} ({top['ver']}) has none of them; kept: review by hand", 1))
            elif r["dir"] == "vendorlib" and top["dir"] == "userlib" and vkey(r["ver"]) < vkey(top["ver"]):
                out.append(("KEEP", r, f"managed vendorlib {art} {r['ver']} is older than userlib {top['ver']}: review by hand", 1))
            elif needs_older_major(project, extra, r, g, top)[0]:
                owners = needs_older_major(project, extra, r, g, top)[0]
                out.append(("KEEP", r, f"CONFLICT {art}: present module(s) {owners} "
                                       f"declare {r['ver']} and no newer copy, major differs from {top['ver']}: review by hand", 1))
                if top["dir"] == "vendorlib" and r["dir"] == "userlib":
                    SHADOWED.append((r, top, owners))
            else:
                if vkey(r["ver"]) != vkey(top["ver"]):
                    why = f"older than {top['id']}"
                else:
                    why = "same version in vendorlib" if top["dir"] == "vendorlib" else f"same version as {top['id']} under another file name"
                notes = needs_older_major(project, extra, r, g, top)[1]
                out.append(("REMOVE", r, f"DUPLICATE {art}: {why}" + "".join(f"; {n}" for n in notes), 1))
                if r["dir"] == "userlib" and top["dir"] == "vendorlib":
                    NEEDS_VENDORLIB.add(r["id"])
    # UNMATCHED (NS-3): a module moved its jars to vendorlib (a userlib copy of one of its jars goes as a DUPLICATE of a
    # vendorlib copy), yet another userlib jar with that module's marker has no copy anywhere and so got no line at all.
    # notification-service a06afe60: netty 4.2 split netty-codec into netty-codec-base, -compression, ...; the old
    # userlib/netty-codec-4.1.119.Final.jar stayed silent next to 14 removals and was deleted by hand. Never removed here
    # (no identity proves the split), but named, so a human decides.
    seen = {x[1]["id"] for x in out}
    moved = {m for x in out if x[0] == "REMOVE" and x[3] == 1 and x[1]["id"] in NEEDS_VENDORLIB for m in x[1]["mods"]}
    for r in jars.values():
        if r["dir"] != "userlib" or r["id"] in seen or not set(r["mods"]) & moved:
            continue
        grp = r["art"].split(":")[0] if ":" in r["art"] else ""
        sib = sorted(v["name"] for v in jars.values() if v["dir"] == "vendorlib" and grp and v["art"].split(":")[0] == grp
                     and v["art"] != r["art"] and v["art"].startswith(r["art"] + "-"))
        hint = f"; vendorlib has {', '.join(sib)}: a renamed or split artifact?" if sib else ""
        out.append(("UNMATCHED", r, f"no copy in vendorlib although {','.join(sorted(set(r['mods']) & moved))} moved its "
                                    f"other jars there{hint}: review by hand (remove it when the new artifacts replace it)", 1))
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("project"); ap.add_argument("--apply", action="store_true"); ap.add_argument("--tsv")
    ap.add_argument("--log"); ap.add_argument("--modules", default="")
    ap.add_argument("--vendorlib-synced", action="store_true", help="state that vendorlib is current (sync ran, or a "
                    "host-Maven fallback filled it); recorded in the output. Without it --apply needs a fresh SBOM")
    ap.add_argument("--updated", default="", help="modules just updated (stepupdate passes them): their old markers "
                    "do not protect an older major version")
    ap.add_argument("--updated-from-git", action="store_true", help="also every module with a 'step: <Module> <version>' "
                    "commit in the app's git history (B4T2-10)")
    ap.add_argument("--cid", action="append", default=[], help="Module=ID content id, to find the installed package in "
                    "the .mpk cache when the .mpr records none (B4N1-7)")
    a = ap.parse_args()
    for m in a.updated.split(","):
        if m.strip():
            UPDATED[m.strip().lower()] = "--updated"
    for c in a.cid:
        k, _, v = c.partition("=")
        if not k or not v.strip().isdigit():
            print(f"jardedupe: --cid takes Module=ID (digits): {c}", file=sys.stderr); sys.exit(2)
        CIDS[k.strip().lower()] = v.strip()
    gitnote = ""
    if a.updated_from_git:
        sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
        from keptdeps import git_updated
        g, err = git_updated(os.path.abspath(a.project))
        if g is None:   # fewer modules counted as updated = more kept, never more removed
            gitnote = f"updated-from-git: {err.splitlines()[0] if err else 'git log failed'}; only --updated counts"
        for m in g or []:
            UPDATED.setdefault(m.lower(), "a 'step:' commit")
    extra = {m.strip().lower() for m in a.modules.split(",") if m.strip()}
    a.project = os.path.abspath(a.project)   # T1R-13: errors and removals name the resolved folder
    res = plan(a.project, extra)
    lines = []
    for act, r, why, _ in sorted(res, key=lambda x: (x[0] != "REMOVE", x[1]["id"])):
        mk = f"  markers: {','.join(r['mods'])}" if r["mods"] else ""
        rv = "  (rests on vendorlib)" if act == "REMOVE" and r["id"] in NEEDS_VENDORLIB else ""
        lines.append(f"{act:<8} {r['id']}  {why}{mk}{rv}")
    if gitnote:
        lines.append(gitnote)
    remall = [x for x in res if x[0] == "REMOVE"]
    rem = [x for x in remall if x[1]["path"]]            # jars (with their markers)
    nalone = len(remall) - len(rem)                      # OLD-MARKER / ORPHAN: markers removed without a jar (rule 3)
    nmark = sum(len(x[1]["markers"]) for x in remall)
    nstale = sum(1 for x in rem if x[3] == 2)
    nold = sum(1 for x in rem if x[3] == 3)
    lines.append(f"summary: {len(rem)} jars to remove ({len(rem) - nstale - nold} duplicate versions, {nstale} stale, "
                 f"{nold} old module version; {nmark} RequiredLib markers, {nalone} of them alone: old or orphan), "
                 f"{sum(1 for x in res if x[0] == 'KEEP')} listed as kept"
                 + (f", {sum(1 for x in res if x[0] == 'UNMATCHED')} UNMATCHED (review by hand)"
                    if any(x[0] == "UNMATCHED" for x in res) else ""))
    # PLM-24: an older MAJOR kept in userlib while vendorlib has the newer one. The module that declares it may only be
    # a leftover marker of an old version (CommunityCommons 9 to 11: PDFBox 2 shadowed PDFBox 3, javac failed in
    # Misc.java). Only the module's installed package, a "step:" commit or --updated can prove that, so it is flagged,
    # never removed on a guess, and named loudly.
    moved = {m for x in res if x[0] == "REMOVE" and x[3] == 1 and x[1]["id"] in NEEDS_VENDORLIB for m in x[1]["mods"]}
    for r, top, owners in SHADOWED:
        mv = sorted(set(owners.split(",")) & moved)
        hint = (f"; {','.join(mv)} already moved other jars to vendorlib, so this is probably a leftover of its old version"
                if mv else "")
        lines.append(f"SHADOWED {r['id']}  older major {r['ver']} next to {top['id']}{hint}; if {owners} was updated rerun "
                     f"with --updated {owners.split(',')[0]} (or --updated-from-git, --cid), else check the build for it")
    if SHADOWED:
        lines.append(f"shadowed: {len(SHADOWED)} older-major userlib jars sit next to a newer vendorlib copy (javac and the "
                     f"runtime may load either)")
    held = sorted(x[1]["id"] for x in rem if x[1]["id"] in NEEDS_VENDORLIB)
    current, proof = vendorlib_proof(a.project, a.vendorlib_synced) if held else (True, "vendorlib not needed for any removal")
    lines.append(f"{'vendorlib-proof' if current else ('REFUSED' if a.apply else 'WARNING')}: {proof}" + ("" if current else f" ({len(held)} userlib jars rest on it)"))
    if a.apply and not current:
        print("\n".join(lines)); sys.stderr.write(f"jardedupe: {proof}; nothing removed\n")
        if a.log:
            with open(a.log, "w") as f:
                f.write("\n".join(lines) + "\n")
        sys.exit(2)
    if a.apply:
        for _, r, _, _ in remall:
            for f in ([r["path"]] if r["path"] else []) + [os.path.join(a.project, "userlib", m) for m in r["markers"]]:
                os.remove(f)
        lines.append(f"removed {len(rem)} jars and {nmark} markers; rerun mx check and the quick start")
    else:
        lines.insert(0, "jardedupe: dry run (add --apply to delete)")
    print("\n".join(lines))
    if a.log:
        with open(a.log, "w") as f:
            f.write("\n".join(lines) + "\n")
    if a.tsv:
        with open(a.tsv, "w") as f:
            for _, r, why, _ in remall:
                f.write(f"{r['id']}\t{r['art']}\t{r['ver']}\t{why}\tmarkers:{','.join(r['mods'])}\n")
    sys.exit(0 if a.apply else (1 if remall else 0))


if __name__ == "__main__":
    main()
