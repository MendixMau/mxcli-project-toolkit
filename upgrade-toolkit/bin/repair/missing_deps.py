#!/usr/bin/env python3
"""missing_deps.py: after a headless module update, list modules and widgets the model needs but the project lacks.

`mxcli marketplace update` installs the module package only. Dependencies of the NEW version are not installed:
SAML20 4.x needs the UserCommons module, OQL 4.2.0 needs the Markdown viewer widget, TaskQueueHelpers 3.1.0 needs the
Charts 6.x widgets, an Atlas update needs Pop-up Menu. mx check then reports CE0462 or unknown-element errors, without
saying which package to install. This script names them.

  missing_deps.py <app.mpr|dir> [--json out.json] [--catalog FILE] [--target <Mendix version>]

Each missing module or widget gets its Marketplace content id from the local catalog mxcli keeps
(~/.mxcli/marketplace-catalog-default.json, or UPG_CATALOG / --catalog), so a search that times out or answers 503 does
not block the repair (E4 27). Match: the module name, or the last part of the widget id, equals the catalog name with
case, spaces and punctuation ignored. The catalog holds only the latest version and its minimum Mendix version: when
that minimum is above the target, run `mxcli marketplace versions <id>` for an older one. No match is said, not guessed.
Platform widgets (com.mendix.widget.web.*) ship in packages with another name: PLATFORM_WIDGETS maps them (Column chart
and Pie chart are in Charts, Markdown in Markdown viewer; E7-6, where the plain name matched nothing for the charts and
a third-party "Markdown" for Mendix's widget). A com.mendix widget lists Mendix-published packages only when one
matches. --target <ver> marks every candidate whose minimum Mendix version is above it and lists those last.

Modules: qualified names in reference fields (Entity, Microflow, Attribute, Page, ...) whose module does not exist.
Excluded documents (Excluded=true, also Atlas building blocks) are skipped: they are not built.
Widgets: pluggable widget ids used on pages/snippets/layouts with no widgets/*.mpk that declares them.
Broken widget packages (zip CRC error or unreadable, E5 F22: every update then prints "skipping <widget>") are listed as
BROKEN: replace the .mpk from the Marketplace. They count as a finding, also when they were already broken before.
Add-on modules (modules/*.mxmodule, T2-2) are not in the .mpr: a referenced module that is one is reported as
ADD-ON (.mxmodule, built with X), not MISSING, and is not a finding. Matched by file name or by the module names inside.
With --target 11.x every add-on built before 10.21 is a finding too, referenced or not: "ADD-ON ... BLOCKS Mendix 11
(built before 10.21, CE1893)". Route: a newer vendor build on the 10.24 rung, idcheck, then convert (playbook 10-to-11).
With --target 11 or later, the deprecated Charts 3.x widgets (com.mendix.widget.custom.PieChart, ColumnChart,
TimeSeries, ... ; DEPRECATED_11) are listed as DEPRECATED-11 with the documents that use them: they build and pass
mx check but fail at runtime on Mendix 11 ("Could not find store"; T7-29, every dashboard page broken). Replace them
with the Charts 6.x widgets before the 11 rung. They count as a finding.
Exit: 0 = nothing missing, 1 = something missing, broken or DEPRECATED-11 (install or replace it, then rerun), 2 = input error.
"""
import argparse, collections, glob, json, os, re, sqlite3, struct, sys, tempfile, uuid, zipfile

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from mxversion import addons as addon_files, below  # noqa: E402  add-on version reader (T2-2)

REF_KEYS = {"Entity", "Microflow", "Nanoflow", "Parameter", "Attribute", "Association", "Page", "Form", "Snippet",
            "Enumeration", "Image", "JavaAction", "JavaScriptAction", "Rule", "Workflow", "Constant", "Generalization",
            "Layout", "Child", "Parent", "ReturnType", "ImageCollection", "ModuleRole", "ModuleRoles"}
