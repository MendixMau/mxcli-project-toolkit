#!/usr/bin/env python3
"""readiness.py: test-readiness scorecard. Before any upgrade work, say per gate rung whether the app can be judged,
what the customer must supply when it cannot, and which verdict the run can reach at best (RD-1).

    readiness.py <work dir> [--app <project dir or .mpr>] [--exclude Teamcenter] [--classify FILE]
                 [--test-systems FILE] [--data FILE] [--journeys-summary FILE] [--md FILE] [--json FILE]

Why: in the 13 and 14 Oct runs, rungs turned out unjudgeable only at the very end. notification-service R2: 233 of 406
generated journeys failed on the OLD app (57%, bar 30%), so the journeys rung could never pass. R1: 19 consumed API
endpoints UNKNOWN, the apis rung INVALID. PLM and PV360: guest access on and no confirmed key-user process as the
anonymous role, journeys INVALID. Teamcenter apps fall back to mock data without an error, so a rendered connector
page proves nothing (TC-1, PV-10, MC-17). Each of those was knowable at triage from what triage already writes.

It reads only (nothing is started, nothing is written into the app), from the work dir $W unless a flag names a file:
  test-inventory.json or inventory.json (test_inventory.py --json), else test-inventory.md   counts per app part
  endpoints.txt (test_inventory.py --endpoints)   safe GET probes
  facts.json (release_impact.py --facts-out)      consumed REST, OData, web services
  connectors.md (triage item 12)                  proof value, mock signs and account per connector
  apimock/inventory.json (apimock.py serve), else apimock.build_inventory on the model (--app)   endpoint classes
  processes.md                                    confirmed key-user processes (process_journeys.parse_processes)
  after the baseline: before.json (row counts), users.json (test users per role), the old-app journeys summary.json
  with a coverage line (run_journeys.py; the newest under $W with the most journeys, or --journeys-summary)
--app reads the model (mprmodel.py): user roles, the guest role, module names, a publisher data-snapshot.zip.
Missing inputs are said per rung ("not read: ..."), never taken as "nothing there".

Per rung (build idcheck const data rest logdiff smoke journeys screens release apis connectors, and scheduled events,
which no rung covers) one status:
  READY          the instruments can judge it with what the run has
  NEEDS <input>  the customer (or the run) must supply something first; "blocks" when the gate is INVALID without it,
                 otherwise the fallback is named (stand-in APIs, NOT CHECKED connector pages, seeded rows only)
  CANNOT JUDGE   measured on the baseline: the instrument does not measure (journeys failing on the OLD app above the
                 gate's 30% bar, run_journeys.DEFECT_MAX; an empty frozen database). The rung stays INVALID.
Top line: "best reachable verdict: PASS", "PASS (on stand-in APIs: ...; on seeded rows; except Teamcenter: connector
pages)", "INVALID unless <inputs> (then at best: PASS (...))", or "NOT JUDGED until read: <input>" when an input
is missing. The same rules as the gate (steps/gate.md, SKILL "External APIs").

--exclude: systems no stand-in can replace (default Teamcenter, apimock's built-in patterns; --exclude '' for none).
--test-systems FILE: lines "<System> <url> # note", the customer's test or sandbox system per consumed system (module
  name as apimock prints it). Covered systems count as real; the rest is stand-in at best.
--data FILE: a demo data snapshot or a test database dump the customer supplied (data route a, steps/baseline.md).
Writes $W/readiness.md and $W/readiness.json unless --md / --json say otherwise.
Exit: 0 = plain PASS reachable, 4 = a qualified PASS at best (stand-in APIs, seeded rows, excluded system),
3 = INVALID unless inputs, 2 = not judged (no work dir, or an input not read).
"""
import argparse, glob, json, os, re, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from run_journeys import DEFECT_MAX  # noqa: E402  the gate's 30% bar, one definition

RUNGS = ("build", "idcheck", "const", "data", "rest", "logdiff", "smoke", "journeys", "screens", "release", "apis",
         "connectors", "scheduled")


