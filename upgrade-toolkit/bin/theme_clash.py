#!/usr/bin/env python3
"""theme_clash.py: does the app's own SCSS still bind to names the NEW Atlas Core defines? (plan item 9b, REVIEW layer)

An upgrade replaces themesource/atlas_core with a newer Atlas. The build can succeed while the app's own styling silently
stops applying: a variable it overrides or reads ($brand-primary), a mixin it @includes, a class it styles (.btn-x), or a
placeholder it @extends, was renamed or removed. This tool lists exactly those names.

  theme_clash.py snap <app-dir> [-o out.json] [--own M,..] [--vendor M,..]
        collect (a) the names Atlas defines and (b) the names the app's own styling uses, as JSON (stdout without -o)
  theme_clash.py diff <old> <new> [--own ..] [--vendor ..] [--client react|dojo]
        <old>/<new> are app dirs or snap JSON files. Judges the NEW app's uses against OLD vs NEW Atlas.

Output: one "CLASH <kind> <name>: used in <file>:<line>, defined in old Atlas <file>:<line>, gone in new Atlas" line per
clash, then "theme clash: N clashes (V variables, M mixins, C classes, X extends); Atlas <old> -> <new>".
A second kind, "dojo-table" (LAY-2, target on the React client; --client dojo switches it off): a Dojo mxui rule that
makes a layout container a CSS table ("display: table", "table-cell", "table-layout" on .mx-scrollcontainer-*,
.mx-templategrid-*, .mx-dataview-*, .mx-listview-*, .mx-tabcontainer-*, .mx-layoutcontainer-*), found in the app's own
styling OR in a vendor module's themesource (core_delta and a company design system carry copies of the old mxui theme).
Harmless on Dojo; on the React client the regions are flex items and a fixed table splits them evenly (LineApp:
the Task List gallery at half the page width, every journey and smoke shot still PASSed). Output line:
"CLASH dojo-table .mx-scrollcontainer-horizontal: display: table; table-layout: fixed in <file>:<line> (vendor module X)".
A third kind, "react-wrapper" (LAY-9): a padding 0 rule scoped under .mx-scrollcontainer-* that targets .mx-layoutgrid*
(React wraps the page in an extra scroll container region, so the rule also zeroes grids that were not nested on Dojo).
The summary line gains ", T dojo-table" / ", W react-wrapper" only when the count is above 0. Atlas modules are not scanned (they are the reference).
Exit 0 no clash, 1 clashes, 3 not compared (a side has no themesource/atlas_core: never "no clash"), 2 usage / bad input.

WHAT IS "ATLAS" (collected from every *.scss under these dirs of the app):
  themesource/atlas_core, themesource/atlas_web_content, themesource/datawidgets*   (the datawidgets theme dir is Atlas's
  widget styling; datagrid, nanoflowcommons, workflowcommons etc. are vendor packages, not Atlas, and are not collected.)
  Defined names: "$x:" variable definitions (incl. !default), "@mixin x", class names in any selector (".x"), and
  placeholders ("%x" in a selector). Atlas version: themesource/atlas_core/.version (first line), else
  atlas_web_content/.version, else package.json "version" of atlas_core, else "unknown".

WHAT IS "THE APP'S OWN STYLING" (collected from every *.scss under):
  theme/web/ (custom-variables, exclusion-variables, main.scss ...) and themesource/<module>/web/ for every module that is
  neither Atlas nor vendor. A module is VENDOR when it has a .version file (a Marketplace package), or is one of the known
  Marketplace names below, or is named by --vendor. --own forces a module to count as own.

WHAT IS USED / DEFINED (per file, after comments and string contents are blanked; #{...} inside a string is kept):
  variables  "$x" occurrences, except a definition ("$x:" at the start of a statement) and mixin/function parameters
             and @each/@for loop variables of the same file (those are local). A name the app defines in its own files is
             never a clash (rule from the plan: the app's own variables are not clashes).
  mixins     "@include x" (and "@include x(...) {"). A mixin the app defines itself is not a clash.
  classes    ".x" in any selector of the app. An app selector that styles an Atlas class that was removed IS the case we
             want (the override is now inert), so app-defined selectors are not excluded for classes.
  extends    "@extend .x" (Atlas class) and "@extend %x" (Atlas placeholder); "!optional" ignored.
SCSS identifiers treat "_" and "-" as the same character, so variables, mixins and placeholders are compared with "_"
read as "-". CSS class names are compared as written.

LIMITS (honest): selectors built by interpolation (".col-#{$i}") and "&-suffix" selectors are not names and are skipped;
namespaced @use (ns.$x) is not parsed (this Atlas uses @import); @function names are not collected; a named argument
written on its own line inside @include is read as a definition. Runtime class names (mx-name-*, widget classes in
markup) are not visible here: a removed Atlas class that only the markup uses is not reported. This is a REVIEW list,
not a verdict on the rendered page.
"""
import argparse
import bisect
import json
import os
import re
import sys

