#!/usr/bin/env python3
"""Load a Marketplace template's demo data (data-snapshot.zip: an HSQLDB default.script + default.log) into the
PostgreSQL database that the SAME Mendix model already created. The toolkit's route for T5-10 and T3-11 (the workers
hand-wrote hsql2pg.py, hsqldb2pg.py and load_snapshot.py; seed_pg.py only makes synthetic rows).

ORDER (the app must create the schema first):
  1. start the app ONCE on the empty database (it creates every table and the mendixsystem$* mapping rows), stop it;
  2. seed_snapshot.py <data-snapshot.zip | folder with default.script> --psql "docker exec -i mig-pg psql -U mendix -d X"
  3. start the app again. Freeze (`createdb -T X X_frozen`) only after that (steps/baseline.md step 1).
  The load needs a superuser role (it sets session_replication_role=replica so the tables load in any order).
  File contents live outside the database: copy <snapshot>/data/files/* to the app's data/files after EVERY start
  (runapp.py wipes run/<name>/ on a start, T5-5); the report counts them when the zip has them.

  seed_snapshot.py SNAPSHOT --dry-run                 counts only, no database (parse + replay + skip rules)
  seed_snapshot.py SNAPSHOT --psql CMD --dry-run      the same plus the mapping check against the database, writes nothing
  seed_snapshot.py SNAPSHOT --psql CMD [--skip TABLE]... [--keep-column TABLE.COLUMN]... [--out load.sql]

What it does (merged from the three worker scripts):
- Replays default.script, then default.log, statement by statement and in order: CREATE TABLE, ALTER TABLE ADD COLUMN,
  DROP TABLE, INSERT, DELETE (HSQLDB logs an UPDATE as DELETE + INSERT). The net rows are what is loaded.
- Object ids are remapped by ENTITY GUID (T5): a Mendix id carries the entity's short id in its top 16 bits; the
  snapshot's short id is looked up through mendixsystem$entityidentifier (GUID -> short id) on both sides.
  Tables and columns the runtime named differently (long names) map through the entity / association / attribute GUIDs (T8).
  System.User and System.UserRole rows that the target already has are matched by NAME, not inserted (T5); their ids are
  mapped onto the existing rows, also in the specializations (Administration.Account) and System.UserRoles.
- Skips runtime state by explicit rule (mendixsystem$*, sessions, task queue, timezone/language): listed with row
  counts, never silently. object_sequence of every mapped entity is advanced past the loaded maxima.
- Reports per table: INSERT statements in the script, rows deleted, net rows, skipped / matched, rows to load, and
  (when applied) the rows the database gained. Anything it cannot map is listed under UNMAPPED and makes exit 1:
  a table or column the database lacks, an id whose entity GUID the database lacks (the model differs from the
  snapshot's), a statement it does not understand, a gained-row count that differs. Nothing is dropped quietly.
  `--skip TABLE` is the explicit, reported waiver for a table you decided not to load.
Exit: 0 all mapped and loaded (or dry-run counted), 1 UNMAPPED or count mismatch, 2 usage / unreadable input / psql failure.
Not covered (open): autonumber counters (mendixsystem$sequence) are not advanced; a Long attribute whose value happens
to equal an id bit pattern is remapped (list it under --keep-column); the file contents are copied by hand.
"""
import argparse, collections, re, shlex, subprocess, sys, tempfile, zipfile
from pathlib import Path

M48 = (1 << 48) - 1
# runtime state, not business data: (regex over the lower-case table name, reason)
SKIP_RULES = [
    (r"mendixsystem\$.*", "runtime mapping table (the target's own)"),
    (r"system\$(session|session_user|sessions)", "login sessions"),
    (r"system\$(queuedtask|processedqueuetask|queuedaction.*|scheduledeventinformation|clusterlock|xasinstance|offlinecreatedguids|tokeninformation)", "runtime queue / cluster state"),
    (r"system\$(timezone|language|user_timezone|user_language)", "reference data the runtime already created"),
]
IGNORED = re.compile(r"^(SET |COMMIT|CONNECT |DISCONNECT|CREATE SCHEMA|CREATE USER|CREATE ROLE|CREATE (UNIQUE )?INDEX|CREATE SEQUENCE|"
                     r"CREATE (OR REPLACE )?FUNCTION |INSERT INTO (PUBLIC\.)?BLOCKS\b|GRANT |ALTER SEQUENCE|ALTER USER|DROP INDEX|DROP SEQUENCE|ALTER TABLE .* (ADD (CONSTRAINT|PRIMARY|FOREIGN|UNIQUE)|"
                     r"ALTER COLUMN|DROP CONSTRAINT|DROP PRIMARY)|ALTER INDEX|CREATE TRIGGER)", re.I)
