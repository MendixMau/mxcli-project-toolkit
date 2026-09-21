# Skill freshness A/B/C — four baseline-tier skills, 2026-09-17

**TLDR.** Three of the four baseline skills still change drafting behaviour in ways the
validator cannot see; one does not. Ablated versions (arm C) of the three kept most of the
effect but not all of it — one skill lost measurable ground when cut. Verdicts:

| Skill (baseline tier, words) | Verdict | One-line evidence |
|---|---|---|
| `learned-mdl-preflight.md` (7,173) | **KEEP the STOP table; CUT the retired-incident narratives and the "MDL gotchas" section; MOVE workflow rows 18–20 to `learned-workflow-patterns.md`** | Arm C (4,483 words, −37%) matched arm B on every routing row the task exercised: 3/3 routed `ALTER PROJECT SECURITY LEVEL` to plain CLI, 3/3 judged the same-module association read safe, 0/3 forced MCP. Arm A routed the security step to Studio Pro in 2/3 and raised MCP as a possible requirement in 2/3. |
| `learned-microflow-patterns.md` (4,512) | **KEEP in full** | Arm B beat arm A on seven rubric rows the validator is blind to (bracketed `[%CurrentUser%]`, no `$` in parameter declarations, BUG-15b annotation, `REFRESH`, objects-only conflict flagged). Arm C (2,135 words) lost ground: 2/3 drafts regressed to declared object variables (4 check errors each, 0 in all of arm B), the objects-only conflict was flagged in 1/3 (B: 3/3), and one draft re-introduced the inline association write (B: 0/3). The cuts are not free. |
| `ui-preflight-pages.md` (3,727) | **KEEP; the "Common failure modes" and "Report-back format" sections are cut candidates** | Repeats the 2026-08-31 result: arm A 0/3 top-bar layout, 0/3 H1, shell violations 3,3,3; arm B 3/3, 3/3, 2,2,1. Arm C (2,797 words, −25%) was indistinguishable from B: 3/3, 3/3, shell 2,1,2, cross-reference block and NOT RUN rows present in all three reports. |
| `learned-stylegallery.md` (4,249) | **DEMOTE to situational routing for the "add a gallery page" task; the ⛔ rules were not tested and stay** | No arm-B advantage on the one task tried. Twin coverage identical (both arms left 0–1 class uncovered); arm A wired the new page into the gallery home 3/3, arm B 1/3 — two B drafts declined because the attached listing was only 40 lines, and neither used the read-only `DESCRIBE PAGE` the task allowed. No arm C run. |

Cross-cutting findings, each with a follow-up below: the generated project `CLAUDE.md` teaches
two forms mxcli v0.22 now rejects; `learned-mdl-preflight.md` has two rows numbered 24; two
bundled mxcli skills contradict STOP row 6; the experiment cost roughly fourteen times its
token estimate.

## Question

The four skills date from earlier mxcli releases and earlier models. Do they still change what a
fresh drafting agent produces, and if so which parts? The 80,000-word baseline budget is spent
mostly on them, so every word that no longer changes behaviour is paid for on every session.

## Method

