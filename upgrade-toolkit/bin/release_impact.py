#!/usr/bin/env python3
"""release_impact.py: the release-note rows an upgrade must handle, from the brain's version tables (V31-RI).

The brain holds the official Studio Pro and Marketplace release notes, but the runs barely read them: E6 and E7 picked
module versions without reading what changed, and E5b looked for a Java 11 error that the 10.x table explains (Java
21 only from 10.21.0). This lists every row in the jump, one per finding, with an empty "handled" column.

  release_impact.py --from <ver> --to <ver> [--plan plan.txt] [--from-mpr old.mpr --to-mpr new.mpr]
                    [--auto --facts facts.json ...] [--types t1,t2] [--out release-impact.md] [--brain DIR]
  release_impact.py --facts-from-mpr app.mpr [--db-vendor V --db-version N --runtime-os linux] [--facts-out facts.json]
  release_impact.py --check release-impact.md

  --from/--to  Studio Pro versions (full or short). Rows with from < version <= to, across majors: 10.24.16 to 11.12.2
               reads the 11 table and the 10.24 rows above 10.24.16.
  --plan       module jumps, one per line, # comments allowed:
                 <Module> <old>-><new> [brain slug] [content id]   (spaces around -> allowed; a number is the content id)
                 <content id> <new> <Module> <old>         (a stepupdate plan line with the installed version added)
               Module rows: old < version <= new. The brain file is found by content id first (a renamed module:
               DataGrid is Data Widgets 116540), then by name (CamelCase or snake_case to the slug, the title,
               "<name>module", "mendix<name>", trailing digits dropped). No file, or more than one match, is UNKNOWN:
               read that module's release notes by hand.
  --from-mpr/--to-mpr  the plan from the two projects themselves (T1-31): the installed Marketplace modules of both,
               paired by content id, then by name. Updated modules get their rows; kept (same version), newly
               installed (by repair, missing_deps) and removed modules are listed in one table, without rows. Use the
               UPGRADED project as --to-mpr after repair, so the plan holds what really happened. --plan lines win
               over the projects for the same module. A module updated by mxcli/stepupdate has no content id in the
               new project (T6R: 12 of 13 updated modules): the old project's id is used (T6R-4). --from-mpr does not
               give the Studio Pro jump: --from/--to are still required (the error names the versions the .mpr files hold).
  --slug Module=slug  the brain file of a module the name and the content id cannot find (repeatable, T6R-4); the
               same as the third field of a --plan line, for --from-mpr/--to-mpr plans.
  --auto --facts F  pre-fill "not relevant (auto): <rule>: <fact>" where a rule and an app fact settle a row. F is
               the --json of test_inventory.py, or a hand-written JSON (several --facts merge, later wins):
                 {"db_vendor": "postgresql", "db_version": "16", "odata_published": 0, "odata_consumed": 0,
                  "odata_consumed_connector": 0,
                  "rest_published": 5, "rest_consumed": 0, "web_services": 0, "workflows": 1, "own_java": 0,
                  "native_profile": false, "oql": 0, "document_templates": 0, "kept": ["M"], "stranded": ["M"]}
               counts or booleans; odata_consumed_connector counts references into OData connector modules
               (SAPODataConnector, ODataQueryBuilder, ...; T3F-11): consumed OData rows close only when it is 0 too,
               and a facts file without it leaves them open; oql counts OQL anywhere (datasets, OQL actions, view entities, Marketplace
               modules too). A fact not given is unknown and fires no rule. Rules: studio-pro-ide rows that are no
               breaking or removal and name nothing the app holds (pages, widgets, URLs, mpr, Java, ...); data-storage
               rows about other database vendors, or only other versions of yours; on a cross-major path the
               patch rows of the source's own line above it (9.24.x above 9.24.2 on a path to 10: the target major's
               rows carry them); every row of a kept or stranded module; rows whose features (OData, REST, web
               services, native, workflows, OQL, document templates) are all absent by the facts; java-actions
               deprecations when own_java is 0; module requirement rows that only raise the module's minimum
               Mendix version to one at or below --to (a minimum above it stays open: a blocker). A row about a
               present or unknown feature stays open, whatever its type: breaking, removal and runtime rows of used
               features need a scan or journey, never the build alone. Rows one fact decides (N1-9), each citing it:
               .NET of the Studio Pro host (runtime_os linux or container: the Mendix runtime there is Java), a language code
               (languages: none of the named codes is in the app; a language row is never closed by the IDE rule), a database
               vendor or version (db_vendor, db_version; "From July 6, 2026" is a date, not a version range; a number after
               "JDBC driver" is the driver's), a JDBC driver row (own_jdbc 0, and database_connector 0 when the row names the
               Database Connector), Core.addDevelopmentServlet (dev_servlet 0). T6R-5: requirement and deprecation rows of
               git-teamserver and mxbuild-cli (the developer's tools, the build host) under the same IDE_REACHES_APP test;
               the SVN removal when the project is under Git (vcs); with project_dir (written by --facts-from-mpr when a
               javasource folder is next to the mpr, or given by hand) a java-actions removal whose every `affected` item
               is a Java symbol none of which occurs in javasource (proxies excluded) or in a userlib jar's class files
               (java-symbol-absent, the scope is cited), and a module requirement row that only bumps libraries of
               LIB_PKG which no Java outside javasource/<module>/ imports (module-library-bump). A prose item, a
               breaking java-actions row, a library outside the map: open. PV-4: the Java is read as it was at the run start,
               not as it is: --java-rev REV, else the newest commit whose subject starts "original:" (none, or not a git
               project: the tree as it is). A symbol that occurred there and is gone now is "handled (auto):
               java-symbol-ported" with the commit that removed it, never "not relevant"; one still present stays open.
               (Product View 360: row 28 was closed "java-symbol-absent" after the Java port, the kept modules had used it.) breaking and removal rows of studio-pro-ide
               stay open: some change the model (B1-RI). A human entry is never replaced; auto
               entries are recomputed on every --auto rerun (so changed facts change them).
  --facts-from-mpr app.mpr  (T2F-2, N1-9) the facts that a model and its javasource folder can answer, counted and written to
               --facts-out (default facts.json): published/consumed OData and REST, web services, workflows, document
               templates, OQL (datasets, view entities), native profile, the languages, own Java files, own Java that
               opens JDBC (java.sql, DriverManager, jdbc:), any call of addDevelopmentServlet in javasource, the Database
               Connector module. A feature is counted 0 only when NO model type of that family occurs anywhere in the model
               (broad on purpose: a false hit leaves a row open, a miss would close a used feature). OData and REST count
               services, not element types (T2R3-3): the published/consumed service documents, and for consumed REST also
               the REST call actions (RestCallAction, SendRestRequestAction; T8R-11); an element of the family outside
               any such document with none found leaves that fact unknown. native_profile is read from the navigation
               profiles only (T2R3-3, N1R2-5): true for a NativeNavigationProfile or a native/hybrid/offline Kind, false when
               every profile is Responsive, Tablet or Phone (Atlas_Core's Platform Native building blocks are no use),
               unknown for no profile or another kind. A test_inventory --json gives rest_consumed as REST clients plus its
               rest_call_activities, unknown without that count (T8R-11). What no file
               can answer is left out and listed: the database the app RUNS on (--db-vendor, --db-version; the model's
               development configuration is HSQLDB, no deployment database) and the OS (--runtime-os linux).
               With --auto and no --facts, --from-mpr (or --to-mpr, or --facts-from-mpr) is read the same way, next to --out as
               <out>.facts.json; --facts files given too win over it. One mpr alone gives facts, no module rows: a line
               "auto cannot use: ..." says each thing that is lost (module rows, kept/stranded, every fact not known).
  --types      default breaking,removal,requirement,deprecation (module rows also migration-step); also security, known-issue, improvement, feature, fix
  --brain      default $UPG_BRAIN or ~/Mendix/<company>-brain
  --out        default release-impact.md. A rerun keeps the handled entries of rows it finds again. An entry whose row is gone
               (the brain reworded it, T2F-4) is listed under "Entries that matched no row", kept until the row returns, and
               counted in the output. With --auto a rerun also says how many human entries auto would have decided and which
               differ in kind (T2F-3); the header counts auto, kept and open (T2F-5).
  --check      exit 1 while any row has no "handled: <evidence path or commit>" or "not relevant: <reason>" entry
               ("handled (...)" and "handled - ..." count too, T5-20). Prints auto, human and open counts.

Exit (generate): 0 = written, every source covered; 2 = something not covered (an UNKNOWN module, a plan line without
an old version, no Studio Pro table for a major in the range, or --to newer than the newest Studio Pro row of its
major: the brain table is older than the target, T1-8, T2-19, T7-6): the file is written and lists it, never silently
empty. Exit (--check): 0 = every row handled, 1 = rows open, 2 = input error.
Read only on the brain: it never writes there.
"""
import argparse, json, os, re, sys
from pathlib import Path

