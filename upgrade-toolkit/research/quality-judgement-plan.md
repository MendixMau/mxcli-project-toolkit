# Upgrade quality judgement — plan (v1, 2026-10-08)

Status: AGREED (decisions in section 8). Built from six research passes (the brain, run evidence b1–b5, the toolkit
gates, Mendix docs/forum/partners, industry practice, data checks), one synthesis and one adversarial review.

## 0. The finding that changes everything

The Forms regression **was already in our own release-impact table, and it was closed with a false reason.**
- Row 230 in `runs/b5-forms/evidence/r2/release-impact-r2full.md:242` (branch `runs/b5-forms`) reads "Removed deprecated
  Objects.SetSystemAttributesOnChange … system attributes updated on commit only". The agent closed it as "not relevant:
  setting never set … the app already ran with the default behaviour".
- The source was 9.24.3, so the default *did* change for this app.
- The same change also appears as a 10.20.0 "improvement" row, which the default type filter drops
  (`release_impact.py:100`).

So the problem was neither missing information nor missing tests. **A judgement was made without evidence.** Walking
more paths would not have fixed that. Checking the soundness of every closure would.

## 1. What we chase

**North-star: regression catch rate on faults the rule authors did not see.** That means held-out real defects plus
seeded faults written by someone else. The verdict line reads `caught c / seeded s`.

Supporting metrics, printed per app:
1. **The impact worklist is 100% resolved with evidence**: `resolved R / R`. Every rule hit, touched action or entry
   point, updated or repaired module, and data-conversion step gets a resolution, and every resolution is typed:
   grep-settled, journey-cited, data-cited, or waived with a reason. A typed resolution must cite its evidence. This
   replaces "100% coverage".
2. **Unexplained old-vs-new differences = 0.** The noise baseline is the old app run twice (the Diffy/Scientist
   model).
3. **False-failure rate**: checks that fail on the old app ÷ checks run. Today about 499 generated journeys fail on
   the old app, and they found 0 regressions.
4. **Cost per layer** (tokens, minutes, and human review minutes). It is instrumented first; no cost target is set
   before there is a baseline.

Why not path coverage: in b4 and b5, generated journeys caught **0 of about 13** real regressions. The rest were caught
by shotdiff (3), smoke console errors (2), constcheck, idcheck, localedits, one hand-written journey, and people
looking at screenshots. Forms was caught by a hand walk. Research also shows coverage is weakly linked to fault
detection. Mendix's own testing pyramid puts static analysis at the base.

## 2. Judgement layers

| # | Layer | Proves | Instrument (existing / new) | Gate | Denominator |
|---|---|---|---|---|---|
| L0 | Build | Model and Java compile on 11.12.5 | mx check, javac | block | errors = 0 |
| L1 | Static behaviour rules | Every changed platform behaviour that applies to this app is located in the model | release_impact (widened to runtime-area improvement/fix rows), replacement_check; **new** `behaviour-rules.tsv` (expr/mdlseq clauses) | block: an open HIT is INVALID, a confirmed HIT is FAIL | rules applicable / hit / resolved |
| L1b | Access matrix diff | No role silently gains or loses entity, page or microflow access, or XPath behaviour | **new**, from mprmodel old vs new | REVIEW | rules × roles |
| L2 | Impact walk + effect values | Touched actions **and non-UI entry points** (scheduled events, task queues, after-startup, published and consumed REST/OData) behave the same and **write the same values** | run_journeys `--bar impact`; **new** D2 effect-values compare; rest/apis rungs required when the app has services | block | touched T = walked W + evidenced E |
| L3 | Critical set | Every role logs in, **anonymous included**; top 3–5 confirmed processes work; **one anonymous process is mandatory** if a guest role exists | always-on journeys + process_journeys | block (an always-on INVALID blocks) | roles R/R, processes P/P |
| L4 | Every page | Every page opens with no new console errors and reads the same (screenshot + visible text) | smokewalk to every page, shotdiff, **new** text diff, numeric HTML-ID prefixes stripped (11.2 change) | block on errors; a difference is REVIEW | pages opened / all, each unopened page with a reason |
| L5 | Data | Data at rest survived; multi-deployment conversions ran and are complete | snapshot + diff (D1); **new** conversion predicates per module rung (D3) | block | entities, predicates |
| L6 | Sampled hand walk | Escapes can still be found | 15 min per app on one random untouched process | finding → FAIL + new rule | 1 per app |
| C | Controls | The layers can fail | seeded mutants (changedDate-class, zeroed attribute, dropped association, throwing page, one in an **unchanged** document) | an uncaught control makes the run INVALID | caught / seeded |

**Closure rule (new, applies to every layer).** "The setting is absent, so this is not relevant" is banned for any
row about a removed setting or a flipped default. The only valid closure is "the source version already had the new
default", citing that version. Every b4/b5 closure is re-audited against this rule, with row 230 as the test case.

## 3. Impact selection

An action or entry point is **touched** if anything it reaches, through its flows, sub-flows, pages and snippets,
meets any of these:
- a model diff (impact_map plus `mx diff`);
- a repaired document;
- an updated module;
- a replacement or deprecated-API hit;
- a convertcheck rewrite;
- an **L1 behaviour-rule hit, including hits in unchanged documents**;
- an unreadable add-on (unknown reach counts as touched).