NUM = re.compile(r"-?\d+(\.\d+)?([eE][+-]?\d+)?$")


def unesc(s):
    s = re.sub(r"\\u([0-9a-fA-F]{4})", lambda m: chr(int(m.group(1), 16)), s)
    try: return s.encode("utf-16", "surrogatepass").decode("utf-16")  # a 😀 pair becomes one character
    except UnicodeError: return s


class V:  # one parsed literal: kind s(tring) n(umber) b(ytes) l(null) t(rue) f(alse)
    __slots__ = ("k", "v")
    def __init__(self, k, v=None): self.k, self.v = k, v
    def key(self): return (self.k if self.k in "slbtf" else "n", self.v)


def parse_literal(s, i):
    """-> (V, index after). Bare words other than NULL/TRUE/FALSE and numbers raise ValueError."""
    n = len(s)
    while i < n and s[i] == " ": i += 1
    m = re.compile(r"(?:TIMESTAMP|DATE|TIME)\s+(?=')").match(s, i)
    if m: i = m.end()
    if s.startswith("X'", i):
        j = s.index("'", i + 2); return V("b", s[i + 2:j]), j + 1
    if s[i] == "'":
        j = i + 1; buf = []
        while True:
            k = s.index("'", j)
            if k + 1 < n and s[k + 1] == "'": buf.append(s[j:k + 1]); j = k + 2; continue
            buf.append(s[j:k]); return V("s", unesc("".join(buf))), k + 1
    m = re.compile(r"[^,)\s]+").match(s, i)
    if not m: raise ValueError(f"no literal at {i}")
    tok = m.group(0)
    if tok == "NULL": return V("l"), m.end()
    if tok == "TRUE": return V("t"), m.end()
    if tok == "FALSE": return V("f"), m.end()
    if NUM.match(tok): return V("n", tok), m.end()
    raise ValueError(f"unknown token {tok!r}")


def parse_values(s, i):
    """s[i] == '(' -> list of V."""
    assert s[i] == "("
    i += 1; out = []
    while True:
        v, i = parse_literal(s, i); out.append(v)
        while s[i] == " ": i += 1
        if s[i] == ",": i += 1; continue
        if s[i] == ")": return out
        raise ValueError(f"expected , or ) at {i}: {s[i:i + 30]!r}")


def split_top(body):
    """split a CREATE TABLE body on commas outside quotes and parentheses."""
    parts, depth, q, cur = [], 0, False, []
    for ch in body:
        if ch == '"': q = not q
        if not q:
            if ch == "(": depth += 1
            elif ch == ")": depth -= 1
            elif ch == "," and depth == 0: parts.append("".join(cur)); cur = []; continue
        cur.append(ch)
    parts.append("".join(cur))
    return parts


TNAME = r'(?:PUBLIC\.)?"([^"]+)"'


class Table:
    def __init__(self, cols):
        self.cols = cols            # [(name, type)]
        self.rows = {}              # rowno -> [V]
        self.idx = collections.defaultdict(list)   # key of first column -> [rowno]
        self.n = 0; self.inserts = 0; self.deleted = 0

    def insert(self, vals):
        self.n += 1; self.inserts += 1
        self.rows[self.n] = vals; self.idx[vals[0].key()].append(self.n)

    def delete(self, conds):  # conds [(colindex, V)]
        first = [c for c in conds if c[0] == 0]
        cand = list(self.idx.get(first[0][1].key(), ())) if first else list(self.rows)
        for r in cand:
            row = self.rows.get(r)
            if row is not None and all(row[i].key() == v.key() for i, v in conds):
                del self.rows[r]; self.deleted += 1


