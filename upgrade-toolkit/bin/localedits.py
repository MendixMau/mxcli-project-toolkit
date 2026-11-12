#!/usr/bin/env python3
"""localedits.py: per Marketplace module, list what was edited locally and mark the data-bearing edits RED.

Why: a module update replaces the module with the new package. A locally added attribute or association is
deleted by the update, and re-creating it afterwards gives it a NEW GUID: the runtime then drops the column or
join table and the data is gone (see idcheck.py). So every RED line here is a decision BEFORE updating.

Three layers:
  1. Domain model (always, fast): the app's module vs the published package of the INSTALLED version
     (downloaded with `mxcli marketplace download`, cached). Compared by name, because installs do not keep
     the package GUIDs. Finds added / removed / changed entities, attributes, associations.
  2. All element kinds (optional, --mxcli-diff, about 1 to 2 min per module): `mxcli marketplace diff --json`,
     which describes every element (pages, microflows, layouts...) on both sides. It needs the mxbuild of the
     project's exact Mendix version; for 10.x on macOS run it in the amd64 container (see --mxcli-cmd).
     A module it cannot diff (package made before 9.18, version not downloadable or not published) is UNKNOWN and
     counts in the summary and the exit code (E4 3). verified=false (elements it cannot describe, such as building
     blocks) and jar-only edits are printed per module (E4 15); both need the force route of stepupdate.sh.
  3. Pages, snippets and layouts (always, fast, E5b 19): per vendor module, pages added or removed and the layout
     each page uses (FormCall.Form), app vs package. A module update puts the package's layout back: in E5b a
     dashboard page that used the app's layout fell back to Atlas_Default, and only a screenshot caught it. Each
     row is a UI edit to save and replay after the update (stepupdate.sh --force-ui saves the edits).
     A layout or snippet present on both sides is also compared by CONTENT (PLM-29: its named widgets and every document
     it points at, ids and geometry left out): a region replaced or a snippet call removed in Atlas_Default is a CHANGED row
     even when mxcli diff is UNKNOWN because the package predates 9.18.

  4. Files outside the model (always, fast, T5-17, T3-21, T3F-9): per vendor module, themesource/<m>/ and
     javascriptsource/<m>/ file by file, and the USER CODE / EXTRA CODE blocks of javasource/<m>/ (bin/usercode.py), app
     vs the cached .mpk of the installed version (bin/themefiles.py: CRLF and "generated" header lines ignored; a JavaScript action file compares only its import set
     and USER CODE / EXTRA CODE blocks, which is all Studio Pro keeps, B4T2-3, B4N1-5). Each
     difference is a `FILES-EDITED <path>` line and the exit code is 1, like a RED edit: the update replaces these
     files and neither `mxcli marketplace update` nor the model layers above see it (11 brand colours in Atlas_Core
     _variables.scss were lost without a signal, T5-17). A SCSS file lists the "$var: value;" lines that differ.
     Theme and JavaScript edits are UI edits (stepupdate.sh --force-ui saves them and replays the variables into
     theme/web/custom-variables.scss); a Java user-code edit is a logic edit (keep the module).
     --files-only runs this layer alone (stepupdate.sh calls it before each update): exit 0 clean, 1 edited, 2 not comparable.

Usage:
  localedits.py <project.mpr|dir> [--module NAME ...] [--files-only] [--cache DIR] [--json out.json] [--md out.md]
                [--cid NAME=ID ...] [--proxy NAME=VERSION ...] [--installed NAME=VERSION ...]
                [--mxcli-diff] [--mxcli-cmd "prefix"] [--mxcli-project PATH-as-seen-by-prefix]
Exit: 0 no RED and every module judged, 1 RED edits found, 2 incomplete (a module UNKNOWN, no RED) or error.

Env: UPG_MXCLI (default ~/.local/bin/mxcli), UPG_CACHE (default ~/.cache/upgrade-toolkit/mpk; packages are cached as
<content id>-<version>.mpk, so a prepared cache works offline). A package that is not cached needs mxcli: without it
localedits stops at once with one line (exit 2; T4-15, T7-1), instead of a traceback halfway.
NETWORK (batch 1: T2-21, T3-2, T5-2, T6-9, T7-2, T8-5): a download or diff that fails with a TLS handshake timeout,
i/o timeout, connection reset, HTTP 502/503/504 or 429 is retried 3 times after 5, 15 and 45 s (UPG_RETRY_SLEEP).
Still failing, the module is NETWORK, printed apart from UNKNOWN with a "rerun: ... --module A --module B" line. NETWORK
is not judged either (exit 2), but it says "try again", where UNKNOWN says "this package cannot be read".
--cid NAME=ID     content id for a module the MPR records as 0 or not at all (Administration often has 0, E5 F2).
--proxy NAME=VER  the installed version is not downloadable (some old versions answer HTTP 500, and the cutoff is not
                  a date: OQL 2.17.x of 2024 fails too; or the label was never published, E1 5, E4 1, E4 6): compare
                  against VER instead. Probe `mxcli marketplace versions <id>` for the nearest version that downloads.
                  Every difference is then "drift or edit" and still counts (RED stays RED): read the package release
                  notes to tell them apart. A proxy a major version away mixes a lot of drift in (E5b 5): the output
                  says so. --proxy covers layers 1 and 3 only; `mxcli marketplace diff` always fetches the installed
                  version and has no option for another base (E4 8), so layer 2 stays UNKNOWN for those modules.
Packages made before 9.18 cannot be imported by `marketplace update` (it needs --no-baseline, which drops local edits
without naming them, E5 F13 / E1 14). This MPR comparison does not import anything, so run it first and keep the output.

Summary line "force-ui:" lists the modules with UI-only, jar-only or unverified edits: give it to stepupdate.sh
--force-ui (E4 13). UI edits do not change the exit code.

Logic layer (E5b 28): microflows, nanoflows, rules, Java and JavaScript actions and scheduled events present on one
side only are listed as "logic ADDED / REMOVED" (a deleted startup microflow comes back on update). Contents are not
compared; that needs --mxcli-diff. A module with logic edits is never put on the force-ui line.
Entity edits also cover a changed generalization (RED: inherited columns move) and changed validation rules: info,
except on a persistent System.User specialization, where accounts are live data (RED).

RED  = data-bearing edit in a persistent context: entity/attribute/association added, removed, or its storage
       changed (attribute type, persistence, association type or ends).
info = edit without own storage (non-persistent entity, calculated attribute) or a non-domain element.
"""
import argparse, glob, json, os, re, shlex, shutil, sqlite3, subprocess, sys, time, zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import idcheck  # noqa: E402
import mprmodel  # noqa: E402
import themefiles  # noqa: E402

