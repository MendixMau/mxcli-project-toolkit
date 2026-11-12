#!/usr/bin/env python3
"""dojo_report.py: what an app needs before it runs on the React client, and what can and cannot move yet (B6-4).

Why: the Dojo client is deprecated in Studio Pro 11 (the React client is advised) and removed in Mendix 12. A classic
Dojo widget (an .mpk widget that does not declare pluginWidget="true"), a legacy core widget the React client refuses,
and a JavaScript action on the Dojo APIs all stop working on the React client. replacement_check.py rows R8 and R26
say THAT an app holds such things; this report lists WHICH, per widget package, with the React path for each:

  ready          every widget in the package is pluggable (React-compatible)
  delete         a Dojo widget package no page, snippet or layout uses: remove the .mpk (check building blocks first)
  can move       a Dojo widget in use with a React path: a newer pluggable version of the same component, a successor
                 component, or a platform feature (playbooks/dojo-successors.tsv, with its source)
  can't move     a Dojo widget in use for which no React path was found (as of the table's check date): rebuild it as a
                 pluggable widget, or drop the feature
  not researched a Dojo widget in use that the table has no row for: research it, add the row (never guess)
  unreadable     the .mpk cannot be read
Plus: legacy core widgets the React client does not support (the table's core-unsupported rows, matched on the model
$Type in used documents), JavaScript files on the Dojo APIs (the js clause of replacements.tsv row R8) and a custom
index.html under theme/ (unchecked: compare it with the React client's own by hand).

Run by: steps/triage.md step 10 (Release impact), after replacement_check.py; output $W/dojo-react.md.
Reads: the .mpr (via replacement_check.App), widgets/*.mpk, javascriptsource/, theme/. Nothing is written to the app.

  dojo_report.py <app dir | app.mpr> [<app> ...] --to <ver> [--table playbooks/dojo-successors.tsv]
                 [--replacements playbooks/replacements.tsv] [--out dojo-react.md] [--json out.json]
                 [--overview overview.md]

  --out       one app: that file; several apps: a directory, one <app folder>.md each
  --overview  several apps: one table of every Dojo package across the apps, most apps first

Prints one line per app: 'dojo-react <app>: P packages, R ready, M can move, D delete, C can't move, U not researched,
X unreadable; legacy core widgets K in N documents; modules not React-ready Q; Dojo JS F files; <ADVISORY|BLOCKING> for <ver>'.
Target below 12: ADVISORY, exit 0 (the switch is advised, not required). Target 12 or above: BLOCKING when anything but
ready is left, exit 1. Exit 2 = an app or a table cannot be read.
"""
import argparse, json, re, sys, zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from replacement_check import App, read_table, TableError, module_of_path  # noqa: E402

HERE = Path(__file__).resolve().parent
DEFAULT_TABLE = HERE.parent / "playbooks" / "dojo-successors.tsv"
DEFAULT_REPL = HERE.parent / "playbooks" / "replacements.tsv"
COLS = ["match", "component", "installed", "status", "react_path", "min_mendix", "source", "verified", "note"]
MOVE = {"newer-pluggable", "successor", "platform"}
STATUSES = MOVE | {"none-found", "core-unsupported", "module-not-ready"}
NOT_WIDGET = {"core-unsupported", "module-not-ready"}
MAX_XML = 2_000_000  # a widget descriptor is a few kB; a larger member is not read (the ListViewControls zip bomb)
ORDER = ["can't move", "not researched", "unreadable", "can move", "delete", "ready"]


def read_successors(path):
    lines = Path(path).read_text().splitlines()
    head = [i for i, l in enumerate(lines) if l.startswith("match\t")]
    if not head or lines[head[0]].split("\t") != COLS:
        raise TableError(f"{path}: no header line '{chr(9).join(COLS)}'")
    rows = []
    for n, l in enumerate(lines[head[0] + 1:], head[0] + 2):
        if not l.strip() or l.startswith("#"):
            continue
        c = l.split("\t")
        if len(c) != len(COLS):
            raise TableError(f"{path}:{n}: {len(c)} columns, expected {len(COLS)}")
        r = dict(zip(COLS, c))
        if r["status"] not in STATUSES:
            raise TableError(f"{path}:{n}: status '{r['status']}' is not one of {', '.join(sorted(STATUSES))}")
        try:
            r["rx"] = re.compile(r["match"])
        except re.error as e:
            raise TableError(f"{path}:{n}: bad match /{r['match']}/: {e}")
        rows.append(r)
    return rows


