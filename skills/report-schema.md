# `report.json` — the contract between measuring and rendering

**Applies to:** any mxcli project running the journey-proof pipeline (`journey-proof.md`), or any
project that wants a second instrument to appear in the same report as the first.

**Purpose:** one file that instruments **append to** and renderers **read only**. Neither imports
the other, so the renderer can be swapped — static HTML, fleet dashboard, markdown — without
touching a single harness, and a new instrument can be written against a written contract instead
of against whatever the current renderer happens to parse.

**Upstream:** `journey-proof.md` (the verdict discipline this file encodes), `e2e-harness-base.md`
(the harness the instruments live in).
**Downstream:** anything that emits or reads `docs/report.json`.

**Why it exists:** on the project where this was first measured, five instruments emitted **four
incompatible verdict enums in three formats**. That, and not the absence of a dashboard, was the
problem. Expect the same on any project that grew its instruments one at a time.

> **Scope note, and it is load-bearing.** The journey ships **five rungs and seven mutants**
> (`journey-proof.md`; rungs 3 and 4 each carry two mutants). Rungs 6 and 7 in this schema are
> fields written by a **separate** instrument (`design-audit.js`) that has not yet been watched
> going red on real work. This file defines where their output *lands* when that instrument is
> present. It does not promote them. **Do not cite rung 6 or rung 7 in a gate, a module brief, or
> a completion claim.**

---

## The verdict enum — one, everywhere

| Value | Means |
|---|---|
| `pass` | The instrument ran and the system agreed. |
| `fail` | The instrument ran and disagreed. **A real finding.** |
| `fault` | **The instrument did not run.** Not a pass. Not a fail. Never amber. |
| `skipped` | Deliberately not run — a flag, or out of scope. Carries `reason`. |
| `manual` | Needs a human verdict, not yet given. |

The `pass`/`fail`/`fault` split is the whole point, and it is the one thing an ad-hoc findings file
almost never has — which is why a harness that never started renders green.

Two corollaries that are not negotiable:

- **An empty result set is never a pass.** `[].every()` is `true`. Guard non-emptiness before every
  assertion, in the instrument *and* in the renderer.
- **Exit codes:** `rc 2` = instrument fault (could not measure), `rc 1` = finding (measured,
  disagreed), `rc 0` = pass. An instrument that exits 1 when it meant "I could not run" has
  laundered a fault into a finding.

---

## Shape

Every literal below is a **placeholder in an invented domain** — a purchase-request app with a
`Procurement` module, the same domain as `examples/journeys/*.json`. Nothing in it corresponds to
any real project. The **Deriving the values** section says where each one actually comes from.

