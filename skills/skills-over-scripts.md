# Skill: skills-over-scripts — do not encode a judgement as a program

**Applies to:** every skill, every harness, every gate in this toolkit.
**Status:** governing rule. When another skill's instructions conflict with this one, this wins,
and that skill is the thing to fix.

---

## The rule

> **If a check requires judgement, write it as instructions. Only write code for the parts a
> reader cannot do by hand: driving a browser, querying a database, fetching a trace,
> comparing thousands of rows.**

An agent reading a skill can already read a file, run a query, look at a screenshot, and decide.
Re-implementing that decision in JavaScript buys nothing and costs everything: the code has to be
written, debugged, wired, path-resolved, installed per project, kept in sync with the skill that
describes it, and re-debugged every time the rule changes. **The rule changes constantly. That is
the whole problem.**

## The test — apply before writing any `.js` or `.sh`

Ask, in order. The first `yes` decides.

| # | Question | If yes |
|---|---|---|
| 1 | Does this touch something an agent physically cannot — a live browser, a DB socket, a trace API, a build binary? | **Code.** This is an *instrument*. |
| 2 | Must this produce a byte-identical result on every run, in CI, with no agent present? | **Code**, and keep it under ~150 lines. |
| 3 | Is this comparing more data than a person could read — thousands of rows, a full DOM diff? | **Code.** |
| 4 | Anything else — "check that X is filled in", "verify the wording is honest", "make sure the guard discriminates", "confirm it matches the wireframe" | **Skill.** Write the sentence. Stop. |

Row 4 is where the money goes. Every one of those reads as a rule a five-line paragraph states
perfectly, and as three hundred lines of parser that states it worse.

## Instruments vs. instructions

Two categories. Keep them physically separate and name them so.

**Instrument** — a thin thing that *fetches a fact* and prints it. It has no opinion.
`journey-runner.js` drives Playwright. `otel.js` fetches spans. `mxcli` queries the model.
An instrument may report **fault** (I could not measure) but never **fail** (this is wrong).

**Instruction** — a skill that says what the facts must look like, and what verdict follows.
All judgement lives here. It is markdown. A human can read it, argue with it, and edit it in
ten seconds without a test suite.

The verdict discipline (`PASS` / `FAIL` / `FAULT` / `INVALID` never collapse; an absent
measurement is never a pass) is an **instruction**. It has been re-implemented in four separate
scripts in this toolkit's history and got it subtly wrong in three of them. It is six lines of
prose.

## What this costs when ignored — measured, PROJECT-C, 2026-08-19

| | lines |
|---|---:|
| `tests/e2e/*.js` | 16,173 |
| `bin/*.sh` | 4,933 |
| **total harness** | **21,106** |
| of which: report formatting only (`report-normalize.js` + `report-render.js`) | 5,881 (28%) |
| the four skills the harness exists to serve | 1,101 |

Two days of build time and several hundred dollars of context. **28% of the harness formats
output.** One 304-line script (`journey-compile.js`) existed to check that a markdown table's
columns were populated and that its refusal cells read `no:runner` rather than bare `no`. Seven
defects were found *in that script* — none in the thing it was checking. That is the signature
failure mode: the instrument becomes the bug surface.

## The tell

You are about to break this rule when you catch yourself:

- writing a parser for a document you also wrote the format of;
- adding a `--positive-control` flag to prove your own checker can go red;
- fixing a defect in a check rather than in the thing checked;
- writing a report renderer instead of printing the findings;
- adding a config file so the script can find its own inputs;
- explaining in a comment *why* the code does something, at greater length than just saying it.

That last one is the cheapest signal. **If the comment explains the rule better than the code
enforces it, delete the code and keep the comment — in a skill.**

## Retiring a script that should have been a skill

Do not just delete it. Order matters:

1. **Find its consumers first.** `grep -rn '<name>' --include='*.sh' --include='*.js' --include='*.json' --include='*.md'`.
   A script unwired from the gate may still feed a report. Deleting it then breaks the report,
   and the breakage shows up as a green run with a missing section — the worst possible failure.
2. **Move the judgement up.** Every rule the script enforced becomes a numbered line in the
   owning skill. Rules with no home mean the skill is missing, not that the rule is optional.
3. **Keep the fact-fetching**, if any, as a much smaller instrument.
4. **Delete, then re-run the gate.** A retirement that was never re-measured is not done.

## The harness updates itself, in the same cycle, not after

When a review run falsifies a hypothesis a skill currently endorses, patch that skill
**immediately, in the same turn** — not as a follow-up, not as a note for later. A finding that
contradicts a written rule and gets filed as "just a finding" leaves the wrong rule in place for
the next reader, who will trust the skill over a buried review note every time. Decide on the spot
whether the new evidence extends an existing skill (add a row, a caveat, a corrected example) or
needs a new file — but decide now, while the falsifying evidence is still in front of you, not
after the review report is written up and the context that produced it is gone.

## Adding a new capability

Write the skill first and use it by hand, at least twice, on real work. Only the parts that were
genuinely tedious *both* times may become code — and only the fact-fetching parts of those.
A capability that has never been exercised by hand does not yet know what it needs.

## Related

- `skills/measured-claims.md` — a claim about the harness is itself a claim; measure it
- `skills/harness-architecture.md` — instrument boundaries and the verdict vocabulary
- `skills/journey-proof.md`, `skills/module-review.md`,
  `skills/monkey-test.md` — the judgement skills; the harness serves these, not the reverse
