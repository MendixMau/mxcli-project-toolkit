# Step records: every action proposed, approved, done and tested, written while it happens

Status: plan, nothing built. Branch `feat/cockpit-trail`. Fixture: the ShopFloor run2 trail
(`~/upgrade-lab/shopfloor/run2/work/cockpit-trail.json`, made by hand with `build_trail.py` and `human.py`).

## 1. Goal

Today the cockpit shows what happened, but not what was proposed for each step, who approved it, or how it was tested.
On run2 those details were rebuilt by hand afterwards from AGENT-DECISIONS.md, commits, logs and screenshots. On ShiftSwap
the plan column only says "Plan written" and 16 choices sit as "assumed by the agent".

The pipeline must write one **step record** per action, at the moment each part happens. The cockpit reads the records
directly. The gate refuses a run whose changes have no record.

**Done looks like this in the cockpit.** Click any cell, for example HTMLSnippet in the Plan column. The drawer shows:
1. what was found, with proof;
2. what is proposed, why, and the other options;
3. the approval state: approved by a name and date, assumed with "needs your OK" and a button, or rejected;
4. the commits that did it;
5. the tests that prove it, with the verdict and the proof behind a toggle.

Every block is in plain words for a person, with the technical proof one click away. None of it is typed in after the run.

## 2. The record

One file per run: `work/steps.jsonl`. Each line is one event, `{"id", "field", "value", "by", "at"}`, and is never
rewritten. For each id and field, the last event wins, the same rule as `decisions.json`. `bin/steps.py` folds the
events into records. The folded record for the run2 jQuery step:

```json
{
 "id": "S-14",
 "topic": "regression:HTMLSnippet",
 "title": "jQuery scripts on the React client",
 "found": {
  "say": "The new React client cannot run the snippet widget at all. 166 snippets hold 88 different jQuery scripts.",
  "stage": "triage",
  "evidence": ["DOJO-ASSESSMENT.md#A-R3", "work/dojo-report.md"]
 },
 "proposed": {
  "say": "Keep every script, but run it from a JavaScript action that an Events widget starts when the page loads.",
  "why": "Same behaviour as today at the lowest cost. Rewriting 88 scripts as widgets takes weeks.",
  "options": ["Bridge now, review the scripts later (recommended)",
              "Rewrite each script as a widget or page logic (about 88, weeks)",
              "Stay on the classic client until just before Mendix 12"],
  "recommend": 0,
  "ra": "RA-3",
  "closes_by": ["smoke", "journeys", "screens"],
  "decisions": ["D71", "D76"]
 },
 "approval": {"state": "assumed", "by": "agent", "at": "2026-10-28T01:12", "source": "unattended",
              "needs": "owner choice before merge"},
 "done": {"commits": [{"sha": "940eb79", "say": "87 scripts moved into JavaScript actions"},
                      {"sha": "fd259b5", "say": "24 snippets mx check did not flag"},
                      {"sha": "112a9b0", "say": "index.html rebuilt on the React template"}]},
 "tested": {"results": [{"rung": "smoke", "verdict": "PASS", "say": "4 of 4 pages open without errors",
                         "proof": ["gate/smoke-after.json"]},
                        {"rung": "journeys", "verdict": "PASS", "say": "46 of 46 click paths end the same",
                         "proof": ["gate/journeys.md"]}],
            "gaps": [{"say": "Each of the 88 scripts on its own is not tested", "owner": "app owner"}]},
 "status": "open"
}
```

Rules:
- `say` fields are for a person: no code, no file names, one or two sentences. Proof and paths sit next to them.
- A missing part is shown as a gap with a reason, never left out.
- `status` is derived, never written: `done` when approval is `approved` and every `closes_by` rung is PASS or PASS*;
  `open` when approval is `assumed` or a test is missing; `blocked` on FAIL or `rejected`.

## 3. Who writes what, and when

