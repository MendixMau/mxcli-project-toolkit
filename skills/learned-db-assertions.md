# DB Assertions — M2EE admin API first, psql only as a fallback
**Applies to:** any mxcli project.
**Companion skills:** `e2e-harness-base.md`, `ui-review-loop.md`, `existing-app-assurance.md`

A data assertion ("did the row actually get written, with its associations set?") is the only
rung of an e2e suite that can catch a golden path which persisted nothing. A green UI assertion
and a green microflow span both survive that. So the instrument you use here matters, and a
suite that silently loses this rung is a UI-only suite still reporting "e2e".

---

## Rule

1. **Try the M2EE admin API first** — `mxcli oql --direct`, `adminPort = runtime port + 10`,
   token read from the project's own m2ee/runtime config. Do not assume the token is random:
   go and read it.
2. Only if that genuinely 401s, **and only on a host that actually has PostgreSQL**, fall back
   to a direct DB connection (below) — and record in the run report that the data rung came
   from a different instrument than usual.
3. If neither is available, the run has **no data rung**. Say so in the report. A suite that
   silently drops to UI-only is the same class of false-green as a spec that logs in as admin:
   it still prints "passed".

---

## The working method: M2EE admin API

Measured on a warehouse-management project — **macOS, Mendix 11.13.0 Beta**, app running under
Studio Pro "Run Locally":

```js
// tests/helpers.js
adminHost:  process.env.M2EE_ADMIN_HOST || 'localhost',
adminPort:  process.env.M2EE_ADMIN_PORT || String(Number(PORT) + 10),  // runtime port + 10
adminToken: process.env.M2EE_ADMIN_PASS || '1',
```

Real rows come back. From a committed run (`tests/e2e/artifacts/findings.json`, 2026-08-12):

```json
{"label": "Total equipment", "sql": "SELECT COUNT(*) AS n FROM Equipment.Item",
 "value": "30", "pass": true}
```

**26 OQL assertions in that one report, all answered.** The token there is not randomised; it is
`1`, because that is what the project's `m2ee` config sets.

### Correction to the previous version of this skill

This skill used to open with: *"`mxcli oql --direct` requires the M2EE admin token. In Mendix
11.10+ the token is randomised on every startup — it cannot be hardcoded … always return `401
Unauthorized`. **Fix:** shell out to `psql.exe`."*

Both halves were wrong in a way that cost a data rung:

- **"Always 401" is false.** Token randomisation is a property of a particular deployment's
  config, not of Mendix 11.10+. Read the project's config before concluding anything.
- **The prescribed workaround is Windows-only and platform-fatal elsewhere.** `psql.exe`, a
  `C:\Program Files\...` path and a local PostgreSQL install do not exist on macOS, and Studio
  Pro's bundled database is not PostgreSQL at all. A macOS harness following the old advice had
  **no data rung whatsoever** while still printing "e2e".

---

## Fallback: PostgreSQL direct

**Platform caveat, read first:** this path requires a `psql` binary and a PostgreSQL-backed
Mendix database on the host running the tests. That is a Windows/Docker/managed-Postgres
situation. On macOS with Studio Pro's bundled database there is nothing to shell out to — do not
"port" this by guessing a path; go back to the M2EE route or declare the rung missing.

### dbQuery() configuration

```js
// tests/helpers.js — defaults, all overridable via env vars
const PSQL = process.env.PSQL_PATH || 'C:\\Program Files\\PostgreSQL\\18\\bin\\psql.exe';
const DB   = process.env.PG_DB   || 'PGadmin';
const USER = process.env.PG_USER || 'postgres';
const PASS = process.env.PG_PASS || 'Mendix1!';
const HOST = process.env.PG_HOST || 'localhost';
const PORT = process.env.PG_PORT || '5432';
```

Uses the `SELECT json_agg(t) FROM (...) t` trick to get JSON output from psql. Returns a parsed
JSON array, or `null` on error.