ATLAS_NAMES = ("atlas_core", "atlas_web_content")
KNOWN_VENDOR = {"administration", "appswitchermodule", "feedbackmodule", "communitycommons", "webactions", "deeplink",
                "datagrid", "workflowcommons", "nanoflowcommons", "encryption", "mendixsso", "atlas_ui_resources"}
SCHEMA = 1


def is_atlas_module(name):
    return name in ATLAS_NAMES or name.startswith("datawidgets")


def norm(name):
    """SCSS treats '_' and '-' as the same character in variable, mixin and placeholder names."""
    return name.replace("_", "-")


def _blank(ch):
    return "\n" if ch == "\n" else " "


def scss_code(text):
    """Same-length copy of text with comments and string contents blanked (newlines kept, so offsets and line numbers
    still match the file). Quotes stay. #{...} inside a string is kept (it is code). url(...) contents are blanked."""
    out = []
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        two = text[i:i + 2]
        if two == "/*":
            j = text.find("*/", i + 2)
            j = n if j < 0 else j + 2
            out.append("".join(_blank(ch) for ch in text[i:j]))
            i = j
            continue
        if two == "//":
            j = text.find("\n", i)
            j = n if j < 0 else j
            out.append("".join(_blank(ch) for ch in text[i:j]))
            i = j
            continue
        if c in "\"'":
            out.append(c)
            j = i + 1
            while j < n and text[j] != c and text[j] != "\n":
                if text.startswith("#{", j):
                    k = text.find("}", j)
                    k = n - 1 if k < 0 else k
                    out.append(text[j:k + 1])
                    j = k + 1
                    continue
                if text[j] == "\\" and j + 1 < n:
                    out.append(_blank(text[j]) + _blank(text[j + 1]))
                    j += 2
                    continue
                out.append(_blank(text[j]))
                j += 1
            if j < n and text[j] == c:
                out.append(c)
                j += 1
            i = j
            continue
        if text[i:i + 4].lower() == "url(" and not (i and (text[i - 1].isalnum() or text[i - 1] in "-_")):
            k = i + 4
            while k < n and text[k] in " \t":
                k += 1
            if k < n and text[k] not in "\"'":
                j = text.find(")", k)
                j = n if j < 0 else j
                out.append(text[i:k] + "".join(_blank(ch) for ch in text[k:j]))
                i = j
                continue
        out.append(c)
        i += 1
    code = "".join(out)
    assert len(code) == len(text)
    return code


def statements(code):
    """Split code into (terminator, prelude, offset). Terminator is '{', '}', ';' or 'end'. Braces of #{...} are not
    terminators."""
    start, interp, i, n = 0, 0, 0, len(code)
    while i < n:
        ch = code[i]
        if ch == "{" and i and code[i - 1] == "#":
            interp += 1
        elif ch == "}" and interp:
            interp -= 1
        elif not interp and ch in "{};":
            yield ch, code[start:i], start
            start = i + 1
        i += 1
    yield "end", code[start:], start


