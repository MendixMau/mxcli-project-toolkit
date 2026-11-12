#!/usr/bin/env python3
"""Entity / attribute / association -> table / column, read from the runtime's own mapping tables; the journey
engine's data instrument on PostgreSQL (E2E-9, E5b-11).

    pgmap.py map    --psql CMD [--out map.json]          check the mapping against the database, write it
    pgmap.py sql    (--psql CMD | --map map.json) OQL     the SQL an OQL query becomes (nothing is run)
    pgmap.py query  --psql CMD [--map map.json] OQL       run it: one JSON row per line (typed, row_to_json)
    pgmap.py counts --psql CMD [--map map.json]           {"<Entity or Association>": rows} for the effect record

Why: the engine's seeds, data and outcome rungs ask OQL through `mxcli oql --direct`, which a runapp/m2ee runtime does
not answer (E5b-11), so every data check came out INVALID and create-save could only be judged by its screen. Every
run has the app's Postgres (mig-pg); run_journeys.py points the engine copy at it with UPG_PSQL (bin/pgdata.js).

Names come ONLY from mendixsystem$entity, $attribute and $association, never from the model names (T2-1: the save
that wrote nothing was found by create-save alone; a guessed column there would have measured another table):
- an inherited attribute lives in the generalization's table: joined on id, as the runtime stores it;
- association storage is read from the mapping: table storage (a join table with parent and child columns) or column
  storage (table_name is the owner entity's table, parent_column_name is "id", the FK is child_column_name). A row
  where the two disagree is a mapping problem and the association is refused, never guessed;
- PostgreSQL keeps 63 bytes of an identifier: a mapped name that is not in information_schema but whose 63-byte prefix
  is, is that table or column (what CREATE did with it). Anything else not in the database is a problem, refused.
seed_pg.py reads the mapping through these loaders (one place).

OQL understood: SELECT ... FROM Module.Entity [AS a] [[INNER|LEFT [OUTER]] JOIN a/Module.Assoc/Module.Target AS t]...
[WHERE ...] [ORDER BY ...] [LIMIT n] [OFFSET n], with a.Attr, bare Attr of the FROM entity, ID, literals and the usual
operators and functions. Anything else (an unknown name, JOIN ... ON, a path in WHERE) exits 1 with the reason: no
measurement is ever made on a guessed translation. A text that starts with /*sql*/ is run as it is.
Exit: 0 ok; 1 not translatable / mapping problem; 2 the database did not answer (psql failed).
"""
import argparse, json, os, re, shlex, subprocess, sys

NOISE = os.environ.get("UPG_EFFECT_IGNORE", r"^System\.(Session|TokenInformation|ScheduledEventInformation|QueuedTask"
                       r"|ProcessedQueueTask|UserReportInfo|Session_User|UserReportInfo_User|SessionLog\w*"
                       r"|TokenInformation_User|XASInstance|TaskQueueToken)$")
# Rows the runtime itself writes during any click (sessions, tokens, task queue) or at start (B4N1-10: XASInstance, one
# row per cluster node, re-registered at every start, so its count depends on how many starts the database copy saw;
# TaskQueueToken, the task queue's per-node lease): not an effect of the action. run_journeys.py applies the same
# pattern when it compares two effect records, so a record taken before this list grew is judged the same way.

Q_ENT = 'select id, entity_name, table_name, superentity_id from "mendixsystem$entity" where not coalesce(remote,false)'
Q_ENT_NOREMOTE = 'select id, entity_name, table_name, superentity_id from "mendixsystem$entity"'
Q_ATTR = 'select entity_id, attribute_name, column_name, type, coalesce(length,0) from "mendixsystem$attribute"'
Q_ASSOC = ('select association_name, table_name, parent_entity_id, child_entity_id, parent_column_name, child_column_name '
           'from "mendixsystem$association"')
Q_COLS = "select table_name, column_name from information_schema.columns where table_schema='public'"


class PsqlError(Exception):
    pass


class Untranslatable(Exception):
    pass


def q(psql, sql, timeout=60):
    """Rows of one statement (tab separated, psql -tA). PsqlError when psql fails or does not answer."""
    try:
        r = subprocess.run(shlex.split(psql) + ["-X", "-tA", "-F", "\t", "-v", "ON_ERROR_STOP=1"], input=sql,
                           capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired) as e:
        raise PsqlError(f"psql did not run: {e}")
    if r.returncode:
        raise PsqlError((r.stderr or r.stdout or f"psql exit {r.returncode}").strip()[:600])
    return [l.split("\t") for l in r.stdout.splitlines() if l]


