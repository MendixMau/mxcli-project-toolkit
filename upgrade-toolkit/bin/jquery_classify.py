#!/usr/bin/env python3
"""jquery_classify.py: classify the jQuery use in snippet content, JavaScript actions and widget/theme JS (RA-19 recipe step 1).

Input: files or folders (.js, .html, .htm, .txt, .json of {"name":..,"content":..} snippets). Text under a path is scanned as given.
Each jQuery call is put into ONE category by its purpose and routed to the platform feature that replaces it:
  visibility  show/hide/toggle/addClass/removeClass/toggleClass/css   -> conditional visibility or dynamic classes (no code)
  events      on/click/change/submit/bind/delegate/ready handlers      -> Events widget or on-change nanoflow (no code)
  ajax        $.ajax/$.get/$.post/$.getJSON/load(                      -> microflow REST call (no code)
  values      val/text/html/attr/prop/data on form fields              -> attribute binding (no code)
  animation   animate/fadeIn/fadeOut/slide*                            -> CSS / Atlas (no code)
  plugin      $.fn.x / .datepicker( / .select2( / .dataTable( ...      -> Marketplace pluggable widget (widget)
  other       any other $( / jQuery( use                              -> plain-JS JavaScript action or React widget (code)
Counts per category per file and in total; "needs code" = other + plugin. Each unit also gets the RA-19 class:
  HTML-only  no script (markup only)                          -> HTML Element widget
  JS-light   script that does not walk or change the page DOM  -> JavaScript action called from a nanoflow, triggered by Events
  JS-DOM     script that queries or changes elements (document./querySelector/classList/innerHTML/mx.addOnLoad, or any jQuery
             call except $.ajax)                               -> pluggable widget, or platform widgets, or keep on Dojo for now
Three flags per unit (RA-19, found in a field app):
  bind-once           a snippet with "Refresh on context change" = No (JSON field refreshOnContextChange: false) that binds handlers: they bind
                      once and are lost when the React client redraws the part of the page they were bound to
  programmatic-click  a click made by code: .click() with no handler, .trigger('click'), .get(0).click(), dispatchEvent; replace by calling the
                      button's nanoflow directly (or NanoflowCommons Set Storage Item for a hidden store button)
  dead-code           a function whose only call sites are commented out, or that is never called; likely dead, confirm before dropping
This is a lexical scan: a hit locates, a person decides.
Exit 0 always (it is an inventory, not a gate); exit 2 on usage errors.
"""
import json, os, re, sys

CLASSES = ["HTML-only", "JS-light", "JS-DOM"]
CATS = ["visibility", "events", "ajax", "values", "animation", "plugin", "other"]
ROUTE = {"visibility": "conditional visibility or dynamic classes", "events": "Events widget / on-change nanoflow",
         "ajax": "microflow REST call", "values": "attribute binding", "animation": "CSS / Atlas",
         "plugin": "Marketplace pluggable widget", "other": "plain-JS JavaScript action or React widget"}
NEEDS_CODE = {"plugin", "other"}
JQ = r"(?:\$|jQuery)"
RULES = [  # first match per call decides; order matters
    ("ajax", re.compile(JQ + r"\s*\.\s*(?:ajax|get|post|getJSON|getScript)\s*\(|\.\s*load\s*\(\s*['\"]")),
    ("animation", re.compile(r"\.\s*(?:animate|fadeIn|fadeOut|fadeTo|fadeToggle|slideUp|slideDown|slideToggle)\s*\(")),
    ("visibility", re.compile(r"\.\s*(?:show|hide|toggle|addClass|removeClass|toggleClass|css)\s*\(")),
    ("events", re.compile(r"\.\s*(?:on|off|bind|unbind|delegate|click|change|submit|keyup|keydown|focus|blur|hover|trigger|ready)\s*\(|" + JQ + r"\s*\(\s*(?:document|window|function)\b")),
    ("values", re.compile(r"\.\s*(?:val|text|html|attr|prop|data|append|prepend|empty)\s*\(")),
    ("plugin", re.compile(r"\.\s*(?:datepicker|select2|dataTable|DataTable|autocomplete|tooltip|popover|modal|slick|owlCarousel|sortable|draggable|dialog|chosen|inputmask|mask|fancybox|magnificPopup|tablesorter|summernote)\s*\(")),
]
CALL = re.compile(JQ + r"\s*[(.]")  # a jQuery entry point
CHAIN = re.compile(r"\.\s*[A-Za-z_]\w*\s*\(")


def statements(text):
    """One unit per jQuery entry point: the entry plus its call chain to the end of the statement (';' or a new '$(' / 'jQuery(')."""
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    text = re.sub(r"(?m)(?<![:'\"])//.*$", " ", text)
    pos = [m.start() for m in CALL.finditer(text)]
    for i, s in enumerate(pos):
        end = pos[i + 1] if i + 1 < len(pos) else len(text)
        semi = text.find(";", s, end)
        yield text[s:(semi if semi != -1 else end)]


def classify(stmt):
    for cat, rx in RULES:
        if rx.search(stmt):
            return cat
    return "other"


def scan_text(text):
    out = dict.fromkeys(CATS, 0)
    for st in statements(text):
        out[classify(st)] += 1
    return out