PARAM_RE = re.compile(r"[(,]\s*\$([\w-]+)")
DEF_RE = re.compile(r"(?:^|(?<=[;{}]))\s*\$([\w-]+)\s*:", re.M)
VAR_RE = re.compile(r"\$([\w-]+)")
CLASS_RE = re.compile(r"\.(-?[A-Za-z_][\w-]*)(?![\w#{-])")
PH_RE = re.compile(r"%(-?[A-Za-z_][\w-]*)")
EXT_RE = re.compile(r"([.%])(-?[A-Za-z_][\w-]*)")


def analyse(text):
    """Facts of one SCSS file. Every line number is 1-based."""
    code = scss_code(text)
    starts = [0] + [m.end() for m in re.finditer("\n", code)]

    def ln(off):
        return bisect.bisect_right(starts, off)

    f = {"var_defs": [], "var_uses": [], "mixin_defs": [], "mixin_uses": [], "classes": [], "placeholders": [],
         "extends": []}
    defpos = set()
    for m in DEF_RE.finditer(code):
        dollar = m.start(1) - 1
        defpos.add(dollar)
        f["var_defs"].append((norm(m.group(1)), ln(dollar)))
    locals_ = set()
    for term, pre, off in statements(code):
        p = pre.strip()
        if not p:
            continue
        base = off + len(pre) - len(pre.lstrip())
        if term == "{":
            if p.startswith("@mixin"):
                m = re.match(r"@mixin\s+([\w-]+)", p)
                if m:
                    f["mixin_defs"].append((norm(m.group(1)), ln(base)))
                locals_.update(norm(x) for x in PARAM_RE.findall(p))
            elif p.startswith("@function"):
                locals_.update(norm(x) for x in PARAM_RE.findall(p))
            elif p.startswith(("@each", "@for")):
                head = re.split(r"\s(?:in|from)\s", p, maxsplit=1)[0]
                locals_.update(norm(x) for x in VAR_RE.findall(head))
            elif p.startswith("@include"):
                m = re.match(r"@include\s+([\w-]+)", p)
                if m:
                    f["mixin_uses"].append((norm(m.group(1)), ln(base)))
            elif p.startswith("@"):
                pass  # @media, @if, @keyframes, @font-face: no selector of their own
            else:
                for m in CLASS_RE.finditer(p):
                    f["classes"].append(("." + m.group(1), ln(base + m.start())))
                for m in PH_RE.finditer(p):
                    f["placeholders"].append(("%" + norm(m.group(1)), ln(base + m.start())))
        else:
            if p.startswith("@extend"):
                for m in EXT_RE.finditer(p[len("@extend"):]):
                    key = m.group(1) + (m.group(2) if m.group(1) == "." else norm(m.group(2)))
                    f["extends"].append((key, ln(base)))
            elif p.startswith("@include"):
                m = re.match(r"@include\s+([\w-]+)", p)
                if m:
                    f["mixin_uses"].append((norm(m.group(1)), ln(base)))
    for m in VAR_RE.finditer(code):
        off = m.start()
        if off in defpos:
            continue
        name = norm(m.group(1))
        if name in locals_:
            continue
        f["var_uses"].append((name, ln(off)))
    f["locals"] = sorted(locals_)
    return f


DOJO_CLASS_RE = re.compile(r"\.(mx-(?:scrollcontainer|templategrid|dataview|listview|tabcontainer|layoutcontainer)(?:-[\w-]+)?)")
DOJO_DECL_RE = re.compile(r"^\s*(display|table-layout)\s*:\s*([^;!}]+)", re.I)
PAD_DECL_RE = re.compile(r"^\s*(padding(?:-[a-z]+)?)\s*:\s*([^;!}]+)", re.I)
# React wraps the page in an extra scroll container region: a rule scoped under .mx-scrollcontainer-* that zeroes the padding
# of .mx-layoutgrid* also hits grids that were not nested on Dojo (LAY-9)
WRAP_CHAIN_RE = re.compile(r"\.mx-scrollcontainer-[\w-]+[^{}]*\.mx-layoutgrid")
TABLE_DISPLAY = {"table", "table-cell", "table-row", "table-row-group", "table-header-group", "table-footer-group",
                 "table-column", "table-column-group", "table-caption", "inline-table"}