QN = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)\.[A-Za-z_][A-Za-z0-9_.]*$")
BUILTIN = {"System", "Administration_System"}
CATALOG = os.environ.get("UPG_CATALOG") or os.path.expanduser("~/.mxcli/marketplace-catalog-default.json")


def norm(s):
    return re.sub(r"[^a-z0-9]", "", (s or "").lower())


def load_catalog(path):
    try:
        return json.load(open(path)).get("items") or []
    except (OSError, ValueError, AttributeError):
        return None


# widget id (lower case, after com.mendix.widget.web. or com.mendix.widget.custom.) -> the Marketplace package that ships it
PLATFORM_WIDGETS = {
    "columnchart": "Charts", "piechart": "Charts", "linechart": "Charts", "barchart": "Charts", "areachart": "Charts",
    "bubblechart": "Charts", "heatmap": "Charts", "timeserieschart": "Charts", "timeseries": "Charts",
    "customchart": "Charts", "chartplayground": "Charts", "markdown": "Markdown viewer",
    "datagrid": "Data Widgets", "gallery": "Data Widgets", "treenode": "Data Widgets", "combobox": "Data Widgets",
    "datagridtextfilter": "Data Widgets", "datagriddatefilter": "Data Widgets", "datagriddropdownfilter": "Data Widgets",
    "datagridnumberfilter": "Data Widgets", "dropdownsort": "Data Widgets", "selectionhelper": "Data Widgets",
}


# T7-29: Charts 3.x widget ids (last part, lower case) that fail at runtime on Mendix 11
DEPRECATED_11 = {"anychart", "areachart", "barchart", "bubblechart", "columnchart", "heatmap", "linechart", "piechart",
                 "polarchart", "timeseries"}


def deprecated_11(wid):
    return wid.lower().startswith("com.mendix.widget.custom.") and wid.rsplit(".", 1)[-1].lower() in DEPRECATED_11


def vtuple(v):
    return tuple(int(x) for x in re.findall(r"\d+", str(v or ""))[:4])


def lookup(cat, name, kind, wid=None, target=None):
    """Catalog entries of type kind ("Module" / "Widget") whose name matches; Mendix-published first."""
    if cat is None:
        return "no local catalog: run `mxcli marketplace search` once, or give --catalog"
    names = [name]
    if wid and wid.lower().startswith("com.mendix.widget."):
        key = wid.lower().split(".")[-2] if wid.count(".") >= 4 else name.lower()
        if key in PLATFORM_WIDGETS:
            names.insert(0, PLATFORM_WIDGETS[key])
    hits = []
    for n in names:
        hits = [x for x in cat if x.get("type") == kind and norm((x.get("latestVersion") or {}).get("name")) == norm(n)]
        if hits:
            break
    if not hits:
        return "no catalog match: search the Marketplace by name"
    if wid and wid.lower().startswith("com.mendix.") and any(x.get("publisher") == "Mendix" for x in hits):
        hits = [x for x in hits if x.get("publisher") == "Mendix"]
    tv = vtuple(target) if target else None
    above = lambda x: bool(tv) and vtuple((x.get("latestVersion") or {}).get("minSupportedMendixVersion")) > tv
    hits.sort(key=lambda x: (above(x), x.get("publisher") != "Mendix", x.get("contentId", 0)))
    out = []
    for x in hits[:3]:
        lv = x.get("latestVersion") or {}
        out.append(f"content {x.get('contentId')} '{lv.get('name')}' latest {lv.get('versionNumber')} "
                   f"(min Mendix {lv.get('minSupportedMendixVersion')}, {x.get('publisher')})"
                   + (f" [min Mendix above target {target}: take an older version from `mxcli marketplace versions {x.get('contentId')}`]" if above(x) else ""))
    return "Marketplace: " + "; ".join(out)


