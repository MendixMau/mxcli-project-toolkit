# Design note: the working flow for an existing, live Mendix app

**Status:** design note, no edits. Nothing in this note is applied. Every file and line cited was
checked against the working tree of this worktree on 2026-09-16 (branch `feat/app-analysis`, HEAD
`f1a407c` plus uncommitted work; the uncommitted change to `bin/gate-check.sh` is the routing map
at line 1492 onward and does not move any line cited here).
**Question this answers:** how should the toolkit work when the starting point is a large Mendix
application that already exists and will keep being developed? What does a person and an agent
actually do, stage by stage, on a 107-module live app, and what does the toolkit check at each point?

**Short answer.** One entry mode, `existing-app-change`, with two phases inside it: a one-time
onboarding that produces the standing artifacts (facts, dossier, layer map, regression harness), and
a repeating per-slice loop that runs Stages P to 6 over one change and its blast radius. The two are
not two modes because they do not differ in the shape of the project, only in time, and the mode
token is the thing that decides shape. The dossier is refreshed at every slice open with the fast
facts run (seconds), never rebuilt; the full run belongs to onboarding and milestones. Stage 3 with
no screens is resolved by making the honest statement (a `Waived artifact` line citing a slice table
row that says zero pages) the passing statement, with a check at slice close that compares the claim
against the refreshed facts. Four increments ship this, in a fixed order, and the first line of the
first increment is a manifest edit, not a parser edit.

Everything below is verdicts with reasons. Section 7 rejects proposals, including some that came
in with the brief. Section 9 lists what the brief said that turned out not to hold. Section 10
lists what was not checked.

---

## 0. Corrections to the brief, up front

Two research passes preceded this note. Most of their findings held. These did not, and the design
below is built on the corrected facts.

| brief said | what the working tree says | consequence |
|---|---|---|
| the manifest has 41 rows | `bin/lib/artifact-manifest.tsv` has 36 data rows: 27 gate/report rows at lines 66 to 92 and 9 opt-in rows at lines 98 to 106 | the landmine is real and smaller; the migration step is 36 rows |
| four readers of entry mode | three executable readers: `bin/gate-check.sh:579` to `:595`, `bin/lib/artifact-check.sh:131` to `:140`, `bin/status.sh:35`. `bin/lib/skill-routing.sh:57` mentions the phrase in a group description and parses nothing | the parser fix is two files plus one regex |
| two incompatible register spellings are both blessed | worse. The table row `\| Entry mode: \| Migration \| CONFIRMED \|` that `evals/scenarios/stage-0-scope/happy-path/expected/project-md.schema.md:18` mandates is readable by **none** of the three readers. `reg_field()` at `gate-check.sh:469` to `:484` strips `[ \t>*_-]` and `*` from a line start but never a `\|`, so the key parses as `\| entry mode` and never equals `entry mode`. Tested in `/tmp` with the exact awk: the table row is skipped, the flat line `Entry mode: requirements-driven` matches. `_art_field()` in `artifact-check.sh` has the identical strip | a Migration project that follows the eval is rescued only by the `intake.md` fallback at `gate-check.sh:580` to `:590`; `artifact-check.sh` has no fallback and treats it as unknown mode (every row owed, which is the loud direction). The new mode must use the flat line, and the eval schema needs correcting |
| `brd-report.sh:180` unknown provenance silently skips every section | `expectation()` at `:267` to `:270` returns `None`, and the verdict loop at `:395` to `:414` then renders an explicit `manual` verdict per section with the reason `provenance undetermined` (line 403). Not silent, but every section of a Path D BRD reads `manual` forever | still needs a `live-model` provenance; the defect is uselessness, not silence |
| `extraction-report.sh` knows only `code-extracted` and `documents` | four values at `:303` to `:315`: `mixed`, `code-extracted`, `documents`, `unknown`. None is live-model. Its vocabulary also differs from `brd-report.sh`'s tuple (`interview`, `greenfield`, no `mixed`) | two provenance vocabularies to extend, not one |
| of the five blast-radius questions the facts answer one fully, one partially, three not at all | true of what `app-facts.sh` **emits**. Not true of what its source holds. The catalog it reads (`<mpr dir>/.mxcli/catalog.db`, written by mxcli, queried read-only at `app-facts.sh:278`) has `associations_data` with `FromEntity` and `ToEntity`, `refs` with named `SourceName` per `SourceType`, `widgets_data` with `EntityRef` per page container, `xpath_expressions_data` with `TargetEntity` per document, and populated `published_rest_operations_data`, `odata_services_data`, `external_entities_data`. Four of five questions are one SQL pass away. Only indexes are absent from the catalog; `mxcli describe entity <QN>` emits `index (...)` clauses | section 4 is about queries, not new instruments, except for indexes |
| the coverage-ledger boundary sentence lives near `coverage-ledger.md:79-81` and the denominator is stated there | the boundary is at `:77` to `:84`. The word denominator does not appear in `:70` to `:90`; the denominator statement for this mode is `existing-app-change.md:156` and the fallback table at `coverage-ledger.md:46` to `:51` | citation fix only |
| intake Q9's wording implies unattended can self-consent | `bin/lib/intake-template.sh:97` to `:101`: unattended applies recommended options "as ASSUMED and logged for reconciliation". `bin/open-questions.sh:285` to `:290` normalises ASSUMED without `consentBy` and `consentAt` to UNRAISED. The two texts do conflict, and the collector is right | section 7, rejected: no self-consent |

Two things the brief did not say that matter to the design:

* `bin/gate-check.sh` has no Stage 5 check. `STAGE_NAMES` at `:1256` lists 5, the dispatch at
  `:2417` to `:2427` sends it to `check_stage_manual()` (`:1130` to `:1132`), which prints MANUAL
  unconditionally. The per-module regression re-run this mode depends on has no mechanical hook at
  Stage 5 today.
* The `Waived artifact <id>: <reason>` register line that `skills/small-project-tier.md:73` to `:79`
  tells people to write is read by `artifact-check.sh` (`_art_waiver`, `:104` to `:112`) and by
  nothing in `gate-check.sh`'s stage checks. `check_stage_3()` at `:1006` to `:1047` tests file
  existence directly. So the small tier's waiver of `module-design` changes the artifact report and
  leaves the gate untouched; the two surfaces already disagree in one mode. The Stage 3 fix in
  section 3 closes that gap for every mode, not only this one.

---

## 1. The working flow, stage by stage