def trunc63(name):
    return name.encode("utf-8")[:63].decode("utf-8", "ignore")


# --- raw loaders (seed_pg.py uses these) --------------------------------------------------------------------------
def entities(psql):
    """{id: {"name", "table", "super"}}; remote (external) entities left out when the column exists."""
    try:
        rows = q(psql, Q_ENT)
    except PsqlError as e:
        if "remote" not in str(e):
            raise
        rows = q(psql, Q_ENT_NOREMOTE)   # older runtimes have no remote column
    return {r[0]: {"name": r[1], "table": r[2], "super": (r[3] if len(r) > 3 else "") or None} for r in rows}


def attributes(psql):
    """{entity_id: [(name, column, type, length)]}."""
    out = {}
    for eid, name, col, typ, length in q(psql, Q_ATTR):
        out.setdefault(eid, []).append((name, col, int(typ or 0), int(length or 0)))
    return out


def columns(psql):
    out = {}
    for t, c in q(psql, Q_COLS):
        out.setdefault(t, set()).add(c)
    return out


def associations(psql, ents):
    """[{"name", "table", "parent", "child" (entity ids), "pcol", "ccol", "storage": "table"|"column"|None, "why"}].
    Storage from the mapping: column storage = table_name is an entity table (the owner's or its generalization's) and
    parent_column_name is "id"; table storage = neither. One without the other is refused (storage None)."""
    ent_tables = {e["table"] for e in ents.values()}
    out = []
    for name, table, pid, cid, pcol, ccol in q(psql, Q_ASSOC):
        a = {"name": name, "table": table, "parent": pid, "child": cid, "pcol": pcol, "ccol": ccol, "storage": None, "why": ""}
        owner_tables, e = set(), pid
        while e and e in ents:
            owner_tables.add(ents[e]["table"]); e = ents[e]["super"]
        on_entity, id_col = table in ent_tables, pcol == "id"
        if on_entity and id_col and table in owner_tables:
            a["storage"] = "column"
        elif not on_entity and not id_col:
            a["storage"] = "table"
        else:
            a["why"] = (f"mapping row is inconsistent: table {table} {'is' if on_entity else 'is not'} an entity table, "
                        f"parent_column_name is {pcol!r}" + ("" if not on_entity or table in owner_tables else ", and the table is not the owner's"))
        out.append(a)
    return out


# --- the checked mapping ----------------------------------------------------------------------------------------
def build(psql):
    """The mapping by NAME, every table and column checked against information_schema (63-byte rule applied)."""
    ents, attrs, cols = entities(psql), attributes(psql), columns(psql)
    problems, truncated = [], []

    def real_table(t):
        if t in cols: return t
        if trunc63(t) in cols:
            truncated.append(f"{t} -> {trunc63(t)}"); return trunc63(t)
        return None

    def real_col(t, c):
        if t is None: return None
        if c in cols.get(t, ()): return c
        if trunc63(c) in cols.get(t, ()):
            truncated.append(f"{t}.{c} -> {trunc63(c)}"); return trunc63(c)
        return None

    m = {"entities": {}, "associations": {}, "problems": problems, "truncated": truncated}
    for eid, e in ents.items():
        t = real_table(e["table"])
        if t is None:
            problems.append(f"entity {e['name']}: table {e['table']} is not in the database")
        sup = ents.get(e["super"], {}).get("name") if e["super"] else None
        at = {}
        for name, col, typ, _ in attrs.get(eid, []):
            c = real_col(t, col)
            if c is None:
                if t is not None:
                    problems.append(f"attribute {e['name']}.{name}: column {e['table']}.{col} is not in the database")
                continue
            at[name] = {"column": c, "type": typ}
        m["entities"][e["name"]] = {"table": t, "super": sup, "attrs": at}
    for a in associations(psql, ents):
        p, c = ents.get(a["parent"], {}).get("name"), ents.get(a["child"], {}).get("name")
        row = {"parent": p, "child": c, "storage": a["storage"], "table": real_table(a["table"]),
               "pcol": None, "ccol": None}
        if a["storage"] is None:
            problems.append(f"association {a['name']}: {a['why']}")
        elif row["table"] is None:
            problems.append(f"association {a['name']}: table {a['table']} is not in the database"); row["storage"] = None
        else:
            row["ccol"] = real_col(row["table"], a["ccol"])
            row["pcol"] = "id" if a["storage"] == "column" else real_col(row["table"], a["pcol"])
            if row["ccol"] is None or row["pcol"] is None:
                problems.append(f"association {a['name']}: column {a['ccol']} / {a['pcol']} of {a['table']} is not in the database")
                row["storage"] = None
        if not p or not c:
            problems.append(f"association {a['name']}: parent or child entity is not in mendixsystem$entity"); row["storage"] = None
        m["associations"][a["name"]] = row
    return m