MXCLI = os.environ.get("UPG_MXCLI") or os.path.expanduser("~/.local/bin/mxcli")
CACHE = os.environ.get("UPG_CACHE") or os.path.expanduser("~/.cache/upgrade-toolkit/mpk")
# HTTP 500 is not here: an installed version that answers 500 is not published any more (E1 5, E4 1), a retry cannot help
TRANSIENT = re.compile(r"TLS handshake timeout|i/o timeout|connection reset|HTTP 50[234]|HTTP 429|Too Many Requests")


def backoff():
    try:
        return [float(x) for x in re.split(r"[ ,]+", (os.environ.get("UPG_RETRY_SLEEP") or "5 15 45").strip())]
    except ValueError:
        return [5.0, 15.0, 45.0]


def run_retry(cmd, what):
    """Run cmd; on a transient network error retry after each backoff step. Return (CompletedProcess, transient)."""
    waits = backoff()
    for i in range(len(waits) + 1):
        try:
            r = subprocess.run(cmd, capture_output=True, text=True)
        except OSError as e:  # a --mxcli-cmd prefix that does not exist: exit 2 (incomplete), never 1 (that means RED)
            print(f"localedits: cannot run {cmd[0]}: {e.strerror}", file=sys.stderr); sys.exit(2)
        hit = TRANSIENT.search((r.stderr or "") + (r.stdout or "")) if r.returncode != 0 else None
        if not hit:
            return r, False
        if i == len(waits):
            return r, hit.group(0)
        print(f"localedits: network error on {what} ({hit.group(0)}): retry {i + 1} of {len(waits)} in {waits[i]:g} s",
              file=sys.stderr)
        time.sleep(waits[i])


def modules(mpr):
    import bson
    from mprunits import unit_rows  # NR2-3: MPR v2 has no Contents column
    out = []
    for _uid, _cid, blob in unit_rows(mpr):
        if not blob:
            continue
        try:
            d = bson.decode(blob)
        except Exception:
            continue
        if d.get("$Type") == "Projects$ModuleImpl" and d.get("FromAppStore"):
            out.append({"name": d["Name"], "cid": d.get("AppStorePackageId"), "version": d.get("AppStoreVersion")})
    return sorted(out, key=lambda m: m["name"])


