# Decompose App — Splitting a Mendix Monolith into Several Apps

**Applies to:** any mxcli project — an existing Mendix app (9 or later) being split into several
Mendix apps, one slice at a time, with the monolith staying live (strangler).
**Purpose:** Pick cuts that are both a business capability and cheap to wire, move each slice by
module package (MPK), account for every crossing edge, and report the level each slice reached.
This is the Change-an-existing-app mode (`existing-app-change.md`) with a cut-scoring Stage 3 and a
per-slice Stage 5 loop.
**Evidence:** increments run 2026-10-12/13. Increment 1 built `bin/cut-score.sh` on a synthetic
4-module app (Mendix 10.24). Increments 2–8 ran on a public field-service template (Mendix 9.24.2,
MPR v1): increment 2 the read probe and the first cut scoring, 3 a native notes slice by MPK,
4 a first seam probe, 5 an asset/parts web slice, 6 the monolith publishing its core, 7 that
slice strangled out of the monolith (level 3), 8 a dispatch/workforce slice run from this skill. "Increment N" below names those runs; results in
`pipelines/mendix-mpr/README.md` → "Field runs". Their captures are not committed to the toolkit.

**Not this skill:** regenerating a whole `.mpr` as MDL into a clean app → `rehost-app.md`.
Module boundaries *inside* one app → `modularize-domain.md` / `layering-review.md`.

---

## Stage 0 — Preconditions and scope

Bound: every line below is a `PROJECT.md` register line, `CONFIRMED` or `ASSUMED`.

1. **Mendix 9 or later.** Earlier versions are out of scope; the upgrade hop is the customer's job.
2. **Work on a copy.** The original `.mpr` is read-only for the whole decomposition.
3. **A 9.x monolith is converted to 10.24 first** (`mx convert`, on the copy) — a means, not a
   deliverable. Why: Mendix refuses a 9.x package into 11.x, so the MPK export always goes through a
   10.24 copy. mxcli ≤ 0.26.0 also cannot create or alter a microflow in a 9.x project, so today the
   monolith-side edits run on that copy too; **[fixed after 0.26.0]** (microflow written into 9.24.2, `mx check` 0)
   — then monolith-side edits can stay on 9.x. `mxcli run` still fails on 9.x (nightly: the runtime
   launcher rejects JDK 17, `Java 11 is required`). Budget the one-time fixes
   (marketplace and widget updates, Java API edits): on the field-service template they cost more than the
   seam itself (increment 4).
4. **Lanes are OData and REST only.** No Event Broker licence, so Business Events is not a lane; an
   edge that is neither OData nor REST blocks.
5. **Scope interview** (`interview-protocol.md`; ask, then stop): why split (team, cadence, licence,
   risk); how many apps may exist (each app is a licensed cloud node); may a slice leave Mendix;
   is data migration of existing rows in scope (the toolkit has not measured it).

## Stage 1 — Read and score

Bound: `analysis/cut-score.json` exists for the chosen cut, and each slice has a written business
reason beside its coupling numbers.

1. Facts: `project-bin/app-facts.sh` (writes `dependencies.json` and the catalog), then
   `bin/app-layer-map.sh`.
2. Score candidate cuts: `bin/cut-score.sh --cut "A,B|C|D"` (read its header for flags). Every cut
   on a tangled monolith reads `blocked`; compare crossing refs and blocker rows, not the verdict.
   Retire test modules; copy utility modules a slice pulls on.
3. **Choose on business fit AND coupling.** The failure: `NativeNote`, the cheapest cut, became the
   first slice and is a poor business slice — 26 behaviour stubs went out (increment 3). The
   recipe: build a capability table — modules, entities, roles using it, in/out refs by lane, biggest
   no-lane calls, one sentence of business fit — and rank. A slice that is mostly inbound reads
   (OData-able) and a plausible separate system of record (Assets & Parts, Insights) beats a cheap
   fragment of the core.
4. Known score blind spots (measured on the field-service template, increment 2): `call` mixes server and client-side calls
   (a nanoflow/JS-action call lanes *copy*, not OData); `sync` refs never reach
   `dependencies.json`, so an entity synced to the device that lands in the other app is an
   unseen blocker. Check both by hand.
