#!/usr/bin/env python3
"""Derive an upgrade regression TEST INVENTORY from an mxcli catalog: which part of the app map drives which test.

  test_inventory.py <project-dir-with-.mxcli/catalog.db> [--json out.json] [--md out.md] [--endpoints out.txt]

Jars are counted from the FILES (userlib/*.jar, vendorlib/*.jar), not only from the catalog, which only knows
managed dependencies (an app with about 50 userlib jars showed "Jar dependencies 0"). Duplicates by ARTIFACT IDENTITY
(jar_identity below: pom.properties groupId:artifactId, else manifest module name, else file-name key; within userlib,
or between userlib and vendorlib) and known upgrade-sensitive jars are listed; a duplicate found here existed before
the upgrade. The same identity function serves bin/repair/jardedupe.py and jarclash.py (T3-3, T3-17).

--endpoints writes a probe list for snapshot.py: only GET operations without path parameters, and never an
operation whose name or path suggests a side effect (delete, clear, stop, reset, ...; a GET "mailclear" deleted
mail in run E1). Flagged operations are listed in the inventory so a person decides.

Build the catalog first with a FULL rebuild (fast mode leaves tables empty):
  mxcli graph-report -p app.mpr --format json > /dev/null      (or the toolkit's bin/app-facts.sh, which forces it)

Read-only. Every row says what to test, how (automated instrument or human), and why it matters on an upgrade.
A section with 0 rows is printed as 0, never omitted: "no published REST" is a fact, not a gap.
"""
import argparse, json, re, sqlite3, sys, zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from mxversion import addons as addon_files, below  # noqa: E402  one reader of add-on versions (T2-2)
from odataconn import catalog_refs  # noqa: E402  OData connector modules count as consumed OData (T3F-11)

SENSITIVE = ("pdfbox", "guava", "commons-", "jackson", "bcprov", "httpclient", "poi", "log4j", "slf4j", "xmlbeans")
SIDE_EFFECT = re.compile(r"(?i)delete|remove|clear|purge|stop|start|reset|cancel|kill|drop|send|trigger|run|execute|"
                         r"sync|import|export|update|create|insert|approve|reject|logout|unsubscribe")


def jar_key(name):
    """'pdfbox-2.0.27.jar' -> ('pdfbox', '2.0.27'); no version -> (stem, '')."""
    stem = name[:-4] if name.endswith(".jar") else name
    m = re.match(r"^(.*?)[-_]v?(\d+(?:\.\d+)*(?:[.-][A-Za-z0-9]+)*)$", stem)
    return (m.group(1), m.group(2)) if m else (stem, "")


def _props(text):
    return dict(re.findall(r"^([\w.-]+)\s*[=:]\s*(.*?)\s*$", text, re.M))


def _manifest(text):
    """MANIFEST.MF main section as a dict (continuation lines start with one space)."""
    text = re.sub(r"\r?\n ", "", text)
    return {k.lower(): v.strip() for k, v in re.findall(r"^([A-Za-z][\w-]*):\s*(.*)$", text, re.M)}