def dojo_table_rules(text):
    """Rules that make a Dojo layout container a CSS table: [(class, selector, 'display: table; ...', line)]. One row per
    rule (its selector line), the offending declarations joined."""
    code = scss_code(text)
    starts = [0] + [m.end() for m in re.finditer("\n", code)]
    ln = lambda off: bisect.bisect_right(starts, off)
    stack, rules, order, flexed = [], {}, [], set()

    def decl(pre):
        if not stack:
            return
        pm = PAD_DECL_RE.match(pre)
        if pm:
            chain = " ".join(x[0] for x in stack if not x[0].startswith("@"))
            if WRAP_CHAIN_RE.search(chain) and re.match(r"^0(px)?(\s+0(px)?)*$", pm.group(2).strip().lower()):
                key = stack[-1][1]
                if key not in rules:
                    rules[key] = [".mx-layoutgrid", re.sub(r"\s+", " ", stack[-1][0]), [], key, "react-wrapper"]
                    order.append(key)
                rules[key][2].append(f"{pm.group(1).lower()}: {pm.group(2).strip().lower()}")
            return
        m = DOJO_DECL_RE.match(pre)
        if not m:
            return
        prop, val = m.group(1).lower(), m.group(2).strip().lower()
        if prop == "display" and val not in TABLE_DISPLAY:   # display: flex / block on the same rule is the fix, not a clash
            flexed.add(stack[-1][1])
            return
        chain = " ".join(x[0] for x in stack if not x[0].startswith("@"))
        cm = DOJO_CLASS_RE.search(chain)
        if not cm:
            return
        key = stack[-1][1]
        if key not in rules:
            rules[key] = [cm.group(1), re.sub(r"\s+", " ", stack[-1][0]), [], key, "dojo-table"]
            order.append(key)
        rules[key][2].append(f"{prop}: {val}")

    for term, pre, off in statements(code):
        p = pre.strip()
        if term == "{":
            base = off + len(pre) - len(pre.lstrip())
            stack.append((p, ln(base)))
        elif term == "}":
            if p:
                decl(pre)
            if stack:
                stack.pop()
        elif p:
            decl(pre)
    return [(rules[k][0] if rules[k][0].startswith(".") else "." + rules[k][0], rules[k][1], "; ".join(rules[k][2]), rules[k][3], rules[k][4])
            for k in order if k not in flexed or rules[k][4] != "dojo-table"]


def read(path):
    with open(path, encoding="utf-8", errors="replace") as fh:
        return fh.read()


def scss_files(root):
    out = []
    for dp, dn, fn in os.walk(root):
        dn.sort()
        for x in sorted(fn):
            if x.endswith(".scss") and not x.startswith("._"):   # ._x.scss: macOS AppleDouble metadata, not SCSS
                out.append(os.path.join(dp, x))
    return out


def atlas_version(app):
    ts = os.path.join(app, "themesource")
    for mod in ("atlas_core", "atlas_web_content"):
        p = os.path.join(ts, mod, ".version")
        if os.path.isfile(p):
            first = read(p).strip().splitlines()
            if first and first[0].strip():
                return first[0].strip()
    pj = os.path.join(ts, "atlas_core", "package.json")
    if os.path.isfile(pj):
        try:
            v = json.loads(read(pj)).get("version")
            if v:
                return str(v)
        except ValueError:
            pass
    return "unknown"


