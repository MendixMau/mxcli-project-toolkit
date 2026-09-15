# mxlabs mxcli v0.22.0 / `main` HEAD retest — workflow constructs only (2026-09-15)

**Scope: workflow only.** This is not a full re-probe of every open bug (that is a separate,
larger exercise) — it is the field verification of the seven items
`mxlabs-v0.22.0-upstream-delta-2026-09-15.md` flagged `EXPECTED CLEARED — PENDING PROBE`, run
the same day the delta doc was written. Every verdict below has a known-bad control in the same
batch, per `workflow-structure-rules.md` §11's discipline.

## Gate 0 — binaries tested

Two binaries, two disposable projects — never mixed against the same `.mpr`:

- **`v0.22.0` (release tag)**, built from source (`git checkout v0.22.0`, ANTLR 4.13.2, Go
  1.26.6). Project: `TestApp` (Mendix 11.13.0), scaffolded by `mxcli new` on this binary.
- **`main` HEAD, `7b42100d` (2026-09-15)**. Project: `TestApp2` (Mendix 11.13.0), separate scaffold.

**Correction to the delta doc:** the `nightly` *tag* (`9905dd7c`, 2026-09-14) is itself a day
stale relative to `main` and does **not** contain `end workflow` or the signature checks —
confirmed by `git merge-base --is-ancestor 598dddc0 nightly` returning false, and by the syntax
error `mismatched input 'END' expecting '}'` when probed on a binary built from that tag. A
project pulling "nightly by tag name" would not get either fix; `main` HEAD is required. The
delta doc's release-boundary table now needs a third column, or the `nightly` label dropped in
favor of "main HEAD, `<sha>`, `<date>`".

Both binaries downloaded MxBuild natively (no Docker daemon in this container; resolved the same
way the v0.21.0 retest did) — every verdict below marked **native 0 errors** rests on a real
`mx check`, not a mocked one.

## Verdicts

### BUG-76 — **RECONFIRMED FIXED on v0.22.0.** DECISION spelling pincer closed as designed

`MDL-WF03` now requires the qualified `Module.Enumeration.Value` form and refuses the bare form
at `check`, before `exec` can write it. Three-shape batch, one known-bad control each:

| Shape | Result |
|---|---|
| qualified outcomes + `''` empty outcome, on a `NOT NULL` enum attribute | `check` pass → `exec` writes → `describe` round-trips clean |
| bare outcomes (`'Approved'`) — **known-bad control** | `check` refused, `MDL-WF03`, names both bad outcomes |
| qualified outcomes, **no** `''` empty outcome, same `NOT NULL` attribute — **known-bad control** | `check` refused, `MDL-WF06`/CE6686, states explicitly "a required (not null) attribute does not exempt it" |

**Verdict: FIXED.** Recommend archiving BUG-76's STOP rule for v0.22.0+ and replacing
`learned-workflow-patterns.md` §8 Warning 1's `--no-check` workaround with "qualified spelling,
plain `mxcli check`, no workaround needed."

### BUG-121 — **FIXED at build-storage and native-check level on v0.22.0. Runtime half not yet verified (see hand-off).**

A 2-leg `PARALLEL SPLIT`, no manual terminator step, no patcher run:

- `check` pass, `exec` writes.
- Raw `.mxunit` (via `mxcli bson dump` / `strings`) contains
  `Workflows$EndOfParallelSplitPathActivity` **once per path**
  (`EndOfParallelSplitPath`, `EndOfParallelSplitPath2`) — written by the builder alone, with no
  patcher run. This is the exact defect BUG-121 reported: the marker was absent entirely on
  v0.20.0/v0.21.0.
- **Native `mx check`: 0 errors.**

**What is still open:** the live-run oracle. BUG-121's own record states a build-clean model
previously opened **zero tasks at runtime** — the marker's presence in storage and a clean
`mx check` are necessary but were never sufficient on their own for this specific defect (that
is the whole lesson BUG-121 taught). A real verdict needs a running instance with concurrent
tasks counted. See "Hand-off: the live-run step" below.

**Verdict: PENDING the live-run confirmation, otherwise clean at every gate that can run without one.**

### Forward `JUMP TO` a real activity — **RECONFIRMED already-fixed, since v0.21.0**