```jsonc
{
  "schemaVersion": "1.2",              // renderer refuses on major mismatch, warns on newer minor

  "project": {
    "id": "acme-procurement",          // stable key; a fleet index groups on this
    "displayName": "Procurement",
    "mpr": "Procurement.mpr",
    "mprModifiedAt": "2026-01-14T09:12:03Z",   // evidence older than this is stale
    "mendixVersion": "11.13.0",
    "toolkitCommit": "abc1234",
    "gitCommit": "def5678",
    "branch": "main"
  },

  "run": {
    "startedAt": "2026-01-14T04:04:57.932Z",
    "finishedAt": "2026-01-14T04:11:02.115Z",
    "trigger": "journey",              // journey | verify-module | gate-check | e2e | manual
    "target": "Procurement",           // module, "full-app", or null
    "env": {
      "baseUrl": "http://127.0.0.1:<APP_PORT>",
      "host": "studio-pro",            // studio-pro | docker | remote
      "ownership": "verified",         // verified | asserted | unknown — see §run.env.ownership
      "ownershipBasis": "tests/e2e/artifacts/journey-findings.json: stack.env",
      "user": "approver_test_user",
      "userFallbackUsed": false,       // silent admin degrade, made visible
      "database": "HSQLDB default"
    },
    "reproduce": {
      "command": "node tests/e2e/journey-runner.js journeys/Procurement.journey.json",
      "seeds": { "supplierCode": "SUP-0001", "requestId": "PR-0042" },
      "monkeySeed": null
    },
    "evidenceSpansMultipleRuns": false,
    "evidenceTimestamps": []           // populated when it does; see correction 7
  },

  // ── Flat. Nesting is presentation, not data — let the renderer group. ──
  "checks": [
    {
      "id": "journey/J-PR-01/step5/landing",     // stable, sortable, unique
      "instrument": "journey-runner",            // WHO measured
      "kind": "ui",                              // ui | trace | data | outcome | control
                                                 // | build | lint | coverage | conformance | stack
      "module": "Procurement",                   // null for cross-cutting
      "journey": "J-PR-01",                      // null when not a journey check
      "stepIndex": 5,                            // ordinal position on the path
      "stepName": "submit the request",
      "requirement": null,                       // BRD JSON Pointer, or null — NEVER invented
      "title": "reached",
      "verdict": "fail",
      "provenance": "measured",                  // measured | judged | declared
      "notRun": false,                           // true only with provenance "declared"
      "blockedBy": null,                         // "<check id>" when notRun
      "derivedFrom": null,                       // "walks[]" on a derived row
      "tags": [],                                // cross-cutting slices, e.g. "mobile"
      "detail": "\".mx-name-btnSubmit\" never appeared",
      "measuredAt": "2026-01-14T04:04:57.932Z",
      "nonVacuity": {                            // an assertion never seen to fail is decoration
        "controlRan": false,
        "note": "positive control not run for this build"
      },
      "evidence": [                              // paths RELATIVE to report.json, never base64
        { "type": "screenshot", "path": "../tests/e2e/artifacts/J-PR-01-step5-NOT-REACHED.png" },
        { "type": "query", "sql": "SELECT COUNT(*) AS n FROM Procurement.Request", "value": "49" },
        { "type": "trace", "spanCount": 10 },
        { "type": "log", "path": "../tests/e2e/artifacts/desktop.log", "line": 412 },
        { "type": "contract" },                  // no path — see correction 5
        { "type": "command" }
      ],
      "blocks": ["journey/J-PR-01/step5/spans", "journey/J-PR-01/step5/data"]
      // what this check's failure rendered unmeasurable — the renderer draws the
      // severed spine from this, and lists the declared-but-absent expectations
    }
  ],

  // Instruments that produced nothing must SAY so. Absent is not green.
  "instruments": [
    { "name": "journey-runner",   "verdict": "pass",    "rc": 1, "elapsedSec": null, "log": null,
      "canExpressFault": true, "expressibleVerdicts": ["pass","fail","fault"],
      "evidenceStrength": "strong" },
    { "name": "positive-control", "verdict": "fault",   "reason": "not requested (--positive-control absent)" },
    { "name": "monkey",           "verdict": "skipped", "reason": "--skip-monkey" },
    { "name": "conformance",      "verdict": "pass",    "log": "docs/conformance/report-<date>.tsv" }
  ],

  // Rollups have denominators, so they are not checks.
  "coverage": [
    {
      "module": "Procurement", "brd": "F101",
      "leaves": { "total": 1043, "claimed": 1043, "unclaimed": 0, "phantom": 0, "doubleClaimed": 0 },
      "rows": { "buildable": 86, "byStatus": { "built": 28, "partial": 18, "notBuilt": 43 } },
      "conformance": { "checked": 22, "ok": 13, "stale": 2, "understated": 3, "unrunnable": 4 },
      "journeys": [],                            // empty = nothing walks this module
      "source": "architecture/modules/Procurement/coverage-ledger.md",
      "generatedAt": "2026-01-03"                // renderer flags staleness vs run.startedAt
    }
  ],

  // Banked questions. An assumption an agent recorded for itself is UNRAISED, not ASSUMED.
  "deferrals": [
    {
      "id": "D-PR-01",
      "question": "Should the recent-requests panel survive a context clear, or is it scoped to the in-progress request?",
      "position": "treat the empty panel as a defect",
      "requirement": null,
      "reversalCost": "low",
      "consentBy": null, "consentAt": null       // null on both = UNRAISED, never ASSUMED
    }
  ]
}
```

## Rules that keep the options open

1. **Instruments only append to `checks[]`.** They never read the file back and never render.
2. **The renderer reads only `report.json`.** The moment it opens a `.md` or a `.tsv`, the contract
   is dead and every project forks its own renderer.
3. **`evidence[].path` is relative and never base64.** Reports go from megabytes to tens of
   kilobytes, and screenshots stay diffable on disk.
4. **`requirement` is a BRD JSON Pointer or `null`.** Never a synthesised one. A blank cell reads
   as an oversight; `null` plus the gap note reads as the measured fact it is.
5. **`fault` on a missing instrument is mandatory.** Omitting the entry renders as green, which is
   the exact false positive this contract exists to retire.

---

## Deriving the values — never carry a literal between projects

Every field above whose value looks project-specific has a derivation. Use the derivation; a
literal copied from another project's report is a fabricated measurement.

| Field | How to obtain it, in the project you are actually in |
|---|---|
| `project.mpr` | The **single** `*.mpr` in the project root. **Zero found ⇒ error out, do not proceed.** **More than one ⇒ refuse to guess** — list them and require an explicit choice (`MPR_FILE=<name>.mpr`). Same rule the toolkit's own scripts use. |
| `project.id` | A stable slug for the repo — the project root's directory name is the usual choice. It must not change between runs; a fleet index groups on it. |
| `project.mendixVersion` | Read from the project metadata, not from memory of what was installed. |
| `project.toolkitCommit` | The `Toolkit commit:` line in `PROJECT.md` (kept fresh by the session-start ritual), or `git -C <toolkit> rev-parse --short HEAD`. |
| `project.gitCommit` / `branch` | `git rev-parse --short HEAD` / `git branch --show-current` in the project root. |
| `run.env.baseUrl` | Host + `APP_PORT` from `.claude/loop/stack.env`, **with the ownership check below**. Never a literal port. There is no default port you may assume. |
| `run.env.user` | The identity the harness actually authenticated as (`TEST_USER`, resolved by `tests/e2e/config.js`) — **not** the journey's `persona` field, which is a label the runner never authenticates with. When they differ, that difference is itself a finding. |
| `run.env.userFallbackUsed` | `true` whenever the harness fell back from the intended user to an admin identity. A silent admin degrade bypasses exactly the role grants the run exists to test. |
| `checks[].module` | A module name from `SHOW MODULES`. An **empty Source column = first-party**; a populated one is a marketplace/imported module and is not yours to report on. |
| `checks[].detail` selectors | `.mx-name-<widgetName>`, where `<widgetName>` is read from `DESCRIBE PAGE <Module>.<Page>` — or from a widget dump of the live page (`e2e-harness-base.md` step 1). **Never invented, never carried between projects.** |
| `walks[].steps[].page.qualifiedName` | Resolved by intersection against the model catalog — see *Page resolution is an intersection*. Never typed by hand. |
| `checks[].requirement`, `coverage[].brd` | BRD ids and pointers that resolve in **this** project's `analysis/**/F<NNN>.brd.json`. A pointer that does not resolve is worse than `null`. |
| `coverage[].source` | `architecture/coverage-ledger.md` for a single-BRD project, or `architecture/modules/<Module>/coverage-ledger.md` per module. |
| `page.wireframe` | The wireframe path under `design/wireframes/` for that screen, or `null` — see the `skipped` rule for rung 6. |
| `roleSets[].roles` | The module roles the model declares, queried from the model's security, not assumed from a naming convention. |
| `reproduce.seeds` | The values the seed queries **returned on this run**, not the values the contract asked for. |

