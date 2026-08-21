# E2E evidence report — turning a passing suite into a readable proof
**Applies to:** any mxcli project where a stakeholder wants to see the app work, not run it
themselves.

**Read first:** `testing-shape.md` — **promoted, so read it in the shared toolkit; there is no local
copy and there must not be one** — the UI+Data rigor vocabulary, the false-green register (§4),
and the positive-control discipline (§6) this skill assumes are already satisfied. This skill does
**not** re-derive test rigor; it re-packages an already-rigorous run as a narrative a non-technical
reader can follow without running anything. A pretty report built on an unguarded assertion is
worse than no report — it dresses up exactly the failure modes §4 documents, for an audience least
equipped to spot them.

## What this is not

| Existing artifact | Answers | Audience |
|---|---|---|
| `module-review.md` (toolkit) | What's broken/off-design? | Builder, diagnostic only |
| `tests/e2e/*.sh` + `results/*.json` | Did the regression pass? | CI, pass/fail |
| **This skill's output** | **Did the feature actually work, and how do I know?** | **Stakeholder, narrative** |

Producing this report is not a substitute for either of the other two. Run them first; this skill
turns their output into something a reader can trust on sight.

## The no-OpenTelemetry decision (record once, don't re-litigate)

Most mxcli projects have no APM/tracing module installed — `testing-shape.md` §2 calls Trace
optional for exactly this reason (Mendix-side OTel has no scriptable switch; someone must flip it
in Studio Pro and hand-start the collector). Unless a project has explicitly done that setup and
recorded it as a CONFIRMED decision, **do not promise trace evidence** in this report. The accepted
substitute, in order of strength:

1. **DB delta** (the Data rung, done right — count delta or a fresh unique key, never bare
   existence, per §4's Data row).
2. **Runtime log line**, if the called microflow has a `LOG INFO`/`LOG ERROR` statement —
   `mxcli docker logs -p app.mpr --tail N` around the action's timestamp. This is corroborating,
   not proof on its own: a log line proves the microflow *logged*, not that every activity inside
   it succeeded (the same gap §4's Trace row calls out for real spans — a caught error can leave a
   microflow "looks fine" while an activity inside failed). Say so if a step relies on log-only
   evidence.
3. If neither is available for a step (a pure UI-state change, nothing persisted), say so —
   `"⚠ No DB/log evidence for this step — UI-observed only"` — never silently omit the row.

If a project later wires real OTel, prefer span evidence over log-grepping and update this
skill's report template accordingly — that is a stronger, not just different, evidence source.

## Report structure

One self-contained HTML file (screenshots embedded as base64 PNG — same portability constraint as
`module-review.md`'s own output; no external file references). Organize by **user journey**, in
the order a real user walks them — not by test-suite filename, which groups by implementation
detail the reader doesn't care about.

Per journey, per step:

| Field | Source |
|---|---|
| Action taken | Plain language ("clicked 'Confirm signed'"), plus the exact selector/command used underneath (for the builder audience reading the same report) |
| Screenshot | Captured **immediately after** the action, once the landing/result guard confirms the UI actually changed (§4's landing-assertion guard — never screenshot before confirming the nav/action landed) |
| DB evidence | Before/after row or field value, from the same `oql()` helper the suite already uses — reuse it, don't hand-roll a second query path |
| Log evidence (if applicable) | The matching runtime log line, or the "no log evidence" note |
| Verdict | Pass/fail for this step, plus which §4 guard would have caught a false-green here (write it even when the step passes — it's what makes the "pass" mean something to a skeptical reader) |

Close each journey with one line: "this journey's assertions satisfy testing-shape.md §4 rows:
[which ones]" — makes the report's own rigor auditable, not just asserted.

## The denominator rule — see `module-review.md`

**This section now lives in `skills/module-review.md`'s Stage 5** (the same 2026-08-19 incident,
the same three-claims table, the same banned-phrase rule, "name what the harness structurally
cannot see," and the two follow-on rules about demo click-throughs and root-causing before
calling a bug closed). Read it there — this file no longer carries its own copy, to avoid the
two-files-one-concept drift that caused the `ui-review-loop.md` merge in the first place.

The one thing worth restating here: this skill's report is downstream of that rule, not a
replacement for it. State the denominator in this report's headline exactly as `module-review.md`
specifies, and do not let this file's prettier packaging soften "N of M journeys executed" into
something that reads like completeness.

## Reuse rule

Never re-derive selectors, login helpers, or navigation clicks for the walkthrough. Pull them from
the project's own already-proven e2e harness (e.g. this project's `tests/e2e/common.sh`:
`login_as`, `nav_click`, `click_widget`, `oql`). A hand-rolled selector in the "pretty report"
script is a second, unaudited path to the same UI — exactly the kind of drift `testing-shape.md`
warns against elsewhere in the harness.

## Sequencing

Run this only against a build that has already passed its own regression suite (§5's "stack is up
and proven" precondition) and — if a design/UX review loop exists for the project — after that
pass too, so the report doesn't need a redo when the reviewer's own findings get fixed.

## Publishing

If the report is meant for a human to open without repo access, publish it (e.g. via an Artifact
tool where available) at a **utilitarian/report treatment**, not an editorial one — this is
evidence, not a marketing page. Keep a repo copy regardless, for history and for readers who do
have repo access.

## Before calling it done

Publishing the HTML is not the last step. Apply `finding-disposition.md`: every journey/module the
denominator names but this run didn't execute gets a named reason, every finding surfaced while
producing the report (not just in the source suite) is routed through `close-the-loop.md`, and any
harness gap hit while building the report (a helper that no longer matches a selector, a missing
`oql()` case) is fixed now or logged — never silently patched around just to get the report out.
