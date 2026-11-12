#!/usr/bin/env python3
"""heal.py: classify every failing row of an upgrade run and apply the heals that belong to the TEST (steps/heal.md).

  heal.py plan     --work W [--round N]               classify, write heal.json / heal.md / the allow files / heal-plan.json
  heal.py patch    --work W                           apply the journey patches listed in heal-plan.json (row-select step)
  heal.py grids    --model X.mpr --out heal-grids.json  per page: its first list widget and entity (the row-select heal)
  heal.py merge    --work W --old DIR --new DIR       put the rerun journeys of the heal into the two stored summaries
  heal.py finalize --work W                           after the reruns and the gate: the result column from the final evidence
  heal.py summary  --work W                           one line for the gate summary (heal.json counts)
  heal.py nj       --work W                           the NEEDS-JUDGMENT text of the rows that stay open (options + recommendation)

Policy: heal the test side only. The app is never edited here, and a row that may be a defect of the upgrade is never
accepted: it stays open with options and a recommendation.

Classes (every failing row gets exactly one):
  startup-noise    differs between two starts of the SAME old app (the restart control, twin-old.md), so the upgrade did
                   not cause it. Heal: an allow line with that evidence as its reason (heal-allow.txt, printed as accepted).
  no-test-data     the page behind a failing journey shows an empty list. Heal: seed the same rows into the old and the new
                   database (seed_pg.py), rerun that journey on both.
  no-click-path    the generator found no click path to the action (or no role): needs a hand-written journey. No heal.
  outside-call     the only reason a journey was not generated is an external call. Heal: apimock.py stands in for the
                   system on the old and the new app (same answers), the journey is generated and run on both.
  test-setup       (seedname) the old app passes, the new one fails on an error dialog and its log names a SEEDED value as a missing
                   entity: seedname_fix.py makes the seeded entity/member names valid on both sides, owner note written
                   (heal-gate-notes.txt, gate-notes-effective.txt).
  test-setup       the harness, not the app: a runner that did not run (rerun), a button that exists only for a selected
                   row (a row-select step is inserted), a known harness log line (accepted with its reason), or a failure
                   the old app has too (listed, no heal).
  real-regression  the old app passes and the new one does not, or data/log rows were lost or a new ERROR appeared. No heal.
  likely-real      anything the rules above could not explain, and any heal that did not work. No heal.
"""
import argparse, glob, json, os, re, shutil, subprocess, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
CLASSES = ("startup-noise", "no-test-data", "no-click-path", "outside-call", "test-setup", "real-regression", "likely-real")
OPEN_CLASSES = ("real-regression", "likely-real")
JOURNEY_HEALS = ("rerun", "seed", "standin", "patch", "seedname")
# A log line the HARNESS causes, with the reason that goes next to it. Each entry carries the check on the run (the evidence).
HARNESS_LOG = [
    {"match": re.compile(r"SessionKeepAliveUpdatesInterval"), "must_name": "SessionTimeout",
     "pattern": "WARNING Configuration: Using derived value for SessionKeepAliveUpdatesInterval*",
     "needs": "the harness starts every app with SessionTimeout {timeout} ms (runapp.py UPG_SESSION_TIMEOUT) and the line itself names SessionTimeout",
     "reason": "test harness: runapp.py starts every app with SessionTimeout {timeout} ms, so the runtime derives the keep-alive interval; production sets its own"},
]
SELECT_GATED = re.compile(r"\$currentObject/[\w.]+\s*!=\s*empty")
EMPTY_LIST = re.compile(r"(no (items|data|results|rows|records)( found)?|showing 0|0 of 0|nothing to show)", re.I)
NEVER = re.compile(r"FAIL open (\S+): reached \"([^\"]+)\" never appeared")
SEEDED_NAME = re.compile(r"does not exist: (s\d+x\d+)\b")   # a synthetic seeded value (seed_pg.py: s<short>x<seq>) used as a model name
ERROR_DIALOG = re.compile(r"An error occurred|mx-underlay")
NEW_APP_LOGS = ("runtime-newjp.log", "runtime-healnew.log")
ROW = re.compile(r"^- (FAIL|REVIEW|INVALID|NEW_ENDPOINT) (\S+): (.*)$")


def jload(p, default=None):
    try:
        return json.load(open(p))
    except (OSError, ValueError):
        return default


def parse_diff_rows(path):
    rows = []
    if not os.path.isfile(path):
        return rows
    on = False
    for line in open(path, errors="replace"):
        if line.startswith("## All rows"):
            on = True
        elif on:
            m = ROW.match(line.rstrip("\n"))
            if m:
                rows.append({"verdict": m.group(1), "check": m.group(2), "detail": m.group(3)})
    return rows


