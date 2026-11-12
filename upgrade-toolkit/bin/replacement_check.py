#!/usr/bin/env python3
"""replacement_check.py: deprecated modules and patterns the app still holds, which a platform feature or another
module replaces (B6). Checked against playbooks/replacements.tsv.

Why: release_impact.py keys on version WINDOWS (rows between the installed and the target version of each module) and
closes every row of a kept module. A deprecated module that stays at the same version (DeepLink 10.0.10 has no
deprecation row in its own notes, MendixSSO, the Email Module with Templates) or a deprecated platform feature in use
(Document Templates, legacy scheduled events, mx.logger in a JavaScript action) gives no open row at all. This keys on
PRESENCE: what the app holds, from the model and the files next to it.

Run by: steps/triage.md step 10 (Release impact, required), after release_impact.py; output $W/replacements.md.
Reads: the .mpr (bin/mprmodel.py Model.load, MPR v1 and v2), javasource/ (proxies excluded, read with release_impact's
JavaIndex), userlib/*.jar names, javascriptsource/, theme/ and themesource/, widgets/*.mpk, and the navigation profiles
(release_impact.native_profile). Nothing is written to the app.

  replacement_check.py <app dir | app.mpr> --to <ver> [--from <ver>] [--table playbooks/replacements.tsv]
                       [--out replacements.md] [--json out.json] [--no-newer A,B] [--accept FILE]

  --from defaults to the version the .mpr holds (mxversion.py). Versions are full or short (11.12, 11.12.5).
  --accept FILE   one line per accepted package, `<sha256 of the .mpk> <reason>`: an mpkjs hit on exactly that file is not
                  reported (the row says "accepted by checksum"). For a package a person patched (V3D-2: 3D Viewer 4.0.0
                  with the react-loading spinner replaced keeps the dead React 16 copy, so R36 still matches the file).
  --no-newer A,B  widgets or modules with no newer version for the target (stranded, private owner): an mpkjs hit on one
                  of them says BLOCKER in its evidence and the run prints a `blockers:` line (NR2-24). Still exit 1.

Every row of the table is reported, never dropped, with one status:
  HIT             open: the app holds the pattern; the evidence names the module, document, file or widget
  UNKNOWN         open: a detector could not decide (no javasource folder, a module version that is no version
                  number such as Opcenter EF's '2be20', a navigation profile of unknown kind)
  clear           the jump binds the row and no detector fired (the reason names what was looked for)
  NOT APPLICABLE  the jump does not reach the row (the reason names the jump and the row's applies_on_jump)
Each row also prints its "unchecked" column: the part of the pattern no detector here can see (database rows, a
forked native template, string concatenation behaviour). Those need a human or a journey; they never make a HIT.
Exit 0 = no open row (no HIT, no UNKNOWN), 1 = open rows, 2 = the app or the table could not be read.

applies_on_jump (comma list, any one applies):
  any       every jump
  ->X       the target is at or above X (the deprecation binds at the target, whatever the source: 11.0 -> 11.12 still
            holds a MendixSSO deprecated in 2026)
  A->B      the jump crosses B (from < B <= to): a behaviour change that happens once (9->10 scheduled events). A
            documents the source line only.
detect: OR of ANDs, written "c1 && c2 || c3"; a clause is [!]kind[@own]:arg. "@own" limits a model or file clause to
the app's own (non-Marketplace) modules. Three-valued: a clause that cannot be decided is unknown; an OR with a true
clause is true, an AND with a false clause is false, else unknown stays unknown.
  module:Name                 the module is installed
  modver:Name:<4.0.0,>=3.0    the module is installed and its Marketplace version is in the range (no version or a
                              non-numeric one: unknown)
  widget:REGEX                a pluggable widget id (full match) on a page, snippet or layout (building blocks and page
                              templates are not used pages: skipped)
  type:REGEX                  a model element $Type (search), on any document but building blocks and page templates
  expr:REGEX                  a string value (expression, XPath, template argument) in a microflow, nanoflow or rule
                              (search); the evidence names the document, the element $Type and the text. A hit only
                              LOCATES: whether the order or the context matters (read before a commit) is the row's
                              unchecked column, for a human or a journey
  prop:Type.Key=VALUE         a document of that $Type whose Key is VALUE ("null": absent or empty)
  ref:Module.Name[@Module2]   a document outside Module (or inside Module2) references the qualified name
  setting:Type.Key=VALUE      a project setting: the project settings or project security unit, or a part of it with that
                              $Type (Settings$ModelSettings, Settings$CertificateSettings), whose Key is VALUE (case is
                              ignored: False = false); "null" = absent or empty. A key the model does not have (an older
                              Studio Pro) is unknown, not false (NS-9)
  startup:REGEX               the After startup microflow
  java:REGEX                  javasource/**/*.java, proxies excluded (java@own: own modules' folders only)
  jar:REGEX                   userlib/*.jar file names
  js:REGEX                    javascriptsource/**/*.{js,jsx,mjs,ts,tsx}, node_modules excluded
  theme:REGEX                 theme/** and themesource/** .scss/.css files (theme@own: theme/ and own modules only)
  mpk:REGEX                   widgets/*.mpk file names
  mpkjs:REGEX                 widgets/*.mpk whose JavaScript (not *.editorPreview.js / *.editorConfig.js, which run in Studio Pro) matches REGEX AND whose widget id is used on a page, snippet or
                              layout (NR2-24: the JAVASCRIPT is read, not the package name, and a mention is not a call: an import binding and
                              react-onclickoutside's guarded fallback do not count; a package that matches but
                              no page uses is not a hit, it is a package to delete). The evidence names the package, its
                              widget ids and the instance count. With --no-newer NAME (comma list: a package file name, a
                              widget id or an owning module, matched case-insensitively as a substring; typically the
                              stranded.md modules and the widgets triage found no newer version of) a hit is a BLOCKER:
                              no update can fix it (NR2-24)
  profile:native              a native navigation profile (release_impact.native_profile)
  rows:R4,R6                  any of those rows' detectors fires (whatever their own applies_on_jump)
"""
import argparse, json, os, re, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

