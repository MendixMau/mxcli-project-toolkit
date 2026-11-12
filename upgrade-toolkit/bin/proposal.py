#!/usr/bin/env python3
"""proposal.py: the upgrade proposal a person signs before anything in the app changes (trust spec section 2).

  proposal.py --work W [--source V --target V [--target2 V]] [--original W/original.mpr] [--app APPDIR] [--unattended]
  proposal.py --status --work W          prints: signed | paused | unsigned | none (no PROPOSAL.md); exit 0

Reads the triage outputs in W (each by the name triage writes it; an input that is absent or unreadable is listed under
"not measured" in section 5, never skipped silently):
  versions.txt, plan-pre.txt, plan.txt, module-jumps.txt            versions, module updates (steps/triage.md items 1-3, 10)
  kept.txt (W, else APP/.stepupdate/kept.txt)                       modules kept at their version (stepupdate output; a rerun)
  stranded.md                                                       one bullet or table row per stranded module (item 3)
  localedits.json                                                   RED / logic / Java and theme file edits (item 5)
  release-impact.md                                                 rows whose "handled" cell is empty need a person (item 10)
  replacements.md                                                   replacement_check.py rows, HIT and UNKNOWN open (item 10)
  dojo-react.md                                                     dojo_report.py: can't move / not researched widgets (item 10)
  actions.json                                                      action_inventory.py summary (action count)
  journey-scope.json                                                journey_scope.py: reachable / out of scope split of the actions
  apimock-inventory.json                                            apimock.py inventory --json: external systems
  original.mpr (or --original)                                      modules / pages / microflows, through mprmodel.py
  DECISIONS.md                                                      P-n lines answer the section-3 items
Four inputs of the trust spec have NO output before the convert and are always listed as not measured, with the tool and
why: widgetcover.py (judges rendered pages: the gate's widgets rung), theme_clash.py (needs the NEW Atlas), rolecheck.py
(needs the NEW model), usercode.py (per module, after the update step: .stepupdate/step<n>-<module>.usercode). Java and
theme edits that exist before the update come from localedits.json FILES-EDITED rows, which are read.

Writes W/PROPOSAL.md: six sections in order (summary; done by the toolkit; needs your decision; needs a person anyway;
human effort; sign-off). A comment line stores the hash of the plan inputs. Section 6 is written by a person:
  Signed-off: <name> <yyyy-mm-dd>        or        Status: PAUSED <reason>
Exit: 0 signed (the section-3 items nobody answered take their recommendation, recorded P-n CONFIRMED in DECISIONS.md),
      or unattended (nothing signed; ASSUMED (unattended) lines in DECISIONS.md), 14 unsigned, 15 PAUSED, 2 usage.
A rerun after sign-off whose plan inputs hash differently rewrites the file with a "Changed since signed" block, clears the
sign-off and exits 14 (asked again). kept.txt, DECISIONS.md and the count of open release rows are not in the hash: the
update step writes kept.txt and people close release rows after the sign-off.
Producer of the inputs: the pipeline steps fetch..basewalk (steps/triage.md) and step_propose, which runs
action_inventory.py and apimock.py inventory on original.mpr.
"""
import argparse, datetime, hashlib, json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
TK = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import steps  # noqa: E402  step records (STEP-RECORDS-PLAN.md): the proposal opens one step per item

SIGNED = re.compile(r"^Signed-off:[ \t]+(\S.*?)[ \t]+(\d{4}-\d{2}-\d{2})[ \t]*$")
PAUSED = re.compile(r"^Status:[ \t]+PAUSED[ \t]+(\S.*?)[ \t]*$")
HASH = re.compile(r"^<!-- proposal inputs-hash: ([0-9a-f]{64}) -->$")
# the toolkit's own assumption for the effort range, hours per touchpoint size; shown as an assumption, not a measurement
HOURS = {"S": (0.5, 2), "M": (2, 8), "L": (8, 40)}
NOT_BEFORE_CONVERT = [
    ("widgetcover.py", "it judges which widget packages the walks render; the walks of the new app exist only at the gate (widgets rung)"),
    ("theme_clash.py", "it compares the app's styling with the NEW Atlas, which exists only after the update"),
    ("rolecheck.py", "it compares the OLD and the NEW model; module roles are checked after each module update"),
    ("usercode.py", "it compares a module's Java user code per module, after the update step (.stepupdate/step<n>-<module>.usercode); "
                    "Java edits that exist now are the localedits.json FILES-EDITED rows"),
]


def load_ra(path=None):
    """Re-architecture catalogue (playbooks/rearchitecture.md): entries '### RA-n title' with '- field: value' lines.
    Tolerant: a missing file, an entry with no usable match regex or a bad regex is skipped, never an error."""
    t = read(path or os.path.join(TK, "playbooks", "rearchitecture.md"))
    out = []
    for blk in re.split(r"(?m)^### (?=RA-\d+\b)", t or "")[1:]:
        m = re.match(r"(RA-\d+)", blk)
        f = {k.lower(): v.strip() for k, v in re.findall(r"(?m)^- ([a-z]+): (.*)$", blk)}
        try:
            rx = re.compile(f.get("match", ""), re.I) if f.get("match") else None
        except re.error:
            rx = None
        if m and rx and f.get("options") and f.get("recommendation"):
            eff = f.get("effort", "M")[:1].upper()
            out.append({"id": m.group(1), "rx": rx, "options": f["options"], "rec": f["recommendation"],
                        "effort": eff if eff in "SML" else "M", "status": f.get("status", "idea")})
    return out