def units(path):
    try:
        import bson
    except ImportError:
        sys.exit("missing_deps: needs the 'bson' module (pip install pymongo)")
    proj = os.path.dirname(os.path.abspath(path))
    con = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    cols = {r[1] for r in con.execute("pragma table_info(Unit)")}
    blob_col = "Contents" if "Contents" in cols else "NULL"
    v2 = {os.path.basename(f)[:-7].lower(): f
          for f in glob.glob(os.path.join(proj, "mprcontents", "**", "*.mxunit"), recursive=True)}
    for uid, blob in con.execute(f"select UnitID, {blob_col} from Unit"):
        if blob is None and v2:
            f = v2.get(str(uuid.UUID(bytes_le=bytes(uid))).lower())
            blob = open(f, "rb").read() if f else None
        if blob:
            try:
                yield bson.decode(blob)
            except Exception:
                continue


def descriptor_error(path, z):
    """Entry with general-purpose flag bit 3 (data descriptor follows) but no valid descriptor after its data.
    Python and unzip take the CRC from the central directory and accept it; Go's archive/zip (mxcli) reads the next 4
    bytes as the CRC and fails with "zip: checksum error" (E5 F22, ListViewControls.mpk)."""
    raw = open(path, "rb").read()
    for i in z.infolist():
        if not i.flag_bits & 8 or i.is_dir():
            continue
        o = i.header_offset
        nl, el = struct.unpack("<HH", raw[o + 26:o + 30])
        end = o + 30 + nl + el + i.compress_size
        tail = raw[end:end + 8]
        crc = struct.unpack("<I", tail[4:8] if tail[:4] == b"PK\x07\x08" else tail[:4])[0] if len(tail) >= 8 else None
        if crc != i.CRC:
            return f"data descriptor missing after {i.filename}: Go zip readers (mxcli) report 'zip: checksum error'"
    return None


