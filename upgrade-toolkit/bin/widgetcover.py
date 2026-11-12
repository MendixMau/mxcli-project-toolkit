#!/usr/bin/env python3
"""widgetcover.py: which widget packages does the gate never render? (MC-19)

Why: the Asset Console 3D viewer widget (3DViewer.mpk 4.0.0, built for an older React) crashed on the 11.12.6 client with
"Could not render widget". Build, check, smoke and journeys all passed (gate exit 0) because no page they open holds the
widget: the frozen data had no configuration for the panel. A widget that no smoke step and no journey renders is not
checked by the gate, whatever its version.

  widgetcover.py <app dir | app.mpr> [--smoke smoke-after.json ...] [--journeys DIR ...] [--rendered FILE]
                 [--waive FILE] [--json out.json]

Packages: every widgets/*.mpk next to the .mpr, with the widget ids its XML declares. A package counts when one of its widget
ids is used on a page, snippet or layout that is not excluded (a package no page uses is a package to delete, not a gap).
Rendered pages: the `target` of every smoke step of kind page (bin/smokewalk.js output, steps that did not PASS do not count);
every string in a journey folder's *.json files that is a page, snippet or layout of the model; `--rendered FILE` (one
qualified page name per line, for a page a hand-written journey opens). A snippet or layout a rendered page references
renders with it.
--waive FILE: "<package file name or widget id> # reason" per line; a line without a reason is INVALID (exit 2).

Output: a header with the denominators, one line per package that no rendered page holds
  UNRENDERED widgets/X.mpk 1.2.0 (widget ids): used on n page(s) (e.g. A.P1, A.P2), none rendered by the walks
  WAIVED widgets/X.mpk (reason)
and a verdict line. Exit: 0 = every used package is rendered, or waived with a reason (verdict `PASS* N waived (reasons)`, which the gate shows as PASS*), 3 = at least one UNRENDERED (the gate reports INVALID:
not checked, never PASS; open the page in a journey, or waive with a reason), 2 = input error (no model, no walk given,
unreadable file, an unreadable widgets/*.mpk, or pages that use custom widgets while widgets/ holds no .mpk: the gate reports
INVALID; PASS means every package was read and the denominator above is real).
"""
import argparse, json, os, re, sys, zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mprmodel  # noqa: E402

DOC = ("Page", "Snippet", "Layout")


def kind(t):
    k = t.split("$")[-1]
    return k if k in DOC else None


def widget_ids(data, out=None):
    out = {} if out is None else out
    if isinstance(data, dict):
        if data.get("$Type") == "CustomWidgets$CustomWidgetType" and isinstance(data.get("WidgetId"), str):
            out[data["WidgetId"]] = out.get(data["WidgetId"], 0) + 1
        for v in data.values():
            widget_ids(v, out)
    elif isinstance(data, list):
        for v in data:
            widget_ids(v, out)
    return out


def package(path):
    """(version, [widget ids]) of an .mpk; None when it is no zip."""
    try:
        with zipfile.ZipFile(path) as z:
            ids, ver = [], ""
            for n in z.namelist():
                if n.lower().endswith(".xml") and not n.startswith("__MACOSX"):
                    t = z.read(n).decode("utf-8", "replace")
                    ids += re.findall(r"<widget\s[^>]*?\bid\s*=\s*\"([^\"]+)\"", t)
                    m = re.search(r"<clientModule\s[^>]*?\bversion\s*=\s*\"([^\"]+)\"", t)
                    ver = ver or (m.group(1) if m else "")
            return ver, list(dict.fromkeys(ids))
    except (zipfile.BadZipFile, OSError, KeyError, NotImplementedError, RuntimeError):
        return None


def jstrings(x):
    if isinstance(x, dict):
        for v in x.values():
            yield from jstrings(v)
    elif isinstance(x, list):
        for v in x:
            yield from jstrings(v)
    elif isinstance(x, str):
        yield x


