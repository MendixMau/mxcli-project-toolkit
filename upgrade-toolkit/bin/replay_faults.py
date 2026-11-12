#!/usr/bin/env python3
"""replay_faults.py: replay seeded faults through the STATIC judgement layers (quality plan item 8).

    replay_faults.py FAULTS.jsonl --apps-root DIR [--apps-root DIR2 ...] --work DIR [--out report.json]

FAULTS.jsonl holds one fault per line (the format in the seeded-fault set's FORMAT.md): id, app, doc, op
(set | delete | replace_text), path, and value / find+replace, plus the author's symptom and why_plausible. The app named
by a fault is looked up as APPS_ROOT/<app> in the first --apps-root that holds it.

For every fault:
  1. mutate  controls/lib/mutate_mpr.py applies the fault to a copy of the app (WORK/<id>/mutated). A fault that cannot be
             applied (no such app or document, a path that does not resolve, a find text not present) is an
             "INVALID seed": counted in s, never removed from the set.
  2. judge   each static layer compares the ORIGINAL app (old) with the MUTATED copy (new) and reports what it flags.
             A layer CATCHES the fault when its output flags a difference that names the mutated document, or a
             document that calls it (a caller, read from the references of either model). The layers are:
               L1b      bin/access_matrix.py diff      caught by a REVIEW line naming the document or a caller
               impact   bin/impact_map.py OLD NEW      caught by a change record naming the document or a caller
               actions  bin/action_inventory.py (OLD, once per app) + bin/impact_actions.py --impact
                        (the impact source above)       caught by a TOUCHED reason from the impact source naming it
               convert  bin/convertcheck.py --mappings  caught by a REVIEW row whose page is the document or a caller
               const    bin/constcheck.py OLD NEW       caught by a FAIL / REVIEW / INFO row naming the constant
               idcheck  bin/idcheck.py OLD NEW          caught by a RED / REVIEW / FAIL / info line naming the document
             Each layer is a measurement of its own tool: an error or a partial comparison is never read as "caught".
  3. runtime layers (L0 mx check, L1 behaviour rules for a version jump, L2 journeys, L3 critical set, L4 every page,
             L5 data, L6 sampled hand walk) need a running app and a build. They cannot run in this container, so every
             fault lists them as "not run (no runtime)". They are never counted caught and never dropped.

JUDGE vs SELECT. L1b, convert, const and idcheck JUDGE: a hit says "this difference is wrong or needs review".
impact and actions only SELECT: a hit says "this changed, walk it at runtime". In a fault-only replay every fault is a
change, so a selection hit is expected and proves nothing about wrongness; it is never counted as caught.

Output per fault:
  F01 caught by: L1b | selected for runtime walk by: impact, actions | missed by: convert, const, idcheck | not run: L0..L6
and the north-star line:
  caught c / seeded s (static judging layers); selected k (a runtime layer must judge them); unseen u (no layer saw it)
where s counts every fault line (INVALID seeds included), c the valid faults a judging layer caught, k the valid faults
only a selecting layer saw, and u the valid faults no static layer saw at all. A fault in a document that is Excluded
in the original app is INERT (not built, so it cannot misbehave at runtime): its layers still run, but it is reported
as "inert i" and counted in none of c, k, u.

Exit: 0 the replay completed (a measurement: a missed fault is a finding, not an error); 1 a malformed faults file;
2 usage (no such faults file or apps root, argparse errors).
"""
import argparse, json, os, re, shutil, subprocess, sys

BIN = os.path.dirname(os.path.abspath(__file__))
TK = os.path.abspath(os.path.join(BIN, ".."))
sys.path.insert(0, BIN)
sys.path.insert(0, os.path.join(TK, "controls", "lib"))
import mprmodel  # noqa: E402
import mutate_mpr  # noqa: E402  (copy_app: the one copy of an app's model files)

PY = sys.executable
MUTATE = os.path.join(TK, "controls", "lib", "mutate_mpr.py")
OPS = ("set", "delete", "replace_text")
STATIC = [("L1b", "access"), ("impact", "impact"), ("actions", "actions"), ("convert", "convert"),
          ("const", "const"), ("idcheck", "idcheck")]