def row(rung, status, why, supply="", blocks=False, fallback="", source=""):
    return {"rung": rung, "status": status, "why": why, "supply": supply, "blocks": blocks, "fallback": fallback,
            "source": source}


def num(text, pat, default=None):
    m = re.search(pat, text or "")
    return int(m.group(1)) if m else default


# ------------------------------------------------------------------------------------------------ inputs
def read_inventory(w, path=None):
    """test_inventory.py output as one dict of counts, from its JSON (preferred) or its markdown table. None if absent."""
    cands = [path] if path else [w / "test-inventory.json", w / "inventory.json", w / "test-inventory.md"]
    for p in [Path(c) for c in cands if c]:
        if not p.is_file():
            continue
        if p.suffix == ".json":
            try:
                d = json.load(open(p))
            except ValueError:
                continue
            if "test_plan" not in d:
                continue
            ok = lambda k: [r for r in d.get(k) or [] if "_error" not in r]
            return {"src": str(p), "pub_rest": len(ok("published_rest")), "probes": len(d.get("rest_probe_list") or []),
                    "consumed": len(ok("consumed_rest")), "calls": ((d.get("rest_call_activities") or [{}])[0]).get("n", 0) or 0,
                    "sched": len(ok("scheduled_events")), "sched_on": sum(1 for s in ok("scheduled_events") if s.get("enabled")),
                    "homes": len(ok("role_homes")), "persistent": (d.get("entities") or {}).get("persistent"),
                    "addons_11": [a["file"] for a in d.get("addons") or [] if a.get("blocks_11")],
                    "workflows": len(ok("workflows"))}
        parts = {}
        for line in p.read_text().splitlines():
            c = [x.strip() for x in line.strip().strip("|").split("|")]
            if len(c) >= 2:
                parts[c[0]] = c[1]
        if "Persistent entities" not in parts:
            continue
        g = parts.get
        return {"src": str(p), "pub_rest": num(g("Published REST operations"), r"^(\d+)", 0),
                "probes": num(g("Published REST operations"), r"(\d+) safe GET", 0),
                "consumed": num(g("Consumed REST / web services"), r"^(\d+) clients", 0),
                "calls": num(g("Consumed REST / web services"), r"(\d+) call activities", 0),
                "sched": num(g("Scheduled events"), r"^(\d+)", 0), "sched_on": num(g("Scheduled events"), r"\((\d+) enabled", 0),
                "homes": num(g("Role home pages and menu"), r"^(\d+) homes", 0),
                "persistent": num(g("Persistent entities"), r"^(\d+)"),
                "addons_11": re.findall(r"[\w.-]+\.mxmodule", (g("Add-on modules (.mxmodule)") or "").partition("BLOCKS MENDIX 11")[2]),
                "workflows": num(g("Workflows / business events"), r"^(\d+)", 0)}
    return None


def load_json(p):
    try:
        return json.load(open(p)) if p and Path(p).is_file() else None
    except ValueError:
        return None


def find_model(app):
    if not app:
        return None
    p = Path(app)
    if p.is_file():
        return p
    found = sorted(p.glob("*.mpr")) if p.is_dir() else []
    return found[0] if found else None


def read_model(mpr):
    """(info, error): roles, guest, modules and the project dir from the model (mprmodel.py)."""
    import mprmodel
    try:
        m = mprmodel.Model.load(str(mpr))
    except SystemExit as e:
        return None, f"model not read: {e}"
    except Exception as e:  # noqa: BLE001  an unreadable model is said, never "no roles"
        return None, f"model not read: {e}"
    sec = m.security_summary()
    roles = sorted(r for r in m.user_roles() if r)
    return {"mpr": str(mpr), "roles": roles, "guest": sec.get("GuestUserRole") if sec.get("EnableGuestAccess") else None,
            "modules": sorted(getattr(m, "modules", []) or []), "project": str(Path(mpr).parent)}, None