---

## Corrections from first contact with real data

The shape above was written before any instrument had emitted against it. Building the normalizer
over five live artifacts bent it in ten places. These are part of the contract, not deviations
from it — expect a new project to rediscover them if it skips this table.

| # | Correction | Why the original was wrong |
|---|---|---|
| 1 | **`provenance` has a third value: `declared`.** Carried with `notRun: true` and `blockedBy: "<check id>"`. | `measured` and `judged` are both lies for an expectation that never ran. |
| 2 | **`blocks[]`/`blockedBy` are populated by the normalizer**, not the instrument — it reads the journey contract and generates a `fault` row per declared-but-unreached expectation, reproducing the runner's exact wording so a real row dedupes against its generated twin. | The runner stops at the failed guard and never emits what it was *going to* check. Silence there renders as green. |
| 3 | **`checks[].tags[]`** added (e.g. `mobile`). | No field existed for cross-cutting slices. |
| 4 | **`instruments[].verdict` means "did the instrument run"** — liveness, never a rollup of its checks. The journey runner is `pass` with a failing check. | A rollup reading contradicts the check counts on the same page. |
| 5 | **`evidence[].type` also allows `contract` and `command`**, neither of which has a `path`. | Not every piece of evidence is a file. |
| 6 | **`coverage[].leaves.*` is `null`, never `0`, when the ledger doesn't carry the numbers.** On the measured project, 3 of 4 modules. | `0 unclaimed` and `we never counted` are opposite facts. Painting null green is the exact false green being retired. |
| 7 | **`run.evidenceSpansMultipleRuns` + `run.evidenceTimestamps[]`** added. | `run` was singular; the evidence spanned three calendar days and read as one long run. |
| 8 | **Parse a legacy `summary.tsv` by shape, not by remembered column count**; set `elapsedSec: null` when the column is absent. | The original spec said 5 columns. The file had 4. It was written from memory, not from the file. |
| 9 | **`INFO` maps to `manual`**, raw kept in `sourceVerdict`. | `INFO` carries no verdict; it means a human still owes one. |
| 10 | **Conformance `pointer` cells may be wildcards** (`/actors/*`), not strict JSON Pointers, and arrive decorated with backticks and counts. Strip decoration; anything not starting with `/` becomes `null`. | Rule 4 says never synthesise a pointer — that includes never *cleaning one into existence*. |

Instruments also carry `canExpressFault` / `expressibleVerdicts[]` / `evidenceStrength`, which make
rule 5 machine-readable: an instrument whose dialect has no "did not run" state cannot be trusted
to report one, and the renderer must weight its greens accordingly rather than treating all greens
alike. **Calibration from the measured project: 98 of 163 checks came from such an instrument** —
expect the majority of a mature harness's checks to be structurally incapable of saying `fault`
until they are migrated.

---

## `walks[]` — the narrated walk

Top-level, optional, `[]` when no journey ran. **Never fabricated from the contract**: the contract
says what *should* happen; this section's entire value is that it says what *did*.

```jsonc
{ "journey": "J-PR-01", "title": "…", "persona": "approver_test_user",
  "requirement": ["F101#/useCases/0/mainFlow/0"], "seeds": {"supplierCode":"…"} | null,
  "steps": [{
    "n": 1, "name": "open the request list", "requirement": [],
    "actions": [{"verb":"Click","target":"Requests","selector":".mx-name-btnRequests"}],
    "expects": { "landsOn": ".mx-name-dvRequestList", "pageSays": [], "pageDoesNotSay": [],
                 "microflows": [], "data": { … see below … } | null },
    "reached": true | false | null,
    "status":  "pass" | "fail" | "fault",
    "checks":  [{"rung":"data","name":"…","verdict":"pass","detail":"…","checkId":"…"}],
    "shot":    {"file":"…png","title":"…","url":"…","at":"…"} | null,
    "ms": 4213 }] }
```

`rung` here is one of `ui | trace | data | outcome | control` — the five shipped rungs, named not
numbered. Do not build tooling on rung numbers.