HERE = Path(__file__).resolve().parent
DEFAULT_TABLE = HERE.parent / "playbooks" / "replacements.tsv"
COLS = ["id", "pattern", "deprecated_in", "removed_in", "replacement", "detect", "applies_on_jump", "effort", "risk",
        "unchecked", "source", "verified"]
NOT_USED_HOSTS = ("Forms$BuildingBlock", "Forms$PageTemplate")
WIDGET_HOSTS = ("Forms$Page", "Forms$Snippet", "Forms$Layout")
EXPR_HOSTS = ("Microflows$Microflow", "Microflows$Nanoflow", "Microflows$Rule")
JS_EXT = {".js", ".jsx", ".mjs", ".ts", ".tsx"}
THEME_EXT = {".scss", ".css"}
KINDS = {"module", "modver", "widget", "type", "expr", "prop", "setting", "ref", "startup", "java", "jar", "js", "theme", "mpk", "mpkjs", "profile",
         "rows"}
NO_NEWER = []  # --no-newer names, lower case (read by the mpkjs clause)
ACCEPT = {}    # --accept: sha256 of a widgets/*.mpk -> reason (a patched package the mpkjs clause no longer reports, V3D-2)
# Libraries that ship their own React copy inside a widget bundle, found by a marker in the bundle (V3D-1: 3D Viewer 3.x to 5.x
# carries react-loading 2.x, a UMD file with React 16.3.2, which renders its own elements; the fix is as big as that library).
BUNDLE_MARKERS = [("react-loading 2.x (spinner, UMD with its own React 16)", r"spinningBubbles|\breact-loading\b|ReactLoading")]
SHOW = 4  # evidence items printed per clause


class TableError(Exception):
    pass


def strict_v(s):
    """Version tuple only for a real version number: '2be20' (an Opcenter EF module's version) is no version."""
    s = str(s or "").strip()
    return tuple(int(x) for x in s.split(".")) if re.fullmatch(r"\d+(\.\d+)*", s) else None


def read_table(path):
    rows = []
    with open(path, encoding="utf-8") as f:
        header = None
        for n, line in enumerate(f, 1):
            line = line.rstrip("\n")
            if not line.strip() or line.startswith("#"):
                continue
            cells = line.split("\t")
            if header is None:
                if cells != COLS:
                    raise TableError(f"{path}:{n}: header is not {' '.join(COLS)}")
                header = cells
                continue
            if len(cells) != len(COLS):
                raise TableError(f"{path}:{n}: {len(cells)} fields, want {len(COLS)}")
            r = dict(zip(COLS, cells))
            r["ast"] = parse_detect(r["detect"], f"{path}:{n} {r['id']}")
            jumps(r["applies_on_jump"], f"{path}:{n} {r['id']}")
            rows.append(r)
    ids = [r["id"] for r in rows]
    if len(set(ids)) != len(ids):
        raise TableError(f"{path}: duplicate ids")
    return rows


