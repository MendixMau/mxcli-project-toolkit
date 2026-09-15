# mxcli v0.22.0 — upstream delta, read from source. NOT a retest. (2026-09-15)

**What this document is.** A reading of `mendixlabs/mxcli` at tag `v0.22.0` (2026-09-14) and at
`main` HEAD `7b42100d`, against this toolkit's workflow record, which is written entirely against
**v0.21.0**. Every row below cites a commit, a changelog passage, or a grammar rule read in the
upstream tree.

**What this document is NOT.** A probe. No binary was built, no `.mpr` was written, no `mx check`
was run, no live instance was started. There is **no known-bad control** in anything below, which
is the one thing this toolkit requires before a coverage row changes
(`skills/workflow-structure-rules.md` §11). So:

> **UPDATE 2026-09-15, same day: §4's probe plan has now been RUN**, with known-bad controls,
> against v0.22.0 (tag) and `main` HEAD (`7b42100d`). Six of the seven rows below moved from
> `EXPECTED CLEARED — PENDING PROBE` to `CONFIRMED`; BUG-121 confirmed at build/native-check
> level with the live-run oracle still open. See
> [`mxlabs-v0.22.0-retest-2026-09-15.md`](mxlabs-v0.22.0-retest-2026-09-15.md) for the full
> results and `mxcli-bugs.md`'s BUG-76/BUG-121 banners for the archival status. The table below
> is left as originally written — the predictions — for anyone comparing prediction to result.

The value of a desk delta is that it tells the probe **what to aim at** and stops a project
carrying a workaround upstream has already removed. It is not evidence.

---

## 1. The release boundary — this is the part that bites

`v0.22.0` was tagged (`e771f490`, 2026-09-14) and then **more workflow work merged to `main`
after the tag**. Two of the three things this toolkit most wanted are on the wrong side of it.
**Correction, confirmed by probe 2026-09-15: the `nightly` tag (`9905dd7c`, 2026-09-14) is
ALSO on the wrong side** — it is a day stale relative to `main` and does not contain `end
workflow` either (`git merge-base --is-ancestor 598dddc0 nightly` is false; confirmed by a
parse failure on a binary built from that tag). Say `main` HEAD by commit, not "nightly" by
tag name.

| Ships in the `v0.22.0` **release binary** | On `main` / `nightly` **only** |
|---|---|
| parallel-split path terminators (`be28539b`) | `end workflow` statement (`598dddc0`) |
| boundary-event path terminators (`6d05f3f8`) | task page / targeting microflow signature checks (`f0d9a928`, `58a20ca0`) |
| `MDL-WF03` qualified decision outcome (`b9bbd6cc`) | `create or modify` rewrite guard (`361e96e1`) |
| `MDL-WF06` enum decision empty outcome (`0d769c26`) | `describe` boundary-event and nested-End fixes (`2e5a06da`) |
| `ALTER` insert aimed at the wrong activity kind refused (`1014f6f7`) | the bogus "move it before itself" hint (`33c6130c`) |

**Consequence for a project plan.** `mxcli --version` reporting `v0.22.0` does **not** mean
`end workflow` parses. A project that needs it is on a nightly build, which is a different
support conversation. Record the binary, not the release name — `skills/workflow-structure-rules.md`
§11's opening rule, and this is exactly the case it was written for.

---

## 2. Our open items, against upstream