def api_inventory(w, mpr, excludes, classify):
    """(inventory dict, source, error): apimock's stand-in state when the run has one, else its inventory of the model."""
    st = w / "apimock" / "inventory.json"
    if st.is_file() and not classify:
        inv = load_json(st)
        if inv and "endpoints" in inv:
            return inv, str(st), None
    if not mpr:
        return None, "", "no apimock/inventory.json and no model (--app): consumed APIs not classified"
    import apimock
    try:
        return apimock.build_inventory([str(mpr)], apimock.parse_excludes(excludes), apimock.read_classify(classify), None), \
            f"apimock.build_inventory({Path(mpr).name})", None
    except SystemExit as e:
        return None, "", f"apimock could not read the model: {e}"


def unknown_kinds(eps):
    """How each UNKNOWN endpoint can be closed, counted: a reason line, a seed-data location, a LOCATION line or a test system."""
    k = {}
    for e in eps:
        if e["status"] != "UNKNOWN":
            continue
        kinds = {r[0] for r in e.get("routes") or []}
        key = ("add-on (declare its LOCATION)" if e["id"].startswith("addon:") else
               "URL constant no modelled call reads (classify with a reason)" if e.get("kind") == "const" else
               "location from data (seed the /a/ URL)" if "attr" in kinds else
               "hard-coded URL (test system, or not stood in)" if "literal" in kinds else
               "location built at runtime (declare its LOCATION)")
        k[key] = k.get(key, 0) + 1
    return k


def read_test_systems(path):
    if not path:
        return {}
    out = {}
    for line in Path(path).read_text().splitlines():
        body = line.partition("#")[0].split()
        if len(body) >= 2:
            out[body[0]] = body[1]
    return out


def connector_blocks(text):
    """connectors.md -> [(heading, body)] for blocks that are about a connector (heading names a connector or toolkit)."""
    out, cur = [], None
    for line in text.splitlines():
        if line.startswith("## "):
            cur = [line[3:].strip(), []]
            out.append(cur)
        elif cur is not None:
            cur[1].append(line)
    return [(h, "\n".join(b)) for h, b in out if re.search(r"(?i)connector|toolkit|teamcenter|\btc\b", h)]


def journeys_summary(w, path=None):
    """The old-app journeys summary.json with a coverage line: --journeys-summary, else the one under $W (not a gate
    folder) with the most journeys, generated sets first."""
    if path:
        d = load_json(path)
        return (d, str(path)) if d else (None, "")
    best = None
    for p in glob.glob(str(w / "**" / "summary.json"), recursive=True):
        rel = os.path.relpath(p, w)
        if rel.count(os.sep) > 4 or re.search(r"(^|/)gate", rel):
            continue
        d = load_json(p)
        c = (d or {}).get("coverage") or {}
        if not isinstance(c, dict) or not c.get("G"):
            continue
        key = (c.get("A") is not None, c.get("G"))
        if best is None or key > best[0]:
            best = (key, d, p)
    return (best[1], best[2]) if best else (None, "")


def confirmed_processes(w):
    p = w / "processes.md"
    if not p.is_file():
        return None
    from process_journeys import parse_processes
    return [x for x in parse_processes(p.read_text()) if x.get("status") == "confirmed"]


