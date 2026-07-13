# DB Assertions via PostgreSQL Direct
**Applies to:** any mxcli project.

## Why mxcli OQL --direct Doesn't Work

`mxcli oql --direct` requires the M2EE admin token. In Mendix 11.10+ the token is
randomised on every startup — it cannot be hardcoded. Attempts to call
`mxcli oql --direct` with a fixed token always return `401 Unauthorized`.

**Fix:** Shell out to `psql.exe` directly and run raw SQL against the Mendix
PostgreSQL database. The `dbQuery()` helper in `tests/helpers.js` implements this.

---

## dbQuery() Configuration

```js
// tests/helpers.js — defaults, all overridable via env vars
const PSQL = process.env.PSQL_PATH || 'C:\\Program Files\\PostgreSQL\\18\\bin\\psql.exe';
const DB   = process.env.PG_DB   || 'PGadmin';
const USER = process.env.PG_USER || 'postgres';
const PASS = process.env.PG_PASS || 'Mendix1!';
const HOST = process.env.PG_HOST || 'localhost';
const PORT = process.env.PG_PORT || '5432';
```

Uses `SELECT json_agg(t) FROM (...) t` trick to get JSON output from psql.
Returns a parsed JSON array, or `null` on error.

---

## Mendix → PostgreSQL Naming Rules

| Mendix | PostgreSQL |
|--------|------------|
| `Module.EntityName` | `module$entityname` (all lowercase, `$` separator) |
| `AttributeName` | `attributename` (all lowercase) |
| `CreatedOn` (system) | `createdon` |
| `ChangedOn` (system) | `changedon` |
| Association FK column | `module$entity_otherentity` (lowercase) |

### FK Column Truncation (63-char PostgreSQL limit)

Long association names get truncated at 63 characters. Always verify with:

```sql
SELECT column_name FROM information_schema.columns
WHERE table_name = 'payerregistration$payerapplicationheader';
```

**Confirmed truncation in this project:**

| Full name | Actual column name stored |
|-----------|--------------------------|
| `payerregistration$payerapplicationheader_applicationcommonheader` (65 chars) | `payerregistration$payerapplicationheader_applicationcommonheade` (63 chars, missing final `r`) |

---

## Confirmed Table Names (this project)

```
businessapp_common$applicationcommonheader
payerregistration$payerapplicationheader
payerregistration$payerdetail
payerregistration$payerareadata
customer_common$payercustomerbase
payerregistration$choiceorg
common_lookups$paymentterm
```

---

## Standard Assertion Queries

### Latest PayerDetail with status (before/after submit)

```js
dbQuery(
  'SELECT ach.status, ach.lockversion ' +
  'FROM "businessapp_common$applicationcommonheader" ach ' +
  'INNER JOIN "payerregistration$payerapplicationheader" pah ' +
  '  ON pah."payerregistration$payerapplicationheader_applicationcommonheade" = ach.id ' +
  'INNER JOIN "payerregistration$payerdetail" pd ' +
  '  ON pd."payerregistration$payerdetail_payerapplicationheader" = pah.id ' +
  'ORDER BY pd.createdon DESC LIMIT 1'
)?.[0] ?? null
// Returns: { status: '01', lockversion: 0 }  (01=Draft, 02=Submitted)
```

Note: use truncated FK name `...applicationcommonheade` (missing final `r`).

### PayerDetail with CurrencyCode and ApplyCategory

```js
dbQuery(
  'SELECT pd.customercode, pd.currencycode, pah.applycategory ' +
  'FROM "payerregistration$payerdetail" pd ' +
  'INNER JOIN "payerregistration$payerapplicationheader" pah ' +
  '  ON pd."payerregistration$payerdetail_payerapplicationheader" = pah.id ' +
  'ORDER BY pd.createdon DESC LIMIT 1'
)?.[0] ?? null
```

### PayerAreaData row count for latest PayerDetail

```js
dbQuery(
  'SELECT COUNT(*) AS cnt ' +
  'FROM "payerregistration$payerareadata" pad ' +
  'INNER JOIN "payerregistration$payerdetail" pd ' +
  '  ON pd.id = pad."payerregistration$payerareadata_payerdetail" ' +
  'WHERE pd.createdon = (SELECT MAX(createdon) FROM "payerregistration$payerdetail")'
)?.[0] ?? null
// Returns: { cnt: '1' }  — note: cnt is a string, use parseInt()
```

---

## psql Line Continuation Quirk

PostgreSQL wraps long JSON lines with ` +\n` continuations when output goes to a
terminal. Strip before `JSON.parse()`:

```js
const out = raw.replace(/\s+\+\r?\n\s*/g, '').trim();
```

This is already handled inside `dbQuery()` — only relevant if writing a new
helper that calls psql directly.

---

## OQL → SQL Translation Reference

| OQL path syntax | SQL equivalent |
|----------------|---------------|
| `FROM Module.Entity AS e` | `FROM "module$entity" e` |
| `INNER JOIN e/Module.Assoc/Module.Other AS o` | `INNER JOIN "module$other" o ON o.id = e."module$entity_other"` |
| `ORDER BY e.CreatedOn DESC` | `ORDER BY e.createdon DESC` |
| `LIMIT 1` (returns entity) | `LIMIT 1` |

**Important:** OQL `LIMIT 1` returns a single entity object. SQL `LIMIT 1` returns
one row — use `?.[0]` on the result array to get the object.