Read this section as Monday morning. The app in the example is invented: 107 modules, 73 own, 799
entities, 448 pages, 2,686 microflows, 40 scheduled events of which 16 are enabled, one strongly
connected component of 52 modules. Those are the probe app's counts and nothing else of it appears
here. The change request in the example is "the nightly reconciliation job times out", and the slice
turns out to be one entity, three microflows, zero pages, on an enabled daily event, outside the big
tangle. That is the shape the dry run had.

### 1.1 Two phases, one project

The project directory is the app's own repository, where `project-bin/app-facts.sh` is installed as
`bin/app-facts.sh` and where `analysis/`, `architecture/` and `PROJECT.md` live. There is one
`PROJECT.md` for the life of the app. There is one facts directory, one dossier, one layer map, one
journeys directory. Those are the **standing artifacts**. Everything else is a **slice artifact**,
produced by one pass through Stages P to 6 and archived when the slice closes.

| phase | runs | produces | how often |
|---|---|---|---|
| onboarding | once, before the first slice, and again only as a milestone audit | `analysis/app-facts/*` from the full run, `architecture/app-dossier.md` with dispositions, `analysis/app-layer-map.html`, the e2e harness stood up per `e2e-harness-base.md` with zero or few journeys, `PROJECT.md` with the mode line and the app-level decisions | once, then at milestones |
| slice | Stages P (light), 0, 1, 2, 3, 4, 5, 6 | `triage.md` with slice table and blast radius, a Path D KB, one BRD per changed capability with as-is and to-be, a build plan, module briefs, a coverage ledger over the slice, journeys added to the standing net, a test report that is the baseline re-run | every change request |

Onboarding is not a stage and it is not "slice zero". It is Stage 0's prerequisite made explicit:
the facts and the dossier are the Stage 0 denominator for every slice that follows. Section 2 says
why this is one mode and not two.

### 1.2 The register lines this mode writes

Machine-readable lines are flat `Label: value` lines under `## Toolkit position` in `PROJECT.md`,
which is where `skills/small-project-tier.md:73` already puts `Size tier:` and `Waived artifact`
lines and which all three readers can parse. The human copy in the Decisions table is welcome and is
not read by anything.

```
Entry mode: existing-app-change
Facts: analysis/app-facts/manifest.json <mpr_sha256_16> <generated>
Slice: S03 nightly-reconciliation-timeout (opened 2026-09-16)
Waived stage 7: no legacy system to cut over from; the app is live (existing-app-change.md stage table)
```

The token is `existing-app-change`, space-free because manifest column 6 is comma-separated with no
quoting, and it is the spelling `bin/lib/skill-routing.tsv:112` already uses. The human label
`Change an existing app` from `existing-app-change.md:129` may stay in prose and in the Decisions
table. Both parsers gain one case arm, `*existing-app*`, and both emit the same token; the existing
split between `requirements-driven` and `requirements` is left alone (section 7).

### 1.3 Stage P, kickoff

**What runs.** `bin/init-project.sh` if the toolkit is not yet installed in the app; otherwise
nothing to scaffold. The ten intake questions in `bin/lib/intake-template.sh` are answered, most of
them from the model and the register rather than by asking: Q1 entry mode is `existing-app-change`
with the evidence that the corpus is one `.mpr` (`bin/lib/source-formats.tsv:64`, kind `code`), Q4
scope boundary is "a slice, defined at Stage 0", Q10 "already done outside the toolkit" names the
onboarding artifacts and their facts sha. Q9 is answered `attended` unless the user explicitly says
otherwise; unattended still cannot consent to its own assumptions (section 7).

**Check.** `check_stage_P()` (`gate-check.sh:678` to `:761`) passes when every `## ` section of
`intake.md` carries an answer marker. It does not validate the mode value. That stays as it is: the
mode's validity is checked where the mode is consumed. What changes is that an unrecognised
non-empty mode token becomes a FAULT in `artifact-check.sh` rather than a wall of N/A (section 6,
step 1), so a misspelt token is loud at the first artifact report.

**Artifact.** `intake.md`, `PROJECT.md` with the four lines above. **Signs.** Nobody; Stage P has
no hand.

**On the second and later slices** Stage P is a `Slice:` line and a re-read of `intake.md` for
anything that changed (a new SME, a new constraint). That is the "light" in the skill's table.

### 1.4 Stage 0, triage and scope, hand

This is the stage that carries the mode. It answers two questions, which slice and what it touches,
and it answers them from the facts, not by hand.

**What runs, in order.**

1. **Refresh trigger.** Compare `manifest.json`'s `mpr_sha256_16` with the sha of the current
   `.mpr`. On a live app they differ almost every time. If they differ, run `bin/app-facts.sh
   --skip-loops`: steps 1 and 2 only, about 18 s on the probe app (8 s catalog and graph report,
   10 s inventory and dependencies, from `manifest.json` `timings_s`). Update the `Facts:` line.
   Do not run the loop sweep here; section 5 says why.
2. **Slice facts.** From the entities and microflows the change request names, run the slice-scoped
   query set of section 4 over the same catalog: associations at both ends, named referrers by
   source type, pages bound through widgets and XPath, published and consumed services, and
   `describe entity` for the indexes of the slice entities and their association neighbours. On a
   slice of one entity that is a handful of describes, seconds.
3. **Layer map.** Read `analysis/app-layer-map.html` or its `--json` for the modules the slice
   touches: the modules above them in the computed order, and the back edges into them. This is
   the honest radius for a module inside the tangle, per `docs/architecture-views-design-note.md`
   section 3.
4. **Write `triage.md`.** Extraction Approach: tick **Reuse existing pipeline**, naming mxcli's
   catalog plus `describe` as the extractor (Path D) and `build_mode = full` from `manifest.json`
   `catalog` as the layout check. This is not a third row and it is not a direct read; the
   catalog is an extractor that either answers or errors, which is the whole argument of
   `existing-app-change.md:90` to `:94`. This dissolves the contradiction between
   `existing-app-change.md:130` ("extraction rows are N/A") and `bin/lib/triage-template.sh:83`
   to `:88` (no third option, ever). The skill sentence is the one to correct.
   Business Capability Map from `inventory.json` modules plus the change request. Coverage Matrix:
   one row per document class in the slice (entities, microflows, pages, scheduled events), each
   with the count the catalog returned. Then the two new sections, below.
5. **CAC-1**, `skills/checkpoints/checkpoint-scope.md`, opens with the brainstorm as always. The
   scope-in question here is "is this the slice, and is this its radius". The person confirms the
   blast radius line by line, and confirms the regression-net size that follows from it.

**The two new sections of `triage.md`.** These are the load-bearing artifact of the mode and the
evidence every later N/A cites.

`## Slice`, a fixed table with fixed row labels, one count per row, and the source of the count:

| row | count | source |
|---|---|---|
| Modules touched | 1 | change request plus `dependencies.json` edges |
| Entities changed | 1 | `SHOW ENTITIES`, `describe entity` |
| Entities added | 0 | decision |
| Associations changed or added | 0 | `associations_data` query, decision |
| Microflows changed | 3 | `refs` query, `describe` |
| Pages changed or added | 0 | `widgets_data` and `xpath_expressions_data` query over the slice entities: 0 bindings |
| Scheduled events on the path | 1 enabled | `inventory.json` `scheduled_events` joined to `loops.json` reachability |
| Published or consumed services touched | 0 | `published_rest_operations_data`, `odata_services_data`, `external_entities_data` query |

`## Blast radius`, the five questions of `existing-app-change.md:108` to `:117` answered from the
slice facts, each with a count and the query, followed by one line the gate later reads back:
`Regression net for this slice: N journeys over M modules`. The module list comes from the layer
map's "above and back edges" reading, not from "the tangle".

**Check.** `check_stage_0()` (`:763` to `:798`) requires a signed `## Sign-off`. Two additions,
both evidence reads and neither mode-aware: (a) the sha in the `Facts:` line must equal
`manifest.json` `mpr_sha256_16`, else FAIL "blast radius was computed from facts of a different
model"; (b) the `## Slice` table must be present with all eight labels, else FAIL. The source
sufficiency advisory (`:2186` to `:2240`, advisory at Stage 0 per `:2802`) runs over the
`analysis/app-facts/mdl/` describe exports and will band the slice as SKETCH; record the band in
`triage.md` with the reason that the instrument grades prose corpora and this corpus is a model,
and move on. `.mdl` gets a row in `source-formats.tsv` so the inventory classes it as `code`
rather than `unknown` (section 6).

**N/A at this stage, and on what evidence.** `assessment.md`'s six areas: N/A because the
dossier's sections 2 to 7 are that assessment for this app, cited by path and facts sha. The
extraction reuse-or-build call is **not** N/A; it is "reuse, mxcli". Small tier does not apply
(it is about an app's size, and the app is 107 modules; the slice's size is what the slice table
is for).

**Artifact.** `triage.md` signed, `analysis/slices/<id>/blast-radius.json` from the slice query,
`Facts:` line updated. **Signs.** The person, at CAC-1, in `## Sign-off` and as a Stage 0
`CONFIRMED` row.

### 1.5 Stage 1, analysis, Path D

**What runs.** `mxcli describe` for every document the slice table counted, plus the association
neighbours the blast radius named, written under `analysis/app-facts/mdl/` (the same place
`app-facts.sh` step 3 writes, so a later full run overwrites with fresher copies, which is what you
want). These files are the **source corpus** of this slice, and that is what makes the source
ledger work without adaptation: the dry run inventoried 3 files, extracted 3, name-verified 3, and
refused a KB that cited the facts directory in prose without naming the file. That is the one
instrument in the run that needed nothing, and this design keeps it that way by giving it real
files to ledger. The source root for `bin/source-sufficiency.sh init` and `bin/source-ledger.sh`
is `analysis/app-facts/mdl/` restricted to the slice's documents, never the app repository (which
would inventory theme files, Java and build output by the thousand).

The KB (`kb-generation.md`) is written from those describes and from the facts, scoped to the slice
plus its radius, and records the slice-versus-app counts: `manifest.json` totals next to the slice
table. Path A is declared not applicable with the attribution "no non-Mendix source exists; the
model is queried directly" (that is a statement about the corpus). Path C matters more here than in
any other mode, because the model says what the app does and nobody wrote down why, so the SME
questions from `analysis/sme-questions.md` are raised at CAC-1b, not parked.

For the slice's loop-bearing microflows, run the parser on the describes you just made:
`bin/app-facts.sh --parse-only analysis/app-facts/mdl` produces the `loops.json` rows for exactly
those documents. No full sweep.

**Check.** `check_stage_1()` (`:800` to `:849`) wants `extraction-report.html` non-empty and
`share/KB.md` non-empty if present. `bin/extraction-report.sh` gains a `live-model` provenance,
detected by a marker the KB writes (`Provenance: live-model` plus the facts sha), whose expected
section set is: canonical KB present, `KB_*.md` not expected, discovery manifest not expected. Until
that lands the report says `documents` and carries a permanent FAULT for the missing `KB_*.md`, and
the gate does not read that FAULT, so the surface and the gate disagree. Same value added to
`brd-report.sh`'s `PROVENANCES` with an `EXPECT` entry, so the BRD surface can render verdicts
instead of `manual` everywhere. The source ledger blocks Stages 1 and 2 (`:2810` to `:2830`) and
should: every describe in the slice's corpus must be named by the KB.

**N/A.** Path A, on the evidence above. The extraction report's document-KB rows, on the
`live-model` provenance. **Artifact.** `<kb>/share/KB.md`, `extraction-report.html`,
`source-ledger.html`. **Signs.** Nobody; CAC-1b is a checkpoint you run, and its scope-out diff is
the slice-versus-app statement.

### 1.6 Stage 2, requirements, slice only

**What runs.** One BRD per capability being changed. Each carries **as-is** and **to-be**. The
as-is comes from the model (the describes, the facts) and is a description. The to-be comes from a
person's decision at CAC-2 or CAC-3 and is the requirement. This is the coverage-ledger boundary
(`coverage-ledger.md:77` to `:84`) applied to this mode, and the sentence that keeps it from being
crossed is:

> The live model is the source of the as-is half only. The to-be half and every ledger leaf come
> from a person's decision. A BRD leaf whose to-be reads the same as its as-is is a description,
> not a requirement, and does not enter the denominator.

That sentence belongs in `existing-app-change.md`'s Coverage section and in `coverage-ledger.md`
next to the boundary. The BRD also carries one line saying how many capabilities of the app were
not BRD'd and why ("the other 106 modules are out of this slice"). `bin/brd-report.sh` renders with
the `live-model` expectations. CAC-2 groups, CAC-3 surfaces the hidden rules, which in this mode are
the ones the model encodes and nobody remembers deciding.

**Check.** `check_stage_2()` (`:851` to `:893`): BRDs exist, `validation-report.md` stop
condition starts with `clean`. Unchanged. **N/A.** Nothing. **Artifact.** `F{NNN}.brd.json` for the
slice, `brd-report.html`, validation report. **Signs.** Nobody at the gate; CAC-2 and CAC-3 are
interviews.

### 1.7 Stage 3, architecture and design, hand

This is the stage the dry run passed dishonestly, and section 3 has the full mechanism. The flow
version:

**Two forms, decided by the slice table.** Collapsed when Modules touched is 1, Entities added is
0, Associations changed or added is 0 and Services touched is 0. Full otherwise.

**Collapsed form.** One question, "which existing module owns this, and does that still hold",
answered with `skills/layering-review.md` over the layer map, and recorded as one Decisions row:
`Stage 3 | owner module holds; slice introduces 0 back edges (layer map, facts <sha>) | CONFIRMED`.
Wireframes only for the pages the slice table counts; with 0 pages, none, and the register says so
with a `Waived artifact wireframes: slice changes 0 pages (triage.md Slice table, facts <sha>)`
line. No design system, no blueprint, no fit-gap, in this form or the full one, for reasons in
section 3.

**Full form.** Plus `module-design.html` when a module is added or a boundary crossed (a decision,
signed), `fit-gap.md` when a service or a marketplace component is added, `workflow-count.md`
when a workflow is touched (the `workflow-count` obligation at `obligations.tsv:73` applies from
Stage 3 and stays), `wireframes/*.html` for every page changed or added, one per page. CAC-4 runs
scoped to what changes; with 0 pages it is the boundary conversation and nothing about branding.

**Check.** `check_stage_3()` reads `Waived artifact` lines for its existence checks (section 3),
consults the manifest for whether the mode owes `blueprint-html` at all, and still requires the
Stage 3 `CONFIRMED` row. **Signs.** The person, as the Stage 3 row.

### 1.8 Stage 4, build plan, hand

**What runs.** `brd-to-build-plan.md` over the slice's BRDs. The ordering constraint of this mode
is written into the plan's first line: nothing that exists is stubbed; an entity with data in it is
altered in place, and the plan's section 9 regression ledger names the journeys from the blast
radius line that must be green before the first exec. The coverage ledger is the single-file form
over the slice's leaves, and its header carries the denominator sentence from
`existing-app-change.md:159` to `:161`. CAC-5 orders the build.

**Check.** `check_stage_4()` (`:1049` to `:1062`): `build-plan.md` plus a Stage 4 `CONFIRMED`
row. Unchanged. **N/A.** `build-plan.html`: waived by register line as the small tier does, with
the reason that the plan is read from the markdown; that is a shape statement and it is written
down. **Signs.** The person.

### 1.9 Stage 5, build

**What runs.** `iterative-build-loop.md`, the STOP table, module briefs, module review with BUILD,
GATE, PROVE, LOOK, CONFIRM. Plus the rule that is specific to this mode
(`existing-app-change.md:140` to `:151`): every module gate re-runs the baseline journeys named
in the blast radius line. The journeys for the slice's radius are written **before** the first
exec, not after; that is Ground Rule 1 made concrete, and it is the step that grows the standing
regression net one slice at a time. On the example slice that is journeys over the one module's
actions that reach the changed flows, plus a DB assertion on the entity the nightly job writes.

**Check.** There is none; Stage 5 is MANUAL by construction (`:1130`). The `ui-reviews`,
`journeys`, `page-scope` artifacts are owed per the manifest; `ui-reviews` is waived on the
0-pages evidence, the same line as wireframes. The honest gap is that the per-gate baseline re-run
has no mark to leave. Section 8 lists it as open; the cheapest candidate is an obligation row
`regression-rerun`, scope `module`, discharged by a dated file that names the module and the
journey count, in the shape of the `look` and `sweep` rows already in `obligations.tsv`.

### 1.10 Stage 6, test and slice close

**What runs.** The full journey suite, which is now the standing net plus this slice's additions,
green; `test-report.html`; `finding-disposition.md` over the report; CAC-6 asks cutover readiness,
which in this mode reads "is this slice ready to merge into the live app". Then the slice close:

1. `bin/app-facts.sh --skip-loops` again. Update the `Facts:` line.
2. **The honesty check.** For each module in the slice table's Modules touched, compare the
   per-module page count, entity count and microflow count in the new `inventory.json` against the
   Stage 0 facts (the `Facts:` sha the triage cites; the facts files are committed, so the Stage 0
   copy is in git). A slice that claimed Pages changed or added is 0 and whose touched modules
   gained a page has made a false Stage 3 claim; FAIL, naming the module and the count. Section 3
   says what this check does and does not catch.
3. Archive the slice artifacts under `slices/<id>/` (triage, BRDs, build plan, briefs, ledger,
   test report) and add the slice's dispositions to the dossier's section 8 if any dossier finding
   was touched.

**Check.** `check_stage_6()` (`:1064` to `:1092`) wants a test surface plus `ui-review-*.html`.
The review report is waived on the 0-pages line; the test surface is never waived, because the
regression re-run is the one thing this mode cannot do without. The honesty check is new and is
the second gate read of `analysis/app-facts/` after the Stage 0 sha compare. **Signs.** The
person, at CAC-6, `CONFIRMED` only.

### 1.11 Stage 7, cutover

Not run. `Waived stage 7` with the reason, as a register line and as the Decisions row the dry run
already wrote. `stage_waiver()` gains the `existing-app-change` arm for stage 7 with `mode` scope,
identical to the `requirements-driven` arm at `gate-check.sh:630` to `:633`: it excuses an empty
stage only, and if someone writes a cutover row it is checked. This is the one place the mode label
decides a stage, and it follows the precedent exactly rather than inventing a stricter rule for one
mode.

### 1.12 Milestone audit

Not a stage. At a milestone, or before a review, or when the team decides: `bin/app-facts.sh`
in full (loops included, minutes), dossier refreshed section by section with dispositions
reconciled per `skills/app-analysis.md` step 4, layer map re-rendered, the two hand checks done.
The delta that matters is `git diff` over the committed facts between the last two full runs: new
back edges, new tangle members, new loop findings on the enabled path. A rendered delta is
deferred (section 7); the diff is enough for the flow to work.

---

## 2. The two-speed question

**Verdict: one mode, two phases, distinguished by register lines and by which artifacts they touch,
not by a second token.**

Three reasons, in order of weight.

**The token decides shape, and the phases have the same shape.** The only executable consequences
of the mode token are `stage_waiver()`'s three-way case and manifest column 6. Both answer "what
does a project of this shape owe". Onboarding and the per-slice loop are the same project at
different times; onboarding owes nothing the slice loop does not also owe, it just produces the
standing half first. A second token would need its own column 6 entries on 36 rows and its own
waiver arm, and the two would have to be kept consistent by hand forever. That doubles the landmine
surface for no decision the gate would make differently.

