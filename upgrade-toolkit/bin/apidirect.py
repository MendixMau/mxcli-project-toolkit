#!/usr/bin/env python3
"""apidirect.py: test every consumed REST call directly, on the old and the new app, against the same stand-in.

Why: the apis rung used to count an outside endpoint as tested only when a browser journey happened to trigger it. In a
field run 16 of 170 stand-in endpoints were hit, because the calls sit deep in flows the UI cannot reach. What an upgrade
can break in a REST integration is request building (location template, query and path parameters, headers, export
mapping, body), response reading (import mapping, object graph, date and number parsing) and error handling. All three
can be seen without a browser: call the microflow that holds the Call REST action, on both apps, and compare what was
SENT to the stand-in and what was READ back.

  apidirect.py inventory OLD.mpr [NEW.mpr] --side old|new --out calls.json [--exclude ..] [--classify F] [--recorded D]
  apidirect.py gen    calls.json --out test.mdl [--recipes F]      MDL of the test-only module (ApiDirectTest)
  apidirect.py prepare calls.json --app DIR --mxcli PATH [--recipes F]   apply it to a THROWAWAY copy of the app
  apidirect.py drive  calls.json --side S --app-url U --standin U --out results-S.jsonl --user U --password P
  apidirect.py compare --state DIR [--classify F]              old vs new: DIR/direct.json, DIR/direct.md
  apidirect.py check  --state DIR                              the rows of the gate's apis rung

The driver (no change to the app): a throwaway COPY of the app, old and new alike and never committed, gets one module
ApiDirectTest with one microflow per REST-calling microflow. Each builds its inputs (a seeded row when the entity has
one, else an object with sample values; strings, numbers, enumerations and dates get fixed samples, so both sides get
the same input), calls the original microflow and returns its result. The runtime's own client API (/xas/ executeaction)
runs it as a test user, and returns the returned objects with their attribute values: that is the "parsed result". The
module role of the wrappers is added to ONE user role of the copy only.

Per call, three runs: the stand-in answers normally (ok), with a 500 (500), and with a 200 whose body is not JSON
(malformed). Before each run the driver tells the stand-in which call and side it is (/__ad/call), and the stand-in
logs method, path, query, headers (secrets reduced to their scheme) and body of every request it gets for that run.

Classes per endpoint (apimock inventory id), from compare:
  PASS     the old and the new app sent the same request(s) and read the same result, in all three runs
  FAIL     they differ: a CANDIDATE regression. Test artefacts first (shared routes, padded sample values, seed
           mismatches), then the upgrade. FAIL is never a finding until the evidence says so.
  INVALID  could not be measured, with the reason: needs input recipe (an input could not be built), the wrapper did
           not build, the call never reached the endpoint with the seeded inputs, the microflow is not in the build
  INFO     a system the classification excludes (an identity provider): no stand-in answers for it; "check at deploy"
Volatile values (GUIDs, ids, timestamps, durations) are normalised before comparing.
"""
import argparse, copy, hashlib, http.cookiejar, json, os, re, shutil, subprocess, sys, time, urllib.error, urllib.parse, urllib.request
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import apimock  # noqa: E402
import mprmodel  # noqa: E402

TESTMOD, ROLE = "ApiDirectTest", "Tester"
MODES = ("ok", "500", "malformed")
CALL_TYPES = ("Microflows$RestCallAction",) + apimock.CALL_TYPES
STRING_DEFAULT = "TEST_{}"
DATE_SAMPLE = "parseDateTimeUTC('2024-01-15 10:30:00', 'yyyy-MM-dd HH:mm:ss')"
VOLATILE_KEY = re.compile(r"(date|time|timestamp|expire|expiry|created|changed|duration|elapsed|nonce|jti|iat|exp)$|^(\$?id|guid|hash)$", re.I)
GUID = re.compile(r"\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b", re.I)
ISO = re.compile(r"\b\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(?:[.,]\d+)?(?:Z|[+-]\d{2}:?\d{2})?\b")
LONGNUM = re.compile(r"(?<![\w.])\d{10,}(?![\w.])")


def die(msg):
    print(f"apidirect: {msg}", file=sys.stderr)
    sys.exit(2)


# ------------------------------------------------------------------------------------------------ inventory
def kind_of(t):
    """DataTypes$X -> a parameter kind."""
    n = (t or {}).get("$Type", "").split("$")[-1]
    return {"StringType": "string", "IntegerType": "integer", "LongType": "integer", "DecimalType": "decimal",
            "FloatType": "decimal", "BooleanType": "boolean", "DateTimeType": "datetime", "DateType": "datetime",
            "EnumerationType": "enum", "ObjectType": "object", "ListType": "list", "VoidType": "void",
            "BinaryType": "binary"}.get(n, n or "unknown")


def type_info(t):
    t = t or {}
    return {"kind": kind_of(t), "entity": t.get("Entity") or "", "enum": t.get("Enumeration") or ""}