def allow_pattern(detail):
    """diff.py --emit-allow's own escaping: the detail of the row is the pattern, wildcards escaped."""
    return "".join("[" + ch + "]" if ch in "*?[" else "?" if ch in "#\r\n" else ch for ch in detail.strip())


def counts_of(detail):
    m = re.search(r"(\d+)\s*->\s*(\d+)", detail)
    return (int(m.group(1)), int(m.group(2))) if m else None


# ----------------------------------------------------------------------------------------------------- model lookups
def grids(model, out):
    """host page qn -> {"grid": first list widget name, "entity": its entity} (the row-select heal needs the grid's name)."""
    sys.path.insert(0, str(HERE))
    import action_inventory as AI
    from mprmodel import Model
    m = Model.load(model)
    ents = {}   # persistable entity qn -> True
    for dm in m.of_type("DomainModels$DomainModel") + [x for x in m.docs.values() if x.type == "DomainModels$DomainModel"]:
        for e in AI.lst(dm.data.get("Entities")):
            if (e.get("MaybeGeneralization") or {}).get("Persistable") is not False:
                ents[f"{dm.module}.{e.get('Name')}"] = True

    def entity_of(x):
        """A list's entity: its data source, else the first qualified name inside the widget that is a persistable entity
        (a pluggable gallery keeps its source in a microflow or XPath, so the entity shows only as text)."""
        e = AI.first(x.get("DataSource"), "Entity") or AI.first(x.get("Object"), "Entity")
        if e:
            return e
        for q in re.findall(r"[A-Za-z_]\w*\.[A-Za-z_]\w*", json.dumps(x, default=str)):
            if q in ents:
                return q
        return ""
    res = {}
    for d in m.all_docs:
        if d.type not in AI.HOSTS or d.data.get("Excluded"):
            continue
        found = []

        def walk(x):
            if isinstance(x, list):
                for v in x:
                    walk(v)
            elif isinstance(x, dict):
                t = x.get("$Type", "")
                if x.get("Name") and (t in AI.LISTS or (t == "CustomWidgets$CustomWidget" and any(s in AI.wid(x) for s in AI.LIST_WIDGETS))):
                    ent = entity_of(x)
                    found.append({"grid": x["Name"], "entity": ent, "type": t.split("$")[-1] if t != "CustomWidgets$CustomWidget" else AI.wid(x)})
                for v in x.values():
                    walk(v)
        walk(d.data)
        if found:
            res[d.qn] = found[0]
    Path(out).write_text(json.dumps(res, indent=1, sort_keys=True) + "\n")
    print(f"heal grids: {len(res)} page(s) with a list widget, written to {out}")
    return res