DEFAULT_TYPES = ["breaking", "removal", "requirement", "deprecation"]
# Module rows also carry migration-step by default (QW-1): "Replace snippet X with Y" is the publisher telling the app
# what to rewrite, and a default that dropped it let 24 such rows of WorkflowCommons 4.0.0 go unflagged. Studio Pro
# tables have no such type, so only the module default grows. --types narrows both.
MODULE_DEFAULT_TYPES = DEFAULT_TYPES + ["migration-step"]
# FM-7: "not relevant: (deployed app) reason" (text may start with a bracket after the colon) and "not relevant for the
# deployed app: reason" (up to 60 characters between the verdict and the colon) are accepted.
HANDLED = re.compile(r"^(handled|not relevant)(?:\s+for\s+[^:()]{1,60}?)?\s*(?::\s*[^\s\-\u2013\u2014]|(?:\(|-|\u2013|\u2014)\s*[^\s()\-\u2013\u2014])", re.I)
AUTO = re.compile(r"^(not relevant|handled) \(auto\):", re.I)
# Closure rule (QJ-2, steps/triage.md step 10). A removed setting or a flipped default changes behaviour exactly where
# the setting was NOT set: the app ran with the old default. So on such a row a "not relevant" that rests only on the
# setting being absent is unsound and the row stays open. Sound: the source version already had the new default (cite
# it), or a scan or journey showing the behaviour is not used. b5-forms row 230 (Objects.SetSystemAttributesOnChange).
FLIP_ROW = re.compile(r"\b(setting|option|parameters?)\b.*\b(remov\w*|default|no longer|now|always|only|mandatory|strict)\b|"
                      r"\b(remov\w*|default|no longer)\b.*\b(setting|option|parameters?)\b", re.I)
ABSENCE = re.compile(r"\b(never|not|is not|isn't) set\b|\bunset\b|no custom (runtime )?settings?|0 custom runtime settings|"
                     r"CustomSettings \[\]|setting (is )?absent|not configured|already (ran|runs|used|uses) (with )?the default|"
                     r"sets none of them|no (custom )?runtime setting|not set in the model|has no JVM params", re.I)
SOUND = re.compile(r"source version already|already (had|has) the new default|new default (since|from|in) \d+\.\d+|"
                   r"\b0 hits\b|\bgrep\b|replacement_check|\bR\d{1,2}\b|journey|\bscan|"
                   r"\bno [\w.$#()/-]+ (call|use|usage|read|reads)?\s*(in|anywhere in) (the )?(model|javasource|app|own)|"
                   r"\bno (microflow|nanoflow|page|document|java action|javascript action)s? (calls?|uses?|reads?)\b|"
                   r"\bDESCRIBE of (all|every)\b|[\w)]: 0\b", re.I)


# NR1-22: "not scanned", "never grepped", "no scan" are the opposite of evidence: cut them out before SOUND looks.
NEGATED_EVIDENCE = re.compile(r"\b(?:not|never|no|without|didn't|did not|wasn't|was not)\s+(?:been\s+|yet\s+)?"
                              r"(?:scan\w*|grep\w*|journey\w*|replacement_check)\b|\b(?:scan|grep|journey)\w*\s+"
                              r"(?:not (?:run|done|made)|skipped|missing|pending)\b", re.I)


def unsound_closure(change, entry):
    """True when a not-relevant entry on a removed-setting / flipped-default row rests only on the setting's absence."""
    return bool(re.match(r"^not relevant", entry, re.I) and FLIP_ROW.search(change or "")
                and ABSENCE.search(entry) and not SOUND.search(NEGATED_EVIDENCE.sub("", entry)))


def vt(s):
    m = re.match(r"^\s*v?(\d+(?:\.\d+)*)", str(s))
    return tuple(int(x) for x in m.group(1).split(".")) if m else None


def cmpv(a, b):
    """Compare version tuples on their common length plus zero padding (10.24.16 == 10.24.16.0)."""
    n = max(len(a), len(b))
    a, b = a + (0,) * (n - len(a)), b + (0,) * (n - len(b))
    return (a > b) - (a < b)


def in_range(v, lo, hi):
    return v is not None and cmpv(v, lo) > 0 and cmpv(v, hi) <= 0


def cells(line):
    s = line.strip()
    if not (s.startswith("|") and s.endswith("|")):
        return None
    # split only on an UNESCAPED pipe: esc() writes a pipe inside an entry as \|, and a human closing a row writes it the
    # same way; the cell comes back with the pipe unescaped
    return [c.strip().replace("\\|", "|") for c in re.split(r"(?<!\\)\|", s[1:-1])]


def tables(text):
    """Every markdown table as (header cells, row cells list)."""
    out, head, rows = [], None, []
    for line in text.splitlines():
        c = cells(line)
        if c is None:
            if head:
                out.append((head, rows))
            head, rows = None, []
            continue
        if head is None:
            head = [x.lower() for x in c]
        elif all(re.match(r"^:?-{2,}:?$", x) for x in c if x):
            continue
        else:
            rows.append(c)
    if head:
        out.append((head, rows))
    return out


def squash(s):
    return re.sub(r"[^a-z0-9]", "", s.lower())


def slugify(name):
    s = re.sub(r"(?<=[a-z0-9])(?=[A-Z])", "-", name.replace("_", "-"))
    s = re.sub(r"(?<=[A-Z])(?=[A-Z][a-z])", "-", s)
    return re.sub(r"-+", "-", s).lower().strip("-")


class Brain:
    def __init__(self, root):
        self.v = Path(root) / "baseline" / "versions"
        self.mods = {}
        for f in sorted((self.v / "modules").glob("*.md")):
            first = f.read_text(errors="replace").split("\n", 1)[0]
            m = re.match(r"^#\s*(.*?)\s*\(Marketplace component (\d+)\)", first)
            title, cid = (m.group(1), m.group(2)) if m else (first.lstrip("# ").strip(), None)
            self.mods[f.stem] = {"title": title, "cid": cid, "path": f}

    def find(self, name, cid=None, slug=None):
        """(slug, how) or (None, why)."""
        if slug:
            return (slug, "given") if slug in self.mods else (None, f"no brain file modules/{slug}.md")
        if cid:
            hit = [s for s, m in self.mods.items() if m["cid"] == str(cid)]
            if len(hit) == 1:
                return hit[0], f"content id {cid}"
        sl = slugify(name)
        if sl in self.mods:
            return sl, "name"
        q = squash(name)
        tries = [q, q + "module", "mendix" + q, re.sub(r"\d+$", "", q), re.sub(r"module$", "", q)]
        for t in [t for t in dict.fromkeys(tries) if t]:
            hit = sorted({s for s, m in self.mods.items() if t in (squash(s), squash(m["title"]))})
            if len(hit) == 1:
                return hit[0], f"name ({t})"
            if len(hit) > 1:
                return None, f"several brain files match {name}: {', '.join(hit)} (give the slug on the plan line)"
        return None, f"no brain file for {name}" + (f" (content id {cid})" if cid else "")

    def studio(self, lo, hi, types):
        rows, missing = [], []
        for major in range(lo[0], hi[0] + 1):
            f = self.v / f"studio-pro-upgrade-{major}.md"
            if not f.exists():
                missing.append(f"no Studio Pro table for Mendix {major} ({f})")
                continue
            newest = None
            for head, body in tables(f.read_text(errors="replace")):
                if "version" not in head or "change" not in head:
                    continue
                ix = {h: i for i, h in enumerate(head)}
                for r in body:
                    get = lambda k: r[ix[k]] if k in ix and ix[k] < len(r) else ""
                    v = vt(get("version"))
                    if v and v[0] == major and (newest is None or cmpv(v, newest) > 0):
                        newest = v
                    if get("type").lower() in types and in_range(vt(get("version")), lo, hi):
                        rows.append({"version": get("version"), "type": get("type").lower(), "area": get("area"),
                                     "change": get("change"), "affected": get("affected"), "source": get("source")})
            # T1-8, T2-19, T7-6: a table older than the target lists nothing for the newest versions, silently.
            # Compared on major.minor.patch: 10.24.25.12345 is in a table whose newest row is 10.24.25.
            if major == hi[0] and newest and cmpv(hi[:3], newest[:3]) > 0:
                missing.append(f"rows for {'.'.join(map(str, hi))} not in brain (newest {'.'.join(map(str, newest))}): "
                               f"read the release notes of {hi[0]}.{hi[1] if len(hi) > 1 else 0}.x versions above "
                               f"{'.'.join(map(str, newest))} on docs.mendix.com/releasenotes/studio-pro/ and write what you "
                               "found in this row (a version that only improves or fixes has no row of these types, so the "
                               "table's newest row can lag the newest release by design); the brain's version table needs a "
                               "data refresh by whoever owns the brain, this tool never writes it (T2F-1)")
        rows.sort(key=lambda r: vt(r["version"]))
        return rows, missing

    def module(self, slug, lo, hi, types):
        m = self.mods[slug]
        text = m["path"].read_text(errors="replace")
        link = re.search(r"\[marketplace\]\((\S+?)\)", text)
        src = f"[brain](modules/{slug}.md)" + (f", [marketplace]({link.group(1)})" if link else "")
        rows = []
        for head, body in tables(text):
            if "version" not in head or "change" not in head:
                continue
            ix = {h: i for i, h in enumerate(head)}
            for r in body:
                get = lambda k: r[ix[k]] if k in ix and ix[k] < len(r) else ""
                if get("type").lower() in types and in_range(vt(get("version")), lo, hi):
                    rows.append({"version": get("version"), "type": get("type").lower(), "change": get("change"),
                                 "affected": get("affected"), "replaced": get("replaced by"), "source": src})
        rows.sort(key=lambda r: vt(r["version"]))
        return rows


def read_plan(p):
    out = []
    for n, line in enumerate(open(p), 1):
        s = line.split("#", 1)[0].strip()
        if not s:
            continue
        m = re.match(r"^(\S+)\s+(\S+?)\s*->\s*(\S+)((?:\s+\S+){0,2})$", s)
        if m:
            extra = m.group(4).split()
            cid = next((x for x in extra if x.isdigit()), None)  # T1-9, T8-6: the content id survives a rename
            slug = next((x for x in extra if not x.isdigit()), None)
            out.append({"module": m.group(1), "old": m.group(2), "new": m.group(3), "slug": slug, "cid": cid, "line": n})
            continue
        f = s.split()
        if len(f) >= 3 and f[0].isdigit():
            out.append({"module": f[2], "old": f[3] if len(f) > 3 else None, "new": f[1], "slug": None, "cid": f[0], "line": n})
            continue
        out.append({"module": s, "old": None, "new": None, "slug": None, "cid": None, "line": n, "bad": True})
    return out