class Domain:
    """Entities and enumerations of one model, for building sample inputs."""

    def __init__(self, m):
        self.m = m
        self.ents = {}
        for d in m.docs.values():
            if d.type == "DomainModels$DomainModel":
                for e in d.data.get("Entities") or []:
                    if isinstance(e, dict) and e.get("Name"):
                        self.ents[f"{d.module}.{e['Name']}"] = e

    def entity(self, qn):
        return self.ents.get(qn)

    def persistable(self, qn):
        """Stored in the database: the root of its generalization chain says so (System.* parents: yes)."""
        for q in self.chain(qn):
            g = self.ents[q].get("MaybeGeneralization")
            if isinstance(g, dict) and g.get("$Type") == "DomainModels$NoGeneralization":
                return g.get("Persistable") is not False
        return qn.startswith("System.") or bool(self.chain(qn))

    def non_creatable(self, qn):
        """Why an entity cannot be created with plain sample values (None when it can)."""
        e = self.ents.get(qn)
        if e is None:
            return f"entity {qn} is not in the model (a system or add-on entity)"
        src = e.get("Source") if isinstance(e.get("Source"), dict) else {}
        st = src.get("$Type", "")
        if st and st not in ("DomainModels$MendixDatabaseSource", "DomainModels$StoredEntitySource"):
            return f"entity {qn} has the source {st.split('$')[-1]} (external or view entity)"
        return None

    def chain(self, qn):
        """The entity and its generalizations that live in this model, most specific first."""
        out, seen = [], set()
        while qn and qn in self.ents and qn not in seen:
            seen.add(qn)
            out.append(qn)
            g = self.ents[qn].get("MaybeGeneralization")
            qn = g.get("Generalization") if isinstance(g, dict) and g.get("$Type") == "DomainModels$Generalization" else None
        return out

    def sort_attr(self, qn):
        """The first stored attribute of the entity itself: sorting makes 'the first seeded row' the same on both apps."""
        for a in (self.ents[qn].get("Attributes") or []):
            if isinstance(a, dict) and a.get("Name") and (a.get("Value") or {}).get("$Type") != "DomainModels$CalculatedValue":
                return a["Name"]
        return None

    def enum_values(self, qn):
        d = self.m.docs.get(qn)
        if not d:
            return []
        return [v.get("Name") for v in d.data.get("Values") or [] if isinstance(v, dict) and v.get("Name")]

    def samples(self, qn):
        """[(attribute, MDL expression)] for every stored attribute that has no default: what a created object gets."""
        out = []
        for eq in reversed(self.chain(qn)):
            mod = eq.split(".")[0]
            for a in self.ents[eq].get("Attributes") or []:
                if not isinstance(a, dict) or not a.get("Name"):
                    continue
                v = a.get("Value") if isinstance(a.get("Value"), dict) else {}
                if v.get("$Type") == "DomainModels$CalculatedValue":
                    continue
                if (v.get("DefaultValue") or "") != "":
                    continue
                t = a.get("NewType") or a.get("Type") or {}
                tn = t.get("$Type", "").split("$")[-1]
                name = a["Name"]
                if tn == "StringAttributeType":
                    n = int(t.get("Length") or 0)
                    s = STRING_DEFAULT.format(name)
                    if n:
                        s = s[:n]
                    out.append((name, "'" + s.replace("'", "''") + "'"))
                elif tn == "EnumerationAttributeType":
                    ev = self.enum_values(t.get("Enumeration") or "")
                    if ev:
                        out.append((name, f"{t['Enumeration']}.{ev[0]}"))
                elif tn == "DateTimeAttributeType":
                    out.append((name, DATE_SAMPLE))
        return out


def flow_returns(d):
    return type_info(d.data.get("MicroflowReturnType"))


def flow_params(d):
    ps = []
    for p in apimock.nodes(d.data, ("Microflows$MicroflowParameter",)):
        ti = type_info(p.get("VariableType"))
        ti["name"] = p.get("Name")
        ps.append(ti)
    return ps


def action_detail(r, d, a, eid):
    hc = a.get("HttpConfiguration") if isinstance(a.get("HttpConfiguration"), dict) else {}
    tpl = hc.get("CustomLocationTemplate") if isinstance(hc.get("CustomLocationTemplate"), dict) else {}
    rq = a.get("RequestHandling") if isinstance(a.get("RequestHandling"), dict) else {}
    rs = a.get("ResultHandling") if isinstance(a.get("ResultHandling"), dict) else {}
    hdr = [{"key": h.get("Key"), "value": h.get("Value")} for h in hc.get("HttpHeaderEntries") or [] if isinstance(h, dict)]
    export = sorted({s for s in mprmodel.strings(rq) if r.m.docs.get(s) is not None
                     and r.m.docs[s].type == "ExportMappings$ExportMapping"})
    imc = rs.get("ImportMappingCall") if isinstance(rs.get("ImportMappingCall"), dict) else {}
    return {"id": eid, "action": a.get("$Type", "").split("$")[-1], "method": (hc.get("HttpMethod") or "").upper(),
            "location": {"text": (tpl.get("Text") or "").strip(), "parameters": [p.get("Expression", "") for p in tpl.get("Parameters") or []
                                                                              if isinstance(p, dict)],
                         "custom": hc.get("CustomLocation") or ""},
            "headers": hdr, "request": {"type": (rq.get("$Type") or "").split("$")[-1], "template": ((rq.get("Template") or {}).get("Text") or "").strip()
                                          if isinstance(rq.get("Template"), dict) else "", "export_mapping": export},
            "response": {"type": a.get("ResultHandlingType") or "", "import_mapping": imc.get("ReturnValueMapping") or "",
                         "content_type": imc.get("ContentType") or ""},
            "error": {"type": a.get("ErrorHandlingType") or "", "result": a.get("ErrorResultHandlingType") or ""}}


def inventory(models, side, excludes, rules, recorded):
    """calls.json of ONE side: per microflow holding a REST call, its signature, its actions (inventory ids with the
    apimock status), and whether a wrapper can be generated."""
    inv = apimock.build_inventory(models, excludes, rules, recorded)
    status = {e["id"]: e for e in inv["endpoints"]}
    mpath = models[-1] if side == "new" else models[0]
    m = mprmodel.Model.load(mpath)
    r = apimock.Reader(m)
    dom = Domain(m)
    calls = []
    for qn, d in sorted(r.flows.items()):
        acts = list(apimock.nodes(d.data, CALL_TYPES))
        if not acts:
            continue
        n_rest = [x for x in apimock.nodes(d.data, ("Microflows$RestCallAction",))]
        n_send = [x for x in apimock.nodes(d.data, apimock.CALL_TYPES)]
        # a disabled activity (Studio Pro's "disable activity") never runs: its call is dead code, not a consumed endpoint
        off = {id(x["Action"]) for x in apimock.nodes(d.data, ("Microflows$ActionActivity",))
               if x.get("Disabled") and isinstance(x.get("Action"), dict)}
        details = []
        for i, a in enumerate(n_rest):
            details.append(action_detail(r, d, a, f"rest:{qn}" + (f"#{i + 1}" if len(n_rest) > 1 else "")))
        for i, a in enumerate(n_send):
            details.append(action_detail(r, d, a, f"send:{qn}" + (f"#{i + 1}" if len(n_send) > 1 else "")))
        for x, a in zip(details, n_rest + n_send):
            x["disabled"] = id(a) in off
        for x in details:
            e = status.get(x["id"]) or {}
            x["status"] = e.get("status") or "UNKNOWN"
            x["system"] = e.get("system") or ""
            x["why"] = e.get("why") or ""
        params = flow_params(d)
        rec = {"microflow": qn, "type": d.type.split("$")[-1], "excluded": bool(d.data.get("Excluded")),
               "params": params, "returns": flow_returns(d), "actions": details,
               "allowed_roles": [x for x in (d.data.get("AllowedModuleRoles") or []) if isinstance(x, str)]}
        rec["reasons"] = needs_recipe(rec, dom, d)
        calls.append(rec)
    for i, c in enumerate(calls, 1):
        c["wrapper"] = f"T_{i:04d}"
    return {"side": side, "model": mpath, "calls": calls, "classes": ["RUNNABLE", "NEEDS_RECIPE", "INFO"]}


