# Fixture seeding — derive it, measure the gap, ask only what cannot be derived

**Applies to:** establishing the data and identities a `journey-proof.md` run needs, before it runs - seed data, test data, demo data, empty pages, fixtures.

This skill sits **above** the mechanism references, not beside them. `demo-data.md` is a good
document about one channel (direct SQL insert) and knows nothing about the others;
`manage-security.md` owns login accounts. Neither answers *what does this app actually need, and
which channel should supply it.* That is this skill.

## The rule that shapes everything else

**Seeding is not part of the harness.** `journey-proof.md` states it for defects — *"do not fix
defects from inside the harness; it is diagnostic"* — and the same logic binds harder for
preconditions. A harness that repairs its own fixture can no longer report that the fixture was
absent, which is the same category error as an instrument that cannot go red.

So the harness **asserts** the precondition and faults. A separate, approved step **satisfies** it.

## The flow

```
1. DERIVE   what the journeys declare they need            bin/fixture-manifest.sh
2. MEASURE  what the running app actually has              (same script — it probes via OQL)
3. CLASSIFY the gap, by cause and by owner                 (same script)
4. INTERVIEW only the residue that is genuinely undecidable   ← the human gate
5. SEED     via the right channel per element                 ← needs approval, every time
6. VERIFY   by re-running the journeys' own seeds[].sql
```

Steps 1–3 are one read-only command. Run it before asking anyone anything.

```bash
bin/fixture-manifest.sh              # 0 = sufficient · 1 = short · 2 = could not measure
```

Run it from the project root. The path is `bin/` — the toolkit's own copy lives in `project-bin/`,
which is the *install source*, not where a wired project runs it from. Pointing at `project-bin/`
runs the template instead of your project's installed copy, or nothing at all.

## 1–3. Derive and measure — do not interview for what is already written down

The journeys publish their own preconditions. Asking a human for them yields a slower, less
accurate copy of a file you could have read:

| Source | What it already answers |
|---|---|
| `journeys/*.journey.json` → `seeds[].sql` | the preconditions, literally as SQL |
| `steps[].data.creates` / `delta` | which entities the run writes to |
| `steps[].data.assocMustBeSet` / `mustPointAt` | which associations must be set, and to what |
| `_seedNote` on an empty `seeds[]` | that this journey needs **no** rows, and why |
| `persona` | the identity the whole run authenticates as |
| module brief golden-path tables | action → creates/changes → associations |
| `CATALOG.PERMISSIONS` × `ROLE_MAPPINGS` | which roles can actually open each page |

**"Seeds return nothing" has at least three causes with three different owners.** Never report it
as one:

| Symptom | Cause | Owner | Verdict |
|---|---|---|---|
| admin API unreachable | stack down / wrong port | operator | **fault** (rc 2) — do not seed on the strength of it |
| seed SQL errors | malformed query, renamed entity | whoever wrote the journey | **fault** — fix the query, do not seed |
| seed SQL runs, 0 rows | fixture absent | this skill | **finding** (rc 1) — seed |
| runtime still warming | race | operator | **fault** — re-run, do not seed |

`journey-proof.md`'s trap table historically attributed all of these to *"usually a race"*. It was
wrong at least once, on a genuinely empty database, and a default explanation of that kind sends
someone to debug the wrong subsystem.

## Explore the data structure first

Journeys declare what they *touch*; a journey that never reaches a page declares no need for it.
Before choosing any row, answer three questions from the model itself, not from entity names:

| Question | Read it from | Failure if skipped |
|---|---|---|
| What must be filled, what is unique? | domain model: required/unique validation, defaults, persistent vs non-persistent (never seed non-persistent entities — pages build them from microflows) | insert refused, or `duplicate key value violates unique constraint` on a row the app creates itself |
| Which association hangs a child on a page? | associations (owner, delete behaviour) + each page's data-source XPath; seed the association the page's data source path names, in the table where it is stored (in Mendix the child usually owns the reference) | marker, line item or ticket row exists, the page list stays empty |
| Which enum values do pages filter on? | XPath strings in page data sources and access rules, plus the enumerations | an overview filtered on `Status != 'Open'` stays empty because the seed only held `Open` rows |

Technique, in the order that worked: persistent entities -> associations -> enumerations -> access
rules per role with their XPath -> page data sources with XPath; end with one table,
`entity | who needs it | state it must be in`. Read each from the model with `mxcli -p <app>.mpr`:
`SHOW ENTITIES`, `DESCRIBE ENTITY`, `SHOW ASSOCIATIONS`, the enumeration and access listings
(`query-the-model.md`). These read the `.mpr` directly; no running app is needed.

## Choose the data by use case, not by table

Write the use case in three sentences first (who, what they do, what they see). Then:

- **One record in every status a page filters on**, and one in each end state of a lifecycle.
- **Children for list and detail pages**: every "children" list gets at least 2 children.
- **Role-linked identities**: the test user must own a domain object (an Employee linked to the
  Account) or a list scoped by `[HR.Employee_Account='[%CurrentUser%]']` is empty for exactly
  that role. Give that scope 2-3 rows.
- **Referential integrity**: set every association a page follows. Counters that microflows maintain
  (`NumberOfTickets`) are plain integers to SQL; make them equal their children.
- **Realistic invented values**: `SI-20261013-001`, mail at example.com, never `Item-001` unless Q3 said so.
- **5-20 rows per entity**; a dashboard needs a spread, not volume.
- **Dates relative to now** ("this week" counters read 0 on a fixed date).
- **Reruns repeat through a stable business key, never through fixed ids.** A Mendix object id is
  a bigint `(short_id << 48) | (sequence << 7) | rand7`: `short_id` from
  `mendixsystem$entityidentifier`, the sequence advanced in the same transaction (`demo-data.md`).
  Never write an id as a literal or a uuid. A hand-minted id that skips the sequence collides with
  rows the app creates later, and a stale `short_id` paints blank grid rows (`mxcli-bugs.md`,
  Platform behaviours D and Methodology lessons #11). Guard each insert with `WHERE NOT EXISTS` on
  the business key (`e2e-harness-base.md`); rebuild from an empty frozen copy.

## 4. Interview — a proposal with evidence, then stop and wait

Only after the manifest exists. Four questions are genuinely undecidable from the repo; everything
else is derivable and must not be asked.

1. **A page the persona cannot open — fixture defect or app defect?** *This is the load-bearing
   one.* If a journey dies at step 1 because the page grants only `MxRole_*` and the persona holds
   generic `User`, seeding **can** close it by granting the roles — and must not decide to. Either
   the grants are wrong (an access-control defect worth finding) or the persona is wrong (a fixture
   defect). Silently granting the roles turns the journey green and buries the finding. Present
   both readings with the grant evidence; let the human choose.
2. **Reuse an existing database, or seed fresh?** Copying a Run Locally database is fast and
   faithful — it is the data the app was actually built against — but its provenance is opaque and
   it is not reproducible. Seeding fresh is reproducible and slow. Real trade-off, real decision.
3. **Volume and realism.** A test fixture and a customer-facing demo have different bars. 20
   locations or 2000; plausible names or `Item-001`.
4. **One persona or several?** If several roles resolve to an identical page set, a per-role report
   is N identical reports — say so rather than emitting them.

Ask these in chat, then **end the turn and wait**. `ASSUMED` is earned by asking and hearing "you
decide" — never by skipping.

## 5. Seed — route per element, not per project

There is no single right channel. Choose per fixture element:

| Element | Channel | Why |
|---|---|---|
| Login accounts | `create demo user 'n' password 'P1!' entity Administration.Account (Role);` — `manage-security.md` | The **only** channel that produces a usable login |
| Accounts, alternative | Mendix demo users in project settings | Declarative, survives a rebuild |
| Bulk domain rows | direct SQL insert — `demo-data.md` | Best ID/association reference in the corpus |
| Bulk rows, from a file | `import from` — `demo-data.md` | Handles multi-`link` rows better than its own INSERT templates |
| A whole realistic dataset | copy an existing Run Locally database | Zero authoring; see interview Q2 |
| Reference/config data | an after-startup microflow | Idempotent, ships with the model |

### Four traps that have each cost real time

- **Passwords are hashed and write-only.** A SQL `INSERT` into `system$user` produces an account
  that exists and cannot log in. If the harness has a fallback identity, it then silently runs as
  someone else and every role-scoped assertion goes vacuously green. That is **worse** than an
  empty database: the empty database fails loudly; a bad persona passes.
- **Do not build account seeding as an after-startup microflow.** Repeated attempts have corrupted
  the model's BSON stream. Use the declarative `create demo user` statement.
- **Wrong password → lockout.** Retries set `Blocked` / `FailedLogins`, and the *next* run then
  fails for a different reason than the original one. Check those columns before re-running.
- **Confirm which database the runtime is attached to before issuing a single insert.** Direct-SQL
  guidance assumes PostgreSQL; if the runtime is on HSQLDB those commands cannot reach it. The
  inserts land somewhere real, the tables look healthy, and the app still shows nothing — and
  `demo-data.md`'s own runtime-cache caveat supplies a plausible wrong explanation for it.

### Scan the actions before you run anything

Reset, delete-all and import-demo-data actions wipe the seed **and the test users**. Grep the
action inventory (buttons, microflow names) for them before the first run. Verbatim symptom from a
generated journey that pressed a "Reset all demodata" button: Administrator passed, then every other
role reported `login FAIL: The username or password you entered is incorrect` - 104 of 127 journeys,
and the same on an empty and a seeded database, so before and after looked identical. Administrator
*delete* journeys do the same through cascades: deleting an Employee also deleted the Account
linked to it, because that association's delete behaviour cascades (read it with `DESCRIBE
ASSOCIATION`; 1 account of 3 left, 157 of 183 journeys failing login). Seeds that link Employee to Account are
what make it bite; an empty database hides it. Run destructive journeys **last, or on a copy**, and
count them separately.

### Generic traps, with the exact symptom

| Trap | Symptom |
|---|---|
| Enum column seeded with the caption | `Status = 'In progress'` matches no value: the cell renders blank and every `Status = 'InProgress'` filter skips the row. Store the value name |
| Specialization seeded in its own table only | `insert into hr$manager` alone: the object is missing from every `Employee` list. Insert one row per table in the inheritance chain with the same id, minted from the specialization's `short_id` (its own `mendixsystem$entityidentifier` row, not the parent's: a parent short_id gives blank or mistyped rows), and set `submetaobjectname` on each parent row to the specialization's name |
| Calculated attribute in the insert | `column "fullname" does not exist`: a calculated attribute has no column. Leave it out |
| View or external entity seeded | the insert fails (no table, or a database view that refuses inserts): a view entity is computed by its OQL and an external entity lives in the remote service. Seed the entities the view reads, or the source system |
| Package snapshot loaded after the app started once | `duplicate key value violates unique constraint` - the app creates some rows itself at first start; waive that table, expect one per self-seeding Marketplace module |
| Snapshot dates vs "this week" counters | dashboard shows 0 for a snapshot dated months ago. Shift all timestamps *before* any spec using relative dates, or the anchor is the new rows |
| Removing a user from a role as sole target | the snapshot's own demo users lose the role, and the rows they own are owned by nobody who can log in; re-own a few rows to the test user's object |
| Role names differ per app (`QualityManager` here, `DepartmentManager` there) | users file lists a role the database does not have; read the roles from the actual database, not habit |
| File-bearing rows (Image, FileDocument) | row exists, `FileNotFoundInStorageException` in the log; copy files after every start, or leave those rows out on purpose |

Every write here is a model or database write. **Get approval before each one.**

## 6. Verify — with the journeys' own SQL

Re-run every `seeds[].sql` and require a non-empty result. This is nearly free and correct by
construction: the journey has already declared what it needs, so there is no second definition to
drift. `fixture-manifest.sh` exiting 0 **is** the verification.

An unverified seed is the same false-green class the whole verification mode exists to retire.

### One more contract, easy to miss

`journey-proof.md`'s `--positive-control` **writes real rows** — one transactional table went 50 →
57 in a single control run. So the fixture must be re-establishable to a known baseline between a
real run and a control run. Decide how you will reset it *before* you need to, and record it. If
the answer is "re-copy the Run Locally database", say that in the project's own notes; if it is
"re-run the seed script", the seed script has to be idempotent, which most hand-written ones are
not.

## What seeding buys - set expectations

Journeys PASS / FAIL / INVALID on two public template apps, same set, empty vs seeded database:
**33 / 93 / 68 -> 58 / 68 / 68** and **20 / 163 / 114 -> 51 / 132 / 114**. Seeding raised passes by
25 and 31; INVALID (no click path, no role, external call) cannot move. The remaining FAILs were not
seed shortfalls alone: no click path or a conditional widget, DATA-STATE not yet seeded (an action shown
only for a reviewed or closed row - add that row, the next iteration), and instrument limits (grids the
engine finds no visible row in). Classify each remaining FAIL into those buckets; do not call a seeded
run "done" because it beat the empty one.

## Non-vacuity

`fixture-manifest.sh` carries three mutants, one per section it judges — an absent account, a seed
that returns zero rows, and a malformed seed query — plus a fault arm (admin API unreachable) that
must exit 2 rather than 1. A section with no mutant reports **fault**, not pass. Run the controls
before trusting a green manifest.

## Done when (denominators)

- [ ] 3-sentence use case written; one table row per persistent entity a page reads (N of N).
- [ ] Every enum value a page filters on has >= 1 row (V of V values).
- [ ] Every role's landing page opened once and non-empty (R of R roles).
- [ ] Destructive actions listed (D found, D run last or on a copy; "none found" is a legal count).
- [ ] `bin/fixture-manifest.sh` exits 0; a second run of the seed changes no row count.

## Related

| Need | Read |
|---|---|
| What the fixture is *for* | `journey-proof.md` |
| Creating login accounts and roles | `manage-security.md` |
| Mendix ID system, associations, bulk insert | `demo-data.md` (project-local, mxcli-bundled) |
| Whether the seed landed, at runtime | `verify-with-oql.md` (project-local) |