NOT_RUN = [("L0", "mx check (needs mxbuild in a container)"), ("L1", "behaviour rules (per version jump)"),
           ("L2", "journeys (needs a running app)"), ("L3", "critical set (needs a running app)"),
           ("L4", "every page (needs a running app)"), ("L5", "data (needs a database)"),
           ("L6", "sampled hand walk (a person)")]
JUDGE = ("L1b", "convert", "const", "idcheck")
SELECT = ("impact", "actions")
TIMEOUT = 900


class Malformed(Exception):
    pass


def check_fault(obj, n):
    if not isinstance(obj, dict):
        raise Malformed(f"line {n}: not a JSON object")
    for key in ("id", "app", "doc", "op", "path"):
        if not isinstance(obj.get(key), str) or not obj.get(key):
            raise Malformed(f"line {n}: {key!r} must be a non-empty string")
    if "." not in obj["doc"]:
        raise Malformed(f"line {n}: doc {obj['doc']!r} is not Module.Name")
    if obj["op"] not in OPS:
        raise Malformed(f"line {n}: op {obj['op']!r} is not one of {', '.join(OPS)}")
    if obj["op"] == "set" and "value" not in obj:
        raise Malformed(f"line {n}: a set fault needs a value")
    if obj["op"] == "replace_text" and not (isinstance(obj.get("find"), str) and isinstance(obj.get("replace"), str)):
        raise Malformed(f"line {n}: a replace_text fault needs string find and replace")
    if "unchanged_doc" in obj and not isinstance(obj["unchanged_doc"], bool):
        raise Malformed(f"line {n}: unchanged_doc must be true or false")


def load_faults(path):
    faults, seen = [], set()
    with open(path, encoding="utf-8") as f:
        for n, line in enumerate(f, 1):
            if not line.strip():
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError as e:
                raise Malformed(f"line {n}: not JSON ({e})")
            check_fault(obj, n)
            if obj["id"] in seen:
                raise Malformed(f"line {n}: duplicate id {obj['id']}")
            seen.add(obj["id"])
            faults.append(obj)
    return faults


def run(cmd):
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=TIMEOUT)
        return p.returncode, p.stdout, p.stderr
    except subprocess.TimeoutExpired:
        return 124, "", f"timed out after {TIMEOUT}s"


def tail(s, n=1):
    lines = [x for x in (s or "").strip().splitlines() if x.strip()]
    return " | ".join(lines[-n:]) if lines else "(no output)"


def mentions(text, names):
    """True when a name occurs as a whole qualified name (Mod.Doc, not Mod.Doc2 and not Mod.Doc_X)."""
    for n in names:
        if re.search(r"(?<![\w.$])" + re.escape(n) + r"(?![\w$])", text):
            return True
    return False


def first(lines, k=3):
    return [x.strip()[:200] for x in lines[:k]]


class App:
    """One app of the apps root: its original copy, its model (for callers), and its action inventory."""

    def __init__(self, name, src, work):
        self.name, self.src = name, src
        self.dir = os.path.join(work, "orig", name)
        if os.path.isdir(self.dir):
            shutil.rmtree(self.dir)
        self.model = None
        self.callers = None
        self.actions = os.path.join(self.dir, "actions.json")
        self.actions_error = None
        self.noise = None
        mutate_mpr.copy_app(src, self.dir)  # self.dir now holds the .mpr and mprcontents/ only

    def load(self):
        if self.model is None:
            self.model = mprmodel.Model.load(self.dir)
            self.callers = self.model.callers_index()
        return self.model

    def inventory(self):
        rc, out, err = run([PY, os.path.join(BIN, "action_inventory.py"), self.dir, "--out", self.actions])
        if rc != 0:
            self.actions_error = f"action_inventory.py exit {rc}: {tail(err or out)}"
        return self.actions_error is None

    def noise_check(self, work):
        """The old app against itself: a difference here is noise, and would make a catch meaningless."""
        imp = os.path.join(work, "orig", self.name, "noise-impact.json")
        rc1, _, _ = run([PY, os.path.join(BIN, "impact_map.py"), self.dir, self.dir, "--out", imp])
        n_imp = None
        if rc1 == 0 and os.path.exists(imp):
            n_imp = len(json.load(open(imp, encoding="utf-8")).get("changes", []))
        rc2, out2, _ = run([PY, os.path.join(BIN, "access_matrix.py"), "diff", self.dir, self.dir])
        n_acc = sum(1 for x in out2.splitlines() if x.startswith("REVIEW "))
        self.noise = {"impact_changes": n_imp, "access_review": n_acc}
        return self.noise