def needs_recipe(rec, dom, d):
    """The reasons no wrapper can build this microflow's inputs (empty list: it can)."""
    why = []
    if rec["type"] != "Microflow":
        why.append(f"a {rec['type']} cannot be called from a test microflow")
    for p in rec["params"]:
        k = p["kind"]
        if k in ("string", "integer", "decimal", "boolean", "datetime"):
            continue
        if k == "enum":
            if not dom.enum_values(p["enum"]):
                why.append(f"parameter {p['name']}: enumeration {p['enum']} has no values in the model")
        elif k in ("object", "list"):
            w = dom.non_creatable(p["entity"])
            if w:
                why.append(f"parameter {p['name']}: {w}")
        else:
            why.append(f"parameter {p['name']}: a {k} input has no sample")
    rk = rec["returns"]["kind"]
    if rk in ("object", "list") and rec["returns"]["entity"] not in dom.ents and "." in rec["returns"]["entity"]:
        # a return of a system entity is still fine for the wrapper's return type
        pass
    return why


# ------------------------------------------------------------------------------------------------ the wrapper (MDL)
def mdl_literal(p, recipes, mf):
    ov = ((recipes.get(mf) or {}).get("params") or {}).get(p["name"])
    if ov is not None:
        return str(ov)
    k = p["kind"]
    if k == "string":
        return "'" + STRING_DEFAULT.format(p["name"]).replace("'", "''") + "'"
    if k == "integer":
        return "1"
    if k == "decimal":
        return "1.5"
    if k == "boolean":
        return "true"
    if k == "datetime":
        return DATE_SAMPLE
    return None


def helper_name(ent):
    return "G_" + ent.replace(".", "_")


def helper_mdl(ent, dom):
    """A microflow that returns a seeded row of a persistable entity, else a fresh (never committed) object with the same
    samples. A sub-microflow because MDL cannot declare an object variable and create it in a branch."""
    sets = ", ".join(f"{n} = {x}" for n, x in dom.samples(ent))
    create = f"create {ent}" + (f" ({sets})" if sets else "")
    return "\n".join([f"create or modify microflow {TESTMOD}.{helper_name(ent)} ()", f"returns {ent} as $R", "begin",
                      f"  retrieve $db from {ent}" + (f" sort by {dom.sort_attr(ent)} asc" if dom.sort_attr(ent) else "") + " first;", "  if $db != empty then", "    return $db;", "  else",
                      f"    $new = {create};", "    return $new;", "  end if;", "end;"])


def wrapper_mdl(c, dom, recipes):
    """MDL text of one wrapper microflow (the entity helpers it calls come from helpers_for)."""
    mf, w = c["microflow"], f"{TESTMOD}.{c['wrapper']}"
    body, args, first_obj = [], [], None
    for p in c["params"]:
        v = f"$in_{p['name']}"
        lit = mdl_literal(p, recipes, mf)
        k = p["kind"]
        if lit is not None:
            args.append(f"{p['name']} = {lit}")
        elif k == "enum":
            args.append(f"{p['name']} = {p['enum']}.{dom.enum_values(p['enum'])[0]}")
        elif k in ("object", "list"):
            ent = p["entity"]
            if dom.persistable(ent):
                body.append(f"{v} = call microflow {TESTMOD}.{helper_name(ent)}();")
            else:
                sets = ", ".join(f"{n} = {x}" for n, x in dom.samples(ent))
                body.append(f"{v} = create {ent}" + (f" ({sets})" if sets else "") + ";")
            if k == "object":
                first_obj = first_obj or (v, ent)
            else:
                body += [f"{v}_list = create list of {ent};", f"add {v} to {v}_list;"]
                v = f"{v}_list"
            args.append(f"{p['name']} = {v}")
    call = f"call microflow {mf}(" + ", ".join(args) + ")"
    rk = c["returns"]
    ret, tail = "", []
    if rk["kind"] == "void":
        body.append(call + ";")
        if first_obj:   # nothing is returned by the call: hand back its first object input, so a change it made is seen
            ret = f"returns {first_obj[1]} as $R"
            tail = [f"return {first_obj[0]};"]
    else:
        rt = {"string": "String", "integer": "Integer", "decimal": "Decimal", "boolean": "Boolean", "datetime": "DateTime",
              "enum": rk["enum"], "object": rk["entity"], "list": f"List of {rk['entity']}"}.get(rk["kind"])
        if rt is None:
            body.append(call + ";")
        else:
            ret = f"returns {rt} as $R"
            body.append(f"$R = {call};")
            tail = ["return $R;"]
    return "\n".join([f"create or modify microflow {w} ()", ret, "begin"] + ["  " + x for x in body + tail] + ["end;"]).replace("\n\n", "\n")


def helpers_for(calls, dom):
    """The helper microflows (MDL) every wrapper of calls needs, once per entity."""
    ents = sorted({p["entity"] for c in calls for p in c["params"] if p["kind"] in ("object", "list") and dom.persistable(p["entity"])})
    return [helper_mdl(e, dom) + f"\ngrant execute on microflow {TESTMOD}.{helper_name(e)} to {TESTMOD}.{ROLE};" for e in ents]


