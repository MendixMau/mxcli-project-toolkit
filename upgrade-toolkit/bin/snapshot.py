#!/usr/bin/env python3
"""Take one regression snapshot of a RUNNING Mendix app: database, HTTP surface, runtime log, admin facts.

  snapshot.py --label before --out snap-before.json \
      --psql "docker exec -i mig-pg psql -U mendix -d mydb" \
      --app-url http://localhost:8080 [--admin-url http://localhost:8090 --admin-pass X] \
      [--log-cmd "docker logs mig-app"] [--endpoints endpoints.txt]

What it records (keyed by MODEL NAMES, not table names, so a storage change does not read as data loss):
  db.entities[<Module.Entity>]     = row count of the entity's table (includes specializations)
  db.attributes[<Module.Entity.Attr>] = {nonnull, md5} over the column, ordered by id
  db.associations[<Module.Assoc>]  = pair count + md5 of sorted pairs, whatever the storage (join table or FK column)
  db.ids[<kind:name>]              = model element GUID of every entity, attribute, association (identity check)
  db.idsets[<kind:name>]           = ALL GUIDs per name (System.owner / System.changedBy have one row per entity)
  db.tables                        = raw table list (for "unmapped table appeared/disappeared")
  http[<path>]                     = status, content type, body md5, JSON key shape   (paths from --endpoints, plus /rest-doc/ discovery)
                                     contract for swagger.json (Mendix 9) and openapi.json (Mendix 10+): path, verb,
                                     parameters (in:name:required), response codes
  log                              = ERROR/CRITICAL line signatures (timestamps and numbers stripped), plus the START
                                     window lines (all levels from INFO, after-startup section marked; see logdiff.py)
  admin                            = runtime_status, about (version)

Fresh copy per snapshot (E4-21): a GET can write (one licence service endpoint created a CSV export and set the
admin's LastLogin), so a baseline taken on a database that a probe, a walk or an earlier snapshot already used reported
15 FAIL that were the probe's own writes. With --ledger FILE (one per run, for example $W/db-ledger.txt):
  - a database named *_frozen is refused (the app writes at start; never run anything on X_frozen)
  - a database the ledger already lists (snapshot, walk, probe) is refused: make a fresh `createdb -T X_frozen X_n`
  - after the snapshot the database is added to the ledger
  snapshot.py --ledger FILE --mark-used DB --use walk   records a database used by a walk or probe (no snapshot)
The refusal happens before any query. Without --ledger a warning is printed.

Read-only: never writes to the database. No network beyond the given URLs.
"""
import argparse
import re, base64, hashlib, json, os, re, shlex, subprocess, sys, tempfile, time, urllib.request, urllib.error

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import logdiff  # noqa: E402


def q(psql, sql):
    r = subprocess.run(shlex.split(psql) + ["-tA", "-F", "\t", "-v", "ON_ERROR_STOP=1"], input=sql, capture_output=True, text=True)
    if r.returncode: raise RuntimeError(r.stderr[:1000])
    return [l.split("\t") for l in r.stdout.splitlines() if l]