| Stage | Field | Writer (file, function) | Today |
|---|---|---|---|
| Triage | `found` | `bin/proposal.py` `Facts.build()` opens one step per section 2, 3 and 4 item, with its evidence (it already gathers every triage output) | items exist only as PROPOSAL.md lines |
| Plan | `proposed` | `Facts.add3()` and the section 2 builders in `proposal.py`; `ids_for()` hands out the step ids | P-n ids for section 3 only |
| Plan | `approval` | `proposal.py` `main()`: unattended writes `assumed`, sign-off writes `approved` for every step that was not answered on its own (today `accept_answers()`) | one sign-off for the whole run |
| Any stage | new step | `bin/steps.py propose` when the agent decides mid-run. **steps/decide.md** and the AGENT-DECISIONS rule in SKILL.md: a D row names its step id, or opens one | D rows never become steps |
| Any stage | `approval` | `bin/decisions.py` `cmd_add()` and `cmd_import()`: a ledger row whose `item` is a step id writes the approval; `apply_decisions_md()` keeps DECISIONS.md in step | per item, not linked to steps |
| Upgrade | `done` | `bin/appcommit.sh --step S-n` adds the trailer `Upgrade-Step: S-n`; the toolkit's own commits (stepupdate, convert, repair replay) pass it too; `bin/changelog.py` reads it and calls `steps.py done` | 6 of 53 run2 commits name a decision |
| Test | `tested` | `bin/gate.sh` after the rungs: `steps.py tested --gate $G` maps each step's `closes_by` rungs to their rows in `gate-summary.md`, `heal.json` and the journeys results | nothing links a test to a step |
| Any | `say` | the agent that did the work, in the same command (`--say`); script-made steps get a template sentence from the script | written afterwards in `human.py` |

`bin/steps.py` is the only writer of `steps.jsonl`. Commands: `open`, `propose`, `approve`, `done`, `tested`, `gap`,
`show`, `check`, `import-legacy`.

## 4. The gate rung `trail`

New rung in `RUNGS` in `bin/gate.sh`, after `widgets`. It runs `steps.py check --work $W --app $APP_REPO`.

| Check | Fail kind |
|---|---|
| Every commit in the app repo since the baseline carries `Upgrade-Step:` with an existing step id | FAIL, the commits are listed |
| Every step has `found`, `proposed` and `approval`, or a written gap | INVALID |
| Every step with `approval: approved` has a `done` commit, or the gap "no change needed" | INVALID |
| Every step with `closes_by` has a `tested` result for each rung | INVALID |
| A step with `approval: assumed` | not a failure: counted as an open topic with its owner, and blocks the owner sign-off (the same rule as ASSUMED lines in decide.md) |
| A `say` field missing or holding a path or code | report line only ("needs plain words"), verdict unchanged |

Start it as optional (NOT RUN allowed), so old runs keep their verdict. It becomes required once ShiftSwap passes it
natively (slice 9).

## 5. Cockpit changes

- **Fold in today's work first (slice 0).** The uncommitted `bin/cockpitmatrix.py` diff on this branch is the drawer
  that slice 9 needs:
  - `merge_trail()` and `plan_doc()`
  - the JS `trailBox`, `pfItem`, `propBox`, `planBtn`, `topicPlan` and `planPanel`
  - the topic-scoped plan view, the facts chips and the "Changes in the app" list
  
  Commit it as it is, still reading `cockpit-trail.json`, with the run2 file as its fixture.
- **Read the records (slice 7).** In `bin/cockpitmatrix.py`:
  - `build()` calls `steps.py`'s loader and turns each record into a trail action under its `topic` row. This replaces `merge_trail(cp.rj(... "cockpit-trail.json"))`; `cockpit-trail.json` stays only as the input for old runs.
  - `plan_doc()` stays as the fallback when no `steps.jsonl` exists.
  - `bin/cockpitpage.py` `build_model()` counts open topics from step status instead of parsing AGENT-DECISIONS.md (`parse_agent_decisions`).
- **Approve per step (slice 8).** The drawer gets the approve, reject and choose-option buttons on any step with `approval: assumed`. They write to the existing artifact db collection that `decisions.py import` reads, with the step id as the `item`. Sign-off of the whole plan stays a separate button (the decisions.py SIGN-OFF RULE is unchanged).

## 6. Controls (in `controls/run-controls.sh`, a catch and a pass for each)