**The dossier is not rebuilt per slice, and that is the whole point of having it.** The facts are
refreshed at slice open with the fast run because the model has moved (the sha trigger), and the
refresh is seconds. The dossier's sections 2 to 7 are regenerated from the facts at milestones, and
its section 8 dispositions are never regenerated. A slice that finds a new dependency or a new loop
finding adds a disposition line; it does not rewrite the document. If onboarding were a mode, the
dossier would look like that mode's output and the slice loop would look like a consumer of a
finished thing, and the refresh discipline in `skills/app-analysis.md:289` to `:296` would have no
home. The design note before this one already made the dossier a standing document; this one
follows.

**The refresh trigger and the delta already exist in the cheapest possible form.** The trigger is
`manifest.json` `mpr_sha256_16` against the current `.mpr`, which is a one-line comparison and is
the same fact the Stage 0 check reads. The delta is `git diff` over four committed JSON files
between two runs, which the skill already tells you to commit. There is no delta today between
refreshes (checked: no `previous`, `delta` or history logic in `app-facts.sh`, `app-report.sh` or
`app-layer-map.sh`), and the flow does not need a rendered one to work. What it needs is the two
targeted comparisons in section 1: cited sha equals current sha at Stage 0, and touched-module
counts at slice close.

What this costs. The register accumulates a `Slice:` line per change and the Decisions table
accumulates rows tagged by slice. On the tenth slice `PROJECT.md` is long. That is what the
`slices/<id>/` archive is for, and the register is still the one document that says what was
decided about this app. A per-slice project directory, which is what the dry run did in `/tmp`, is
rejected in section 7 because it breaks the accretion of the regression net and the dispositions.

Where I am least sure. Whether the archive step at slice close is enough, or whether two slices
will one day run in parallel on the same app and need the singular layout (`triage.md`,
`build-plan.md`) namespaced. Section 8, first item.

---

## 3. Stage 3 with no screens

**The finding.** `check_stage_3()` tests for `design/design-system.html`, `design/wireframes/*.html`,
`architecture/fit-gap.md` and `architecture/blueprint.html` before it looks at anything else. A
slice with zero pages has nothing honest to put in three of those. The agent passed it with a
155-byte page saying "No UI in this slice" and a 72-byte wireframe. The gate reported PASS on a hand
stage and the board could not tell. `tests/wave2/test-closeout.sh:102` to `:104` sets up a passing
Stage 3 with one-line `<html>` files, so the stub is the suite's own habit. The defect is not the
agent; it is that the gate has no honest N/A path for an artifact that can legitimately be absent.

**The principle.** Every mandatory artifact needs an evidence-based N/A path in every mode where it
can legitimately be absent, and the gate must read the evidence, not the file. Where the honest
statement and the passing statement are the same statement, nobody writes a stub.

**The mechanism, three parts.**

**Part one: the claim.** The `## Slice` table in `triage.md` (section 1.4) states the counts with
their source. The person confirms them at CAC-1. When Pages changed or added is 0, the agent writes:

```
Waived artifact wireframes: slice changes 0 pages (triage.md Slice table, facts a1b2c3d4e5f60718)
Waived artifact ui-reviews: slice changes 0 pages (same evidence)
```

That is the vocabulary `small-project-tier.md` already uses and `artifact-check.sh` already parses.
The reason is not "existing-app mode"; it is a count with a source and a sha. That satisfies "N/A
is earned on evidence, never on the mode label" literally.

**Part two: the gate reads the claim.** `check_stage_3()` consults `_art_waiver` (or a copy of its
three-line lookup) before each of its existence tests. A waived artifact reports `WAIVED: <reason>`
in the stage line, never PENDING and never PASS-by-stub. The `CONFIRMED` row is still required; a
waiver never excuses the hand. This change applies to every mode, and it fixes the existing
disagreement where the small tier's `module-design` waiver is honoured by the artifact report and
ignored by the gate. For `blueprint-html`, the gate additionally asks the manifest whether the
current mode owes it at all (one helper that reads column 6), because a blueprint is never produced
in this mode, section 7 says why, and a waiver line for an artifact the mode cannot owe is noise.

**Part three: the claim is checked against the world.** At slice close (section 1.10) the fast facts
run gives per-module page counts. A touched module that gained a page while the register says 0
pages is a FAIL that names the module. The same comparison covers Entities added and, coarsely,
Microflows changed.

**What part three does not catch, said plainly.** A page count only sees pages added or removed.
A slice that edits an existing page's widgets without adding a page passes the count and may have
changed UI. The precise instrument is a model diff of page documents between two shas, which does
not exist; `mxcli` has no diff command (checked in `mxcli --help` and `mxcli show --help`, no
project opened). Until one exists, the coarse check is paired with the journeys: an existing page
whose behaviour changed is caught by the regression net if a journey walks it, and the blast radius
step 3 (pages bound to the slice entities, now answerable from `widgets_data`) is what tells you
which journeys those are. So the honest statement about Stage 3 with zero pages is "no page added,
and the pages bound to the changed entities are these N, walked by these journeys", and that is
what the waiver line should say when N is not zero.

**Why not simply make Stage 3 mode-aware.** A `case "$ENTRY_MODE"` inside `check_stage_3()` that
skips the design checks for `existing-app-change` would pass a slice that adds three pages with no
wireframes, on the mode label alone. That is exactly the rule the runbook forbids, and it is the
proposal that came in with the brief as "the per-stage inversion table". The inversion table in
`existing-app-change.md:127` to `:137` is right as prose and wrong as a mechanism; the mechanism is
evidence lines the gate reads, and the prose table stays as the explanation of which evidence to
expect.

**The design system.** Not owed in this mode, in either form. The slice's pages, if any, use the
app's theme, and whether they do is a Stage 6 LOOK question, not a Stage 3 artifact. A
`design-system.html` showcase of an existing theme is Track A2 of `existing-app-assurance.md`, an
onboarding-time audit if the team wants one, never a slice gate. This is a shape statement and it
lives in manifest column 6 (row `design-system` and `ds-css` do not carry the token), which is where
shape statements belong; the `design-reaches-app` obligation, which checks the design system reaches
the built app, follows the artifact and is not owed.

---

## 4. What the dossier must gain

The five blast-radius questions, what answers them today, and what should.