### psql line-continuation quirk

PostgreSQL wraps long JSON lines with ` +\n` continuations when output goes to a terminal. Strip
before `JSON.parse()`:

```js
const out = raw.replace(/\s+\+\r?\n\s*/g, '').trim();
```

Already handled inside `dbQuery()` — only relevant if writing a new helper that calls psql directly.

---

## Mendix → PostgreSQL naming rules

Needed only on the psql fallback — the M2EE/OQL route speaks Mendix names directly.

| Mendix | PostgreSQL |
|--------|------------|
| `Module.EntityName` | `module$entityname` (all lowercase, `$` separator) |
| `AttributeName` | `attributename` (all lowercase) |
| `CreatedOn` (system) | `createdon` |
| `ChangedOn` (system) | `changedon` |
| Association FK column | `module$entity_otherentity` (lowercase) |

### FK column truncation (63-char PostgreSQL limit)

Long association names are truncated at 63 characters. Always verify with:

```sql
SELECT column_name FROM information_schema.columns
WHERE table_name = 'orderregistration$orderapplicationheader';
```

Confirmed truncation in one project:

| Full name | Actual column name stored |
|-----------|--------------------------|
| `orderregistration$orderapplicationheader_applicationcommonheader` (65 chars) | `orderregistration$orderapplicationheader_applicationcommonheade` (63 chars, missing final `r`) |

---

## OQL → SQL translation reference

For rewriting an existing OQL assertion when you are forced onto the psql fallback.

| OQL path syntax | SQL equivalent |
|----------------|---------------|
| `FROM Module.Entity AS e` | `FROM "module$entity" e` |
| `INNER JOIN e/Module.Assoc/Module.Other AS o` | `INNER JOIN "module$other" o ON o.id = e."module$entity_other"` |
| `ORDER BY e.CreatedOn DESC` | `ORDER BY e.createdon DESC` |
| `LIMIT 1` (returns entity) | `LIMIT 1` |

**Important:** OQL `LIMIT 1` returns a single entity object. SQL `LIMIT 1` returns one row — use
`?.[0]` on the result array to get the object.

---

## Worked psql assertion examples

From one order-registration project; the table names are that project's, the shape is general.
Confirmed tables there: `businessapp_common$applicationcommonheader`,
`orderregistration$orderapplicationheader`, `orderregistration$orderdetail`,
`orderregistration$orderareadata`, `customer_common$ordercustomerbase`,
`orderregistration$choiceorg`, `common_lookups$paymentterm`.

### Latest OrderDetail with status (before/after submit)

```js
dbQuery(
  'SELECT ach.status, ach.lockversion ' +
  'FROM "businessapp_common$applicationcommonheader" ach ' +
  'INNER JOIN "orderregistration$orderapplicationheader" pah ' +
  '  ON pah."orderregistration$orderapplicationheader_applicationcommonheade" = ach.id ' +
  'INNER JOIN "orderregistration$orderdetail" pd ' +
  '  ON pd."orderregistration$orderdetail_orderapplicationheader" = pah.id ' +
  'ORDER BY pd.createdon DESC LIMIT 1'
)?.[0] ?? null
// Returns: { status: '01', lockversion: 0 }  (01=Draft, 02=Submitted)
```

Note the truncated FK name `...applicationcommonheade` (missing final `r`).

### OrderAreaData row count for the latest OrderDetail

```js
dbQuery(
  'SELECT COUNT(*) AS cnt ' +
  'FROM "orderregistration$orderareadata" pad ' +
  'INNER JOIN "orderregistration$orderdetail" pd ' +
  '  ON pd.id = pad."orderregistration$orderareadata_orderdetail" ' +
  'WHERE pd.createdon = (SELECT MAX(createdon) FROM "orderregistration$orderdetail")'
)?.[0] ?? null
// Returns: { cnt: '1' }  — cnt is a string, use parseInt()
```