def parse_detect(s, where):
    ors = []
    for alt in s.split(" || "):
        ands = []
        for c in alt.split(" && "):
            c = c.strip()
            neg = c.startswith("!")
            c = c[1:] if neg else c
            m = re.match(r"^([a-z]+)(@own)?:(.+)$", c)
            if not m or m.group(1) not in KINDS:
                raise TableError(f"{where}: bad detect clause '{c}' (kinds: {', '.join(sorted(KINDS))})")
            kind, own, arg = m.group(1), bool(m.group(2)), m.group(3)
            if kind in ("widget", "type", "expr", "startup", "java", "jar", "js", "theme", "mpk", "mpkjs"):
                try:
                    re.compile(arg)
                except re.error as e:
                    raise TableError(f"{where}: bad regex in '{c}': {e}")
            ands.append((neg, kind, own, arg))
        ors.append(ands)
    return ors


def jumps(s, where):
    out = []
    for part in [p.strip() for p in s.split(",") if p.strip()]:
        if part == "any":
            out.append(("any", None))
            continue
        m = re.fullmatch(r"([0-9.]*)->([0-9.]+)", part)
        if not m or strict_v(m.group(2)) is None:
            raise TableError(f"{where}: bad applies_on_jump '{part}' (any, ->X or A->B)")
        out.append(("cross" if m.group(1) else "target", strict_v(m.group(2))))
    if not out:
        raise TableError(f"{where}: empty applies_on_jump")
    return out


def applies(r, fv, tv):
    """(bool, reason)."""
    from release_impact import cmpv
    for kind, x in jumps(r["applies_on_jump"], r["id"]):
        if kind == "any":
            return True, "any jump"
        if kind == "target" and cmpv(tv, x) >= 0:
            return True, f"target at or above {'.'.join(map(str, x))}"
        if kind == "cross" and cmpv(fv, x) < 0 <= cmpv(tv, x):
            return True, f"jump crosses {'.'.join(map(str, x))}"
    return False, f"applies_on_jump {r['applies_on_jump']}: not reached"


class App:
    """The app folder: the model (mprmodel) and the files next to it, each read once on first use."""

    def __init__(self, path):
        import mprmodel
        p = Path(path)
        self.m = mprmodel.Model.load(str(p))
        self.root = Path(self.m.path).resolve().parent
        self.own = {n.lower() for n, i in self.m.modules.items() if n and not i.get("from_appstore")}
        self.mp = {n.lower() for n, i in self.m.modules.items() if n and i.get("from_appstore")}
        self._cache = {}

    def once(self, key, fn):
        if key not in self._cache:
            self._cache[key] = fn()
        return self._cache[key]

    def tag(self, module):
        return "Marketplace" if (module or "").lower() in self.mp else "own" if (module or "").lower() in self.own else "?"

    def docs(self):
        return [d for d in self.m.all_docs if d.type not in NOT_USED_HOSTS] + \
            [d for q, d in self.m.docs.items() if q.endswith(".$DomainModel") or q.endswith(".$ModuleSecurity")]

    def types(self):
        """$Type -> {doc qn: count}, per used document."""
        def build():
            idx = {}

            def walk(x, qn):
                if isinstance(x, dict):
                    t = x.get("$Type")
                    if isinstance(t, str):
                        idx.setdefault(t, {})
                        idx[t][qn] = idx[t].get(qn, 0) + 1
                    for v in x.values():
                        walk(v, qn)
                elif isinstance(x, list):
                    for v in x:
                        walk(v, qn)
            for d in self.docs():
                walk(d.data, d.qn)
            return idx
        return self.once("types", build)

    def widgets(self):
        """widget id -> {host qn: count}, pages, snippets and layouts only."""
        def build():
            idx = {}

            def walk(x, qn):
                if isinstance(x, dict):
                    if x.get("$Type") == "CustomWidgets$CustomWidgetType" and isinstance(x.get("WidgetId"), str):
                        w = idx.setdefault(x["WidgetId"], {})
                        w[qn] = w.get(qn, 0) + 1
                    for v in x.values():
                        walk(v, qn)
                elif isinstance(x, list):
                    for v in x:
                        walk(v, qn)
            for d in self.m.all_docs:
                if d.type in WIDGET_HOSTS:
                    walk(d.data, d.qn)
            return idx
        return self.once("widgets", build)

    def exprs(self):
        """[(doc qn, element $Type, text)]: every non-empty string value in microflows, nanoflows and rules, minus the
        $-keys (ids, types) and names, so an attribute in an expression or an XPath constraint is found."""
        def build():
            out = []

            def walk(x, qn, t):
                if isinstance(x, dict):
                    t = x.get("$Type") if isinstance(x.get("$Type"), str) else t
                    for k, v in x.items():
                        if isinstance(v, str):
                            if v.strip() and not k.startswith("$") and k not in ("Name", "Documentation"):
                                out.append((qn, t, v))
                        else:
                            walk(v, qn, t)
                elif isinstance(x, list):
                    for v in x:
                        walk(v, qn, t)
            for d in self.m.all_docs:
                if d.type in EXPR_HOSTS:
                    walk(d.data, d.qn, d.type)
            return out
        return self.once("exprs", build)

    def files(self, folder, exts, skip_dirs=()):
        """{relative posix path: text} under root/folder, or None when the folder is absent."""
        def build():
            base = self.root / folder
            if not base.is_dir():
                return None
            out = {}
            for f in base.rglob("*"):
                rel = f.relative_to(base)
                if f.is_file() and f.suffix.lower() in exts and not any(p in skip_dirs for p in rel.parts):
                    out[f"{folder}/{rel.as_posix()}"] = f.read_text(errors="replace")
            return out
        return self.once(("files", folder), build)

    def java(self):
        from release_impact import JavaIndex
        ix = JavaIndex.of(self.root)
        if not (self.root / "javasource").is_dir():
            return None
        return {f"javasource/{p}": t for p, t in ix.java.items()}