### The data effect — three claims, not one

Earlier drafts of this contract wrote the data effect as
`"writes": {"entity", "delta", "associations"}`. **That shape is wrong and describes only the
first of rung 4's three claims.** A runner emitting it cannot express "saved *with* its
association" or "…pointing at the *right* one", so a second project building to that shape would
silently ship one third of the rung and still report `pass`. Set-ness is not correctness.

The real shape:

```jsonc
"data": {
  "creates": "<Module>.<Entity>",        // qualified name from SHOW ENTITIES IN <Module>
  "delta":   1,                          // claim 1 — something was saved

  "scope":   { "newRowsBy": "id" },      // MANDATORY when either claim below is present

  "assocMustBeSet": [                    // claim 2 — saved WITH its association
    { "entity": "<Module>.<Entity>",
      "assoc":  "<Module>.<Entity>_<Other>",
      "target": "<OtherModule>.<Other>",
      "mustPointAt": {                   // claim 3 — …at the RIGHT one. Optional per assoc.
        "attr":  "<AttributeName>",
        "value": "{{seedKey}}"           // resolves from the journey's seeds
      } }
  ],

  "oql": [ { "label": "…", "sql": "SELECT COUNT(*) AS n FROM …", "atLeast": 1 } ]
}
```

Every name in it is derived, never typed from memory: `creates` and `assocMustBeSet[].entity` /
`.target` from `SHOW ENTITIES IN <Module>`, `.assoc` from `DESCRIBE ENTITY <Module>.<Entity>`,
`mustPointAt.attr` from that same describe, and `{{seedKey}}` from the journey's own `seeds`
block.

**`scope` is not optional decoration.** Without it, claims 2 and 3 are evaluated over the whole
table and give false verdicts in *both* directions: `mustPointAt` passes on a row a previous run
wrote — so it goes green with this journey having done nothing — and `assocMustBeSet` fails
forever on any legacy row with a null foreign key that this step never touched. `newRowsBy: "id"`
makes the runner read `MAX(id)` immediately before the step's actions and scope both claims to
rows above that watermark. The watermark comes from the database that answers the assertion, not
from the runner's clock, so there is no skew to reason about.

A `data` block carrying `assocMustBeSet` with **no** `scope` must be reported as
`[WEAK EVIDENCE]`, not silently accepted.

Four constraints a renderer must honour, each paid for:

| Constraint | Why |
|---|---|
| `status` comes from `checks`, **never** from `shot`. A step with `shot: null` renders normally. | A screenshot is not an assertion. A measured case: a combobox off-by-one committed a valid *neighbouring* row; the shot looked perfect and every downstream signal was green. |
| `checks: []` → `status: "fault"`, and must **look** empty, not clean. | An empty list passing is `[].every()` in another costume. |
| Precedence **fault > fail > pass**. | "Could not measure" outranks "everything we measured was fine", or a walk reads as a clean run through a page whose main claim was never tested. |
| `expects.microflows: []` means the contract **declared nothing** (`—`); a declared expectation that never ran is `⌀`. | Collapsing the two hides unreached scope. |

`shot.file` is repo-relative. The renderer inlines it as a `data:` URI (external hosts are
CSP-blocked) and renders an explicit *why* placeholder — never a broken image — when the file is
absent or the page's size budget would be exceeded.

---

# Schema 1.1 — the report is a per-persona journey, not a test log

Minor bump: every field is additive, so a 1.0 renderer warns and draws what it knows. One thing
that is *not* additive in spirit is called out below — the journey rows of `checks[]` become
derived rather than independently read.

The requirement 1.1 exists to serve: for **every page in the end-to-end process**, the report must
answer six questions, in this order, per persona.

| # | Question | Where 1.1 answers it |
|---|---|---|
| 1 | Which tests ran against this page? | `walks[].steps[].checks[]` (the five behavioural rungs) |
| 2 | Where does the page sit in the process? | `walks[].steps[].n` of `steps.length`, per journey |
| 3 | What data change was expected? | `walks[].steps[].expects.data` |
| 4 | Was it seen? | the `data`-rung entries of `checks[]` for that step |
| 5 | Does the page reflect its **wireframe**? | `page.rung6` — *separate instrument, see the scope note* |
| 6 | Does it reflect general **design practice**? | `page.rung7[]` — *separate instrument, see the scope note* |

"UI test" in questions 5 and 6 means *does the screen look the way we said it would*. It is not a
unit test, and a green unit suite says nothing about either. **Questions 5 and 6 are answered only
when `design-audit.js` is installed, and its answers are not gate-citable** (scope note, top).
When it is absent, say so as its own finding rather than silently absorbing its scope.

## `checks[]` is DERIVED from `walks[]`

Until 1.1 the journey rows of `checks[]` and the rows inside `walks[]` were read out of the same
artifact by two independent code paths, and nothing compared them. **Two structures that can
disagree will.** On the live artifact they happened to agree — 22 walk checks, 24 result rows, zero
verdict disagreements — which is precisely the state in which the first divergence ships unnoticed.

From 1.1:

1. Where a walk exists, **the walk is the checks**. `deriveWalkChecks()` emits one `checks[]` entry
   per walk-step check, with the same id the old path produced (`journey/<id>/step<n>/<slug>`), so
   `blocks[]` expansion and every existing dedupe still land.