def read(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return None


def lines_of(path):
    t = read(path)
    return None if t is None else [x.rstrip("\n") for x in t.splitlines()]


def tables(text):
    """Markdown tables: [(lower-cased header cells, [row cells])]."""
    out, head, rows = [], None, []
    for line in text.splitlines():
        s = line.strip()
        if not (s.startswith("|") and s.endswith("|")):
            if head:
                out.append((head, rows))
            head, rows = None, []
            continue
        c = [x.strip().replace("\\|", "|") for x in re.split(r"(?<!\\)\|", s[1:-1])]
        if head is None:
            head = [x.lower() for x in c]
        elif all(re.match(r"^:?-{2,}:?$", x) for x in c if x):
            continue
        else:
            rows.append(c)
    if head:
        out.append((head, rows))
    return out


def col(head, row, name):
    return row[head.index(name)] if name in head and head.index(name) < len(row) else ""


class Facts:
    def __init__(self, a):
        self.a = a
        self.W = a.work
        self.measured, self.not_measured = [], []
        self.plan = []          # (module, from, to, when)
        self.kept = {}          # module -> reason
        self.stranded = {}      # module -> text
        self.items3 = []        # decision items
        self.items2 = []        # toolkit items
        self.items4 = []        # person items
        self.repair_rows = {}
        self.sizes = {}
        self.systems = None
        self.nendpoints = None; self.api_mocked = 0; self.api_unknown = []; self.api_excluded = 0
        self.dojo_adv = []
        self.release_open = None
        self.release_total = None
        self.actions = None
        self.scope = None       # journey_scope.py output: line, testability_line, counts
        self.effort = {}        # S/M/L -> count (section 3 items)

    def p(self, name):
        return os.path.join(self.W, name)

    def need(self, name, why=""):
        t = read(self.p(name))
        if t is None:
            self.not_measured.append((name, why or "file not found in the work folder"))
            return None
        self.measured.append(name)
        return t

    def add3(self, kind, name, evidence, options, rec, effort, risk):
        self.items3.append({"kind": kind, "name": name, "evidence": evidence, "options": options, "rec": rec,
                            "effort": effort, "risk": risk})

    # ---- inputs ----
    def versions(self):
        t = self.need("versions.txt")
        a = self.a
        self.src, self.tgt, self.tgt2 = a.source or "unknown", a.target or "unknown", a.target2
        if t is not None and not a.source:
            m = re.search(r"^app:\s*(\S+)", t, re.M)
            self.src = m.group(1) if m else "unknown"

    def plans(self):
        jumps = {}
        j = lines_of(self.p("module-jumps.txt"))
        if j is not None:
            self.measured.append("module-jumps.txt")
            for ln in j:
                m = re.match(r"^\s*(\S+)\s+(\S+)\s*->\s*(\S+)", ln)
                if m and not ln.lstrip().startswith("#"):
                    jumps[m.group(1)] = (m.group(2), m.group(3))
        else:
            self.not_measured.append(("module-jumps.txt", "the installed version of each module is unknown; the plan lists the target only"))
        # BT-11: the second pass starts from what the first pass left, not from the installed version (Atlas_Core 3.19.0 -> 3.21.1
        # before the convert, then 3.21.1 -> 4.5.1 after it, never 3.19.0 -> 4.5.1 beside the first line)
        left = {}
        for name, when in (("plan-pre.txt", "before the convert"), ("plan.txt", "after the convert")):
            ls = lines_of(self.p(name))
            if ls is None:
                self.not_measured.append((name, "no module updates are known for that pass" + (
                    "" if name == "plan.txt" else " (a 10.x source goes through plan-pre.txt, an 11.x or 9.x source has none)")))
                continue
            self.measured.append(name)
            for ln in ls:
                s = ln.strip()
                if not s or s.startswith("#"):
                    continue
                f = s.split()
                if len(f) < 3:
                    continue
                mod = f[2]
                fr = left.get(mod) or jumps.get(mod, ("?", f[1]))[0]
                left[mod] = f[1]
                self.plan.append((mod, fr, f[1], when))

    def keptmods(self):
        for path in (self.p("kept.txt"), os.path.join(self.a.app or "", ".stepupdate", "kept.txt") if self.a.app else None):
            ls = lines_of(path) if path else None
            if ls is None:
                continue
            self.measured.append("kept.txt")
            for ln in ls:
                f = ln.strip().split(None, 1)
                if f and not f[0].startswith("#"):
                    self.kept[f[0]] = f[1] if len(f) > 1 else "kept"
            return
        self.not_measured.append(("kept.txt", "written by the update step; before it runs, kept modules are only predicted by localedits RED rows and stranded.md"))

    def strandedmods(self):
        t = self.need("stranded.md", "steps/triage.md item 3 lists stranded modules and add-on modules built before 10.21 there")
        if t is None:
            return
        for ln in t.splitlines():
            s = ln.strip()
            m = (re.match(r"^[-*]\s+`?([A-Za-z][A-Za-z0-9_]*)`?\b[:\s-]*(.*)$", s)
                 or re.match(r"^#{2,}\s+`?([A-Za-z][A-Za-z0-9_]*)`?\b[:\s-]*(.*)$", s)
                 or re.match(r"^\|\s*`?([A-Za-z][A-Za-z0-9_]*)`?\s*\|(.*)$", s))
            if m and m.group(1).lower() not in ("module", "modules", "stranded", "name"):
                self.stranded.setdefault(m.group(1), m.group(2).strip(" |"))

    def localedits(self):
        t = self.need("localedits.json", "steps/triage.md item 5: localedits.py --json")
        self.red, self.logic, self.files, self.renamed = {}, {}, {}, {}
        if t is None:
            return
        try:
            rep = json.loads(t)
        except ValueError:
            self.measured.remove("localedits.json")
            self.not_measured.append(("localedits.json", "not valid JSON"))
            return
        # BT-6: a module the Marketplace renamed or republished (playbooks/module-renames.tsv, matched by content id)
        try:
            import renamed_modules
            for h in renamed_modules.find([e for e in rep if isinstance(e, dict)] if isinstance(rep, list) else []):
                self.renamed[h["module"]] = h
        except (OSError, ImportError):
            self.not_measured.append(("module-renames.tsv", "playbooks/module-renames.tsv could not be read; renamed Marketplace modules are not detected"))
        for e in rep if isinstance(rep, list) else []:
            n = e.get("name", "?")
            red = [x for x in (e.get("domain") or []) if x.get("data")]
            if red:
                self.red[n] = "; ".join(f"{x.get('change')} {x.get('kind')} {x.get('name')}" for x in red[:3]) + (f" (+{len(red) - 3})" if len(red) > 3 else "")
            lg = e.get("logic") or []
            if lg:
                self.logic[n] = f"{len(lg)} logic document(s) added or deleted locally"
            fl = e.get("files") or []
            if fl:
                self.files[n] = fl
            if (e.get("domain") is None) and not e.get("files_error"):
                self.logic.setdefault(n, "package not readable: edits UNKNOWN (never read as none)")

    def release(self):
        t = self.need("release-impact.md", "steps/triage.md item 10")
        if t is None:
            return
        tot = opn = 0
        for head, rows in tables(t):
            if "handled" not in head:
                continue
            for r in rows:
                tot += 1
                if not col(head, r, "handled").strip():
                    opn += 1
        self.release_total, self.release_open = tot, opn

    def repairmap(self):
        t = read(os.path.join(TK, "steps", "repair.md")) or ""
        for m in re.finditer(r"^\| (\d+) \|([^\n]*)$", t, re.M):
            code = re.search(r"\bCE\d{4}\b", m.group(2))
            for rid in set(re.findall(r"\bR\d{1,2}\b", m.group(0))):
                self.repair_rows[rid] = (m.group(1), code.group(0) if code else "")

    def replacements(self):
        t = self.need("replacements.md", "steps/triage.md item 10: replacement_check.py --out")
        if t is None:
            return
        for head, rows in tables(t):
            if "id" not in head or "status" not in head:
                continue
            for r in rows:
                rid, st = col(head, r, "id"), col(head, r, "status")
                short = lambda x: (x if len(x) <= 70 else x[:67].rsplit(" ", 1)[0] + "...")
                if st not in ("HIT", "UNKNOWN"):
                    continue
                ev, pat, rep = col(head, r, "evidence"), col(head, r, "pattern"), col(head, r, "replacement")
                eff = (col(head, r, "effort") or "M")[:1].upper()
                eff = eff if eff in "SML" else "M"
                if rid in self.repair_rows and st == "HIT":
                    n, code = self.repair_rows[rid]
                    self.items2.append({"key": f"repair:{rid}", "text": f"predicted repair {rid} ({short(pat)}) -> repair row {n}"
                                        + (f" ({code})" if code else "")})
                    continue
                low = (pat + " " + ev + " " + rep).lower()
                kind = ("widget" if "widget" in low or ".mpk" in low else "Java" if re.search(r"\bjava\b|\bjar\b", low)
                        else "theme" if re.search(r"theme|scss", low) else "page" if re.search(r"\bpage|layout|template", low)
                        else "re-architecture" if eff == "L" else "module")
                self.add3(kind, f"{rid} {short(pat)}", f"replacements.md row {rid} {st}: {ev or 'no detector decided'}",
                          f"{rep} (replacements.tsv row {rid})" if rep and rep != "-" else "see replacements.tsv row " + rid,
                          f"follow replacements.tsv row {rid}: {rep}" if rep and rep != "-" else "hand to a named person",
                          eff, (col(head, r, "risk") or "see the row")[:80])

    def dojo(self):
        t = self.need("dojo-react.md", "steps/triage.md item 10: dojo_report.py --out")
        if t is None:
            return
        for head, rows in tables(t):
            if head[:3] != ["status", "package", "version"]:
                continue
            for r in rows:
                st, pkg = r[0], r[1]
                ver = r[2] if len(r) > 2 else ""
                if st in ("can't move", "not researched", "unreadable"):
                    self.add3("widget", (pkg if ver in ("", "?") else f"{pkg} {ver}"), f"dojo-react.md: {st}: {r[3] if len(r) > 3 else ''}",
                              "keep old package, accept the risk | swap to a successor (dojo-successors.tsv) | rebuild as pluggable / native | hand to a named person",
                              "keep old package, accept the risk (advisory on 11, blocking on 12)", "L" if st == "can't move" else "M",
                              "does not run on the React client; Mendix 12 removes the Dojo client")
                elif st in ("can move", "delete"):
                    self.dojo_adv.append(f"{pkg} ({st})")
                    if st == "can move" and re.search(r"htmlsnippet|snippetjs", pkg + " " + (r[3] if len(r) > 3 else ""), re.I):
                        # the successor depends on what each snippet holds (HTML only, a little script, DOM work): a decision per snippet
                        self.add3("widget", (pkg if ver in ("", "?") else f"{pkg} {ver}"),
                                  f"dojo-react.md: can move: {r[3] if len(r) > 3 else ''}; the successor depends on the content of each snippet",
                                  "keep on the Dojo client for now | HTML Element widget | JavaScript action + nanoflow + Events | pluggable widget | hand to a named person",
                                  "keep on the Dojo client on an 11 target (advisory on 11, blocking on 12); classify every snippet first", "M",
                                  "script in a snippet runs on the Dojo page DOM; Mendix 12 removes the Dojo client")

    def sizes_and_actions(self):
        t = read(self.p("actions.json"))
        if t is None:
            self.not_measured.append(("actions.json", "action_inventory.py; the action count of the app is unknown"))
        else:
            try:
                self.actions = json.loads(t)["summary"]["actions"]
                self.measured.append("actions.json")
                sc = read(self.p("journey-scope.json"))
                if sc is not None:
                    try:
                        d = json.loads(sc)
                        self.scope = {k: d[k] for k in ("line", "testability_line", "counts")}
                        self.measured.append("journey-scope.json")
                    except (ValueError, KeyError, TypeError):
                        self.not_measured.append(("journey-scope.json", "not a journey_scope.py file"))
            except (ValueError, KeyError, TypeError):
                self.not_measured.append(("actions.json", "not an action_inventory.py file"))
        orig = self.a.original or self.p("original.mpr")
        if not os.path.exists(orig):
            self.not_measured.append(("original.mpr", "modules, pages and microflows cannot be counted"))
            return
        try:
            import mprmodel
            m = mprmodel.Model.load(orig)
            docs = list(m.docs.items())
            self.sizes = {"modules": len({qn.split(".")[0] for qn, _ in docs}),
                          "pages": sum(1 for _, d in docs if d.type == "Forms$Page"),
                          "microflows": sum(1 for _, d in docs if d.type == "Microflows$Microflow")}
            self.measured.append("original.mpr")
        except Exception as ex:  # noqa: BLE001  an unreadable model is not an empty app
            self.not_measured.append(("original.mpr", f"cannot be read ({ex}); modules, pages and microflows are not counted"))

    def apimock(self):
        t = read(self.p("apimock-inventory.json"))
        if t is None:
            self.not_measured.append(("apimock-inventory.json", "apimock.py inventory; the external systems the app consumes are unknown"))
            return
        try:
            eps = json.loads(t)["endpoints"]
            self.systems = sorted({(e.get("system") or "unclassified") for e in eps})
            self.nendpoints = len(eps)
            self.api_mocked = sum(1 for e in eps if e.get("status") == "MOCKED")
            self.api_unknown = [e for e in eps if e.get("status") == "UNKNOWN"]
            self.api_excluded = sum(1 for e in eps if e.get("status") == "EXCLUDED")
            self.measured.append("apimock-inventory.json")
        except (ValueError, KeyError, TypeError):
            self.not_measured.append(("apimock-inventory.json", "not an apimock.py inventory file"))

    def build(self):
        self.versions(); self.repairmap(); self.plans(); self.keptmods(); self.strandedmods(); self.localedits()
        self.release(); self.replacements(); self.dojo(); self.sizes_and_actions(); self.apimock()
        for tool, why in NOT_BEFORE_CONVERT:
            self.not_measured.append((tool, why))
        # modules that are decisions, never "done by the toolkit"
        held = {}
        for m, h in self.renamed.items():
            held[m] = (f"{h['kind']} on the Marketplace: content {h['cid']} is now '{h['new']}' (installed {m} {h['version']}); "
                       f"no version update of {m} is planned. {h['route']}")
        for m, why in self.kept.items():
            held[m] = f"kept at its version by the update step: {why}"
        for m, why in self.red.items():
            held.setdefault(m, f"RED local edit (data-bearing): {why}")
        for m, why in self.logic.items():
            held.setdefault(m, f"local logic edits: {why}")
        for m, why in self.stranded.items():
            held.setdefault(m, f"stranded (no version fits the target): {why or 'see stranded.md'}")
        for m, rows in self.files.items():
            kinds = sorted({x.get("kind", "?") for x in rows})
            if "java" in kinds:
                held.setdefault(m, f"Java user code edited locally ({len(rows)} FILES-EDITED rows)")
        for m, why in sorted(held.items()):
            kind = "module"
            if m in self.files and any(x.get("kind") == "java" for x in self.files[m]) and m not in self.kept and m not in self.red:
                kind = "Java"
            stranded = m in self.stranded
            if m in self.renamed:
                self.add3("renamed module", m, held[m] + f" ({self.renamed[m]['row']}, playbooks/module-renames.tsv)",
                          "install the new module and move the references | keep the installed module as is and test it at the gate | hand to a named person",
                          "install the new module" if self.renamed[m]["kind"] == "RENAMED" else "keep the installed module, test it at the gate; the owner decides on the new listing",
                          "M", "references and data of the old module are moved by hand" if self.renamed[m]["kind"] == "RENAMED" else "the installed version may not run on the target")
                continue
            self.add3(kind, m, why + " (" + ("stranded.md" if stranded else "localedits.json / kept.txt") + ")",
                      "keep old version (kept list) | replace with the Marketplace equivalent (replacements.tsv row) | rebuild locally, drop the module | hand to a named person"
                      if kind == "module" else "keep old jar, pin | port to the new API | replace with a Marketplace module or a microflow | hand to a named person",
                      "hand to a named person (no version fits; port, replace or remove)" if stranded else
                      "keep old version (kept list); the stop rule keeps it unattended" if kind == "module" else "keep old jar, pin",
                      "L" if stranded else "M", "data loss if a RED edit is replaced" if m in self.red else "behaviour of local edits is lost on update")
        for m, rows in sorted(self.files.items()):
            if any(x.get("kind") == "theme" for x in rows):
                self.add3("theme", f"{m} themesource edits", f"localedits.json FILES-EDITED rows of {m} in themesource/",
                          "keep module styling and replay | adopt the package styling | hand to a named person",
                          "replay the edits after the update (UI-only edits are replayed by the pipeline)", "S", "look only")
        for mod, fr, to, when in self.plan:
            if mod in held:
                continue
            self.items2.append({"key": f"module:{mod}", "text": f"module update {mod} {fr} -> {to} ({when})"})
        self.items2.sort(key=lambda x: x["key"])
        self.items3.sort(key=lambda x: (x["kind"], x["name"]))
        # re-architecture catalogue: the first RA entry whose match fits kind + name + evidence prefills options, recommendation, effort
        ra = load_ra(getattr(self.a, "ra_file", None))
        for it in self.items3:
            for e in ra:
                if e["rx"].search(f"{it['kind']} {it['name']} {it['evidence']}"):
                    it["options"], it["effort"] = e["options"], e["effort"]
                    it["rec"] = f"{e['rec']} [{e['id']}, {e['status']}, playbooks/rearchitecture.md]"
                    break
        # section 4: a person anyway
        if self.release_open:
            self.items4.append({"key": "release-rows", "text": "release-impact rows a person must judge",
                                "detail": f"{self.release_open} of {self.release_total} rows have no 'handled' entry yet (release-impact.md)"})
        self.items4.append({"key": "key-user", "text": "key-user confirmation of the user processes (status: confirmed is set only by a person)",
                            "detail": "templates/process-interview.md; the number of processes is unknown at this point"})
        self.items4.append({"key": "visual", "text": "visual sign-off of the changed screens (shotdiff REVIEW pairs)",
                            "detail": "the number of changed screens is known only after the gate"})
        if self.systems:
            self.items4.append({"key": "apis:" + ",".join(self.systems), "text": "real test systems for external APIs: " + ", ".join(self.systems),
                                "detail": f"{self.nendpoints} endpoints in apimock-inventory.json; the stand-in gives at best PASS (on stand-in APIs)"})
        elif self.systems is not None:
            self.items4.append({"key": "apis:none", "text": "external systems: none found by apimock.py inventory", "detail": ""})
        self.items4.append({"key": "go-live", "text": "go-live actions (deployment, data migration window, rollback decision)",
                            "detail": "outside the toolkit"})


def ids_for(items, work):
    """Stable P-n ids: first appearance order, remembered in state/proposal-ids.json."""
    path = os.path.join(work, "state", "proposal-ids.json")
    try:
        ids = json.load(open(path))
    except (OSError, ValueError):
        ids = {}
    for it in items:
        k = f"{it['kind']}:{it['name']}"
        if k not in ids:
            ids[k] = max(ids.values(), default=0) + 1
        it["id"] = f"P-{ids[k]}"
    os.makedirs(os.path.dirname(path), exist_ok=True)
    json.dump(ids, open(path, "w"), indent=1, sort_keys=True)


def plainify(text, fallback):
    """The text when it is plain words for a person (steps.plain), else without its parentheses, else the fallback."""
    s = " ".join(str(text).split())
    for c in (s, re.sub(r"\s*\([^)]*\)", "", s).strip(" ;,"), re.sub(r"\s*\[[^\]]*\]", "", s).strip(" ;,")):
        if c and steps.plain(c):
            return c
    return fallback


def major(v):
    """The major version number of a Mendix version string, None when it has none."""
    m = re.match(r"\s*(\d+)\.", str(v or ""))
    return int(m.group(1)) if m else None


def write_steps(F, work):
    """Open (or find) one step per triage item and set found and proposed (STEP-RECORDS-PLAN.md section 3). A rerun with the
    same input adds no event; the same topic and title is the same step. Returns {step id: key} in item order.
    Routine module updates (section 2) are ONE step per topic row, approved with the plan sign-off. Section 3 items keep
    their P-n as the alias field of the step; PROPOSAL.md itself keeps showing [P-n]. Plain-language texts are fixed
    template sentences (the item's own words only when they are plain)."""
    out = {}
    groups = [("modules", "Routine module updates", "module", ("module update in the plan that the toolkit does on its own", "module updates in the plan that the toolkit does on its own"),
               "Update these modules to the versions that fit the new Mendix version."),
              ("repairs", "Predicted repairs", "repair", ("repair that the toolkit expects to make", "repairs that the toolkit expects to make"),
               "Make these repairs during the upgrade, as the repair table describes.")]
    for topic, title, key, what, prop in groups:
        its = [x for x in F.items2 if x["key"].startswith(key + ":")]
        if not its:
            continue
        sid = steps.ensure(work, topic, title, {
            "found_say": f"The plan holds {len(its)} {what[len(its) != 1]}.", "stage": "triage", "evidence": [x["text"] for x in its],
            "proposed_say": prop, "why": "Routine work with a known result. It is approved with the sign-off of the plan."})
        out[sid] = f"2:{topic}"
    if major(F.src) and major(F.tgt) and major(F.src) != major(F.tgt):
        # the plan converts the app: the convert commit and the "after the convert" updates belong to this step (steps.py trailer --kind convert)
        sid = steps.ensure(work, "convert", "Convert the app to the new Mendix version", {
            "found_say": f"The app is on Mendix {major(F.src)} and the plan moves it to Mendix {major(F.tgt)}, which needs the Mendix conversion.",
            "stage": "triage", "evidence": [f"{F.src} -> {F.tgt}"],
            "proposed_say": "Run the Mendix conversion once, then fix what it leaves open.",
            "why": "Routine work with a known result. It is approved with the sign-off of the plan.", "closes_by": ["build"]})
        out[sid] = "2:convert"
    for it in F.items3:
        opts = [o.strip() for o in it["options"].split(" | ") if o.strip()]
        opts = [plainify(o, "see the proposal for this option") for o in opts]
        rec = re.sub(r"\s*\[RA-\d+[^\]]*\]", "", it["rec"])
        pick = next((i for i, o in enumerate(opts) if o.split(" (")[0].lower() in rec.lower()), None)
        name = plainify(it["name"], "")
        sid = steps.ensure(work, f"{it['kind']}:{it['name']}", steps.item_title(it["kind"], it["name"]), {
            "alias": it["id"],
            "found_say": f"A {it['kind']}{(' (' + name + ')') if name else ''} needs a decision before the upgrade starts.",
            "stage": "triage", "evidence": [it["evidence"]],
            "proposed_say": "The toolkit recommends: " + plainify(rec, "the first option in the proposal") + ".",
            "why": f"Effort {it['effort']}. Risk: " + plainify(it["risk"], "see the proposal") + ".",
            "options": opts, "recommend": pick})
        out[sid] = f"3:{it['id']}"
    for it in F.items4:
        sid = steps.ensure(work, f"person:{it['key']}", it["text"], {
            "found_say": plainify(it["text"], "A person has to do something that the toolkit cannot do.") .rstrip(".") + ".",
            "stage": "triage", "evidence": [it["detail"]] if it["detail"] else None,
            "proposed_say": "A person does this. The toolkit lists it so it is not forgotten.",
            "why": "The toolkit has no way to do this on its own."})
        out[sid] = f"4:{it['key']}"
    return out


def approve_steps(work, ids, state, signer, source, answers=None):
    """Write the approval of every step that has none yet (state assumed: unattended run) or is not answered on its own
    (state approved: the sign-off). A step a person approved or rejected on its own keeps that answer. A section-3 item
    with a hand-written, non-ASSUMED P-n line in DECISIONS.md is approved by the name on that line."""
    n = 0
    for sid, key in ids.items():
        cur = steps.approval_of(work, sid)
        have = cur["state"] if cur else None
        if state == "assumed" and have:
            continue
        if state == "approved" and have in ("approved", "rejected"):
            continue
        by, src = signer, source
        d = (answers or {}).get(key[2:]) if key.startswith("3:") else None
        if state == "approved" and d and len(d) > 5 and not d[5].startswith("ASSUMED") and d[4] not in ("", "-"):
            by, src = d[4], "decisions"
        extra = {"needs": "a person signs the proposal or answers this item"} if state == "assumed" else {}
        steps.set_approval(work, sid, state, by, src, **extra)
        n += 1
    return n


def decisions(work):
    out = {}
    for ln in lines_of(os.path.join(work, "DECISIONS.md")) or []:
        m = re.match(r"^(P-\d+)\s*\|(.*)$", ln)
        if m:
            f = [x.strip() for x in m.group(2).split("|")]
            out[m.group(1)] = f
    return out


def testing_plan(F):
    """The testing plan: what is tested and how, what cannot be tested in the sandbox, how each gap is closed. From the
    apimock inventory, the action inventory and the app shape only; a missing input is said, never guessed."""
    sz = F.sizes
    L = ["", "## Testing plan", "",
         "What the gate tests, what it cannot test in a sandbox, and how each gap is closed. Numbers come from the inputs named in section 5.", "",
         "### What is tested and how", ""]
    L.append("- build: mx check and mxbuild of the converted app, errors listed per code" +
             (f" ({sz['modules']} modules, {sz['pages']} pages, {sz['microflows']} microflows)" if sz else " (app size not measured)"))
    L.append("- data: the old and the new app each start on a copy of the same database; every table is compared row by row (a row that differs is FAIL until accepted with a written reason)")
    L.append("- journeys: " + (f"one browser journey per action ({F.actions} actions in the inventory)" if F.actions is not None else "one browser journey per action (action count not measured)") +
             ", per role, run on the old app and the new app; a difference is a regression")
    if F.scope:   # journey_scope.py: only what is used and reachable counts; the rest is listed, never INVALID
        L.append("  - " + F.scope["line"])
        L.append("  - " + F.scope["testability_line"] + "; each of these stays INVALID in the gate until it has a path")
    if F.nendpoints is not None:
        unk = len(F.api_unknown)
        L.append(f"- external calls on a stand-in: {F.nendpoints} endpoints and constants found, {F.api_mocked} can be answered by the stand-in (apimock.py), {unk} are UNKNOWN"
                 + (f", {F.api_excluded} excluded" if F.api_excluded else "") + "; the apis rung checks that the stand-in was asked what the model says it should be asked")
    else:
        L.append("- external calls: not measured (no apimock-inventory.json)")
    L += ["", "### What cannot be tested in the sandbox", ""]
    if F.nendpoints is not None:
        L.append(f"- {len(F.api_unknown)} of {F.nendpoints} external endpoints are UNKNOWN: no stand-in route exists, so a journey that needs one is INVALID, not PASS" +
                 (" (examples: " + ", ".join(sorted({e.get('doc') or e.get('id') for e in F.api_unknown})[:5]) + ")" if F.api_unknown else ""))
    L.append("- the real behaviour of an external system (answers, limits, errors): a stand-in only returns shaped data, so a pass on it is reported as PASS (on stand-in APIs), never plain PASS")
    L.append("- single sign-on and any login through an identity provider: the sandbox uses local smoke users")
    L.append("- data the sandbox database does not hold (an action that needs rows of a kind that does not exist yet): the heal step seeds identical rows in both databases where it can, the rest stays INVALID")
    L += ["", "### How each gap is closed", ""]
    L.append("- classify every UNKNOWN endpoint (static, data-driven or add-on) in apimock-classify.txt; owner: the person who knows the integration")
    L.append("- seed the data that data-driven endpoints need, in the old and the new database alike; owner: the app owner")
    L.append("- run the apis rung against a real test system before go-live and compare with the stand-in run; owner: a named person on the customer side")
    L.append("- go-live decision on every INVALID journey that remains: accept in writing or test by hand; owner: a named person")
    return L


def render(F, hashval, changed_block, signoff_text):
    a = F.a
    ans = decisions(F.W)
    n2, n3, n4 = len(F.items2), len(F.items3), len(F.items4)
    sz = F.sizes
    size = (f"{sz['modules']} modules, {sz['pages']} pages, {sz['microflows']} microflows" if sz else "modules, pages, microflows not measured")
    size += f", {F.actions} actions" if F.actions is not None else ", actions not measured"
    rungs = f"rung 1 {F.src} -> {F.tgt}" + (f", rung 2 {F.tgt} -> {F.tgt2}" if F.tgt2 else "")
    L = [f"# Upgrade proposal: {F.src} -> {F.tgt}" + (f" -> {F.tgt2}" if F.tgt2 else ""), "",
         f"<!-- proposal inputs-hash: {hashval} -->", "",
         "Written by bin/proposal.py from the triage outputs. Nothing in the app model changes before section 6 is signed. "
         "Every line starting with `- ` is an item; sub-lines are evidence.", ""]
    if changed_block:
        L += changed_block + [""]
    L += ["## 1. Summary", "",
          f"- From {F.src} to {F.tgt}" + (f" and {F.tgt2}" if F.tgt2 else "") + f" ({rungs}). App size: {size}.",
          f"- {n2} items the toolkit expects to handle, {n3} need your decision, {n4} need a person anyway.", "",
          "## 2. Done by the toolkit", "",
          "Module updates and predicted repairs only. A kept module, a stranded module, a RED local edit and a widget with no "
          "successor are never here; they are in section 3.", ""]
    L += [f"- {it['text']}" for it in F.items2] or ["- none: no module update and no predicted repair in the inputs read"]
    L += ["", "## 3. Needs your decision before we start", "",
          "Answer each item in chat (steps/decide.md options); the toolkit records it in DECISIONS.md as the P-n line. "
          "Signing section 6 without an answer accepts the recommendation of that item.", ""]
    for it in F.items3:
        L.append(f"- [{it['id']}] {it['kind']}: {it['name']}")
        L.append(f"  - evidence: {it['evidence']}")
        L.append(f"  - options: {it['options']}")
        L.append(f"  - recommendation: {it['rec']}; effort {it['effort']}; risk: {it['risk']}")
        d = ans.get(it["id"])
        L.append(f"  - answer: {d[2] if len(d) > 2 else '?'} ({d[5] if len(d) > 5 else '?'})" if d else "  - answer: not yet")
    if not F.items3:
        L.append("- none: no kept, stranded, RED, Java, theme, widget or replacement item in the inputs read")
    L += ["", "## 4. Needs a person anyway", ""]
    for it in F.items4:
        L.append(f"- {it['text']}")
        if it["detail"]:
            L.append(f"  - {it['detail']}")
    if F.dojo_adv:
        L.append("- React client switch, advisory on 11 (not done in this run): " + ", ".join(F.dojo_adv[:12]) + (" ..." if len(F.dojo_adv) > 12 else ""))
    # section 5
    cnt = {}
    for it in F.items3:
        cnt[it["effort"]] = cnt.get(it["effort"], 0) + 1
    lo = sum(HOURS[e][0] * n for e, n in cnt.items())
    hi = sum(HOURS[e][1] * n for e, n in cnt.items())
    kinds = {}
    for it in F.items3:
        kinds[it["kind"]] = kinds.get(it["kind"], 0) + 1
    L += ["", "## 5. Human effort", "",
          "- decision touchpoints: " + (", ".join(f"{k} {n}" for k, n in sorted(kinds.items())) or "0"),
          f"- person-anyway touchpoints: {n4}" + (f", release rows to judge {F.release_open}" if F.release_open else ""),
          f"- range for the decisions alone: {lo:g} to {hi:g} hours (toolkit assumption per item: " + ", ".join(
              f"{e} {HOURS[e][0]:g}-{HOURS[e][1]:g} h" for e in "SML") + "; not measured). Key-user time, screen review and go-live are not in it.",
          "- unknown at this point:"]
    L += [f"  - not measured: {n}: {w}" for n, w in F.not_measured] or ["  - nothing: every input was read"]
    L += testing_plan(F)
    L += ["", "## 6. Sign-off", "", signoff_text, ""]
    return "\n".join(L)


def signoff_default():
    return ("A person writes exactly one of these two lines below (an agent never does):\n\n"
            "`Signed-off: <name> <yyyy-mm-dd>`   or   `Status: PAUSED <reason>`\n\n"
            "Status: open")


def parse_signoff(text):
    if not text:
        return None
    i = text.find("\n## 6.")
    for ln in (text[i:] if i >= 0 else "").splitlines():
        m = PAUSED.match(ln)
        if m:
            return ("paused", m.group(1), "")
    for ln in (text[i:] if i >= 0 else "").splitlines():
        m = SIGNED.match(ln)
        if m:
            return ("signed", m.group(1), m.group(2))
    return None


def item_lines(text):
    out = set()
    sec = ""
    for ln in (text or "").splitlines():
        if ln.startswith("## "):
            sec = ln
        elif ln.startswith("- ") and sec[:5] in ("## 2.", "## 3.", "## 4."):
            out.add(sec[3:4] + ": " + re.sub(r"^- \[P-\d+\] ", "- ", ln))
    return out


def write_decisions(F, rows, signer, status, closes):
    path = os.path.join(F.W, "DECISIONS.md")
    have = decisions(F.W)
    add = []
    for rid, name, kind, option, reason in rows:
        if rid in have:
            continue
        add.append(f"{rid} | {name} | {kind} | {option} | {reason} | {signer} | {status} | closes by: {closes}")
    if add:
        with open(path, "a", encoding="utf-8") as f:
            if os.path.exists(path) and os.path.getsize(path) and not (read(path) or "").endswith("\n"):
                f.write("\n")
            f.write("\n".join(add) + "\n")
    return len(add)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--work", required=True)
    ap.add_argument("--source"); ap.add_argument("--target"); ap.add_argument("--target2")
    ap.add_argument("--original"); ap.add_argument("--app")
    ap.add_argument("--unattended", action="store_true")
    ap.add_argument("--ra-file", help="re-architecture catalogue to read (default playbooks/rearchitecture.md)")
    ap.add_argument("--status", action="store_true")
    a = ap.parse_args()
    a.work = os.path.abspath(a.work)
    out_path = os.path.join(a.work, "PROPOSAL.md")
    old = read(out_path)
    if a.status:
        s = parse_signoff(old)
        print("none" if old is None else s[0] if s else "unsigned")
        return 0
    if not os.path.isdir(a.work):
        print(f"proposal: no work folder {a.work}", file=sys.stderr)
        return 2
    F = Facts(a)
    F.build()
    ids_for(F.items3, a.work)
    sids = write_steps(F, a.work) if os.path.isdir(a.work) else {}
    ident = [f"2|{it['key']}|{it['text']}" for it in F.items2] + [f"3|{it['kind']}|{it['name']}|{it['evidence']}" for it in F.items3] \
        + [f"4|{it['key']}|{it['text']}" for it in F.items4] + [f"v|{F.src}|{F.tgt}|{F.tgt2}"]
    hashval = hashlib.sha256("\n".join(sorted(ident)).encode()).hexdigest()
    prev_hash = next((m.group(1) for m in (HASH.match(x) for x in (old or "").splitlines()) if m), None)
    so = parse_signoff(old)
    today = os.environ.get("PROPOSAL_TODAY") or datetime.date.today().isoformat()

    def accept_answers(signer):
        ans = decisions(a.work)
        rows = [(it["id"], it["name"], it["kind"], it["rec"], f"accepted with the sign-off of {signer} (no separate answer)")
                for it in F.items3 if it["id"] not in ans]
        return write_decisions(F, rows, signer, "CONFIRMED", "the rung that measures it passes (steps/decide.md)")

    if so and so[0] == "paused":
        print(f"proposal: PAUSED by the owner: {so[1]}. Resume: remove the Status line and sign, then rerun the pipeline.")
        return 15
    if so and so[0] == "signed" and prev_hash == hashval:
        n = accept_answers(so[1])
        approve_steps(a.work, sids, "approved", so[1], "signoff", decisions(a.work))
        print(f"proposal: signed by {so[1]} on {so[2]}" + (f"; {n} unanswered section-3 item(s) took their recommendation (DECISIONS.md)" if n else ""))
        return 0
    changed = None
    signoff = signoff_default()
    if so and so[0] == "signed":
        cur = render(F, hashval, None, signoff)
        before, after = item_lines(old), item_lines(cur)
        changed = [f"## Changed since signed ({so[1]}, {so[2]})", "",
                   "The plan inputs changed after the sign-off; the sign-off is cleared and the proposal is asked again. "
                   "Items that differ from the signed version:", ""]
        changed += [f"- removed: {x}" for x in sorted(before - after)] + [f"- added: {x}" for x in sorted(after - before)]
        if before == after:
            changed.append("- no item text differs; the versions or the evidence behind an item changed (compare the input files)")
        signoff = f"Previously signed-off: {so[1]} {so[2]} (cleared: the plan inputs changed)\n\n" + signoff
    doc = render(F, hashval, changed, signoff)
    tmp = out_path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(doc)
    os.replace(tmp, out_path)
    if a.unattended:
        rows = [("P-0", "proposal", "proposal", "continue without a sign-off", "Interview mode: unattended signs nothing; the run goes on at the recommendations")]
        rows += [(it["id"], it["name"], it["kind"], it["rec"], "unattended: recommendation taken, nobody asked") for it in F.items3]
        write_decisions(F, rows, "-", "ASSUMED (unattended)", "a person signs PROPOSAL.md section 6")
        approve_steps(a.work, sids, "assumed", "agent", "unattended")
        print("proposal: not signed (unattended): ASSUMED (unattended) lines in DECISIONS.md; every report says 'proposal not signed'")
        return 0
    print(f"proposal awaits sign-off: {out_path} ({len(F.items2)} done by the toolkit, {len(F.items3)} to decide, {len(F.items4)} for a person)")
    return 14


if __name__ == "__main__":
    sys.exit(main())