# ----------------------------------------------------------------------------------------------------- classification
class Run:
    def __init__(self, W):
        self.W = Path(W)
        self.after = jload(self.W / "e2e-after/after/summary.json", {"journeys": {}})
        self.before = jload(self.W / "e2e-before-picked/before-picked/summary.json", {"journeys": {}})
        acts = jload(self.W / "actions.json", {"actions": []})
        self.actions = {a["id"]: a for a in acts.get("actions", [])}
        self.grids = jload(self.W / "heal-grids.json", {})
        plan = jload(self.W / "journeys" / "plan.json", {})   # the CURRENT plan: why a journey is skipped now (not the stored text)
        self.skipped = {x.get("id"): x for x in plan.get("skipped", []) if isinstance(x, dict)}
        self.twin_present = (self.W / "twin-old.md").is_file()
        self.twin = {r["check"]: r for r in parse_diff_rows(str(self.W / "twin-old.md")) if r["verdict"] in ("FAIL", "REVIEW")}
        self.prev = jload(self.W / "heal.json", {"rounds": [], "rows": []})
        self.done = {(r["id"], r["heal_kind"]) for r in self.prev.get("rows", []) if r.get("heal_kind") in JOURNEY_HEALS}
        # a row that was healed and is classified again keeps no heal_kind: the memory of what ran lives in its own file
        self.done |= {tuple(x) for x in jload(self.W / "heal-done.json", [])}

    def row(self, id_, check, cls, evidence, heal="none", kind=None, **kw):
        d = {"id": id_, "check": check, "class": cls, "evidence": evidence, "heal": heal, "result": "not rerun", "heal_kind": kind}
        d.update(kw)
        return d

    # ---- data and log rows (diff.md)
    def data_rows(self):
        out = []
        pre = self.W / "heal-pre-diff.md"   # the heal step runs diff.py itself: it comes before the gate writes diff.md
        for r in parse_diff_rows(str(pre if pre.is_file() else self.W / "diff.md")):
            if r["check"].startswith(("journeys", "screens", "smoke")):
                continue
            out.append(self.log_row(r) if r["check"].startswith("log.") else self.data_row(r))
        return out

    def data_row(self, r):
        c, det = r["check"], r["detail"]
        id_ = "data:" + c
        n = counts_of(det)
        if "gone" in det or "lost" in det or "dropped" in det or (n and n[1] < n[0]):
            return self.row(id_, c, "real-regression", f"{det}: rows or columns of the old data are missing after the upgrade")
        if c in self.twin:
            t = self.twin[c]
            why = f"start noise: {c} also differs between two starts of the SAME old app (twin-old.md: {t['detail']}), so the upgrade did not cause it"
            return self.row(id_, c, "startup-noise", why, heal="allow line written to heal-allow.txt, accepted with this reason", kind="allow",
                            allow=f"{c} {allow_pattern(det)} # {why}")
        if self.twin_present:
            return self.row(id_, c, "likely-real", f"{det}; the same check does not differ between two starts of the old app, so start noise does not explain it")
        return self.row(id_, c, "likely-real", f"{det}; no restart control (twin-old.md) to tell start noise from an upgrade change")

    def log_row(self, r):
        c, det = r["check"], r["detail"]
        id_ = "log:" + c + ":" + re.sub(r"\W+", "_", det)[:48]
        if c.endswith(("NEW_ERROR", "NEW_CRITICAL")) or det.startswith(("ERROR", "CRITICAL")):
            return self.row(id_, c, "real-regression", f"a new error signature after the upgrade: {det[:200]}")
        timeout = os.environ.get("UPG_SESSION_TIMEOUT", "30000")
        for h in HARNESS_LOG:
            if h["match"].search(det) and h["must_name"] in det:
                return self.row(id_, c, "test-setup", f"known harness line: {h['needs'].format(timeout=timeout)}",
                                heal="log allow line written to heal-log-allow.txt, accepted with its reason", kind="logallow",
                                logallow=f"{h['pattern']} # {h['reason'].format(timeout=timeout)}")
        return self.row(id_, c, "likely-real", f"{det[:200]}: not a known harness line")

    # ---- journey rows
    def journey_rows(self):
        out = []
        for jid, a in sorted(self.after.get("journeys", {}).items()):
            b = self.before.get("journeys", {}).get(jid, {})
            av = a.get("verdict")
            if av == "INVALID":
                out.append(self.invalid_row(jid, a, b))
            elif av == "FAIL":
                out.append(self.fail_row(jid, a, b))
        return out

    def again(self, id_, kind):
        return (id_, kind) in self.done

    def invalid_row(self, jid, a, b):
        id_, why, w = "journey:" + jid, a.get("why") or "", (a.get("why") or "").lower()
        if "runner did not run" in w:
            if self.again(id_, "rerun"):
                return self.row(id_, "journeys", "likely-real", "the runner did not run it, also after a rerun on both apps")
            return self.row(id_, "journeys", "test-setup", f"the runner wrote no findings for this journey's role pass (old app: {b.get('verdict')}); the journey never ran",
                            heal="rerun this journey on the old and the new app", kind="rerun", journey=jid)
        if "external-call" in w and not any(k in w for k in ("no-click-path", "no-role")):
            if self.again(id_, "standin"):
                sk = self.skipped.get(jid)
                if sk and "external-call" not in " ".join(sk.get("reasons") or []):
                    return self.row(id_, "journeys", "no-click-path", f"with the stand-in the external call is no longer the reason; it is now skipped for another one: {sk.get('why', '')[:180]} ({', '.join(sk.get('reasons') or [])})")
                return self.row(id_, "journeys", "likely-real", f"generated against the stand-in and still INVALID: {why[:160]}")
            return self.row(id_, "journeys", "outside-call", f"not generated, its only reason is an external call ({why[:120]})",
                            heal="generate with --standin, run on both apps against the same apimock stand-in", kind="standin", journey=jid)
        if "external-call" in w:
            return self.row(id_, "journeys", "no-click-path", f"no click path reaches it ({why[:150]}); it also calls an outside system, so a stand-in alone would not make it runnable")
        if any(k in w for k in ("no-click-path", "no-role", "anonymous role", "no menu item", "navigation profile", "combobox", "name-collision", "profile", "skipped")):
            return self.row(id_, "journeys", "no-click-path", f"{why[:200]}: needs a hand-written journey or a role the generator can walk as")
        return self.row(id_, "journeys", "likely-real", f"INVALID: {why[:200] or 'no reason stored'}")

    def fail_row(self, jid, a, b):
        id_ = "journey:" + jid
        npp = " | ".join(a.get("not_pass") or [])
        bv = b.get("verdict")
        if bv == "PASS":
            names = self.seeded_names() if ERROR_DIALOG.search(npp) else []
            if names and not self.again(id_, "seedname"):
                return self.row(id_, "journeys", "test-setup",
                                f"the new app logs 'does not exist: {', '.join(names)}' (a seeded test value used as an entity or member name) and this journey fails on an error dialog "
                                f"that the old app never shows: {npp[:120]}. Behaviour change: a Data widgets Combo box now loads its options when the page opens, the old one when the dropdown opens, "
                                "so an invalid configured entity name errors on page open now",
                                heal="make the seeded entity and member names valid in the old and the new database (seedname_fix.py), rerun on both", kind="seedname",
                                journey=jid, names=names)
            if names:
                return self.row(id_, "journeys", "real-regression", f"still fails after the seeded names were made valid: {npp[:260]}")
            return self.row(id_, "journeys", "real-regression", f"passes on the old app, fails on the new one: {npp[:260]}")
        m = NEVER.search(npp)
        if m:
            host, ready = m.group(1), m.group(2).replace(".mx-name-", "")
            ent = self.actions.get(f"{host}.{ready}") or {}
            gated = [s for s in ent.get("shown_if") or [] if SELECT_GATED.search(s)]
            g = self.grids.get(host)
            if self.again(id_, "patch") or self.again(id_, "seed"):
                return self.row(id_, "journeys", "likely-real", f"still fails after the heal ({host}: {ready} never appeared); old app: {bv}")
            if self.empty_list(a):
                return self.row(id_, "journeys", "no-test-data", f"the page {host} shows an empty list (screenshot text), {ready} needs a row",
                                heal=f"seed 3 rows of {(g or {}).get('entity')} into the old and the new database, rerun on both" if (g or {}).get("entity") else "no list entity found",
                                kind="seed" if (g or {}).get("entity") else None, journey=jid, entity=(g or {}).get("entity"))
            if gated and g:
                return self.row(id_, "journeys", "test-setup",
                                f"{ready} on {host} is shown only for a SELECTED row ({gated[0][:110]}); the journey never selects one (old app: {bv}, same step)",
                                heal=f"a step 'select the first row of {g['grid']}' is inserted before the click", kind="patch",
                                journey=jid, host=host, ready=ready, grid=g["grid"])
        if bv == "FAIL":
            return self.row(id_, "journeys", "test-setup", f"fails on the old app too, same journey: {npp[:200]}; not caused by the upgrade, no automatic heal")
        return self.row(id_, "journeys", "likely-real", f"fails on the new app ({npp[:200]}); old app: {bv}")

    def seeded_names(self):
        """Seeded values the NEW app's journey logs name as a missing entity or member ('Entity does not exist: s294x2')."""
        out = set()
        for n in NEW_APP_LOGS:
            f = self.W / "logs" / n
            if f.is_file():
                out |= set(SEEDED_NAME.findall(f.read_text(errors="replace")))
        return sorted(out)

    def empty_list(self, a):
        for s in a.get("shots") or []:
            if "NOT-REACHED" in s:
                t = self.W / "e2e-after" / (s[:-4] + ".txt")
                if t.is_file() and EMPTY_LIST.search(t.read_text(errors="replace")):
                    return True
        return False