def db_snapshot(psql):
    ents = {r[0]: (r[1], r[2]) for r in q(psql, 'select id, entity_name, table_name from "mendixsystem$entity"')}
    cols = {}
    for t, c in q(psql, "select table_name, column_name from information_schema.columns where table_schema='public'"):
        cols.setdefault(t, set()).add(c)
    out = {"entities": {}, "attributes": {}, "associations": {}, "tables": sorted(cols), "ids": {}, "idsets": {}}
    # model element ids: the runtime maps columns and join tables by these GUIDs, not by name. Same name + new id after an
    # upgrade means the runtime DROPPED and re-created the column or join table: the data is gone even though the name survived.
    for en, an, aid in q(psql, 'select e.entity_name, a.attribute_name, a.id from "mendixsystem$attribute" a join "mendixsystem$entity" e on e.id = a.entity_id'):
        out["ids"][f"attr:{en}.{an}"] = aid
        out["idsets"].setdefault(f"attr:{en}.{an}", []).append(aid)
    for an, aid in q(psql, 'select association_name, id from "mendixsystem$association" order by id'):
        out["ids"][f"assoc:{an}"] = aid
        out["idsets"].setdefault(f"assoc:{an}", []).append(aid)
    for eid, en in q(psql, 'select id, entity_name from "mendixsystem$entity"'):
        out["ids"][f"entity:{en}"] = eid
        out["idsets"].setdefault(f"entity:{en}", []).append(eid)
    for k in out["idsets"]:
        out["idsets"][k] = sorted(set(out["idsets"][k]))
    attrs = {}
    for eid, an, col in q(psql, 'select entity_id, attribute_name, column_name from "mendixsystem$attribute"'):
        attrs.setdefault(eid, []).append((an, col))
    for eid, (en, t) in sorted(ents.items(), key=lambda x: x[1][0]):
        if t not in cols: out["entities"][en] = None; continue
        parts = ['count(*)']
        al = [(an, c) for an, c in attrs.get(eid, []) if c in cols[t]]
        for an, c in al:
            parts += [f'count("{c}")', f"md5(coalesce(string_agg(coalesce(\"{c}\"::text,'~'), '|' order by id),''))"]
        row = q(psql, f'select {", ".join(parts)} from "{t}"')[0]
        out["entities"][en] = int(row[0])
        for i, (an, c) in enumerate(al):
            out["attributes"][f"{en}.{an}"] = {"nonnull": int(row[1 + 2 * i]), "md5": row[2 + 2 * i]}
    for name, table, pcol, ccol in q(psql, 'select association_name, table_name, parent_column_name, child_column_name from "mendixsystem$association"'):
        if table not in cols or ccol not in cols[table]: out["associations"][name] = None; continue
        if pcol == "id":
            sql = f'select count("{ccol}"), md5(coalesce(string_agg(id::text||\'>\'||"{ccol}"::text, \'|\' order by id),\'\')) from "{table}" where "{ccol}" is not null'
        else:
            sql = f'select count(*), md5(coalesce(string_agg("{pcol}"::text||\'>\'||"{ccol}"::text, \'|\' order by "{pcol}","{ccol}"),\'\')) from "{table}"'
        n, h = q(psql, sql)[0]
        out["associations"][name] = {"pairs": int(n), "md5": h}
    # PLM-27: the Mx10 runtime deletes session-less Anonymous_* users at start, so System.User rows, their attributes and
    # their role links always drop on a 9 to 10 data rung. Record the same figures for the NAMED users alone, so diff.py can
    # judge those and report the anonymous rows as one known behaviour.
    try:
        out["anonymous"] = anonymous_snapshot(psql, ents, attrs, cols)
    except RuntimeError:
        pass
    return out