def dojo_js_regex(repl):
    """The js clause of row R8, so the Dojo API pattern has one home (replacements.tsv)."""
    for r in read_table(repl):
        if r["id"] == "R8":
            for c in r["detect"].split(" || "):
                if c.strip().startswith("js:"):
                    return re.compile(c.strip()[3:])
    raise TableError(f"{repl}: row R8 has no js: clause")


def read_mpk(f):
    """(version, [(widget id, pluggable)]) or raises."""
    with zipfile.ZipFile(f) as z:
        names = z.namelist()
        pk = z.read("package.xml").decode("utf8", "replace") if "package.xml" in names else ""
        m = re.search(r'<clientModule\b[^>]*\bversion="([^"]+)"', pk)
        ws = []
        for i in z.infolist():
            if not i.filename.lower().endswith(".xml") or i.filename == "package.xml" or i.file_size > MAX_XML:
                continue
            t = z.read(i).decode("utf8", "replace")
            w = re.search(r"<widget\b[^>]*>", t)
            if not w:
                continue
            wid = re.search(r'\bid="([^"]+)"', w.group(0))
            if wid:
                ws.append((wid.group(1), 'pluginWidget="true"' in w.group(0)))
    return (m.group(1) if m else "?"), ws


def lookup(rows, wid):
    return next((r for r in rows if r["status"] not in NOT_WIDGET and r["rx"].fullmatch(wid)), None)


def analyse(path, rows, js_rx):
    app = App(path)
    used = app.widgets()
    pkgs = []
    wdir = app.root / "widgets"
    for f in sorted(wdir.glob("*.mpk")) if wdir.is_dir() else []:
        p = {"package": f.name, "version": "?", "dojo": [], "pluggable": 0, "status": "", "react": "", "source": "",
             "verified": ""}
        try:
            p["version"], ws = read_mpk(f)
        except Exception as e:  # noqa: BLE001 (a bad zip, a CRC error: the package is reported, never dropped)
            p.update(status="unreadable", react=f"{type(e).__name__}: {e}")
            pkgs.append(p)
            continue
        p["pluggable"] = sum(1 for _, plug in ws if plug)
        for wid, plug in ws:
            if not plug:
                p["dojo"].append({"id": wid, "uses": sum(used.get(wid, {}).values()), "docs": sorted(used.get(wid, {}))})
        inuse = [d for d in p["dojo"] if d["uses"]]
        if not p["dojo"]:
            p["status"] = "ready"
        elif not inuse:
            p["status"] = "delete"
        else:
            hits = [(d, lookup(rows, d["id"])) for d in inuse]
            miss = [d["id"] for d, r in hits if r is None]
            found = [r for _, r in hits if r]
            if miss:
                p.update(status="not researched", react=f"no table row for {', '.join(miss)}")
            elif any(r["status"] == "none-found" for r in found):
                r = next(r for r in found if r["status"] == "none-found")
                p.update(status="can't move", react=r["react_path"] or r["note"], source=r["source"],
                         verified=r["verified"])
            else:
                r = found[0]
                path_ = r["react_path"] + (f" (Mendix {r['min_mendix']}+)" if r["min_mendix"] not in ("", "-") else "")
                p.update(status="can move", react=f"{r['status']}: {path_}", source=r["source"], verified=r["verified"])
        pkgs.append(p)

    core = []
    types = app.types()
    for r in rows:
        if r["status"] != "core-unsupported":
            continue
        hosts = {}
        for t, hs in types.items():
            if r["rx"].fullmatch(t):
                for q, n in hs.items():
                    hosts[q] = hosts.get(q, 0) + n
        if hosts:
            core.append({"type": r["match"], "component": r["component"], "count": sum(hosts.values()),
                         "docs": sorted(hosts), "react": r["react_path"], "source": r["source"],
                         "verified": r["verified"]})

    mods = []
    for r in rows:
        if r["status"] != "module-not-ready":
            continue
        hit = sorted(n for n in app.m.modules if n and r["rx"].fullmatch(n))
        if hit:
            mods.append({"modules": hit, "component": r["component"], "react": r["react_path"], "source": r["source"],
                         "verified": r["verified"]})

    js = []
    files = app.files("javascriptsource", {".js", ".jsx", ".mjs", ".ts", ".tsx"}, skip_dirs=("node_modules",)) or {}
    for rel, text in sorted(files.items()):
        hits = sorted({m.group(0) for m in js_rx.finditer(text)})
        if hits:
            mod = module_of_path(rel)
            js.append({"file": rel, "module": mod, "tag": app.tag(mod), "apis": hits})
    theme = app.root / "theme"
    index = sorted(str(f.relative_to(app.root).as_posix()) for f in theme.rglob("index*.html")) if theme.is_dir() else []
    return {"app": Path(app.m.path).resolve().parent.name, "mpr": app.m.path, "packages": pkgs, "core": core, "modules": mods, "js": js,
            "index_html": index}