def classify(app, own_force, vendor_force):
    """-> (atlas modules, own modules, vendor modules) found under themesource/ and theme/."""
    ts = os.path.join(app, "themesource")
    atlas, own, vendor = [], [], []
    if os.path.isdir(ts):
        for name in sorted(os.listdir(ts)):
            p = os.path.join(ts, name)
            if not os.path.isdir(p):
                continue
            if is_atlas_module(name):
                atlas.append(name)
            elif name in own_force:
                own.append(name)
            elif name in vendor_force or name.lower() in KNOWN_VENDOR or os.path.exists(os.path.join(p, ".version")):
                vendor.append(name)
            else:
                own.append(name)
    return atlas, own, vendor


def snap_dir(app, own_force=(), vendor_force=()):
    app = os.path.abspath(app)
    if not os.path.isdir(app):
        raise SystemExit(f"theme_clash: not a directory: {app}")
    atlas_mods, own_mods, vendor_mods = classify(app, set(own_force), set(vendor_force))
    rel = lambda p: os.path.relpath(p, app).replace(os.sep, "/")

    A = {"present": "atlas_core" in atlas_mods, "version": atlas_version(app), "modules": atlas_mods, "files": 0,
         "variables": {}, "mixins": {}, "classes": {}, "placeholders": {}}
    for mod in atlas_mods:
        for path in scss_files(os.path.join(app, "themesource", mod)):
            A["files"] += 1
            f = analyse(read(path))
            r = rel(path)
            for name, line in f["var_defs"]:
                A["variables"].setdefault(name, f"{r}:{line}")
            for name, line in f["mixin_defs"]:
                A["mixins"].setdefault(name, f"{r}:{line}")
            for name, line in f["classes"]:
                A["classes"].setdefault(name, f"{r}:{line}")
            for name, line in f["placeholders"]:
                A["placeholders"].setdefault(name, f"{r}:{line}")

    P = {"files": [], "own_modules": own_mods, "vendor_modules": vendor_mods,
         "defined": {"variables": set(), "mixins": set(), "placeholders": set()},
         "uses": {"variables": {}, "mixins": {}, "classes": {}, "extends": {}}}
    own_roots = [os.path.join(app, "theme", "web")] + [os.path.join(app, "themesource", m, "web") for m in own_mods]
    for root in own_roots:
        for path in scss_files(root):
            r = rel(path)
            P["files"].append(r)
            f = analyse(read(path))
            P["defined"]["variables"].update(n for n, _ in f["var_defs"])
            P["defined"]["mixins"].update(n for n, _ in f["mixin_defs"])
            P["defined"]["placeholders"].update(n for n, _ in f["placeholders"])
            for name, line in f["var_uses"]:
                P["uses"]["variables"].setdefault(name, []).append(f"{r}:{line}")
            for name, line in f["mixin_uses"]:
                P["uses"]["mixins"].setdefault(name, []).append(f"{r}:{line}")
            for name, line in f["classes"]:
                P["uses"]["classes"].setdefault(name, []).append(f"{r}:{line}")
            for key, line in f["extends"]:
                P["uses"]["extends"].setdefault(key, []).append(f"{r}:{line}")
    P["defined"] = {k: sorted(v) for k, v in P["defined"].items()}
    V = {"variable": {}, "mixin": {}, "class": {}, "placeholder": {}}
    for mod in vendor_mods:
        for path in scss_files(os.path.join(app, "themesource", mod)):
            r = rel(path)
            f = analyse(read(path))
            for name, line in f["var_defs"]:
                V["variable"].setdefault(name, f"{r}:{line}")
            for name, line in f["mixin_defs"]:
                V["mixin"].setdefault(name, f"{r}:{line}")
            for name, line in f["classes"]:
                V["class"].setdefault(name, f"{r}:{line}")
            for name, line in f["placeholders"]:
                V["placeholder"].setdefault(name, f"{r}:{line}")
    P["vendor_defined"] = V
    T = []   # Dojo table rules in own styling (theme/web, own modules) and in vendor modules; never in Atlas
    for root, label in ([(r, "own") for r in own_roots] + [(os.path.join(app, "themesource", m), "vendor " + m) for m in vendor_mods]):
        for path in scss_files(root):
            for cls, sel, props, line, kind in dojo_table_rules(read(path)):
                T.append({"class": cls, "selector": sel, "props": props, "where": f"{rel(path)}:{line}", "module": label, "kind": kind})
    P["dojo_table"] = T
    return {"schema": SCHEMA, "source": app, "atlas": A, "app": P}


