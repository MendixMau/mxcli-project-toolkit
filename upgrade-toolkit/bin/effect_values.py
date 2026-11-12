#!/usr/bin/env python3
"""D2 effect values: the VALUES a journey wrote, old app against new app, not only the row counts (quality-judgement
plan, L2 / build item 5).

    effect_values.py snap    --psql CMD [--map map.json] [--model APP] --entities E1,E2 --out snap.json
    effect_values.py compare OLD.json NEW.json [--accept accept.txt]

Why: pgmap.py counts (the effect record of a journey step) cannot see a save that wrote 0 instead of 42, or one that
dropped an association, when the row counts match. This reads the business values of the entities, through pgmap's
own mapping and OQL translation (no SQL mapping of its own), and compares them across the two apps.

Column classes:
  id        the object id ($id in a snapshot). Stored for matching, never compared.
  system    createddate, changeddate and the owner / changedby members (by name). Stored, never compared.
  sequence  AutoNumber. Stored, never compared.
  hash      HashString: stored as present / absent only; no hash value is ever written to a snapshot or compared.
  business  everything else. Compared.
  assoc     an association: the sorted list of the TARGET rows' business values (never the raw target id). An
            association with no target is []. Targets' own id / system / sequence columns are not stored.
With --model APP (an app dir or .mpr, read with mprmodel.py) the sequence and hash classes come ONLY from each
attribute's type in the domain model (DomainModels$AutoNumberAttributeType, DomainModels$HashStringAttributeType). An
attribute of the entity or its generalizations that the model does not declare is refused (the entity is INVALID).
Without --model, a name heuristic is used: sequence = mendixsystem$attribute.type 0 (seed_pg.py's val() also takes 3
as an integer), hash = type 30 with "password" in the column name. That is printed once to stderr, recorded in the
snapshot as "classes_from", and compare prints "column classes: heuristic on OLD/NEW" when a side used it. The
heuristic cannot see a HashString that is not named like a password: that value is compared and stored raw, as
business. That is why --model exists, and why the heuristic runs only when asked for with --no-model: a real app's
database is never read without the model by default (a raw hash would land in the snapshot).
Inherited attributes are read from the generalization chain. Self-associations are read in one direction only.
Entities in pgmap.NOISE (runtime housekeeping: sessions, tokens, queues) are skipped, as counts() skips them.

Rows are matched between the runs by the multiset of their business values (ids differ between runs). A row that does
not match is paired with the most similar unmatched row of the other run, and the differing values are named.

Verdicts per entity: same / REVIEW (differing attribute, old value, new value) / INVALID (not measured on one side:
a mapping problem, the entity missing from one model, or an association that pgmap refuses). INVALID is never "same".
An entity that is not in one of the two snapshots is INVALID, so a model that dropped it cannot pass.

snap      --psql (or UPG_PSQL) or --map. Writes the snapshot; exit 0 when written (entities that could not be measured
          are recorded in it and judged INVALID by compare), 2 on usage or when the database did not answer.
compare   exit 0 all same or accepted; 1 any REVIEW; 3 any INVALID (3 wins over 1). 2 on usage or an unreadable file.
--accept  lines "fnmatch-pattern # reason" (the reason is required, as run_journeys --effect-accept): the pattern is
          matched against "<Entity>.<attribute>" or "<Entity>". An accepted difference is reported as accepted, and
          the entity counts as same.

Which step produces the inputs: NO mandatory step produces snapshots yet. Nothing in run_journeys.py or gate.sh calls
snap or compare; this is a standalone instrument, run by hand. Wiring it into the journey effect record (a snapshot
before and after each step) and into the gate is a later build item.
"""
import argparse, fnmatch, json, os, re, sys
from collections import Counter

import pgmap

FORMAT = "effect-values/1"
SYSTEM_NAMES = {"createddate", "changeddate", "owner", "changedby"}
SYSTEM_ASSOC = {"System.owner", "System.changedBy"}
COMPARED = ("business", "hash", "assoc")
ABSENT = "<absent>"