def anonymous_snapshot(psql, ents, attrs, cols):
    """{"users": n anonymous rows, "total": n, "attrs": {"System.User.X": {...}}, "assoc": {name: {...}}} for the rows of
    System.User that are not anonymous; {} when System.User or IsAnonymous cannot be found."""
    uid = next((i for i, (en, _) in ents.items() if en == "System.User"), None)
    if uid is None:
        return {}
    ut = ents[uid][1]
    acol = next((c for an, c in attrs.get(uid, []) if an == "IsAnonymous"), None)
    if ut not in cols or not acol or acol not in cols[ut]:
        return {}
    named = f'coalesce("{acol}", false) = false'
    n_anon = int(q(psql, f'select count(*) from "{ut}" where not ({named})')[0][0])
    n_total = int(q(psql, f'select count(*) from "{ut}"')[0][0])
    res = {"users": n_anon, "total": n_total, "attrs": {}, "assoc": {}}
    for an, c in attrs.get(uid, []):
        if c in cols[ut]:
            n, h = q(psql, f'select count("{c}"), md5(coalesce(string_agg(coalesce("{c}"::text,\'~\'), \'|\' order by id),\'\')) '
                           f'from "{ut}" where {named}')[0]
            res["attrs"][f"System.User.{an}"] = {"nonnull": int(n), "md5": h}
    for name, table, pcol, ccol, peid in q(psql, 'select association_name, table_name, parent_column_name, child_column_name, parent_entity_id '
                                                 'from "mendixsystem$association"'):
        if peid != uid or table not in cols or ccol not in cols[table]:
            continue
        if pcol == "id":
            sql = (f'select count("{ccol}"), md5(coalesce(string_agg(id::text||\'>\'||"{ccol}"::text, \'|\' order by id),\'\')) '
                   f'from "{table}" where "{ccol}" is not null and {named}')
        else:
            sql = (f'select count(*), md5(coalesce(string_agg("{pcol}"::text||\'>\'||"{ccol}"::text, \'|\' order by "{pcol}","{ccol}"),\'\')) '
                   f'from "{table}" where "{pcol}" in (select id from "{ut}" where {named})')
        n, h = q(psql, sql)[0]
        res["assoc"][name] = {"pairs": int(n), "md5": h}
    return res


def shape(v, depth=0):
    if depth > 4: return "..."
    if isinstance(v, dict): return {k: shape(v[k], depth + 1) for k in sorted(v)}
    if isinstance(v, list): return [shape(v[0], depth + 1)] if v else []
    return type(v).__name__


def http_get(url, auth=None):
    h = {"Accept": "application/json"}
    if auth: h["Authorization"] = "Basic " + base64.b64encode(auth.encode()).decode()
    t0 = time.time()
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers=h), timeout=60) as r:
            body, code, ctype = r.read(), r.status, r.headers.get("Content-Type", "")
    except urllib.error.HTTPError as e:
        body, code, ctype = e.read(), e.code, e.headers.get("Content-Type", "")
    except Exception as e:
        return {"status": None, "error": str(e)[:200]}
    rec = {"status": code, "ctype": ctype.split(";")[0], "bytes": len(body), "md5": hashlib.md5(body).hexdigest(), "ms": int((time.time() - t0) * 1000)}
    if "json" in ctype:
        try: rec["shape"] = shape(json.loads(body))
        except Exception: pass
    return rec, body


def contract(spec):
    """Swagger 2.0 or OpenAPI 3 -> {path: {verb: {"responses": [...], "params": ["in:name:req", ...]}}}.
    Volatile fields (host, servers, descriptions) are left out, so the same API gives the same md5 on both versions."""
    base = spec.get("basePath", "") if "swagger" in spec else ""
    out = {}
    for path, ops in (spec.get("paths") or {}).items():
        shared = ops.get("parameters", []) if isinstance(ops, dict) else []
        for verb, op in (ops.items() if isinstance(ops, dict) else []):
            if verb == "parameters" or not isinstance(op, dict):
                continue
            params = []
            for prm in list(shared) + list(op.get("parameters", [])):
                if isinstance(prm, dict) and prm.get("in") == "body":  # Swagger 2 body = OpenAPI 3 requestBody (name is free)
                    params.append(f"body:requestBody:{'req' if prm.get('required') else 'opt'}")
                elif isinstance(prm, dict) and "name" in prm:
                    params.append(f"{prm.get('in', '?')}:{prm['name']}:{'req' if prm.get('required') else 'opt'}")
            if isinstance(op.get("requestBody"), dict):
                params.append(f"body:requestBody:{'req' if op['requestBody'].get('required') else 'opt'}")
            out.setdefault(base + path, {})[verb] = {"responses": sorted(str(c) for c in op.get("responses", {})),
                                                     "params": sorted(set(params))}
    return out