def replay(files, unmapped):
    tables, ignored, stmts = {}, 0, 0
    for path in files:
        raw = Path(path).read_bytes()
        try: text = raw.decode("utf-8")
        except UnicodeDecodeError: text = raw.decode("latin-1")
        for ln, line in enumerate(text.splitlines(), 1):
            line = re.sub(r"^/\*C\d+\*/", "", line).strip()
            if not line: continue
            stmts += 1; where = f"{Path(path).name}:{ln}"
            try:
                m = re.match(r"CREATE (?:MEMORY |CACHED |TEXT )?TABLE " + TNAME + r"\s*\((.*)\)\s*$", line)
                if m:
                    cols = []
                    for part in split_top(unesc(m.group(2))):
                        pm = re.match(r'\s*"([^"]+)"\s+(.*)$', part)
                        if pm: cols.append((pm.group(1), pm.group(2).strip()))
                    tables[m.group(1)] = Table(cols); continue
                m = re.match(r"ALTER TABLE " + TNAME + r' ADD (?:COLUMN )?"([^"]+)"\s+(.*?)(?: BEFORE "[^"]+")?$', line)
                if m and m.group(1) in tables:
                    t = tables[m.group(1)]; t.cols.append((m.group(2), m.group(3)))
                    for row in t.rows.values(): row.append(V("l"))
                    continue
                m = re.match(r"DROP TABLE " + TNAME, line)
                if m: tables.pop(m.group(1), None); continue
                m = re.match(r"INSERT INTO " + TNAME + r"\s+VALUES\s*", line)
                if m:
                    t = tables.get(m.group(1))
                    if t is None: unmapped.append(f"INSERT into undeclared table {m.group(1)} ({where})"); continue
                    vals = parse_values(line, m.end())
                    if len(vals) != len(t.cols): unmapped.append(f"INSERT {m.group(1)} has {len(vals)} values for {len(t.cols)} columns ({where})"); continue
                    t.insert(vals); continue
                m = re.match(r"DELETE FROM " + TNAME + r"(?:\s+WHERE\s+(.*))?$", line)
                if m:
                    t = tables.get(m.group(1))
                    if t is None: continue
                    if not m.group(2): t.deleted += len(t.rows); t.rows.clear(); t.idx.clear(); continue
                    names = [c[0] for c in t.cols]; conds = []; s = m.group(2); i = 0
                    while i < len(s):
                        cm = re.compile(r'\s*(?:AND\s+)?"([^"]+)"\s*(=|IS)\s*').match(s, i)
                        if not cm: raise ValueError(f"WHERE not understood: {s[i:i + 40]!r}")
                        if cm.group(2) == "IS":
                            if not s.startswith("NULL", cm.end()): raise ValueError("IS without NULL")
                            v, i = V("l"), cm.end() + 4
                        else: v, i = parse_literal(s, cm.end())
                        conds.append((names.index(cm.group(1)), v))
                    t.delete(conds); continue
                if IGNORED.match(line): ignored += 1; continue
                unmapped.append(f"statement not understood: {line[:90]} ({where})")
            except (ValueError, IndexError, AssertionError) as e:
                unmapped.append(f"{where}: {e}")
    return tables, ignored, stmts


def find_input(src, tmp):
    """SNAPSHOT may be the zip, a folder anywhere above default.script, or the script itself -> ([script, log], nfiles)."""
    p = Path(src); nfiles = None
    if p.is_file() and zipfile.is_zipfile(p):
        with zipfile.ZipFile(p) as z:
            names = z.namelist(); nfiles = sum(1 for n in names if "/files/" in "/" + n and not n.endswith("/"))
            for n in names:
                if n.endswith(("default.script", "default.log")):
                    d = Path(tmp) / n; d.parent.mkdir(parents=True, exist_ok=True); d.write_bytes(z.read(n))
        p = Path(tmp)
    if p.is_file(): p = p.parent if p.name == "default.script" else p
    scripts = [p] if p.is_file() else sorted(p.rglob("default.script"))
    if not scripts: sys.exit(f"no default.script in {src}")
    if len(scripts) > 1: sys.exit(f"{len(scripts)} default.script files under {src}: pass the folder that holds one")
    s = scripts[0]; files = [s] + ([s.with_name("default.log")] if s.with_name("default.log").exists() else [])
    if nfiles is None:
        fd = [d for d in s.parents if (d / "files").is_dir()][:1]
        nfiles = sum(1 for x in (fd[0] / "files").rglob("*") if x.is_file()) if fd else None
    return files, nfiles


def q(psql, sql):
    r = subprocess.run(shlex.split(psql) + ["-tAq", "-F", "\t", "-v", "ON_ERROR_STOP=1"], input=sql, capture_output=True, text=True)
    if r.returncode: print(f"psql failed: {r.stderr[:2000]}", file=sys.stderr); sys.exit(2)
    return [l.split("\t") for l in r.stdout.splitlines() if l]