def mpr_plan(old_path, new_path):
    """(plan entries for updated modules, status table rows) from the installed Marketplace modules of two projects."""
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import mprmodel  # needs bson (pip install pymongo); only loaded for --from-mpr/--to-mpr

    def mods(p):
        return {n: i for n, i in mprmodel.Model.load(p).modules.items() if n and i.get("version")}
    old, new = mods(old_path), mods(new_path)
    # T6R-4: a module updated by mxcli/stepupdate carries no AppStorePackageId in the new project (T6R: 12 of 13 updated
    # modules, so AWSAuthentication and AnyChart_BuildingBlocks became "no brain file"); the old project's id is the same
    # component, so a pair by name takes it from there.
    by_cid = {str(i["package_id"]): n for n, i in old.items() if i.get("package_id")}
    plan, status, used = [], [], set()
    for name in sorted(new):
        ni = new[name]
        cid = str(ni["package_id"]) if ni.get("package_id") else None
        oname = by_cid.get(cid) if cid else None
        if oname is None and name in old:
            oname = name
            if not cid and old[name].get("package_id"):
                cid = str(old[name]["package_id"])
        label = name if oname in (None, name) else f"{name} (was {oname})"
        if oname is None:
            status.append((label, cid or "", "", ni["version"], "new: installed, no jump (read its notes for this version)"))
            continue
        used.add(oname)
        ov = old[oname]["version"]
        if vt(ov) and vt(ni["version"]) and cmpv(vt(ov), vt(ni["version"])) == 0:
            status.append((label, cid or "", ov, ni["version"], "kept: same version, no rows"))
            continue
        status.append((label, cid or "", ov, ni["version"], "updated: rows below"))
        plan.append({"module": name, "old": ov, "new": ni["version"], "slug": None, "cid": cid, "line": "project"})
    for oname in sorted(set(old) - used):
        if oname not in new:
            status.append((oname, str(old[oname].get("package_id") or ""), old[oname]["version"], "", "removed"))
    return plan, status


FACT_KEYS = {"db_vendor", "db_version", "odata_published", "odata_consumed", "odata_consumed_connector", "rest_published", "rest_consumed",
             "web_services", "workflows", "own_java", "native_profile", "oql", "document_templates", "kept", "stranded",
             "runtime_os", "languages", "own_jdbc", "dev_servlet", "database_connector", "project_dir", "vcs"}


def load_facts(paths):
    """{key: (value, source file)}. A test_inventory.py --json is read for what it knows; a hand file gives any key."""
    facts = {}
    for p in paths or []:
        try:
            d = json.load(open(p))
        except (OSError, ValueError) as e:
            sys.exit(f"release_impact: cannot read facts {p}: {e}")
        src = Path(p).name
        if "test_plan" in d or "published_rest" in d:
            def n(k):
                v = d.get(k)
                return None if not isinstance(v, list) or any("_error" in x for x in v if isinstance(x, dict)) else len(v)
            got = {"odata_published": n("odata_published"), "odata_consumed": n("odata_consumed"),
                   "odata_consumed_connector": n("odata_consumed_connector"),
                   "rest_published": n("published_rest"), "rest_consumed": n("consumed_rest"), "workflows": n("workflows")}
            # T8R-11 (RI-1): REST call activities are consumed REST too (MendixSSO: 0 clients, 4 call activities). The
            # count also holds web service and external calls: a false hit keeps rows open. No count: unknown.
            ca = d.get("rest_call_activities")
            calls = (ca[0].get("n") if isinstance(ca, list) and len(ca) == 1 and isinstance(ca[0], dict) else None)
            got["rest_consumed"] = got["rest_consumed"] + calls if got["rest_consumed"] is not None and isinstance(calls, int) else None
            own = set((d.get("modules") or {}).get("own") or [])
            ja = d.get("java_actions")
            if isinstance(ja, list) and not any("_error" in x for x in ja):
                got["own_java"] = sum(x.get("n", 0) for x in ja if x.get("module") in own)
            for k, v in got.items():
                if v is not None:
                    facts[k] = (v, src)
            continue
        if isinstance(d.get("db"), dict):
            d.setdefault("db_vendor", d["db"].get("vendor"))
            d.setdefault("db_version", d["db"].get("version"))
        for k, v in d.items():
            if k in ("db", "source", "notes", "_comment") or k.startswith("_"):
                continue
            if k not in FACT_KEYS:
                print(f"release_impact: unknown fact {k} in {p} ignored (known: {', '.join(sorted(FACT_KEYS))})", file=sys.stderr)
                continue
            if v is not None:
                facts[k] = (v, src)
    return facts


VENDORS = {"postgresql": r"postgre(?:s|sql)", "mariadb": r"maria\s*db", "mysql": r"\bmysql\b",
           "sqlserver": r"sql\s*server|\bmssql\b|azure sql", "oracle": r"\boracle\b", "db2": r"\bdb2\b",
           "hana": r"\bhana\b", "hsqldb": r"\bhsql(?:db)?\b"}
# a version range ("12 or higher", "versions below 17", "13+") may include yours: such a row stays open
RANGE_WORDS = re.compile(r"\b(?:above|higher|later|newer|below|earlier|older|lower|prior|before|after|minimum|maximum|"
                         r"least|less|greater|up to|through|until|since|from)\b|\d\s*\+|\bto \d|[<>]", re.I)
# feature -> (row text regex, fact keys whose values must ALL be zero/false for "absent")
FEATURES = [
    ("published OData", r"\bodata\b(?=.*\bpublish)|\bpublish\w*\b.*\bodata\b", ("odata_published",)),
    ("consumed OData", r"\bodata\b(?=.*\bconsum)|\bconsum\w*\b.*\bodata\b|external entit", ("odata_consumed", "odata_consumed_connector")),
    ("OData", r"\bodata\b", ("odata_published", "odata_consumed", "odata_consumed_connector")),
    ("published REST", r"(?-i:\bREST\b)(?=.*\bpublish)|\bpublish\w*\b.*(?-i:\bREST\b)", ("rest_published",)),
    ("consumed REST", r"(?-i:\bREST\b)(?=.*\b(?:consum|call))|\b(?:consum|call)\w*\b.*(?-i:\bREST\b)", ("rest_consumed",)),
    ("REST", r"(?-i:\bREST\b)", ("rest_published", "rest_consumed")),
    ("web services", r"web ?services?\b|\bsoap\b|\bwsdl\b", ("web_services",)),
    ("native", r"react[- ]native|\bnative[- ](?:mobile|apps?|widgets?|navigation|profiles?|pages?|layouts?|builder|"
               r"actions?|template|client|platform)\b", ("native_profile",)),
    ("workflows", r"\bworkflows?\b|\buser tasks?\b", ("workflows",)),
    ("OQL", r"\boql\b", ("oql",)),
    ("document templates", r"document templates?|document generation", ("document_templates",)),
]
# A module requirement row that only raises the module's minimum Mendix version (T3, T4 rule scripts): met when the
# target is at least that version, version arithmetic only. A minimum ABOVE the target stays open (a real blocker).
MIN_MENDIX = re.compile(r"^(?:(?:upgraded|updated)\s+(?:the\s+)?(?:[\w ]+?\s+)?(?:module\s+)?to\s+(?:mendix\s+)?(?:version\s+)?|"
                        r"(?:updated\s+)?(?:[\w ]+?\s+)?minimum\s+(?:mendix\s+|studio pro\s+)?version\s+to\s+"
                        r"(?:studio pro\s+|mendix\s+)?|mendix runtime upgraded to\s+)(\d+\.\d+(?:\.\d+)?)"
                        r"(?:\s+(?:for|to support)\s+(?:compatibility with\s+)?mendix\s+\d+(?:\s+support)?)?\s*\.?$", re.I)
# NR1-2: more phrasings of the same requirement ("Minimal required version of Studio Pro is v9.12.0", "Minimum Mendix
# version set to 9.24.1", "Module upgraded to require Mendix 10.24.0 minimum", "Requires Mendix 10.24.0 or higher").
MIN_MENDIX_MORE = (
    re.compile(r"^(?:the\s+)?minim(?:um|al)\s+(?:required\s+)?(?:(?:mendix|studio pro)\s+)?(?:version\s+)?"
               r"(?:of\s+(?:mendix|studio pro)\s+)?(?:is|set to|raised to|updated to|changed to|now)?\s*v?"
               r"(\d+\.\d+(?:\.\d+)?)\s*\.?$", re.I),
    re.compile(r"^(?:the\s+)?(?:module\s+)?(?:(?:upgraded|updated)\s+to\s+)?requires?\s+(?:at least\s+)?(?:mendix|studio pro)\s+v?"
               r"(\d+\.\d+(?:\.\d+)?)\s*(?:minimum|or (?:higher|newer|above|later))?\s*\.?$", re.I),
)


def min_mendix_match(change):
    """The match (group 1 = the version) when the change only states a minimum Mendix version, else None."""
    change = change.strip()
    for rx in (MIN_MENDIX,) + MIN_MENDIX_MORE:
        m = rx.match(change)
        if m:
            return m
    return None