def http_snapshot(app, endpoints, auth):
    out = {}
    paths = list(endpoints)
    r = http_get(app + "/rest-doc/")
    if isinstance(r, tuple) and r[0]["status"] == 200:  # discover published REST services (dev/test mode only)
        for m in sorted(set(re.findall(rb'href="\./([^"#?]+)"', r[1]))):
            svc = m.decode().rstrip("/")
            if svc.endswith((".json", ".html", ".css", ".js")):
                continue
            # Mendix 9 publishes swagger.json, Mendix 10+ also openapi.json: probe both, every time, so a
            # contract that only exists on one side shows up as NEW_ENDPOINT or a lost endpoint in diff.py
            for doc in ("swagger.json", "openapi.json"):
                paths.append(f"/rest-doc/{svc}/{doc}")
    seen = set()
    for p in paths:
        if p in seen:
            continue
        seen.add(p)
        r = http_get(app + p, auth)
        rec = r[0] if isinstance(r, tuple) else r
        if isinstance(r, tuple) and p.endswith((".json",)) and "/rest-doc/" in p and rec["status"] == 200:
            try:
                spec = json.loads(r[1])
                if "paths" in spec:
                    rec["contract"] = contract(spec)
                    rec["md5"] = hashlib.md5(json.dumps(rec["contract"], sort_keys=True).encode()).hexdigest()
            except Exception: pass
        out[p] = rec
    return out


def log_snapshot(cmd):
    r = subprocess.run(shlex.split(cmd), capture_output=True, text=True)
    text = r.stdout + r.stderr
    lines = text.splitlines()
    with tempfile.NamedTemporaryFile("w", suffix=".log", delete=False) as t:
        t.write(text)
    try:
        start, started, _ = logdiff.parse(t.name)
        error_sigs = sorted(logdiff.error_sigs(t.name))
    finally:
        os.unlink(t.name)
    sig = {}
    for l in lines:
        m = re.match(r"^\S+ \S+ (ERROR|CRITICAL) - (.*)$", l)
        if not m: continue
        s = re.sub(r"\d+", "#", m.group(1) + " " + m.group(2))[:200]
        sig[s] = sig.get(s, 0) + 1
    return {"lines": len(lines), "errors": sig, "start": start, "started": started, "error_sigs": error_sigs}


def admin_snapshot(url, pw):
    out = {}
    for act in ("runtime_status", "about"):
        req = urllib.request.Request(url, data=json.dumps({"action": act, "params": {}}).encode(),
                                     headers={"Content-Type": "application/json", "X-M2EE-Authentication": base64.b64encode(pw.encode()).decode()})
        try:
            with urllib.request.urlopen(req, timeout=30) as r: out[act] = json.loads(r.read()).get("feedback")
        except Exception as e: out[act] = {"error": str(e)[:200]}
    return out


def psql_db(psql):
    """Database name from a psql command string (-d NAME, --dbname=NAME, --dbname NAME)."""
    w = shlex.split(psql or "")
    for i, x in enumerate(w):
        if x in ("-d", "--dbname") and i + 1 < len(w):
            return w[i + 1]
        if x.startswith("--dbname="):
            return x.split("=", 1)[1]
        if x.startswith("-d") and len(x) > 2:
            return x[2:]
    return None


def ledger_read(path):
    """{db: (line number, rest of the line)} for the first line of each database."""
    used = {}
    if path and os.path.exists(path):
        for n, line in enumerate(open(path), 1):
            p = line.split()
            if p and not p[0].startswith("#"):
                used.setdefault(p[0], (n, " ".join(p[1:])))
    return used


LEDGER_LINE = re.compile(r"^\S+\s+\S+\s+\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d$")