def load(psql=None, mapfile=None):
    if mapfile and os.path.exists(mapfile):
        return json.load(open(mapfile))
    if not psql:
        raise Untranslatable("no mapping: give --psql or --map")
    return build(psql)


def summary_line(m):
    a = m["associations"].values()
    return (f"pgmap: {len(m['entities'])} entities, {sum(len(e['attrs']) for e in m['entities'].values())} attributes, "
            f"{len(m['associations'])} associations ({sum(1 for x in a if x['storage'] == 'table')} table storage, "
            f"{sum(1 for x in a if x['storage'] == 'column')} column storage), {len(m['truncated'])} names cut at 63 bytes, "
            f"{len(m['problems'])} problems")


# --- OQL -> SQL ---------------------------------------------------------------------------------------------------
TOK = re.compile(r"""(?P<s>'(?:[^']|'')*')|(?P<path>[A-Za-z_]\w*(?:/[A-Za-z_]\w*\.[A-Za-z_]\w*)+)|"""
                 r"""(?P<n>[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)|(?P<num>\d+(?:\.\d+)?)|(?P<ws>\s+)|(?P<o>.)""", re.S)
KEYWORDS = set("""SELECT FROM WHERE AND OR NOT AS ORDER BY ASC DESC LIMIT OFFSET IN IS NULL LIKE ILIKE DISTINCT INNER
LEFT RIGHT OUTER FULL JOIN GROUP HAVING TRUE FALSE CASE WHEN THEN ELSE END BETWEEN EXISTS ALL ANY""".split())


def qi(name):
    return '"' + name.replace('"', '""') + '"'


class Tr:
    def __init__(self, m):
        self.m = m
        self.ents = m["entities"]
        self.aliases = {}        # alias -> entity name
        self.joins = []          # SQL join clauses, in order
        self.anc = {}            # (alias, table) -> sql alias of that generalization table
        self.kind = {}           # alias -> "INNER" | "LEFT"

    def ent(self, name):
        if name in self.ents and self.ents[name]["table"]:
            return name
        hits = [n for n in self.ents if n.lower() == name.lower() and self.ents[n]["table"]]
        if len(hits) == 1:
            return hits[0]
        raise Untranslatable(f"entity {name} is not in mendixsystem$entity (or its table is missing)")

    def chain(self, e):
        out = []
        while e:
            out.append(e); e = self.ents.get(e, {}).get("super")
        return out

    def is_a(self, x, y):
        return y in self.chain(x)

    def table_ref(self, alias, table):
        """SQL alias that has `table` for this object: its own, or a generalization's joined on id."""
        if self.ents[self.aliases[alias]]["table"] == table:
            return alias
        k = (alias, table)
        if k not in self.anc:
            a2 = f"{alias}__{len(self.anc) + 1}"
            self.anc[k] = a2
            self.joins.append(f"{self.kind.get(alias, 'INNER')} JOIN {qi(table)} AS {qi(a2)} ON {qi(a2)}.id = {qi(alias)}.id")
        return self.anc[k]

    def attr(self, alias, name):
        if name.lower() == "id":
            return f"{qi(alias)}.id"
        for e in self.chain(self.aliases[alias]):
            at = self.ents[e]["attrs"]
            hit = name if name in at else next((k for k in at if k.lower() == name.lower()), None)
            if hit:
                return f"{qi(self.table_ref(alias, self.ents[e]['table']))}.{qi(at[hit]['column'])}"
        raise Untranslatable(f"attribute {self.aliases[alias]}.{name} is not in mendixsystem$attribute")

    def assoc(self, name):
        A = self.m["associations"]
        hit = name if name in A else next((k for k in A if k.lower() == name.lower()), None)
        if not hit:
            raise Untranslatable(f"association {name} is not in mendixsystem$association")
        if not A[hit]["storage"]:
            raise Untranslatable(f"association {hit}: storage unknown (see pgmap.py map problems)")
        return hit, A[hit]

    def path_join(self, kind, path, alias):
        parts = path.split("/")
        src = parts[0]
        if src not in self.aliases:
            raise Untranslatable(f"join path {path} starts at {src}, which is no alias in this query")
        hops = list(zip(parts[1::2], parts[2::2]))
        for i, (an, tn) in enumerate(hops):
            name, a = self.assoc(an)
            tgt = self.ent(tn)
            X = self.aliases[src]
            rel = lambda x, y: self.is_a(x, y) or self.is_a(y, x)
            if self.is_a(X, a["parent"]) and rel(tgt, a["child"]):
                fwd = True
            elif self.is_a(X, a["child"]) and rel(tgt, a["parent"]):
                fwd = False
            else:
                raise Untranslatable(f"{name} links {a['parent']} and {a['child']}, not {X} and {tgt}")
            dst = alias if i == len(hops) - 1 else f"{alias}__h{i}"
            self.aliases[dst] = tgt; self.kind[dst] = kind
            ttab = qi(self.ents[tgt]["table"])
            if a["storage"] == "table":
                j = f"{alias}__j{i}"
                mine, other = (a["pcol"], a["ccol"]) if fwd else (a["ccol"], a["pcol"])
                self.joins.append(f"{kind} JOIN {qi(a['table'])} AS {qi(j)} ON {qi(j)}.{qi(mine)} = {qi(src)}.id")
                self.joins.append(f"{kind} JOIN {ttab} AS {qi(dst)} ON {qi(dst)}.id = {qi(j)}.{qi(other)}")
            elif fwd:   # the FK is on the source object's (owner's) table
                fk = f"{qi(self.table_ref(src, a['table']))}.{qi(a['ccol'])}"
                self.joins.append(f"{kind} JOIN {ttab} AS {qi(dst)} ON {qi(dst)}.id = {fk}")
            elif self.ents[tgt]["table"] == a["table"]:
                self.joins.append(f"{kind} JOIN {ttab} AS {qi(dst)} ON {qi(dst)}.{qi(a['ccol'])} = {qi(src)}.id")
            else:       # the FK is on a generalization table of the target
                j = f"{alias}__j{i}"
                self.joins.append(f"{kind} JOIN {qi(a['table'])} AS {qi(j)} ON {qi(j)}.{qi(a['ccol'])} = {qi(src)}.id")
                self.joins.append(f"{kind} JOIN {ttab} AS {qi(dst)} ON {qi(dst)}.id = {qi(j)}.id")
            src = dst