class Usage(Exception):
    pass


# --- classes ------------------------------------------------------------------------------------------------------
HEURISTIC = "name heuristic (no --model)"


def is_system(name, column):
    return name.lower() in SYSTEM_NAMES or column.lower() in SYSTEM_NAMES


def classify(name, column, typ, mtype=None, by_model=False):
    """by_model: sequence and hash come only from the model's attribute type (mtype); else the name heuristic."""
    if is_system(name, column):
        return "system"
    if by_model:
        return {"AutoNumber": "sequence", "HashString": "hash"}.get(mtype, "business")
    if typ == 0:
        return "sequence"
    if typ == 30 and "password" in column.lower():
        return "hash"
    return "business"


def model_types(path):
    """{"Module.Entity": {"Attribute": "AutoNumber" | "HashString" | ...}} from the domain models (mprmodel.py)."""
    try:
        from mprmodel import Model
        m = Model.load(path)
    except SystemExit as x:
        raise Usage(f"--model {path}: {x}")
    lst = lambda x: [i for i in (x or []) if isinstance(i, dict)]   # BSON arrays carry an int marker first
    out = {}
    for d in m.docs.values():
        if d.type != "DomainModels$DomainModel":
            continue
        for e in lst(d.data.get("Entities")):
            types = out.setdefault(f"{d.module}.{e.get('Name')}", {})
            for a in lst(e.get("Attributes")):
                t = a.get("NewType") or a.get("Type") or {}
                types[a.get("Name")] = (t.get("$Type", "") if isinstance(t, dict) else "").split("$")[-1].replace("AttributeType", "") or "unknown"
    return out


def model_type(m, mtypes, entity, name):
    """The domain-model type of an attribute, looked up along the generalization chain; None when not declared."""
    e = entity
    while e and e in m["entities"]:
        t = mtypes.get(e, {}).get(name)
        if t is not None:
            return t
        e = m["entities"][e]["super"]
    return None


def column_class(m, mtypes, entity, name, column, typ):
    """-> class. Under --model an undeclared, non-system attribute is refused: its class is unknown, never guessed."""
    if mtypes is None:
        return classify(name, column, typ)
    mt = model_type(m, mtypes, entity, name)
    if mt is None and not is_system(name, column):
        raise pgmap.Untranslatable(f"attribute {entity}.{name} is not declared in the model: its class is unknown")
    return classify(name, column, typ, mt, by_model=True)


def stored(v, cls):
    """What a snapshot keeps of one value: a hash is kept as present / absent only."""
    return bool(v) if cls == "hash" else v


def attr_list(m, entity):
    """{attribute name: (column, type)} of an entity, inherited attributes included (the most specific name wins)."""
    out, e = {}, entity
    while e and e in m["entities"]:
        for name, info in m["entities"][e]["attrs"].items():
            out.setdefault(name, (info["column"], info["type"]))
        e = m["entities"][e]["super"]
    return out


def touches(a, entity):
    return entity in (a["parent"], a["child"])