def gen_mdl(calls, dom, recipes):
    parts = ["mdl 1;", f"create module {TESTMOD};", f"create module role {TESTMOD}.{ROLE};"]
    wrappers = []
    todo = [c for c in calls["calls"] if not (c["reasons"] or c["excluded"] or not any(a["status"] != "EXCLUDED" for a in c["actions"]))]
    parts += helpers_for(todo, dom)
    for c in todo:
        parts.append(wrapper_mdl(c, dom, recipes))
        parts.append(f"grant execute on microflow {TESTMOD}.{c['wrapper']} to {TESTMOD}.{ROLE};")
        wrappers.append(c["wrapper"])
    return "\n".join(parts) + "\n", wrappers


def load_recipes(path):
    if not path:
        return {}
    p = Path(path)
    if not p.is_file():
        die(f"--recipes {path}: no such file")
    try:
        return json.loads(p.read_text())
    except ValueError as e:
        die(f"--recipes {path}: {e}")


def cmd_inventory(a):
    calls = inventory(a.models, a.side, apimock.parse_excludes(a.exclude), apimock.read_classify(a.classify), a.recorded)
    Path(a.out).write_text(json.dumps(calls, indent=1) + "\n")
    cs = calls["calls"]
    run = [c for c in cs if not c["reasons"] and not c["excluded"] and any(x["status"] != "EXCLUDED" for x in c["actions"])]
    acts = sum(len(c["actions"]) for c in cs)
    print(f"apidirect inventory ({a.side}): {len(cs)} microflows with {acts} REST calls · runnable {len(run)} · "
          f"needs input recipe {sum(1 for c in cs if c['reasons'] and not c['excluded'])} · "
          f"excluded from the build {sum(1 for c in cs if c['excluded'])}")


def cmd_gen(a):
    calls = json.load(open(a.calls))
    m = mprmodel.Model.load(calls["model"])
    mdl, wrappers = gen_mdl(calls, Domain(m), load_recipes(a.recipes))
    Path(a.out).write_text(mdl)
    print(f"apidirect gen: {len(wrappers)} wrappers in {a.out}")


def cmd_prepare(a):
    """Apply the test module to the throwaway copy at --app. Statements are applied one wrapper at a time so one that
    does not check is recorded INVALID (with mxcli's reason) instead of stopping the rest."""
    calls = json.load(open(a.calls))
    app = Path(a.app)
    mprs = list(app.glob("*.mpr"))
    if len(mprs) != 1:
        die(f"{app}: expected exactly one .mpr")
    mpr = str(mprs[0])
    m = mprmodel.Model.load(mpr)
    dom = Domain(m)
    recipes = load_recipes(a.recipes)
    base = f"mdl 1;\ncreate module {TESTMOD};\ncreate module role {TESTMOD}.{ROLE};\n"
    first = Path(a.app) / ".apidirect-base.mdl"
    first.write_text(base)
    r = subprocess.run([a.mxcli, "-p", mpr, "exec", str(first)], capture_output=True, text=True)
    if r.returncode != 0:
        die(f"mxcli could not create the test module: {(r.stdout + r.stderr)[-600:]}")
    bad = {}
    todo = [c for c in calls["calls"] if not c["reasons"] and not c["excluded"]
            and any(x["status"] != "EXCLUDED" and not x.get("disabled") for x in c["actions"])]
    # one file for all wrappers: mxcli checks every statement first and applies none when one is wrong, so on a failure
    # the wrappers go one by one and the refused ones are recorded with mxcli's reason
    allf = Path(a.app) / ".apidirect-all.mdl"
    allf.write_text("mdl 1;\n" + "\n".join(helpers_for(todo, dom)) + "\n" + "\n".join(wrapper_mdl(c, dom, recipes) + f"\ngrant execute on microflow {TESTMOD}.{c['wrapper']} to {TESTMOD}.{ROLE};"
                                           for c in todo) + "\n")
    r = subprocess.run([a.mxcli, "-p", mpr, "exec", str(allf)], capture_output=True, text=True)
    allf.unlink(missing_ok=True)
    if r.returncode != 0:
        print(f"apidirect prepare: bulk apply refused ({(r.stdout + r.stderr).strip().splitlines()[-1][:160] if (r.stdout + r.stderr).strip() else r.returncode}); one by one")
        bad_ent = set()
        ents = sorted({p["entity"] for c in todo for p in c["params"] if p["kind"] in ("object", "list") and dom.persistable(p["entity"])})
        for e in ents:
            f = Path(a.app) / ".apidirect-one.mdl"
            f.write_text("mdl 1;\n" + helper_mdl(e, dom) + f"\ngrant execute on microflow {TESTMOD}.{helper_name(e)} to {TESTMOD}.{ROLE};\n")
            r = subprocess.run([a.mxcli, "-p", mpr, "exec", str(f)], capture_output=True, text=True)
            if r.returncode != 0:
                bad_ent.add(e)
        for c in todo:
            if any(p["entity"] in bad_ent for p in c["params"] if p["kind"] in ("object", "list")):
                bad[c["microflow"]] = "the sample-row helper for an input entity did not apply: " + ", ".join(
                    sorted({p["entity"] for p in c["params"] if p["entity"] in bad_ent}))
                continue
            f = Path(a.app) / ".apidirect-one.mdl"
            f.write_text("mdl 1;\n" + wrapper_mdl(c, dom, recipes) + f"\ngrant execute on microflow {TESTMOD}.{c['wrapper']} to {TESTMOD}.{ROLE};\n")
            r = subprocess.run([a.mxcli, "-p", mpr, "exec", str(f)], capture_output=True, text=True)
            if r.returncode != 0:
                msg = [x for x in (r.stdout + r.stderr).splitlines() if x.strip() and "warning:" not in x.lower()
                       and not x.startswith("Connected")]
                key = [x.strip() for x in msg if re.search(r"error|unresolved|not found|does not exist|parse", x, re.I)]
                bad[c["microflow"]] = (" ".join((key or msg)[:2])[:300] or f"mxcli exit {r.returncode}")
    for n in (".apidirect-one.mdl", ".apidirect-base.mdl"):
        (Path(a.app) / n).unlink(missing_ok=True)
    r = subprocess.run([a.mxcli, "-p", mpr, "-c", f"alter user role {a.user_role} add module roles ({TESTMOD}.{ROLE});"],
                       capture_output=True, text=True)
    if r.returncode != 0:
        die(f"mxcli could not give the user role {a.user_role} the module role: {(r.stdout + r.stderr)[-400:]}")
    for c in calls["calls"]:
        if c["microflow"] in bad:
            c["reasons"].append(f"the wrapper did not apply: {bad[c['microflow']]}")
    Path(a.calls).write_text(json.dumps(calls, indent=1) + "\n")
    print(f"apidirect prepare: {len(todo) - len(bad)} wrappers applied, {len(bad)} refused (needs input recipe)")


