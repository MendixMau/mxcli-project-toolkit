# fixtures/snapshot

A small HSQLDB demo-data snapshot (`data/database/hsqldb/default.script` + `default.log`) and the Postgres schema the
app would create for its model (`pg-schema.sql`), for the `seed-snapshot-*` controls.

**Format-derived, not a capture.** No real `default.script` is committed on any run branch (T1R, T5, T8 loaded theirs
from a local `data-snapshot.zip`), so these lines follow the HSQLDB 2.x script syntax the three worker loaders parse
(`CREATE MEMORY TABLE PUBLIC."t"(...)`, `INSERT INTO "t" VALUES(...)`, `é` escapes, `/*C1*/` log prefix, an UPDATE
as DELETE + INSERT). Replace with a truncated excerpt of a real public Marketplace template's `default.script` as soon as
one is available and keep the per-table assertions in `run-controls.sh` in step with it. Entities: System.User,
Administration.Account (specialization), System.UserRole, Demo.Product, Demo.Order and an association table; the
snapshot's short ids (1..5) differ from the database's (11..15) on purpose.