# --- snap ---------------------------------------------------------------------------------------------------------
def snap_entity(psql, m, entity, mtypes=None):
    """One entity's snapshot: {"columns": {key: class}, "rows": [{key: value}]}. Raises pgmap.Untranslatable."""
    attrs = attr_list(m, entity)
    names = list(attrs)
    cls = {n: column_class(m, mtypes, entity, n, attrs[n][0], attrs[n][1]) for n in names}
    cols = {"$id": "id", **cls}
    sql = pgmap.translate("SELECT " + ", ".join(["a.ID AS k"] + [f"a.{n} AS c{i}" for i, n in enumerate(names)])
                          + f" FROM {entity} AS a", m)
    rows = {}
    for r in pgmap.run_query(psql, sql):
        d = {"$id": r[0]}
        for i, n in enumerate(names):
            d[n] = stored(r[1 + i], cls[n])
        rows[r[0]] = d
    for a_name, a in sorted(m["associations"].items()):
        if not a["storage"] or not touches(a, entity) or a_name in SYSTEM_ASSOC or re.search(pgmap.NOISE, a_name):
            continue
        target = a["child"] if a["parent"] == entity else a["parent"]
        t_attrs = attr_list(m, target)
        t_cls = {n: column_class(m, mtypes, target, n, t_attrs[n][0], t_attrs[n][1]) for n in t_attrs}
        t_names = [n for n in t_attrs if t_cls[n] in COMPARED]
        sql = pgmap.translate("SELECT " + ", ".join(["a.ID AS k"] + [f"t.{n} AS c{i}" for i, n in enumerate(t_names)]
                                                   + ["t.ID AS p"])
                              + f" FROM {entity} AS a LEFT JOIN a/{a_name}/{target} AS t", m)
        got = {}
        for r in pgmap.run_query(psql, sql):
            if r[-1] is None:
                continue          # no target on this row
            tgt = {n: stored(r[1 + i], t_cls[n]) for i, n in enumerate(t_names)}
            got.setdefault(r[0], []).append(tgt)
        for k, d in rows.items():
            d[a_name] = sorted(got.get(k, []), key=lambda x: json.dumps(x, sort_keys=True))
        cols[a_name] = "assoc"
    return {"columns": cols, "rows": list(rows.values())}


def cmd_snap(a):
    if not a.psql:
        raise Usage("snap needs --psql (or UPG_PSQL): the rows are read from the database")
    if not a.model and not a.no_model:
        raise Usage("snap needs --model APP (column classes from the domain model); --no-model runs the name heuristic, "
                    "which stores a HashString not named like a password raw: never on a real app's database")
    mtypes = model_types(a.model) if a.model else None
    if mtypes is None:
        print(f"effect values snap: column classes from the {HEURISTIC}: sequence and hash are guessed from the "
              "database, pass --model APP to read them from the model", file=sys.stderr)
    wanted = [e.strip() for e in (a.entities or "").split(",") if e.strip()]
    if not wanted:
        raise Usage("snap needs --entities E1,E2")
    if not a.out:
        raise Usage("snap needs --out")
    m = pgmap.load(a.psql, a.mapfile)
    out = {"format": FORMAT, "classes_from": "model" if mtypes is not None else HEURISTIC,
           "entities": {}, "invalid": {}, "missing": [], "skipped": []}
    for e in wanted:
        if re.search(pgmap.NOISE, e):
            out["skipped"].append(e); continue
        if e not in m["entities"]:
            out["missing"].append(e); continue
        if not m["entities"][e]["table"]:
            out["invalid"][e] = "its table is not in the database"; continue
        why = [p for p in m["problems"] if p.startswith(f"entity {e}:") or p.startswith(f"attribute {e}.")]
        why += [p for p in m["problems"] if p.startswith("association ") and any(
            touches(a, e) and p.startswith(f"association {n}:") for n, a in m["associations"].items())]
        if why:
            out["invalid"][e] = "mapping problem: " + "; ".join(why); continue
        try:
            out["entities"][e] = snap_entity(a.psql, m, e, mtypes)
        except pgmap.Untranslatable as x:
            out["invalid"][e] = f"not translated: {x}"
    open(a.out, "w").write(json.dumps(out, indent=1, sort_keys=True) + "\n")
    n_rows = sum(len(v["rows"]) for v in out["entities"].values())
    print(f"effect values snap: {len(out['entities'])} entities, {n_rows} rows, {len(out['invalid'])} not measured, "
          f"{len(out['missing'])} missing from the model, {len(out['skipped'])} skipped (runtime housekeeping) -> {a.out}")
    for e, why in sorted(out["invalid"].items()):
        print(f"  not measured: {e}: {why}")
    for e in out["missing"]:
        print(f"  missing from the model: {e}")