| question (`existing-app-change.md:108` to `:117`) | today | source that holds it | instrument | cost |
|---|---|---|---|---|
| 1. associations from the slice entities, both ends named | not collected; `dependencies.json` has `kinds` per module pair only | catalog `associations_data`: `FromEntity`, `ToEntity`, `AssociationType`, `Owner`, 621 rows on the probe | `app-facts.sh` step 2, new section `associations`, app-wide | one SELECT, well under a second |
| 2. microflows that read or write those entities, by name | degree only (`god_nodes`) | catalog `refs`: `SourceType`, `SourceName`, `TargetName`, `RefKind`; 13,868 microflow-sourced rows on the probe | slice-scoped query, `blast-radius.json` | one SELECT with a name list |
| 3. pages bound to them | not collected | catalog `widgets_data` (`ContainerQualifiedName`, `EntityRef`, 614 non-empty on the probe), `refs` with `RefKind = datasource`, `xpath_expressions_data` (`DocumentQualifiedName`, `TargetEntity`) | slice-scoped query, same file | three SELECTs |
| 4. module dependencies and the tangle | collected; the layer map turns it into a list | `dependencies.json`, `app-layer-map.json` | exists | none |
| 5. published and consumed services on the slice entities | not collected | catalog `published_rest_services_data` (21), `published_rest_operations_data` (93, with `Microflow`), `odata_services_data`, `odata_clients_data`, `external_entities_data` (7), `business_event_services_data` (8); `rest_clients_data` exists and is empty on the probe | `app-facts.sh` step 2, new section `services`, app-wide; the slice query joins it | one SELECT per table |
| the index fact the example fix rests on | not collected; no index table anywhere in the catalog (checked `sqlite_master` for `Index` outside `idx_*`) | `mxcli describe entity <QN>` MDL output, `index (...)` clauses; verified on one probe entity, sub-second warm | slice-scoped: describe the slice entities and their association neighbours; parse the index clauses into `blast-radius.json` | seconds per slice; app-wide would be 799 describes, about three minutes, and is rejected below |

**Split, as asked.**

*`project-bin/app-facts.sh` collects, app-wide, cheap:* `associations` and `services` as two new
sections of `dependencies.json` (or a fifth file; the manifest gains a status for each so a version
that cannot collect them says `fault`). Both are small and both serve the dossier as well as the
slice: the entity-ownership view the previous design note wants needs `associations`, and section 5
of the dossier (security posture, FAULT today) will need `services` eventually. `entity_writers`
from that note's section 9b belongs in the same pass.

*A slice-scoped query needs a name list and belongs in a slice instrument:* referrers by name, page
bindings, and indexes. Call it `app-facts.sh --slice <entity>...` or a sibling `slice-facts.sh`;
the choice is cosmetic, the shape is not: it takes named targets, reads the same catalog read-only,
runs `describe entity` for the targets and their association neighbours, and writes
`analysis/slices/<id>/blast-radius.json` with the query text beside every list. App-wide dumps of
`refs` and `widgets_data` are rejected: 18,690 and 6,725 rows nobody reads, refreshed every slice.

*A human decides:* what "touched" means (the change request names an entity; the person confirms
whether the neighbour entity across the association is in or out), and whether a published
operation's consumer, who is not in the `.mpr`, has to be told. Nothing in the facts needs a human
to collect; everything in the radius needs one to confirm, at CAC-1.

**Structural cause, and the fix.** `inventory.json` carries names for modules and scheduled events
and counts for everything else. That is correct for a dossier that a person reads; it is why the
slice needs its own file rather than a fatter inventory. Do not add entity, page and microflow names
to `inventory.json`: 799 plus 448 plus 2,686 names in a file the renderer folds into tables helps
nobody, and the catalog already has them.

**`--skip-loops` has a latent bug worth knowing before this flow leans on it.** With the flag,
`loops.json` is not written at all and `N_CAND` is still counted (`app-facts.sh:504` to `:505`),
so the manifest reports candidates with `described: 0` and `app-report.sh`'s `load("loops.json")`
returns `None`. On a project that has a `loops.json` from an earlier full run the fast run should
leave it in place and the manifest should say `loops: skipped, previous run retained <date>`; today
the fast run's manifest says skipped and the old file sits beside it unmentioned. One-line fix,
listed in section 6.

---

## 5. The fast/full decision

| when | run | why | reads the result |
|---|---|---|---|
| onboarding | full, `bin/app-facts.sh` with loops, then dossier, layer map, two hand checks | the loop section is the dossier's section 4 and the scheduled-reach weight in severity depends on it; you do this once | dossier, `app-report.sh`, `app-layer-map.sh` |
| Stage 0, every slice | fast, `--skip-loops`, triggered by sha mismatch (in practice always), plus the slice-scoped query | the slice needs current modules, edges and counts; it does not need every loop body in the app re-described; the slice's own loop bodies are described at Stage 1 anyway | `triage.md` Slice table, blast radius, `Facts:` line, Stage 0 sha check |
| Stage 1 | none app-wide; `describe` per slice document; `--parse-only` over those | the describes are the Path D corpus and the ledger's rows; parsing them gives the slice's loop rows for free | KB, source ledger, slice `loops.json` rows |
| Stage 6, slice close | fast again | the honesty check needs post-build counts for the touched modules; a full run here would cost minutes per slice for facts nothing at this point reads | close check, `Facts:` line |
| milestone or audit | full | the loop section goes stale as slices change flows; dispositions need reconciling; the layer map may have moved | dossier refresh, `git diff` of the facts |

Two rules that make the table safe. First, the fast run rewrites the shared catalog exactly as the
full run does (`graph-report` at `app-facts.sh:233` forces the rebuild), so the skill's "run it when
nobody is mid-edit" applies to the fast run too. On a live team that is a real constraint and it is
listed open in section 8. Second, a full run's manifest supersedes a fast run's and never the other
way around: the fast run must not overwrite `loops.json` or mark the loop section anything but
`skipped, previous retained`.

---

## 6. Migration order

**Hard precondition, stated once and enforced by a test: manifest first, parsers second.** If either
parser learns the token `existing-app-change` before `bin/lib/artifact-manifest.tsv` column 6 carries
it, `artifact-check.sh:298` to `:305` prints `N/A ... does not owe it` for all 36 rows and the
aggregate stays PASS. Traced, not assumed. The ordering rule is written nowhere in the repo today;
it goes into the manifest's header comment and into `CHANGELOG.md`'s line for step 1.

Four increments. Each ships with its fixture, in the shape `tests/run-tests.sh` demands: a guard is
not fixed until a fixture proves it fails.

### Increment 1: the token exists and cannot misfire

1. **Defuse the landmine permanently.** In `artifact-check.sh`, before the per-row loop, collect the
   vocabulary of column 6 across all rows. If `mode` is non-empty and not in that vocabulary, set
   `MXTK_ART_STATUS=FAULT` and print one line: `entry mode <x> is not known to the manifest; no
   artifact can be owed or excused`. Test: a fixture register with `Entry mode: brownfield`
   yields FAULT, not 36 N/A lines. This step touches no manifest row and no parser, so it can land
   alone.