5. **Native and web slices differ.** A native slice needs a native profile: target the Blank
   Native Mobile starter. An offline profile cannot sync an external entity, so data the device
   needs from the other app arrives as REST-fed local copies, not OData.

## Stage 1b — Target architecture (gated) ✋

Bound: `architecture/target-architecture.md` holds all eight sections below, its module map states
N/N own modules assigned or retired, and every decision is a `PROJECT.md` line, `CONFIRMED` or
`ASSUMED`. No cut, MPK export or seam work starts before this gate.

The failure it prevents — seven field-service template increments ran without it, and each of these was decided late:
`NativeNote` was cut on coupling alone, yet notes belong to work orders (238 in-edges stayed
behind); Assets & Parts went build-green with **120 out-stub rows** because the core was not
published first (increment 5; 120 → 32 once it was, increment 6); keys, machine-role auth, key-copy joins, dual writes and OData
page outage behaviour were invented mid-build (`mendix-service-seam.md`).

Write it with `architecture-blueprint.md` Step 7b §A (single vs multi-app), Step 3 (wiring, here
between apps), Step 6a (roles) and Step 6c (contracts). Sections and their checks:
1. **Target landscape** — the apps, within the Stage 0 app count.
2. **Capability → module → app map** — every own module assigned to an app or `retire`: N/N.
3. **Data ownership** — every entity crossing a cut has exactly one owning app.
4. **Contract per seam** — lane (OData read / REST action / key copy / local owner / hand-off),
   key, versioned path (`mendix-service-seam.md` P1, P10, recipe B).
5. **Auth between apps** — machine role now (P2); the token-based target named.
6. **Cut order** — follows dependency direction, core published first (Stage 2 recipes).
7. **Mobile/offline partition** — which app owns the native profile and synced entities.
8. **Non-goals** — e.g. who owns data migration of existing rows.

Gate: put it to the user per `interview-protocol.md` §3, end the turn, wait. Moved modules need no
wireframes or build plan — the existing app is the spec. Only redesigned parts do (legacy widgets →
React client, new seam services, navigation across apps): `design-artifacts.md`,
`brd-to-build-plan.md`.

## Stage 2 — Sequence the cuts by dependency direction

Bound: for each planned slice, every out-edge target is either moving with it, copied, platform,
or already published by the monolith.

A slice can only go seam-live when what it depends on answers over HTTP (failure: Stage 1b).
Recipe — the Stage 1b cut order picks one:
- **Monolith publishes first.** Before cutting a leaf, publish the core services its out-edges need
  (OData for reads, REST for writes) from the 10.24 monolith copy; the slice consumes them.
- **Cut in dependency order.** Cut what the leaf depends on before the leaf, so out-edges point at
  an app that already publishes.

**Pre-check: out-edges no service can carry.** Grep the slice's access rules for XPath paths into
other modules (16 such rows on the field-service template). XPath cannot cross apps, so decide per path before cutting:
local owner entity, REST-fed copy, or hand-off. Joins across apps go through a published mirror
(`mendix-service-seam.md` recipe B).

## Stage 3 — Move the slice (MPK route)

Bound: every slice module installed; target `mx check` errors are crossing edges only.

1. Create the target. Web: `mxcli new <App> --version 11.x`. Native: download the Blank Native
   Mobile starter and `mx create-project` with an **absolute** `--output-dir` (relative fails).
2. Export each module from the 10.24 copy:
   `python3 -I pipelines/mendix-mpr/export-module-mpk.py <src.mpr> <Module> <out.mpk> --json`.
   It keeps unit and entity IDs, scrubs secrets, and refuses MPR v2 sources (read its header).
3. Install **dependencies first**: marketplace modules the slice needs (`marketplace install`),
   then copied modules, then the slice: `mxcli marketplace install --file <out.mpk> -p <target.mpr>`.
4. Mendix 10 targets: `mxcli fix widgets` after page exec. 10.x packages into 11.x: legacy widgets
   become CE0582 on the React client with no warning at install. Workaround (increment 5,
   22 widgets): read each legacy widget with `mxcli bson dump` and write its React-client
   equivalent (the converter scripts of that run are not in the toolkit); converted pages are
   `not-expressible` drift on the fidelity check.
