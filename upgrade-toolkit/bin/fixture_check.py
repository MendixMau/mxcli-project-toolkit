#!/usr/bin/env python3
"""Fixture preflight (E2E-12, plan work package 5): run every journey's seed queries against the app's database BEFORE the
journey run, and sort each one that returns nothing by its cause.

    fixture_check.py <gen-dir> [--psql CMD] [--out fixture-check.json] [--only id,id]

Why: the engine (journey-runner.js resolveSeeds) turns a seed that answers nothing into "<seed> returned nothing" and the
journey into INVALID, whatever the reason: a database that is down, a query on a renamed entity, a runtime that has not
created its tables yet, and a fixture that is simply absent all read the same. On the old app that row then became a
"baseline defect" nobody could attribute. Four causes, four owners (fixture-seeding.md section 3, sister toolkit
skills/fixture-seeding.md at 588056a, copied here because cloud workers cannot clone it):

    | Symptom                         | Cause                              | Owner          | Here        | exit |
    | database unreachable            | stack down / wrong port            | operator       | UNREACHABLE | 2    |
    | seed SQL errors                 | malformed query, renamed entity    | journey author | QUERY-ERROR | 2    |
    | seed SQL runs, 0 rows (or NULL) | fixture absent                     | seeding        | EMPTY       | 1    |
    | runtime still warming           | race (mapping or table not there)  | operator       | WARMING     | 2    |

The harness checks the preconditions and never repairs them: nothing is written. EMPTY is a finding (seed the fixture);
the other three are faults (fix the stack or the query, re-run): never seed on the strength of a fault. EMPTY rows are
what a FIXTURE evidence line of run_journeys.py --baseline-evidence cites (E2E-11): "<journey> FIXTURE fixture-check.json".

Seeds run as the engine runs them: in order, each `{{name}}` filled with an earlier seed's first value, through
pgmap.py (names from mendixsystem$*, never guessed; a text that starts with /*sql*/ runs as it is). A journey whose
seed is not OK stops at that seed, as the engine stops. --psql defaults to env UPG_PSQL (run_journeys.py --psql);
without one every journey with seeds is UNREACHABLE (no database to ask), never OK.

Output: one row per journey, the line "fixture: J journeys · S with seeds · OK n · EMPTY n · QUERY-ERROR n · WARMING n ·
UNREACHABLE n", and --out JSON {"tool", "line", "counts", "journeys": {id: {role, status, seed, detail}}} (NO-SEEDS:
the journey asks nothing). Exit: 0 every seeded journey OK (or none has seeds); 1 EMPTY and no fault; 2 a fault, or the
arguments (no gen dir).
"""
import argparse, json, os, re, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import pgmap   # noqa: E402

STATUSES = ("OK", "EMPTY", "QUERY-ERROR", "WARMING", "UNREACHABLE", "NO-SEEDS")
WARM = re.compile(r"mendixsystem\$|does not exist|no such table|relation .* does not exist", re.I)


def journeys(gen_dir, only=None):
    """[(id, role, seeds)] of every generated journey file, sorted by path."""
    out = []
    for f in sorted((Path(gen_dir) / "journeys").glob("*/*.journey.json")):
        d = json.load(open(f))
        if only and d.get("id") not in only:
            continue
        out.append((d.get("id", f.stem), f.parent.name, d.get("seeds") or []))
    return out


def mapping(psql):
    """(map, None) or (None, (status, detail)) for the database as a whole."""
    if not psql:
        return None, ("UNREACHABLE", "no --psql / UPG_PSQL: no database to ask")
    try:
        m = pgmap.build(psql)
    except pgmap.PsqlError as e:
        if WARM.search(str(e)) and "connection" not in str(e).lower():
            return None, ("WARMING", f"the runtime's mapping tables are not there yet: {str(e)[:200]}")
        return None, ("UNREACHABLE", f"the database did not answer: {str(e)[:200]}")
    if not m["entities"]:
        return None, ("WARMING", "mendixsystem$entity is empty: the runtime has not synchronised the database yet")
    return m, None