def module_of_path(rel):
    parts = rel.split("/")
    return parts[1].lower() if len(parts) > 2 and parts[0] in ("javasource", "javascriptsource", "themesource") else None


def fmt_hosts(app, hosts):
    items = sorted(hosts.items())
    s = ", ".join(f"{q} ({app.tag(q.split('.')[0])}){' x' + str(n) if n > 1 else ''}" for q, n in items[:SHOW])
    return s + (f" ... ({len(items)} documents)" if len(items) > SHOW else "")


def grep(app, files, rx, own, label):
    """files: {rel: text} or None. (value, evidence)."""
    if files is None:
        return None, f"{label}: folder not found next to the .mpr"
    hits = {}
    for rel, text in files.items():
        if own:
            mod = module_of_path(rel)
            if mod is not None and mod not in app.own:
                continue
        n = len(re.findall(rx, text))
        if n:
            hits[rel] = n
    if not hits:
        return False, f"no match of /{rx}/ in {label} ({len(files)} files{', own modules only' if own else ''})"
    items = sorted(hits.items())
    s = ", ".join(f"{p} ({n})" for p, n in items[:SHOW]) + (f" ... ({len(items)} files)" if len(items) > SHOW else "")
    return True, f"/{rx}/ in {s}"


def mpk_widgets(z):
    """Widget ids a package declares: <widget id="..."> in its XML files, plus the clientModule version."""
    ids, ver = [], ""
    for n in z.namelist():
        if n.lower().endswith(".xml") and not n.startswith("__MACOSX"):
            txt = z.read(n).decode("utf-8", "replace")
            ids += re.findall(r"<widget\s[^>]*?\bid\s*=\s*\"([^\"]+)\"", txt)
            m = re.search(r"<clientModule\s[^>]*?\bversion\s*=\s*\"([^\"]+)\"", txt)
            ver = ver or (m.group(1) if m else "")
    return list(dict.fromkeys(ids)), ver


def real_hit(rx, text):
    """A match that is a CALL, not a mention. Two shapes of mention are skipped: an import binding (`findDOMNode as M` in an
    ES bundle) and react-onclickoutside's guarded fallback (`typeof e.setClickOutsideRef == "function" ? ... : findDOMNode(e)`),
    which ships inside the current Data Widgets 3.x filters that run on React 19 (customer DatagridDateFilter 3.11.2: a plain
    grep flagged 29 packages of which 2 really called it, NR2-24)."""
    for m in re.finditer(rx, text):
        if text[m.end():m.end() + 4] == " as ":
            continue
        if "setClickOutsideRef" in text[max(0, m.start() - 160):m.start()]:
            continue
        return True
    return False