2. **Manifest rows gain the token.** Add `existing-app-change` to column 6 of: `intake`,
   `register`, `triage`, `extraction-report`, `source-ledger`, `brds`, `brd-validation`,
   `brd-surface`, `module-design`, `fit-gap`, `wireframes`, `module-definition`, `build-plan`,
   `build-plan-html`, `module-brief`, `coverage-ledger`, `ui-reviews`, `journeys`, `page-scope`,
   `improvement-register`, `improvement-register-html`, `report-json`, `verification-html`, and all
   nine opt-in rows. Not `blueprint-md`, `blueprint-html`, `design-system`, `ds-css`. Test: a
   static test over the TSV asserting every column 6 token is in the vocabulary set and every mode
   in the set appears on the three Stage P and 0 rows. This is the column 6 test that does not
   exist today.
3. **Parsers.** `gate-check.sh:591` to `:595` and `artifact-check.sh:134` to `:139` each gain
   `*existing-app*)` emitting `existing-app-change`. `stage_waiver()` gains the stage 7 arm with
   `mode` scope. `bin/status.sh:35` regex becomes `^Entry mode: *[A-Za-z-]+` (it still reads only
   the flat line, which is now the documented machine spelling). Tests: a fixture with the flat
   line gets Stage 7 WAIVED and every other stage unchanged; `artifact-check.sh` on the same fixture
   owes exactly the step 2 set; the `test-closeout.sh` fixture is unchanged.
4. **Spelling.** `evals/scenarios/stage-0-scope/happy-path/expected/project-md.schema.md:18`
   changes from the table row to the flat line, with a note that the Decisions row is for people.
   `existing-app-change.md:129` names the token.

### Increment 2: Stage 3 and 6 pass honestly

5. `check_stage_3()` reads `Waived artifact` lines for its four existence checks and reports
   `WAIVED: <reason>`; consults column 6 for `blueprint-html` before requiring it. `check_stage_6()`
   does the same for `ui-reviews`. Tests: the dry-run shape (no `design/`, waiver lines citing
   0 pages, a Stage 3 CONFIRMED row) passes with WAIVED in the line; the same fixture without the
   CONFIRMED row fails; a migration fixture with the `test-closeout.sh` stubs behaves as before.
6. `bin/lib/triage-template.sh` gains `## Slice` (eight fixed labels) and `## Blast radius`.
   Other modes fill them with one line each stating why they are empty. `check_stage_0()` gains
   the `Facts:` sha compare and the eight-label presence check, both skipped with a printed note
   when no `Facts:` line exists (a migration project has none). Test: fixture with a stale sha
   fails naming both shas.
7. The slice-close check: a small script, `bin/lib/slice-close-check.sh`, that takes the Stage 0
   facts sha (from git, by path) and the current `inventory.json`, reads Modules touched from the
   Slice table, and fails on a page or entity count change in a touched module when the register
   waived wireframes on 0 pages. Wired into Stage 6 the way `report-disposition-check` is at
   `gate-check.sh:2838`. Test: fixture with a waiver on 0 pages and a touched module whose page
   count went from 12 to 13 fails naming the module.

### Increment 3: the facts serve Stage 0

8. `app-facts.sh`: `associations` and `services` sections; `--skip-loops` retains a previous
   `loops.json` and says so in the manifest; `--slice <entity>...` (or `slice-facts.sh`) writing
   `blast-radius.json` including indexes from `describe entity`. `bin/lib/source-formats.tsv`
   gains a `mdl` row, kind `code`. Tests: the existing `tests/wave2/test-app-report.sh` fixture
   gains the two sections; a golden `blast-radius.json` from an invented fixture catalog, not from
   the probe app.
9. `extraction-report.sh` and `brd-report.sh` gain `live-model`. Test: a KB with the marker
   renders no `KB_*.md` fault; a BRD with the provenance renders verdicts, not `manual`.

### Increment 4: the words agree

10. `conversion-runbook.md` classification rules get a rule 0 ahead of rule 1: "the source is a
    Mendix model you intend to keep developing: `existing-app-change`; rule 1 does not apply to a
    `.mpr`". Entry-modes table gains the row. `existing-app-change.md` is reconciled: the token,
    extraction approach is reuse not N/A, blast radius from the facts and the layer map first, the
    denominator sentence, the two-phase description, the `Waived artifact` lines. `coverage-ledger.md`
    gets the boundary sentence. `skill-routing.tsv:110` stages become `P,0,1,2,3,4,6`.
    `app-analysis.md:303` to `:308` ("not yet wired") is rewritten when, and only when, increments
    2 and 3 have landed. An eval scenario for this path, in the shape of `stage-0-scope/happy-path`,
    built on an invented fixture.

Increments 1 and 2 are the four correct things. Increment 3 makes Stage 0 cheap instead of manual.
Increment 4 is documentation and can trail by a week without anything being wrong, as long as the
runbook's rule 0 lands with increment 1 so nobody routes a live app to Migration in the meantime.

---

## 7. What not to do

**A second mode or token for onboarding.** Section 2. It doubles the manifest and waiver surface
for no decision the gate would make differently.

**A per-slice project directory.** The dry run did this in `/tmp` and it worked for one slice. It
breaks on the second: the regression net does not accrete, the dispositions do not accumulate, and
the `Facts:` sha the second slice cites belongs to a directory the first slice cannot see. One
project, the app's own, with an archive at slice close.

**A namespaced live layout (`slices/<id>/triage.md`) read by the gate.** Every `resolve_stage_file`
and `resolve_artifact` call in `gate-check.sh` would need a slice argument; that is a rewrite of the
gate for a case (two slices in flight on one app) that has not happened yet. Archive at close, and
revisit when it happens (section 8).

**Mode-aware stage checks.** A `case "$ENTRY_MODE"` inside `check_stage_3()` passes a slice that
adds pages with no wireframes on the label alone. The inversion table stays prose; the mechanism is
evidence lines. This is the proposal in the brief I reject most firmly.

**A generated `blueprint.html` for an existing app, or a renderer for it.** The previous design
note's view 7: it presents a computed order as an intended architecture with no checkpoint behind
it. The layer map is the description; the Stage 3 row is the decision. The manifest row simply does
not carry the token.

**Rebuilding the dossier per slice.** Section 2. Facts refresh in seconds; the dossier is a standing
document whose dispositions a rebuild would destroy.

**A whole-app Track B baseline before the first slice.** 448 pages of journeys before anyone is
allowed to change a microflow is the instruction that guarantees Ground Rule 1 is skipped. The
baseline is per radius, written before the slice's first exec, and it grows.

**Unattended self-consent for ASSUMED.** Intake Q9's text implies it; `open-questions.sh:285` to
`:290` refuses it; the collector is right. An unattended run on a live app produces UNRAISED
questions that block the gate until a person looks, and that is the correct outcome. Fix the Q9
wording, not the collector.

