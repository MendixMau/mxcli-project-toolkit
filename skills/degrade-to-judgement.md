# Skill: degrade-to-judgement — a missing input never cancels the verdict

**Applies to:** every pass, every gate, every agent, every entry mode. Baseline routing.
**Status:** governing rule for what happens when wiring is incomplete. Where another skill says
"skip if absent", this wins and that skill is the thing to fix.

---

## The rule

> **A missing input changes what you assess *against*. It never changes *whether* you assess.**

Projects are never fully wired. Wireframes were never drawn, the design system arrived late, an
extractor produced no BRD for one module, an instrument is not installed, a path in the `Wiring`
table does not resolve. Every one of those is a normal Tuesday, and none of them is permission to
report nothing.

The failure this replaces is specific and it keeps happening: an artifact is absent, the pass
quietly drops that dimension, and the report reads clean over a hole. **A skipped check and a
passed check are indistinguishable in a report that does not name the skip.** Absence renders as
green. That is the entire bug.

## Why this is a rule and not a nicety

An agent reading this can already judge whether a screen is usable, whether a flow does what the
BRD asked for, whether a page is presentable, and whether a module's behaviour is coherent —
with none of those artifacts in existence. The judgement was available the whole time. Declining
to use it because a file was missing is not caution; it is choosing to emit nothing, and nothing
is the one output that gets misread as success.

## The three rules — every degraded row carries all three, or it is silence with extra steps

1. **Named.** Which input was missing, by path, in the report. Not "no wireframe available" —
   `design/wireframes/Orders/OrderList.html` (absent).
2. **Substituted.** What you assessed against instead, named explicitly: the design system, the
   BRD, the module brief, the build-plan row, sibling pages, the requirements as written, or your
   own unaided judgement against the rubric.
3. **Still a verdict.** Per item, per dimension. Not "could not assess".

`UNMEASURED` is a legitimate verdict when a **mechanical** dimension genuinely could not be
measured — a11y without axe, overflow without a browser, a count-delta without a DB connection.
It is never legitimate for a **judgement** dimension. If the question was "does this make sense",
your instrument was present.

## The ladder — fall to the next rung, do not fall off

When the yardstick you expected is gone, take the next one down and say which rung you landed on.

| Rung | Yardstick |
|---|---|
| 1 | The declared artifact — wireframe, design system, journey file, module brief |
| 2 | The next-nearest declared artifact — BRD, build-plan row, architecture blueprint |
| 3 | The requirements as the user stated them, wherever they are written |
| 4 | The process — what this stage of `conversion-runbook.md` says the thing is for |
| 5 | Unaided professional judgement, with the rubric rows cited |

There is no rung 6. Rung 5 always exists, which is why "not applicable" is almost never the
honest answer to a missing input.

## Instrument fault is a handoff, not an exemption

An instrument that exits 2 has said *I could not measure this*. It has not said *this dimension
does not matter today*. Assess it by hand and report **both**: the fault, and your verdict.

```
⚠ design-audit.js FAULTED (exit 2) — class promotion and overflow UNMEASURED;
  layout and hierarchy assessed by hand, rubric rows 2 and 4 — see finding 7
```

## What a degraded verdict looks like in a report

Degraded rows are not footnotes. They sit in the same table as everything else, with the same
verdict vocabulary, and the headline still states its denominator.

```
12 of 12 pages reviewed — 4 against wireframes, 8 against unaided judgement (no wireframe)
⚠ design/wireframes/Orders/ absent — rung 5, rubric cited per page
```

A report that says "all green" while three dimensions silently degraded has lied twice: once
about the dimensions, once about the denominator. See `skills/e2e-evidence-report.md` §
"The denominator rule".

## The catch-all

No table can enumerate every way a project can be half-wired. When you meet a gap nothing
documents, the answer is never "not applicable" and never a silent skip. It is the three rules:
**name it, substitute the best remaining yardstick, still deliver a verdict.**

And then fix the documentation in the same turn — `skills-over-scripts.md` §
"The harness updates itself, in the same cycle, not after".

## Related

- `skills/module-review.md` §4 — the worked per-dimension degradation table for the visual pass
- `skills/e2e-evidence-report.md` — the denominator rule a degraded report must still satisfy
- `skills/harness-architecture.md` — fault vs fail; an instrument may fault, never fail
- `skills/skills-over-scripts.md` — governing rule on where judgement lives