def mpkjs(app, rx):
    """widgets/*.mpk with JavaScript matching rx and a widget id that a page, snippet or layout uses (NR2-24)."""
    import zipfile
    d = app.root / "widgets"
    files = sorted(d.glob("*.mpk")) if d.is_dir() else None
    if files is None:
        if not ((app.root / "javasource").is_dir() or (app.root / "theme").is_dir()):
            return None, "widgets: folder not found next to the .mpr (nor javasource/ or theme/)"
        return False, "no widgets/ folder next to the .mpr (0 files)"
    import hashlib
    used, unused, unreadable, accepted = [], [], [], []
    for f in files:
        try:
            with zipfile.ZipFile(f) as z:
                texts = [z.read(n).decode("utf-8", "replace")
                         for n in z.namelist() if n.lower().endswith((".js", ".mjs"))
                         and not n.lower().endswith((".editorpreview.js", ".editorconfig.js"))]   # Studio Pro design mode, not the runtime (MC-19)
                if not any(real_hit(rx, t) for t in texts):
                    continue
                ids, ver = mpk_widgets(z)
                libs = [name for name, mrx in BUNDLE_MARKERS if any(re.search(mrx, t) for t in texts)]
        except (zipfile.BadZipFile, OSError, KeyError, NotImplementedError, RuntimeError):
            unreadable.append(f.name)
            continue
        sha = hashlib.sha256(f.read_bytes()).hexdigest()
        if sha in ACCEPT:   # V3D-2: a patched package keeps the dead pattern in its file; a person accepted this exact file
            accepted.append(f"widgets/{f.name}{' ' + ver if ver else ''} (sha256 {sha[:12]}: {ACCEPT[sha]})")
            continue
        hosts = {}
        for wid in ids:
            for q, n in app.widgets().get(wid, {}).items():
                hosts[q] = hosts.get(q, 0) + n
        (used if hosts else unused).append((f.name, ver, ids, hosts, libs))
    if used:
        out = []
        for name, ver, ids, hosts, libs in used:
            n = sum(hosts.values())
            blocked = [x for x in NO_NEWER if x and (x in name.lower() or any(x in i.lower() for i in ids))]
            out.append(("BLOCKER (no newer version: " + ", ".join(blocked) + "): " if blocked else "") +
                       f"widgets/{name}{' ' + ver if ver else ''} runs /{rx}/ in its JavaScript and widget "
                       f"{', '.join(ids[:SHOW])} is used {n} time(s) on {fmt_hosts(app, hosts)}"
                       + (f"; the bundled copy belongs to {', '.join(libs)}" if libs else ""))
        return True, "; ".join(out)
    if accepted:
        return False, "accepted by checksum, not reported: " + "; ".join(accepted)
    if unreadable:
        return None, f"widgets/ {', '.join(unreadable[:SHOW])} cannot be read as a zip: check the JavaScript for /{rx}/ by hand"
    if unused:
        return False, ("package(s) with /" + rx + "/ in their JavaScript, but no page uses them: "
                       + ", ".join(f"widgets/{u[0]}" for u in unused[:SHOW]) + " (delete the .mpk after a check of building blocks)")
    return False, f"no widgets/*.mpk JavaScript matches /{rx}/ ({len(files)} packages)"


