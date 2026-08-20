# Field run — driving the whole pipeline on a real source to find out what the documents don't say

**Applies to:** the mxcli conversion toolkit itself, not to any customer project. A field run's
subject is the toolkit; the app it builds is the by-product.

**Purpose:** `tests/wave2/` tests mechanism — given a fixture directory, does `gate-check.sh` print
the right verdict. Nothing tests the thing the toolkit actually is: a body of written material that
has to carry an agent through real work. This skill is the method for finding out whether it does.

**Companion:** `improvement-register.md` (same append-and-count shape, applied to defects in a built
app rather than friction in the process); `measured-claims.md` (the positive-control discipline this
skill's control runs depend on); `close-the-loop.md` (nothing goes in two places).

---

## Why this exists

On 2026-08-19 a GitHub Copilot / Windows dry run of the toolkit surfaced six real defects: intake
bodies that read as accepted before anyone had answered them, a lint-rule clobber where
`init-project.sh` wrote rules before `wire-agents.sh` overwrote them, `AskUserQuestion` treated as
universally available, a triage rubric that could not see `.sql` or `.xlsx`, an intake template with
no single home, and a `sources/` folder nothing scaffolded.

**None of the 26 fixtures in `tests/wave2/` would have caught any of them**, and no fixture could
have. Each defect lived in the gap between what a document says and what a reader does with it. That
run was ad hoc and left no method behind. This is the method.

## What a field run is not

| | Answers | Verdict shape |
|---|---|---|
| `tests/wave2/` fixture | Does this script emit the right string? | Binary, deterministic |
| `bin/gate-check.sh` | Is this project's stage N in order? | Five verdicts, mechanical |
| **A field run** | **Does the written material carry a fresh reader through real work?** | **A friction log. Not pass/fail.** |

**Do not give a field run a pass/fail headline.** If the output is a green checkmark, the next run
gets optimised toward the checkmark, and the run stops being able to see anything. The artifacts it
builds are evidence, not the deliverable.

## The three roles, and why they are separate

**Driver.** Runs the pipeline in a fresh session with no memory of toolkit intent, reading the
toolkit as documents only. The driver is a witness, not a judge.

**Persona.** A sealed brief, written before the run by someone who is not the driver, answering the
gate questions in place of a human stakeholder.

**Grader.** A different session that never saw the run. Reads only the produced artifacts, the
friction log, the persona brief, and the exit-criterion output. Writes the run record.

The separation is the whole design. A session that both drives and grades will be generous with
itself, and — worse — will silently route around rough edges using context that a real first-time
reader does not have. The rough edges are the entire point of the exercise. A driver who is also the
author of the toolkit text under test cannot see the text; it can only see what it meant.

## The two assertion layers

### Layer 1 — hard invariants (mechanical, genuinely binary)

These are the only things a field run may state as pass/fail:

1. Every stage that ran produced its named artifact, per that stage's **owning skill file** — not
   per the runbook's summary row, which names highlights and not the full deliverable.
2. Every skipped stage has a register line in `PROJECT.md` with a reason.
3. `bin/gate-check.sh <project> N` verdicts match what the confirmed entry mode predicts.
4. No `ASSUMED` decision in `PROJECT.md` that was not preceded by an actually-asked question.

**These reuse `bin/gate-check.sh` as it stands. Write no new checker.** Per `skills-over-scripts.md`,
judgement belongs in a skill and code only fetches facts a reader cannot. And if `gate-check.sh`
cannot tell you something you need to know, **that is a finding about the toolkit**, not a licence to
build a second checker beside it. Log it and move on.

### Layer 2 — the friction log (the actual product)

Every point where the driver:

- had to work out something no skill wrote down,
- found two toolkit files disagreeing,
- knew what it needed and could not find where it was documented,
- hit a tool that errored or produced wrong output,
- found the extractor blind to structure that was plainly in the source,
- got a gate verdict that did not match reality,
- hit a gate question the persona could not answer,
- or did something other than what a skill said, for any reason.

## The friction log contract

**Written during the run, at the moment of friction. Never reconstructed afterwards.**

Retrospective friction logs are fiction. By Stage 4 the driver has forgotten the thing it worked
around in Stage 0 — and the things that get forgotten are disproportionately the small
undocumented-but-obvious-in-hindsight ones, which are exactly the class this method exists to catch.
A driver that reaches a gate with an empty log since the last gate should treat that as a prompt to
check whether it is logging at all, not as good news.

Lives at `<field-run-project>/friction-log.md`. Append-only. One row per event.

```markdown
| # | Stage | Class | What happened | What I did | Where it should have been written |
|---|---|---|---|---|---|
| 1 | 0 | undocumented | Coverage Matrix wants a row per extractable structure; nothing says whether a seed-data SQL file is one structure or two | Treated DDL and seed as one row | source-triage.md, Coverage Matrix section |
```

### Closed class vocabulary — do not invent a class per row

`improvement-register.md` already establishes why: a fixed vocabulary is what makes the cross-run
trend read possible, and free-text descriptions of what went wrong do not group into a count.

| Class | Means |
|---|---|
| `undocumented` | Had to work out something no skill wrote down |
| `contradiction` | Two toolkit files said different things |
| `not-found` | Knew what was needed; could not find where it lives |
| `tool-broke` | A script errored, or produced output that was wrong |
| `extractor-gap` | Extractor missed structure that is present in the source |
| `gate-mismatch` | A gate verdict did not match the actual state |
| `question-unanswerable` | A gate question the persona could not answer |
| `deviated` | Did something other than what a skill said — always record why |
| `other` | Rare. If `other` recurs, the vocabulary needs a new class. |

## The persona brief

Written **before** the run and **not edited during it**. A driver that can edit the brief mid-run
simply writes itself the answers it wants, and the gate interviews become theatre.

Must contain:

- Company, sector, size. Why they are migrating, in their words.
- Budget and timeline, and how firm each is.
- Scope opinions — what they care about most, what they would drop.
- Target role model, at whatever fidelity a real stakeholder would have it.
- Branding inputs: logo, palette, type, spacing.
- NFRs, expected data volumes, concurrency.
- Integration stance per external system: real, stub, or not-yet-decided.
- **Two things the persona is wrong about.** A real stakeholder is confidently mistaken about
  something, and a pipeline that only ever meets correct stakeholders is untested.
- **An explicit "things this persona does not know" list.**

### The unanswerable question is the most valuable output

Any gate question the brief cannot answer gets logged `question-unanswerable`, and the run proceeds
with an `ASSUMED` recorded per the interview protocol. Do not go back and extend the brief to cover
it — the gap *is* the finding. It names a gate question that only the person who wrote the toolkit
can answer, which means it will not survive contact with a customer either.

## Choosing a source

| Criterion | Why |
|---|---|
| Covered by an existing extractor | Otherwise the run becomes an extractor project and tests nothing about the process |
| A domain a business would recognise | Media servers and dev tools produce thin BRDs and a weak Mendix story |
| Complete rather than large | Process cost across stages scales with stage and checkpoint count, not entity count |
| Relational schema present | JPA `@Entity` or SQL DDL feeds Stage 1 and Stage 3 enormously |
| Permissive licence, if the run may ever go external | MIT/Apache. AGPL and GPL carry derivative and optics problems |
| Some written documentation | Otherwise Stage 1 Path B has nothing to run against |

**Consider a control run first.** Pointing run #1 at the source an extractor was *built* against
makes extraction a solved problem and isolates the process as the only variable — so anything that
breaks is the runbook, not the regex. This is `measured-claims.md`'s positive-control discipline
applied to the pipeline: *three arms agreeing is evidence of nothing until the control has been shown
to move.*

## Running one

**Preconditions.** Toolkit tree clean, at a recorded SHA — this repo is edited by more than one
session at a time, and a run against a moving target measures a snapshot nobody can reproduce.
`bin/doctor.sh` clean. Source cloned at a recorded SHA.

**The toolkit tree is read-only for the duration.** Findings get written down, not fixed mid-run.
Fixing as you go destroys the record of what a fresh reader would have hit, and the second half of
the run then measures a toolkit that no longer exists.

**`tests/wave2/` is not run at any point** — not `run-all.sh`, not a single fixture. A field run is
not a test-suite run and must not be confused with one.

**Protocol the driver honours, because these are what the run exists to test:**

- Live Checklist Protocol (`conversion-runbook.md` §1b) — checklist in chat at stage start, marks as
  items land, full repost before every gate.
- Gates are paste-proven — `bin/gate-check.sh <project> N` output pasted in chat before stage N+1
  begins. Self-attesting "stage complete" is a protocol violation and, if it happens, a finding.
- No cross-stage parallelism. Within a stage is fine.
- Open the stage's **owning skill** before producing its artifacts. The runbook's matrix row is
  routing, not a spec.

**Phase 1 exit criterion — `bin/gate-check.sh <project> build-ready`.** The toolkit's own Stage-5
preflight, and therefore the natural terminal assertion for a stages-0–4 run. Its output goes into
the run record verbatim, whichever way it goes. **A `FAIL` here is a successful field run** — it
means the method found something.

## The run record

`field-runs/<date>-<source>.md`. Holds:

- Toolkit SHA, source SHA, date, and which sessions were driver and grader
- Layer-1 invariant results: each gate's verdict against what the entry mode predicted
- The friction log, classed, with a count per class
- The exit-criterion output verbatim
- A disposition per finding: fixed / deferred / won't-fix, with a pointer

**Findings route to their existing homes; the record holds pointer rows, not copies.** mxcli CLI
bugs to `bug-logs/mxcli-bugs.md`. Reusable patterns to `skills/learned-*.md`. Process decisions to
`process/process-learnings.md`. Per `close-the-loop.md`, nothing goes in two places.

`field-runs/` is the cross-run trend surface. It is what turns *"this is the fourth time a stage
summary got followed instead of the owning skill"* into a grep, rather than an archaeology project
across a directory of dated reports — the same argument `improvement-register.md` makes for defects
in a built app, applied one level up to the process that builds them.

## Reading a field run honestly

**A run that reports zero friction has not verified the toolkit. It has failed to observe.** Treat an
empty or near-empty log as an instrument fault and investigate the driver, not as a clean bill of
health — the same first move `measured-claims.md` prescribes when every arm of an experiment agrees.