**Index collection app-wide in `app-facts.sh`.** 799 describes, about three minutes, for a fact
only slices consume. Slice-scoped, seconds.

**Names in `inventory.json`.** Section 4. The catalog has them; the dossier does not want them.

**Reading `app-report.json` health in the gate.** Tempting, since the JSON exists for agents. But
health is a statement about the app and the gate is a statement about the slice; a gate that fails
because the app is `at risk` blocks every slice on an app whose whole point is to get less risky
one slice at a time. The two gate reads of the facts in this design are the sha compare and the
close check, both about the slice.

**A rendered refresh delta, now.** Deferred, not rejected. `git diff` over committed facts is enough
for the flow; the previous design note ranks a rendered delta second on its build list, and nothing
here contradicts that once increments 1 to 3 exist.

**Unifying `requirements-driven` and `requirements` between the two parsers in this change.** It
should happen, and it is a separate change with its own fixture, because it touches every migration
and requirements project's artifact report. Do not bundle it with a new mode.

---

## 8. Open questions

1. **Two slices in flight on one app.** The singular layout assumes one. Teams of three on a
   107-module app will want two. Archive-at-close does not answer it; namespacing does, at the cost
   in section 7. Not settled; watch for the first time it happens.
2. **Detecting edits to existing pages.** The close check sees page counts, not page content. A
   model diff between two `.mpr` shas at document granularity is the right instrument and does not
   exist in `mxcli` as far as its help output shows. Whether the catalog's `source` or `snapshots`
   tables (present in the schema, not examined) could support a cheap per-document hash was not
   checked.
3. **Catalog rebuild on a live team.** Both fast and full runs rewrite `<mpr dir>/.mxcli/catalog.db`,
   which every other `mxcli` command shares. "Run when nobody is mid-edit" is not a rule a
   continuous team can follow. Whether `mxcli` can query without a rebuild, or whether the facts
   run can point at a copy of the `.mpr`, was not checked.
4. **The Stage 5 regression mark.** Section 1.9 proposes an obligation row. Whether the `look` and
   `sweep` rows' discharge shape (a dated file that names the module) is enough for "the baseline
   was re-run and was green", or whether `report-disposition-check` should own it, is a design
   choice I have not made.
5. **Where the slice's `describe` exports live.** Section 1.5 puts them in `analysis/app-facts/mdl/`
   so a full run refreshes them. That means the source ledger's root contains documents from other
   slices and from the loop sweep, and the ledger will want dispositions for all of them. Either
   the ledger's root is a per-slice list, or the exports go under `analysis/slices/<id>/mdl/` and
   are duplicated by the next full run. Either works; I lean to per-slice directories and have not
   tested the ledger against 400 unrelated files.
6. **"Modules touched" for a module inside the tangle.** The layer map gives modules above and
   back-edge sources; whether that list, rather than the full component, is the right regression
   scope for a change to a widely referenced entity is a judgement per slice, and the slice table
   has no row for "modules in the regression net" separate from "modules touched". Possibly it
   should.
7. **The `Facts:` sha on a two-tree checkout.** `graph-sweep.sh:39` to `:50` documents the case
   where the catalog lands under `app/.mxcli/`. Whether the sha compare resolves the same `.mpr`
   the facts run did was not checked.
8. **Whether `mxcli describe entity`'s index clause syntax is stable across versions**, since the
   slice instrument would parse it. Verified on v0.21.0 only.

---

## 9. What the flow does to the dry run's findings

| finding | resolved by |
|---|---|
| dishonest 155-byte design-system stub passes Stage 3 | section 3: waiver lines with evidence, gate reads them, close check compares |
| triage template and skill contradict each other on extraction | Stage 0 ticks "reuse: mxcli catalog and describe"; the skill sentence changes |
| blast radius has no slot in the template | `## Blast radius` and `## Slice` sections, gate checks the labels |
| Path D KB reads as `documents` and carries a permanent FAULT | `live-model` provenance in both report scripts |
| `brd-report.sh` renders `manual` everywhere | same |
| source sufficiency bands a live app SKETCH and wants 433 `.mdl` rows | sufficiency is advisory at Stage 0 and recorded with its reason; `.mdl` gets a formats row; the ledger's root is the slice's describes, which is what made the ledger work |
| open-questions said zero sources read while the ledger said three | that message fires on the absence of `*.brd.json` and `sme-questions.md` (`open-questions.sh:503` to `:510`), a file-presence rule; in this flow `sme-questions.md` exists from Stage 1 onward |
| four obligations owed including a walking skeleton | `skeleton` (`obligations.tsv:51`) is a from-Stage-5 project-scope obligation; on a live app the skeleton is the app, and it is waived by register line with that reason. `design-reaches-app` follows the design-system artifact and is not owed. `workflow-count` and `coherence` stay |
| no renderer for `blueprint.html` | not owed in this mode; nothing to render |
| unattended cannot self-consent | correct; Q9 wording changes |
| the ledger worked | kept exactly as is |

---

## 10. What was not checked

* I did not run `gate-check.sh`, `status.sh` or `artifact-check.sh` myself. A subagent ran
  `artifact-check.sh` read-only against the dry-run project and confirmed by mtime that nothing was
  written; `gate-check.sh` was not re-run because its full run regenerates `index.html` in the
  project. The gate output in this note is the transcript the field-run record captured.
* I did not open the probe app, run any `mxcli` command against it, or read any of its documents.
  Catalog table names, row counts and the index-clause verification come from one subagent's
  read-only `sqlite3 .schema` and `SELECT COUNT(*)` queries and one `describe entity` call; I did
  not repeat them.
* I did not read `bin/lib/obligation-check.sh` beyond confirming `obligations.tsv` has no mode
  column, so whether obligations can be waived per mode or only by register line is inferred from
  the header at `obligations.tsv:21` to `:30`, not verified.
* I did not verify that `_art_waiver`'s lookup can be called from `gate-check.sh` without sourcing
  order problems; the stage checks run before `artifact-check.sh` is sourced at `:2179`, so
  increment 2 may need the three-line lookup copied rather than called.
* I did not time the fast run; 18 s is the sum of two `timings_s` fields in the probe manifest.
* I did not test the source ledger against a `mdl/` directory holding hundreds of unrelated
  describes (open question 5).
* I did not read `process/process-learnings.md` or the eval runner assertions.
* The 36-row manifest count and the `reg_field` behaviour on a table row are the two facts I
  verified with my own commands; everything else in section 0 is a subagent's reading that I did
  not independently repeat.