- **Fixture.** A scratch copy of the TCX graph PoC model under the session scratchpad, with
  mxcli **v0.22.0 built from its tag** in-container (the project's own binary is v0.16). Nothing
  touched the real model; the scratch model was only read (`SHOW` / `DESCRIBE`).
- **Arms.** A = task prompt with no skill. B = the same prompt with the skill's current full text
  inlined. C = the same prompt with an ablated copy (pure deletion of the sections named in
  `ablations/<skill>.md`; no rewording). 3 reps per arm, fresh Sonnet general-purpose agents,
  identical prompts within an arm. Arm C ran only where B beat A (skills 1–3): 24 + 9 = 33
  drafting runs, plus 2 rubric graders and 1 overlap-table agent.
- **Tasks.** Skill 1: a cross-module microflow plus a security-level change, judged on write-mode
  routing. Skill 2: a page-triggered submit microflow with an XPath retrieve on the current user.
  Skill 3: one page from an attached wireframe, `ds.css` and gallery listing. Skill 4: add a
  gallery page for a card component and wire it into the gallery home.
- **Scoring.** Mechanical first: `mxcli check` errors and `--references` errors; for pages,
  `project-bin/check-page-shell.sh` violations and `project-bin/page-fidelity.js`; for
  microflows, three greps for STOP-row behaviour (inline association write without the MCP
  note, security-level step routed to Studio Pro, annotation on an XPath retrieve). Then a
  rubric grader per skill (10 and 26 rows) reading the drafts and reports; arm C was graded by
  inspection against the same rows.
- **Receipts.** Drafts, reports, `scores.tsv`, `twin-coverage.tsv`, rubric grades,
  `overlap.md`, `armC-notes.md` and `token-spend.tsv` live in the private planning repo under
  `experiments/skill-freshness/receipts/2026-09-17/`. The prompt builders and the scorer are in
  the same folder.

## Results

### Mechanical scores (`scores.tsv`)

| Draft | check errors | ref errors | shell violations | fidelity | STOP hits |
|---|---|---|---|---|---|
| mdl-preflight A r1/r2/r3 | 0 / 4 / 5 | 3 / 0 / 0 | – | – | 0 / 1 / 1 |
| mdl-preflight B r1/r2/r3 | 4 / 0 / 4 | 0 / 1 / 0 | – | – | 0 / 0 / 0 |
| mdl-preflight C r1/r2/r3 | 4 / 1 / 7 | 0 / 1 / 0 | – | – | 0 / 0 / 0 |
| microflow-patterns A r1/r2/r3 | 0 / 0 / 0 | 0 / 0 / 0 | – | – | 1 / 1 / 1 |
| microflow-patterns B r1/r2/r3 | 0 / 0 / 0 | 0 / 0 / 0 | – | – | 0 / 0 / 0 |
| microflow-patterns C r1/r2/r3 | 4 / 4 / 0 | 0 / 0 / 0 | – | – | 0 / 0 / 1 |
| ui-preflight A r1/r2/r3 | 0 | 0 | 3 / 3 / 3 | 71% | – |
| ui-preflight B r1/r2/r3 | 0 | 0 | 2 / 2 / 1 | 71% | – |
| ui-preflight C r1/r2/r3 | 0 | 0 | 2 / 1 / 2 | 71% | – |

Reading the check-error column: every non-zero mdl-preflight cell is the same defect —
`DECLARE $Var Module.Entity;` for an object, which v0.22 rejects (MDL043/CE0053) and then
reports again as a duplicate variable (MDL063/CE0111). It appears in all three arms because the
generated project `CLAUDE.md` teaches that form (see "Findings outside the skills"). It is
validator-visible, so it is not the skill's job; the STOP-hit column is the one the skill owns,
and there arm A hits in 2/3 and arms B and C in 0/3.

Fidelity saturates at 71% on this wireframe (the missed rows are demo values and a script-driven
state a static page cannot carry), so the shell check is the discriminating instrument, exactly
as on 2026-08-31.

### Skill 1 — `learned-mdl-preflight.md`

Rubric (10 rows, grader over A and B; C by inspection of the same rows):

| Row | A | B | C |
|---|---|---|---|
| Same-module association read judged safe, no MCP forced | 1/3 | 3/3 | 3/3 |
| `ALTER PROJECT SECURITY LEVEL` routed to plain CLI (row retired at v0.16) | 1/3 | 3/3 | 3/3 |
| No quoting inside `CHANGE`/`CREATE` attribute lists | 1/3 | 3/3 | 3/3 |
| `[%CurrentUser%]` vs `$currentUser` | split | split | split |

The fourth row splits inside every arm: the skill underdetermines it and the task did not force
it. Arm A's two Studio Pro routings and two MCP detours are the cost of the skill's
absence — an agent without it reaches for the most conservative write mode and the build slows
down for nothing.

What arm C removed and did not miss on this task: STOP row 10 (`count()` unverified), the
incident narratives behind rows 2 and 7 (action cells kept), and the "MDL gotchas" section. What
arm C removed and this task **could not test**: workflow rows 18–20 and the `JUMP TO` row — a
microflow task never reaches them. So the recommendation is to move those to
`learned-workflow-patterns.md`, where the workflow trigger routes, not to delete them.

### Skill 2 — `learned-microflow-patterns.md`

Rubric (26 rows). Clean B-over-A wins on seven rows the validator cannot see:

| Row | A | B | C |
|---|---|---|---|
| No `$` in parameter declarations | 0/3 | 3/3 | 3/3 |
| `[%CurrentUser%]` inside XPath brackets | 1/3 | 3/3 | 3/3 |
| Objects-only page-to-microflow conflict flagged | 0/3 | 3/3 | 1/3 |
| `REFRESH` on the page-triggered commit | 0/3 | 2/3 | 3/3 |
| BUG-15b annotation on the XPath retrieve | 0/3 | 3/3 | 3/3 |
| Declared object variables (check errors) | 0/3 | 0/3 | 2/3 |
| Inline association write (STOP hit) | 1/3 | 0/3 | 1/3 |

Rows the skill does not fix in any arm: the association path without module prefix (missed by
5/6 A+B drafts) and `VALIDATION FEEDBACK` (4/6 used a log line instead). Those two sections are
either not being read or not clear enough; a rewrite there is the next A/B, not a cut.

Arm C's regressions map to the cut sections: the NPE "Dto" section is the only place the file
says that `declare $Var Module.Entity` generates a Create Variable activity, and the objects-only
conflict row draws on the "Mendix-First Design" section. Both were cut in C and both signals
dropped. Verdict: keep the file whole; 2,135 words is too far.

### Skill 3 — `ui-preflight-pages.md`

| Signal | A | B | C |
|---|---|---|---|
| `Atlas_TopBar` (the wireframe's nav is a sticky top bar) | 0/3 | 3/3 | 3/3 |
| H1/H2 title block present | 0/3 | 3/3 | 3/3 |
| Shell violations | 3,3,3 | 2,2,1 | 2,1,2 |
| Wireframe→widget cross-reference table in report | 2/3 partial | 3/3 | 3/3 |
| NOT RUN rows for checks not performed | 3/3 (2–6 rows) | 3/3 (6–12 rows) | 3/3 (5–8 rows) |

The one violation common to every B and C draft is the page-column cap: `ds.css` as attached
carries no page-column class, so the drafts shipped full-bleed and said so. That is the
instrument reporting the fixture, not the skill failing. Arm C cut Step 3, the report-back
format and the failure-mode catalogue; the NOT RUN rows survived because Steps 1, 2, 4 and 5
each still demand them. Step 3 (gallery example reuse) was exercised — C drafts still cited
gallery precedent for button classes — so it stays; the other two sections are cut candidates.

### Skill 4 — `learned-stylegallery.md`

| Signal (`twin-coverage.tsv`) | A r1/r2/r3 | B r1/r2/r3 |
|---|---|---|
| Classes on the new page | 9 / 9 / 13 | 11 / 14 / 10 |
| Left uncovered after the draft | 0 / 0 / 1 | 1 / 1 / 1 |
| New page wired into the gallery home | yes / yes / yes | no / yes / no |
| `check --references` errors | 0 / 0 / 0 | 0 / 0 / 0 |

The two unwired B drafts explained themselves the same way: the attached home-page listing was
truncated, so they refused to guess at the insertion point — and neither ran the `DESCRIBE PAGE`
the prompt allowed. The three A drafts ran it. On this task the skill's text made the agent more
cautious and less complete. The ⛔ rules the file also carries (`ds.css` is never compiled into
the app; `mxcli theme create/apply` does not port component classes) were not exercised and are
not judged here. `check-page-shell.sh` inspects nothing on a gallery draft (no wireframe pairs
with it), so twin coverage plus wiring was the whole mechanical signal. No arm C.

## Findings outside the skills

1. **The generated project `CLAUDE.md` teaches two forms v0.22 rejects.** Its quick reference
   shows `DECLARE $Entity Module.Entity;` for an object and `$Customer: Sales.Customer` (with the
   sigil) in a parameter list. The first produced the check errors in nine drafts across all
   arms. This is the bundled scaffold, not the toolkit — file upstream, and until then
   `skills/bootstrap-project.md` should strip both examples when it merges.
2. **`learned-mdl-preflight.md` has two rows numbered 24** (DesignProperties and `JUMP TO`).
   Renumber when the workflow rows move.
3. **Bundled skills contradict STOP row 6.** `overlap.md` (91 bundled files tabled) finds
   `create-page.md` and `overview-pages.md` both showing association-mode `COMBOBOX` as plain
   `CREATE PAGE` syntax, which row 6 says no mxcli path can write. A check-level probe tonight
   was inconclusive (page-parameter syntax error on my side, not the combobox); the real test is
   exec into the scratch model plus native `mx check`, one afternoon, and either row 6 retires or
   a bug goes upstream. Second conflict: bundled lint rule CONV009 says 15 objects per microflow,
   the toolkit says 30–50 before splitting.
4. **`overlap.md` also lists what only the toolkit says** — every ⛔ rule in the gallery skill,
   the five-step gated page sequence, the Dto pattern, per-row loop isolation — none restated by
   any bundled file. The bundled set is syntax reference; the toolkit's four are discipline.

## Cost, honestly

| | Planned | Actual |
|---|---|---|
| Drafting runs | 60 (4 skills × 3 arms × 5 reps) | 33 (3 reps; arm C only where B > A) |
| Subagent tokens per drafting run | ~8,000 | 115,168 average (range 84k–156k) |
| Total subagent tokens, 37 agents | ~500,000 | 4,325,982 |

Each run reads a 4,000–9,000-word prompt, runs several `SHOW`/`DESCRIBE` queries whose output
is wide, and writes a draft plus a report; the estimate counted only the prompt. Graders cost
144k–156k each. Anyone repeating this should budget 120k per run and cut reps before cutting
arms.

## Deviations from the plan

- 3 reps, not 5; arm C only for skills 1–3 (user asked for the cheapest defensible design).
- The wireframe's column is 1,060px; the plan said 900px. Scored against the real file.
- `ds.css` was derived from the project's design system, not the file the plan named.
- Pass B (bug retirement) skipped: the open bugs are unchanged in v0.22.0 (checked earlier the
  same day against the v0.22 changelog and nightly).
- Three `score.sh` fixes landed during the field run and are committed with it: error counts
  read from the v0.22 summary line instead of a grep over findings; the shell check receives its
  wireframe through a staged directory; the fidelity scorer reads a copy of the wireframe with
  mock-only classes stripped.
- `page-fidelity.js` was run against that stripped copy because the wireframe's mock-state
  classes are not page content; the 71% ceiling is on that copy.

## Follow-ups (each its own PR, none opened tonight)

1. `learned-mdl-preflight.md`: cut rows 10 and the two incident narratives; drop "MDL gotchas";
   move rows 18–20 and `JUMP TO` to `learned-workflow-patterns.md`; renumber 24. Re-render the
   budget (`bin/render-routing.sh --check`).
2. `ui-preflight-pages.md`: cut "Common failure modes" and "Report-back format", keeping the
   NOT RUN sentence inside Step 5.
3. `learned-stylegallery.md`: routing row becomes situational for "add a gallery page"; the ⛔
   section gets its own short baseline-tier entry or moves into `ui-preflight-pages.md` Step 2.
4. `learned-microflow-patterns.md`: A/B the two rows nobody follows (module prefix, validation
   feedback) before touching them.
5. Probe STOP row 6 by exec + `mx check`; retire it or file upstream.
6. Upstream the `CLAUDE.md` quick-reference defects; strip them in `bootstrap-project.md` meanwhile.