`check` pass, `exec` writes, native `mx check`: **0 errors**, forward-jumping to a real later
activity. Known-bad control: a **dangling** jump (`JUMP TO nowhere` where no such activity
exists) is refused pre-write, `MDL-WF05`, and the message correctly identifies the fault ("this
is written as a jump to itself") and lists valid targets. This is precisely our own v0.21.0
field run's CE6681 fault, now caught at `check` instead of at native build.

**Verdict: our coverage row has been stale since 2026-09-06 (upstream fix `825873d6`, already in
v0.21.0). No project on v0.21.0+ needs the "forward jump = redesign to backward" workaround.**

### Workflow-body `annotation` — **direction correction confirmed: refused, not hand-add**

A standalone `annotation` statement in a workflow body: `check` refused (`MDL-WF04`), `exec`
also refused with nothing written. The message is explicit: it would produce a model Mendix
cannot load at all.

**Verdict: our "hand-add" row was pointing the wrong way.** Correct guidance: remove the
statement, keep the note as an MDL comment (`-- ...`), or add a real annotation in Studio Pro
after the last scripted rewrite.

### `end workflow` — **CONFIRMED present and correctly gated, on `main` HEAD only**

Three-shape batch matching the upstream measurement table exactly:

| Placement | Result |
|---|---|
| closing a user-task outcome | `check` pass → `exec` writes → `describe` round-trips (`end workflow comment '...';`) → native `mx check`: **0 errors** |
| under a parallel-split path — **known-bad control** | `check` refused, `MDL-WF08`/CE1844, names the reason and the fix |
| an activity after `end workflow` in the same block — **known-bad control** | `check` refused, `MDL-WF09`/CE6671 |

**Verdict: FIXED, on `main` HEAD (`7b42100d`) — NOT on the `v0.22.0` tag and NOT on the stale
`nightly` tag.** A project needs `main` specifically.

### Task-page and targeting-microflow signatures — **CONFIRMED caught pre-write, `main` HEAD only**

Both of our own v0.21.0 field-run findings, reproduced as their own known-bad controls and now
refused at `check --references` before `exec` can write anything:

| Shape | Result |
|---|---|
| task page taking only the context entity, no `System.WorkflowUserTask` param — our v0.21.0 CE7412 finding | `check --references` refused, names CE7412 verbatim and the exact fix |
| targeting microflow taking one parameter, missing `System.Workflow` — our v0.21.0 CE6677 finding | `check --references` refused, names CE6677 verbatim and the exact fix |
| targeting microflow with the correct two-parameter signature | `check --references` pass — control pair, probe not blind |

`mxcli syntax workflow.user-task.targeting` now states the signature, confirms **order is
free** and a generalization of the context entity is accepted (looser than our §11's "in that
order"). `mxcli syntax workflow.multi-user-task` topic confirmed present.

**Verdict: FIXED, `main` HEAD only.** The build-time-only failure mode our v0.21.0 briefing
called out ("a green CLI check is not evidence for workflows") no longer applies to these two
specific shapes on `main`.

### NOT run — needs a live Studio Pro / MCP, out of scope for a container probe

The `create or modify` rewrite guard (refuses to reset a hand-added *On created* handler, event
handlers, or a multi-user completion rule) needs a workflow actually configured through Studio
Pro first. Confirmed present by reading `mdl/executor/cmd_workflows_write.go` at `main` HEAD
(cited in the delta doc); not independently probed here.

## Hand-off: the live-run step for BUG-121

Everything mechanical is done and green. What is missing is exactly what BUG-121's own history
says cannot be skipped: a running instance.

1. Build the `WF_Split` shape (or reuse the field project's split) on **v0.22.0 or later**.
2. Start an instance so the split is reached.
3. Count **concurrent open tasks** at the split — BUG-121's signature failure was consecutive
   *End of parallel split path* records with **no task between them**; the fix is confirmed only
   if every leg opens its own task.
4. If (and only if) that holds: archive BUG-121, retire `bin/wf-add-path-terminators.py` from
   the build plan for projects on v0.22.0+, and update
   `learned-workflow-patterns.md` §23 to a historical note.
5. **Separately**, if any project has a workflow with a split **written by a pre-v0.22.0
   binary**: run `create or modify` over it once to add the markers to the existing model.
   Upstream states existing **instances** are not migrated by this — only the definition.

## Sources

- Probe scripts, raw output, and the full confirmed-results table:
  `wf-probe/` and `wf-probe-nightly/` scratch projects (not committed — disposable, no client
  data, per this repo's scratch-project convention).
- `mxlabs-v0.22.0-upstream-delta-2026-09-15.md` — the source reading this retest verifies.
- Upstream: `mendixlabs/mxcli` tag `v0.22.0` and `main` HEAD `7b42100d` (2026-09-15).
