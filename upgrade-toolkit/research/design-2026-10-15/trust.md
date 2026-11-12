# Trust: definition of done, upgrade proposal, change ledger (spec, 15 Oct 2026)

Product owner decisions, 15 Oct: an upgrade is never fully automatic, so the toolkit must (1) define "done" as nothing
left that the toolkit can close on its own, (2) propose before it changes anything, with custom work and re-architecture
flagged and signed off by a person, and (3) show afterwards exactly what was changed, by whom and why.

## 1. Definition of done (SKILL.md, new section "Run done", above the existing machine definition)

A run is DONE when there are 0 open items and the owner has signed off. Every item ends in exactly one closed state:

| state | means | who closes it | proof |
|---|---|---|---|
| FIXED | re-measured PASS or PASS* | the toolkit | the gate rung, after the fix |
| EVIDENCED | cannot be measured in this app (no route, no data the UI can make), shown from the model or a log | a person confirms | evidence line + `confirmed: <name>` |
| DECIDED | an option was chosen (steps/decide.md) | a person | DECISIONS.md line, CONFIRMED |
| HANDED-OFF | someone else does it (Studio Pro step, custom widget, key user) | a person | name + date in DECISIONS.md |
| PAUSED | the owner stopped the run on purpose | a person | `Status: PAUSED <reason>` |

- "Open" = anything else. The progress line (PR 101) counts FIXED only; the other states are listed by name.
- The agent closes FIXED alone. It may propose EVIDENCED/DECIDED/HANDED-OFF with a recommendation, never close them.
- Re-architecture (replace a widget family, rebuild a layout, drop a module, rewrite Java) is always a proposal to the
  owner, never done silently. Pause is a valid answer at every stop.
- The existing machine definition (mx check 0, gate rungs...) stays: it defines FIXED for the gate rungs.

## 2. Upgrade proposal: steps/propose.md + bin/proposal.py + pipeline step `propose`

Where: new pipeline step between `basewalk` and `convert` (STEPS list in bin/cloud/upgrade-pipeline.sh). Nothing in the
app model changes before the proposal is signed.

Inputs (all exist after triage/baseline; a missing input is listed as "not measured", never skipped silently):
versions/path, `$W/plan-pre.txt` + `$W/plan.txt`, kept and stranded modules (`kept.txt`, `stranded.md`), localedits RED
modules, `release-impact.md` rows marked human, replacements/release predictions (replacement_check output, e.g. R37
CE6779), widget coverage (widgetcover), dojo_report "can't move", Java user code (usercode/javafinal), theme_clash,
rolecheck, the action inventory size, external systems (apimock inventory).

Output `$W/PROPOSAL.md`, sections in this order:
1. Summary: from -> to, rungs, app size (modules, pages, microflows, actions), headline "N items the toolkit expects to
   handle, M need your decision, K need a person anyway".
2. Done by the toolkit: module updates (version from -> to), predicted repairs with their repair-row / replacement ids.
3. Needs your decision before we start: one entry per item with kind (module / widget / page / Java / theme /
   re-architecture), the evidence, options (steps/decide.md table), a recommendation, effort S/M/L and risk. Custom work
   and re-architecture candidates are here, never in section 2.
4. Needs a person anyway: key-user confirmation of processes, visual sign-off of changed screens, release rows a person
   must judge, go-live actions, real test systems for external APIs.
5. Human effort: count of touchpoints per kind and an honest range (no single number); say what is unknown.
6. Sign-off: `Signed-off: <name> <yyyy-mm-dd>` or `Status: PAUSED <reason>`, written by a person.

Gate behaviour: unsigned -> exit 14 "proposal awaits sign-off" (NEEDS-JUDGMENT.md points at PROPOSAL.md); PAUSED ->
exit 15 with the resume command; signed -> continue. Section-3 answers are recorded as DECISIONS.md lines (decide.md
format, `P-n` ids). `Interview mode: unattended` signs nothing: it records `ASSUMED (unattended)` and every later report
carries "proposal not signed". The proposal stores a hash of its inputs; if a later step changes the plan, the pipeline
regenerates it and shows what changed since the signed version, and asks again.

Controls (must-catch + must-pass, fixtures under controls/fixtures/proposal/): a kept module and a widget with no
successor appear under section 3 (catch: they must never be in section 2); unsigned -> exit 14; signed -> 0;
PAUSED -> exit 15; unattended -> ASSUMED line; a changed plan after sign-off -> re-asks; a missing input -> listed as
not measured.

## 3. Change ledger: bin/changelog.py -> `$W/CHANGES.md`, linked from the gate summary

Every commit the toolkit or the agent makes in the app repo carries two trailers:
`Changed-By: toolkit|agent|person` and `Upgrade-Change: <kind> <rule-id>` (kind: module-update, convert, repair,
replay, theme, data, config; rule-id: e.g. `repair-row-22`, `R37`, `stepupdate`, `decision P-3`). stepupdate,
the repair scripts and the convert step add them; hand repairs by the agent go through a small helper
(`bin/appcommit.sh --by agent --kind repair --rule row-22 --why "..." -- <paths>`). A commit without trailers is
"unlabelled": listed, never assumed to be the toolkit's.

`changelog.py` reads the app repo from the run-start marker to HEAD, plus DECISIONS.md and the accept/allow files, and
writes per change: when, by (toolkit / agent / person / unlabelled), kind, rule, why (commit message), what changed
(files; for the model, the changed documents from the toolkit's existing model diff when available, else "model
changed"), and the evidence (log, check output, screenshot). Then the accepted differences (each allow line with its
reason) and the decisions. Gate summary line: `Changes: N (toolkit a, agent b, person c, unlabelled d)`; d > 0 is a
"needs a decision" item. CHANGES.md is the reviewer's document: readable without git.

Controls: a fixture app repo built inside the control with labelled and unlabelled commits: counts per author, an
unlabelled commit is listed and raises the decision item (catch), allow lines appear with their reasons, the gate
summary carries the Changes line.

## Not in scope here
Time/cost tracking (cost_ledger.py exists), the learning harvest (FEEDBACK.md process exists).
