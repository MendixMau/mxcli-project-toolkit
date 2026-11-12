#!/usr/bin/env python3
"""convertcheck.py: read what `mx convert` really did, never its exit code.

Why: mx convert exits 0 and prints "mx convert finished." also when it reports errors (E6: "The project contains 31
errors", rc=0; Academy 10.18 to 11.15: 4 errors, "finished", success). It also refuses a source it cannot convert
(Mendix 11 converts only from the last Mendix 10 release; 10.18 to 11.15 was refused, AC-1). Reading rc=0 as "done"
hides both. This check reads the log, then proves the conversion from the project file itself: its version must now
be the target.

  convertcheck.py <convert log> <app dir or app.mpr> --target <full version> [--json out.json]

  convertcheck.py --mappings <old app or .mpr> <new app or .mpr> [--json out.json]

Second mode (T2-1): what the convert rewrote INSIDE pages. mx convert 9 to 10 makes implicit call arguments explicit
(a button or data source that called a microflow or page with no ParameterMappings now has them), and inside a data
view whose source is a microflow, nanoflow or association it can bind the argument to the PAGE PARAMETER, a different
(empty) object, where 9.x meant the data view's object. mx check 0, build, start and the data diff all pass; only a
create-and-save journey fails ("Alias is mandatory"). Every call site whose mappings went from empty to explicit is
listed. REVIEW = it sits inside a data view and the mapped object is not provably that data view's object. INFO =
outside any data view, in a list widget, or mapped to the same object. Unknown stays REVIEW (never silently INFO).
`$currentObject` is the innermost data container's object, so inside a data view it is that view's object (INFO;
T2R3-8, B4T2-8: the repair.md row 12 fix for an own flow wrote exactly that and stayed REVIEW).
A REVIEW a person has looked at is answered in writing (B4T2-8), never by a flag that hides it:
  --answer answers.txt   one line per answered site: '<Page>: <site fnmatch> @maps:<hash> # reason (required)'
Every REVIEW line prints its '@maps:<hash>' (12 hex over the site's mappings): the answer holds for that mapping only;
a site whose mapping changed is REVIEW again ("answer pinned to another mapping"). An answered site prints
ANSWERED with the reason, apart from INFO; an answer line that matches no site is printed as STALE (and is no answer).
Exit: 0 = no open REVIEW (INFO and ANSWERED lines are listed), 1 = at least one open REVIEW, 2 = input error.

Errors after a convert are normal: they are the repair backlog of step 4, not a failure of the convert. They are
printed as a number so the run records them; step 4 must bring mx check to 0.
Exit: 0 = CONVERTED (the project version is the target; errors, if any, are printed as the backlog),
1 = NOT CONVERTED (refused, no save line, or the project version is not the target), 2 = input error.
"""
import argparse, fnmatch, hashlib, json, os, re, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mxversion import version as mx_version  # noqa: E402  one version reader for the toolkit

COUNTS = re.compile(r"contains (\d+) errors?, (\d+) warnings?(?: and (\d+) deprecations?)?", re.I)
REFUSED = re.compile(r"not supported|cannot be converted|unsupported|is newer than|is older than", re.I)


def read_log(text):
    r = {"tool": None, "source": None, "errors": None, "warnings": None, "deprecations": None,
         "saved": False, "finished": False, "refused": None}
    m = re.search(r"This is mx convert, version (\S+?)\.?$", text, re.M)
    r["tool"] = m and m.group(1)
    m = re.search(r"mpr file version is '([^']+)'", text)
    r["source"] = m and m.group(1)
    m = COUNTS.search(text)
    if m:
        r["errors"], r["warnings"] = int(m.group(1)), int(m.group(2))
        r["deprecations"] = int(m.group(3)) if m.group(3) else 0
    r["saved"] = bool(re.search(r"Saving the converted", text, re.I))
    r["finished"] = "mx convert finished" in text
    m = next((ln for ln in text.splitlines() if REFUSED.search(ln)), None)
    r["refused"] = m and m.strip()
    return r