| Our record | Upstream | Verdict |
|---|---|---|
| **BUG-121** — `PARALLEL SPLIT` paths written with no terminator, no task ever opens | `be28539b`, in **v0.22.0**. Every path now ends with `EndOfParallelSplitPathActivity`, empty paths included, from the builder and from **both** `INSERT PATH` mutators; both writers serialize it; the modelsdk reader reads it back typed; `describe` still omits it. Upstream measured it on 11.14.0 by reading `system$workflowactivity` with the marker as the only variable. Their first cut named every marker the same and hit **CE0495 "Duplicate name"**, caught only by mxbuild — now covered by `TestDeduplicateNamesEndOfPathMarkers` | **EXPECTED CLEARED — PENDING PROBE.** Note the upstream instruction: **a workflow already written by an affected version must be re-run through `create or modify` to pick up the markers, and existing instances are not changed** |
| **BUG-76 / mendixlabs/mxcli#1031** — `DECISION` outcome spelling pincer | `b9bbd6cc`, in **v0.22.0**, plus #1065. `MDL-WF03` now **requires** the qualified `Module.Enum.Value` form — the jaw that accepted the bare label and produced an unloadable `.mpr` is closed as an *error*, and `exec` refuses a script with errors, so the corrupting write can no longer happen | **EXPECTED CLEARED — PENDING PROBE.** If it holds, the `exec --no-check` workaround in `learned-workflow-patterns.md` §8 Warning 1 **inverts**: qualified is now the required spelling, and `--no-check` becomes the wrong advice rather than the necessary one |
| **forward `JUMP TO` → CE6681** | `825873d6`, already in **v0.21.0**. Root cause was that the jump activity took its *target's* name, so name-based resolution could resolve the jump to itself; deduplication renames the *second* activity with a given name, so **forward order was the broken case and backward order accidentally worked**. Jumps are now named `JumpTo`/`JumpTo2` | **OUR ROW IS STALE ALREADY.** The v0.21.0 field run's CE6681 was a *dangling* jump (no target exists) — a different, legitimate fault, now refused at check time by `ValidateWorkflowJumpTargets`. Probe forward-jump-to-a-real-activity on v0.21.0 **and** v0.22.0 |
| **"no End event, anywhere"** — the one grammar gap | `598dddc0`, **main only**. `end workflow [comment '<caption>'];` is legal in any `{ }` block. The top-level body is its own grammar rule and deliberately excludes it, because there the words close the body *and* are the main flow's End, which is the one place Mendix refuses an explicit End (CE6671) | **EXPECTED CLEARED on nightly — PENDING PROBE.** See §3 for the placement rules, which are the interesting part |
| **task page / targeting microflow signatures undocumented** | `f0d9a928` + `58a20ca0`, **main only**. Both are now **validated** by `check --references`, not merely documented, for `CREATE WORKFLOW` (nested and multi-user tasks included) and `ALTER WORKFLOW`. `mxcli syntax workflow` gains a `multi-user-task` topic and both signatures | **EXPECTED CLEARED on nightly — PENDING PROBE.** Upstream credits "a team briefing on building workflows from MDL" for both. Three rows are *looser* than our table states — see §3 |
| **workflow-body annotations / mxcli#1007** | Grammar has had `annotation` since `40b74017` (v0.18.0), but `exec` and check now **refuse** it as `MDL-WF04`: a standalone annotation lands in the activity flow, which accepts only flow elements, so the written `.mpr` cannot be **loaded at all** — Studio Pro will not open the project and `mx check` dies before validating anything | **NOT a capability fix — a refusal.** Our "hand-add" row is wrong in direction: the guidance is **remove it and keep the note as an MDL comment (`-- …`)**, or add it in Studio Pro *after* the last scripted rewrite |
| **event sub-process · interrupting boundary timer · boundary event on notification · multi-user decision rule · user-task *On created* · AI agent task** | Still absent from `mdl/grammar/domains/MDLWorkflow.g4` at HEAD — read directly: `workflowBoundaryEventClause` admits `{TIMER, INTERRUPTING TIMER, NON INTERRUPTING TIMER}` and nothing else, and there is no rule for a sub-process, a completion rule, an on-created handler or an agent task anywhere. **But** `361e96e1` (main only) makes `create or modify` and `REPLACE ACTIVITY` **refuse** a workflow that holds any of them, listing every reason at once | **STILL HAND-ADD — and that is now safe.** This is the bigger win than it looks: the standing regression risk (a later scripted rewrite silently resetting an on-created microflow to `NoEvent`, event handlers to empty, a completion rule to Consensus-on-first-outcome) becomes a refusal instead of a silent reset |
| **interrupting boundary timer** specifically | Was hand-add for us because its path must end and MDL had no end-activity. `6d05f3f8` (v0.22.0) writes `EndOfBoundaryEventPathActivity` on every boundary-event path, and `end workflow` (main) is legal at any depth inside an interrupting path | **EXPECTED CLEARED — PENDING PROBE.** Upstream measured the old behaviour: interrupting = `CE0105` at build, non-interrupting = builds at 0 errors and then **the runtime refuses to start the application** (*"Expected the flow to end with an end event"*). Their own `mxcli syntax workflow boundary-event` example was one of the wrong shapes |

---

## 3. Two upstream measurement tables worth copying verbatim

Both are mxbuild measurements, one workflow per shape, verdict = the literal `mx check` line.
They are more precise than anything we have, and three rows **contradict a reading of the error
text** — which is why they matter.

**`end workflow` placement** (`mdl/executor/validate_workflow_end.go`, mxbuild 11.13.0):