def counts(r):
    c = {s: sum(1 for p in r["packages"] if p["status"] == s) for s in ORDER}
    return (c, sum(x["count"] for x in r["core"]), len({d for x in r["core"] for d in x["docs"]}), len(r["js"]),
            len(r["modules"]))


def summary(r, to, blocking):
    c, k, n, f, mn = counts(r)
    open_ = sum(c[s] for s in ORDER if s != "ready") + k + f + mn
    verdict = ("BLOCKING" if open_ else "ready") if blocking else "ADVISORY"
    cant = c["can't move"]
    return (f"dojo-react {r['app']}: {len(r['packages'])} packages, {c['ready']} ready, {c['can move']} can move, "
            f"{c['delete']} delete, {cant} can't move, {c['not researched']} not "
            f"researched, {c['unreadable']} unreadable; legacy core widgets {k} in {n} documents; modules not React-ready {mn}; "
            f"Dojo JS {f} files; "
            f"{verdict} for {to}"), open_


def cell(s):
    return str(s).replace("|", "/").replace("\n", " ")


def markdown(r, to, blocking, line):
    out = [f"# Dojo to React client: {r['app']}", "",
           ("Target " + to + (": Mendix 12 removes the Dojo client, so everything below but 'ready' blocks the jump."
                              if blocking else ": the React client is advised on 11, not required; Mendix 12 removes "
                              "the Dojo client. Plan the open items before any 12 attempt.")), "",
           f"## Widget packages ({len(r['packages'])})", "",
           "| status | package | version | Dojo widgets in use (uses) | React path | source |", "|---|---|---|---|---|---|"]
    for p in sorted(r["packages"], key=lambda p: (ORDER.index(p["status"]), p["package"].lower())):
        dw = ", ".join(f"{d['id']} ({d['uses']})" for d in p["dojo"] if d["uses"]) or \
            ("none (all pluggable)" if p["status"] == "ready" else "none")
        src = p["source"] + (f" [{p['verified']}]" if p["verified"] and p["verified"] != "yes" else "")
        out.append(f"| {p['status']} | {cell(p['package'])} | {p['version']} | {cell(dw)} | {cell(p['react'])} | "
                   f"{cell(src)} |")
    out += ["", f"## Legacy core widgets the React client does not support ({len(r['core'])} widget types)", ""]
    if r["core"]:
        out += ["| widget | count | documents | React path | source |", "|---|---|---|---|---|"]
        out += [f"| {cell(x['component'])} | {x['count']} | {cell(', '.join(x['docs'][:8]))}"
                f"{' ...' if len(x['docs']) > 8 else ''} | {cell(x['react'])} | {cell(x['source'])} |" for x in r["core"]]
    else:
        out.append("none in used documents")
    out += ["", f"## Marketplace modules not React-ready ({len(r['modules'])})", ""]
    if r["modules"]:
        out += ["| component | module | React path | source |", "|---|---|---|---|"]
        out += [f"| {cell(x['component'])} | {cell(', '.join(x['modules']))} | {cell(x['react'])} | "
                f"{cell(x['source'])}{' [' + x['verified'] + ']' if x['verified'] not in ('', 'yes') else ''} |"
                for x in r["modules"]]
    else:
        out.append("none of the table's modules")
    out += ["", f"## JavaScript on the Dojo APIs ({len(r['js'])} files)", ""]
    if r["js"]:
        out += ["| file | module | APIs |", "|---|---|---|"]
        out += [f"| {cell(x['file'])} | {x['module']} ({x['tag']}) | {cell(', '.join(x['apis']))} |" for x in r["js"]]
        out.append("")
        out.append("A Marketplace module's file is fixed by updating that module; an own module's file is rewritten.")
    else:
        out.append("none")
    out += ["", "## Custom index.html (unchecked)", "",
            ", ".join(r["index_html"]) + ": compare with the React client's index.html by hand" if r["index_html"]
            else "none under theme/", "",
            "'delete' looks at pages, snippets and layouts only: a building block or page template that still holds the "
            "widget breaks when the .mpk goes, so clear those first.", "",
            "'ready' means the package declares pluginWidget=\"true\". The React client also needs a pluggable widget built "
            "with pluggable-widget-tools 9.4.1 or later, which the .mpk does not record: update every widget (R9) and let "
            "Studio Pro's React client check have the last word.", "", line, ""]
    return "\n".join(out)