# ------------------------------------------------------------------------------------------------ rungs
def judge(w, a):
    notread, rows = [], {}
    inv = read_inventory(w, a.inventory)
    if inv is None:
        notread.append("test inventory (triage item 8: test_inventory.py --md/--json)")
    facts = load_json(w / "facts.json")
    mpr = find_model(a.app) or find_model(w.parent / "app")
    model, merr = (read_model(mpr) if mpr else (None, "no model (--app)"))
    if merr:
        notread.append(merr)
    excludes = [x for x in (a.exclude if a.exclude is not None else ["Teamcenter"]) if x]
    api, api_src, aerr = api_inventory(w, model and model["mpr"], excludes, a.classify)
    if aerr:
        notread.append(aerr)
    before = load_json(w / "before.json")
    users = load_json(w / "users.json")
    jsum, jsrc = journeys_summary(w, a.journeys_summary)
    procs = confirmed_processes(w)
    phase = "baseline" if (before or jsum) else "triage"

    # build: an add-on built before 10.21 cannot be reopened; only a vendor build helps
    adds = (inv or {}).get("addons_11") or []
    rows["build"] = (row("build", "NEEDS a newer vendor build of " + ", ".join(adds),
                         f"add-on module(s) built before 10.21 block Mendix 11 (playbook 10-to-11 blocker 9): {', '.join(adds)}",
                         "a vendor build of each add-on made with 10.21 or later", True, source=(inv or {}).get("src", ""))
                     if adds else row("build", "READY", "mx check and mxbuild need only the toolset", source=(inv or {}).get("src", "")))
    rows["idcheck"] = row("idcheck", "READY", "model only (old and new MDA)")
    rows["const"] = row("const", "READY", "model only; give the environment's values as --overrides so a reset to a package default shows",
                        supply="the environment's constant values (CONST_OVERRIDES), recommended")
    rows["logdiff"] = row("logdiff", "READY", "two start logs of the same database")
    rows["release"] = row("release", "READY", "brain release-note tables (triage item 10); open rows are run work, not customer input")

    # data: rows in the frozen database; route a (real or publisher data) beats seeded rows
    snap = [str(p) for p in Path(model["project"]).glob("**/data-snapshot.zip")][:1] if model else []
    supplied = a.data if a.data and Path(a.data).exists() else None
    if before and isinstance((before.get("db") or {}).get("entities"), dict):
        ents = before["db"]["entities"]
        own = {k: v for k, v in ents.items() if not k.startswith("System.") and isinstance(v, int)}
        total, filled = sum(own.values()), sum(1 for v in own.values() if v)
        if total == 0:
            rows["data"] = row("data", "CANNOT JUDGE", f"the frozen database holds 0 rows outside System ({len(own)} entities): "
                               "the data rung would compare empty tables", "a demo data snapshot or a copy of a test database (route a)",
                               True, source="before.json")
        elif (w / "seed.log").is_file() and not (snap or supplied) and filled and \
                sum(1 for v in own.values() if 0 < v <= 3) >= 0.8 * filled:
            rows["data"] = row("data", "READY", f"{total} rows in {filled} of {len(own)} entities, seed_pg rows only (route b): "
                               "survival is judged, realistic states are not", "a demo data snapshot or test database copy, recommended",
                               fallback="seeded rows", source="before.json, seed.log")
        else:
            rows["data"] = row("data", "READY", f"{total} rows in {filled} of {len(own)} entities", source="before.json")
    elif snap or supplied:
        rows["data"] = row("data", "READY", f"route a: {supplied or snap[0]}", source=supplied or snap[0])
    else:
        rows["data"] = row("data", "NEEDS a demo data snapshot or test database copy",
                           "no publisher data-snapshot.zip and none supplied: seed_pg.py (route b) gives a few rows per entity, "
                           "enough for survival, not for realistic journeys (notif R2: 3 rows each, 57% of journeys failed on the old app)",
                           "a demo data snapshot or an anonymised copy of a test database", fallback="seeded rows",
                           source=(model or {}).get("project", ""))

    # rest: published contract and safe probes
    if inv is None:
        rows["rest"] = row("rest", "NEEDS the test inventory", "not read", "", False)
    elif not inv["pub_rest"]:
        rows["rest"] = row("rest", "READY", "no published REST operations: nothing to compare", source=inv["src"])
    elif inv["probes"]:
        rows["rest"] = row("rest", "READY", f"{inv['pub_rest']} published operations, {inv['probes']} safe GET probes (contract diff for the rest)",
                           supply="test payloads for write operations, recommended", source=inv["src"])
    else:
        rows["rest"] = row("rest", "NEEDS test payloads", f"{inv['pub_rest']} published operations, 0 safe GET probes: only the contract is compared",
                           "a test payload per write operation, or accept contract-only", fallback="contract only", source=inv["src"])

    # smoke: one login per role (smoke_users.py), checked against users.json after the baseline
    roles = [r for r in (model or {}).get("roles", []) if r != (model or {}).get("guest")]
    if users is not None and roles:
        missing = [r for r in roles if not (users.get(r) or {}).get("user")]
        rows["smoke"] = (row("smoke", "NEEDS test users for " + ", ".join(missing), f"{len(missing)} of {len(roles)} roles have no login in users.json",
                             "a test user per role (or a local login smoke_users.py can create)", True, source="users.json")
                         if missing else row("smoke", "READY", f"a login for every role ({len(roles)})", source="users.json"))
    elif roles:
        rows["smoke"] = row("smoke", "READY", f"{len(roles)} roles: smoke_users.py creates smoke_<role> per role on a copy",
                            source=model["mpr"])
    else:
        rows["smoke"] = row("smoke", "NEEDS the model (--app)", "user roles not read", "", False)
    rows["screens"] = row("screens", rows["smoke"]["status"] if rows["smoke"]["blocks"] else "READY",
                          "screenshots come from the smoke walk and the journeys of both apps", rows["smoke"]["supply"], rows["smoke"]["blocks"])

    # journeys: anonymous role, the old-app pass rate, confirmed processes
    jr, guest = [], (model or {}).get("guest")
    if jsum:
        c = jsum["coverage"]
        G, D = c.get("G") or 0, c.get("D") or 0
        fx = load_json(w / "fixture-check.json")
        fxs = f"; fixture_check: {fx['line']}" if fx and fx.get("line") else ""
        if G and D / G > DEFECT_MAX:
            jr.append(row("journeys", "CANNOT JUDGE", f"{D} of {G} {'actions' if c.get('A') is not None else 'journeys'} fail on the OLD app "
                          f"({100 * D // G}% > {int(DEFECT_MAX * 100)}%): the instrument is not measuring{fxs}",
                          "confirmed key-user processes (JOURNEY_BAR=processes), or demo data the old app passes on", True, source=jsrc))
    if guest and not any(guest in p.get("roles", []) for p in procs or []):
        jr.append(row("journeys", f"NEEDS a confirmed key-user process as {guest}",
                      f"guest access is on (role {guest}): the gate needs one confirmed process run as the anonymous role (rule S), "
                      f"and none is confirmed ({'no processes.md' if procs is None else str(len(procs)) + ' confirmed, none as ' + guest})",
                      f"a key user confirms one process an anonymous visitor follows (processes.md status: confirmed)", True,
                      source=(model or {}).get("mpr", "")))
    if not jr:
        notes = []
        if rows["data"]["fallback"] == "seeded rows":
            notes.append("generated action journeys on seeded rows are at risk (notif R2: 57% failed on the old app)")
        if not procs:
            notes.append("no confirmed key-user process: JOURNEY_BAR=processes would be INVALID, the action bar needs <= 30% failing on the old app")
        if jsum:
            c = jsum["coverage"]
            notes.insert(0, f"{c.get('D')} of {c.get('G')} fail on the old app (<= {int(DEFECT_MAX * 100)}%)")
        jr.append(row("journeys", "READY", "; ".join(notes) or "always-on set, generated actions and confirmed processes can run",
                      "confirmed key-user processes, recommended" if not procs else "", fallback="at risk" if notes and not jsum else "",
                      source=jsrc))
    rows["journeys"] = jr[0] if len(jr) == 1 else row("journeys", jr[0]["status"], " | ".join(r["why"] for r in jr),
                                                       "; ".join(r["supply"] for r in jr), True, source=", ".join(r["source"] for r in jr if r["source"]))

    # apis: every consumed endpoint answered by a test system, or by the stand-in (then a conditional PASS)
    tsys = read_test_systems(a.test_systems)
    standin, excluded = [], []
    if api is None:
        n = (facts or {}).get("rest_consumed", 0) + (facts or {}).get("odata_consumed", 0) + (facts or {}).get("web_services", 0)
        rows["apis"] = row("apis", "NEEDS the model (--app) or an apimock inventory",
                           f"consumed APIs not classified ({n} consumed calls in facts.json)" if facts else "consumed APIs not classified",
                           "", bool(n) or facts is None, source="facts.json" if facts else "")
    else:
        eps = api["endpoints"]
        excluded = sorted({e["system"] for e in eps if e["status"] == "EXCLUDED"})
        live = [e for e in eps if e["status"] != "EXCLUDED"]
        standin = sorted({e.get("module") or e["id"].split(":")[1].split(".")[0] for e in live} - set(tsys))
        unk = [e for e in live if e["status"] == "UNKNOWN" and (e.get("module") or "") not in tsys]
        line = f"apis {len(eps)} found · mocked {sum(1 for e in eps if e['status'] == 'MOCKED')} · excluded {len(eps) - len(live)} · unknown {len(unk)}"
        if not live:
            rows["apis"] = row("apis", "READY", line + ": no consumed API outside the excluded systems", source=api_src)
        elif unk:
            k = unknown_kinds(unk)
            rows["apis"] = row("apis", f"NEEDS {len(unk)} UNKNOWN endpoints classified or test-system URLs",
                               line + ": " + ", ".join(f"{n} {t}" for t, n in sorted(k.items(), key=lambda x: -x[1])),
                               f"test-system URLs for {', '.join(sorted({e.get('module') or '?' for e in unk}))}, or accept stand-in APIs "
                               "and classify each UNKNOWN endpoint (apimock --classify, seed data locations)", True, source=api_src)
        elif standin:
            rows["apis"] = row("apis", "NEEDS test-system URLs or accept stand-in APIs", line + ": every endpoint can be stood in",
                               f"test-system URLs for {', '.join(standin)}, or accept PASS on stand-in APIs", fallback="stand-in", source=api_src)
        else:
            rows["apis"] = row("apis", "READY", line + ": every system has a test URL", source=api_src)

    # connectors: proof values, mock signs and a test account per connector (triage item 12)
    mods = (model or {}).get("modules", [])
    import fnmatch
    import apimock
    csys = set(excluded)
    for s in (excludes or []):
        pats = (apimock.BUILTIN_EXCLUDE.get(s.lower()) or [f"*{s}*"])
        if any(fnmatch.fnmatch(m.lower(), p.lower()) for m in mods for p in pats if not p.startswith("host:")):
            csys.add(s)
    cm = w / "connectors.md"
    if not csys:
        rows["connectors"] = row("connectors", "READY", "no connector to an excluded system (Teamcenter) in the model or the API inventory")
    elif not cm.is_file():
        rows["connectors"] = row("connectors", "NEEDS connector proof values", f"{', '.join(sorted(csys))} connector present and no connectors.md "
                                 "(triage item 12): a connector page that only renders may be the app's mock fallback",
                                 "per connector: a read-only test account, the proof value only the real server returns per page, the mock fallback signs",
                                 fallback="except", source=(model or {}).get("mpr", ""))
    else:
        blocks = connector_blocks(cm.read_text())
        bad = [h for h, b in blocks if not re.search(r"(?im)^\s*-?\s*\**proof value", b)]
        nomock = [h for h, b in blocks if not re.search(r"(?i)mock|fallback", b)]
        if not blocks or bad or nomock:
            why = ("no connector block" if not blocks else
                   "; ".join(x for x in (f"no 'Proof value' line: {', '.join(bad)}" if bad else "",
                                         f"no mock fallback signs: {', '.join(nomock)}" if nomock else "") if x))
            rows["connectors"] = row("connectors", "NEEDS connector proof values", why + " (connectors.md, TC-1, MC-17)",
                                     "the proof value only the real server returns per connector page, and the mock fallback signs",
                                     fallback="except", source=str(cm))
        else:
            rows["connectors"] = row("connectors", "READY", f"{len(blocks)} connector block(s) with proof values and mock signs", source=str(cm))

    # scheduled events: no rung triggers them
    if inv is not None and inv["sched_on"]:
        rows["scheduled"] = row("scheduled", "NEEDS a decision per enabled event",
                                f"{inv['sched_on']} of {inv['sched']} scheduled events enabled; no rung triggers them (the data rung sees only the model)",
                                "per event: trigger once on a copy and name its proof, or accept it untested", fallback="untested", source=inv["src"])
    else:
        rows["scheduled"] = row("scheduled", "READY", "no enabled scheduled event" if inv else "test inventory not read")

    # verdict
    qual = []
    if standin and rows["apis"]["status"] != "READY":
        qual.append("on stand-in APIs: " + ", ".join(standin[:6]) + (f" +{len(standin) - 6}" if len(standin) > 6 else ""))
    if rows["data"]["fallback"] == "seeded rows":
        qual.append("on seeded rows")
    if rows["connectors"]["fallback"] == "except":
        qual.append("; ".join(f"except {s}: connector pages" for s in sorted(csys)))
    pass_txt = "PASS" + (f" ({'; '.join(qual)})" if qual else "")
    hard = [rows[r] for r in RUNGS if rows[r]["blocks"]]
    if hard:
        verdict = f"INVALID unless {'; '.join(r['rung'] + ': ' + (r['supply'] or r['status']) for r in hard)} (then at best: {pass_txt})"
        code = 3
    elif notread:  # a missing input is never "nothing there": no PASS claim until it is read
        verdict, code = f"NOT JUDGED until read: {'; '.join(notread)} (otherwise at best: {pass_txt})", 2
    else:
        verdict, code = pass_txt, 4 if qual else 0
    return {"tool": "readiness", "phase": phase, "verdict": "best reachable verdict: " + verdict, "exit": code,
            "not_read": notread, "model": (model or {}).get("mpr"), "rungs": [rows[r] for r in RUNGS]}