def cached(cid, version, cache):
    mpk = os.path.join(cache, f"{cid}-{version}.mpk")
    return os.path.exists(mpk) or os.path.exists(os.path.join(mpk[:-4], "project.mpr"))


def fetch_pkg(cid, version, cache):
    """Return (project.mpr of the package, None, False) or (None, [error], transient error text or False)."""
    os.makedirs(cache, exist_ok=True)
    mpk = os.path.join(cache, f"{cid}-{version}.mpk")
    if not os.path.exists(mpk):
        r, net = run_retry([MXCLI, "marketplace", "download", str(cid), "--version", version, "-o", mpk],
                           f"download {cid} {version}")
        if r.returncode != 0 or not os.path.exists(mpk):
            return None, (r.stderr or r.stdout).strip().splitlines()[-1:] or ["download failed"], net
    xdir = mpk[:-4]
    xmpr = os.path.join(xdir, "project.mpr")
    if not os.path.exists(xmpr):
        with zipfile.ZipFile(mpk) as z:
            names = [n for n in z.namelist() if n.endswith(".mpr")]
            if not names:
                return None, ["package has no .mpr"], False
            z.extract(names[0], xdir)
            if names[0] != "project.mpr":
                os.rename(os.path.join(xdir, names[0]), xmpr)
    return xmpr, None, False


def domain_diff(app, pkg, mod):
    """app/pkg: idcheck.build() tables. Return list of edits for module mod."""
    edits = []
    def sub(t):
        return {k: v for k, v in t.items() if v["module"] == mod}
    ae, pe = sub(app["entity"]), sub(pkg["entity"])
    for qn in sorted(set(ae) | set(pe)):
        a, p = ae.get(qn), pe.get(qn)
        if a and not p:
            edits.append(("ADDED", "entity", qn, a["persistent"], ""))
        elif p and not a:
            edits.append(("REMOVED", "entity", qn, p["persistent"], ""))
        elif a["persistent"] != p["persistent"]:
            edits.append(("CHANGED", "entity", qn, True, f"persistent {p['persistent']} -> {a['persistent']}"))
        if a and p and a.get("gen") != p.get("gen"):
            edits.append(("CHANGED", "entity", qn, a["persistent"] or p["persistent"],
                          f"generalization {p.get('gen') or 'none'} -> {a.get('gen') or 'none'} (inherited columns move)"))
        if a and p and a.get("vrules") != p.get("vrules"):
            gone = sorted(set(map(tuple, p.get("vrules") or ())) - set(map(tuple, a.get("vrules") or ())))
            new_ = sorted(set(map(tuple, a.get("vrules") or ())) - set(map(tuple, p.get("vrules") or ())))
            what = "; ".join([f"+{r[1].replace('RuleInfo', '')} {r[0].rsplit('.', 1)[-1]}" for r in new_] + [f"-{r[1].replace('RuleInfo', '')} {r[0].rsplit('.', 1)[-1]}" for r in gone])
            if a.get("user") and a["persistent"]:
                edits.append(("CHANGED", "entity", qn, True, f"validation rules ({what}) on a System.User specialization: "
                              "accounts are live data, a lost or added rule changes which accounts save (E5b 28)"))
            else:
                edits.append(("CHANGED", "entity", qn, False, f"validation rules ({what}) (behaviour, not storage; lost on update)"))
        if a and p and a.get("acl") != p.get("acl"):
            edits.append(("CHANGED", "entity", qn, False, "access rules (security, not data; lost on update)"))
    aa, pa = sub(app["attribute"]), sub(pkg["attribute"])
    for qn in sorted(set(aa) | set(pa)):
        a, p = aa.get(qn), pa.get(qn)
        ent = qn.rsplit(".", 1)[0]
        if a and not p:
            if ent in pe:  # attribute added to a package entity (an added entity is reported once, above)
                edits.append(("ADDED", "attribute", qn, a["persistent"], a["type"]))
        elif p and not a:
            if ent in ae:
                edits.append(("REMOVED", "attribute", qn, p["persistent"], p["type"]))
        elif (a["type"], a["stored"]) != (p["type"], p["stored"]):
            edits.append(("CHANGED", "attribute", qn, a["persistent"] or p["persistent"],
                          f"{p['type']}{'' if p['stored'] else ' calc'} -> {a['type']}{'' if a['stored'] else ' calc'}"))
    asc, psc = sub(app["association"]), sub(pkg["association"])
    for qn in sorted(set(asc) | set(psc)):
        a, p = asc.get(qn), psc.get(qn)
        if a and not p:
            edits.append(("ADDED", "association", qn, a["persistent"], f"{a['parent']} -> {a['child']}"))
        elif p and not a:
            edits.append(("REMOVED", "association", qn, p["persistent"], f"{p['parent']} -> {p['child']}"))
        elif (a["type"], a["parent"], a["child"]) != (p["type"], p["parent"], p["child"]):
            edits.append(("CHANGED", "association", qn, a["persistent"] or p["persistent"],
                          f"{p['type']} {p['parent']}->{p['child']}  =>  {a['type']} {a['parent']}->{a['child']}"))
    return [{"change": c, "kind": k, "name": n, "data": bool(d), "detail": x} for c, k, n, d, x in edits]