def layer_access(ctx):
    rc, out, err = run([PY, os.path.join(BIN, "access_matrix.py"), "diff", ctx["old"], ctx["new"]])
    review = [x for x in out.splitlines() if x.startswith("REVIEW ")]
    hits = [x for x in review if mentions(x, ctx["names"])]
    if hits:
        return "caught", first(hits)
    if rc == 3 or rc not in (0, 1):
        return "error", [f"access_matrix.py exit {rc}: {tail(err or out)}"]
    return "missed", []


def layer_impact(ctx):
    imp = os.path.join(ctx["dir"], "impact.json")
    rc, out, err = run([PY, os.path.join(BIN, "impact_map.py"), ctx["old"], ctx["new"], "--out", imp])
    if rc != 0 or not os.path.exists(imp):
        return "error", [f"impact_map.py exit {rc}: {tail(err or out)}"]
    changes = json.load(open(imp, encoding="utf-8")).get("changes", [])
    hits = [c for c in changes if c.get("qn") in ctx["names"] or c.get("target") in ctx["names"] or c.get("doc") in ctx["names"]
            or mentions(str(c.get("detail", "")), ctx["names"])]
    if hits:
        return "caught", [f"{c['kind']} {c['qn']}: {c.get('detail', '')}" for c in hits[:3]]
    return "missed", []


def layer_actions(ctx):
    imp = os.path.join(ctx["dir"], "impact.json")
    if ctx["app"].actions_error:
        return "error", [ctx["app"].actions_error]
    if not os.path.exists(imp):
        return "error", ["no impact.json (the impact layer did not run)"]
    ia = os.path.join(ctx["dir"], "impact-actions.json")
    rc, out, err = run([PY, os.path.join(BIN, "impact_actions.py"), ctx["app"].actions, "--impact", imp, "--out", ia])
    if rc != 0 or not os.path.exists(ia):
        return "error", [f"impact_actions.py exit {rc}: {tail(err or out)}"]
    res = json.load(open(ia, encoding="utf-8"))["actions"]
    hits = [f"{a['id']}: {r['match']} ({r['detail']})" for a in res if a["touched"] for r in a["reasons"]
            if r["source"] == "impact" and r.get("match") in ctx["names"]]
    if hits:
        return "caught", hits[:3]
    return "missed", []


def layer_convert(ctx):
    jp = os.path.join(ctx["dir"], "convertcheck.json")
    rc, out, err = run([PY, os.path.join(BIN, "convertcheck.py"), "--mappings", ctx["old"], ctx["new"], "--json", jp])
    if rc not in (0, 1) or not os.path.exists(jp):
        return "error", [f"convertcheck.py exit {rc}: {tail(err or out)}"]
    rows = json.load(open(jp, encoding="utf-8"))
    hits = [f"REVIEW {r['page']}: {r['site']}" for r in rows if r.get("verdict") == "REVIEW" and r.get("page") in ctx["names"]]
    if hits:
        return "caught", hits[:3]
    return "missed", []


def layer_const(ctx):
    jp = os.path.join(ctx["dir"], "constcheck.json")
    rc, out, err = run([PY, os.path.join(BIN, "constcheck.py"), ctx["old"], ctx["new"], "--json", jp])
    if rc not in (0, 1) or not os.path.exists(jp):
        return "error", [f"constcheck.py exit {rc}: {tail(err or out)}"]
    rows = json.load(open(jp, encoding="utf-8"))
    hits = [f"{r['verdict']} {r['kind']} {r['name']}: {r.get('detail', '')}" for r in rows
            if r.get("verdict") in ("FAIL", "REVIEW", "INFO") and r.get("name") in ctx["names"]]
    if hits:
        return "caught", hits[:3]
    return "missed", []


