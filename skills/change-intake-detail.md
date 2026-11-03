# Change Intake — Detail: Why, Worked Example, Apply, Prove, Gate Check

**Applies to:** any mxcli project with a `PROJECT.md` (migration, requirements-driven, greenfield, change an existing app), from Stage 2 onward.
**Purpose:** the on-demand half of `change-intake.md`. That file is the baseline core every lead and ba-agent session reads. Read this one to apply or prove a change request, when a class, size or status is unclear, or to explain the `Change log:` gate line.
**Owns:** nothing: `change-intake.md` owns the `## Change log` table and the classes, sizes and statuses. `conversion-runbook.md` §3b (drift-sync) is this loop's BRD-flush step.

**Trigger:** any message asking for something different from the artifacts or the build, typed, pasted, relayed or said over a screenshot. Not a trigger: a gate answer (`interview-protocol.md`) or a review finding (`finding-disposition.md`).

---

## Why this exists: the change went into MDL, every time

Across 12 mid-build changes on real projects:

| What happened | Count |
|---|---|
| Change applied straight in an MDL script | 12 of 12 |
| BRD, build plan or wireframe updated for it | 0 of 12 |
| `[sync: … UNSYNCED]` drift markers ever written | 0 |
| One screenshot-driven fix: rounds before it stuck | 4 (it regressed twice, and every gate was green both times) |
| One settled entity change sent through ba-agent twice and architect-agent once | ~270k tokens for a handful of document edits |

The drift gate passed on all 12, because it looks for a marker and nobody wrote one. A missing marker looks the same as nothing to sync. The second failure is the opposite one: too much ceremony for a change that was already settled. This skill fixes the first with a row you write *before* the edit. It fixes the second by scaling the ceremony to the size of the change.

### Wrong vs right, same request

The user, looking at the running app: *"The customer form also needs a VAT number."*

**Wrong (what happened 12 times):**
```
Sure — adding it now.
  → mdlsource/0412-customer-vat.mdl   ALTER ENTITY + ALTER PAGE, exec, green
PROJECT.md: no row.  F003.brd.json: no VAT.  wireframe: no field.  build plan: no step.
Two sessions later a BRD-driven rebuild of the Customer page drops the field. Every gate is green.
```

**Right:**
```
Logged CR-07: requirement, small → F003.brd.json + Customer_Edit, then MDL.
  1. PROJECT.md ## Change log: CR-07 row, status agreed (user typed it, small)
  2. F003.brd.json: VATNumber attribute + its validation, a one-leaf edit by the lead
  3. Customer_Edit page built → before/after screenshot pair in design/ui-reviews/
  4. ./bin/exec.sh --cr CR-07 mdlsource/0412-customer-vat.mdl
  5. Journey customer-edit asserts the field; CR-07 → proven, Closed-by: <commit>, journey customer-edit
```
The extra cost is two lines of text and one BRD leaf. The next agent that reads F003 gets VAT.

---

## Step 1 — Capture: one row, before any edit

Append a row to `PROJECT.md` → `## Change log` (the one decision register; no separate file). If the section is missing, `bin/sync-project.sh <project-root>` adds it.

```
| CR | Date | Source | Verbatim ask | Class | Size | Entry artifact | Status | Closed-by |
|---|---|---|---|---|---|---|---|---|
| CR-07 | 2026-10-13 | user | The customer form also needs a VAT number | requirement | S | F003.brd.json | agreed | |
```

- **CR**: `CR-` plus the next number. Never reuse a number.
- **Source**: `user`, or the stakeholder's name and role as the user gave it (`stakeholder (finance lead)`).
- **Verbatim ask**: the words as typed, not your summary. Your restatement goes in the reply (Step 3). Escape a pipe as `\|`.
- One ask, one row. "Also make the button blue and add a VAT field" is two rows.

## Step 2 — Classify and size

**Class → entry artifact.** The entry artifact is the highest layer the change alters. It is never the MDL.

| Class | What changed | Entry artifact |
|---|---|---|
| `requirement` | what the app must do or store | the BRD (`*.brd.json`), plus a decision row if it settles a choice |
| `decision` | a choice recorded in `PROJECT.md` | a **new** `CONFIRMED` Decisions row whose Notes say `supersedes D-NN`, or `supersedes <stage>: <old decision, first words>` if the register does not number its decisions. The old row's Status becomes `SUPERSEDED by CR-NN`. Its text is never edited |
| `structure` | module boundary, entity ownership, integration, security model | `architecture/` blueprint or the module brief |
| `visual` | how a page looks or flows | the wireframe while the page is unbuilt. Once it is built: a before/after screenshot pair in `design/ui-reviews/`, and the wireframe gets a "BUILT, see ui-reviews" stamp instead of upkeep |
| `impl` | how something is built, with no behaviour change | none: a regression journey only |
| `bug` | the build does not do what an artifact already says | none: the artifact was right. Add a regression journey that fails before the fix |

**Size.**

| Size | Test (all must hold for S) |
|---|---|
| **S** | one artifact per layer, one module, contradicts no `CONFIRMED` decision |
| **M** | several artifacts in a layer, or 2+ modules. Still contradicts nothing `CONFIRMED` |
| **L** | a new feature or module, or it contradicts a `CONFIRMED` decision |

## Step 3 — Who is asked, and when (ask, then stop)

Asking follows `interview-protocol.md` §3. On Claude Code use `AskUserQuestion`. On any other agent use numbered markdown, as §3 "Asking on a non-Claude agent" describes. Either way, end the turn and wait.