def installed_widgets(proj, broken):
    ids = set()
    for mpk in glob.glob(os.path.join(proj, "widgets", "*.mpk")):
        try:
            with zipfile.ZipFile(mpk) as z:
                bad = z.testzip()
                if bad:
                    broken.append(f"{os.path.basename(mpk)} (CRC error in {bad})")
                    continue
                dd = descriptor_error(mpk, z)
                if dd:
                    broken.append(f"{os.path.basename(mpk)} ({dd})")
                for n in z.namelist():
                    if n.endswith(".xml"):
                        ids.update(re.findall(r'<widget[^>]*\sid="([^"]+)"', z.read(n).decode("utf-8", "replace")))
        except (zipfile.BadZipFile, OSError) as e:
            broken.append(f"{os.path.basename(mpk)} ({e})")
    return ids


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("project"); ap.add_argument("--json")
    ap.add_argument("--catalog", default=CATALOG, help="mxcli's local Marketplace catalog (JSON with items[])")
    ap.add_argument("--target", help="target Mendix version: candidates whose minimum is above it are marked and listed last")
    a = ap.parse_args()
    p = a.project
    if os.path.isdir(p):
        mprs = glob.glob(os.path.join(p, "*.mpr"))
        if len(mprs) != 1:
            print(f"missing_deps: {p}: expected one .mpr", file=sys.stderr); sys.exit(2)
        p = mprs[0]
    proj = os.path.dirname(os.path.abspath(p))
    mods, refs, widgets = set(), collections.defaultdict(set), collections.Counter()
    used_in, doc = collections.defaultdict(set), [""]

    def walk(d, key=None):
        if isinstance(d, dict):
            if d.get("$Type") == "CustomWidgets$CustomWidgetType" and d.get("WidgetId"):
                widgets[d["WidgetId"]] += 1
                used_in[d["WidgetId"]].add(doc[0])
            for k, v in d.items():
                walk(v, k)
        elif isinstance(d, list):
            for v in d:
                walk(v, key)
        elif isinstance(d, str) and key in REF_KEYS:
            m = QN.match(d)
            if m:
                refs[m.group(1)].add(d)

    excluded = 0
    for d in units(p):
        if d.get("$Type") in ("Projects$ModuleImpl", "Projects$Module"):
            mods.add(d.get("Name"))
        if d.get("Excluded") is True:  # excluded documents and building blocks are not built: ignore their refs
            excluded += 1
            continue
        doc[0] = d.get("Name") or d.get("$Type", "?")
        walk(d)
    if not mods:
        print("missing_deps: INVALID, no modules read", file=sys.stderr); sys.exit(2)
    addon, blocked = {}, []  # module name -> "ADD-ON (...) file" for modules/*.mxmodule (T2-2)
    for f, v in addon_files(proj):
        label = f"ADD-ON (.mxmodule, built with {v or 'unknown version'})"
        names = {f[:-9]}
        if a.target and a.target.startswith("11.") and below(v, 10, 21):
            blocked.append(f"ADD-ON {f} built with {v}: BLOCKS Mendix {a.target} (built before 10.21, CE1893): "
                           "get a newer vendor build, load it on the 10.24 rung, idcheck, then convert")
        try:
            with tempfile.TemporaryDirectory() as d, zipfile.ZipFile(os.path.join(proj, "modules", f)) as z:
                z.extractall(d)
                inner = glob.glob(os.path.join(d, "**", "*.mpr"), recursive=True)
                if inner:
                    names |= {u.get("Name") for u in units(inner[0]) if u.get("$Type") in ("Projects$ModuleImpl", "Projects$Module")}
        except (OSError, zipfile.BadZipFile, sqlite3.Error):
            pass
        for n in names:
            if n:
                addon[n] = f"{label} {f}"
    missing_mods = {m: sorted(v) for m, v in refs.items() if m not in mods and m not in BUILTIN and m not in addon}
    addon_refs = {m: sorted(v) for m, v in refs.items() if m in addon and m not in mods}
    broken = []
    have = installed_widgets(proj, broken)
    missing_w = sorted(w for w in widgets if w not in have)
    lines = [f"# missing_deps {p}", "", f"modules {len(mods)}, widget types used {len(widgets)}, widget ids installed {len(have)}, "
             f"excluded documents skipped {excluded}"]
    cat = load_catalog(a.catalog) if (missing_mods or missing_w) else []
    found = {}
    for m, v in sorted(missing_mods.items()):
        found[m] = lookup(cat, m, "Module", target=a.target)
        lines.append(f"MISSING module {m}: {len(v)} references, e.g. {', '.join(v[:3])}")
        lines.append(f"  {found[m]}")
    for m, v in sorted(addon_refs.items()):
        lines.append(f"{addon[m]}: module {m}, {len(v)} references, e.g. {', '.join(v[:3])}")
    for w in missing_w:
        found[w] = lookup(cat, w.rsplit(".", 1)[-1], "Widget", wid=w, target=a.target)
        lines.append(f"MISSING widget {w}: used {widgets[w]}x, no widgets/*.mpk declares it")
        lines.append(f"  {found[w]}")
    for b in broken:
        lines.append(f"BROKEN widget package {b}")
    lines += blocked
    dep11 = sorted(w for w in widgets if deprecated_11(w)) if a.target and vtuple(a.target)[:1] >= (11,) else []
    for w in dep11:
        lines.append(f"DEPRECATED-11 widget {w}: used {widgets[w]}x in {', '.join(sorted(used_in[w]))}: Charts 3.x fails at "
                     f"runtime on Mendix 11 (T7-29); replace with the Charts 6.x widget before the 11 rung")
    if not missing_mods and not missing_w and not broken and not blocked and not dep11:
        lines.append("nothing missing")
    print("\n".join(lines))
    if a.json:
        json.dump({"modules": missing_mods, "widgets": missing_w, "broken": broken, "deprecated_11": dep11, "marketplace": found, "addons": addon_refs, "blocked": blocked}, open(a.json, "w"), indent=1)
    sys.exit(1 if missing_mods or missing_w or broken or blocked or dep11 else 0)


if __name__ == "__main__":
    main()