def load_side(arg, own_force, vendor_force):
    if os.path.isfile(arg) and arg.endswith(".json"):
        with open(arg, encoding="utf-8") as fh:
            snap = json.load(fh)
        if snap.get("schema") != SCHEMA:
            raise SystemExit(f"theme_clash: {arg} is not a schema {SCHEMA} snapshot")
        return snap
    return snap_dir(arg, own_force, vendor_force)


def diff(old, new, client="react"):
    """-> (clash rows, not_compared message or None)."""
    if not old["atlas"]["present"] or not new["atlas"]["present"]:
        missing = [s for s, sn in (("old", old), ("new", new)) if not sn["atlas"]["present"]]
        return None, "theme clash: not compared (no themesource/atlas_core in " + " and ".join(
            f"{s} app {old['source'] if s == 'old' else new['source']}" for s in missing) + ")"
    oa, na, app = old["atlas"], new["atlas"], new["app"]
    vend = app.get("vendor_defined", {})
    rows = []
    for name, locs in sorted(app["uses"]["variables"].items(), key=lambda kv: kv[0]):
        if name in oa["variables"] and name not in na["variables"] and name not in app["defined"]["variables"]:
            rows.append(("variable", "$" + name, locs, oa["variables"][name], vend.get("variable", {}).get(name)))
    for name, locs in sorted(app["uses"]["mixins"].items()):
        if name in oa["mixins"] and name not in na["mixins"] and name not in app["defined"]["mixins"]:
            rows.append(("mixin", name, locs, oa["mixins"][name], vend.get("mixin", {}).get(name)))
    for key, locs in sorted(app["uses"]["classes"].items()):
        if key in oa["classes"] and key not in na["classes"]:
            rows.append(("class", key, locs, oa["classes"][key], vend.get("class", {}).get(key)))
    for key, locs in sorted(app["uses"]["extends"].items()):
        table_old = oa["classes"] if key.startswith(".") else oa["placeholders"]
        table_new = na["classes"] if key.startswith(".") else na["placeholders"]
        own = key in app["defined"]["placeholders"]   # app-defined placeholders are the app's own, never a clash
        if key in table_old and key not in table_new and not own:
            hint = vend.get("class" if key.startswith(".") else "placeholder", {}).get(key)
            rows.append(("extend", key, locs, table_old[key], hint))
    if client == "react":
        for t in app.get("dojo_table", []):
            rows.append((t.get("kind", "dojo-table"), t["class"], [t["where"]], t["props"], t["module"]))
    return rows, None


def fmt_clash(kind, name, locs, where, vendor_hint=None):
    if kind == "react-wrapper":
        mod = "own styling" if vendor_hint == "own" else f"{vendor_hint} module"
        return (f"CLASH react-wrapper {name}: {where} in {locs[0]} ({mod}); the React client wraps the page in an extra scroll "
                f"container region, so a rule scoped under .mx-scrollcontainer-* also hits grids that were not nested on Dojo: "
                f"scope it to the nested grid or look at the page")
    if kind == "dojo-table":   # where = the declarations, vendor_hint = "own" or "vendor <module>"
        mod = "own styling" if vendor_hint == "own" else f"{vendor_hint} module"
        return (f"CLASH dojo-table {name}: {where} in {locs[0]} ({mod}); the React client lays this container out with "
                f"flexbox, so a table rule splits or squeezes it: override with display: flex or remove the rule")
    more = f" (+{len(locs) - 1} more uses)" if len(locs) > 1 else ""
    hint = f" (still defined in new vendor module {vendor_hint}: check it does not carry the style)" if vendor_hint else ""
    return f"CLASH {kind} {name}: used in {locs[0]}{more}, defined in old Atlas {where}, gone in new Atlas{hint}"