2. Attribution improves as a side effect: the walk carries its journey id and step ordinal
   directly. The old path recovered both by matching a step-name prefix against the contracts,
   first match wins.
3. The raw results array is read for exactly two things — rows no walk step owns (login, the
   end-state query) — and reconciliation.
4. Reconciliation is a **check**, not a comment: `derivation/<journey>/walk-is-the-source` is
   `pass` when every walk check has a same-verdict twin in the raw results, and `fail` naming each
   divergence otherwise. With no `walks[]` at all, `derivation/no-walk` is `fault` — the report
   then says out loud that it fell back to the unreconciled path.

A derived row carries `derivedFrom: "walks[]"`.

## `walks[].steps[].page` — the block that joins behaviour to design

```jsonc
"page": {
  "qualifiedName": "Procurement.Request_New" | null,
  "role":          ["Administrator", "Approver"],    // ARRAY, see below
  "inScope":       true | false | null,
  "orphan":        { "classification": "dead-code", "note": "…" } | null,
  "wireframe":     "design/wireframes/request-new.html" | null,
  "rung6":         "pass" | "fail" | "fault" | "skipped",
  "rung7":         [ { "id": …, "title": …, "verdict": …, "detail": … } ],
  "resolvedBy":    "widget-intersection" | "… + in-scope" | "… + same-page actions (WEAK)" | null,
  "candidates":    ["Procurement.Request_New", "Procurement.Request_Edit"],
  "usedSelectors": ["dvRequestForm", "btnSubmit"],
  "why":           null            // populated only when qualifiedName is null
}
```

**`role` is an array and that is deliberate.** A page is visible to N module roles. A scalar would
force the normalizer to pick one, and an arbitrary pick in a security-adjacent field is worse than
a list.

### rung 6 vs rung 7 — which is which

`design-audit.json` files several class-corpus checks under its own `rung6/` id prefix. **This
contract splits them differently**, because the reader's question is different. This is a known
naming collision between the instrument's ids and this schema's fields — do not "fix" it by
renaming one to match the other; map it.

| This contract | Means | Source ids |
|---|---|---|
| `rung6` | Does this page match **its own wireframe**? | `design-audit/rung6/wireframe-conformance/<page>` only |
| `rung7[]` | Does it match **general design practice**? | everything else keyed to the page — the invented-class / never-promoted / wireframe-chrome checks, all of `rung7/*`, and `read/<page>/complete` |

Two consequences, both load-bearing:

- **No wireframe drawn ⇒ `rung6: "skipped"`, and rung 7 still runs.** Skipped is not a pass: the
  page was built without a drawing to build it against. Rung 7 needs no wireframe, which is the
  entire point of rung 7.
- **`partially-read` degrades rung 6 to `fault`.** Under **mxcli issue #891**, an object-list
  item's content-slot children are never read: a DataGrid2 inside an Accordion describes as an
  empty group and a class sweep reports clean **without having looked**. When
  `design-audit/read/<page>/complete` is `fault`, every class finding under that page is a *lower
  bound*, and a `pass` computed from a page only half seen is not a pass — it is rewritten to
  `fault`, and the page must be reviewed by hand (`module-review.md` §4b). Calibration: **6 of 19
  in-scope pages** were in this state on the measured project. Expect a meaningful minority, not a
  rarity.

### Page resolution is an intersection, never a pick

A walk step says `.mx-name-dvRequestForm`; only the model knows that several pages declare a widget
by that name. The normalizer reads the model catalog **read-only** (a `sqlite3 SELECT` against
`.mxcli/catalog.db` — no mxcli invocation, nothing that touches the `.mpr`) and intersects:

1. Widgets the step asserts about the page it is *on* — `expects.landsOn` and every `widget X`
   check. Action selectors are excluded here: a navigation click is issued from the *previous* page.
2. Still ambiguous → narrow to the in-scope set. An out-of-scope orphan is not where a walked
   persona is standing.
3. Still ambiguous → intersect with actions performed anywhere in the contiguous run of steps
   sharing one landing selector, greedily, skipping any that would empty the set. This tie-break is
   **labelled WEAK** in `resolvedBy` and its `page-join` check is `manual`, not `pass`.

**Unresolved ⇒ `qualifiedName: null` and both design rungs are `fault`.** Attaching a wireframe
verdict to a page we could not identify is worse than admitting the hole. Every step also gets a
`page-join/<journey>/step<n>` check, so the join is auditable rather than assumed.

## `roleSets[]` — one report per distinct SET, not per role

```jsonc
"roleSets": [
  { "id": "set-1", "roles": ["Administrator"], "pages": [ … ], "pageCount": 19, "empty": false },
  { "id": "set-3", "roles": ["Approver", "Buyer", "Requester", "Auditor"],
    "pages": [ … ], "pageCount": 5, "empty": false }
]
```

Calibration from the measured project: **9 roles resolved to 4 distinct in-scope page sets, and six
of those roles saw the byte-identical five pages.** Six identical persona reports would present as
thoroughness the very fact being reported, so the renderer emits **one section per SET**, named for
every role that shares it, and the normalizer raises
`scope/security-does-not-differentiate-personas` as a **`fail`**.