def layer_idcheck(ctx):
    rc, out, err = run([PY, os.path.join(BIN, "idcheck.py"), ctx["old"], ctx["new"]])
    if rc not in (0, 1):
        return "error", [f"idcheck.py exit {rc}: {tail(err or out)}"]
    hits = [x for x in out.splitlines() if re.match(r"^(RED|REVIEW|FAIL|INFO|info|WARN)\b", x) and mentions(x, ctx["names"])]
    if hits:
        return "caught", first(hits)
    return "missed", []


LAYER_FN = {"L1b": layer_access, "impact": layer_impact, "actions": layer_actions, "convert": layer_convert,
            "const": layer_const, "idcheck": layer_idcheck}


def judge(fault, app, mut_dir, work, rid):
    """Run every static layer on OLD (the app) against NEW (the mutated copy). Returns the per-layer results."""
    app.load()
    mut_model = mprmodel.Model.load(mut_dir)
    doc = fault["doc"]
    callers = set(app.callers.get(doc, set())) | set(mut_model.callers_index().get(doc, set()))
    names = {doc} | callers
    fdir = os.path.join(work, rid)
    os.makedirs(fdir, exist_ok=True)
    ctx = {"old": app.dir, "new": mut_dir, "dir": fdir, "names": names, "app": app}
    results = {}
    for label, _ in STATIC:
        status, evidence = LAYER_FN[label](ctx)
        results[label] = {"status": status, "evidence": evidence}
    return results, sorted(callers)


def fmt_fault_line(rec):
    fid = rec["id"]
    if rec["invalid"]:
        return f"{fid} INVALID seed: {rec['invalid']} | not run: all layers"
    L = rec["layers"]
    caught = [k for k in JUDGE if L[k]["status"] == "caught"]
    selected = [k for k in SELECT if L[k]["status"] == "caught"]
    missed = [k + ("(error)" if L[k]["status"] == "error" else "") for k, _ in STATIC if L[k]["status"] != "caught"]
    flag = " (doc an upgrade would not normally touch)" if rec.get("unchanged_doc") else ""
    if rec.get("inert"):
        flag += " (INERT: the document is Excluded, not built)"
    return (f"{fid} caught by: {', '.join(caught) or 'none'} | selected for runtime walk by: "
            f"{', '.join(selected) or 'none'} | missed by: {', '.join(missed) or 'none'} | "
            f"not run: {', '.join(k for k, _ in NOT_RUN)}{flag}")