| Piece | Catch | Pass |
|---|---|---|
| steps.py events | a second `approve` on the same id wins, the first stays in the file | fold of the run2 fixture equals the expected JSON |
| steps.py refusals | `propose` on an unknown id, `say` with a file path | a valid propose |
| proposal.py | an unattended run leaves no step without `approval` | a signed run gives every step `approved` with the signer |
| decisions.py | a ledger row for a step id writes the approval, rerun adds nothing | a sign-off row still refuses `add` |
| appcommit.sh | `--step` with an unknown id is refused (exit 2) | the trailer is in the commit |
| changelog.py | a commit without `Upgrade-Step` is listed "no step" | a labelled commit lands in `done` |
| gate trail rung | a commit without a step makes the rung FAIL | the run2 fixture with gaps written is PASS* |
| cockpit | a step with no test shows a gap box, not a pass | the run2 fixture renders the jQuery step with 3 commits and 2 tests |

## 7. Old runs

`steps.py import-legacy --work W` builds records from what an old run holds:
- PROPOSAL.md items and their P-n ids;
- DECISIONS.md lines;
- AGENT-DECISIONS.md D rows;
- commits whose `Upgrade-Change` rule names a decision.

Anything it cannot link becomes a gap, "not linked in this run". It never guesses.

`build_trail.py` and `human.py` move out of the scratchpad into `controls/fixtures/steps/run2/` as the expected output.
Then `import-legacy` on run2 is checked against them, which shows how much of the hand-made trail the importer
recovers. The hand-written plain text there is kept as the fixture's `say` values.

## 8. Slices (one PR each, controls green against main before each)

| # | Slice | Files |
|---|---|---|
| 0 | Commit today's drawer and plan view, still reading cockpit-trail.json, with the run2 fixture and a cockpit control | `bin/cockpitmatrix.py`, `controls/cockpit_control.sh`, `steps/report.md` |
| 1 | `bin/steps.py`: schema, events, fold, check, show | new `bin/steps.py`, controls |
| 2 | Triage and plan write steps (`found`, `proposed`, `approval`), ids from `ids_for()` | `bin/proposal.py`, `steps/propose.md` |
| 3 | Approval through the ledger, per step | `bin/decisions.py`, `steps/decide.md` |
| 4 | Mid-run decisions open steps; D rows name their step | `steps/decide.md`, `SKILL.md` (rules and stop rules) |
| 5 | Commits name their step | `bin/appcommit.sh`, `bin/changelog.py`, the toolkit's own committing scripts, `steps/upgrade.md`, `steps/repair.md` |
| 6 | Tests link to steps | `bin/gate.sh` (after the rungs), `bin/steps.py tested` |
| 7 | Cockpit reads steps.jsonl, falls back to the old inputs | `bin/cockpitmatrix.py` `build()`, `bin/cockpitpage.py` `build_model()` |
| 8 | Approve per step in the drawer | `bin/cockpitmatrix.py` JS, `bin/decisions.py import` |
| 9 | Gate rung `trail` (optional), `import-legacy`, run2 fixture | `bin/gate.sh`, `steps/gate.md`, `bin/steps.py` |
| 10 | ShiftSwap native rerun, add to `examples/`, make the rung required | `examples/shiftswap/`, `bin/gate.sh`, `READING-THE-VERDICT.md` |

Slices 0 to 2 give a visible cockpit gain on their own; the public release can wait for slice 10, or go out after 0.

## 9. Open decisions for the maintainer

1. **One id for everything?**
   - (a) Every record is `S-n`, and P-n stays as an alias. `S-n` already names stuck items in decide.md.
   - (b) Keep P-n for plan items and add S-n for the rest.
   
   Recommend (a): one number per step, the one people approve.
2. **How fine is a step?**
   - (a) One step per module update.
   - (b) One step per topic row, with sub-items.
   
   Recommend (b) for routine updates (approved with the plan, no button, see feedback "flag only real decisions") and one step per real choice.
3. **Trail rung strictness.**
   - (a) Required from slice 9.
   - (b) Optional until ShiftSwap passes it natively.
   
   Recommend (b), so old runs keep their verdict.
4. **Who writes the plain text?**
   - (a) The agent, at the moment.
   - (b) Templates in the scripts.
   - (c) Both.
   
   Recommend (c): templates for script steps, the agent for its own.
5. **Public release timing.**
   - (a) Release now, with the run2 drawer as a demo.
   - (b) Release after slice 10, with ShiftSwap as the native showcase.
   
   Recommend (b), because the first thing outside users see should be produced by the pipeline itself.