def jar_identity(path):
    """What a jar IS, not what it is called (T3-3, T3-17): the file name differs between module packagings
    ('commons-codec-1.15.jar', 'commons-codec.commons-codec-1.15.jar', 'org.apache.commons.io-2.3.0.jar',
    'org.apache.commons.lang3.jar' without a version) while the library is one.
    Returns {"key": label, "aliases": set, "ver": str, "src": "pom"|"manifest"|"name"}.
      key     groupId:artifactId from META-INF/maven/*/*/pom.properties; else the manifest Automatic-Module-Name /
              Bundle-SymbolicName; else the file-name key (last fallback: empty or unreadable files land here).
              A jar with several poms (shaded, uber) uses the one whose artifactId the file name carries; none -> next rule.
      aliases every name the jar answers to (key + manifest names): two jars are one artifact when they share one
              (a jar with a pom and a jar with only a manifest name still meet on the module name).
      ver     the file name's version; if it has none, pom version, Bundle-Version, Implementation-Version."""
    name = Path(path).name
    fa, fv = jar_key(name)
    ga, pv, mnames, mver = None, "", [], ""
    try:
        with zipfile.ZipFile(path) as z:
            names = z.namelist()
            poms = []
            for n in names:
                if re.fullmatch(r"META-INF/maven/[^/]+/[^/]+/pom\.properties", n):
                    p = _props(z.read(n).decode("utf-8", "replace"))
                    if p.get("artifactId"):
                        poms.append((p.get("groupId") or n.split("/")[2], p["artifactId"], p.get("version", "")))
            pick = poms if len(poms) == 1 else [x for x in poms if fa.lower().endswith(x[1].lower())]
            if len({(g, a) for g, a, _ in pick}) == 1:
                ga, pv = f"{pick[0][0]}:{pick[0][1]}", pick[0][2]
            if "META-INF/MANIFEST.MF" in names:
                m = _manifest(z.read("META-INF/MANIFEST.MF").decode("utf-8", "replace"))
                for k in ("automatic-module-name", "bundle-symbolicname"):
                    if m.get(k):
                        mnames.append(m[k].split(";")[0].strip())
                mver = m.get("bundle-version") or m.get("implementation-version") or ""
    except (zipfile.BadZipFile, OSError):
        pass
    key = ga or (mnames[0] if mnames else fa)
    src = "pom" if ga else ("manifest" if mnames else "name")
    # T6R-10: BouncyCastle ships one library per JDK build ('bcprov-jdk15on', 'bcprov-jdk15to18', 'bcprov-jdk18on'): the
    # same classes, a renamed artifact. BC 1.69+ jars meet on the manifest module name, older ones (Bundle-SymbolicName
    # 'bcprov', or no manifest) did not, and a jdk15on jar kept shadowing the jdk18on one. The family name is an alias.
    bc = re.fullmatch(r"(?i)(bc[a-z]+(?:-ext)?)-jdk\d+(?:on|to\d+)?", fa)
    fam = {f"org.bouncycastle:{bc.group(1).lower()}"} if bc else set()
    if bc and src == "name":
        key = next(iter(fam))
    return {"key": key, "aliases": {key, *mnames, *fam}, "ver": fv or pv or mver, "src": src}


def group_by_identity(items):
    """items: [(id, identity)] -> [(label, [id, ...])] sorted by label. Jars sharing any alias are one artifact."""
    parent = {}

    def find(x):
        while parent.setdefault(x, x) != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x
    for _, ident in items:
        al = sorted(ident["aliases"])
        for a in al[1:]:
            parent[find(a)] = find(al[0])
    groups = {}
    for jid, ident in items:
        groups.setdefault(find(sorted(ident["aliases"])[0]), []).append((jid, ident))
    out = []
    for g in groups.values():
        label = next((i["key"] for _, i in g if i["src"] == "pom"), g[0][1]["key"])
        out.append((label, [j for j, _ in g]))
    return sorted(out)


def jar_files(project):
    out, ids = {}, []
    for d in ("userlib", "vendorlib"):
        out[d] = sorted(p.name for p in (Path(project) / d).glob("*.jar")) if (Path(project) / d).is_dir() else []
        ids += [(f"{d}/{j}", jar_identity(Path(project) / d / j)) for j in out[d]]
    # inside userlib too (commons-lang3 3.12 and 3.14 side by side in run E5b): listed at triage, so a duplicate that was
    # there before the upgrade is not blamed on it later (E5b-4). Grouped by identity, not file name (T3-3).
    out["duplicates"] = sorted(" | ".join(v) for _, v in group_by_identity(ids) if len(v) > 1)
    out["sensitive"] = sorted(j for j in out["userlib"] + out["vendorlib"] if j.lower().startswith(SENSITIVE))
    return out