def waivers(path):
    out = {}
    for n, line in enumerate(open(path), 1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        key, _, why = line.partition("#")
        if not why.strip():
            print(f"widgetcover: {path} line {n}: '{key.strip()}' has no reason after '#'; a waiver without a reason is not accepted",
                  file=sys.stderr)
            sys.exit(2)
        out[key.strip()] = why.strip()
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("app")
    ap.add_argument("--smoke", action="append", default=[])
    ap.add_argument("--journeys", action="append", default=[])
    ap.add_argument("--rendered")
    ap.add_argument("--waive")
    ap.add_argument("--json")
    a = ap.parse_args()
    if not (a.smoke or a.journeys or a.rendered):
        print("widgetcover: give at least one of --smoke, --journeys, --rendered (what the gate walks)", file=sys.stderr)
        return 2
    try:
        model = mprmodel.Model.load(a.app)
        waived = waivers(a.waive) if a.waive else {}
    except SystemExit as e:
        print(e, file=sys.stderr)
        return 2
    base = os.path.dirname(os.path.abspath(model.path))
    docs = {}   # qn -> (kind, {widget id: n}, strings)
    for d in model.all_docs:
        k = kind(d.type)
        if k and not d.data.get("Excluded"):
            docs[f"{d.module}.{d.data.get('Name')}"] = (k, widget_ids(d.data), set(mprmodel.strings(d.data)))
    rendered = set()
    for f in a.smoke:
        try:
            for r in json.load(open(f)).get("roles") or []:
                for s in r.get("steps") or []:
                    if s.get("kind") == "page" and s.get("verdict") in ("PASS", "PASS*") and s.get("target"):
                        rendered.add(s["target"])
        except (OSError, ValueError, AttributeError) as e:
            print(f"widgetcover: {f}: not a smoke walk result ({e})", file=sys.stderr)
            return 2
    for d in a.journeys:
        if not os.path.isdir(d):
            print(f"widgetcover: no journeys folder {d}", file=sys.stderr)
            return 2
        for root, _, files in os.walk(d):
            for fn in files:
                if fn.endswith(".json"):
                    try:
                        rendered.update(s for s in jstrings(json.load(open(os.path.join(root, fn)))) if s in docs)
                    except (OSError, ValueError):
                        pass
    if a.rendered:
        try:
            rendered.update(l.strip() for l in open(a.rendered) if l.strip() and not l.startswith("#"))
        except OSError as e:
            print(f"widgetcover: {e}", file=sys.stderr)
            return 2
    rendered = {q for q in rendered if q in docs}
    # a layout or snippet that a rendered page references renders with it (to a fixpoint through snippets)
    todo = list(rendered)
    while todo:
        q = todo.pop()
        for s in docs[q][2]:
            for mod, name in mprmodel.QN.findall(s):
                t = f"{mod}.{name}"
                if t in docs and docs[t][0] in ("Snippet", "Layout") and t not in rendered:
                    rendered.add(t); todo.append(t)
    wdir = os.path.join(base, "widgets")
    pkgs = sorted(f for f in os.listdir(wdir) if f.endswith(".mpk")) if os.path.isdir(wdir) else []
    used_n = 0
    unread, gaps, res = [], [], []
    for f in pkgs:
        p = package(os.path.join(wdir, f))
        if p is None:
            unread.append(f)
            continue
        ver, ids = p
        hosts = sorted(q for q, (_, w, _) in docs.items() if any(i in w for i in ids))
        if not hosts:
            continue
        used_n += 1
        seen = [q for q in hosts if q in rendered]
        row = {"package": f, "version": ver, "ids": ids, "pages": hosts, "rendered": seen}
        res.append(row)
        if seen:
            continue
        why = waived.get(f) or next((waived[i] for i in ids if i in waived), None)
        if why:
            print(f"WAIVED widgets/{f} ({why})")
            row["waived"] = why
            continue
        gaps.append(f"UNRENDERED widgets/{f}{' ' + ver if ver else ''} ({', '.join(ids[:3])}): used on {len(hosts)} page(s) "
                    f"(e.g. {', '.join(hosts[:3])}), none rendered by the walks")
    print(f"widgetcover: {len(pkgs)} widget package(s) in {wdir}, {used_n} used on a page, {len(rendered)} page/snippet/layout "
          f"documents rendered by the walks" + (f", {len(unread)} package(s) not readable as a zip" if unread else ""))
    # NMR-3: PASS only when measured. An unreadable package (a Git LFS pointer, a truncated download) or a model that uses
    # custom widgets with no package to read them from could not be measured: exit 2, never a PASS.
    model_widgets = sorted({i for _, w, _ in docs.values() for i in w})
    if unread or (not pkgs and model_widgets):
        for f in unread:
            print(f"UNREADABLE widgets/{f}: not a readable zip (a Git LFS pointer or a truncated file?)")
        if not pkgs:
            print(f"NO PACKAGES: {wdir} {'holds no .mpk' if os.path.isdir(wdir) else 'does not exist'}, but pages use "
                  f"{len(model_widgets)} custom widget id(s) (e.g. {', '.join(model_widgets[:3])})")
        print("verdict: INVALID (could not measure: widget packages unreadable or missing; fix the package files, never read this as PASS)")
        return 2
    for g in gaps:
        print(g)
    if gaps:
        print(f"verdict: UNRENDERED ({len(gaps)} of {used_n} used package(s) no smoke step or journey renders: a widget that "
              "crashes on the new client passes the gate. Open one of its pages in a journey or a hand-written walk, or "
              "waive it with a reason)")
    else:
        nw = sum(1 for r in res if r.get("waived"))
        if nw:   # NMR-4: waived gaps are PASS*, with the reasons, so the gate prints PASS* and not a plain PASS
            print(f"verdict: PASS* {nw} waived of {used_n} used package(s) (not rendered by any walk; " +
                  "; ".join(f"{r['package']}: {r['waived']}" for r in res if r.get("waived")) + ")")
        else:
            print(f"verdict: PASS (every used package is rendered by a walk)")
    if a.json:
        json.dump({"packages": res, "unrendered": len(gaps)}, open(a.json, "w"), indent=1)
    return 3 if gaps else 0


if __name__ == "__main__":
    sys.exit(main())
