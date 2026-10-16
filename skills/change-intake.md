# Change Intake — Log Feedback Before You Build It

**Applies to:** `PROJECT.md` projects.
**Purpose:** log a change before any edit, then edit the highest artifact it alters; MDL last. `change-intake-detail.md`.
**Trigger:** the user or a relayed stakeholder wants anything to differ (not a gate answer or review finding).

Wrong: "Sure, adding it now" → MDL, no row.
## Row first, in `PROJECT.md` `## Change log`

Columns: CR-NN (never reused), Date, Source, Verbatim ask (`\|` for a pipe), Class, Size, Entry artifact, Status, Closed-by. One ask, one row; status: open → refined → agreed → applied → proven, or `rejected — reason`.

## Class → entry artifact (never the MDL)

- **requirement** → BRD.
- **decision** → new `CONFIRMED` row `supersedes D-NN`; old row `SUPERSEDED by CR-NN`, text untouched.
- **structure** → `architecture/` or brief.
- **visual** → wireframe while unbuilt; once built, before/after pair in `design/ui-reviews/`.
- **impl**, **bug** → regression journey (failing first for a bug).

## Brief and waiting changes

BRD stays the source of truth. A CR touching a module's build steps, screens, access or rules gets a `CR-07-1` row in that brief's Build steps and a build-plan row `CR-NN` (S: module's phase; M/L: change round). Agreed, unbuilt CRs are *waiting*: say so at session start and module close.

## Size → ask (ask, then stop)

- **S** (one artifact per layer, one module, no `CONFIRMED` clash), user-typed: no question, receipt `Logged CR-07: S → wireframe`, `agreed`, lead edits.
- **M** (several artifacts or modules): restate (`refined`); one batched gate question, one ba-agent pass.
- **L** (new feature or module, or contradicts `CONFIRMED`): ask now (two options, one recommended); re-enter that stage.
- **Relayed**: `open` until a gate asks. **Ambiguous**: one "A or B?".

## Owners

Lead: CR/decision rows, S edits; helpers never write `PROJECT.md`. ba-agent: BRDs, briefs. architect-agent: wireframes, `design/`, `architecture/`.

## Done when

- N asks → N rows; decisions superseded, not edited.
- Every CR script ran via `./bin/exec.sh --cr CR-NN`.
- At a module gate, `Change log:` reads `PASS` or each listed row is named; none lack Closed-by evidence.