On that project the upstream `page-scope.json` and the normalizer's own count **disagreed**: the
artifact declared 3 distinct sets, its own role list contained 4. The difference was the empty one
— a role that reaches nothing in scope. **A role with no reachable surface is still a distinct set
and still a finding**, so the normalizer counts it, keeps the empty set visible, and raises
`scope/distinct-role-set-count-agrees` as a `fail` rather than silently preferring either number.

## `pageCoverage` — the denominator, and the honest headline

```jsonc
"pageCoverage": {
  "inScope": 19, "walked": 2, "uncovered": 17,
  "walkedOutOfScope": [],
  "byJourney": [ { "journey": "J-PR-01", "pages": ["Procurement.Request_New", …] },
                 { "journey": "(no journey for Suppliers)", "pages": [ … ] } ],
  "orphans": [ … ], "generatedAt": "…"
}
```

**Every in-scope page that no walk step resolved to is a `fault` check** — `scope/uncovered/<page>`,
`provenance: "declared"`, `notRun: true` — filed under the journey that should have covered it, or
under `(no journey for <Module>)` where none exists.

The renderer promotes `uncovered` to the **verdict headline**, above the pass/fail counts, because
every other number on the page is a statement about the walked minority. A pass count next to a
denominator nobody printed is the false green this contract exists to retire.

Calibration: the measured project had **19 in-scope pages and 2 of them walked**. Expect single
digits to low tens walked on a first pass, against an in-scope denominator in the tens — and expect
the raw project page count (all modules, all imported) to be an order of magnitude larger, which is
exactly why `inScope` and not the raw count is the denominator.

## `run.env.ownership` — which application did you actually measure?

`ownership` and `ownershipBasis` sat in this schema from the first draft and **nothing wrote them**,
so every report to date was silent about which application it measured. That went from theoretical
to measured the day a harness was pointed at a port another project's app was serving on, and
reported normally.

`tests/e2e/config.js` resolves them:

| Value | Means | Basis |
|---|---|---|
| `verified` | a container published this port **and** its compose `working_dir` label is this project — the one identity claim that cannot be true of two projects at once | `APP_OWNERSHIP=verified` in `.claude/loop/stack.env`, written by `bin/test-stack-up.sh` |
| `asserted` | an operator said so and nothing checked | an `APP_PORT` env var, or the project's deployment config |
| `unknown` | a Mendix answered and nothing more | a guess, or a `stack.env` predating the marker |

`config.js` **refuses to run** (`exit 2` = instrument fault, never `1` = finding) on anything below
`asserted` unless an explicit override env var is set.

The normalizer prefers an **instrument-recorded** ownership over its own after-the-fact detection:
the instrument knows which app it actually talked to; the normalizer can only inspect the
environment afterwards. `ownershipBasis` is then prefixed with the artifact that carried it.
Missing on every artifact ⇒ fall back to detection; missing there too ⇒ `unknown`, never a guess
dressed as a fact.

## Verdict discipline in 1.1 — unchanged, and not weakened

`pass | fail | fault | skipped | manual`. Never collapsed to two, never to three.

- `fault` is **never amber** and never renders green. Amber reads "ran, degraded"; the truth is
  "nothing here". It is the only achromatic + dashed + hatched state in the renderer.