def lit(v):
    if v.k == "l": return "NULL"
    if v.k == "t": return "TRUE"
    if v.k == "f": return "FALSE"
    if v.k == "n": return v.v
    if v.k == "b": return f"decode('{v.v}','hex')"
    return "'" + v.v.replace("'", "''") + "'"


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("snapshot"); ap.add_argument("--psql"); ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--skip", action="append", default=[], metavar="TABLE", help="waive a table (reported, not an error)")
    ap.add_argument("--keep-column", action="append", default=[], metavar="TABLE.COLUMN", help="do not remap ids in this column")
    ap.add_argument("--out", help="also write the load SQL here")
    a = ap.parse_args()
    if not a.psql and not a.dry_run: sys.exit("seed_snapshot.py: --psql CMD is required unless --dry-run")
    unmapped = []
    with tempfile.TemporaryDirectory() as tmp:
        files, nfiles = find_input(a.snapshot, tmp)
        tables, ignored, stmts = replay(files, unmapped)
    print(f"snapshot: {', '.join(f.name for f in files)}; {stmts} statements ({ignored} DDL/SET ignored), {len(tables)} tables"
          + (f"; {nfiles} files under files/ (copy to data/files after each start)" if nfiles else ""))
    for need in ("mendixsystem$entityidentifier", "mendixsystem$entity"):
        if need not in tables: sys.exit(f"{need} not in the snapshot: not a Mendix data snapshot")

    def col(t, c): return [x[0] for x in tables[t].cols].index(c)
    def rows_of(t): return list(tables[t].rows.values())
    s_ei = {r[0].v: (int(r[1].v), int(r[2].v)) for r in rows_of("mendixsystem$entityidentifier")}   # GUID -> (short, seq)
    ec = {c: col("mendixsystem$entity", c) for c in ("id", "entity_name", "table_name", "superentity_id")}
    s_ent = {r[ec["id"]].v: (r[ec["entity_name"]].v, r[ec["table_name"]].v, r[ec["superentity_id"]].v) for r in rows_of("mendixsystem$entity")}

    skip_re = [(re.compile(p), why) for p, why in SKIP_RULES]
    waived = set(a.skip)
    def skip_reason(t):
        if t in waived: return "waived (--skip)"
        for rx, why in skip_re:
            if rx.fullmatch(t.lower()): return why
        return None

    # ---- the database side (read only) -------------------------------------------------------------------------
    pgcols, pg_ei, pg_ent, pg_assoc, pg_attr, pg_users, pg_roles, pre = {}, {}, {}, {}, {}, {}, {}, {}
    if a.psql:
        for t, c in q(a.psql, "select table_name, column_name from information_schema.columns where table_schema='public'"): pgcols.setdefault(t, set()).add(c)
        pg_ei = {r[0]: (int(r[1]), int(r[2] or 0)) for r in q(a.psql, 'select id, short_id, object_sequence from "mendixsystem$entityidentifier"')}
        pg_ent = {r[0]: r[1] for r in q(a.psql, 'select id, table_name from "mendixsystem$entity"')}
        pg_assoc = {r[0]: r[1:] for r in q(a.psql, 'select id, table_name, parent_column_name, child_column_name from "mendixsystem$association"')}
        pg_attr = {r[0]: r[1] for r in q(a.psql, 'select id, column_name from "mendixsystem$attribute"')}
        pg_users = {r[1]: r[0] for r in q(a.psql, 'select id, name from "system$user"')}
        pg_roles = {r[1]: r[0] for r in q(a.psql, 'select id, name from "system$userrole"')}
        h2p = {s_ei[g][0]: pg_ei[g][0] for g in s_ei if g in pg_ei}
        for g in s_ei:
            if g not in pg_ei: unmapped.append(f"entity {s_ent.get(g, ('?',))[0]} (GUID {g}) is not in the database: the model differs from the snapshot's")
    else: h2p = {}

    # snapshot association / attribute GUID -> names, for tables and columns the runtime shortened
    s_assoc = {}
    if "mendixsystem$association" in tables:
        c = {n: col("mendixsystem$association", n) for n in ("id", "table_name", "parent_entity_id", "parent_column_name", "child_column_name")}
        s_assoc = {r[c["id"]].v: (r[c["table_name"]].v, r[c["parent_entity_id"]].v, r[c["parent_column_name"]].v, r[c["child_column_name"]].v) for r in rows_of("mendixsystem$association")}
    s_attr = {}   # (snapshot table, column) -> attribute GUID
    if "mendixsystem$attribute" in tables:
        c = {n: col("mendixsystem$attribute", n) for n in ("id", "entity_id", "column_name")}
        for r in rows_of("mendixsystem$attribute"):
            e = s_ent.get(r[c["entity_id"]].v)
            if e: s_attr[(e[1], r[c["column_name"]].v)] = r[c["id"]].v
    ent_by_table = {v[1]: g for g, v in s_ent.items()}

    def pg_table(t):
        """-> (pg table, {snapshot col: pg col}) or None."""
        if t in pgcols: return t, {}
        g = ent_by_table.get(t)
        if g in pg_ent and pg_ent[g] in pgcols: return pg_ent[g], {}
        for aid, (at, _, pc, cc) in s_assoc.items():
            if at == t and aid in pg_assoc and pg_assoc[aid][0] in pgcols: return pg_assoc[aid][0], {pc: pg_assoc[aid][1], cc: pg_assoc[aid][2]}
        return None

    # users and roles the target already has: matched by name, ids mapped onto the existing rows
    idmap, deduped = {}, collections.defaultdict(set)
    if a.psql:
        sub = {g for g in s_ent if s_ent[g][0] == "System.User"}
        changed = True
        while changed:
            changed = False
            for g, (_, _, sup) in s_ent.items():
                if sup in sub and g not in sub: sub.add(g); changed = True
        for base, have in (("system$user", pg_users), ("system$userrole", pg_roles)):
            if base not in tables: continue
            nm = col(base, "name"); idc = col(base, "id")
            for r in rows_of(base):
                if r[nm].v in have: idmap[int(r[idc].v)] = int(have[r[nm].v])
        if "system$user" in tables:
            utabs = {s_ent[g][1] for g in sub} | {"system$user"}
            for t in utabs:
                if t in tables:
                    for r in rows_of(t):
                        if int(r[0].v) in idmap: deduped[t].add(id(r))
        for r in rows_of("system$userrole") if "system$userrole" in tables else []:
            if int(r[0].v) in idmap: deduped["system$userrole"].add(id(r))

    unresolved = collections.Counter()
    maxseq = collections.defaultdict(int)
    def remap(t, cname, ctype, v):
        if v.k != "n" or not ctype.upper().startswith("BIGINT") or f"{t}.{cname}" in a.keep_column: return v
        x = int(v.v)
        if x in idmap: return V("n", str(idmap[x]))
        if x <= (1 << 48): return v
        hs = x >> 48
        if not a.psql: return v
        if hs in h2p:
            maxseq[h2p[hs]] = max(maxseq[h2p[hs]], x & M48); return V("n", str((h2p[hs] << 48) | (x & M48)))
        unresolved[(t, cname, hs)] += 1; return v

    plan, report, sql, applied = [], [], [], False
    tot = collections.Counter()
    for t in sorted(tables):
        tb = tables[t]; net = len(tb.rows); tot["ins"] += tb.inserts; tot["del"] += tb.deleted; tot["net"] += net
        why = skip_reason(t)
        if why:
            report.append((t, tb.inserts, tb.deleted, net, f"skipped: {why}", 0)); tot["skip"] += net; continue
        if net == 0 and not tb.inserts:
            report.append((t, 0, tb.deleted, 0, "empty", 0)); continue
        mp = None; ren = {}
        if a.psql:
            mp = pg_table(t)
            if mp is None:
                unmapped.append(f"table {t} ({net} rows) has no counterpart in the database"); report.append((t, tb.inserts, tb.deleted, net, "UNMAPPED table", 0)); continue
            ren = {c: mp[1].get(c, c) for c, _ in tb.cols}
            for c, _ in tb.cols:
                pc = ren[c]
                if pc not in pgcols[mp[0]]:
                    g = s_attr.get((t, c)); alt = pg_attr.get(g) if g else None
                    if alt and alt in pgcols[mp[0]]: ren[c] = alt
                    else: unmapped.append(f"column {t}.{c} has no counterpart in the database table {mp[0]}"); ren[c] = None
        dd = deduped.get(t, set())
        out = []
        for r in tb.rows.values():
            if id(r) in dd: continue
            out.append([remap(t, c, ty, v) for (c, ty), v in zip(tb.cols, r)])
        have = 0
        if a.psql and mp and not dd and tb.cols[0][0] != "id" and all(ren.get(c) for c, _ in tb.cols):
            touched = [r for r in out if any(v.k == "n" and int(v.v) in idmap.values() for v in r)]
            if touched:   # a join row (user -> role) the database already holds: present, not inserted twice
                got = {tuple(r) for r in q(a.psql, "select " + ",".join(f'"{ren[c]}"::text' for c, _ in tb.cols) + f' from "{mp[0]}"')}
                keep = [r for r in out if tuple(v.v for v in r) not in got]; have = len(out) - len(keep); out = keep
        for r in out:
            if a.psql and r[0].k == "n" and int(r[0].v) > (1 << 48): maxseq[int(r[0].v) >> 48] = max(maxseq[int(r[0].v) >> 48], int(r[0].v) & M48)
        note = (f"matched by name: {len(dd)}" if dd else "") + (f"already present: {have}" if have else "")
        report.append((t, tb.inserts, tb.deleted, net, note, len(out))); tot["dedupe"] += len(dd) + have; tot["load"] += len(out)
        if mp and all(ren[c] for c, _ in tb.cols): plan.append((t, mp[0], [c for c, _ in tb.cols], [ren[c] for c, _ in tb.cols], out))
    for (t, c, hs), n in sorted(unresolved.items()):
        unmapped.append(f"{t}.{c}: {n} value(s) carry entity short id {hs}, which the database has no entity GUID for (model differs; or a Long attribute: --keep-column {t}.{c})")

    print(f"\n{'table':<46}{'inserts':>8}{'deleted':>8}{'net':>7}{'to load':>9}  note")
    for t, ins, dl, net, note, ld in report:
        print(f"{t:<46}{ins:>8}{dl:>8}{net:>7}{ld:>9}  {note}")
    print(f"\ntotal: {tot['ins']} INSERT statements, {tot['del']} rows deleted, {tot['net']} net rows in {len(tables)} tables; "
          f"skipped by rule {tot['skip']}, matched by name or already present {tot['dedupe']}, to load {tot['load']}")

    if a.psql and not unmapped:
        sql = ["BEGIN;", "SET LOCAL session_replication_role = replica;"]
        for t, pt, sc, pc, rows in plan:
            cl = ",".join(f'"{c}"' for c in pc)
            for i in range(0, len(rows), 500):
                sql.append(f'INSERT INTO "{pt}" ({cl}) VALUES ' + ",".join("(" + ",".join(lit(v) for v in r) + ")" for r in rows[i:i + 500]) + ";")
        for g, (hs, seq) in s_ei.items():
            if g in pg_ei:
                top = max(seq, maxseq.get(pg_ei[g][0], 0))
                sql.append(f"UPDATE \"mendixsystem$entityidentifier\" SET object_sequence = GREATEST(object_sequence, {top + 1}) WHERE id = '{g}';")
        sql.append("COMMIT;")
        if a.out: Path(a.out).write_text("\n".join(sql) + "\n")
    if a.dry_run:
        print("dry run: nothing written" + ("" if a.psql else "; mapping against a database NOT checked (no --psql)"))
    elif a.psql and not unmapped:
        def counts():
            u = " union all ".join(f"select '{pt}', count(*) from \"{pt}\"" for _, pt, *_ in plan)
            return {r[0]: int(r[1]) for r in q(a.psql, u)} if plan else {}
        before = counts(); q(a.psql, "\n".join(sql)); after = counts(); applied = True
        for t, pt, _, _, rows in plan:
            if after.get(pt, 0) - before.get(pt, 0) != len(rows): unmapped.append(f"{pt}: gained {after.get(pt, 0) - before.get(pt, 0)} rows, expected {len(rows)}")
        print(f"applied: {tot['load']} rows in {len(plan)} tables; every table gained exactly its 'to load' rows" if not unmapped else "applied, but counts differ")
    if unmapped:
        print(f"\nUNMAPPED ({len(unmapped)}):")
        for u in unmapped[:60]: print(f"  {u}")
        if len(unmapped) > 60: print(f"  ... {len(unmapped) - 60} more")
        print("the load was applied before the count check failed" if applied else "nothing was loaded")
        sys.exit(1)


if __name__ == "__main__":
    main()