To build: a `reach` field in action_inventory.py, plus `impact_actions.py`.

**Safety net for untouched code:** L1 scans the whole model, L4 opens every page, L3 always runs, D1 checks all data,
L6 samples one process, and the controls include a mutant in an unchanged document.

## 4. Verdicts

- **PASS**: everything was walked (the current `all` bar, unchanged).
- **PASS (impact: U unwalked)**: a new, distinct label, and the normal shippable result. Every blocking layer passes,
  the worklist is resolved with evidence, and every unwalked action is listed with its reason and the layers that
  cover it. It is kept separate from PASS*, which keeps its current meaning (accepted differences, stand-ins).
- **FAIL**: a regression, a confirmed rule HIT, a failed data predicate, or a new console error.
- **INVALID**: anything not measured, or a missing denominator line. This includes an uncaught control, an unknown
  touched set, or an unevidenced resolution.

No gate gets weaker: the `all` and `processes` bars and the full-coverage line stay printed, and SKILL.md and
steps/gate.md are synced in the same change.

## 5. Case scan online (new: "Option 3", brain-first)

Per app, at triage time. The input is the source version, 11.12.5, and the modules, widgets and jars with their
versions.
1. **Brain first.** Look up `sp-changes.jsonl` and `module-changes.jsonl`. Examples of what the brain already names:
   multi-deployment modules such as Workflow Commons 3.0 → 3.6 → 4.0, Encryption 2.2 re-encrypt, Global Inbox, the
   GenAI connectors, and Charts/HTML Snippet property loss.
2. **Live scan only for gaps**, meaning module versions the brain does not know. It covers Marketplace module pages
   and their GitHub issues, the community forum, and docs known issues. Results are cached into the brain with source
   URL and date.
3. **Output: candidate rows** (module, version window, symptom, source). Each becomes a candidate L1 rule, an impact
   input or a D3 rung.

Build split:
- **Script** (`case_scan.py`): query building, fetching, deduplication, caching, no LLM.
- **Skill** (`skills/case-scan.md`): relevance judgement and turning a hit into a rule.

Safety: web text is untrusted data and never executed. **Candidates are advisory** until a field run or a human
confirms them, and only then can they block.

## 6. Build order (first item is small)

1. **S. Done (QJ-1, R30 + `expr:` clause).** Rule S1 (changedDate / system attributes, matched on meaning, not only on the token):
   - fires when the jump crosses 10.20.0;
   - answers UNKNOWN for a source between 10.20 and 11.0 unless the runtime settings are evidenced;
   - widen release_impact to runtime-area improvement/fix rows;
   - **check: S1 must HIT SubmitForm on `runs/b5-forms`.**
2. **S. Done (QJ-2: `release_impact --check` flags UNSOUND; re-audit in `closure-reaudit-b4b5.md`).** The closure rule, plus a re-audit of b4/b5 closures.
2b. **S. Done (QJ-3: R31, behaviour rule S2, StrictChangeBehavior).** By-name setters in own Java and ObjectHandling's
   by-name Java action; clear on all 15 field apps. S3 (list after Delete) waits on item 12 (QJ-4).
3. **S. Done (QJ-5: `anonymous process: P of 1 required`, always-on INVALID blocks under either bar).** An anonymous login plus a mandatory anonymous process in L3; an always-on INVALID blocks. A process cannot run as the anonymous role until the runner can sign in as nobody (E6-10), so a guest-access app is INVALID at rung 8 until then.
   - Follow-up (user decision 2026-10-09): an API-only role (home page = the login page) is a `not_browser` row, never an
     always-on INVALID: no browser journey could ever clear it, so blocking on it would hold every app with an integration
     user. Its services are what the other rungs check. FSM (t8r2): `login-FSMAPIConsumer` moved from skipped to not_browser.
4. **S. Done (`bin/cost_ledger.py`, printed by gate.sh, measurement only).** Per-layer cost and review-minute instrumentation, which becomes the cost baseline.
5. **M.** D2 effect-values compare: column classes from the model, one shared noise list (merging diff.py VOLATILE and
   pgmap NOISE), and a planted-zero control.
   - **5a done:** `bin/effect_values.py` snap/compare (standalone, not wired into run_journeys yet; snap needs
     `--model`, the name heuristic only with `--no-model`, since it would store a raw hash). Planted zero, dropped
     association and missing entity are caught on fixtures and on a throwaway Postgres. **Open:** the shared noise
     list. pgmap NOISE alone has Session_User, UserReportInfo_User, TokenInformation_User, TaskQueueToken, SessionLog*;
     diff VOLATILE alone has Error*, ClusterLock*, Http*, ODataResponse, Paging, SoapFault, SynchronizationError*,
     WorkflowEndedUserTask*, UnreferencedFile*. A plain union would make D1 ignore more, so it needs a row-by-row call.