def translate(oql, m):
    """OQL text -> PostgreSQL text, or Untranslatable with the reason."""
    s = oql.strip().rstrip(";")
    if s.startswith("/*sql*/"):
        return s[len("/*sql*/"):].strip()
    toks = [(k, v) for mt in TOK.finditer(s) for k, v in mt.groupdict().items() if v is not None]
    U = lambda i: toks[i][1].upper() if i < len(toks) and toks[i][0] == "n" else None
    sig = [i for i, t in enumerate(toks) if t[0] != "ws"]   # positions of significant tokens
    tr = Tr(m)
    # locate FROM ... (the FROM segment ends at WHERE / ORDER / GROUP / LIMIT / OFFSET / HAVING / end)
    fi = next((j for j, i in enumerate(sig) if U(i) == "FROM"), None)
    if fi is None:
        raise Untranslatable("no FROM")
    if any(U(i) == "FROM" for i in sig[fi + 1:]) or any(U(i) == "SELECT" for i in sig[1:]):
        raise Untranslatable("subqueries are not translated")
    end = next((j for j in range(fi + 1, len(sig)) if U(sig[j]) in ("WHERE", "ORDER", "GROUP", "LIMIT", "OFFSET", "HAVING")), len(sig))
    seg = sig[fi + 1:end]
    if not seg or toks[seg[0]][0] != "n":
        raise Untranslatable("FROM needs Module.Entity")
    main = tr.ent(toks[seg[0]][1]); p = 1; alias = "q0"
    if p < len(seg) and U(seg[p]) == "AS": p += 1
    if p < len(seg) and toks[seg[p]][0] == "n" and U(seg[p]) not in KEYWORDS:
        alias = toks[seg[p]][1]; p += 1
    tr.aliases[alias] = main; tr.kind[alias] = "INNER"
    from_sql = f"FROM {qi(tr.ents[main]['table'])} AS {qi(alias)}"
    while p < len(seg):
        kind = "INNER"
        if U(seg[p]) in ("INNER",): p += 1
        elif U(seg[p]) == "LEFT":
            kind = "LEFT"; p += 1
            if p < len(seg) and U(seg[p]) == "OUTER": p += 1
        if p >= len(seg) or U(seg[p]) != "JOIN":
            raise Untranslatable(f"FROM clause not understood near {toks[seg[p]][1]!r}" if p < len(seg) else "FROM clause ends early")
        p += 1
        if p >= len(seg) or toks[seg[p]][0] != "path":
            raise Untranslatable("only JOIN alias/Module.Association/Module.Entity paths are translated (no JOIN ... ON)")
        path = toks[seg[p]][1]; p += 1
        if p < len(seg) and U(seg[p]) == "AS": p += 1
        if p >= len(seg) or toks[seg[p]][0] != "n":
            raise Untranslatable(f"JOIN {path} needs an alias")
        tr.path_join(kind, path, toks[seg[p]][1]); p += 1
    # rewrite names outside the FROM segment
    out_alias = set()
    for j, i in enumerate(sig):
        if U(i) == "AS" and j + 1 < len(sig) and toks[sig[j + 1]][0] == "n":
            out_alias.add(toks[sig[j + 1]][1].lower())
    seg_set = set(range(sig[fi], sig[end - 1] + 1)) if end > fi else set()
    parts = []
    for idx, (k, v) in enumerate(toks):
        if idx in seg_set:
            if idx == sig[fi]:
                parts.append("\x00FROM\x00")
            continue
        if k == "path":
            raise Untranslatable(f"association path {v} outside FROM is not translated")
        if k == "n":
            nxt = next((toks[t][1] for t in range(idx + 1, len(toks)) if toks[t][0] != "ws"), "")
            prev = next((toks[t][1].upper() for t in range(idx - 1, -1, -1) if toks[t][0] != "ws"), "")
            if v.upper() in KEYWORDS or nxt == "(" or prev == "AS":
                parts.append(v); continue
            if "." in v:
                head, rest = v.split(".", 1)
                if head in tr.aliases and "." not in rest:
                    parts.append(tr.attr(head, rest)); continue
                raise Untranslatable(f"{v}: not alias.Attribute of this query")
            if v.lower() in out_alias:      # ORDER BY n: the output name, folded the same way as where it was set
                parts.append(v); continue
            parts.append(tr.attr(alias, v)); continue
        parts.append(v)
    sql = "".join(parts)
    return sql.replace("\x00FROM\x00", " ".join([from_sql] + tr.joins)).strip()


