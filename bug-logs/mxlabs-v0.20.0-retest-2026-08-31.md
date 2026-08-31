# mxlabs mxcli v0.20.0 retest — 2026-08-31

Open bugs retested against a freshly built v0.20.0, cross-checked against the v0.19.0
(2026-08-21) and v0.20.0 (2026-08-28) changelogs — two releases landed since the last
retest baseline (v0.18.0, 2026-08-20). Investigation only; no GitHub issues filed; no real
project touched — every probe ran in a disposable copy of a scratch app created for this
retest.

## Gate 0 — binary tested

- Repo: shallow clone of `https://github.com/mendixlabs/mxcli` at tag `v0.20.0`
- **Commit tested: tag `v0.20.0`**, `git describe --tags` = `v0.20.0` (clean tree, not `-dirty`)
- Built with `make build` on Linux amd64, go1.24.7 (ANTLR 4.13.2 jar fetched manually —
  `antlr4-tools`' own downloader is blocked by the egress proxy)
- Verified: `mxcli version v0.20.0 (2026-08-31T07:00:24Z)`

## Test environment — stronger than the v0.18.0 retest in one important way

- Baseline: **blank Mendix 11.13.0 app scaffolded by `mxcli new TestApp --version 11.13.0`**
  itself (v0.20's own scaffold: split-model MPR v2, 370 `.mxunit` files, project-owned
  `MyFirstModule.App_Default` layout, signal theme), first build settled by `new`.
- **Control: `mxcli docker check` = 0 errors on the pristine baseline.** Clean, unlike the
  v0.18.0 retest's 3-error baseline.
- Host is **Linux amd64**, so the auto-downloaded mxbuild 11.13.0 actually executes —
  every "docker check" verdict below is a **real native mxbuild consistency check**, the
  layer the v0.18.0 retest (macOS, `exec format error`) could not run. `docker check` on
  v0.20 preserves the split tree (BUG-60 fix held).
- Disposable copies: the **whole project tree** is copied per probe group, not just
  `.mpr` + `mprcontents/` — a model-only copy loses `widgets/` and produces 1082 bogus
  CE0462s. (Learned in this run's first, discarded probe.)
- ADR-0008 write-elision is still in effect; verdicts rest on `DESCRIBE`/`SHOW` read-backs
  or mxbuild output, never on a success line alone.

## Verdicts

| Bug | Verdict | Fixed in | Build-verified |
|---|---|---|---|
| BUG-97 15th-cumulative-write corruption | **NOT REPRODUCED** | — (see notes) | yes — 0 errors at writes 14, 15, 16 |
| BUG-85 DROP ATTRIBUTE orphans/keeps validation rule | **FIXED** | v0.19.0 (changelog: "DROP ATTRIBUTE left orphaned validation rules behind") | yes (0 errors) |
| BUG-69 DROP ATTRIBUTE "RefID" silent no-op | **FIXED** | ≤v0.20.0 | yes |
| BUG-82 cannot clear a "not null" validation rule | **FIXED** | ≤v0.20.0 — `MODIFY ATTRIBUTE … NULLABLE` now really removes it | yes |
| BUG-66 `ADD ATTRIBUTE … autocreateddate` silent no-op | **FIXED** | ≤v0.20.0 — adds for real; name mismatch → new MDL022 warning | yes |
| BUG-79 GRANT on System.* leaks missing-file error | **FIXED (better refusal; limitation is Mendix's)** | v0.20.0 | n/a (refusal) |
| GRANT: 2nd grant replaces rule / one rule per role | **FIXED** | v0.19.0 (#936) — additive merge + per-XPath-constraint rules | yes (0 errors) |
| BUG-01 drop attribute carried by access rules → MPR corruption | **FIXED** | ≤v0.20.0 — "Removed 3 access rule member reference(s)", grants updated | yes (0 errors, cold load) |
| BUG-64 `ALTER SETTINGS CONFIGURATION` port fields silent no-op | **FIXED** | v0.20.0 (settings-write resolution work) — `show settings` reads back `http=8080` | yes (0 errors) |
| BUG-58 `SET Editable = [expr]` blank AttributeIdentifier → SP load crash | **FIXED** | ≤v0.20.0 — expression stored, describes back, no StorageLoadException | yes (0 errors on that page) |
| BUG-71 REPLACE of a DataGrid2 column deletes it | **FIXED** | v0.19.0 (#891) — bare name **refused** naming `grid.column`; qualified form replaces in place | yes |
| BUG-91 `DynamicCellClass` CREATE-time only | **FIXED** | ≤v0.20.0 — `SET DynamicCellClass … ON grid.col` lands and describes back | read-back |
| BUG-74 `on error {}` silently gets `return;` appended | **FIXED** | ≤v0.20.0 — describe shows clean handler, flow continues | yes (0 errors) |
| BUG-75 quoted attr path in call-microflow arg → CE0117 | **FIXED** (call-arg form) | ≤v0.20.0 | yes (0 errors) |
| BUG-90 loop-var attr path inlined into call param → CE0117 | **FIXED** | ≤v0.20.0 | yes (0 errors) |
| uppercase `AND` + `!=` in one expression → CE0117/CE0161 | **FIXED** | ≤v0.20.0 | yes (0 errors) |
| BUG-80 no way to start a workflow instance from a microflow | **RESOLVED (feature shipped)** | ≤v0.20.0 — `call workflow Mod.WF ($Ctx);` microflow activity | yes (0 errors) |
| BUG-81 `create or modify microflow` corrupts existing change activities | **NOT REPRODUCED** (minimal shape) | — likely the v0.19/v0.20 `canon.TransplantIDs` rework | yes (cold load, 0 errors) |
| BUG-76 workflow DECISION storage corruption | **STILL OPEN — CRITICAL, byte-exact original signature** | — | yes: `StorageLoadException … The text 'OutcomeA' is not a valid EnumerationValueIdentifier`, project unloadable |
| BUG-73 `raise error` in main flow → CE0710 | **STILL OPEN** | — | yes (CE0710) |
| BUG-86 nanoflow write barrier: `currentDeviceType()` | **STILL OPEN** (function form; token form now builds clean) | — | yes (CE0117 isolated to `NF_Dev` by drop-and-recheck) |
| BUG-70/95 `show_page` args on a page-level button | **STILL OPEN** | — v0.19's MDL-PAGEARG01 refusal does not cover a CREATE PAGE page-level button; args rebound to `$currentObject` | yes (CE1571 ×2 + CE0117) |
| BUG-84 `SET DataSource = DATABASE` on a DataView wipes it | **STILL OPEN** | — silent "Altered page", DataSource gone, CE7007 downstream | yes (CE7007) |
| BUG-67 snippet primitive param `{ $X: String }` | **STILL OPEN** | — `entity not found: String` | n/a (exec error) |
| BUG-63 write-lint-rules.md fictional API values | **STILL OPEN** | — | n/a (inspection: same `action_type` row, now line 318 of `write-lint-rules/SKILL.md`) |
| BUG-87 DESCRIBE JAVA ACTION drops type-param name | **STILL OPEN** | — | n/a (describe: `entity <>`) |

Not retested this round (no changelog claim, or needs fixtures/Studio Pro this container lacks):
BUG-93/96/92/94/68/77 (page/widget fixtures not built), BUG-14/15/16/17/18/22/23/25/WF01
(pre-v0.17 backlog), the marketplace-install split-model collapse (#879 — needs marketplace
auth; **no fix in either changelog, STOP rule stays**), and the whole `--mcp` family
(BUG-26 residual/32/34/54/72 — needs a live Studio Pro).

## Notes per verdict

### BUG-97 — NOT REPRODUCED on v0.20.0

16 sequential write-class execs (module, entities, association, module role, 2 GRANTs,
create + 2× create-or-replace microflow, alter entity) against one `.mpr` lineage copied
from the pristine baseline; `mxcli docker check` (native mxbuild) at cumulative writes 14,
15 and 16: **0 errors each time**. The original incident (2026-08-14, version unrecorded)
hit ~70 errors at exactly 15 on three orderings. Caveats: the original project was a real
PoC with far more content, and its op mix included `create or replace page`/`alter page`;
this probe's blank app + entity/microflow/grant mix is lighter. Combined with the
v0.19/v0.20 rework of the write choke point (`canon.TransplantIDs`, idempotent writes,
"unit files finalized before the commit rather than after it" — v0.20 changelog), the
operating rule can be relaxed from "hard cap 10–12 writes" to "read back state after
sizeable batches" — keep snapshots until one real project has gone through a long scripted
session on v0.20.

### BUG-85 / BUG-69 / BUG-82 / BUG-66 — the ALTER ENTITY silent-no-op cluster is fixed

- Drop of a rule-bearing attribute now prints `Removed 1 validation rule(s)` and actually
  removes attribute + rule — including the previously-fatal case where it was the entity's
  **only** attribute (which doubled as BUG-69's literal `RefID` repro). mx check: 0 errors.
- `alter entity … modify attribute Email string(200) nullable;` now removes the not-null
  rule (read back via DESCRIBE). Note the **redeclare-without-constraint form does NOT
  remove it** — v0.20 reports `Unchanged attribute` — that is now the documented
  omitted-clause-preserves semantics, not a bug. Update `learned-mdl-preflight.md`
  accordingly: the working removal spelling is `NULLABLE`.
- `alter entity … add attribute CreatedDate: autocreateddate;` adds the system member; a
  non-matching declared name gets warning `MDL022` explaining the rename to the fixed
  system member name instead of a silent no-op.

### BUG-79 — refusal with an explanation (v0.20 changelog item, confirmed verbatim)

`grant Retest.User on System.User (read *)` now refuses up front: "the System module's
domain model is not stored in the project … this is true of every Mendix project", and
names the workarounds (grant on Administration.Account / target a user role). The
underlying inability is Mendix's, not mxcli's — reclassify as BY-DESIGN with good
diagnostics, keep the skill guidance.

### GRANT multi-rule entry (2026-07-22, unnumbered) — both halves resolved

Probe: `read (Name, Email)` then `read (Phone)` for the same role → `Result: read (Name,
Email, Phone)` (additive merge, v0.19 #936). Two GRANTs with different `WHERE` XPath →
**two** access rules, read back via DESCRIBE ENTITY, mx check 0 errors. Symptom 1
(association member dropped) was already fixed as BUG-59 in v0.17.0.

### BUG-87 — still open

`create java action Flow.JA_Test (ContextObject: entity <pEntity> not null) …` describes
back as `ContextObject: entity <> not null` — the type-parameter name is still dropped and
the description does not round-trip.

### BUG-63 — still open

v0.20 reshaped the skills to directory form (`write-lint-rules/SKILL.md`), but the
`action_type` examples row still carries the same values flagged in the 2026-08-20
verification, now at line 318. Keep the STOP note in `existing-app-assurance.md`.

### BUG-76 — still open, and the sharpest STOP rule to keep

`create workflow … decision '1 = 1' outcomes 'OutcomeA' -> { } 'OutcomeB' -> { }; end
workflow;` on a fresh copy: exec reports `Created workflow`, and the next `docker check`
cannot load the project — `The text 'OutcomeA' is not a valid EnumerationValueIdentifier`,
one line per outcome, the original signature byte for byte. None of v0.19's workflow fixes
(#943–#949 are boundary events, names, PersistentId, references) touch this. Every other
Group-D probe on the same copy was masked by this crash until bisected onto its own copy —
which is also the operational lesson: **a workflow DECISION poisons the whole project's
check**, so the STOP rule ("no DECISION activities in CREATE WORKFLOW via mxcli") stays at
full strength. `create workflow … begin end workflow;` and `call workflow` are clean.

### BUG-70/95 — the refusal shipped in v0.19 does not cover this shape

v0.19 added "a SHOW_PAGE widget argument that is not the context object is refused instead
of ignored" (MDL-PAGEARG01). A **page-level** actionbutton (outside any data widget) with
`Action: show_page Detail(RefID: $SomeRef)` — `$SomeRef` a page variable — still execs
silently, and DESCRIBE shows both target-page params bound to `$currentObject`; mxbuild
reports CE1571 for each param plus CE0117 on the page. The guard evidently treats "no
enclosing data widget" like ALTER PAGE's unknown-context case and stands down. Keep the
STOP rule: wire page params through microflow `show page` calls, not widget-level
`show_page` args.

### ALTER PAGE syntax changed shape (toolkit-facing, not a bug)

Old flat `alter page X set P = v on w;` no longer parses — v0.20 wants the braced block
`ALTER PAGE Module.Page { SET P = v ON w; … };`. Also new: DataGrid2 columns store **no
names** — `MDL-WIDGET16` says authored column names are dropped on write and columns are
addressed by *derived* name (attribute name, or caption), e.g. `grid1.Name`. Both need to
land in `learned-mdl-preflight.md` / `mdl-cookbook-microflows.md`-adjacent page guidance,
or every migrated ALTER PAGE script in a consuming project breaks at parse time.