def verdict(rec):
    if rec.get("inert"):
        return "inert"
    L = rec["layers"]
    if any(L[k]["status"] == "caught" for k in JUDGE):
        return "caught"
    if any(L[k]["status"] == "caught" for k in SELECT):
        return "selected"
    return "unseen"


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("faults", help="faults.jsonl, one fault per line")
    ap.add_argument("--apps-root", action="append", required=True, metavar="DIR",
                    help="a folder holding the apps by name (repeatable; the first that holds the app wins)")
    ap.add_argument("--work", required=True, metavar="DIR", help="scratch folder for the copies and layer outputs")
    ap.add_argument("--out", metavar="REPORT.json", help="write the per-fault report here")
    a = ap.parse_args(argv)
    if not os.path.isfile(a.faults):
        print(f"replay_faults: {a.faults}: no such faults file", file=sys.stderr)
        return 2
    for r in a.apps_root:
        if not os.path.isdir(r):
            print(f"replay_faults: --apps-root {r}: no such folder", file=sys.stderr)
            return 2
    try:
        faults = load_faults(a.faults)
    except Malformed as e:
        print(f"replay_faults: {a.faults}: {e}", file=sys.stderr)
        return 1
    os.makedirs(a.work, exist_ok=True)
    print("not run (no runtime in this container): " + "; ".join(f"{k} {v}" for k, v in NOT_RUN))

    apps, recs = {}, []
    for idx, fault in enumerate(faults):
        rid = f"{idx:03d}-" + re.sub(r"[^A-Za-z0-9_.-]", "_", fault["id"])
        rec = {"id": fault["id"], "app": fault["app"], "doc": fault["doc"], "op": fault["op"], "path": fault["path"],
               "unchanged_doc": fault.get("unchanged_doc"), "invalid": None, "mutated": None, "layers": {}, "callers": []}
        recs.append(rec)
        src = next((os.path.join(r, fault["app"]) for r in a.apps_root
                    if os.path.isdir(os.path.join(r, fault["app"]))), None)
        if src is None:
            rec["invalid"] = f"app {fault['app']!r} is not under any --apps-root"
            print(fmt_fault_line(rec))
            continue
        if fault["app"] not in apps:
            try:
                apps[fault["app"]] = App(fault["app"], src, a.work)
            except (mutate_mpr.Usage, mutate_mpr.Fail, OSError) as e:
                rec["invalid"] = f"app {fault['app']!r} cannot be copied: {e}"
                print(fmt_fault_line(rec))
                continue
            apps[fault["app"]].inventory()
            apps[fault["app"]].noise_check(a.work)
            nz = apps[fault["app"]].noise
            print(f"noise {fault['app']}: impact {nz['impact_changes']} changes, access {nz['access_review']} REVIEW "
                  f"between the original and itself (must be 0)")
            if apps[fault["app"]].actions_error:
                print(f"actions {fault['app']}: {apps[fault['app']].actions_error}")
        app = apps[fault["app"]]
        mut_dir = os.path.join(a.work, rid, "mutated")
        if os.path.isdir(os.path.dirname(mut_dir)):
            shutil.rmtree(os.path.dirname(mut_dir))
        os.makedirs(os.path.dirname(mut_dir))
        rc, out, err = run([PY, MUTATE, json.dumps(fault, ensure_ascii=False), src, mut_dir])
        if rc != 0:
            rec["invalid"] = tail(err or out)
            print(fmt_fault_line(rec))
            continue
        rec["mutated"] = out.strip()
        results, callers = judge(fault, app, mut_dir, os.path.join(a.work, "layers"), rid)
        rec["layers"], rec["callers"] = results, callers
        od = app.model.docs.get(fault["doc"])
        rec["inert"] = bool(od is not None and od.data.get("Excluded"))
        print(fmt_fault_line(rec))
        print(f"      {rec['mutated']}")
        for label, _ in STATIC:
            v = results[label]
            if v["status"] == "caught":
                for e in v["evidence"][:1]:
                    print(f"      {label}: {e}")

    s = len(recs)
    inv = [r for r in recs if r["invalid"]]
    valid = [r for r in recs if not r["invalid"]]
    for r in valid:
        r["verdict"] = verdict(r)
    c = [r for r in valid if r["verdict"] == "caught"]
    k = [r for r in valid if r["verdict"] == "selected"]
    u = [r for r in valid if r["verdict"] == "unseen"]
    n = [r for r in valid if r["verdict"] == "inert"]
    R = len(k) + len(u)
    print(f"invalid seeds: {len(inv)}" + (f" ({', '.join(r['id'] for r in inv)})" if inv else ""))
    print(f"caught {len(c)} / seeded {s} (static judging layers); selected {len(k)} (a runtime layer must judge them); "
          f"unseen {len(u)} (no layer saw it)" + (f": {', '.join(r['id'] for r in u)}" if u else "")
          + (f"; inert {len(n)} (Excluded document, not built): {', '.join(r['id'] for r in n)}" if n else ""))
    if a.out:
        with open(a.out, "w", encoding="utf-8") as f:
            json.dump({"tool": "replay_faults.py", "faults_file": os.path.abspath(a.faults),
                       "not_run": dict(NOT_RUN), "static_layers": dict(STATIC),
                       "noise": {k: v.noise for k, v in apps.items()},
                       "judge_layers": list(JUDGE), "select_layers": list(SELECT),
                       "summary": {"seeded": s, "caught": len(c), "selected": len(k), "unseen": len(u), "inert": len(n),
                                   "invalid": len(inv), "needs_runtime": R},
                       "faults": recs}, f, indent=1, default=str)
        print(f"wrote {a.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