EXACT_UPGRADED = re.compile(r"^upgraded (?:the module )?to \d+\.\d+(?:\.\d+)?\.?$", re.I)
# external-entities is not mapped: the area also holds the External Database Connector, which is not OData.
AREA_FEATURE = {"workflow": "workflows", "native-mobile": "native"}
# studio-pro-ide rows that still reach the app: the model (pages, widgets, URLs, placeholders, mpr format), its
# consistency checks, Java and the runtime. Those stay open, and so does every breaking or removal row of the area
# (real 10.x rows: "No longer supports old {Id} format in page URLs", "Curly braces in placeholder text must now be
# escaped", "Removed deprecated reporting category widgets").
IDE_REACHES_APP = re.compile(r"\b(?:pages?|widgets?|urls?|placeholders?|consisten\w*|errors?|mpr\w*|models?|projects?|"
                             r"app settings|convert\w*|java|jdk|runtime|deploy\w*|build\w*|microflows?|nanoflows?|"
                             r"entit\w*|domain|languages?|locales?|calendars?|[a-z]{2}_[a-z]{2})\b", re.I)
# N1-9: rows whose subject one fact decides (each rule cites that fact in the entry; a fact not given leaves the row open)
LANG_CODE = re.compile(r"\b([a-z]{2,3}_[A-Z]{2})\b")
DOTNET = re.compile(r"\.NET\b")
DEV_SERVLET = re.compile(r"addDevelopmentServlet", re.I)
JDBC = re.compile(r"\bjdbc\b", re.I)
# "From July 6, 2026", "after November 1, 2023": a date is no version range
DATE_PHRASE = re.compile(r"\b(?:from|after|since|before|until|by|on)\s+(?:(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?\s+\d{1,2}(?:st|nd|rd|th)?,?\s+\d{4}|\d{1,2}\s+(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?,?\s+\d{4}|\d{4}-\d{2}-\d{2})", re.I)

# type names that exist in EVERY model (captured from a real 11.x project, a customer 11.x app): the
# project settings part for workflows and the native layout slot of an Atlas layout say nothing about use.
ALWAYS_PRESENT_TYPES = {"Settings$WorkflowsProjectSettingsPart", "Forms$NativeLayoutContent"}
# fact -> regex on the $Type values found anywhere in the model. Broad on purpose: a false hit leaves rows open, a miss
# would close a row of a feature the app uses, so absent means NO type of that family occurs in the whole model.
TYPE_FAMILIES = {
    "workflows": re.compile(r"workflow", re.I),
    "web_services": re.compile(r"webservice", re.I),
    "document_templates": re.compile(r"documenttemplate", re.I),
    "oql": re.compile(r"oql|dataset|viewentity", re.I),
}
JAVA_SQL = re.compile(r"\bjava\.sql\b|\bjavax\.sql\b|\bDriverManager\b|\bjdbc:", re.I)
# T6R-5: areas of the developer's tools, not of the app. git-teamserver is version control between Studio Pro and the
# Team Server; mxbuild-cli rows of type requirement/deprecation are about the build host (Gradle, arm64, the dotnet of
# the command line tools), which the target build provides or fails on loudly. Their breaking and removal rows stay
# open (real 10.x rows: "Removed Build Using Gradle option", "Retracted mx.exe git-merge": a pipeline may use them).
TOOL_AREAS = ("git-teamserver", "mxbuild-cli")
SVN = re.compile(r"\bSVN\b|\bsubversion\b", re.I)
# T6R-5: a Marketplace module's requirement row that only bumps a Java library it ships ("Nimbus oauth2-oidc-sdk
# library upgraded to version 11.28"). The library is the module's own business unless other Java in javasource
# imports it; jar copies and clashes are jardedupe.py/jarclash.py's (steps/repair.md row 3). Each library the row
# names must be in this map, or the row stays open.
LIB_BUMP = re.compile(r"\b(?:upgraded|updated|upgrade|update|bumped)\b", re.I)
LIB_PKG = [(re.compile(r"nimbus|oauth2-oidc-sdk|nimbus-jose-jwt", re.I), "com.nimbusds"),
           (re.compile(r"json-smart", re.I), "net.minidev"),
           (re.compile(r"\bnetty\b|netty-codec", re.I), "io.netty"),
           (re.compile(r"commons[- ]lang3", re.I), "org.apache.commons.lang3"),
           (re.compile(r"commons[- ]text", re.I), "org.apache.commons.text"),
           (re.compile(r"commons[- ]io\b", re.I), "org.apache.commons.io"),
           (re.compile(r"commons[- ]codec", re.I), "org.apache.commons.codec"),
           (re.compile(r"bouncy ?castle", re.I), "org.bouncycastle"),
           (re.compile(r"httpcomponents\.client5|httpclient5|http-client-version", re.I), "org.apache.hc"),
           (re.compile(r"\bjackson\b", re.I), "com.fasterxml.jackson"),
           (re.compile(r"\bguava\b", re.I), "com.google.common")]
# T6R-5: one item of a java-actions row's `affected` that names Java code: a class, Class.method(), Class#method or a
# dotted package path. Prose ("Mendix Runtime API") is no symbol: a row with one such item stays open.
JAVA_SYM = re.compile(r"[A-Za-z_][\w$]*(?:[.#][A-Za-z_][\w$]*)*(?:\(\))?")


def java_symbols(affected):
    """[(item, search key)] or None when an item is no Java symbol. The key is the last name (method or class)."""
    items = [x.strip() for x in re.split(r",(?![^(]*\))", affected or "") if x.strip()]
    out = []
    for it in items:
        if not JAVA_SYM.fullmatch(it):
            return None
        last = re.split(r"[.#]", it.replace("()", ""))[-1]
        # a plain lower-case word ("jdk") or a single capitalised English word without a second capital is no symbol
        # ("Node.js": "js" is no class), so a dotted item needs a capitalised last name
        if not (re.search(r"[a-z][A-Z]|^[A-Z]{2,}[a-z]", last) or it.endswith("()") or "#" in it
                or ("." in it and last[:1].isupper())):
            return None
        out.append((it, last))
    return out or None


JAVA_REV = {"rev": None}   # PV-4: --java-rev; None = look for the run's "original:" commit


def java_rev(project_dir):
    """The commit whose Java the removal rows are judged on: --java-rev, else the newest commit whose subject starts with
    "original:" (the run start; the toolkit's run branches begin with one). None: not a git project, or no such commit,
    and the rows are judged on the tree as it is (the old behaviour)."""
    import subprocess
    if JAVA_REV["rev"]:
        return JAVA_REV["rev"]
    r = subprocess.run(["git", "-C", str(project_dir), "log", "-1", "--format=%H", "--extended-regexp", "--grep=^original:"],
                       capture_output=True, text=True)
    return r.stdout.strip() or None if r.returncode == 0 else None