5. Java bodies arrive byte-identical; Mendix 9 API calls are hand-edits
   (`pipelines/mendix-mpr/README.md` → "The MPK route").

## Stage 4 — Account for every edge

Bound: `bin/cut-ledger.sh` exits 0 (0 unresolved rows).

1. Write `slice.txt` (modules, plus `Module.Doc` lines for documents that move alone) and a
   `cut-rules.tsv` in the format `bin/cut-ledger.sh`'s header gives; every rule carries evidence.
2. `bin/cut-ledger.sh --catalog <catalog.db> --slice slice.txt --rules cut-rules.tsv
   --check-log <mx-check.txt> --exporter-json <export.json> -o cut-ledger.tsv`. Exit 1 while any row
   is unresolved.
3. Resolutions: `resolved[:how]` (moved, copied, starter, marketplace, odata, rest, page-odata,
   local-owner), `stub` (green but
   carries no behaviour — evidence says what is missing), `handoff` (named human work), `retire`,
   `platform`. **The stub count is the progress measure**; a stub is never a resolution.
4. **Level 3:** ledger the monolith's in-edges too. **In-edge hand-offs become the measure** (field-service
   template, increment 7: 499 → 157). Extra kinds: `resolved:rebind` (XPath text re-pointed), `resolved:pull` (device copy
   pulled from the slice), `resolved:rewired`, `resolved:association` (re-created local → external).
   A hand-off naming a deleted module is a defect, not a resolution.

## Stage 5 — Build the seam

Bound: every behaviour-carrying stub is replaced by a working call, or is still counted.

Patterns, anti-patterns, external-entity limits and completion criteria for the seam itself live
in **`mendix-service-seam.md`** — read it before the first publish. Decompose-specific points:

- **Reads: OData** as external entities, keyed per P1 (on the field-service template 9 of 10 core
  entities had no safe existing key), each stub replaced in recipe A order.
- **Writes: a published REST action** when the write carries behaviour (P3), else Send External
  Object. DateTime per P9.
- **Ownership flips.** Once the slice serves an entity it is the system of record; a local save
  kept next to the REST call is a dual write, a hand-off row until one side goes (P13).
- **Errors.** Every REST call gets `on error without rollback`; OData-backed pages have no error
  path (P4).
- **Security Production on both sides**, machine role only on the services (P2), credentials in
  machine-local constants. API account passwords meet the Mendix password policy — a failing
  after-startup create kills the boot — and a `__SET_ME__` sentinel needs a guard where code acts on
  it (P11); production auth per P2. Stub entities need module roles too (CE2729 otherwise).
- Monolith edits: see Stage 5b step 7.

## Stage 5b — Strangle (level 3 only)

Bound: the monolith passes `mx check` 0 and `BUILD SUCCEEDED` with the slice modules deleted, and 0
hand-off rows name a deleted module.

Not describe → edit → exec: on the field-service template 25 of 38 referencing pages held widgets mxcli cannot author
(34 DataGrid, 21 ReferenceSelector). Edit in place:

1. `move entity` each slice entity the monolith still uses into **one** consumer module (seam P6).
2. Swap each for a same-name external entity (seam recipe A order); pages and flows rebind by name.
3. Re-create monolith-owned associations local → external (seam limits → Associations).
4. `drop module` each slice module.
5. Work the `mx check` phases in order: **CE1613** (access rules and selections naming dropped
   members — `drop module` leaves them), then **CE0161 / CE0463** (XPath across the seam; widget
   definitions), then **CE2729** (module roles on the new entities).
6. Rebind XPath and expression text: `move entity` leaves qualified names in strings unchanged (62
   strings in 24 units still read `AssetManagement.Asset…`). Grep the old module names; 0 hits.
7. Monolith flows: edit only what needs editing. Edited flows went through drop + create, which
   resets the layout and broke an unchanged decision (`[CE0117] "Error(s) in expression." at
   Decision 'User is SDE?'`). Keep a per-unit restore path (a copy before each exec).
8. Offline push chains and the monolith's own delete cascades break silently: seam limits
   "Offline" and P13.

## Stage 6 — Prove and report the level