6. **M.** `reach` + `impact_actions.py` + `--bar impact` + non-UI entry points + the report lines + doc sync.
   - **6a done:** `reach` / `reach_unknown` in action_inventory.py and `bin/impact_actions.py` (measurement only, not
     wired to the gate). Field run, Purchase Request 2023 old -> new: impact_map alone touches 194 of 196 actions; with
     replacement_check and convertcheck, 196 of 196. Updated modules (Atlas_Core, WorkflowCommons) reach almost
     every action through layouts and snippets, and replacement rows that name no document touch everything.
     **Open before 6b:** as written, impact selection selects everything on a real app, so `--bar impact` would save
     nothing. A finer rule is needed (a module update touches only the reached documents that changed in it; widget
     rows mapped to the pages using the widget). Non-UI entry points are not in actions.json yet.
7. **M.** `case_scan.py` + `skills/case-scan.md`, brain-first.
8. **M. Done (harness + first blind set; static layers only).** The seeded-fault set (authored by someone other than the rule author) and a replay harness.
   `bin/replay_faults.py` + `controls/lib/mutate_mpr.py`; the first blind set is
   `controls/fixtures/seeded/blind-2026-10-08.jsonl` (12 faults, written by a separate agent that never saw the rules;
   format in `FORMAT.md` beside it). Only JUDGING layers (L1b, convert, const, idcheck) count as caught; impact and
   actions only SELECT a change for a runtime walk, and in a fault-only replay every fault is a change.
   **Result (after the two fixes below): caught 1 / seeded 12; selected 10 (a runtime layer must judge them); unseen 0;
   inert 1.** First run read caught 1, selected 10, unseen 1 (F10), with F12 counted as selected. Findings:
   - F10 (an attribute default changed) was unseen: `impact_map` only diffed flows and pages. Fixed: it now diffs domain
     models (entities, attributes, validation, access per role set), and F10 is selected. Re-scored: caught 1,
     selected 10, unseen 0, inert 1 (with F12 inert). No static layer JUDGES a default change wrong; that stays a runtime question.
   - F12 (a MendixSSO microflow lost the Administrator role) is an INERT seed: the microflow is Excluded, so it is not
     built and its roles grant nothing; `access_matrix` skips Excluded documents by design. The harness now reports
     such seeds as `inert` (counted in none of caught / selected / unseen).
   - The runtime layers L0 and L1–L6 cannot run here (no mxbuild); the 10 selected faults are the real test of them.
9. **M.** The access matrix diff, the theme-clash grep, and the HTML-ID strip.
   - **9a done:** `bin/access_matrix.py` matrix/diff (L1b, REVIEW; not wired to the gate yet). Field: Purchase Request
     2023 old -> new 806 gained, 268 lost, 78 XPath changed (mostly the WorkflowCommons update); viA -> viB 5 lost. A
     module whose roles the model cannot read is "not compared" and the diff exits 3, never "no difference". The HTML-ID
     strip is still open.
   - **9b done (user decision 2026-10-09: a clash is against the new Atlas):** `bin/theme_clash.py` snap/diff (REVIEW;
     not wired to the gate yet). A clash is a variable, mixin, class or @extend target that the app's own styling uses,
     that the old Atlas (atlas_core, atlas_web_content, datawidgets) defined, and that the new Atlas no longer has. Exit 3
     when either side has no Atlas, never "no clash". Field: the three upgrade pairs have 0 clashes (pr19->pr33 removes
     no Atlas names; viA->viB removes 14 variables and 1 class, none used by the app). The reversed pairs give 2 real
     clashes (.table-content, .mx-scrollcontainer-top), both checked by hand. A planted @extend of the removed
     .date-filter-container in viB is caught. Limits: interpolated selectors, markup-only classes and plain .css are not seen.
10. **M–L.** L4 every page: parameter pages opened with seeded objects, plus the text diff.
11. **L.** D3 multi-deployment rungs: Workflow Commons and Encryption first.
12. **Ongoing.** Behaviour rules per jump: about 100 for 11.x, about 360 for 10.x and about 670 for 9.x (estimates
    from n=88). Each is versioned by patch.

## 7. Trial

- **Training check.** Replay batch 5 (Forms, Tasks, News) in observation mode. S1 and D2 must flag Forms with no hand
  walk, and no earlier finding may be lost. This is reported as *training-set recall*.
- **Real check.** One held-out app (batch 6) plus mutants written by a second author. Its catch rate is the
  north-star number.
- "Touched set size" is information only, never a success criterion.

## 8. Decisions

1. **Decided:** "PASS (impact: U unwalked)" is the normal shippable verdict. It deliberately narrows Mendix's "test all
   functionality"; the full bar stays printed.
2. **Decided:** seeded faults are written by a separate agent with no access to the rules (or a colleague), never by
   the rule author.
3. **Decided:** the plan lives here and build starts with item 1.
4. **Decided:** the online case scan is brain-first (section 5), live scan only for gaps, advisory until confirmed.

Still open:
5. Merge the mxupgradeassist entries (75 human-checked) into the rules?
6. Should the 15-minute sampled hand walk stay mandatory per app? It is our only way to measure escapes.
7. For parameter pages that can't be seeded: list them as unopened, or block?