UI_TYPES = ("Forms$Page", "Forms$Snippet", "Forms$Layout")


def ui_index(model, mod):
    out = {}
    for qn, d in model.docs.items():
        if d.module == mod and d.type in UI_TYPES:
            fc = d.data.get("FormCall") or d.data.get("LayoutCall") or {}
            out[qn] = {"type": d.type.split("$")[1].lower(), "layout": fc.get("Form") if isinstance(fc, dict) else None,
                       "excluded": bool(d.data.get("Excluded"))}
    return out


QN_ONLY = re.compile(r"^[A-Za-z_]\w*\.[A-Za-z_]\w*$")


def content_signature(model, qn):
    """What a layout or snippet is made of, version-neutral (PLM-29): the named widgets (type, name) and every
    qualified name it points at (snippet calls, pages, layouts, microflows). Geometry, ids and design-property format
    are left out, because a package made before 9.18 and the same module after Studio Pro converted it differ there
    without a local edit."""
    d = model.docs.get(qn)
    if d is None:
        return None
    sig = set()

    def walk(x):
        if isinstance(x, dict):
            t = x.get("$Type", "")
            if x.get("Name") and isinstance(x["Name"], str) and ("Forms$" in t or "CustomWidgets$" in t or "Pages$" in t):
                sig.add(f"widget {t.split('$')[-1]} {x['Name']}")
            for k, v in x.items():
                if k not in ("$ID", "$Type") and isinstance(v, str) and QN_ONLY.match(v) and k != "Name":
                    sig.add(f"ref {v}")
                walk(v)
        elif isinstance(x, list):
            for v in x:
                walk(v)
    walk(d.data)
    return sig


def ui_diff(app_model, pkg_model, mod):
    """Pages, snippets and layouts of one module: added, removed, page layout changed (E5b 19)."""
    a, p = ui_index(app_model, mod), ui_index(pkg_model, mod)
    rows = []
    for qn in sorted(set(a) | set(p)):
        x, y = a.get(qn), p.get(qn)
        if x and not y:
            rows.append({"change": "ADDED", "kind": x["type"], "name": qn, "detail": "local document, removed by the update"})
        elif y and not x:
            rows.append({"change": "REMOVED", "kind": y["type"], "name": qn, "detail": "package document deleted locally, comes back on update"})
        elif x["layout"] != y["layout"]:
            rows.append({"change": "CHANGED", "kind": x["type"], "name": qn,
                         "detail": f"layout {y['layout'] or '(none)'} -> {x['layout'] or '(none)'} (the update resets it: replay)"})
        elif x and y and x["type"] in ("layout", "snippet"):
            # PLM-29: the content of a layout or snippet. A package made before 9.18 gives mxcli diff no answer
            # (UNKNOWN), so this is the only layer that sees a local edit of Atlas_Default or Atlas_TopBar.
            sa, sp = content_signature(app_model, qn), content_signature(pkg_model, qn)
            if sa is not None and sp is not None and sa != sp:
                add, gone = sorted(sa - sp), sorted(sp - sa)
                shown = lambda xs: ", ".join(i.replace("widget ", "").replace("ref ", "") for i in xs[:4]) + (" ..." if len(xs) > 4 else "")
                rows.append({"change": "CHANGED", "kind": x["type"], "name": qn,
                             "detail": "content differs from the package"
                                       + (f"; local: {shown(add)}" if add else "") + (f"; package only: {shown(gone)}" if gone else "")
                                       + " (the update puts the package version back: save with --force-ui and replay)"})
    return rows