# ----------------------------------------------------------------------------------------------------- plan
def write_text(p, s):
    Path(p).write_text(s)


def do_plan(W, rnd):
    W = Path(W)
    r = Run(W)
    rows = r.data_rows() + r.journey_rows()
    prev = {(x["id"], x.get("heal_kind")) for x in r.prev.get("rows", [])}
    hdr = "# written by heal.py: one line per row accepted as start noise / known harness line, the evidence is the reason\n"
    write_text(W / "heal-allow.txt", hdr + "".join(a + "\n" for a in sorted({x["allow"] for x in rows if x.get("allow")})))
    write_text(W / "heal-log-allow.txt", hdr + "".join(a + "\n" for a in sorted({x["logallow"] for x in rows if x.get("logallow")})))
    for nm in ("allow", "log-allow"):   # what the gate reads: the person's file first, then the heal's
        txt = ""
        for f in (W / f"{nm}.txt", W / f"heal-{nm}.txt"):
            if f.is_file():
                t = f.read_text()
                txt += t if t.endswith("\n") or not t else t + "\n"
        write_text(W / f"{nm}-effective.txt", txt)
    patches = [x for x in rows if x.get("heal_kind") == "patch"]
    rerun = {x["journey"] for x in rows if x.get("heal_kind") in ("rerun", "patch", "seed", "seedname")}
    seednames = sorted({n for x in rows if x.get("heal_kind") == "seedname" for n in x.get("names", [])})
    standin = sorted({x["journey"] for x in rows if x.get("heal_kind") == "standin"})
    seeds = sorted({x["entity"] for x in rows if x.get("heal_kind") == "seed" and x.get("entity")})
    new_heals = sum(1 for x in rows if x.get("heal_kind") and (x["id"], x["heal_kind"]) not in prev)
    plan = {"round": rnd, "rerun": sorted(rerun | set(standin)), "seed": seeds, "seedname": seednames, "standin": standin, "new_heals": new_heals,
            "patches": [{k: x[k] for k in ("journey", "host", "ready", "grid")} for x in patches]}
    write_text(W / "heal-plan.json", json.dumps(plan, indent=1) + "\n")
    done = sorted(r.done | {(x["id"], x["heal_kind"]) for x in rows if x.get("heal_kind") in JOURNEY_HEALS})
    write_text(W / "heal-done.json", json.dumps(done) + "\n")
    ids = {x["id"] for x in rows}
    carried = [x for x in r.prev.get("rows", []) if x["id"] not in ids and x.get("heal_kind")]
    res = {"rounds": r.prev.get("rounds", []) + [{"round": rnd, "new_heals": new_heals, "rows": len(rows)}], "rows": rows + carried}
    recheck_data(W, res)
    write_text(W / "heal.json", json.dumps(res, indent=1) + "\n")
    write_md(W, res)
    write_notes(W, res)
    print(f"heal plan round {rnd}: {len(rows)} failing row(s) classified, {new_heals} new heal(s); rerun {len(plan['rerun'])} journey(s), "
          f"seed {len(seeds)} entit(y/ies), stand-in {len(standin)} journey(s)")
    print("  " + class_line(res))
    print(f"CHANGED {new_heals}")