Bound: the slice report names exactly one level. The three levels were CONFIRMED with the user
2026-10-12; level 3 was amended 2026-10-13 from field evidence: "one journey per crossing edge"
became **one journey per crossing kind**, because per edge was undefined for 536 in-edge rows
(increment 7).

| Level | Criteria |
|---|---|
| 1 build-green | `cut-ledger.sh` 0 unresolved, `mx check` 0, `BUILD SUCCEEDED`, moved documents describe-identical |
| 2 seam-live | every behaviour-carrying stub replaced by a working REST/OData call, or handed off with a written reason when external entities cannot carry it (XPath, aggregates) — hand-offs counted separately from stubs; security Production, roles mapped |
| 3 strangled | monolith in-edges rewired or handed off (Stage 4 step 4); modules deleted from the monolith (Stage 5b); one journey per crossing kind (read, write, join, sync pull, offline forward) passes with data checked in both databases, and passes again on a second consecutive run (idempotent) |

Calling level 1 "done" hides the stubs. Journeys follow `project-tests/e2e/journey-runner.js`:
landing guard and ledger pointer per step, data effects checked by `mxcli oql`, exit 2 for an
instrument fault. Measured: increment 7's journey across both apps passed 16/16 steps on two
consecutive runs.

## Stage 7 — Learnings

Bound: every finding of the run is in exactly one place.

- mxcli defect with verbatim repro → a `contrib/inbox/` drop, triaged into `bug-logs/mxcli-bugs.md`.
- MDL rule an author would trip on → a `contrib/inbox/` drop, promoted to `skills/learned-mdl-preflight.md`.
- Judgement about cutting, sequencing, seams → this skill. Instrument gap → `bin/` with a fixture.

`CHANGELOG.md` line in the same commit, crediting the source project.

---

## Traps on this route (mxcli 0.26 and platform)

Each line: trap → workaround → the increment that measured it. Tag **[fixed after 0.26.0]**: fixed on mxcli main after 0.26.0 (`nightly-80-gbd45c47e`, nightly retest 2026-10-13), not yet released — keep the workaround while `mxcli --version` reports ≤ 0.26.0; drop it once your mxcli includes the fix.

- Microflow create/alter refused on 9.x **[fixed after 0.26.0]**; `mxcli run` fails on 9.x (nightly: launcher wants Java 11) → convert to 10.24 (increment 4).
- exec is not atomic; a recommended drop + create can stop after the drop → copy first, `mx check` after every exec (increments 3, 4).
- No `-p` silently picks any `.mpr` in the working directory → always pass `-p` (increment 3).
- `with all` omits nanoflows → describe them one by one (increment 3).
- JS/Java action type parameters describe as entity `.Entity` → hand-off row (increment 3).
- No native navigation profile can be created → native starter as target (increment 3).
- OData publish passes `check` with no key or a non-unique key → `PublicID: AutoNumber default 1`; expose bare attribute names, not quoted (quoting **[fixed after 0.26.0]**) (increment 5).
- `mxcli new` 11.x apps are MPR v2 → back up `<app>.mpr` **and** `mprcontents/` (increment 6).
- 11.x consumed OData: `ConfigurationMicroflow:` holding a headers microflow → CE6808, and the slot cannot be cleared; `set (ConfigurationMicroflow: none)` stores a microflow named `none` that crashes `mx check` → drop and recreate the consumed service with `HeadersMicroflow:` only (increment 6).
- Combo box on an association passes `check`, fails exec or `mx check` → wrap in a data view (increment 5).
- `marketplace update` needs `--force` on a converted copy and leaves CE0463 → `mx update-widgets` with an absolute path; DataGrid 2 on 10.24 reads `CE0463 "The definition of this widget has changed"` until `mxcli fix widgets` (increments 4, 5, 7).
- Trial licence: machine OData sessions count against the user cap → `The OData endpoint returned 402 Payment Required` (increment 7), and the trial caps logins too (`Maximum number of sessions exceeded!`, increment 6) → restart the runtime between journey batches; for repeated e2e runs use a licensed test environment.
- `limit 1` retrieve is a list but `check` accepts object operations → use `first`, then drop + create (increment 4). Nightly: `mx check` names it CE7247 and a splice to `first` clears it; `mxcli check` still passes it.