# ------------------------------------------------------------------------------------------------ the driver
class Xas:
    """The runtime's client API: login, executeaction. The same calls the Mendix web client makes."""

    def __init__(self, base):
        self.base = base.rstrip("/")
        self.jar = http.cookiejar.CookieJar()
        self.op = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(self.jar))
        self.csrf = ""

    def post(self, body, timeout=300):
        req = urllib.request.Request(self.base + "/xas/", data=json.dumps(body).encode(), method="POST",
                                     headers={"Content-Type": "application/json", "X-Csrf-Token": self.csrf,
                                              "X-Mx-ReqToken": str(int(time.time() * 1000))})
        try:
            with self.op.open(req, timeout=timeout) as r:
                return r.status, json.loads(r.read().decode() or "{}")
        except urllib.error.HTTPError as e:
            raw = e.read().decode("utf-8", "replace")
            try:
                return e.code, json.loads(raw)
            except ValueError:
                return e.code, {"raw": raw[:2000]}

    def login(self, user, pw):
        st, js = self.post({"action": "login", "params": {"username": user, "password": pw, "locale": "en_US"}})
        if st != 200:
            die(f"login as {user} failed (HTTP {st}): {json.dumps(js)[:300]}")
        self.csrf = js.get("csrftoken") or js.get("csrfToken") or ""
        # the web client's startup call: it sets the device and profile cookies the runtime needs for executeaction
        st, js2 = self.post({"action": "get_session_data", "params": {
            "offline": False, "referrer": None, "deviceType": "Desktop", "profile": "", "timezoneoffset": 0,
            "timezoneId": "UTC", "preferredLanguages": ["en-US"], "version": 2}})
        if st != 200:
            die(f"session startup as {user} failed (HTTP {st}): {json.dumps(js2)[:300]}")
        self.csrf = js2.get("csrftoken") or self.csrf
        return js

    def run(self, action):
        return self.post({"action": "executeaction", "params": {"actionname": action, "params": {}, "applyEntityChanges": True},
                          "changes": {}, "objects": [], "context": []})

    def logout(self):
        try:
            self.post({"action": "logout", "params": {}}, timeout=20)
        except Exception:
            pass