# --- compare ------------------------------------------------------------------------------------------------------
def load_snapshot(path):
    try:
        s = json.loads(open(path).read())
    except (OSError, ValueError) as e:
        raise Usage(f"{path}: not a readable snapshot ({e})")
    if not isinstance(s, dict) or s.get("format") != FORMAT:
        raise Usage(f"{path}: not an {FORMAT} snapshot")
    return s


def read_accept(path):
    try:
        lines = open(path).read().splitlines()
    except OSError as e:
        raise Usage(f"--accept {path}: {e}")
    pats = []
    for i, l in enumerate(lines, 1):
        l = l.strip()
        if not l or l.startswith("#"):
            continue
        pat, _, why = l.partition(" #")
        if not pat.strip() or not why.strip():
            raise Usage(f"--accept {path}:{i}: no '# reason': {l}")
        pats.append((pat.strip(), why.strip()))
    return pats


def accepted_by(pats, entity, key):
    names = [f"{entity}.{key}", entity]
    for pat, why in pats:
        if any(fnmatch.fnmatch(n, pat) for n in names):
            return why
    return None


def disp(v, cls):
    if cls == "hash":
        return "present" if v else "absent"
    s = json.dumps(v, ensure_ascii=False, sort_keys=True)
    return s if len(s) <= 160 else s[:157] + "..."


def canon_val(v, cls):
    """The comparable form of one stored value: hash = present / absent; assoc = the multiset of target rows."""
    if cls == "hash":
        return bool(v)
    if cls == "assoc":
        return sorted(json.dumps(x, sort_keys=True) for x in (v or []))
    return v


def same_val(x, y, cls):
    return json.dumps(canon_val(x, cls), sort_keys=True) == json.dumps(canon_val(y, cls), sort_keys=True)


def plural(n):
    return "row" if n == 1 else "rows"


def row_label(row, keys):
    for k in keys:
        if row.get(k) not in (None, "", [], False):
            return f"row {disp(row.get(k), 'business')[:60]}"
    return "row (no business value)"


def compare_entity(e, old, new, pats):
    """-> (verdict "same" | "REVIEW", lines, accepted reasons). Only business / hash / assoc columns are compared."""
    ocols, ncols = old["columns"], new["columns"]
    ko = {k: c for k, c in ocols.items() if c in COMPARED}
    kn = {k: c for k, c in ncols.items() if c in COMPARED}
    diffs, acc = [], []

    def add(key, label, o, n):
        why = accepted_by(pats, e, key)
        (acc if why else diffs).append((key, label, o, n, why))

    for k in sorted(set(ko) - set(kn)):
        add(k, "(column)", "present", "absent" if k not in ncols else f"class {ncols[k]}")
    for k in sorted(k for k in ko if k in kn and ko[k] != kn[k]):
        add(k, "(column)", f"class {ko[k]}", f"class {kn[k]}")
    keys = sorted(k for k in ko if k in kn and ko[k] == kn[k])

    def canon(r):
        return tuple(json.dumps(canon_val(r.get(k), ko[k]), sort_keys=True) for k in keys)

    orows, nrows = old["rows"], new["rows"]
    lo, ln = [], []
    left = Counter(canon(r) for r in nrows)
    for r in orows:
        c = canon(r)
        if left[c] > 0:
            left[c] -= 1
        else:
            lo.append(r)
    left = Counter(canon(r) for r in orows)
    for r in nrows:
        c = canon(r)
        if left[c] > 0:
            left[c] -= 1
        else:
            ln.append(r)
    unpaired = list(ln)
    for r in lo:
        # the most similar unmatched row of the other run is the one this row became
        best = max(unpaired, key=lambda cand: sum(same_val(r.get(k), cand.get(k), ko[k]) for k in keys), default=None)
        label = row_label(r, keys)
        if best is None:
            add("(row)", label, "present", "absent")
            continue
        unpaired.remove(best)
        for k in keys:
            if not same_val(r.get(k), best.get(k), ko[k]):
                add(k, label, disp(canon_val(r.get(k), ko[k]), ko[k]), disp(canon_val(best.get(k), ko[k]), ko[k]))
    for r in unpaired:
        add("(row)", row_label(r, keys), "absent", "present")
    note = f"{len(orows)} {plural(len(orows))} old, {len(nrows)} {plural(len(nrows))} new"
    extra = sorted(set(kn) - set(ko))
    if extra:
        note += f"; not compared (new in NEW): {', '.join(extra)}"
    if not diffs:
        reasons = [f"{k}: {w}" for k, _, _, _, w in acc]
        line = f"same    {e} ({note})" + (f"; accepted: {'; '.join(reasons)}" if reasons else "")
        return "same", [line], [w for *_, w in acc]
    lines = [f"REVIEW  {e}: {note}"]
    for key, label, o, n, _ in diffs[:12]:
        if key == "(row)":
            lines.append(f"    a row is only in {'old' if o == 'present' else 'new'} ({label})")
        elif label == "(column)":
            lines.append(f"    {key}: old {o}, new {n}")
        else:
            lines.append(f"    {key}: old {o}, new {n} ({label})")
    if len(diffs) > 12:
        lines.append(f"    ... {len(diffs) - 12} more")
    return "REVIEW", lines, [w for *_, w in acc]