def same(a, b):
    """'11.15.0.12345' vs '11.15.0' match on the parts both give."""
    pa, pb = a.split("."), b.split(".")
    n = min(len(pa), len(pb))
    return n >= 3 and pa[:n] == pb[:n]


FLOW_KEYS = ("Microflow", "Nanoflow", "Form", "Page")
LISTS = ("Forms$ListView", "Forms$DataGrid", "Forms$TemplateGrid")


def _var(pm):
    """(kind, name) of one parameter mapping's value: a page parameter, a widget, or an expression."""
    v = pm.get("Variable") if isinstance(pm.get("Variable"), dict) else {}
    if v.get("PageParameter"):
        return "param", str(v["PageParameter"]).split(".")[-1]
    if v.get("Widget"):
        return "widget", str(v["Widget"])
    # 10.x stores the value as an expression in "Argument" (real units: Forms$PageParameterMapping has Argument,
    # Parameter, Variable): "$dataView1" names a widget, "$Param" a page parameter or variable
    arg = str(pm.get("Argument") or pm.get("Expression") or "").strip()
    m = re.fullmatch(r"\$([A-Za-z_]\w*)", arg)
    if m:
        return "ref", m.group(1)
    return "expr", arg or "?"


def call_sites(data):
    """Every flow or page call with a ParameterMappings key in one page, snippet or layout document, as
    {key: dict}. key = widget-name path + ':' + target, '#n' on a repeated key. The ancestors that give an object
    context (data view, list widget) are kept so a site can be judged where it sits. A data view's OWN source call is
    not inside that data view: its arguments are inputs to it."""
    out = {}

    def walk(o, names, ctx, src_of=None):
        if isinstance(o, dict):
            n = o.get("Name") if isinstance(o.get("Name"), str) else None
            names2 = names + [n] if n else names
            ctx2 = ctx
            if n and o.get("$Type") == "Forms$DataView" or n and o.get("$Type") in LISTS:
                ctx2 = ctx + [o]
            if "ParameterMappings" in o:
                pms = [x for x in o["ParameterMappings"] if isinstance(x, dict)]
                tgt = next((str(o[k]) for k in FLOW_KEYS if o.get(k)), "?")
                key = "/".join(names2) + ":" + tgt
                i = 1
                while key in out:
                    i += 1
                    key = "/".join(names2) + ":" + tgt + f"#{i}"
                out[key] = {"maps": [(str(x.get("Parameter", "")).split(".")[-1],) + _var(x) for x in pms],
                            "ctx": ctx, "names": names2, "target": tgt}
            for k, v in o.items():
                # the data source of a data view is evaluated before the view exists: not inside it
                walk(v, names2, ctx if (k == "DataSource" and o.get("$Type") == "Forms$DataView") else ctx2)
        elif isinstance(o, list):
            for v in o:
                walk(v, names, ctx)

    walk(data, [], [])
    return out


def judge(site):
    """('REVIEW'|'INFO', reason) for one site that went from empty to explicit mappings."""
    ctx = site["ctx"][-1] if site["ctx"] else None
    if ctx is None:
        return "INFO", "outside any data view (or the data view's own source call)"
    if ctx.get("$Type") != "Forms$DataView":
        return "INFO", f"inside list widget {ctx.get('Name')}"
    ds = ctx.get("DataSource") if isinstance(ctx.get("DataSource"), dict) else {}
    kind = str(ds.get("$Type", "?")).split("$")[-1]
    sv = ds.get("SourceVariable") if isinstance(ds.get("SourceVariable"), dict) else {}
    own = str(sv.get("PageParameter") or "").split(".")[-1]
    bad = []
    for param, mk, name in site["maps"]:
        if mk in ("widget", "ref") and name in site["names"]:
            continue  # an enclosing widget: the data view itself or a list inside it
        if mk in ("param", "ref") and own and name == own and kind == "DataViewSource":
            continue  # the data view shows that very parameter
        if mk == "ref" and name == "currentObject":
            continue  # T2R3-8 / B4T2-8: $currentObject in a page expression is the innermost data view's object
        bad.append(f"{param} = {'$' + name if mk != 'expr' else name} ({mk})")
    if not bad:
        return "INFO", f"maps the object of data view {ctx.get('Name')}"
    return "REVIEW", (f"in data view {ctx.get('Name')} (source {kind}"
                      + (f" on {own}" if own else "") + f") the object is not what is mapped: {'; '.join(bad)}")


