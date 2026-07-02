# QA Loop Goal Pattern — Iterative Pipeline Validation
**Purpose:** A reusable `/goal` directive for autonomously validating a new stack's
extractor/linker/mapper pipeline against real source, run until output quality is genuinely
high — not just "runs without crashing."
**Source:** java-angular-migration-skills pipeline build, 2026-07-01/02. See that project's
`SESSION-NOTES.md` for the full bug list this produced.

---

## The goal text (copy-paste template)

```
keep on looping through run the extractors, validating to quality, finding errors, evaluating
if all details are correctly extracted and interconnected, find broken patterns etc, keep doing
this until we can run a full extraction -> mapping and we have the highest possible quality of
brds
```

Set via `/goal <text above>`. Runs as a session-scoped Stop hook — it blocks the session from
ending until the condition holds, and auto-clears once met.

---

## When to use it

After the initial extractor(s) exist and run without crashing, but before trusting the BRD
output. This is a validation/iteration tool, not a substitute for the initial build — don't set
it before you have something to iterate on.

## Precondition: you need ground truth to check against

The loop only works because there was something known-correct to compare pipeline output
against — in this case, an `analysis/<repo>/architecture.md` written by hand *before* any
extractor code existed (reading the entities/controllers/services closely and documenting the
real business rules found). Without that, "iterate until highest quality" has no way to
distinguish confident-but-wrong output from actually-correct output. **Write that doc first.**

## What it actually looks like in practice

Not "run the whole pipeline and eyeball the summary." Each iteration was: make one targeted
code change → re-run just the affected extractor(s) + merger + relevant mapper → inspect actual
field-level output (`python3 -c "import json; ..."` one-liners against the extracted JSON or
generated BRD, not just exit codes) → compare specific values against the ground truth doc →
fix or move on. The bugs this caught (see `java-angular-migration-skills/SESSION-NOTES.md` for
the full list) were mostly invisible to a "does it crash" check:

- Chained method calls producing giant duplicated blob strings instead of clean names
- An extractor writing to a path the merger didn't actually read (doc for the convention was
  stale relative to the real working code)
- A linker rule inherited from the source pipeline firing irrelevant noise on every item
- **The category that matters most:** cross-reference rules that ran without error and produced
  plausible-looking links that were quietly wrong (e.g. every screen in a module linking to the
  same two endpoints, because a URL built via string concatenation only had its first fragment
  captured) — this class of bug is exactly why "no errors" isn't sufficient evidence of quality,
  and why the loop has to check field-level content against known-correct facts, not just run
  the pipeline and look at gap counts.

## How to reuse this for a future stack (.NET, Oracle Forms, Rails, etc.)

1. Bootstrap the new pipeline repo per `migration-pipeline.md`'s "Creating a New Stack Pipeline"
   checklist far enough that extractors run without crashing.
2. Hand-verify a small amount of ground truth first — an `architecture.md`, or just reading a
   handful of source files closely enough to know what the "right answer" should be for a few
   entities/endpoints/screens.
3. Set the goal (adapt the template above to name the actual stack/output if useful).
4. Expect it to surface bugs in: URL/path reconstruction (string concatenation, template
   literals, whatever the target language's equivalent is), verb/method or type
   disambiguation, naming-convention assumptions (module bucketing, repository-to-entity name
   matching), and stale rules copy-pasted from whichever pipeline you started from.
5. Stop when cross-reference counts are high, every remaining gap has been individually checked
   and confirmed legitimate (not just accepted because the count is low), and a handful of BRD
   entries have been manually cross-checked against the ground truth doc.