def rows(db, sql):
    try:
        cur = db.execute(sql); cols = [c[0] for c in cur.description]
        return [dict(zip(cols, r)) for r in cur.fetchall()]
    except sqlite3.OperationalError as e:
        return [{"_error": str(e)}]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("project"); ap.add_argument("--json"); ap.add_argument("--md"); ap.add_argument("--endpoints")
    a = ap.parse_args()
    cat = Path(a.project) / ".mxcli" / "catalog.db"
    if not cat.exists(): sys.exit(f"no catalog at {cat}; run a full mxcli graph-report first")
    db = sqlite3.connect(f"file:{cat}?mode=ro", uri=True)

    mods = rows(db, "select Name, Source, AppStoreVersion from modules_data order by Name")
    own = {m["Name"] for m in mods if not m["Source"] and m["Name"] != "System"}
    ents = rows(db, "select QualifiedName, ModuleName, EntityType, Generalization, AttributeCount, AssociationCount, HasEventHandlers from entities_data")
    persist = [e for e in ents if (e["EntityType"] or "").lower().startswith("persist")]
    inv = {
        "modules": {"marketplace": [m for m in mods if m["Source"]], "own": sorted(own)},
        "entities": {"persistent": len(persist), "non_persistent": len(ents) - len(persist),
                     "own_persistent": sorted(e["QualifiedName"] for e in persist if e["ModuleName"] in own),
                     "with_event_handlers": sorted(e["QualifiedName"] for e in persist if e["HasEventHandlers"])},
        "published_rest": rows(db, "select ServiceQualifiedName as service, HttpMethod as method, Path as path, Microflow as microflow from published_rest_operations_data order by 1,3"),
        "consumed_rest": rows(db, "select QualifiedName as name, BaseUrl as base_url, OperationCount as ops from rest_clients_data"),
        "rest_call_activities": rows(db, "select count(*) as n from activities_data where ActionType in ('RestCallAction','WebServiceCallAction','CallExternalAction','SendRestRequestAction')"),
        "odata_published": rows(db, "select QualifiedName, Path, EntitySetCount from odata_services_data"),
        "odata_consumed": rows(db, "select QualifiedName, MetadataUrl from odata_clients_data"),
        # T3F-11: the built-in client count misses OData consumed through a Marketplace connector (SAPODataConnector, ...)
        "odata_consumed_connector": catalog_refs(rows(db, "select SourceName, RefKind, TargetName from refs"),
                                                 [{"QualifiedName": e["QualifiedName"], "Generalization": e["Generalization"]} for e in ents if "_error" not in e],
                                                 [m["Name"] for m in mods if "Name" in m]),
        "scheduled_events": rows(db, "select QualifiedName as name, Microflow as microflow, Enabled as enabled, RepeatDescription as repeat from scheduled_events_data order by 1"),
        "java_actions": rows(db, "select ModuleName as module, count(*) as n from java_actions_data group by 1 order by 2 desc"),
        "role_homes": rows(db, "select ProfileName as profile, UserRole as role, Page as page, Microflow as microflow from navigation_role_homes"),
        "menu_items": rows(db, "select count(*) as n, count(distinct TargetPage) as pages from navigation_menu_items"),
        "pluggable_widgets": rows(db, "select WidgetType as type, count(*) as n from widgets_data where WidgetType like '%.%' group by 1 order by 2 desc"),
        "jars": rows(db, "select ModuleName as module, Coordinate as coord, Version as version from jar_dependencies_data"),
        "workflows": rows(db, "select QualifiedName from workflows_data"),
        "business_events": rows(db, "select QualifiedName from business_event_services_data"),
    }
    inv["jar_files"] = jar_files(a.project)
    # add-on modules (modules/*.mxmodule) are not in the catalog; each is listed with the Studio Pro version that built it (T2-2)
    inv["addons"] = [{"file": f, "built_with": v, "blocks_11": below(v, 10, 21)} for f, v in addon_files(a.project)]
    probes, flagged = [], []
    for r in inv["published_rest"]:
        if "_error" in r: continue
        path = (r.get("path") or "").strip()
        label = f"{r.get('method')} {r.get('service')} {path} ({r.get('microflow')})"
        if (r.get("method") or "").upper() != "GET": continue
        if SIDE_EFFECT.search(f"{path} {r.get('microflow') or ''}"): flagged.append(label); continue
        if not path or "{" in path: flagged.append(label + " [path empty or has parameters: fill by hand]"); continue
        probes.append(path if path.startswith("/") else "/" + path)
    inv["rest_probe_list"], inv["rest_flagged"] = probes, flagged
    if a.endpoints:
        open(a.endpoints, "w").write("# generated by test_inventory.py: parameterless GETs without side-effect names\n/\n/rest-doc/\n"
                                     + "".join(p + "\n" for p in probes)
                                     + "".join(f"# NOT PROBED (decide by hand): {f}\n" for f in flagged))
    jf = inv["jar_files"]
    ocr = inv["odata_consumed_connector"]
    oc = ("connector modules: UNKNOWN (" + ocr[0]["_error"] + ")" if ocr and "_error" in ocr[0]
          else f"{len(ocr)} references into OData connector modules ({', '.join(sorted({r['target'].split('.')[0] for r in ocr})) or 'none'}): consumed OData if > 0")
    jown = sum(r["n"] for r in inv["java_actions"] if r.get("module") in own)
    plan = [
        ("Persistent entities", f"{len(persist)} ({len(inv['entities']['own_persistent'])} in own modules)", "data survival: per-entity row count + per-attribute checksum + association pairs, before vs after on a COPY of the same DB", "auto: seed_pg.py, snapshot.py, diff.py"),
        ("Entities with event handlers", str(len(inv["entities"]["with_event_handlers"])), "commit/delete through the app (journey or unit test) so before/after-commit logic runs", "auto if journeys exist, else human"),
        ("Published REST operations", f"{len(inv['published_rest'])} ({len(probes)} safe GET probes, {len(flagged)} flagged: side effect or parameters)", "OpenAPI contract diff (auto) + one live call per GET without parameters (auto) + write calls with test payloads", "auto contract; payloads human-authored once"),
        ("Consumed REST / web services", f"{len(inv['consumed_rest'])} clients, {inv['rest_call_activities'][0].get('n', '?')} call activities", "outbound call against a mock or sandbox; check encoding, auth, TLS (PKIX) after the Java/runtime change", "human or mock server"),
        ("OData published / consumed", f"{len(inv['odata_published'])} / {len(inv['odata_consumed'])} (built-in client); {oc}", "$metadata diff + one query per entity set", "auto"),
        ("Scheduled events", f"{len(inv['scheduled_events'])} ({sum(1 for s in inv['scheduled_events'] if s.get('enabled'))} enabled)", "enabled state and interval unchanged (model diff); trigger the microflow once in test (admin API or unit test) and check its side effect", "auto diff; trigger semi-auto"),
        ("Java actions", f"{sum(r.get('n', 0) for r in inv['java_actions'])} ({jown} in own modules)", "compile is proved by the build; behaviour needs a unit test per own Java action (Unit Testing module or mxcli test)", "build auto; unit tests human-authored"),
        ("Role home pages and menu", f"{len(inv['role_homes'])} homes, {inv['menu_items'][0].get('n', '?')} menu items", "per role: log in, land on home, open each menu target, no client error (journey-runner)", "auto once journeys are written"),
        ("Pluggable widgets", f"{len(inv['pluggable_widgets'])} types", "page renders with no console error; visual diff on the pages that use the widget", "auto render; visual review human"),
        ("Jar dependencies", f"{len(jf['userlib'])} userlib + {len(jf['vendorlib'])} vendorlib files ({len(inv['jars'])} managed in the catalog); {len(jf['duplicates'])} duplicated by artifact identity, present BEFORE the upgrade{(': ' + '; '.join(jf['duplicates'][:4])) if jf['duplicates'] else ''}; upgrade-sensitive: {', '.join(jf['sensitive'][:8]) or 'none'}", "userlib/vendorlib diff; duplicate jars by artifact (bin/repair/jardedupe.py); runtime start log has no ClassNotFound/NoSuchMethod", "auto"),
        ("Add-on modules (.mxmodule)", f"{len(inv['addons'])}{(': ' + '; '.join(x['file'] + ' built with ' + (x['built_with'] or 'UNKNOWN') for x in inv['addons'])) if inv['addons'] else ''}{('; BLOCKS MENDIX 11 (built before 10.21): ' + ', '.join(x['file'] for x in inv['addons'] if x['blocks_11'])) if any(x['blocks_11'] for x in inv['addons']) else ''}", "mx check on each rung; a vendor binary cannot be reopened, so one built before 10.21 needs a newer vendor build (playbook 10-to-11, blocker 9); idcheck old vs new", "auto check; vendor build human"),
        ("Marketplace modules", str(len(inv["modules"]["marketplace"])), "mxcli marketplace diff per module BEFORE updating (local edits get overwritten); after: module version table", "auto"),
        ("Workflows / business events", f"{len(inv['workflows'])} / {len(inv['business_events'])}", "in-flight workflow instances survive; event contract unchanged", "auto data rung + human"),
    ]
    inv["test_plan"] = [dict(zip(("app_part", "count", "test", "how"), p)) for p in plan]
    if a.json: json.dump(inv, open(a.json, "w"), indent=1)
    md = "| app part | count | regression test | automated? |\n|---|---|---|---|\n" + "\n".join(f"| {p[0]} | {p[1]} | {p[2]} | {p[3]} |" for p in plan)
    if a.md: open(a.md, "w").write(md + "\n")
    print(md)


if __name__ == "__main__":
    main()