def render(res):
    out = [f"# Test readiness ({res['phase']})", "", res["verdict"], ""]
    out += ["| rung | status | why | customer supplies |", "|---|---|---|---|"]
    for r in res["rungs"]:
        st = r["status"] + (" (blocks)" if r["blocks"] else f" (fallback: {r['fallback']})" if r["fallback"] else "")
        out.append(f"| {r['rung']} | {st} | {r['why'].replace('|', '/')} | {r['supply'].replace('|', '/') or '-'} |")
    if res["not_read"]:
        out += ["", "Not read: " + "; ".join(res["not_read"])]
    return "\n".join(out) + "\n"


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("work")
    ap.add_argument("--app", help="project dir or .mpr of the OLD app (default: <work>/../app)")
    ap.add_argument("--inventory", help="test_inventory.py JSON or md (default: test-inventory.json, inventory.json, test-inventory.md)")
    ap.add_argument("--exclude", action="append", help="system no stand-in can replace (default Teamcenter; '' for none)")
    ap.add_argument("--classify", help="apimock --classify file (lines '<pattern> MOCKED # reason', ...)")
    ap.add_argument("--test-systems", help="lines '<System> <url> # note': the customer's test system per consumed system")
    ap.add_argument("--data", help="a demo data snapshot or test database dump the customer supplied")
    ap.add_argument("--journeys-summary", help="the old-app run_journeys summary.json (default: found under the work dir)")
    ap.add_argument("--md"); ap.add_argument("--json")
    a = ap.parse_args()
    w = Path(a.work)
    if not w.is_dir():
        print(f"readiness: {a.work}: not a directory (give the run's work dir)", file=sys.stderr)
        sys.exit(2)
    res = judge(w, a)
    md = render(res)
    Path(a.md or w / "readiness.md").write_text(md)
    Path(a.json or w / "readiness.json").write_text(json.dumps(res, indent=1, ensure_ascii=False) + "\n")
    print(md, end="")
    sys.exit(res["exit"])


if __name__ == "__main__":
    main()
