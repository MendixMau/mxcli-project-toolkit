# Fixture seeding — derive it, measure the gap, ask only what cannot be derived

**Applies to:** establishing the data and identities a `journey-proof.md` run needs, before it runs.

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

## Non-vacuity

`fixture-manifest.sh` carries three mutants, one per section it judges — an absent account, a seed
that returns zero rows, and a malformed seed query — plus a fault arm (admin API unreachable) that
must exit 2 rather than 1. A section with no mutant reports **fault**, not pass. Run the controls
before trusting a green manifest.

## Related

| Need | Read |
|---|---|
| What the fixture is *for* | `journey-proof.md` |
| Creating login accounts and roles | `manage-security.md` |
| Mendix ID system, associations, bulk insert | `demo-data.md` (project-local, mxcli-bundled) |
| Whether the seed landed, at runtime | `verify-with-oql.md` (project-local) |
