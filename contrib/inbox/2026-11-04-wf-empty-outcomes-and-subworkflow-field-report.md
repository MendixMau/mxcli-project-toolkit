# Field report: 91 empty true/false workflow splits removed; a sub-workflow extraction spike

**From:** field project "three-app process hub" (Hub, Loans and Cards apps; anonymised), MendixMau
**Date:** 2026-11-04
**Kind:** learning + bug (lint gap)
**Field evidence:** two runs, both with the artefacts on disk in the field project: an audit of `mxcli describe workflow` output before and after (2026-11-03), and a spike on a copy of the Cards app (2026-11-02). Mendix 11.13 / 11.15, mxcli v0.28.0.
**Proposed target:** promoted in this PR: preflight STOP row 34, `learned-workflow-patterns.md` §16, `workflow-structure-rules.md` §1. **Still open:** the lint rule in part 3.

---

## 1. Empty true/false splits: what we did and what it measured

**Problem.** A workflow `call microflow` whose callee `returns Boolean` gets a true/false split.
The agents kept writing callees that end in `return true` and calling them with
`outcomes true -> { } false -> { }`. On the canvas that reads as a decision with an unhandled
failure path. It was flagged in review repeatedly and came back with every generation round,
because no gate looks at it (same finding as `2026-10-02-workflow-antipatterns-bug.md` §1, a
different project).

**Audit.** Count, per workflow, the call-microflow steps whose outcomes are *all* empty, from
`mxcli describe workflow` dumps:

| Workflow (anonymised) | Before | After |
|---|---|---|
| Hub: task router | 33 | 0 |
| Hub: reusable call-and-wait child | 5 | 0 |
| Hub: dispute process | 38 | 0 |
| Loans: early payoff | 4 | 0 |
| Cards: card disbursement | 11 | 0 |
| **Total** | **91** | **0** |

**Change.** Every such callee now returns nothing, and its call site carries no Boolean outcomes
(describe renders it as `default -> { }`). Kept on purpose: splits where one branch does real
work (send-request / needs-attention in the call-and-wait child, the Loans "get data" enum and
"Waiting for the back office?", the Cards route and system-step splits). The Cards decisions
got readable captions at the same time.

**Gates after the change** (verbatim summary lines from the run logs):
- happy-path demo run: `SUMMARY steps passed 30/30  failed 0  gaps 0`
- unhappy-path demo run: `[unhappy] SUMMARY steps passed 27/27  failed 0  gaps 0`
- card gate: 13/0 + 8/0 PASS/FAIL = 21/21
- docker `mx check` on all three apps: `The app contains: 0 errors.`

**What did not go cleanly:**
- A plain grep for `true -> { }` is the wrong metric. The "after" dumps still contain 13 such
  lines, and all 13 are correct: the *other* branch does something. Count only splits whose
  every outcome is empty.
- Loans: 5 workflow instances went `Incompatible` after the redeploy (3 seed cases, cleared by
  the nightly reseed; 2 orphans of deleted test cases, not fixed). Same defect family as
  BUG-141: changing outcomes under a paused instance.
- The audit was an ad-hoc script in the field project, not a toolkit instrument. Hence part 3.

## 2. Sub-workflow extraction spike: what worked and what did not

Goal: shorten a 54-activity parent (Cards disbursement) by moving its credit-check-and-contract loop
into a child workflow with the same context entity. Done on a copy, own ports and database.
About 95 active minutes, about 25 of them on model changes.

**Worked:**
- The first attempt (a full restatement of the parent) was refused by the exec guard: 10 stored
  `end workflow`, 7 declared. Nothing was written. Redone with `alter workflow` (insert call +
  decision, drop the 4 loop activities): `mxcli check` passed, mxbuild 0 errors.
- Parent 54 → 36 activities, child 21. All 40 task names, captions, outcomes and timers
  identical; one new end, "Stopped in credit check and contract".
- A "close case" inside the child ends the parent through the decision after the call.

**Did not work / risks found** (suite, pass/fail/invalid):

| Test | Baseline | After extract | After task-lookup fix | After admin fix |
|---|---|---|---|---|
| workflow-arm | all pass | all pass | all pass | all pass |
| J-06 | 68/0/4 of 72 | 27/2/3 of 32 | 67/1/4 of 72 | 60/8/4 of 72 |
| J-11 | 42/0/0 of 42 | 13/1/1 of 15 | 41/1/0 of 42 | 41/1/0 of 42 |
| called-off parent | 12/12 | 12/12 | 12/12 | 12/12 |
| hand-off into child (simulated) | 9/9 | 2/9 | 9/9 | 9/9 |

- **Incompatible instances:** on the first start, 5 of 7 waiting instances (all those inside
  the moved loop) went `Incompatible`. The case page still showed them at their step, with no
  sign they were stuck.
- **One-workflow-per-case code:** the open-task lookup for the cross-app hand-off broke
  (9/9 → 2/9) until it looked tasks up by case. It now copes with at most 2 running workflows
  per case. Instance-counting tests fail ("got 2, expected 1") although parent + child is right.
- **Admin page:** error dialog before the fix. After it, each case in the loop is listed twice
  (parent and child, unlabelled) and the counters double-count.
- **Unexplained:** J-06 60/8/4 after the admin fix: 7 extra failures on one tab, judged flaky
  by the agent, not rerun. Not proven either way.
- **Not checked:** how Studio Pro renders the call + decision.
- `call workflow` has no outcomes, and `jump to` cannot cross the boundary. The per-step
  technical-error pattern (retry step / close case, 7 copies) therefore cannot move into a
  child. Only the business loop could.

Verdict recorded in the field project: do it later, with a drain-or-migrate plan, not before a demo.

## 3. Still open: a lint rule (not in this PR)

> **MXTK-WF001 (warning):** a workflow `call microflow` activity with ≥ 2 outcomes whose bodies
> are all empty. Message: "Callee returns a value nobody branches on: make it return nothing
> and drop the outcomes."

Golden inputs exist: the before/after describe dumps of the 5 workflows above (anonymise the
module names before copying them in). Expected result: 91 hits before, 0 after, 0 on the 13
one-sided splits. Per `CLAUDE.md` → "Shipping an instrument", it still needs both layouts, both
platforms and a cited field run.