LOGIC_TYPES = ("Microflows$Microflow", "Microflows$Nanoflow", "Microflows$Rule", "JavaActions$JavaAction",
               "JavaScriptActions$JavaScriptAction", "ScheduledEvents$ScheduledEvent")


def logic_diff(app_model, pkg_model, mod):
    """Microflows, nanoflows, rules, Java and JavaScript actions, scheduled events of one module: present on one side
    only (E5b 28: four startup microflows deleted locally came back with the update). Contents are not compared."""
    def idx(m):
        return {(d.type, qn) for qn, d in m.docs.items() if d.module == mod and d.type in LOGIC_TYPES}
    a, p = idx(app_model), idx(pkg_model)
    rows = []
    for t, qn in sorted(a - p, key=lambda x: x[1]):
        rows.append({"change": "ADDED", "kind": t.split("$")[1].lower(), "name": qn, "detail": "local document, removed by the update"})
    for t, qn in sorted(p - a, key=lambda x: x[1]):
        rows.append({"change": "REMOVED", "kind": t.split("$")[1].lower(), "name": qn,
                     "detail": "package document deleted locally, comes back on update (and runs again if it is wired in)"})
    return rows


def files_layer(app_dir, mpk, mod):
    """(rows, None) or (None, error text): the files outside the model of one module against the installed .mpk (T5-17)."""
    if not os.path.exists(mpk):
        return None, "no .mpk of the installed version in the cache (only an extracted project.mpr)"
    try:
        return themefiles.diff(app_dir, mpk, mod), None
    except (zipfile.BadZipFile, OSError) as e:
        return None, f"{os.path.basename(mpk)}: {e}"


def files_lines(rows):
    return [f"FILES-EDITED {x['path']}  {x['change']}  {x['detail']}" for x in rows]


def classify_error(e):
    e = e or ""
    if "created with version" in e:
        return "package made before 9.18, cannot be imported into this model: compare after convert, or read the release notes"
    if "HTTP 500" in e:
        return "installed version not downloadable; mxcli diff has no base-version option, so --proxy does not reach this layer"
    if "not found" in e:
        return "version label not published; run `mxcli marketplace versions <id>`"
    return e


def mxcli_diff(m, args):
    prefix = args.mxcli_cmd.split() if args.mxcli_cmd else [MXCLI]
    proj = args.mxcli_project or args.mpr
    cmd = prefix + ["marketplace", "diff", str(m["cid"]), "--module", m["name"], "--json", "-p", proj]
    r, net = run_retry(cmd, f"diff {m['name']}")
    try:
        j = json.loads(r.stdout[r.stdout.index("{"):])
        return j, None, False
    except Exception:
        tail = [l for l in (r.stderr + r.stdout).splitlines() if l.strip() and "vibe-coded" not in l]
        return None, " | ".join(tail[-2:]) or f"rc={r.returncode}", net


def files_only(args, mods, cids, proxies, app_dir):
    """--files-only: the files layer alone. Exit 0 clean, 1 edited, 2 not comparable (never 'clean')."""
    out, bad, edited = [], False, False
    for m in mods:
        if m["name"] in cids:
            m["cid"] = int(cids[m["name"]])
        against = proxies.get(m["name"], m["version"])
        entry = dict(m, compared_with=against)
        if not m["cid"]:
            rows, err, net = None, f"content id {m['cid']!r} in the MPR: give --cid {m['name']}=<id>", False
        else:
            _, e, net = fetch_pkg(m["cid"], against, args.cache)
            rows, err = (None, "; ".join(e) + (f" ({net})" if net else "")) if e else files_layer(app_dir, os.path.join(args.cache, f"{m['cid']}-{against}.mpk"), m["name"])
        entry["files"], entry["files_error"] = rows, err
        if rows is None:
            bad = True
            print(f"## {m['name']} {m['version']}: FILES NOT COMPARED ({err}); not 'unedited'")
        else:
            edited = edited or bool(rows)
            print(f"## {m['name']} {m['version']}: " + (f"FILES edits {len(rows)}" if rows else "files unchanged (themesource, javascriptsource, Java user code)"))
            for ln in files_lines(rows):
                print(ln)
        out.append(entry)
    if args.json:
        json.dump(out, open(args.json, "w"), indent=1)
    return 1 if edited else 2 if bad else 0