def last_change(project_dir, key, rev):
    """'<short hash> <subject>' of the newest commit after rev that touched javasource and names key, or ''."""
    import subprocess
    r = subprocess.run(["git", "-C", str(project_dir), "log", "-1", "--format=%h %s", "-S", key, f"{rev}..HEAD", "--", "javasource"],
                       capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else ""


class JavaIndex:
    """T6R-5: the Java a project compiles and loads: javasource/**/*.java without generated proxies (the target build
    regenerates them) and the class files in userlib/*.jar. Read once per project folder."""
    _cache = {}

    @classmethod
    def of(cls, root, rev=None):
        key = (str(root), rev)
        if key not in cls._cache:
            cls._cache[key] = cls(str(root), rev)
        return cls._cache[key]

    def __init__(self, root, rev=None):
        import zipfile
        self.rev = rev
        if rev:  # PV-4: the tree as it was at rev (git archive of javasource and userlib into a temp folder)
            import subprocess, tarfile, tempfile, atexit, shutil, io
            tmp = tempfile.mkdtemp(prefix="relimpact-rev-")
            atexit.register(shutil.rmtree, tmp, True)
            pre = subprocess.run(["git", "-C", root, "rev-parse", "--show-prefix"], capture_output=True, text=True).stdout.strip()
            r = subprocess.run(["git", "-C", root, "archive", f"{rev}:{pre}" if pre else rev, "javasource", "userlib"],
                               capture_output=True)
            if r.returncode != 0:   # no userlib at that commit is fine: retry with javasource alone
                r = subprocess.run(["git", "-C", root, "archive", f"{rev}:{pre}" if pre else rev, "javasource"], capture_output=True)
            if r.returncode == 0:
                with tarfile.open(fileobj=io.BytesIO(r.stdout)) as t:
                    t.extractall(tmp)
            root = tmp
        self.root, self.ok, self.java, self.jars, self.bad = Path(root), False, {}, {}, []
        js = self.root / "javasource"
        if not js.is_dir():
            return
        for f in js.rglob("*.java"):
            rel = f.relative_to(js)
            if "proxies" in rel.parts:
                continue
            self.java[rel.as_posix()] = f.read_text(errors="replace")
        for j in sorted((self.root / "userlib").glob("*.jar")):
            try:
                with zipfile.ZipFile(j) as z:
                    self.jars[j.name] = b"\n".join(z.read(n) for n in z.namelist() if n.endswith(".class"))
            except (zipfile.BadZipFile, OSError) as e:
                self.bad.append(f"{j.name}: {e}")
        self.ok = not self.bad

    def where(self, key, skip_module=None):
        """files and jars that hold key (whole word in .java, bytes in class files); skip_module drops javasource/<m>/."""
        rx = re.compile(r"(?<![\w$])" + re.escape(key) + r"(?![\w$])")
        hits = [p for p, t in self.java.items() if not (skip_module and p.split("/")[0] == skip_module) and rx.search(t)]
        hits += [n for n, b in self.jars.items() if key.encode() in b]
        return hits

    def scope(self):
        return f"{self.root}/javasource ({len(self.java)} .java, proxies excluded), {self.root}/userlib ({len(self.jars)} jars)"


# T8R-11 (RI-1): a REST call activity is consumed REST even with no consumed REST document (MendixSSO: 0 clients, 4 calls)
REST_CALL_ACTIONS = ("Microflows$RestCallAction", "Microflows$SendRestRequestAction")
# T2R3-3, N1R2-5: browser profiles. Atlas_Core ships BuildingBlocks and layouts with Platform Native in every app, and a
# Phone profile is a browser profile: neither is native use. Only the navigation profiles say whether the app has one.
WEB_PROFILE_KINDS = {"responsive", "tablet", "phone"}


def native_profile(m, facts, notes):
    """native_profile from the navigation document's profiles (T2R3-3, N1R2-5): true for a Navigation$NativeNavigationProfile
    or a profile Kind naming native, hybrid or offline (broad on purpose: a false hit leaves native rows open); false only
    when every profile is a known browser profile (Responsive, Tablet, Phone). No navigation document, or a profile of
    another type or kind, is unknown: the fact stays out and native rows stay open."""
    profs = []

    def find(x):  # every profile object of the navigation document, wherever its list sits
        if isinstance(x, dict):
            t = str(x.get("$Type", ""))
            if t.startswith("Navigation$") and "Profile" in t:
                profs.append(x)
                return
            for v in x.values():
                find(v)
        elif isinstance(x, list):
            for v in x:
                find(v)
    find(m.singletons.get("Navigation$NavigationDocument") or {})
    if not profs:
        notes.append("native_profile: no navigation profile in the model: native rows stay open")
        return
    seen, other = [], []
    for p in profs:
        t, kind = str(p.get("$Type", "")), str(p.get("Kind") or "")
        label = f"{p.get('Name') or '?'} ({t.split('$')[-1]}{' ' + kind if kind else ''})"
        if "native" in t.lower() or re.search(r"native|hybrid|offline", kind, re.I):
            facts["native_profile"] = True
            print(f"release_impact: native_profile: navigation profile {label}", file=sys.stderr)
            return
        if t == "Navigation$NavigationProfile" and kind.lower() in WEB_PROFILE_KINDS:
            seen.append(label)
        else:
            other.append(label)
    if other:
        notes.append(f"native_profile: navigation profile of unknown kind: {', '.join(other)}: native rows stay open")
        return
    facts["native_profile"] = False


def facts_from_project(mpr, db_vendor=None, db_version=None, runtime_os=None):
    """(facts, unknown notes) counted from the model and javasource next to it (T2F-2, N1-9). Facts that no file can
    answer stay out and are listed as notes: db_vendor/db_version (the model's dev configuration is HSQLDB, no
    deployment database) and runtime_os come from the flags, never from a guess."""
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import mprmodel  # needs bson (pip install pymongo)
    mpr = Path(mpr)
    m = mprmodel.Model.load(str(mpr))
    types, per_unit = {}, []  # per_unit: (unit $Type, {$Type: n} inside that unit)

    def walk(x, acc):
        if isinstance(x, dict):
            t = x.get("$Type")
            if isinstance(t, str):
                acc[t] = acc.get(t, 0) + 1
            for v in x.values():
                walk(v, acc)
        elif isinstance(x, list):
            for v in x:
                walk(v, acc)
    for _, (_, _, d) in m.units.items():
        acc = {}
        walk(d, acc)
        per_unit.append((d.get("$Type"), acc))
        for t, n in acc.items():
            types[t] = types.get(t, 0) + n
    live = {t: n for t, n in types.items() if t not in ALWAYS_PRESENT_TYPES}
    facts, notes = {}, []

    def count(rx, exclude=None):
        return sum(n for t, n in live.items() if rx.search(t) and not (exclude and exclude.search(t)))

    def services(key, family, pick, actions=()):
        """T2R3-3, T8R-11: the documents of a family (units whose own $Type is picked) plus the call actions named,
        not every element type: 79 OData element types were 1 consumed service. A picked element type in a unit that
        is no document of the family (published or consumed), while no document or action is found, is unknown: the
        fact stays out and its rows stay open."""
        docs = sum(1 for top, _ in per_unit if top and pick(top))
        calls = sum(n for t, n in live.items() if t in actions)
        stray = sorted({t for top, acc in per_unit if not (top and family.search(top)) for t in acc
                        if t in live and pick(t) and t not in actions})
        if docs + calls == 0 and stray:
            notes.append(f"{key}: no {key.replace('_', ' ')} document{' or call action' if actions else ''}, but "
                         f"{', '.join(stray[:4])}{' ...' if len(stray) > 4 else ''} in other units: its rows stay open")
            return
        facts[key] = docs + calls
    odata = re.compile(r"odata", re.I)
    services("odata_published", odata, lambda t: bool(odata.search(t) and re.search(r"publish", t, re.I)))
    services("odata_consumed", odata, lambda t: bool(odata.search(t) and not re.search(r"publish", t, re.I)))
    # T3F-11: OData consumed through a Marketplace connector module has no OData document type at all
    import odataconn
    conn = odataconn.count_model_refs(m)
    facts["odata_consumed_connector"] = sum(conn.values())
    if conn:
        notes_conn = ", ".join(f"{k} {v}" for k, v in sorted(conn.items()))
        print(f"release_impact: odata_consumed_connector: references into {notes_conn}: consumed OData rows stay open", file=sys.stderr)
    # "SendRestRequestAction" (the 10.x consumed REST service's action) has "Rest" after a lowercase letter
    rest = re.compile(r"(?<![A-Za-z])Rest(?![a-z])|SendRest")
    services("rest_published", rest, lambda t: bool(rest.search(t) and not odata.search(t) and "Publish" in t))
    services("rest_consumed", rest, lambda t: bool(rest.search(t) and not odata.search(t) and "Publish" not in t),
             REST_CALL_ACTIONS)
    for k, rx in TYPE_FAMILIES.items():
        facts[k] = count(rx)
    native_profile(m, facts, notes)
    ls = [i.get("Code") for part in (m.singletons.get("Settings$ProjectSettings") or {}).get("Settings", [])
          if isinstance(part, dict) and part.get("$Type") == "Settings$LanguageSettings"
          for i in part.get("Languages", []) if isinstance(i, dict)]
    if ls:
        facts["languages"] = ls
    else:
        notes.append("languages: no Settings$LanguageSettings in the model")
    own = sorted(n for n, i in m.modules.items() if n and not i.get("from_appstore"))
    facts["database_connector"] = sum(1 for n in m.modules if n and re.sub(r"[^a-z]", "", n.lower()) == "databaseconnector")
    js = mpr.resolve().parent / "javasource"
    if js.is_dir():
        files = [f for f in js.rglob("*.java") if "proxies" not in f.relative_to(js).parts]
        mine = {n.lower() for n in own}
        own_files = [f for f in files if f.relative_to(js).parts[0].lower() in mine]
        facts["own_java"] = len(own_files)
        facts["own_jdbc"] = sum(1 for f in own_files if JAVA_SQL.search(f.read_text(errors="replace")))
        facts["dev_servlet"] = sum(1 for f in files if DEV_SERVLET.search(f.read_text(errors="replace")))
        # T6R-5: the folder the java-actions and module-library rules grep at run time (they cite what they read)
        facts["project_dir"] = str(js.parent)
    else:
        notes.append(f"own_java, own_jdbc, dev_servlet: no javasource folder next to {mpr.name}")
    # T6R-5: the project's version control, from the nearest .git/.svn folder above the mpr (none found: unknown)
    for d in [mpr.resolve().parent, *mpr.resolve().parent.parents]:
        got = [k for k in ("git", "svn") if (d / f".{k}").exists()]
        if got:
            facts["vcs"] = got[0] if len(got) == 1 else "+".join(got)
            break
    if db_vendor:
        facts["db_vendor"] = db_vendor
    else:
        notes.append("db_vendor: pass --db-vendor <postgresql|mariadb|mysql|sqlserver|oracle|...> (the database the app "
                     "RUNS on; the model's dev configuration is not it): database rows stay open")
    if db_version:
        facts["db_version"] = str(db_version)
    else:
        notes.append("db_version: pass --db-version <major> to also close rows about other versions of your vendor")
    if runtime_os:
        facts["runtime_os"] = runtime_os
    else:
        notes.append("runtime_os: pass --runtime-os linux when the app runs on Linux or in a container: the "
                     ".NET Studio Pro host rows stay open")
    return facts, notes


def fact_str(facts, k):
    v, src = facts[k]
    return f"{k}={json.dumps(v) if not isinstance(v, str) else v} ({src})"


def module_library_rule(mod, typ, change, affected, facts):
    """T6R-5: 'not relevant (auto): module-library-bump: ...' for a module requirement row that only bumps Java
    libraries the module ships, when no Java outside javasource/<module>/ imports them; else None. Every part of the
    row that names a version must name a library of LIB_PKG ("... 10.7.1 including json-smart 2.4.10": both)."""
    if typ != "requirement" or "project_dir" not in facts or not LIB_BUMP.search(change):
        return None
    parts = [p for p in re.split(r"\band\b|,|;|\bincluding\b|\bplus\b", change) if re.search(r"\d+\.\d+", p)]
    if not parts:
        return None
    pkgs = []
    for p in parts:
        got = [pkg for rx, pkg in LIB_PKG if rx.search(p)]
        if not got:
            return None  # a library this rule cannot name: a person reads it
        pkgs += [g for g in got if g not in pkgs]
    ix = JavaIndex.of(facts["project_dir"][0])
    if not (ix.ok and ix.java):
        return None
    own = mod.lower()
    if not any(p.split("/")[0] == own for p in ix.java):
        return None  # the module's Java folder is not where we look for it: its own use cannot be told apart
    users = {pkg: [p for p in ix.where(pkg, skip_module=own) if not p.endswith(".jar")] for pkg in pkgs}
    if any(users.values()):
        return None
    return (f"not relevant (auto): module-library-bump: {', '.join(pkgs)} is used only by javasource/{own}/ "
            f"(0 imports in the other {sum(1 for p in ix.java if p.split('/')[0] != own)} .java files of "
            f"{ix.root}/javasource, proxies excluded); jar copies and clashes: jardedupe.py, jarclash.py "
            f"(steps/repair.md row 3); {fact_str(facts, 'project_dir')}")


def auto_rule(section, cols, facts, lo, hi):
    """'not relevant (auto): <rule>: <fact>' or None. cols as written in the row (Studio Pro or module layout)."""
    if section == "Not covered":
        mod = cols[0]
        for k in ("kept", "stranded"):
            if k in facts and mod in (facts[k][0] or []):
                return f"not relevant (auto): {k}-module: {mod} is {k}, no jump ({k} list, {facts[k][1]})"
        return None
    if section == "Studio Pro":
        version, typ, area, change, affected = cols[0], cols[1], cols[2].lower(), cols[3], cols[4]
    else:
        version, typ, area, change, affected = cols[0], cols[1], "", cols[2], cols[3]
        mod = section[len("Module "):]
        for k in ("kept", "stranded"):
            if k in facts and mod in (facts[k][0] or []):
                return f"not relevant (auto): {k}-module: {mod} is {k}, its rows do not apply ({k} list, {facts[k][1]})"
        m = min_mendix_match(change)
        if typ == "requirement" and m and (re.search(r"\bmendix\b|studio pro", change, re.I) or EXACT_UPGRADED.match(change.strip())):
            need = vt(m.group(1))
            if need and 7 <= need[0] <= 12 and cmpv(need, hi) <= 0:
                return (f"not relevant (auto): min-mendix-met: the module needs Mendix {m.group(1)}, "
                        f"the target is {'.'.join(map(str, hi))}")
        lib = module_library_rule(mod, typ, change, affected, facts)
        if lib:
            return lib
    text = f"{change} {affected}"
    if section == "Studio Pro":
        # N1-9: rows one fact decides. Each cites that fact; a fact not given leaves the row to the rules below or open.
        langs = sorted(set(LANG_CODE.findall(text))) if re.search(r"\b(?:language|locale|culture)", text, re.I) else []
        if langs and "languages" in facts:
            have = {str(x).lower() for x in (facts["languages"][0] or [])}
            if not any(c.lower() in have for c in langs):
                return (f"not relevant (auto): language-code: row is about {', '.join(langs)}; the app's languages "
                        f"do not include them ({fact_str(facts, 'languages')})")
            return None  # the app holds that language: a person decides, not the IDE rule below
        if DEV_SERVLET.search(text) and "dev_servlet" in facts and facts["dev_servlet"][0] in (0, False):
            return ("not relevant (auto): dev-servlet-unused: no call of Core.addDevelopmentServlet in the app's javasource; "
                    f"{fact_str(facts, 'dev_servlet')}")
        if (DOTNET.search(text) and typ in ("requirement", "deprecation") and area in ("runtime", "studio-pro-ide")
                and not IDE_REACHES_APP.search(re.sub(r"\bruntime\b", "", text, flags=re.I))
                and str(facts.get("runtime_os", ("",))[0]).lower() in ("linux", "container")):
            return ("not relevant (auto): dotnet-ide-host: row is about the .NET of the Studio Pro host; the Mendix "
                    f"runtime on Linux is Java, not .NET; {fact_str(facts, 'runtime_os')}")
        if area == "studio-pro-ide" and typ not in ("breaking", "removal") and not IDE_REACHES_APP.search(text):
            return "not relevant (auto): studio-pro-ide: area studio-pro-ide is the desktop IDE, the app is built headless by mxbuild"
        # T6R-5: the developer's tools (TOOL_AREAS). SVN removal: only a project under Git is spared, by the vcs fact.
        svn = area == "git-teamserver" and SVN.search(text)
        if svn and str(facts.get("vcs", ("",))[0]) == "git":
            return f"not relevant (auto): git-teamserver: the row is about SVN; the project is under Git, {fact_str(facts, 'vcs')}"
        if area in TOOL_AREAS and not svn and typ in ("requirement", "deprecation") and not IDE_REACHES_APP.search(text):
            what = ("version control between Studio Pro and the Team Server, not the app" if area == "git-teamserver" else
                    "the build host (the target mxbuild the toolkit builds with brings it, or the build fails)")
            return f"not relevant (auto): {area}: area {area} is {what}"
        # T6R-5: a removed Java API breaks only code that names it. Every `affected` item must be a Java symbol, and
        # none may occur in javasource (proxies excluded: regenerated) or in a userlib jar's class files.
        if area == "java-actions" and typ == "removal" and "project_dir" in facts:
            syms = java_symbols(affected)
            pdir = facts["project_dir"][0]
            rev = java_rev(pdir) if syms else None
            ix = JavaIndex.of(pdir, rev) if syms else None
            if syms and ix.ok and ix.java:
                hit = [k for _, k in syms if ix.where(k)]
                at = f" at {rev[:9]}" if rev else ""
                if not hit:
                    return (f"not relevant (auto): java-symbol-absent: {', '.join(k for _, k in syms)}: 0 hits in "
                            f"{ix.scope()}{at}; {fact_str(facts, 'project_dir')}")
                if rev:
                    # PV-4: present before the port, gone now: the row was real and is handled, not "not relevant"
                    now = JavaIndex.of(pdir)
                    if now.ok and now.java and not any(now.where(k) for k in hit):
                        by = "; ".join(f"{k}: {last_change(pdir, k, rev) or 'commit not found'}" for k in hit)
                        return (f"handled (auto): java-symbol-ported: {', '.join(hit)} occurred in the kept Java at {rev[:9]} "
                                f"(the run start) and is gone now ({by}); {fact_str(facts, 'project_dir')}")
        v = vt(version)
        if v and hi[0] > lo[0] and len(lo) >= 2 and v[:2] == lo[:2]:
            return (f"not relevant (auto): source-line-patch: {version} is a {lo[0]}.{lo[1]}.x patch above the source "
                    f"{'.'.join(map(str, lo))} on a path to {hi[0]}.x; the {hi[0]}.x rows carry the change")
        if area == "data-storage" and "db_vendor" in facts:
            given = str(facts["db_vendor"][0]).lower()
            ours = next((k for k, rx in VENDORS.items() if re.search(rx, given) or re.search(rx, given.replace(" ", ""))), None)
            if ours is None:
                return None  # a vendor no rule can name (azure sql, ...) may be one the row names: no db rule
            named = [k for k, rx in VENDORS.items() if re.search(rx, text, re.I)]
            if named and ours not in named:
                return f"not relevant (auto): other-db-vendor: row is about {', '.join(named)}; {fact_str(facts, 'db_vendor')}"
            # a number after "JDBC driver" is the driver's version, not the database's (42.7 is no PostgreSQL 42)
            if (named and ours in named and "db_version" in facts and not JDBC.search(text)
                    and not RANGE_WORDS.search(DATE_PHRASE.sub(" ", text))):
                mine = str(facts["db_version"][0]).split(".")[0]
                after = re.split(VENDORS[ours], text, maxsplit=1, flags=re.I)[1]
                seg = re.split("|".join(rx for k, rx in VENDORS.items() if k != ours), after, maxsplit=1, flags=re.I)[0]
                nums = {x.split(".")[0] for x in re.findall(r"\b\d+(?:\.\d+)?\b", DATE_PHRASE.sub(" ", seg))}
                if nums and mine not in nums:
                    return (f"not relevant (auto): other-db-version: row is about {ours} {', '.join(sorted(nums, key=int))}; "
                            f"{fact_str(facts, 'db_version')}")
        # N1-9: a driver row of a vendor no rule above closed (yours, or none named) concerns own code only through
        # own Java that opens JDBC connections; a Database Connector row also needs the module absent.
        if JDBC.search(text) and typ in ("requirement", "deprecation") and "own_jdbc" in facts \
                and facts["own_jdbc"][0] in (0, False):
            dbc = re.search(r"database connector", text, re.I)
            if not dbc or ("database_connector" in facts and facts["database_connector"][0] in (0, False)):
                cite = [fact_str(facts, "own_jdbc")] + ([fact_str(facts, "database_connector")] if dbc else [])
                return ("not relevant (auto): jdbc-unused: row is about a JDBC driver; the app's own Java opens no JDBC "
                        f"connection; {', '.join(cite)}")
        # A deprecated Java API still compiles on the target; only own Java is ours to move. Breaking and removal rows
        # stay open even without own Java: Marketplace module Java breaks on them too (T7: TcConnector Logout).
        if area == "java-actions" and typ == "deprecation" and "own_java" in facts and facts["own_java"][0] in (0, False):
            return f"not relevant (auto): java-deprecation: no own Java action; {fact_str(facts, 'own_java')}"
    touched = []
    if area in AREA_FEATURE:
        touched.append(AREA_FEATURE[area])
    for name, rx, _ in FEATURES:
        if re.search(rx, text, re.I) and name not in touched:
            touched.append(name)
    # a specific direction (published / consumed) replaces the general one
    for gen, spec in (("OData", ("published OData", "consumed OData")), ("REST", ("published REST", "consumed REST"))):
        if gen in touched and any(s in touched for s in spec):
            touched.remove(gen)
    if area == "odata-rest" and not touched:
        return None  # an odata-rest row whose subject we cannot name stays open
    if not touched:
        return None
    keys = {name: ks for name, _, ks in FEATURES}
    cite = []
    for name in touched:
        for k in keys[name]:
            if k not in facts or facts[k][0] not in (0, False, "0", "false", "no", [], None):
                return None  # present or unknown: a person (scan or journey) decides
            cite.append(fact_str(facts, k))
    return f"not relevant (auto): feature-absent: row is about {', '.join(touched)}; {', '.join(dict.fromkeys(cite))}"


_PIPE_WARNED = set()


def esc(s):
    s = str(s or "")
    if "|" in s and s not in _PIPE_WARNED:
        _PIPE_WARNED.add(s)
        print(f"release_impact: an entry contains '|', written as \\| so the table row stays whole: {s[:70]!r}", file=sys.stderr)
    return s.replace("|", "\\|").replace("\n", " ")


ORPHAN_HEAD = "Entries that matched no row"


def old_handled(path):
    """(entries, orphans). Keep handled entries across reruns: key = section + version + change. Entries listed under
    "Entries that matched no row" (T2F-4) come back as keys too, so one survives until its row reappears."""
    keep, orphans, section = {}, {}, ""
    if not path.exists():
        return keep, orphans
    for line in path.read_text(errors="replace").splitlines():
        if line.startswith("## "):
            section = line[3:].strip()
        c = cells(line)
        if not c:
            continue
        if section.startswith(ORPHAN_HEAD):
            if len(c) >= 5 and c[0].startswith("o") and c[0][1:].isdigit() and c[-1]:
                orphans[(c[1], c[2], c[3])] = c[-1]
            continue
        if len(c) >= 4 and re.match(r"^\d+$", c[0]) and c[-1]:
            sec = section.split(" (")[0]
            keep[(sec, c[1], c[4] if sec == "Studio Pro" else c[3])] = c[-1]
    return keep, orphans


def parse_slugs(items):
    """--slug Module=slug (repeatable) -> {Module: slug}; a malformed item is an input error (T6R-4)."""
    out = {}
    for it in items or []:
        m = re.fullmatch(r"\s*([A-Za-z_][\w.]*)\s*=\s*([a-z0-9][a-z0-9-]*)\s*", it)
        if not m:
            sys.exit(f"release_impact: --slug {it!r}: write Module=brain-slug (the file name under modules/, without .md)")
        out[m.group(1)] = m.group(2)
    return out


def generate(a):
    lo, hi = vt(getattr(a, "from")), vt(a.to)
    if not lo or not hi:
        sys.exit("release_impact: --from and --to need a version (10.24.16 or 10.24.16.96987)")
    one_mpr = bool(a.from_mpr) != bool(a.to_mpr)
    if one_mpr and not a.auto:
        sys.exit("release_impact: --from-mpr and --to-mpr go together (with --auto, one of them is read for facts only)")
    types = [t.strip().lower() for t in (a.types.split(",") if a.types else DEFAULT_TYPES) if t.strip()]
    mtypes = types if a.types else MODULE_DEFAULT_TYPES
    br = Brain(a.brain)
    if not (br.v / "modules").is_dir():
        print(f"release_impact: no brain version tables under {br.v}", file=sys.stderr)
        return 2
    out = Path(a.out)
    facts, lost, fact_files = {}, [], []
    if a.auto:
        src = a.facts_from_mpr or a.from_mpr or a.to_mpr
        if not a.facts and not src:
            sys.exit("release_impact: --auto needs facts. One command makes them from the project (it counts the model "
                     "and javasource):\n  release_impact.py --facts-from-mpr app/<App>.mpr --db-vendor postgresql "
                     "--db-version 16 --runtime-os linux --facts-out facts.json\nthen add --facts facts.json. Or give "
                     "--from-mpr <app>.mpr and --auto derives them (database vendor, version and OS stay unknown unless "
                     "you pass those flags). Or test_inventory.py app --json inv.json plus a hand-written facts file.")
        if src:
            derived, notes = facts_from_project(src, a.db_vendor, a.db_version, a.runtime_os)
            dpath = out.with_name(out.stem + ".facts.json")
            dpath.write_text(json.dumps(derived, indent=1) + "\n")
            fact_files.append(str(dpath))
            lost += notes
            print(f"facts: {len(derived)} counted from {src} -> {dpath}")
        fact_files += list(a.facts or [])
        facts = load_facts(fact_files)  # later wins: a hand file overrides what the model gave
        if one_mpr:
            lost.append("module rows and the kept/stranded rule: only one of --from-mpr/--to-mpr given, so the installed "
                        "modules are not paired (add the other mpr, or a --plan)")
        elif not (a.plan or a.from_mpr):
            lost.append("module rows: no --plan and no --from-mpr/--to-mpr pair, so Marketplace module jumps are not listed")
        if "kept" not in facts and "stranded" not in facts:
            lost.append("kept/stranded: not given, rows of modules held back stay open")
        for k in ("db_vendor", "runtime_os", "languages", "own_jdbc", "dev_servlet"):
            if k not in facts:
                lost.append(f"{k}: unknown, the rows it decides stay open")
        for l in dict.fromkeys(lost):
            print(f"auto cannot use: {l}")
    keep, orphans = old_handled(out)
    keep = {**orphans, **keep}
    used = set()
    would = []  # T2F-3: rows that carry a human entry where --auto would also have decided
    gaps = []
    srows, missing = br.studio(lo, hi, types)
    gaps += missing
    L = [f"# Release impact: Mendix {getattr(a, 'from')} to {a.to}", "",
         f"Types: {', '.join(types)}" + ("" if a.types else f" (module rows also: {', '.join(t for t in mtypes if t not in types)})") + f". Source: {br.v} (official release notes in the brain). Every row needs a",
         "`handled: <evidence path or commit>` or `not relevant: <reason>` entry in the last column;",
         "`release_impact.py --check` exits 1 while one is empty. Gate rule: --check clean, or INVALID."]
    hdr_ix = len(L)
    if a.auto:
        L += ["", ""]  # filled once the rows are known (T2F-5): how many entries are auto and how many are a person's
    L.append("")
    n = 0
    counts = {}
    nauto = nhuman = 0

    def row(section, cols):
        nonlocal n, nauto, nhuman
        n += 1
        key = (section, cols[0], cols[3] if section == "Studio Pro" else cols[2])
        h = keep.get(key, "")
        if h:
            used.add(key)
        if a.auto:
            rule = auto_rule(section, cols, facts, lo, hi) or ""
            if not h or AUTO.match(h):  # auto entries are recomputed; a human entry stays
                h = rule
                nauto += bool(h)
            elif rule:
                would.append((n, cols[0], h, rule))
        nhuman += bool(h) and not AUTO.match(h) and bool(HANDLED.match(h))
        return f"| {n} | " + " | ".join(esc(c) for c in cols) + f" | {esc(h)} |"

    L += [f"## Studio Pro ({len(srows)} rows)", ""]
    if srows:
        L += ["| # | version | type | area | change | affected | source | handled |", "|---|---|---|---|---|---|---|---|"]
        for r in srows:
            L.append(row("Studio Pro", [r["version"], r["type"], r["area"], r["change"], r["affected"], r["source"]]))
            counts[r["type"]] = counts.get(r["type"], 0) + 1
    else:
        L.append("No row of these types in the range.")
    L.append("")
    unknown = []
    mod_total = 0
    plan, status = [], []
    if a.from_mpr and a.to_mpr:
        plan, status = mpr_plan(a.from_mpr, a.to_mpr)
    if a.plan:
        given = read_plan(a.plan)
        names = {p["module"] for p in given}
        plan = [p for p in plan if p["module"] not in names] + given
    slugs = parse_slugs(a.slug)
    for p in plan:
        if p["module"] in slugs:
            p["slug"] = slugs[p["module"]]
    for name in sorted(set(slugs) - {p["module"] for p in plan}):
        print(f"release_impact: --slug {name}=... names no module of the plan", file=sys.stderr)
    if status:
        L += [f"## Module versions in the projects ({len(status)} modules, {a.from_mpr} to {a.to_mpr})", "",
              "Paired by content id, then by name. Only updated modules have rows; kept and new modules have no jump.", "",
              "| module | content id | installed before | installed after | status |", "|---|---|---|---|---|"]
        L += ["| " + " | ".join(esc(c) for c in s) + " |" for s in status]
        L.append("")
    for p in plan:
        where = "the projects" if p["line"] == "project" else f"plan line {p['line']}"
        if p.get("bad"):
            unknown.append((p["module"], f"{where} not understood"))
            continue
        if not p["old"]:
            unknown.append((p["module"], f"{where} has no old version: the jump is unknown"))
            continue
        slug, how = br.find(p["module"], p["cid"], p["slug"])
        if not slug:
            unknown.append((p["module"], how))
            continue
        mlo, mhi = vt(p["old"]), vt(p["new"])
        if not mlo or not mhi:
            unknown.append((p["module"], f"{where}: versions not readable"))
            continue
        rows = br.module(slug, mlo, mhi, mtypes)
        sec = f"Module {p['module']}"
        L += [f"## {sec} ({p['old']} to {p['new']}, {len(rows)} rows, brain file modules/{slug}.md by {how})", ""]
        if rows:
            L += ["| # | version | type | change | affected | replaced by | source | handled |", "|---|---|---|---|---|---|---|---|"]
            for r in rows:
                L.append(row(sec, [r["version"], r["type"], r["change"], r["affected"], r["replaced"], r["source"]]))
        else:
            L.append("No row of these types in the jump (the brain file exists; read its improvement rows too when the jump is large).")
        mod_total += len(rows)
        L.append("")
    if unknown or gaps:
        L += [f"## Not covered ({len(unknown) + len(gaps)})", "",
              "Read these release notes by hand and record what you found.", "",
              "| # | module or source | why | change | handled |", "|---|---|---|---|---|"]
        for mname, why in unknown:
            L.append(row("Not covered", [mname, "UNKNOWN", why]))
        for g in gaps:
            L.append(row("Not covered", ["Studio Pro", "UNKNOWN", g]))
        L.append("")
    # T2F-4: an entry whose row is gone (the brain caught up and reworded it) is listed, never dropped
    lost_entries = [(k, v) for k, v in keep.items() if k not in used and not AUTO.match(v)]
    if lost_entries:
        L += [f"## {ORPHAN_HEAD} ({len(lost_entries)})", "",
              "These handled entries belonged to rows this run did not find (the brain's wording or version changed, or "
              "the row left the jump). Read each: copy it to its new row, or delete it. A rerun keeps it until its row "
              "returns.", "",
              "| # | section | version | change | handled |", "|---|---|---|---|---|"]
        for i, ((sec, ver, chg), v) in enumerate(sorted(lost_entries), 1):
            L.append(f"| o{i} | {esc(sec)} | {esc(ver)} | {esc(chg)} | {esc(v)} |")
        L.append("")
    if a.auto:
        L[hdr_ix:hdr_ix + 2] = [
            "`not relevant (auto): <rule>: <fact>` entries were written by --auto from the facts "
            + ", ".join(f"`{f}`" for f in fact_files) + ": replace one with your own entry",
            f"when the fact is wrong for that row (a human entry is never overwritten). This run: {nauto} auto, "
            f"{nhuman} kept from a person, {n - nauto - nhuman} open."]
    out.write_text("\n".join(L) + "\n")
    print(f"release-impact: Studio Pro {len(srows)} rows (" + (", ".join(f"{k} {v}" for k, v in sorted(counts.items())) or "none") +
          f"), modules {mod_total} rows, not covered {len(unknown) + len(gaps)} -> {out}")
    if a.auto:
        print(f"auto: {nauto} of {n} rows pre-filled as not relevant from {len(facts)} facts "
              f"({', '.join(sorted(facts)) or 'none'}); the rest stay for a person")
    if lost_entries:
        print(f"orphan entries: {len(lost_entries)} handled entries matched no row (listed under '{ORPHAN_HEAD}' in {out})")
    if would:
        differ = [w for w in would if not w[2].lower().startswith("not relevant")]
        print(f"auto would also decide {len(would)} rows that carry a human entry; {len(differ)} of them differ in kind "
              "(auto says not relevant, the person says handled)")
        for num, ver, h, rule in differ[:10]:
            print(f"  row {num} ({ver}): human `{h[:70]}` vs {rule[:110]}")
    for mname, why in unknown:
        print(f"UNKNOWN {mname}: {why}")
    for g in gaps:
        print(f"UNKNOWN {g}")
    return 2 if unknown or gaps else 0


def check(path):
    p = Path(path)
    if not p.exists():
        print(f"release_impact: no file {p}", file=sys.stderr)
        return 2
    section, open_rows, unsound, blocked, total, nauto, reviewed, rejected = "", [], [], [], 0, 0, [], []
    for line in p.read_text(errors="replace").splitlines():
        if line.startswith("## "):
            section = line[3:].split(" (")[0]
        c = cells(line)
        if c and re.match(r"^\d+$", c[0]):
            total += 1
            if HANDLED.match(c[-1]) and re.search(r"\bREVIEW\b", c[-1]):   # MC-15: counted as handled, but a person said "look again"
                reviewed.append(f"{section} row {c[0]}")
            label = f"{section} row {c[0]}: {c[1]} {c[2]} {c[4] if len(c) > 4 else ''}"[:160]
            if not HANDLED.match(c[-1]):
                open_rows.append(label)
                if c[-1].strip() and not re.match(r"^(open|blocked)\s*:\s*\S", c[-1], re.I):
                    rejected.append(label)
                if re.match(r"^(open|blocked)\s*:\s*\S", c[-1], re.I):   # NR1-23: a finding is written, nobody has to re-read it
                    blocked.append(label)
            elif len(c) > 4 and (c[2].lower() in ("removal", "breaking") or re.search(r"\bdefault", c[4], re.I)) \
                    and unsound_closure(c[4], c[-1]):   # NR1-21: a flipped default is unsound whatever the row type
                open_rows.append(label)
                unsound.append(label)
            elif AUTO.match(c[-1]):
                nauto += 1
    if total == 0 and "No row of these types" not in p.read_text(errors="replace"):
        print(f"release_impact: {p} holds no release-impact rows", file=sys.stderr)
        return 2
    for r in open_rows[:30]:
        print(f"{'UNSOUND' if r in unsound else 'BLOCKED' if r in blocked else 'OPEN'} {r}")
    if len(open_rows) > 30:
        print(f"... and {len(open_rows) - 30} more")
    if rejected:   # FM-7: a written entry that does not parse: say what is expected, do not make the agent guess
        print(f"{len(rejected)} open row(s) have text in the last column that is not an entry (e.g. {rejected[0]}). "
              "Expected: `handled: <evidence path or commit>` or `not relevant: <reason>` (also `not relevant for <what>: <reason>`), "
              "starting with that word; the reason must follow the colon.")
    print(f"release-impact check: {total - len(open_rows)} of {total} rows handled or not relevant, {len(open_rows)} open"
          + (f" ({len(reviewed)} handled row(s) marked REVIEW)" if reviewed else ""))
    if reviewed:
        print("REVIEW-MARKED (handled, flagged for a human; the check does not fail on them, the report must list them): "
              + ", ".join(reviewed[:12]) + (f" and {len(reviewed) - 12} more" if len(reviewed) > 12 else ""))
    print(f"auto: {nauto}, human: {total - len(open_rows) - nauto}, open: {len(open_rows)}")
    if blocked:
        print(f"blocked: {len(blocked)} (finding written), untouched: {len(open_rows) - len(blocked) - len(unsound)}, "
              f"unsound: {len(unsound)}")
    if unsound:
        print(f"unsound closures: {len(unsound)} (a removed setting or flipped default closed only because the setting is "
              "not set; the app ran with the OLD default. Cite the source version that already had the new default, or a "
              "scan or journey showing the behaviour is not used: steps/triage.md step 10, QJ-2)")
    return 1 if open_rows else 0


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--from", dest="from")
    ap.add_argument("--to")
    ap.add_argument("--plan")
    ap.add_argument("--from-mpr", dest="from_mpr")
    ap.add_argument("--to-mpr", dest="to_mpr")
    ap.add_argument("--slug", action="append", help="Module=brain-slug, for a module neither name nor content id finds (T6R-4)")
    ap.add_argument("--auto", action="store_true")
    ap.add_argument("--facts", action="append")
    ap.add_argument("--types")
    ap.add_argument("--out", default="release-impact.md")
    ap.add_argument("--brain", default=os.environ.get("UPG_BRAIN", str(Path("~/Mendix/<company>-brain").expanduser())))
    ap.add_argument("--facts-from-mpr", dest="facts_from_mpr", help="count facts from this project (model + javasource), T2F-2")
    ap.add_argument("--facts-out", dest="facts_out")
    ap.add_argument("--db-vendor", dest="db_vendor")
    ap.add_argument("--db-version", dest="db_version")
    ap.add_argument("--runtime-os", dest="runtime_os")
    ap.add_argument("--check")
    ap.add_argument("--java-rev", dest="java_rev", help="commit whose javasource/userlib the java-actions removal rows are judged on (PV-4)")
    a = ap.parse_args()
    JAVA_REV["rev"] = a.java_rev
    if a.check:
        sys.exit(check(a.check))
    if a.facts_from_mpr and not getattr(a, "from") and not a.to:
        facts, notes = facts_from_project(a.facts_from_mpr, a.db_vendor, a.db_version, a.runtime_os)
        dest = a.facts_out or "facts.json"
        Path(dest).write_text(json.dumps(facts, indent=1) + "\n")
        print(f"facts: {len(facts)} counted from {a.facts_from_mpr} -> {dest}")
        for k, v in facts.items():
            print(f"  {k} = {json.dumps(v)}")
        for nline in notes:
            print(f"unknown, left out: {nline}")
        sys.exit(0)
    if not getattr(a, "from") or not a.to:
        hint = ""
        if a.from_mpr or a.to_mpr:  # T6R-4: --from-mpr gives the module plan, not the Studio Pro jump
            sys.path.insert(0, str(Path(__file__).resolve().parent))
            from mxversion import version as mpr_version

            def ver(f):
                try:
                    return mpr_version(f) or "unreadable"
                except Exception:  # a missing or locked file must not hide the real message
                    return "unreadable"
            vs = [f"{f} is {ver(f)}" for f in (a.from_mpr, a.to_mpr) if f]
            hint = (" --from-mpr/--to-mpr give the module plan only, not the Studio Pro versions of the jump: add "
                    f"--from <old Studio Pro> --to <target Studio Pro> ({'; '.join(vs)})")
        ap.error("--from and --to are required (or --check FILE)." + hint)
    sys.exit(generate(a))


if __name__ == "__main__":
    main()