def mappings(old, new):
    """Sites empty in OLD and explicit in NEW: [(verdict, document, key, maps, reason)]. A site only in one model, or
    explicit in both, is not a convert rewrite and is not listed."""
    import mprmodel  # noqa: E402  late: the log mode needs no bson
    docs = {}
    for tag, path in (("old", old), ("new", new)):
        m = mprmodel.Model.load(path)
        docs[tag] = {d.qn: call_sites(d.data) for d in m.all_docs
                     if d.type in ("Forms$Page", "Forms$Snippet", "Forms$Layout")}
    rows = []
    for qn in sorted(set(docs["old"]) & set(docs["new"])):
        for key, s in docs["new"][qn].items():
            o = docs["old"][qn].get(key)
            if o is not None and not o["maps"] and s["maps"]:
                v, why = judge(s)
                rows.append((v, qn, key, s["maps"], why))
    return rows


def maps_hash(maps):
    """12 hex over one site's mappings: what an answer line pins (B4T2-8)."""
    return hashlib.sha256(json.dumps([list(m) for m in maps]).encode()).hexdigest()[:12]


ANSWER = re.compile(r"^(?P<page>[^:\s]+):\s*(?P<site>\S+)\s+@maps:(?P<pin>[0-9a-fA-F]{12})$")


def read_answers(path):
    """'Page: site-pattern @maps:<12 hex> # reason' -> [(page, site pattern, pin, reason, line)]. A line without a
    reason or a pin is an input error: an unpinned answer would hold for any later mapping of that site."""
    out = []
    try:
        lines = open(path).read().splitlines()
    except OSError as e:
        print(f"convertcheck: {e}", file=sys.stderr); sys.exit(2)
    for ln in lines:
        if not ln.strip() or ln.lstrip().startswith("#"):
            continue
        head, _, why = ln.partition("#")
        m = ANSWER.match(head.strip())
        if not why.strip() or not m:
            print(f"convertcheck: {path}: {ln.strip()!r}: write '<Page>: <site> @maps:<hash> # what you checked' "
                  "with the hash the REVIEW line printed", file=sys.stderr); sys.exit(2)
        out.append((m.group("page"), m.group("site"), m.group("pin").lower(), why.strip(), ln.strip()))
    return out


def answer_rows(rows, answers):
    """REVIEW rows an answer covers become ANSWERED (same mapping only). Returns (rows, stale answer lines)."""
    used, res = set(), []
    for v, qn, key, maps, why in rows:
        if v == "REVIEW":
            h, other = maps_hash(maps), None
            for i, (page, pat, pin, reason, _) in enumerate(answers):
                if page != qn or not fnmatch.fnmatchcase(key, pat):
                    continue
                if pin == h:
                    used.add(i)
                    v, why = "ANSWERED", f"{why} (answered: {reason})"
                    break
                used.add(i); other = pin
            if v == "REVIEW":
                why += f"; @maps:{h}" + (f" [answer pinned to another mapping @maps:{other}: look again]" if other else "")
        res.append((v, qn, key, maps, why))
    return res, [a[4] for i, a in enumerate(answers) if i not in used]