| Situation | Ask? | Status path | Who edits |
|---|---|---|---|
| **S**, typed by the user themselves | **No question.** Reply with a one-line receipt: `Logged CR-07: visual, small → wireframe + page` | straight to `agreed` | the lead, inline. No subagent |
| **M** | Restate it in your reply (`refined`). Then **one batched question at the next module gate**: "Apply these N changes? CR-08, CR-09, CR-11" | `open` → `refined` → `agreed` at the gate | one `ba-agent` pass at the gate for the whole batch |
| **L**, or it contradicts a `CONFIRMED` decision | **Ask and stop now**, before anything is built: the proposal, two named options, your recommendation | `refined` → `agreed` / `rejected` | re-enter the pipeline at the owning stage for that slice (Stage 2 for a new BRD, Stage 3 for structure) |
| Stakeholder or relayed feedback, any size | Not on its own. It stays `open` until the user agrees or rejects. All such rows are surfaced together at the next gate | `open` → `agreed` / `rejected` | as for its size, after agreement |
| The meaning is ambiguous | **One** "A or B?" question. It is the only mid-stream interruption this skill allows | `open` until answered | — |

A row the user rejects is kept, with Status `rejected — <reason>`. A rejected ask that nobody can find gets asked for again.

## Step 4 — Apply: top down, as far down as needed

1. Edit the entry artifact (Step 2).
2. The BRD stays the source of truth. The module brief's `### Build steps` table is updated, with a CR-tagged row such as `CR-07-1`, for every CR that touches that module's build steps, screens, access or rules, so `context-pack.sh <Module> CR-07-1` finds it. Every CR that adds work also gets a build-plan row tagged `CR-NN`: **S** one row in the module's own phase, **M** and **L** wait for a change round (a follow-up adds the full "unplanned changes" view and change rounds). An agreed CR that is not built yet is *waiting*. Surface it at session start and at module close; never let it drop out of sight.
3. Then write the MDL and run it with `./bin/exec.sh --cr CR-NN <script>`. The tag lands in the BUILD-LOG detail cell, and that BUILD-LOG row is the evidence for Step 5.
4. Set the status to `applied` and fill Closed-by with the commit that holds the artifact edit.

**Owners**, expanded. The source is `change-intake.md` → Owners; this table only spells it out (it replaces the split that `agent-roles.md` lanes contradicted):

| Duty | Owner |
|---|---|
| Write and update the CR row and any `PROJECT.md` decision row (the "mark") | the **lead**, the session talking to the user. Helpers report a change to the lead. They never write `PROJECT.md` from the build lanes |
| Flush a BRD or a module brief (an M batch, or any deferred `[sync: … UNSYNCED]` marker) | **ba-agent** |
| Flush a wireframe, `design/`, or `architecture/` | **architect-agent** (it owns `design/`) |
| S edits to any of the above | the **lead**, inline |

When the lead edits a BRD inline in the same session, no `UNSYNCED` marker is needed, because nothing was left unsynced. Use the marker (runbook §3b) only when a flush is deferred.

## Step 5 — Prove

Set the status to `proven` once Closed-by cites the evidence: the commit, plus the journey, test or screenshot pair that shows the change working. For a `bug` or an `impl` row, that is the regression journey. Never weaken or delete an existing journey to make a change pass. That needs its own CR row, which the user agrees to.

---

## The mechanical check (warn-only for now)

`bin/gate-check.sh` prints a `Change log:` line next to `Drift (BRD sync):` and a row on the dashboard:

```
Change log: WARN — 2 of 6 change request(s) not yet applied (open 1, refined 0, agreed 1); 1 applied/proven with no Closed-by — warn-only (skills/change-intake.md)
  CR-02  applied  no Closed-by evidence — Orders overview should be a gallery, not a grid
```

It counts `open`, `refined` and `agreed` rows, plus `applied`/`proven` rows with an empty Closed-by. It also flags any status outside the six words. It **never blocks.** It becomes blocking, for `agreed` rows still unapplied at a module gate, once two projects have run with it and its counts matched a hand count of their change logs. Until then a false FAIL would cost more than the WARN does. What it cannot see is an ask that was never logged: `0 change requests logged` is not proof that nothing changed. That gap is closed by the completion criteria below, not by the script.

When nothing is owed the line is `PASS`, in one of two forms:

```
Change log: PASS — 0 change requests logged (a change made with no row is invisible here — log every ask first, skills/change-intake.md)
Change log: PASS — 6 change request(s); every one applied with evidence, proven, or rejected
```

The first is not evidence that nothing changed (see above). The second is what `change-intake.md` → Done when means by "reads `PASS`".

## Checking each Done-when line

- **Asks → rows:** every change the user asked for in this session has a CR row. N asks give N rows. Count them in the transcript before you claim the module gate.
- **No MDL before the row:** every `mdlsource/` script written for a CR was executed with `--cr CR-NN`. Its BUILD-LOG row shows `cr: CR-NN`.
- **Gate line:** before a module gate, `Change log:` reads `PASS` (`N change request(s); every one applied with evidence, proven, or rejected`, or `0 change requests logged`), or every row it still lists under a `WARN` is named in your gate message with a reason.
- **Evidence:** every `applied`/`proven` row has a Closed-by. Zero rows reported "no Closed-by evidence".
- **Superseded, not edited:** every `decision` row has a new Decisions row. The old row's Status reads `SUPERSEDED by CR-NN`.