def standin_call(base, path, body):
    req = urllib.request.Request(base.rstrip("/") + path, data=json.dumps(body).encode(), method="POST",
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.loads(r.read().decode() or "{}")


def log_lines(cmd):
    if not cmd:
        return []
    r = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    return (r.stdout + r.stderr).splitlines()


TS = re.compile(r"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}[.,]\d+ ")


def error_block(lines):
    """The first ERROR entry of new runtime log lines: its first line without time and session, and the lines after it
    until the next log entry (the exception text and the microflow activity it stopped in)."""
    for i, ln in enumerate(lines):
        if " ERROR - " in ln:
            head = re.sub(r"\s*\[User '[^]]*\]", "", TS.sub("", ln))
            tail = []
            for x in lines[i + 1:i + 12]:
                if TS.match(x):
                    break
                if x.strip() and not x.lstrip().startswith("at ") or re.match(r"\s+at \w+\.\w+ \(", x):
                    tail.append(x.strip())
            return " | ".join([head] + tail[:5])[:600]
    return ""


def cmd_drive(a):
    calls = json.load(open(a.calls))
    todo = [c for c in calls["calls"] if not c["reasons"] and not c["excluded"]
            and any(x["status"] != "EXCLUDED" and not x.get("disabled") for x in c["actions"])]
    if a.only:
        todo = [c for c in todo if re.search(a.only, c["microflow"])]
    x = Xas(a.app_url)
    x.login(a.user, a.password)
    out = open(a.out, "w")
    done = 0
    for c in todo:
        for mode in MODES:
            standin_call(a.standin, "/__ad/call", {"call": c["microflow"], "side": a.side, "mode": mode})
            t0 = time.time()
            before = len(log_lines(a.log_cmd))
            try:
                st, js = x.run(f"{TESTMOD}.{c['wrapper']}")
            except Exception as e:   # a timeout or a dropped connection: a result too
                st, js = 0, {"message": f"{type(e).__name__}: {e}"}
            ms = int((time.time() - t0) * 1000)
            standin_call(a.standin, "/__ad/end", {})
            if st in (401, 403) and "csrf" in json.dumps(js).lower():
                x.login(a.user, a.password)
            err = ""
            if a.log_cmd and (st != 200 or "exceptionType" in js):
                time.sleep(0.2)
                err = error_block(log_lines(a.log_cmd)[before:])
            out.write(json.dumps({"call": c["microflow"], "wrapper": c["wrapper"], "side": a.side, "mode": mode, "http": st,
                                  "response": js, "ms": ms, "log_error": err}) + "\n")
            out.flush()
        done += 1
        if done % 20 == 0:
            print(f"apidirect drive ({a.side}): {done}/{len(todo)} calls", flush=True)
    x.logout()
    out.close()
    print(f"apidirect drive ({a.side}): {done} calls x {len(MODES)} runs -> {a.out}")


# ------------------------------------------------------------------------------------------------ compare
def norm_text(s):
    s = GUID.sub("<guid>", s)
    s = ISO.sub("<time>", s)
    s = LONGNUM.sub("<num>", s)
    s = re.sub(r"(?:https?://)?(?:127\.0\.0\.1|host\.docker\.internal|[\d.]+):\d{2,5}", "<host>", s)
    return s


def norm_value(v, key="", ids=None):
    ids = ids if ids is not None else {}
    if isinstance(v, dict):
        # the object hash is a signature over the object id and its values: it differs on every run
        # a value that sits in a volatile attribute (changedDate: {value: ...}) is volatile too
        return {k: norm_value(x, key if k == "value" and VOLATILE_KEY.search(key or "") else k, ids)
                for k, x in sorted(v.items()) if k != "hash"}
    if isinstance(v, list):
        return [norm_value(x, key, ids) for x in v]
    if isinstance(v, bool) or v is None:
        return v
    if isinstance(v, (int, float)):
        return "<time>" if VOLATILE_KEY.search(key or "") and abs(v) > 10 ** 9 else v
    if isinstance(v, str):
        if VOLATILE_KEY.search(key or "") and key.lower() not in ("name",):
            if re.fullmatch(r"-?\d{6,}", v) or ISO.search(v) or GUID.search(v):
                return "<volatile>"
        return norm_text(v)
    return v


def canon_ids(v, ids=None):
    """Replace object ids (long digit strings under 'guid'/'id' keys) by their order of appearance."""
    ids = ids if ids is not None else {}
    if isinstance(v, dict):
        out = {}
        for k, x in v.items():
            if k in ("guid", "id", "$id", "objectId") and isinstance(x, (str, int)) and re.fullmatch(r"\d{6,}", str(x)):
                out[k] = ids.setdefault(str(x), f"<obj{len(ids) + 1}>")
            else:
                out[k] = canon_ids(x, ids)
        return out
    if isinstance(v, list):
        return [canon_ids(x, ids) for x in v]
    if isinstance(v, str) and re.fullmatch(r"\d{12,}", v):
        return ids.setdefault(v, f"<obj{len(ids) + 1}>")
    return v


def norm_json_text(text):
    try:
        v = json.loads(text)
    except (ValueError, TypeError):
        return norm_text(text or "")
    return norm_value(canon_ids(v))


def norm_request(r):
    q = sorted((k.lstrip("$"), norm_text(v)) for k, vs in urllib.parse.parse_qs(r.get("query") or "", keep_blank_values=True).items()
               for v in vs)
    hdrs = {k: norm_text(v) for k, v in sorted((r.get("headers") or {}).items()) if k not in apimock.IGNORED_HEADERS}
    return {"method": r.get("method"), "path": r.get("path"), "query": q, "headers": hdrs, "body": norm_json_text(r.get("body") or "")}


def norm_error(msg):
    """The part of a runtime log error that does not depend on the runtime version: the first line of the message of the
    stopped activity (the log prefix, the exception class, the 'Caused by' chain and how much of a multi-line expression is
    printed differ per version) and the first microflow activity it stopped in."""
    parts = [x.strip() for x in norm_text(str(msg)).split(" | ")]
    head = re.split(r"handling the request\.?:?\s*", parts[0], maxsplit=1)
    text = head[1] if len(head) > 1 else parts[0]
    if not text and len(parts) > 1:
        text = parts[1]
        parts = parts[1:]
    text = re.sub(r"^(?:[\w.$]+Exception):\s*", "", text).strip()
    text = re.sub(r"^(?:[\w.$]+Exception):\s*", "", text).strip()
    frame = next((x for x in parts[1:] if x.startswith("at ")), "")
    return (text + (" @ " + frame if frame else ""))[:300]


def label_objects(body):
    """The runtime lists returned objects in no fixed order and the result guids point into that list: label every object by
    its type and attributes (the ids differ on every run anyway), sort the list by label, and rewrite the guids to the label."""
    objs = body.get("objects")
    if not isinstance(objs, list):
        return body
    lab = {}
    for o in objs:
        if isinstance(o, dict) and o.get("guid") is not None:
            lab[str(o["guid"])] = f"{o.get('objectType')}:{json.dumps(canon_ids(o.get('attributes') or {}, {}), sort_keys=True)[:200]}"

    def sub(v):
        if isinstance(v, dict):
            return {k: (lab.get(str(x), x) if k == "guid" else sub(x)) for k, x in v.items()}
        if isinstance(v, list):
            return [lab.get(str(x), x) if isinstance(x, (str, int)) and str(x) in lab else sub(x) for x in v]
        return v
    out = sub(body)
    out["objects"] = sorted(out["objects"], key=lambda o: json.dumps(o, sort_keys=True))
    if isinstance(out.get("actionResult"), dict) and isinstance(out["actionResult"].get("resultGuids"), list):
        out["actionResult"]["resultGuids"] = sorted(map(str, out["actionResult"]["resultGuids"]))
    return out


def norm_response(rec):
    """What the runtime returned for one wrapper run: the action result and the returned objects, or the error."""
    js = rec.get("response") or {}
    if rec.get("http") == 200 and not js.get("message") and "exceptionType" not in js:
        body = {k: v for k, v in js.items() if k not in ("csrftoken", "changes", "instanceid", "xasid", "duration")}
        return {"ok": norm_value(canon_ids(label_objects(body)))}
    msg = rec.get("log_error") or js.get("message") or js.get("raw") or json.dumps(js)[:300]
    return {"error": {"http": rec.get("http"), "type": js.get("exceptionType") or js.get("type") or "",
                      "message": norm_error(msg)}}


def first_diff(a, b, path="$"):
    if type(a) != type(b):
        return f"{path}: {json.dumps(a)[:80]} vs {json.dumps(b)[:80]}"
    if isinstance(a, dict):
        for k in sorted(set(a) | set(b)):
            if k not in a:
                return f"{path}.{k}: missing in the old app, new has {json.dumps(b[k])[:80]}"
            if k not in b:
                return f"{path}.{k}: old has {json.dumps(a[k])[:80]}, missing in the new app"
            d = first_diff(a[k], b[k], f"{path}.{k}")
            if d:
                return d
        return None
    if isinstance(a, list):
        if len(a) != len(b):
            return f"{path}: {len(a)} items in the old app, {len(b)} in the new"
        for i, (x, y) in enumerate(zip(a, b)):
            d = first_diff(x, y, f"{path}[{i}]")
            if d:
                return d
        return None
    return None if a == b else f"{path}: {json.dumps(a)[:80]} vs {json.dumps(b)[:80]}"


def read_jsonl(p):
    out = []
    if Path(p).is_file():
        for line in Path(p).read_text().splitlines():
            try:
                out.append(json.loads(line))
            except ValueError:
                pass
    return out


def class_of(c):
    if c["excluded"]:
        return "INVALID", "the microflow is excluded from the build (not part of the running app)"
    if c["reasons"]:
        return "INVALID", "needs input recipe: " + "; ".join(c["reasons"])[:300]
    return None, ""


def compare(state, classify_file=None):
    st = Path(state)
    old, new = json.load(open(st / "calls-old.json")), json.load(open(st / "calls-new.json"))
    res = {s: {(r["call"], r["mode"]): r for r in read_jsonl(st / f"results-{s}.jsonl")} for s in ("old", "new")}
    reqs = {s: {} for s in ("old", "new")}
    for r in read_jsonl(st / "standin" / "requests.jsonl"):
        if r.get("call") and r.get("side") in reqs:
            reqs[r["side"]].setdefault((r["call"], r.get("mode")), []).append(r)
    oc = {c["microflow"]: c for c in old["calls"]}
    nc = {c["microflow"]: c for c in new["calls"]}
    out = {}

    def put(eid, mf, verdict, reasons, **kw):
        out[eid] = dict({"verdict": verdict, "microflow": mf, "reasons": reasons}, **kw)

    for mf in sorted(set(oc) | set(nc)):
        o, n = oc.get(mf), nc.get(mf)
        ref = n or o
        for act in ref["actions"]:
            eid = act["id"]
            if o is not None and n is not None:
                oa = {x["id"]: x for x in o["actions"]}.get(eid, {})
                if oa.get("disabled") and act.get("disabled"):
                    put(eid, mf, "INFO", ["the activity is disabled in both apps (never runs): nothing to test"], disabled=True)
                    continue
                if bool(oa.get("disabled")) != bool(act.get("disabled")):
                    put(eid, mf, "FAIL", [f"the activity is {'disabled' if act.get('disabled') else 'enabled'} in the new app and "
                                          f"{'enabled' if act.get('disabled') else 'disabled'} in the old app"])
                    continue
            if act["status"] == "EXCLUDED":
                put(eid, mf, "INFO", [f"excluded system {act['system'] or '?'}: no stand-in answers for it, check at deploy"],
                    system=act["system"], system_note=act.get("why", ""))
                continue
            if act["status"] != "MOCKED":
                put(eid, mf, "INVALID", [f"endpoint is {act['status']} in the stand-in inventory: {act.get('why', '')[:160]}"])
                continue
            if o is None or n is None:
                put(eid, mf, "FAIL", [f"the microflow exists only in the {'new' if n else 'old'} app (renamed or removed by the upgrade)"])
                continue
            if o["excluded"] and n["excluded"]:
                put(eid, mf, "INFO", ["the microflow is excluded from the build in both apps (never runs): nothing to test"], disabled=True)
                continue
            v, why = class_of(n) if n["reasons"] or n["excluded"] else class_of(o)
            if v is None:
                v, why = class_of(o)
            if v:
                put(eid, mf, v, [why])
                continue
            sig = lambda c: json.dumps([[p["name"], p["kind"], p["entity"] or p["enum"]] for p in c["params"]] + [c["returns"]], sort_keys=True)
            if sig(o) != sig(n):
                put(eid, mf, "FAIL", ["the microflow signature (parameters or return type) differs between the old and the new app"])
                continue
            diffs, reached = [], {s: {} for s in ("old", "new")}
            invalid = None
            for mode in MODES:
                ro, rn = res["old"].get((mf, mode)), res["new"].get((mf, mode))
                if ro is None or rn is None:
                    invalid = f"no {'old' if ro is None else 'new'} run recorded for the {mode} run (the driver did not reach it)"
                    break
                qo = [norm_request(r) for r in reqs["old"].get((mf, mode), []) if r.get("endpoint") == eid]
                qn = [norm_request(r) for r in reqs["new"].get((mf, mode), []) if r.get("endpoint") == eid]
                reached["old"][mode], reached["new"][mode] = len(qo), len(qn)
                if len(qo) != len(qn):
                    diffs.append(("request", mode, f"the old app sent {len(qo)} request(s) to this endpoint, the new app {len(qn)}"))
                else:
                    for i, (x, y) in enumerate(zip(qo, qn)):
                        d = first_diff(x, y, f"request{i + 1}")
                        if d:
                            diffs.append(("request", mode, d))
                            break
                no, nn = norm_response(ro), norm_response(rn)
                d = first_diff(no, nn, "result")
                if d:
                    kind = "response" if mode == "ok" else "error"
                    if mode != "ok" and ("error" in no) != ("error" in nn):
                        d += " (one app failed, the other handled it)"
                    diffs.append((kind, mode, d))
            if invalid:
                put(eid, mf, "INVALID", [invalid])
                continue
            if reached["old"].get("ok", 0) == 0 and reached["new"].get("ok", 0) == 0:
                # a difference that arises before the call is a difference of the surrounding flow, not of this endpoint
                err = norm_response(res["old"][(mf, "ok")]).get("error")
                put(eid, mf, "INVALID",
                    ["no request reached this endpoint in the ok run on either app"
                     + (f" (the call stopped with: {err['message'][:140]})" if err else
                        " (a branch the seeded inputs do not take, or an earlier call decides)")
                     + (f"; the two apps also differ before the call: {diffs[0][2][:120]}" if diffs else "")],
                    reached=reached)
                continue
            if diffs:
                kinds = sorted({d[0] for d in diffs})
                put(eid, mf, "FAIL", [f"{k} difference ({m} run): {t}" for k, m, t in diffs][:6], kinds=kinds, reached=reached)
            else:
                put(eid, mf, "PASS", ["same request, same result, same error path on both apps"], reached=reached, kinds=[])
    counts = {}
    for e in out.values():
        counts[e["verdict"]] = counts.get(e["verdict"], 0) + 1
    return {"counts": counts, "endpoints": out, "runs": {s: len(res[s]) for s in res}}


def cmd_compare(a):
    d = compare(a.state, a.classify)
    st = Path(a.state)
    (st / "direct.json").write_text(json.dumps(d, indent=1) + "\n")
    lines = [f"# Direct API test: old vs new", "", "counts: " + ", ".join(f"{k} {v}" for k, v in sorted(d["counts"].items())), ""]
    for v in ("FAIL", "INVALID", "PASS", "INFO"):
        rows = [(k, e) for k, e in sorted(d["endpoints"].items()) if e["verdict"] == v]
        if rows:
            lines += [f"## {v} ({len(rows)})", ""]
            lines += [f"- {k}: {'; '.join(e['reasons'])[:400]}" for k, e in rows]
            lines.append("")
    (st / "direct.md").write_text("\n".join(lines))
    print("apidirect compare: " + ", ".join(f"{k} {v}" for k, v in sorted(d["counts"].items())) + f" -> {st / 'direct.json'}")


# ------------------------------------------------------------------------------------------------ the gate rung
def verdict(direct_dir, info_lines=True):
    """(rc, lines) of the apis rung from direct results. INFO is documented, never a downgrade; any FAIL is rc 1, any
    INVALID rc 3, else 0."""
    p = Path(direct_dir) / "direct.json"
    d = json.load(open(p))
    c = d["counts"]
    eps = d["endpoints"]
    lines = [f"direct API test: PASS {c.get('PASS', 0)} · FAIL {c.get('FAIL', 0)} · INVALID {c.get('INVALID', 0)} · INFO {c.get('INFO', 0)}"
             f" (measured {c.get('PASS', 0) + c.get('FAIL', 0)} of {sum(c.values())} REST calls; runs old {d['runs']['old']}, new {d['runs']['new']})"]
    for k, e in sorted(eps.items()):
        if e["verdict"] in ("FAIL", "INVALID"):
            lines.append(f"  {e['verdict']} endpoint {k}: {'; '.join(e['reasons'])[:300]}")
    for k, e in sorted(eps.items()) if info_lines else []:
        if e["verdict"] == "INFO":
            lines.append(f"  INFO (excluded: {e.get('system') or '?'}) endpoint {k}: check at deploy")
    if c.get("FAIL"):
        return 1, lines + [f"verdict: FAIL: {c['FAIL']} REST calls differ between the old and the new app (candidate regressions: diagnose each from the evidence)"]
    if c.get("INVALID"):
        return 3, lines + [f"verdict: INVALID: {c['INVALID']} REST calls could not be measured (reasons above)"]
    return 0, lines + ["verdict: PASS" + (f" (INFO: {c['INFO']} excluded endpoints, check at deploy)" if c.get("INFO") else "")]


def cmd_check(a):
    rc, lines = verdict(a.state)
    print("\n".join(lines))
    sys.exit(rc)


def cmd_split_log(a):
    """The stand-in's log mixes journey requests with the direct test's (tagged with call/side/mode): the direct ones go to
    --out, the journey ones stay in the stand-in's log, so the apis rung's journey evidence is not inflated."""
    p = Path(a.state) / "requests.jsonl"
    keep, direct = [], []
    for ln in p.read_text().splitlines() if p.is_file() else []:
        try:
            (direct if json.loads(ln).get("call") else keep).append(ln)
        except ValueError:
            keep.append(ln)
    Path(a.out).parent.mkdir(parents=True, exist_ok=True)
    Path(a.out).write_text("".join(x + "\n" for x in direct))
    p.write_text("".join(x + "\n" for x in keep))
    print(f"apidirect split-log: {len(direct)} direct requests -> {a.out}, {len(keep)} journey requests kept")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("inventory")
    p.add_argument("models", nargs="+")
    p.add_argument("--side", required=True, choices=("old", "new"))
    p.add_argument("--out", required=True)
    p.add_argument("--exclude", action="append")
    p.add_argument("--classify")
    p.add_argument("--recorded")
    p.set_defaults(fn=cmd_inventory)
    p = sub.add_parser("gen")
    p.add_argument("calls")
    p.add_argument("--out", required=True)
    p.add_argument("--recipes")
    p.set_defaults(fn=cmd_gen)
    p = sub.add_parser("prepare")
    p.add_argument("calls")
    p.add_argument("--app", required=True)
    p.add_argument("--mxcli", required=True)
    p.add_argument("--recipes")
    p.add_argument("--user-role", default="Administrator")
    p.set_defaults(fn=cmd_prepare)
    p = sub.add_parser("drive")
    p.add_argument("calls")
    p.add_argument("--side", required=True, choices=("old", "new"))
    p.add_argument("--app-url", required=True)
    p.add_argument("--standin", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--user", required=True)
    p.add_argument("--password", required=True)
    p.add_argument("--only")
    p.add_argument("--log-cmd", help="prints the runtime log of the app under test (docker logs NAME): the message of a failed run is only there")
    p.set_defaults(fn=cmd_drive)
    p = sub.add_parser("split-log")
    p.add_argument("--state", required=True)
    p.add_argument("--out", required=True)
    p.set_defaults(fn=cmd_split_log)
    p = sub.add_parser("compare")
    p.add_argument("--state", required=True)
    p.add_argument("--classify")
    p.set_defaults(fn=cmd_compare)
    p = sub.add_parser("check")
    p.add_argument("--state", required=True)
    p.set_defaults(fn=cmd_check)
    a = ap.parse_args()
    a.fn(a)


if __name__ == "__main__":
    main()