def clause(app, kind, own, arg, rows, stack):
    m = app.m
    if kind == "module":
        if arg in m.modules:
            i = m.modules[arg]
            return True, f"module {arg} {i.get('version') or '(no version)'} ({app.tag(arg)})"
        return False, f"no module {arg}"
    if kind == "modver":
        name, _, spec = arg.partition(":")
        if name not in m.modules:
            return False, f"no module {name}"
        raw = m.modules[name].get("version") or ""
        v = strict_v(raw) if "." in raw else None  # Opcenter EF 6.0.0: '2be20', '73355' (a hash, also all digits)
        if v is None:
            return None, f"module {name} version '{raw}' is no version number: compare by hand against {spec}"
        from release_impact import cmpv
        ok = True
        for c in spec.split(","):
            mm = re.fullmatch(r"\s*(<=|>=|<|>|==)\s*([0-9.]+)\s*", c)
            if not mm:
                raise TableError(f"bad modver range '{spec}'")
            r = cmpv(v, strict_v(mm.group(2)))
            ok = ok and {"<": r < 0, "<=": r <= 0, ">": r > 0, ">=": r >= 0, "==": r == 0}[mm.group(1)]
        return (True, f"module {name} {raw} ({app.tag(name)}) is {spec}") if ok else \
            (False, f"module {name} {raw} is not {spec}")
    if kind == "widget":
        hosts = {}
        for wid, hs in app.widgets().items():
            if re.fullmatch(arg, wid):
                for q, n in hs.items():
                    if not own or q.split(".")[0].lower() in app.own:
                        hosts[f"{q}"] = hosts.get(q, 0) + n
        if hosts:
            return True, f"widget /{arg}/ on {fmt_hosts(app, hosts)}"
        return False, f"no widget /{arg}/ on a page, snippet or layout{' of an own module' if own else ''}"
    if kind == "type":
        from release_impact import ALWAYS_PRESENT_TYPES
        hosts, names = {}, set()
        for t, hs in app.types().items():
            if t in ALWAYS_PRESENT_TYPES or not re.search(arg, t):
                continue
            for q, n in hs.items():
                if not own or q.split(".")[0].lower() in app.own:
                    hosts[q] = hosts.get(q, 0) + n
                    names.add(t)
        if hosts:
            return True, f"{', '.join(sorted(names))}: {sum(hosts.values())} in {fmt_hosts(app, hosts)}"
        return False, f"no model element /{arg}/{' in an own module' if own else ''}"
    if kind == "expr":
        hosts, texts = {}, []
        for q, t, v in app.exprs():
            if not re.search(arg, v) or (own and q.split(".")[0].lower() not in app.own):
                continue
            hosts[q] = hosts.get(q, 0) + 1
            if len(texts) < SHOW:
                texts.append(f"{q} {t}: '{v if len(v) <= 120 else v[:117] + '...'}'")
        if hosts:
            return True, f"/{arg}/ in {fmt_hosts(app, hosts)}: " + "; ".join(texts)
        return False, f"no microflow, nanoflow or rule text matches /{arg}/{' in an own module' if own else ''}"
    if kind == "prop":
        lhs, _, want = arg.partition("=")
        typ, _, key = lhs.rpartition(".")
        hosts = {}
        for d in m.of_type(typ):
            if own and d.module.lower() not in app.own:
                continue
            val = d.data.get(key)
            if (want == "null" and val in (None, "", [])) or (want != "null" and str(val) == want):
                hosts[d.qn] = 1
        if hosts:
            return True, f"{typ} with {key}={want}: {fmt_hosts(app, hosts)}"
        return False, f"no {typ} with {key}={want} ({len(m.of_type(typ))} of that type)"
    if kind == "setting":
        lhs, _, want = arg.partition("=")
        typ, _, key = lhs.rpartition(".")
        found = []

        def walk(x):
            if isinstance(x, dict):
                if x.get("$Type") == typ:
                    found.append(x)
                for v in x.values():
                    walk(v)
            elif isinstance(x, list):
                for v in x:
                    walk(v)
        for d in m.singletons.values():
            walk(d)
        if not found:
            return None, f"no {typ} in the project settings or security (cannot read the setting {key})"
        vals = [x.get(key) for x in found]
        if want == "null":
            hit = any(v in (None, "", []) for v in vals)
        elif all(key not in x for x in found):
            return None, f"{typ} has no {key} (an older Studio Pro): check it in Studio Pro after the convert"
        else:
            hit = any(str(v).lower() == want.lower() for v in vals)
        shown = ", ".join(sorted({"absent (its default applies)" if v is None else str(v) for v in vals}))
        return hit, f"setting {typ}.{key} is {shown}" + ("" if hit else f" (not {want})")
    if kind == "ref":
        qn, _, inside = arg.partition("@")
        mod = qn.split(".")[0]
        hosts = {}
        for q in m.docs:
            src = q.split(".")[0]
            if (inside and src != inside) or (not inside and src == mod):
                continue
            if own and src.lower() not in app.own:
                continue
            if qn in m.refs(q):
                hosts[q] = 1
        if hosts:
            return True, f"{qn} referenced by {fmt_hosts(app, hosts)}"
        return False, f"no document {'in ' + inside if inside else 'outside ' + mod} references {qn}"
    if kind == "startup":
        mf = app.m.after_startup().get("AfterStartupMicroflow") or ""
        if re.search(arg, mf):
            return True, f"After startup microflow {mf}"
        return False, f"After startup microflow '{mf}' does not match /{arg}/"
    if kind == "java":
        return grep(app, app.java(), arg, own, "javasource (proxies excluded)")
    if kind == "js":
        return grep(app, app.files("javascriptsource", JS_EXT, ("node_modules",)), arg, own,
                    "javascriptsource (node_modules excluded)")
    if kind == "theme":
        t, s = app.files("theme", THEME_EXT), app.files("themesource", THEME_EXT)
        if t is None and s is None:
            return None, "theme: no theme/ or themesource/ folder next to the .mpr"
        return grep(app, {**(t or {}), **(s or {})}, arg, own, "theme/ and themesource/")
    if kind in ("jar", "mpk"):
        folder, pat = ("userlib", "*.jar") if kind == "jar" else ("widgets", "*.mpk")
        d = app.root / folder
        names = sorted(p.name for p in d.glob(pat)) if d.is_dir() else None
        if names is None:
            # git keeps no empty folder: in an app folder with javasource or theme, no userlib/widgets means none
            # (customer golden: no userlib). Without either, this is no app folder: unknown.
            if not ((app.root / "javasource").is_dir() or (app.root / "theme").is_dir()):
                return None, f"{folder}: folder not found next to the .mpr (nor javasource/ or theme/)"
            return False, f"no {folder}/ folder next to the .mpr (0 files)"
        hit = [n for n in names if re.search(arg, n)]
        if hit:
            return True, f"{folder}/: {', '.join(hit[:SHOW])}{f' ... ({len(hit)} files)' if len(hit) > SHOW else ''}"
        return False, f"no {folder}/ file matches /{arg}/ ({len(names)} files)"
    if kind == "mpkjs":
        return mpkjs(app, arg)
    if kind == "profile":
        from release_impact import native_profile
        facts, notes = {}, []
        native_profile(m, facts, notes)
        if "native_profile" not in facts:
            return None, "; ".join(notes) or "native profile: unknown"
        return (True, "a native navigation profile") if facts["native_profile"] else \
            (False, "no native navigation profile (every profile is a browser profile)")
    if kind == "rows":
        hit, unk, why = [], [], []
        for rid in [x.strip() for x in arg.split(",")]:
            if rid not in rows:
                raise TableError(f"rows: unknown row {rid}")
            if rid in stack:
                raise TableError(f"rows: cycle through {rid}")
            v, ev = evaluate(app, rows[rid]["ast"], rows, stack | {rid})
            (hit if v else unk if v is None else why).append(rid)
        if hit:
            return True, f"rows {', '.join(hit)} fire"
        if unk:
            return None, f"rows {', '.join(unk)} unknown"
        return False, f"rows {', '.join(why)} do not fire"
    raise TableError(f"unknown kind {kind}")