def cmd_snap(a):
    snap = snap_dir(a.app, a.own, a.vendor)
    text = json.dumps(snap, indent=1, sort_keys=True) + "\n"
    if a.o:
        with open(a.o, "w", encoding="utf-8") as fh:
            fh.write(text)
        print(f"wrote {a.o}")
    else:
        sys.stdout.write(text)
    A, P = snap["atlas"], snap["app"]
    print(f"info: atlas {A['version']} present={A['present']} files={A['files']} variables={len(A['variables'])} "
          f"mixins={len(A['mixins'])} classes={len(A['classes'])} placeholders={len(A['placeholders'])} "
          f"modules={','.join(A['modules']) or '-'}", file=sys.stderr)
    print(f"info: app own styling files={len(P['files'])} modules={','.join(P['own_modules']) or '-'} "
          f"vendor-skipped={','.join(P['vendor_modules']) or '-'} uses: variables={len(P['uses']['variables'])} "
          f"mixins={len(P['uses']['mixins'])} classes={len(P['uses']['classes'])} "
          f"extends={len(P['uses']['extends'])}", file=sys.stderr)
    return 0


def cmd_diff(a):
    old = load_side(a.old, a.own, a.vendor)
    new = load_side(a.new, a.own, a.vendor)
    rows, msg = diff(old, new, a.client)
    if msg:
        print(msg)
        return 3
    for kind, name, locs, where, hint in rows:
        print(fmt_clash(kind, name, locs, where, hint))
    cnt = {k: sum(1 for r in rows if r[0] == k) for k in ("variable", "mixin", "class", "extend", "dojo-table", "react-wrapper")}
    tail = (f", {cnt['dojo-table']} dojo-table" if cnt["dojo-table"] else "") + (f", {cnt['react-wrapper']} react-wrapper" if cnt["react-wrapper"] else "")
    print(f"theme clash: {len(rows)} clashes ({cnt['variable']} variables, {cnt['mixin']} mixins, "
          f"{cnt['class']} classes, {cnt['extend']} extends{tail}); Atlas {old['atlas']['version']} -> "
          f"{new['atlas']['version']}")
    print(f"info: old Atlas {len(old['atlas']['variables'])} variables, {len(old['atlas']['mixins'])} mixins, "
          f"{len(old['atlas']['classes'])} classes, {len(old['atlas']['placeholders'])} placeholders; new Atlas "
          f"{len(new['atlas']['variables'])} variables, {len(new['atlas']['mixins'])} mixins, "
          f"{len(new['atlas']['classes'])} classes, {len(new['atlas']['placeholders'])} placeholders; new app uses "
          f"{len(new['app']['uses']['variables'])} variables, {len(new['app']['uses']['mixins'])} mixins, "
          f"{len(new['app']['uses']['classes'])} classes, {len(new['app']['uses']['extends'])} extend targets "
          f"in {len(new['app']['files'])} own files")
    return 1 if rows else 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("snap")
    s.add_argument("app")
    s.add_argument("-o", metavar="OUT.json")
    d = sub.add_parser("diff")
    d.add_argument("old", help="old app dir or snap json")
    d.add_argument("new", help="new app dir or snap json")
    d.add_argument("--client", choices=("react", "dojo"), default="react",
                   help="client the NEW app runs on (default react: the Dojo table rules are then reported)")
    for p in (s, d):
        p.add_argument("--own", type=lambda x: set(filter(None, x.split(","))), default=set(),
                       help="modules to treat as the app's own styling even if vendor-looking")
        p.add_argument("--vendor", type=lambda x: set(filter(None, x.split(","))), default=set(),
                       help="modules to treat as vendor (never judged)")
    a = ap.parse_args(argv)
    try:
        return cmd_snap(a) if a.cmd == "snap" else cmd_diff(a)
    except SystemExit as e:
        if isinstance(e.code, str):
            print(e.code, file=sys.stderr)
            return 2
        raise


if __name__ == "__main__":
    sys.exit(main())