- `partially-read` (mxcli #891 / lost content slots) → `fault`.
- `skipped` on rung 6 means *no wireframe was drawn*, not *the page is fine*.
- **Measured** and **judged** stay unblended, and `declared` (never ran) is a third value that is
  neither.
- A report with zero checks says **`NOT MEASURED`**, not pass.
- Every behavioural check green with the design rungs red renders **`FAILED ON DESIGN`**, tested
  *before* the generic incomplete branch. "INCOMPLETE — N were never measured" is technically true
  and reads as an instrument problem, which invites the reader to assume the pages are fine. They
  are not known to be. A page that works and looks wrong is a page that ships wrong.
  (Because rungs 6–7 are not gate-citable, a `FAILED ON DESIGN` headline is a signal to a human,
  not a gate verdict.)

## Versioning

`schemaVersion` is `major.minor`. A renderer **refuses a major mismatch outright (exit 2)** and
**warns on a newer minor**, rendering the fields it knows. Instruments emitting an older minor are
read as-is with missing fields treated as `null` — never as `false`, and never as `pass`.

Measured, unpiped so the exit code is the renderer's and not a downstream tool's:

| `schemaVersion` | Behaviour | rc |
|---|---|---|
| `2.0` | REFUSED, major mismatch | **2** |
| absent | REFUSED, undeclared contract | **2** |
| `1.1` | rendered | 0 |
| `1.2` | rendered (current) | 0 |
| `1.3` | WARNING on stderr, page rendered | 0 |
| `1.4` | WARNING on stderr, page rendered | 0 |

---

# Schema 1.2 — every hole says what would close it

Additive minor. A 1.1 renderer warns and renders every field it already knew; nothing was removed
and no field changed meaning.

## The measured problem

The 1.1 render of the measured project's report contained the string **"DID NOT RUN" 135 times**
and the strings *"next step"*, *"remediation"* and *"how to fix"* **zero times**. Every one of
those 135 rows correctly refused to be green — the verdict discipline held — but a reader could not
act on any of them. Two further gaps in the same render:

- the findings table had **no column naming the page**, so dozens of design findings rendered as
  `no invented classes` with nothing saying *which page*;
- the report had **no next-steps section at all**, per page, per process or overall.

**A `fault` that does not say what would close it is a shrug wearing a verdict's clothes.**

## `checks[].remediation` — four sentences, on every non-pass

Present on **every** check whose verdict is not `pass`. Absent on a pass (there is nothing to do).

```jsonc
"remediation": {
  "class":        "trace-zero-spans",   // stable grouping key; also the nextSteps[] group id
  "measures":     "which microflows fired, in what ORDER, …",   // what it WOULD have measured
  "why":          "the span capture returned an empty set …",   // why it did not run / why it failed
  "blastRadius":  "NO microflow-ordering claim anywhere in this report is proven …",
  "action":       "Before re-running, verify the collector end to end: (1) curl …",
  "actionKind":   "harness",  // journey | harness | model | design | ledger | infra | unknown
  "needsApproval": false,     // true ⇒ the action is a MENDIX MODEL write; approval rule applies
  "where":        "tests/e2e/otel.js"   // the file / page / microflow to open
}
```

**Constraints, each from a defect caught while writing this:**

| Constraint | Why |
|---|---|
| `class: "unclassified"` with `action: null` is the ONLY honest fallthrough | The classifier must never invent plausible advice for a row it does not recognise. An unclassified row is a gap in the normalizer's remediation table, and the renderer says exactly that. |
| The renderer emits `NO REMEDIATION DERIVED` for a non-pass with no `remediation` | Silence would read as "nothing to do". |
| `measures` on a **group** is synthesised, never the first member's | A 32-check group first rendered one member's expectation sentence, presented as the loss of all 32. |
| `needsApproval` is set wherever the fix is a model write | No `mxcli exec` without approval. The report must not hand a reader an action that quietly breaks that. |
| A remediation must not repeat the instrument's own guess | The runner writes e.g. *"collector down or tracing off"*. That is a guess, not a measurement; the remediation says so and supplies the two commands that decide it. |

## `nextSteps[]` — the same remediations, grouped and ranked

```jsonc
{ "rank": 1, "id": "next/journey-severed-procurement",
  "class": "journey-severed", "tier": 2, "scope": "module",
  "target": "Procurement",
  "measures": "…", "why": "…", "blastRadius": "…", "action": "…",
  "actionKind": "journey", "needsApproval": false,
  "where": "journeys/Procurement.journey.json",
  "count": 32, "verdicts": { "fault": 32 },
  "affects": ["J-PR-01"],
  "checkIds": ["journey/J-PR-01/step1/…", …] }   // never a summary that loses its members
```

Ordering is **`tier`, then count descending, then id** — blast radius first, never volume. Tiers:

| Tier | Meaning |
|---|---|
| 1 | Blocks whole processes (a failed landing guard) |
| 2 | Severed *by* tier 1 — no separate work; they measure themselves once it is fixed |
| 3 | A user meets this defect on the golden path |
| 4 | An entire rung of evidence is missing |
| 5 | Pages nothing has ever walked |
| 6 | The instrument cannot see the page, or cannot say which page it saw |
| 7 | Design evidence absent for a page |
| 8 | Design defects, measured |
| 9 | Leads from the weaker (pass/fail-only) instruments |
| 10 | Governance and documents |
| 99 | Unclassified — a gap in the remediation table |

Tier 1 sits **above** tier 2 deliberately: the severed rows' own action is *"fix the blocking check
first"*, so listing them above the guard told the reader to do nothing before telling them what to
do.

## `walks[].steps[].checks[].checkId`

The narrative check and the verdict check are the same measurement seen twice. `checkId` joins
them, so the walk can render a fault's remediation **inline, beside the screenshot**, rather than
only in the summary at the top. Stamped when the walk checks are derived and carried through
collection.

## What the renderer adds at 1.2

| Section | Rule |
|---|---|
| **What to do next** | Second section on the page, above the persona tables. An empty `nextSteps[]` with findings present renders *"produced by a normalizer older than schema 1.2"* — never *"nothing to do"*. |
| **Per-page next steps** | Rendered inside the walk under each page block. **Derived from that page's own checks, not from the project-wide group** — the first cut reused the group's action, and the panel under one page told the reader to go fix a different page in a different module. The group is used only for its rank, so the two orderings cannot disagree. |
| **Per-process next steps** | Rendered at the end of each journey walk, deduped by class, ranked globally. |
| **Findings table `Where` column** | `page` → `module` → `journey`, and `NOT ATTRIBUTED TO A PAGE` when none exists. Never a blank cell. |
| Verdict vocabulary | **Unchanged.** `fault` is still achromatic, hatched, `DID NOT RUN`, never amber. An action is not a verdict and is not colour-coded. |

---

# Rendering rules added 2026-08-20 — coverage is the headline

**No schema change. No field added, none removed, nothing renamed, `schemaVersion` stays
`1.2`.** Everything below is derived by the renderer from fields the contract already
defines, so a 1.1 or 1.2 report renders under the new rules with no re-normalisation, and an
older renderer reading the same file still works. It is written here because it changes what
the report *says*, and this file is the contract for that.

## The measured problem, again, one layer up

VB-USI-main, `docs/report.json` at 1.2: **611 checks — 205 pass, 23 fail, 353 fault, 30
skipped.** A human read the rendered page as "roughly 90% healthy". It is 205 of 611 — **34%
executed and agreed, and 58% never ran at all.** Four instruments were at verdict `fault` for
the entire run (coverage-ledger, conformance, deferrals, full-app-walkthrough). A hand
walkthrough minutes later found a runtime crash, a broken widget, an unstyled page and a live
data-integrity bug, every one of them on a surface inside those 353.

Every one of those 353 rows already rendered as `DID NOT RUN`. **The verdict discipline held
perfectly and the report was still misread**, because the arithmetic a reader does in their
head is done on whichever number is largest and highest on the page. Verdict-per-row is
necessary and it is not sufficient; the *summary* has to carry the same discipline.

## The four rules

| # | Rule |
|---|---|
| 1 | **The report leads with coverage.** The first element inside the verdict card, above the verdict word, is one line: `58% of 611 checks did not run · 205 passed · 23 failed · 353 did not run · 30 skipped`. Same sentence on stdout. Two summaries of one run can therefore never disagree — they are one function, `executionLine()`. |
| 2 | **One denominator, and it is every check.** `ran = pass + fail`. A `fault` never ran; a `skipped` did not execute either. **No pass rate is printed anywhere.** The single percentage the document is allowed to contain is the share that did **not** run — the one figure an instrument dying early makes *worse* rather than better. Any ratio printed elsewhere counts faults in its denominator or is not printed. |
| 3 | **Counts are ordered not-run first.** The old counts row led with the pass cell, so the largest and greenest number was also the first one read. |
| 4 | **"Did it produce anything" is its own axis**, beside the existing `evidenceStrength` / `canExpressFault` badges and distinct from the liveness verdict. An instrument with **no** `checks[]` entry is badged `NOTHING EXAMINED — NO CHECKS EMITTED`; one whose every check is `fault` is badged `EVERY CHECK DID NOT RUN (n of n)`. Both get the hatched hole treatment even when their own `verdict` is `pass`, and both are named in one alert rather than left to be counted off the tiles. |

Nothing here blocks. No gate, no exit code, no refusal to render — other projects run this
renderer on their own reports and a change that stops their work gets switched off rather
than obeyed. The number is made impossible to misread instead.

**Vocabulary is reused, not invented.** `NOTHING EXAMINED` is `bin/open-questions.sh`'s rc-3
state, and `bin/questions-report.sh:72` refuses outright to render a clean-looking zero over
it — the closest existing precedent for this whole change. "cannot evaluate, which is not a
pass" is `bin/gate-check.sh`'s wording, verbatim.

## Instrument rows join to checks on the name before the first slash

Rule 4 needs to know which checks an instrument appended. `instruments[].name` is sometimes
per-module (`coverage-ledger/Sales`) while the checks it emits carry the base name
(`coverage-ledger`), so **both sides are keyed on the segment before the first `/`**. A name
that fails to join counts as *we could not tell*, never as *it produced nothing* — the flag
is deliberately conservative, because a false "produced nothing" would be its own false
signal. **If you add an instrument, make its `instruments[].name` and its
`checks[].instrument` share that first segment**, or its tile will under-report.

## Every absent artifact names what would write it

`report-normalize.js` carries a `PRODUCERS` table from input path to the command that writes
it, and the `missing` fault reason appends it:

> `tests/e2e/artifacts/findings.json` does not exist — the instrument did not run, or ran
> without writing. `node tests/e2e/full-app-walkthrough.js` writes it; until it does, nothing
> in this report is evidence about what it would have measured.

Same house style as `bin/gate-check.sh:577`: name where it looked **and** what produces it.
The walkthrough entries come from `project.config.js` → `walkthroughs[]`, not from literals.
**Verified producers only** — a path with no entry says it has no entry and names the table
as the gap, exactly as `class: "unclassified"` with `action: null` is the only honest
fallthrough for a remediation. An invented command is worse than an admitted hole.

---

## Adding a new instrument — the short checklist

- [ ] It **appends** to `checks[]` and never reads the report back or renders anything.
- [ ] It emits an `instruments[]` row **whether or not it ran**, with `fault` when it did not.
- [ ] Its `instruments[].name` shares its first `/`-delimited segment with the
      `checks[].instrument` value it stamps — otherwise the "produced no evidence" badge
      cannot join the two and its tile under-reports (see *Instrument rows join to checks*).
- [ ] It declares `canExpressFault` / `expressibleVerdicts[]` honestly. If its dialect cannot say
      "did not run", say so — the renderer must weight its greens down, not treat them as equal.
- [ ] Every assertion guards non-emptiness first. `[].every()` is `true`.
- [ ] It exits **2** on instrument fault, **1** on finding, **0** on pass.
- [ ] Every non-pass check carries a `remediation`, or `class: "unclassified"` with `action: null`.
- [ ] Every value that looks project-specific came from the derivation table above, not from
      another project's report.
- [ ] `requirement` is a resolving BRD pointer or `null`. Never synthesised, never cleaned into
      existence.