def write_notes(W, res):
    """Owner-facing lines for what a heal changed in the TEST DATA because of a behaviour change of the new version.
    heal-gate-notes.txt is the heal's own file; gate-notes-effective.txt = the person's gate-notes.txt + it (the diff step passes
    the effective file to the gate, which lists every line as 'needs a decision': a healed row must not hide a production risk)."""
    W = Path(W)
    sn = [x for x in res["rows"] if x.get("heal_kind") == "seedname"]
    lines = []
    if sn:
        names = sorted({n for x in sn for n in x.get("names", [])})
        lines.append(f"Behaviour change seen through a test-data heal ({len(sn)} journey(s), seeded value(s) {', '.join(names)}): the new app raises "
                     "'Entity does not exist' on pages the old app opened without error. Likely cause: a Data widgets Combo box now loads its options when the page opens, "
                     "the old one when the dropdown opens, so a configured entity or member name that is empty or wrong now shows an error dialog on page open, not on dropdown open. "
                     "The test data was made valid on both sides (seedname_fix.py); check the production configuration for an empty or wrong entity name before go-live.")
    write_text(W / "heal-gate-notes.txt", "# written by heal.py: behaviour changes the test-data heals hid; each line is an owner decision item\n" + "".join(l + "\n" for l in lines))
    txt = ""
    f = W / "gate-notes.txt"
    if f.is_file():
        t = f.read_text()
        txt = t if t.endswith("\n") or not t else t + "\n"
    write_text(W / "gate-notes-effective.txt", txt + "".join(l + "\n" for l in lines))


def class_line(res):
    c = {}
    for x in res["rows"]:
        c[x["class"]] = c.get(x["class"], 0) + 1
    return "classes: " + ", ".join(f"{k} {c[k]}" for k in CLASSES if c.get(k))