def overview(results, to):
    agg = {}
    for r in results:
        for p in r["packages"]:
            if p["status"] == "ready":
                continue
            a = agg.setdefault(p["package"], {"apps": {}, "react": "", "uses": 0})
            a["apps"][r["app"]] = p["status"]
            a["uses"] += sum(d["uses"] for d in p["dojo"])
            a["react"] = a["react"] or p["react"]
    out = [f"# Dojo to React client: overview of {len(results)} apps (target {to})", "",
           "Every widget package that is not React-ready in at least one app, most apps first.", "",
           "| package | apps | uses | per app | React path |", "|---|---|---|---|---|"]
    for name, a in sorted(agg.items(), key=lambda x: (-len(x[1]["apps"]), -x[1]["uses"], x[0].lower())):
        per = "; ".join(f"{k}: {v}" for k, v in sorted(a["apps"].items()))
        out.append(f"| {cell(name)} | {len(a['apps'])} | {a['uses']} | {cell(per)} | {cell(a['react'])} |")
    return "\n".join(out + [""])


def major(v):
    m = re.match(r"\s*(\d+)", v or "")
    if not m:
        raise SystemExit(f"dojo_report: --to '{v}' is no version")
    return int(m.group(1))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    ap.add_argument("apps", nargs="+")
    ap.add_argument("--to", required=True)
    ap.add_argument("--table", default=str(DEFAULT_TABLE))
    ap.add_argument("--replacements", default=str(DEFAULT_REPL))
    ap.add_argument("--out")
    ap.add_argument("--json")
    ap.add_argument("--overview")
    a = ap.parse_args()
    blocking = major(a.to) >= 12
    try:
        rows = read_successors(a.table)
        js_rx = dojo_js_regex(a.replacements)
    except (OSError, TableError) as e:
        print(f"dojo_report: {e}", file=sys.stderr)
        sys.exit(2)
    results, rc = [], 0
    for path in a.apps:
        try:
            r = analyse(path, rows, js_rx)
        except Exception as e:  # noqa: BLE001
            print(f"dojo_report: cannot read the app {path}: {e}", file=sys.stderr)
            sys.exit(2)
        line, open_ = summary(r, a.to, blocking)
        r["summary"] = line
        results.append(r)
        print(line)
        if blocking and open_:
            rc = 1
        if a.out:
            dest = Path(a.out)
            if len(a.apps) > 1:
                dest.mkdir(parents=True, exist_ok=True)
                dest = dest / f"{r['app']}.md"
            dest.write_text(markdown(r, a.to, blocking, line))
    if a.overview:
        Path(a.overview).write_text(overview(results, a.to))
    if a.json:
        Path(a.json).write_text(json.dumps(results if len(results) > 1 else results[0], indent=1))
    sys.exit(rc)


if __name__ == "__main__":
    main()