LOGIC_TYPE = re.compile(r"(?<![A-Z_])(MICROFLOW|NANOFLOW|JAVA_ACTION|JAVASCRIPT_ACTION|WORKFLOW|RULE)(?![A-Z_])")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("project")
    ap.add_argument("--module", action="append")
    ap.add_argument("--cache", default=CACHE)
    ap.add_argument("--cid", action="append", default=[], help="NAME=ID content id override")
    ap.add_argument("--proxy", action="append", default=[], help="NAME=VERSION compare against this published version")
    ap.add_argument("--installed", action="append", default=[],
                    help="NAME=VERSION the installed version when the MPR's AppStoreVersion is stale (F16)")
    ap.add_argument("--json"); ap.add_argument("--md")
    ap.add_argument("--files-only", action="store_true", help="only the files layer (themesource, javascriptsource, Java user code)")
    ap.add_argument("--mxcli-diff", action="store_true")
    ap.add_argument("--mxcli-cmd", help='command prefix for mxcli, e.g. "$RUN/tools/mxcli10.sh" for the 10.x container')
    ap.add_argument("--mxcli-project", help="project path as the prefixed command sees it (container mount)")
    args = ap.parse_args()
    p = args.project
    if os.path.isdir(p):
        mprs = glob.glob(os.path.join(p, "*.mpr"))
        if len(mprs) != 1:
            sys.exit(f"localedits: {p}: expected one .mpr, found {len(mprs)}")
        p = mprs[0]
    args.mpr = os.path.abspath(p)
    app_dir = os.path.dirname(args.mpr)
    app = None if args.files_only else idcheck.build(idcheck.read_mpr(args.mpr))
    mods = [m for m in modules(args.mpr) if not args.module or m["name"] in args.module]
    if not mods:
        print("localedits: no Marketplace modules found (or none matched --module)", file=sys.stderr); sys.exit(2)
    # F16 (Purchase Request 10.24, real run): the WorkflowCommons 3.12.1 and Administration 4.5.0 packages import with a
    # stale AppStoreVersion (2.4.0, 2.0.1), so the files layer compared against 2.4.0 and called 3.12.1's own Java
    # actions "local edits". stepupdate passes the version its own idcheck-PASS step commit installed
    try:
        for x in args.installed:
            k, v = x.split("=", 1)
            for m in mods:
                if m["name"] == k and m["version"] != v:
                    print(f"localedits: {k}: the MPR records {m['version']}, installed is {v} (--installed)", file=sys.stderr)
                    m["version"] = v
    except ValueError:
        print("localedits: --installed takes NAME=VALUE", file=sys.stderr); sys.exit(2)
    try:
        cids = dict(x.split("=", 1) for x in args.cid)
        proxies = dict(x.split("=", 1) for x in args.proxy)
    except ValueError:
        print("localedits: --cid and --proxy take NAME=VALUE", file=sys.stderr); sys.exit(2)
    # T4-15, T7-1: a missing mxcli is one line up front, not a FileNotFoundError traceback in the middle
    need = [m for m in mods if (m["cid"] or m["name"] in cids)
            and not cached(cids.get(m["name"], m["cid"]), proxies.get(m["name"], m["version"]), args.cache)]
    if (need or (args.mxcli_diff and not args.mxcli_cmd)) and not (os.path.isfile(MXCLI) and os.access(MXCLI, os.X_OK)) \
            and not shutil.which(MXCLI):
        print(f"localedits: mxcli not found at {MXCLI} (set UPG_MXCLI, or prepare {args.cache}); needed for "
              + (", ".join(m["name"] for m in need) or "--mxcli-diff"), file=sys.stderr)
        sys.exit(2)
    # PLM-1: mx below 10.0 has no module-import, so mxcli diff cannot run on a 9.x model: say so once, not a failure per module
    if args.mxcli_diff:
        try:
            pv = sqlite3.connect(f"file:{args.mpr}?mode=ro", uri=True).execute("select _ProductVersion from _MetaData").fetchone()[0]
            if int(pv.split(".")[0]) < 10:
                print(f"localedits: --mxcli-diff needs a model of Mendix 10.0 or newer, this one is {pv} (mx below 10 has no "
                      f"module-import). Run it again after the convert, on the 10.x model: that run is the proof.", file=sys.stderr)
                sys.exit(2)
        except (sqlite3.Error, TypeError, ValueError, IndexError):
            pass
    if args.mxcli_cmd and not shutil.which(shlex.split(args.mxcli_cmd)[0]):
        print(f"localedits: --mxcli-cmd {shlex.split(args.mxcli_cmd)[0]}: not found", file=sys.stderr); sys.exit(2)
    if args.files_only:
        sys.exit(files_only(args, mods, cids, proxies, app_dir))
    report, lines, red_total = [], [f"# localedits {args.mpr}", ""], 0
    app_model = None
    unknown_el, partial, force_ui, network, netdiff = [], [], [], {}, {}
    files_total, files_unknown = 0, []
    for m in mods:
        if m["name"] in cids:
            m["cid"] = int(cids[m["name"]])
        entry = dict(m)
        against = proxies.get(m["name"], m["version"])
        entry["compared_with"] = against
        if not m["cid"]:
            pkg_mpr, err, net = None, [f"content id {m['cid']!r} in the MPR: give --cid {m['name']}=<id>"], False
        else:
            pkg_mpr, err, net = fetch_pkg(m["cid"], against, args.cache)
        if net:
            network[m["name"]] = net
        if err:
            entry["domain"] = None; entry["domain_error"] = err; entry["ui"] = None; entry["logic"] = None
        else:
            entry["domain"] = domain_diff(app, idcheck.build(idcheck.read_mpr(pkg_mpr)), m["name"])
            if app_model is None:
                app_model = mprmodel.Model.load(args.mpr)
            pkg_model = mprmodel.Model.load(pkg_mpr)
            entry["ui"] = ui_diff(app_model, pkg_model, m["name"])
            entry["logic"] = logic_diff(app_model, pkg_model, m["name"])
        if err:
            entry["files"], entry["files_error"] = None, "package not readable"
        else:
            entry["files"], entry["files_error"] = files_layer(app_dir, os.path.join(args.cache, f"{m['cid']}-{against}.mpk"), m["name"])
        if args.mxcli_diff:
            j, e, net2 = mxcli_diff(m, args)
            entry["elements"] = j; entry["elements_error"] = e
            if net2:
                netdiff[m["name"]] = net2
        red = [x for x in (entry["domain"] or []) if x["data"]]
        red_total += len(red)
        ui = entry.get("ui") or []
        if entry["domain"] is None and m["name"] in network:
            status = f"NETWORK ({network[m['name']]} after {len(backoff())} retries: not judged, rerun this module)"
        elif entry["domain"] is None:
            status = "UNKNOWN (package not readable: " + "; ".join(entry["domain_error"]) + ")"
        elif red:
            status = f"RED {len(red)}"
        elif entry["domain"]:
            status = "edited (no storage change" + ("" if args.mxcli_diff else "; microflow contents not compared: --mxcli-diff") + ")"
        else:
            status = "domain model unchanged"
        logic = entry.get("logic") or []
        files = entry.get("files") or []
        files_total += len(files)
        if files:
            status += f" | FILES edits {len(files)} (themesource / javascriptsource / Java user code: the update replaces them)"
        elif entry.get("files") is None and not err:
            status += f" | FILES NOT COMPARED ({entry['files_error']})"; files_unknown.append(m["name"])
        if ui:
            status += f" | UI edits {len(ui)} (replay after update)"
        if logic:
            status += f" | LOGIC edits {len(logic)} (documents added or deleted locally: keep the module or replay)"
        el, ui_only, logic_mod = "", bool(ui), []
        if args.mxcli_diff:
            j = entry.get("elements")
            if j:
                mod_ = j.get("modified") or []; unk = j.get("unknown") or []; only = j.get("onlyInstalled") or []
                jars = [x for x in only if str(x).startswith("JAR_DEPENDENCY")]
                el = f" | mxcli diff: {len(mod_)} modified"
                if j.get("verified") is False:
                    el += f", verified=false ({len(unk)} elements not describable)"; partial.append(m["name"]); ui_only = True
                if jars and len(jars) == len(only):
                    el += f", jar-only edits ({len(jars)} JAR_DEPENDENCY)"; ui_only = True
                elif only:
                    el += f", {len(only)} only in the app"
                if mod_:
                    ui_only = True
                # a modified microflow / nanoflow / Java or JavaScript action / workflow / rule is logic: the module
                # never goes on the force-ui line (the update replaces the edit; there is nothing to replay)
                logic_mod = [x for x in mod_ if LOGIC_TYPE.search(json.dumps(x, sort_keys=True).upper())]
                if logic_mod:
                    el += f", {len(logic_mod)} of them logic (microflow, nanoflow, action, workflow, rule: keep the module or replay)"
            elif m["name"] in netdiff:
                el = f" | mxcli diff: NETWORK ({netdiff[m['name']]} after {len(backoff())} retries, rerun)"
            else:
                el = f" | mxcli diff: UNKNOWN ({classify_error(entry['elements_error'])})"; unknown_el.append(m["name"])
        if (ui_only or any(x["kind"] != "java" for x in files)) and not red and not logic and not logic_mod \
                and not any(x["kind"] == "java" for x in files):
            force_ui.append(m["name"])
        px = ""
        if against != m["version"]:
            px = f" [PROXY: compared with {against}; differences are package drift OR local edits"
            if against.split(".")[0] != (m["version"] or "").split(".")[0]:
                px += f"; {against} is a major version away from {m['version']}: expect much drift"
            px += "]"
        lines.append(f"## {m['name']} {m['version']} (content {m['cid']}): {status}{el}{px}")
        for x in entry["domain"] or []:
            lines.append(f"  {'RED ' if x['data'] else 'info'} {x['change']:8} {x['kind']:11} {x['name']}  {x['detail']}")
        for x in ui:
            lines.append(f"  ui   {x['change']:8} {x['kind']:11} {x['name']}  {x['detail']}")
        lines.extend(files_lines(files))
        for x in logic:
            lines.append(f"  logic {x['change']:8} {x['kind']:11} {x['name']}  {x['detail']}")
        for e in (entry.get("elements") or {}).get("modified") or []:
            lines.append(f"  elem modified: {e}")
        for e in (entry.get("elements") or {}).get("unknown") or []:
            lines.append(f"  elem UNKNOWN: {e}")
        report.append(entry)
    unknown = sorted(set([e["name"] for e in report if e["domain"] is None and e["name"] not in network] + unknown_el + files_unknown))
    nets = sorted(set(network) | set(netdiff))
    lines += ["", f"modules: {len(mods)}, RED data-bearing edits: {red_total}, UNKNOWN (not judged): {len(unknown)}"
              + (f" {unknown}: use `mxcli marketplace diff` or a Studio Pro compare; UNKNOWN is never 'no edits'" if unknown else "")
              + f", NETWORK (not judged, transient): {len(nets)}",
              *([f"NETWORK {nets}: a download kept failing on the network after retries; not a verdict on the package.",
                 "rerun: localedits.py " + shlex.quote(args.mpr) + "".join(f" --module {shlex.quote(n)}" for n in nets)
                 + "".join(f" --proxy {shlex.quote(k)}={shlex.quote(v)}" for k, v in proxies.items() if k in nets)
                 + "".join(f" --cid {shlex.quote(k)}={shlex.quote(v)}" for k, v in cids.items() if k in nets)
                 + (" --mxcli-diff" if args.mxcli_diff else "")] if nets else []),
              f"LOGIC edits (documents added or deleted, contents not compared): {sum(len(e.get('logic') or []) for e in report)}",
              f"FILES edits (themesource, javascriptsource, Java user code; exit 1): {files_total}",
              f"UI edits (pages, layouts): {sum(len(e.get('ui') or []) for e in report)}"
              + (f", partially verified (mxcli diff verified=false): {partial}" if partial else ""),
              "force-ui: " + (",".join(force_ui) if force_ui else "none")
              + ("  (stepupdate.sh --force-ui: saves the edits under $W/saved-edits and forces the update; replay them after)" if force_ui else ""),
              "RED rule: do not update and replay these edits blindly. Re-creating an element gives it a new GUID",
              "and the runtime drops its column. Keep the module, or migrate the data, then prove it with idcheck.py",
              "and the regression gate."]
    out = "\n".join(lines)
    print(out)
    if args.md:
        open(args.md, "w").write(out + "\n")
    if args.json:
        json.dump(report, open(args.json, "w"), indent=1)
    sys.exit(1 if red_total or files_total else 2 if unknown or nets else 0)


if __name__ == "__main__":
    main()