def do_patch(W):
    """Insert 'select the first row of <grid>' before the gated click. Originals are kept in heal/journeys-orig/."""
    W = Path(W)
    plan = jload(W / "heal-plan.json", {"patches": []})
    done = []
    orig = W / "heal" / "journeys-orig"
    for x in plan["patches"]:
        hits = glob.glob(str(W / "journeys" / "journeys" / "*" / (x["journey"] + ".journey.json")))
        if not hits:
            continue
        f = Path(hits[0])
        d = json.load(open(f))
        if d.get("_heal"):
            done.append(x["journey"])   # patched in an earlier call
            continue
        steps = d.get("steps", [])
        want = ".mx-name-" + x["ready"]
        hit = next((i for i, s in enumerate(steps) if (s.get("ui") or {}).get("ready") == want and s.get("name", "").startswith("open " + x["host"])), None)
        if hit is None:
            continue
        dest = orig / f.parent.name / f.name
        if not dest.exists():
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(f, dest)
        s = steps[hit]
        absent = (s.get("ui") or {}).get("textAbsent")
        s["ui"] = dict(s["ui"], ready=".mx-name-" + x["grid"])
        row = {"do": "row", "widget": x["grid"]}
        # the row is picked right before the click on the gated widget: a fill on the page (a search box) would drop an earlier selection
        slot = next(((i, k) for i in range(hit + 1, len(steps)) for k, ac in enumerate(steps[i].get("actions") or [])
                     if ac.get("do") == "click" and ac.get("widget") == x["ready"]), None)
        if slot:
            steps[slot[0]]["actions"].insert(slot[1], row)
        else:
            steps.insert(hit + 1, {"name": f"select the first row of {x['grid']} on {x['host']} (heal: {x['ready']} is shown only for a selected row)",
                                   "actions": [row], "ui": dict({"ready": want}, **({"textAbsent": absent} if absent else {}))})
        d["_heal"] = f"row of {x['grid']} selected before the click on {x['ready']} (shown only for a selected row)"
        f.write_text(json.dumps(d, indent=1) + "\n")
        done.append(x["journey"])
    print(f"heal patch: {len(done)} of {len(plan['patches'])} journey(s) patched (originals in {orig})")
    return done


