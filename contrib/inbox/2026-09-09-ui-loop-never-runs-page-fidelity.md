# `ui-loop.md`'s per-script look never runs the fidelity harness that already exists — a whole batch of built pages went unstyled and unmeasured until an end-of-session screenshot pass

**From:** a change-governance (MOC/PSSR) app replacement project (2026-09-09, overnight session)
**Date:** 2026-09-09
**Kind:** learning / skill-draft
**Field evidence:** confirmed finding on a real build, not a hypothesis. See numbers below.
**Proposed target:** `skills/ui-loop.md` (the per-script cadence skill), possibly also
`skills/module-review.md` stage 4's own instructions to actually invoke the harness it already
requires as evidence

---

## What happened

The project has `project-bin/page-fidelity.js` — a real, working, already-installed instrument
that scores a built page against its wireframe (headings/actions/content/classes) and appends
every run to `docs/PAGE-FIDELITY.tsv`, target ≥80%. It was never run against 4 of a module's
8 pages (Employee/Section/Machine/ApproverList admin overview pages, `build-plan.md` row 62,
built two build-scripts earlier). Nobody noticed, because `ui-loop.md`'s cadence — a screenshot
and three subjective questions after each script — kept saying the pages "looked fine enough
to keep going," and `module-review.md`'s stage-4 LOOK pass hadn't happened yet either (row 62b,
the module's own regression harness, was also still `not built`).

The user asked directly mid-session, after being shown an ad-hoc screenshot pass: **"why did
our UI review not look at the pages? ... run UI improvements. Why is that so hard?"** — and was
right to ask. Running the actual harness that day turned up:

- `Employee_Overview`: **50%** fidelity (below target) — but the "content" miss driving that
  score was the page's subtitle text differing from the wireframe's own **placeholder** copy
  (the wireframe file's own header literally says "copy is placeholder; structure is the
  deliverable"), and the built copy was arguably better (cites the real BR number). So the
  score alone was not the actionable signal here — the harness's number needed a human reading
  the "missed:" detail lines next to it, not blind score-chasing.
- Two **real** defects the fidelity harness's page-vs-wireframe diff would NOT have caught,
  because they're not about one page's shape: (a) the module's landing page (`Admin_Home`) had
  navigation to only 1 of 5 admin screens — the other 4 were built, access-granted, and
  completely unreachable from the UI; (b) a reused card-list snippet
  (`SNIPPET_CardListRow`) had shipped with class names (`card-row`, `avatar`, `card-who`,
  `role-tag`, `card-name`) that were never defined in the project's `ds.css` — every card on
  every admin list rendered as raw unstyled concatenated text.

## Why this is a process gap, not a one-off miss

`ui-loop.md` already states the right cadence philosophy ("cheap enough to run ten times per
module... a defect that survives into the next script costs more to find and more to place")
but its actual four-step loop is entirely subjective (screenshot + three eyeballed questions).
It never tells the agent to run the ONE instrument in the repo built specifically to answer
"does this page match its wireframe" with a number and a denominator — `page-fidelity.js`
already exists, is already wired into `docs/PAGE-FIDELITY.tsv`, and was simply never invoked
until asked for explicitly, four build-scripts and one whole module later.

Separately: neither the fidelity harness nor the eyeballed loop check **reachability**
(can a user actually navigate to this page from anywhere) or **cross-page shared-component
styling** (is every class this page's markup emits actually defined somewhere). Both defects
found here are the "the individual page's own MDL and wireframe substantially agree, but the
thing is still broken" class — orthogonal to what page-fidelity measures.

## Suggested fix (not built — proposing, not shipping, per this project's own rule that
skill authorship needs baseline-testing before a rewrite)

1. Add a numbered step to `ui-loop.md`'s loop: **"If a wireframe exists for this page, run
   `page-fidelity.js` now, not just at module close — read the score AND the 'missed:' detail
   lines, and use judgement before rewriting copy to chase 100%; placeholder-vs-real-copy
   divergence is not always a defect."**
2. Add a fifth question to the loop's three, specifically aimed at what fidelity-scoring can't
   see: **"Reachable? Can a real user actually navigate here through the built nav, not a
   direct `/p/` link — click through it."** (This project also found that direct `/p/<Page>`
   deep links don't work at all in this app's runtime, which made this check non-optional —
   worth a separate bug-log entry, not repeated here.)
3. Consider a periodic (not per-script) full sweep — screenshot + fidelity-score every built
   page in the module, cross-checked against the shared stylesheet for any class a page's own
   markup emits that the stylesheet doesn't define — run at least once **before** claiming a
   module's Phase done, not deferred to whenever someone happens to ask. `module-review.md`
   stage 4 may already intend this; if so, the gap is that nothing forces it to actually run
   before a phase gets marked "done" in the build plan (this project's own build-plan rows 59-61
   were marked done while row 62, the harness pass, sat at "not built" with no red flag raised).

Per this toolkit's own skill-authoring rule 2 (`CLAUDE.md` "Authoring rules for
behaviour-shaping skills") — baseline-test before rewriting a skill "because outcomes were
bad" — this is a field-evidence writeup for triage to weigh, not a drop-in replacement text.