def missing_table(m, oql):
    """The entity of the query whose table the mapping lists but the database does not have (a runtime still creating
    its tables), else None."""
    for name in re.findall(r"\b([A-Za-z_]\w*\.[A-Za-z_]\w*)\b", oql):
        e = m["entities"].get(name)
        if e is not None and not e["table"]:
            return name
    return None


def check_journey(psql, m, seeds):
    """(status, seed name, detail) of one journey's seeds, run in order as the engine runs them."""
    vars_ = {}
    for s in seeds:
        name, text = s.get("name", "?"), re.sub(r"\{\{(\w+)\}\}", lambda x: vars_.get(x.group(1), x.group(0)), str(s.get("sql", "")))
        try:
            sql = pgmap.translate(text, m)
        except pgmap.Untranslatable as e:
            gone = missing_table(m, text)
            if gone:
                return "WARMING", name, f"{name}: {gone} is mapped but its table is not in the database yet"
            return "QUERY-ERROR", name, f"{name}: not translated: {e}"
        try:
            rows = pgmap.run_query(psql, sql)
        except pgmap.PsqlError as e:
            if "connection" in str(e).lower() or "could not connect" in str(e).lower() or "did not run" in str(e):
                return "UNREACHABLE", name, f"{name}: the database did not answer: {str(e)[:200]}"
            return "QUERY-ERROR", name, f"{name}: the SQL failed: {str(e)[:200]}"
        v = rows[0][0] if rows and rows[0] else None
        if v is None or v == "":   # the engine's test (resolveSeeds): null or '' is "returned nothing"
            return "EMPTY", name, f"{name} returned nothing: {'0 rows' if not rows else 'first value is NULL or empty'}"
        vars_[name] = str(v)
    return "OK", None, ", ".join(f"{k}={v[:40]}" for k, v in vars_.items())


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("gen_dir")
    ap.add_argument("--psql", default=os.environ.get("UPG_PSQL") or None)
    ap.add_argument("--out")
    ap.add_argument("--only", help="comma list of journey ids")
    a = ap.parse_args()
    if not (Path(a.gen_dir) / "journeys").is_dir():
        print(f"fixture_check: {a.gen_dir}: no journeys/ folder (gen_journeys.py writes <gen-dir>/journeys/<role>/)", file=sys.stderr)
        sys.exit(2)
    js = journeys(a.gen_dir, set(a.only.split(",")) if a.only else None)
    seeded = [j for j in js if j[2]]
    m, fault = mapping(a.psql) if seeded else (None, None)
    rows = {}
    for jid, role, seeds in js:
        if not seeds:
            rows[jid] = {"role": role, "status": "NO-SEEDS", "seed": None, "detail": "the journey asks the database nothing"}
        elif fault:
            rows[jid] = {"role": role, "status": fault[0], "seed": seeds[0].get("name"), "detail": fault[1]}
        else:
            st, seed, detail = check_journey(a.psql, m, seeds)
            rows[jid] = {"role": role, "status": st, "seed": seed, "detail": detail}
    c = {s: sum(1 for r in rows.values() if r["status"] == s) for s in STATUSES}
    line = (f"fixture: {len(rows)} journeys · {len(seeded)} with seeds · OK {c['OK']} · EMPTY {c['EMPTY']} · "
            f"QUERY-ERROR {c['QUERY-ERROR']} · WARMING {c['WARMING']} · UNREACHABLE {c['UNREACHABLE']}")
    for jid, r in rows.items():
        if r["status"] != "NO-SEEDS":
            print(f"  {r['status']:11} {jid:50} {r['detail'][:160]}")
    print(line)
    faults = c["QUERY-ERROR"] + c["WARMING"] + c["UNREACHABLE"]
    if faults:
        print("  a fault, not a finding: fix the stack or the query and run again; do not seed on the strength of it")
    elif c["EMPTY"]:
        print("  EMPTY: the fixture is absent: seed it before the run (fixture-seeding.md), or cite this file as FIXTURE "
              "evidence for the journeys that fail on the baseline (run_journeys.py --baseline-evidence)")
    if a.out:
        Path(a.out).write_text(json.dumps({"tool": "fixture_check", "line": line, "counts": c, "journeys": rows}, indent=1, ensure_ascii=False) + "\n")
    sys.exit(2 if faults else 1 if c["EMPTY"] else 0)


if __name__ == "__main__":
    main()