def recheck_data(W, res):
    """The result column of the data and log rows: diff.py again on the same two snapshots, with the effective allow files."""
    bj, aj = W / "before.json", W / "after.json"
    if not (bj.is_file() and aj.is_file()):
        return
    md = W / "heal-diff.md"
    subprocess.run([sys.executable, str(HERE / "diff.py"), str(bj), str(aj), "--md", str(md), "--allow", str(W / "allow-effective.txt"),
                    "--log-allow", str(W / "log-allow-effective.txt")], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    final, on = {}, False
    if md.is_file():
        for line in open(md, errors="replace"):
            if line.startswith("## All rows"):
                on = True
            elif on:
                m = re.match(r"^- (\S+) (\S+): (.*)$", line.rstrip("\n"))
                if m:
                    final.setdefault(m.group(2), []).append((m.group(1), m.group(3)))
    for x in res["rows"]:
        if not x["id"].startswith(("data:", "log:")):
            continue
        rs = final.get(x["check"], [])
        acc = [d for v, d in rs if v == "PASS*" and "(accepted: " in d]
        opn = [v for v, d in rs if v in ("FAIL", "REVIEW", "INVALID", "NEW_ENDPOINT")]
        if x.get("heal_kind") and acc and not opn:
            x["result"] = "accepted: " + acc[0].split("(accepted: ", 1)[1].rstrip(")")[:220]
        elif opn:
            x["result"] = "open (" + "/".join(sorted(set(opn))) + ")"
        else:
            x["result"] = "no longer a row"


def write_md(W, res):
    L = ["# Heal report", "", "Every failing row has one class. Heals touch the test, never the app.", "", class_line(res), "",
         "| id | class | heal | result |", "|---|---|---|---|"]
    skipped = 0
    for x in res["rows"]:
        if x["class"] == "no-click-path":
            skipped += 1
            continue
        L.append(f"| {x['id'][:90]} | {x['class']} | {x['heal'][:90]} | {x['result'][:130]} |")
    L += ["", f"{skipped} journey row(s) of class no-click-path are counted above and listed in heal.json (no heal exists for them: each needs a hand-written journey).", "",
          "Rounds: " + ", ".join(f"round {r['round']}: {r['new_heals']} new heal(s)" for r in res["rounds"]), ""]
    write_text(Path(W) / "heal.md", "\n".join(L) + "\n")


# ----------------------------------------------------------------------------------------------------- merge reruns
def merge(W, old_dir, new_dir):
    """The rerun journeys' rows replace the stored ones; the stored summaries are kept as summary.pre-heal.json."""
    W = Path(W)
    sys.path.insert(0, str(HERE))
    jset = None
    try:
        import run_journeys as RJ
        jset = RJ.journey_set(str(W / "journeys"))
    except Exception as e:  # noqa: BLE001
        print(f"heal merge: cannot hash the journey set ({e}); the stored hash stays", file=sys.stderr)
    n = 0
    for src, dst, dstw in ((Path(new_dir) / "after/summary.json", W / "e2e-after/after/summary.json", W / "e2e-after"),
                           (Path(old_dir) / "before-picked/summary.json", W / "e2e-before-picked/before-picked/summary.json", W / "e2e-before-picked")):
        s, d = jload(src), jload(dst)
        if not s or not d:
            print(f"heal merge: {src if not s else dst} missing, nothing merged", file=sys.stderr)
            continue
        bak = dst.with_name("summary.pre-heal.json")
        if not bak.exists():
            shutil.copy2(dst, bak)
        for jid, row in s["journeys"].items():
            row.pop("compare", None)
            row.pop("screen", None)
            d["journeys"][jid] = row
        if jset:
            d["journey_set"] = jset
        d["healed"] = sorted(set(d.get("healed", [])) | set(s["journeys"]))
        dst.write_text(json.dumps(d, indent=2) + "\n")
        art_src, art_dst = src.parent.parent / "engine" / "artifacts", dstw / "engine" / "artifacts"
        if art_src.is_dir() and art_dst.is_dir():
            for jid in s["journeys"]:
                for f in glob.glob(str(art_src / (jid + "-*"))):
                    shutil.copy2(f, art_dst / os.path.basename(f))
        # the compared runs read shots-<role>/ (shotdiff pairs by file name): the rerun's shots replace the stale ones of the
        # same journey there, or the screens of a healed PASS row stay NOT-REACHED / missing on one side (run2: 22 pairs INVALID)
        for sd in sorted(glob.glob(str(src.parent / "shots-*"))):
            if not os.path.isdir(sd):
                continue
            for jid in s["journeys"]:
                fresh = [f for f in glob.glob(os.path.join(sd, jid + "-step*")) if os.path.isfile(f)]
                if not fresh:
                    continue
                dd = dstw / dst.parent.name / os.path.basename(sd)
                dd.mkdir(parents=True, exist_ok=True)
                for f in glob.glob(str(dd / (jid + "-step*"))):
                    os.remove(f)
                for f in fresh:
                    shutil.copy2(f, dd / os.path.basename(f))
        n = len(s["journeys"])
    print(f"heal merge: {n} journey(s) merged into the stored summaries")


# ----------------------------------------------------------------------------------------------------- finalize / summary / nj
def finalize(W):
    W = Path(W)
    res = jload(W / "heal.json")
    if not res:
        print("heal finalize: no heal.json", file=sys.stderr)
        return 1
    after = jload(W / "e2e-after/after/summary.json", {"journeys": {}})
    a, b = after["journeys"], jload(W / "e2e-before-picked/before-picked/summary.json", {"journeys": {}})["journeys"]
    healed = set(after.get("healed", []))
    for x in res["rows"]:
        if not x["id"].startswith("journey:"):
            continue
        j = x["id"][8:]
        if j not in a or not (j in healed or x.get("heal_kind") in JOURNEY_HEALS):
            continue
        av, bv = a[j]["verdict"], b.get(j, {}).get("verdict", "absent")
        if av == "PASS" and bv == "PASS":
            x["result"] = "passes on the old and the new app"
        elif av == "PASS":
            x["result"] = f"passes on the new app (old app {bv})"
        elif bv == "PASS":
            x["result"], x["class"] = "REGRESSION: passes on the old app, fails on the new one", "real-regression"
        else:
            x["result"] = f"still {av} on the new app, old app {bv}"
            if x.get("heal_kind") in JOURNEY_HEALS:
                x["class"] = "likely-real"
    for x in res["rows"]:   # a rerun on the healed base that passes closes an earlier open class (a probe on a plain base had put it there)
        if x["id"].startswith("journey:") and x["class"] in OPEN_CLASSES and x.get("heal_kind") in JOURNEY_HEALS \
                and x["result"].startswith("passes"):
            x["class"] = "test-setup"
    gs = (W / "gate-summary.md").read_text(errors="replace") if (W / "gate-summary.md").is_file() else ""
    res["gate_rungs"] = {m.group(1): m.group(2).strip() for m in re.finditer(r"^\| \d+ \| (\w+) \| ([A-Z* ]+?) \|", gs, re.M)}
    write_text(W / "heal.json", json.dumps(res, indent=1) + "\n")
    write_md(W, res)
    return 0


def summary(W):
    res = jload(Path(W) / "heal.json")
    if not res:
        print("heal: not run")
        return
    acc = sum(1 for x in res["rows"] if x["result"].startswith("accepted"))
    ok = sum(1 for x in res["rows"] if x["result"].startswith("passes"))
    op = [x for x in res["rows"] if x["class"] in OPEN_CLASSES]
    print(f"heal: {len(res['rows'])} failing row(s) classified, {acc} accepted with a written reason, {ok} journey(s) pass after the heal, "
          f"{len(op)} stay open ({sum(1 for x in op if x['class'] == 'real-regression')} real-regression, "
          f"{sum(1 for x in op if x['class'] == 'likely-real')} likely-real); {class_line(res)}")


OPTIONS = {
    "real-regression": ("fix the app (the upgrade changed behaviour) | accept the change as intended, in writing | the old behaviour was wrong, say so in writing",
                        "fix the app: the old version passes it, so a person must see why the new one does not"),
    "likely-real": ("read the evidence and classify it | fix the app | accept in writing with a reason",
                    "open the screenshot or log line named in the evidence first; most of these resolve in minutes"),
}


def nj_text(W):
    res = jload(Path(W) / "heal.json")
    if not res:
        return ""
    groups = {}
    for x in res["rows"]:
        if x["class"] in OPEN_CLASSES:
            groups.setdefault(x["class"], []).append(x)
    out = []
    for cls in OPEN_CLASSES:
        rows = groups.get(cls)
        if not rows:
            continue
        opts, rec = OPTIONS[cls]
        out.append(f"{cls}: {len(rows)} row(s) the heal step could not explain away\n")
        out += [f"- `{x['id']}`: {x['evidence'][:240]} (result: {x['result']})" for x in rows[:12]]
        if len(rows) > 12:
            out.append(f"- ... and {len(rows) - 12} more in heal.json")
        out.append(f"\nOptions: {opts}.\nRecommendation: {rec}.\n")
    return "\n".join(out)


def reshoot_plan(W):
    """Journeys whose compared runs hold no usable screenshots of their own: the healed ones (their rows were merged from
    reruns whose folders a later rerun deleted) and the likely-real ones (no old run). Printed as JSON: ids to rerun on a
    plain base, ids to rerun on the seedname base with the seeded values (seedname_fix.py --value)."""
    W = Path(W)
    after = jload(W / "e2e-after/after/summary.json", {"journeys": {}})
    res = jload(W / "heal.json", {"rows": []})
    ids = set(after.get("healed", []))
    names, sn_ids = set(), set()
    for x in res.get("rows", []):
        if not x.get("id", "").startswith("journey:"):
            continue
        j = x["id"][8:]
        if x.get("class") == "likely-real":
            ids.add(j)
        if x.get("heal_kind") == "seedname":
            sn_ids.add(j)
            names.update(x.get("names", []))
    ids |= sn_ids
    ids = {j for j in ids if j in after["journeys"]}
    print(json.dumps({"rerun": sorted(ids - sn_ids), "seedname_ids": sorted(sn_ids & ids), "seedname": sorted(names)}))


def nats_plan(W):
    """Journeys to run again once a NATS broker is up (natsfixture.py): every journey with a baseline-defect evidence line
    (the old app failed at the NATS dialog), plus the seedname rows with their seeded values (they need the same base).
    Printed as JSON: ids to rerun, seedname values."""
    W = Path(W)
    after = jload(W / "e2e-after/after/summary.json", {"journeys": {}})
    ids = set()
    ev = W / "baseline-evidence.txt"
    if ev.is_file():
        for line in ev.read_text(errors="replace").splitlines():
            line = line.strip()
            if line and not line.startswith("#"):
                ids.add(line.split()[0])
    names = set()
    for x in jload(W / "heal.json", {"rows": []}).get("rows", []):
        if x.get("heal_kind") == "seedname" and x.get("id", "").startswith("journey:"):
            ids.add(x["id"][8:])
            names.update(x.get("names", []))
    ids = {j for j in ids if j in after["journeys"]}
    print(json.dumps({"rerun": sorted(ids), "seedname": sorted(names)}))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("plan")
    p.add_argument("--work", required=True)
    p.add_argument("--round", type=int, default=1)
    p = sub.add_parser("grids")
    p.add_argument("--model", required=True)
    p.add_argument("--out", required=True)
    p = sub.add_parser("reshoot-plan")
    p.add_argument("--work", required=True)
    p = sub.add_parser("nats-plan")
    p.add_argument("--work", required=True)
    p = sub.add_parser("merge")
    p.add_argument("--work", required=True)
    p.add_argument("--old", required=True)
    p.add_argument("--new", required=True)
    for n in ("patch", "finalize", "summary", "nj"):
        p = sub.add_parser(n)
        p.add_argument("--work", required=True)
    a = ap.parse_args()
    if a.cmd == "plan":
        do_plan(a.work, a.round)
    elif a.cmd == "patch":
        do_patch(a.work)
    elif a.cmd == "grids":
        grids(a.model, a.out)
    elif a.cmd == "reshoot-plan":
        reshoot_plan(a.work)
    elif a.cmd == "nats-plan":
        nats_plan(a.work)
    elif a.cmd == "merge":
        merge(a.work, a.old, a.new)
    elif a.cmd == "finalize":
        return finalize(a.work)
    elif a.cmd == "summary":
        summary(a.work)
    elif a.cmd == "nj":
        print(nj_text(a.work))
    return 0


if __name__ == "__main__":
    sys.exit(main())