def evaluate(app, ast, rows, stack=frozenset()):
    """(True|False|None, evidence lines): OR of ANDs, three-valued."""
    alts = []
    for ands in ast:
        vals, evs = [], []
        for neg, kind, own, arg in ands:
            v, ev = clause(app, kind, own, arg, rows, stack)
            if neg and v is not None:
                v, ev = (not v), (f"not ({ev})")
            vals.append(v)
            evs.append(ev)
        if any(v is False for v in vals):
            val = False
            evs = [e for v, e in zip(vals, evs) if v is False]
        elif all(v is True for v in vals):
            val = True
        else:
            val = None
            evs = [e for v, e in zip(vals, evs) if v is None]
        alts.append((val, evs))
    pick = True if any(v is True for v, _ in alts) else None if any(v is None for v, _ in alts) else False
    return pick, list(dict.fromkeys(e for v, es in alts if v is pick for e in es))


def esc(s):
    return str(s).replace("|", "\\|").replace("\n", " ")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("app", help="app folder (holding exactly one .mpr) or the .mpr")
    ap.add_argument("--to", required=True, help="target Studio Pro version")
    ap.add_argument("--from", dest="frm", help="source version (default: the .mpr's)")
    ap.add_argument("--table", default=str(DEFAULT_TABLE))
    ap.add_argument("--out", help="markdown report (one row per table row, a handled column for the open ones)")
    ap.add_argument("--json", help="JSON report")
    ap.add_argument("--accept", help="file: one line per accepted widget package, `<sha256 of the .mpk> <reason>` ('#' lines skipped); "
                    "an mpkjs hit on exactly that file is not reported (a package patched by a person, V3D-2)")
    ap.add_argument("--no-newer", default="", help="comma list: widgets or modules with no newer version (BLOCKER on a React 19 hit)")
    a = ap.parse_args()
    NO_NEWER[:] = [x.strip().lower() for x in a.no_newer.split(",") if x.strip()]
    if a.accept:
        try:
            for n, ln in enumerate(Path(a.accept).read_text().splitlines(), 1):
                ln = ln.strip()
                if not ln or ln.startswith("#"):
                    continue
                sha, _, why = ln.partition(" ")
                if not re.fullmatch(r"[0-9a-fA-F]{64}", sha) or not why.strip():
                    print(f"replacement_check: {a.accept}:{n}: want '<sha256 of the .mpk> <reason>'")
                    return 2
                ACCEPT[sha.lower()] = why.strip()
        except OSError as e:
            print(f"replacement_check: cannot read --accept: {e}")
            return 2
    try:
        rows = read_table(a.table)
    except (OSError, TableError) as e:
        print(f"replacement_check: cannot read the table: {e}")
        return 2
    try:
        app = App(a.app)
    except SystemExit as e:  # mprmodel exits with a message on a folder without exactly one .mpr, or without bson
        print(f"replacement_check: cannot read the app {a.app}: {e.code}")
        return 2
    except Exception as e:  # sqlite: no Unit table, not a database, ...
        print(f"replacement_check: cannot read the app {a.app}: {type(e).__name__}: {e}")
        return 2
    frm = a.frm
    if not frm:
        from mxversion import version
        frm = version(app.m.path)
    fv, tv = strict_v(str(frm).split("-")[0]), strict_v(a.to)
    if fv is None or tv is None:
        print(f"replacement_check: --from {frm!r} / --to {a.to!r}: not a version (give both, e.g. --from 10.24.16 --to 11.12.5)")
        return 2
    byid = {r["id"]: r for r in rows}
    results = []
    try:
        for r in rows:
            ok, why = applies(r, fv, tv)
            if not ok:
                results.append({"id": r["id"], "status": "NOT APPLICABLE", "evidence": [f"jump {frm} -> {a.to}: {why}"]})
                continue
            v, ev = evaluate(app, r["ast"], byid)
            results.append({"id": r["id"], "status": {True: "HIT", None: "UNKNOWN", False: "clear"}[v], "evidence": ev})
    except TableError as e:
        print(f"replacement_check: table: {e}")
        return 2
    count = {s: sum(1 for x in results if x["status"] == s) for s in ("HIT", "UNKNOWN", "clear", "NOT APPLICABLE")}
    print(f"replacement_check: {app.m.path} ({frm} -> {a.to}), {len(rows)} rows: {count['HIT']} HIT (open), "
          f"{count['UNKNOWN']} UNKNOWN (open), {count['clear']} clear, {count['NOT APPLICABLE']} NOT APPLICABLE")
    for x in results:
        r = byid[x["id"]]
        x.update({k: r[k] for k in COLS if k != "id"})
        print(f"{x['status']:<14} {r['id']:<4} {r['pattern']} -> {r['replacement']} [effort {r['effort']}]")
        for e in x["evidence"]:
            print(f"    {'evidence' if x['status'] == 'HIT' else 'why'}: {e}")
        if x["status"] in ("HIT", "UNKNOWN", "clear") and r["unchecked"] not in ("", "-"):
            print(f"    unchecked: {r['unchecked']}")
        if x["status"] in ("HIT", "UNKNOWN") and r["verified"] != "yes":
            print(f"    verified: {r['verified']}")
    blockers = [x["id"] for x in results if x["status"] == "HIT" and any("BLOCKER" in e for e in x["evidence"])]
    if blockers:
        print(f"blockers: {', '.join(blockers)}: no update can fix these, plan the replacement before the upgrade (steps/triage.md step 10)")
    if a.out:
        lines = [f"# Replacement check: {app.m.path} ({frm} -> {a.to})", "",
                 f"Table: {a.table}. {count['HIT']} HIT, {count['UNKNOWN']} UNKNOWN (both open), {count['clear']} clear, "
                 f"{count['NOT APPLICABLE']} NOT APPLICABLE. Every open row gets `handled: <evidence>` or "
                 "`not relevant: <reason>` in its last column.", "",
                 "| id | status | pattern | replacement | evidence | unchecked | effort | risk | verified | handled |",
                 "|---|---|---|---|---|---|---|---|---|---|"]
        for x in results:
            lines.append("| " + " | ".join(esc(c) for c in (
                x["id"], x["status"], x["pattern"], x["replacement"], "; ".join(x["evidence"]), x["unchecked"],
                x["effort"], x["risk"], x["verified"], "")) + " |")
        Path(a.out).write_text("\n".join(lines) + "\n")
    if a.json:
        Path(a.json).write_text(json.dumps({"app": app.m.path, "from": frm, "to": a.to, "counts": count,
                                            "rows": results}, indent=1))
    return 1 if count["HIT"] or count["UNKNOWN"] else 0


if __name__ == "__main__":
    sys.exit(main())