SCRIPT = re.compile(r"<script|javascript:|\bon[a-z]+\s*=|\bfunction\b|=>|\bwindow\.|\bdocument\.|\bmx\.|\$\(|jQuery|\b(?:var|const|let)\s|;\s*(?:\n|$)")
DOM = re.compile(r"\bdocument\.|querySelector|getElementsBy|getElementBy|innerHTML|outerHTML|\.classList|\.style\b|createElement|appendChild|addEventListener|\bmx\.addOnLoad|\bwindow\.mx\b")


def unit_class(text, counts, is_script_file):
    if not is_script_file and not SCRIPT.search(text):
        return "HTML-only"
    if DOM.search(text) or any(counts[k] for k in CATS if k != "ajax"):
        return "JS-DOM"
    return "JS-light"


FLAGS = ["bind-once", "programmatic-click", "dead-code"]
PCLICK = re.compile(r"\.\s*click\s*\(\s*\)|\.\s*trigger\s*\(\s*['\"]click['\"]|\.get\s*\(\s*0\s*\)\s*\.\s*click\s*\(|dispatchEvent\s*\(")


def flags_of(text, counts, meta):
    out = []
    if meta.get("refreshOnContextChange") is False and counts["events"]:
        out.append("bind-once")
    code = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    live = re.sub(r"(?m)(?<![:'\"])//.*$", " ", code)
    if PCLICK.search(live):
        out.append("programmatic-click")
    dead = []
    for fn in sorted(set(re.findall(r"\bfunction\s+([A-Za-z_$][\w$]*)\s*\(", live))):
        calls = len(re.findall(r"(?<!function )\b" + re.escape(fn) + r"\b", live)) - 0
        if calls == 0 and fn:
            dead.append(fn)
    if dead:
        out.append("dead-code")
    return out, dead


def items(path):
    """(name, text) units: a snippet JSON list gives one unit per snippet; any other file is one unit."""
    try:
        raw = open(path, encoding="utf-8", errors="replace").read()
    except OSError:
        return
    if path.lower().endswith(".json"):
        try:
            d = json.loads(raw)
        except ValueError:
            d = None
        if isinstance(d, list) and all(isinstance(x, dict) and "content" in x for x in d):
            for i, x in enumerate(d, 1):
                yield f"{os.path.basename(path)}:{x.get('name') or i}", str(x["content"]), x
            return
    yield path, raw, {}


def main(argv):
    paths = [a for a in argv if not a.startswith("-")]
    as_json = "--json" in argv
    if not paths:
        print("usage: jquery_classify.py [--json] PATH...", file=sys.stderr)
        return 2
    files = []
    for p in paths:
        if os.path.isdir(p):
            for r, _, fs in os.walk(p):
                files += [os.path.join(r, f) for f in sorted(fs) if f.lower().endswith((".js", ".html", ".htm", ".txt", ".json"))]
        elif os.path.isfile(p):
            files.append(p)
        else:
            print(f"jquery_classify: no such path {p}", file=sys.stderr)
            return 2
    rows, total = [], dict.fromkeys(CATS, 0)
    classes = dict.fromkeys(CLASSES, 0)
    flagn = dict.fromkeys(FLAGS, 0)
    for f in sorted(files):
        for name, text, meta in items(f):
            c = scan_text(text)
            cl = unit_class(text, c, name.lower().endswith(".js"))
            fl, dead = flags_of(text, c, meta)
            rows.append((name, c, cl, fl, dead))
            for k in fl:
                flagn[k] += 1
            classes[cl] += 1
            for k in CATS:
                total[k] += c[k]
    n = sum(total.values())
    code = sum(total[k] for k in NEEDS_CODE)
    if as_json:
        print(json.dumps({"units": [{"name": a, "counts": b, "class": c, "flags": f, "dead": d} for a, b, c, f, d in rows], "classes": classes, "flags": flagn, "total": total, "calls": n, "needs_code": code}, indent=1))
        return 0
    print(f"jquery_classify: {len(rows)} unit(s) of {len(files)} file(s), {n} jQuery call(s), {code} need code")
    print("classes: " + ", ".join(f"{k} {classes[k]}" for k in CLASSES))
    print("| unit | class | " + " | ".join(CATS) + " |")
    print("|---|---|" + "---|" * len(CATS))
    for a, b, c, _f, _d in rows:
        print(f"| {a} | {c} | " + " | ".join(str(b[k]) for k in CATS) + " |")
    print("| TOTAL | | " + " | ".join(str(total[k]) for k in CATS) + " |")
    print("flags: " + ", ".join(f"{k} {flagn[k]}" for k in FLAGS))
    for a, _b, _c, f, d in rows:
        for k in f:
            why = {"bind-once": "Refresh on context change is No: handlers bind once and are lost when the React client redraws",
                   "programmatic-click": "a click made by code: call the button's nanoflow directly (NanoflowCommons Set Storage Item for a hidden store button)",
                   "dead-code": "likely dead, no live call: " + ", ".join(d)}[k]
            print(f"  {k}: {a}: {why}")
    print()
    for k in CATS:
        print(f"{k:10} {total[k]:4}  -> {ROUTE[k]}" + ("  [needs code]" if k in NEEDS_CODE and total[k] else ""))
    print("A jQuery edit of a React-rendered page is undone at the next re-render: a page that still loads is not a page that works.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