def ledger_check(path, db):
    """Exit 2 when db is frozen or already used; returns None when the snapshot may run."""
    if db and db.endswith("_frozen"):
        print(f"snapshot: REFUSED, {db} is a frozen database; snapshot a fresh copy (createdb -T {db} <name>)", file=sys.stderr)
        sys.exit(2)
    if path is None:
        print("snapshot: WARNING, no --ledger: nothing checks that this database is a fresh copy (E4-21)", file=sys.stderr)
        return
    if db is None:
        print("snapshot: REFUSED, --ledger needs the database name in --psql (-d NAME)", file=sys.stderr)
        sys.exit(2)
    used = ledger_read(path)
    if db in used:
        n, rest = used[db]
        print(f"snapshot: REFUSED, {db} was already used ({rest}); a probe, walk or earlier snapshot may have written to it. "
              f"Take the snapshot on a fresh copy: createdb -T <X>_frozen <new name>", file=sys.stderr)
        print(f"   ledger line {n} of {path}: {db} {rest}", file=sys.stderr)
        if not LEDGER_LINE.match(rest):  # E6-16, E7-8: a note written by hand reads as "already used"
            print("   that line is not in the form snapshot.py writes (<db> <use> <label> <timestamp>): if it is your own note, "
                  "remove it. Never write ledger lines by hand: snapshot.py adds the line itself after the snapshot, "
                  "and --mark-used DB --use walk|probe records a walk or probe.", file=sys.stderr)
        sys.exit(2)


def ledger_add(path, db, use, label):
    with open(path, "a") as f:
        f.write(f"{db} {use} {label} {time.strftime('%Y-%m-%dT%H:%M:%S')}\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--label"); ap.add_argument("--out")
    ap.add_argument("--ledger", help="databases already used in this run; refuse to snapshot one twice (E4-21)")
    ap.add_argument("--mark-used", metavar="DB", help="with --ledger: record DB as used by a walk or probe, then exit")
    ap.add_argument("--use", default="walk", help="with --mark-used: what used it (walk, probe, journeys)")
    ap.add_argument("--psql"); ap.add_argument("--app-url"); ap.add_argument("--endpoints")
    ap.add_argument("--auth", help="user:pass for endpoint calls"); ap.add_argument("--log-cmd")
    ap.add_argument("--admin-url"); ap.add_argument("--admin-pass")
    a = ap.parse_args()
    if a.admin_url and not a.admin_pass:  # NR2-9: runapp.py starts every app with this admin password
        a.admin_pass = os.environ.get("M2EE_ADMIN_PASS") or "m2ee-local-only"
    if a.mark_used:
        if not a.ledger:
            ap.error("--mark-used needs --ledger")
        ledger_add(a.ledger, a.mark_used, a.use, a.label or "-"); print(f"ledger: {a.mark_used} {a.use}"); return
    if not (a.label and a.out):
        ap.error("--label and --out are required")
    db_name = psql_db(a.psql) if a.psql else None
    if a.psql:
        ledger_check(a.ledger, db_name)
    snap = {"label": a.label, "taken": time.strftime("%Y-%m-%dT%H:%M:%S"), "faults": []}
    for key, fn in (("db", lambda: db_snapshot(a.psql) if a.psql else None),
                    ("http", lambda: http_snapshot(a.app_url.rstrip("/"), [l.strip() for l in open(a.endpoints) if l.strip() and not l.startswith("#")] if a.endpoints else ["/"], a.auth) if a.app_url else None),
                    ("log", lambda: log_snapshot(a.log_cmd) if a.log_cmd else None),
                    ("admin", lambda: admin_snapshot(a.admin_url, a.admin_pass) if a.admin_url else None)):
        try: snap[key] = fn()
        except Exception as e: snap[key] = None; snap["faults"].append(f"{key}: {e}")
    json.dump(snap, open(a.out, "w"), indent=1, sort_keys=True)
    if a.ledger and db_name:
        ledger_add(a.ledger, db_name, "snapshot", a.label)
    db = snap.get("db") or {}
    print(f"{a.label}: entities {len(db.get('entities', {}))}, rows {sum(v or 0 for v in db.get('entities', {}).values())}, "
          f"associations {len(db.get('associations', {}))}, http {len(snap.get('http') or {})}, log errors {sum((snap.get('log') or {}).get('errors', {}).values())}, faults {snap['faults']}")


if __name__ == "__main__":
    main()