def run_mappings(old, new, jpath, answer=None):
    for p in (old, new):
        if not os.path.exists(p):
            print(f"convertcheck: {p}: no such app dir or .mpr", file=sys.stderr); sys.exit(2)
    answers = read_answers(answer) if answer else []
    try:
        rows = mappings(old, new)
    except (SystemExit, Exception) as e:  # noqa: BLE001  an unreadable model is an input error, never "no REVIEW"
        print(f"convertcheck: {e}", file=sys.stderr); sys.exit(2)
    rows, stale = answer_rows(rows, answers)
    for v in ("REVIEW", "ANSWERED", "INFO"):
        for vv, qn, key, maps, why in rows:
            if vv == v:
                print(f"{v:6} {qn}: {key} -> {[(p, n) for p, _, n in maps]}  {why}")
    for ln in stale:
        print(f"STALE  answer matches no call site, not used: {ln}")
    rv = sum(1 for r in rows if r[0] == "REVIEW")
    an = sum(1 for r in rows if r[0] == "ANSWERED")
    print(f"{len(rows)} call sites got an explicit mapping in the new model: {rv} REVIEW, "
          + (f"{an} ANSWERED, " if an else "") + f"{len(rows) - rv - an} INFO")
    if rv:
        print("REVIEW: 9.x bound the implicit argument to the data view's object; open each page, check the mapped "
              "object, and map the data view object where the new one is the page parameter. Only a "
              "create-and-save journey shows this at run time (T2-1). Checked and right as it is: answer it in "
              "writing, '--answer FILE' with '<Page>: <site> @maps:<hash> # what you checked' (B4T2-8)")
    if jpath:
        with open(jpath, "w") as f:
            json.dump([{"verdict": v, "page": qn, "site": k, "maps": [list(m) for m in mp], "why": w}
                       for v, qn, k, mp, w in rows], f, indent=1)
    sys.exit(1 if rv else 0)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("log", nargs="?"); ap.add_argument("app", nargs="?"); ap.add_argument("--target")
    ap.add_argument("--mappings", nargs=2, metavar=("OLD", "NEW"))
    ap.add_argument("--answer", help="--mappings only: '<Page>: <site> @maps:<hash> # reason' per line, a looked-at "
                                     "REVIEW becomes ANSWERED (B4T2-8)")
    ap.add_argument("--json")
    a = ap.parse_args()
    if a.mappings:
        run_mappings(a.mappings[0], a.mappings[1], a.json, a.answer)
    if not (a.log and a.app and a.target):
        ap.error("log, app and --target are required (or use --mappings OLD NEW)")
    try:
        text = open(a.log, errors="replace").read()
    except OSError as e:
        print(f"convertcheck: {e}", file=sys.stderr); sys.exit(2)
    if not re.match(r"^\d+\.\d+\.\d+", a.target):
        print(f"convertcheck: --target {a.target}: not a version", file=sys.stderr); sys.exit(2)
    r = read_log(text)
    try:
        now = mx_version(a.app)
    except Exception as e:  # noqa: BLE001  unreadable mpr is an input error, not a verdict
        print(f"convertcheck: {a.app}: {e}", file=sys.stderr); sys.exit(2)
    if not now:
        print(f"convertcheck: {a.app}: no project version found", file=sys.stderr); sys.exit(2)
    r.update(target=a.target, project_now=now)

    why = []
    if r["refused"]:
        why.append(f"converter refused: {r['refused']}")
        src = r["source"] or now
        if a.target.split(".")[0] == "11" and src.startswith("10.") and not src.startswith("10.24."):
            why.append(f"Mendix 11 converts only from 10.24: convert {src} to the last 10.24 first, gate it, then 11")
    if not r["saved"]:
        why.append("no 'Saving the converted' line: nothing was written")
    if not same(now, a.target):
        why.append(f"project version is {now}, not the target {a.target}")
    r["verdict"] = "NOT CONVERTED" if why else "CONVERTED"
    r["why"] = why

    if why:
        print(f"NOT CONVERTED {r['source'] or '?'} -> {a.target} (the exit code and 'finished' say nothing)")
        for w in why:
            print(f"  - {w}")
    else:
        e = r["errors"]
        print(f"CONVERTED {r['source'] or '?'} -> {now}")
        if e is None:
            print("  error count: not in the log; run mx check before step 4 and record the count")
        else:
            print(f"  {e} errors, {r['warnings']} warnings, {r['deprecations']} deprecations"
                  + (f": REPAIR BACKLOG {e}, step 4 must bring mx check to 0" if e else ""))
    if a.json:
        with open(a.json, "w") as f:
            json.dump(r, f, indent=1)
    sys.exit(1 if why else 0)


if __name__ == "__main__":
    main()