| Placement | Verdict |
|---|---|
| closing an outcome / decision branch / call-microflow outcome | 0 errors |
| closing an **interrupting** boundary path, at any depth | 0 errors |
| under a **parallel split**, at any depth | **CE1844 — `MDL-WF08`** |
| under a **non-interrupting** boundary path, at any depth | **CE1844 — `MDL-WF08`** |
| an activity after End in the same block | CE6671 — `MDL-WF09` |
| every path of an activity ends, then another activity follows | CE6689 — `MDL-WF10` |
| `return;` in a workflow body | refused, `MDL-WF11`, pointing at `end workflow` |

This **confirms `workflow-structure-rules.md` §4** exactly as written: a split path ends *locally*
and can never end the instance. So the split-path terminator and the End event are two different
mechanisms, not one gap — our briefing framing ("one grammar gap behind both runtime faults")
should be corrected: the split fault is a **writer** defect, the branch-End fault was a **grammar**
gap, and only the second one `end workflow` solves.

**Task page and targeting microflow signatures** (`mdl/executor/validate_workflow_task_signature.go`,
`MDL-WF07`, mxbuild 11.13.0):

| Shape | Verdict |
|---|---|
| task page, no parameters | CE7410 |
| task page, only a context-entity parameter (multi-user task too) | CE7412 |
| task page, `WorkflowUserTask` **+ an extra parameter** | **0 errors** |
| targeting `(System.Workflow, Ctx)` | 0 errors |
| targeting `(Ctx, System.Workflow)` | **0 errors — order is free** |
| targeting one parameter, none, or a third | CE6677 |
| targeting `(System.Workflow, <generalization of Ctx>)` | **0 errors** |
| targeting `(System.Workflow, <specialization of Ctx>)` | CE6677 |

Our §11 states the targeting signature as "TWO parameters … **in that order**". Upstream measured
order as free, and a generalization as acceptable. Our statement is *safe* but over-tight — keep
it as the recommendation, drop the "in that order" as a rule.

---

## 4. Probe plan — what a real v0.22.0 retest must run

Same discipline as the v0.21.0 round: disposable project copies, native `mx check` on every
verdict, **and a known-bad control in every batch**.

| # | Probe | Binary | Known-bad control in the same batch |
|---|---|---|---|
| 1 | `PARALLEL SPLIT`, 2 paths + 1 nested, **no patcher**, then a **live run counting concurrent tasks** | v0.22.0 | the same workflow written by a v0.21.0 binary (must still fail) |
| 2 | Re-run `create or modify` over a workflow written by v0.21.0 — do the markers appear? | v0.22.0 | — (this is the upstream-stated migration step; it is the one every existing project needs) |
| 3 | `DECISION` with a **qualified** outcome, no `--no-check`; then a **bare** outcome, which must now be refused at check | v0.22.0 | the bare form **is** the control |
| 4 | Forward `JUMP TO` to a real activity; separately a dangling `JUMP TO` | v0.21.0 **and** v0.22.0 | the dangling jump is the control |
| 5 | `end workflow` in a user-task outcome; under a split path (must be `MDL-WF08`); after another activity (`MDL-WF09`) | nightly | the split-path placement is the control |
| 6 | Task page with a context-entity-only parameter, and a one-parameter targeting microflow — both must now fail at `check --references`, before anything is written | nightly | a correct pair in the same script |
| 7 | `create or modify` over a Studio-Pro workflow carrying an on-created microflow — must refuse, not reset | nightly | the same workflow with no on-created handler (must proceed) |
| 8 | A standalone `annotation` in a workflow body — must be refused as `MDL-WF04` | v0.22.0 | — |

**Probe 1 and probe 2 are the ones that pay for the round.** Every project in this toolkit's
record that has a split is currently carrying `bin/wf-add-path-terminators.py` as a repeated
step in its build plan (`learned-workflow-patterns.md` §23), and that step does not retire until
probe 1 says so on the binary that project actually runs.

---

## 5. Sources

- `mendixlabs/mxcli` `CHANGELOG.md`, the `[0.22.0] - 2026-09-14` section.
- Commits: `be28539b`, `6d05f3f8`, `b9bbd6cc`, `0d769c26`, `1014f6f7` (in the tag);
  `598dddc0`, `f0d9a928`, `58a20ca0`, `361e96e1`, `2e5a06da`, `33c6130c`, `825873d6` (tag
  containment as stated in §1).
- Grammar read at HEAD: `mdl/grammar/domains/MDLWorkflow.g4`.
- Validators read at HEAD: `mdl/executor/validate_workflow_end.go`,
  `mdl/executor/validate_workflow_task_signature.go`, `mdl/executor/cmd_workflows_write.go`.
- Our side: `skills/workflow-structure-rules.md` §11, `skills/learned-workflow-patterns.md`
  §8/§18/§21–23, `bug-logs/mxcli-bugs.md` BUG-76 and BUG-121.