def run_query(psql, sql):
    """Typed rows: each row through row_to_json, so a boolean is true/false and a number stays a number."""
    rows = q(psql, f"SELECT row_to_json(q) FROM ({sql}) q")
    return [list(json.loads("\t".join(r)).values()) for r in rows]


def counts(psql, m):
    """Rows per entity table and per association (join table rows, or set FKs on a column-stored owner table)."""
    noise = re.compile(NOISE)
    parts = []
    for n, e in sorted(m["entities"].items()):
        if e["table"] and not noise.search(n):
            parts.append(f"SELECT '{n}' AS k, COUNT(*) AS n FROM {qi(e['table'])}")
    for n, a in sorted(m["associations"].items()):
        if not a["storage"] or noise.search(n):
            continue
        if a["storage"] == "table":
            parts.append(f"SELECT '{n}' AS k, COUNT(*) AS n FROM {qi(a['table'])}")
        else:
            parts.append(f"SELECT '{n}' AS k, COUNT({qi(a['ccol'])}) AS n FROM {qi(a['table'])}")
    if not parts:
        return {}
    return {k: int(n) for k, n in q(psql, "\nUNION ALL\n".join(parts) + ";")}


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("cmd", choices=["map", "sql", "query", "counts"])
    ap.add_argument("oql", nargs="?")
    ap.add_argument("--psql", default=os.environ.get("UPG_PSQL"))
    ap.add_argument("--map", dest="mapfile", default=os.environ.get("UPG_PGMAP") or None)
    ap.add_argument("--out")
    a = ap.parse_args()
    try:
        if a.cmd == "map":
            if not a.psql:
                print("pgmap: --psql (or UPG_PSQL) is required", file=sys.stderr); sys.exit(1)
            m = build(a.psql)
            if a.out:
                open(a.out, "w").write(json.dumps(m, indent=1) + "\n")
            print(summary_line(m))
            for p in m["problems"][:20]:
                print(f"  problem: {p}")
            for t in m["truncated"][:20]:
                print(f"  cut at 63 bytes: {t}")
            sys.exit(0)
        m = load(a.psql, a.mapfile)
        if a.cmd == "sql":
            print(translate(a.oql or "", m)); return
        if not a.psql:
            raise Untranslatable("--psql (or UPG_PSQL) is required to run a query")
        if a.cmd == "query":
            for r in run_query(a.psql, translate(a.oql or "", m)):
                print(json.dumps(r))
            return
        print(json.dumps(counts(a.psql, m), sort_keys=True))
    except Untranslatable as e:
        print(f"pgmap: not translated: {e}", file=sys.stderr); sys.exit(1)
    except PsqlError as e:
        print(f"pgmap: database did not answer: {e}", file=sys.stderr); sys.exit(2)


if __name__ == "__main__":
    main()