def not_measured(e, side, snap):
    if e in snap.get("invalid", {}):
        return f"{side} snapshot: {snap['invalid'][e]}"
    if e in snap.get("missing", []):
        return f"missing from the {side} model"
    return f"no entity in the {side} snapshot"


def cmd_compare(a):
    old, new = load_snapshot(a.old), load_snapshot(a.new)
    pats = read_accept(a.accept) if a.accept else []
    heur = [label for label, s in (("OLD", old), ("NEW", new)) if s.get("classes_from", HEURISTIC) != "model"]
    if heur:
        print(f"column classes: heuristic on {'/'.join(heur)}")
    names, skipped = set(), set()
    for s in (old, new):
        names |= set(s.get("entities", {})) | set(s.get("invalid", {})) | set(s.get("missing", []))
        skipped |= set(s.get("skipped", []))
    names -= skipped
    if not names:
        print("effect values: nothing measured in either snapshot")
        print("effect values: 0 same, 0 REVIEW, 1 INVALID (0 entities)")
        return 3
    same = review = invalid = n_acc = 0
    for e in sorted(names):
        bad = [not_measured(e, side, s) for side, s in (("old", old), ("new", new)) if e not in s.get("entities", {})]
        if bad:
            invalid += 1
            print(f"INVALID {e}: " + "; ".join(bad))
            continue
        v, lines, accepted = compare_entity(e, old["entities"][e], new["entities"][e], pats)
        n_acc += len(accepted)
        if v == "same":
            same += 1
        else:
            review += 1
        print("\n".join(lines))
    print(f"effect values: {same} same, {review} REVIEW, {invalid} INVALID ({len(names)} entities)")
    if n_acc:
        print(f"effect values: {n_acc} difference(s) accepted by --accept")
    if skipped:
        print(f"effect values: skipped as runtime housekeeping: {', '.join(sorted(skipped))}")
    return 3 if invalid else (1 if review else 0)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("snap")
    s.add_argument("--psql", default=os.environ.get("UPG_PSQL"))
    s.add_argument("--map", dest="mapfile", default=os.environ.get("UPG_PGMAP") or None)
    s.add_argument("--model", default=None, help="app dir or .mpr: column classes from the domain model")
    s.add_argument("--no-model", action="store_true", help="name heuristic instead of --model (fixtures only)")
    s.add_argument("--entities")
    s.add_argument("--out")
    c = sub.add_parser("compare")
    c.add_argument("old")
    c.add_argument("new")
    c.add_argument("--accept")
    a = ap.parse_args(argv)
    try:
        if a.cmd == "snap":
            cmd_snap(a)
            return 0
        return cmd_compare(a)
    except Usage as x:
        print(f"effect_values: {x}", file=sys.stderr)
        return 2
    except pgmap.PsqlError as x:
        print(f"effect_values: database did not answer: {x}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
