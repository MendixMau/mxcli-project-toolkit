# LOOK pass, ui-loop and page-fidelity never executed on a full Stage-5 build — second occurrence

**From:** lowcode-vs-highcode benchmark, Mendix arm run 1 (orchestrator session)
**Date:** 2026-09-19
**Kind:** process
**Field evidence:** A 3-module, 7-screen requirements-driven build (Mendix 11.14, mxcli 0.22.0, toolkit @ 2d9a0a2) closed with `design/ui-reviews/` empty, no `docs/PAGE-FIDELITY.tsv`, no `.claude/loop/`, `bin/page-fidelity.js` present but never run, and `PROJECT.md` still reading "gates passed: none yet (derived by gate-check on <scaffold date>)". The human noticed by looking at the screenshots. Same chain as `contrib/inbox/2026-09-09-ui-loop-never-runs-page-fidelity.md`, which was still unpromoted.
**Proposed target:** `skills/conversion-runbook.md` §1b (definition of done), `bin/init-project.sh` (install instruments), agent-stub dispatch / `iterative-build-loop.md`, and triage of the 2026-09-09 note together with this one.

---

## What we did

- Stages 0–4 with the toolkit (intake, BRDs, blueprint, wireframes S1–S7, ds.css, build plan).
- Stage 5 built by a lead agent that was itself a subagent, plus 14 generic worker agents in 5
  batches, each with a per-file brief naming the MDL script and the wireframe. Role-agent stubs
  (`mdl-agent`, `review-agent`, …) were scaffolded but not dispatched — a subagent lead cannot
  spawn subagents, and the run rules excluded them anyway.
- Every stage was declared done in the run log. `gate-check.sh` was never re-run after scaffold.
- Result: pages structurally off their wireframes (missing status chips, unformatted amounts,
  absent filter chips, empty persona selector, clipped collapsed nav, raw "No items found" empty
  states), on top of the scaffold `signal` theme the spec's "platform default" rule left in place.

## Why the five UI obligations never fired (finding, reproduced by reading the artifacts)

1. **The obligation check is only as good as the last `gate-check.sh` run.** `obligations.tsv`
   row `look` would have printed PENDING for all three modules — but nothing in the build loop
   requires gate-check before "done", so it printed nothing. Green-by-absence happened one level
   up: absence of the *check*, not absence of the artifact.
2. **"A citation is not a read" — again.** `ui-preflight-pages.md`, `ui-loop.md`,
   `module-review.md`, `page-fidelity.js` and `check-page-shell.sh` are routed through
   `mdl-agent.md` / `review-agent.md` stubs and the CLAUDE.local.md situational table only. The
   lead's own always-on block (mxtk wiring: RESUME.md, exec-approval, no strays) has no LOOK line,
   no fidelity step, no gate-check-before-done. Workers got briefs, not skills. So the text was
   in nobody's context at page-writing time.
3. **Instruments installed, never run.** `init-project.sh` copied `page-fidelity.js`
   and `check-page-shell.sh` into the project `bin/`; nothing in the loop required executing them.
4. **Inbox not drained.** The 2026-09-09 note predicted this exactly. Ten days in the queue.

## Should these be part of the pipeline? (position, not hypothesis)

They are. The gap is enforcement, not content. Proposals, smallest first:

- **A.** In the runbook's Live Checklist Protocol (§1b), make the last item of every Stage-5
  module checklist literally: `gate-check.sh <root> 5` ran, output pasted, zero PENDING
  obligations for this module. A stage reposted without it is not done.
- **B.** `init-project.sh` (already installs both instruments) additionally writes the `docs/PAGE-FIDELITY.tsv` header
  so the artifact check sees a stub and the
  human sees zeros instead of nothing.
- **C.** Put a 6-line "before any page MDL / after any page MDL" block into the *always-on*
  section of the generated `CLAUDE.local.md` (not the situational table): read
  `ui-preflight-pages.md`; after exec, screenshot, run page-fidelity, append the row. This is
  the inline-the-dispatch rule from CLAUDE.md authoring rule 2 applied to the lead itself.
- **D.** Hypothesis: the `look` obligation should also accept a *fidelity row ≥ threshold plus
  a screenshot file* as evidence, not only `ui-review-*.html`, so single-session builds without a
  review agent can still satisfy it honestly.
- **E.** Triage discipline: an inbox note older than N days that names a pipeline gap blocks the
  next `init-project.sh` on that machine with a warning listing it. (Hypothesis; may be too noisy.)

## What we are doing on the project

Re-running the UI pass on both benchmark arms under a spec amendment: element-checklist
alignment per wireframe (present / placed / behaves), ≥95% target, header/topbar mandatory,
platform-default theme retained. Fidelity measured mechanically, LOOK pass with screenshots,
`gate-check.sh` before close. Outcome will be filed as a follow-up to this note.

## Follow-up (same day, same author) — proposal D is field-refuted; A/C landed

Run 1b closed on both arms and the outcome is filed at
`lowcode-vs-highcode-benchmark/results/mendix-run1b/` and `results/highcode-run1b/`.

**D is withdrawn, not deferred.** It proposed that the `look` obligation accept a fidelity row
≥ threshold plus a screenshot instead of a review artifact. Scoring the same commit both ways
shows the score cannot stand in for the pass in either direction:

| Screen | Fidelity (text match) | Element checklist (present / placed / behaves) |
|---|---:|---:|
| S1 Requests overview | 100% | 58% |
| S4 Approval queue | 100% | 40% |
| S3 Request detail | 55% | 69% |

`page-fidelity.js` greps identifiers out of the page MDL and matches them against the
wireframe's text; it cannot see nesting or placement. S1 and S4 named every element and laid
them out wrongly. S3 fails the grep on formatting the instrument has no expression for. A
threshold over this number would have passed the two worst screens in the run.

**A and C landed instead**, as commit `e466e4c` in this repo:
- `skills/conversion-runbook.md` §1b **rule 8** — the last checklist item of every stage and
  every module build is `bin/gate-check.sh`, run and pasted, zero `PENDING` or each one named
  and waived (proposal A).
- `bin/init-project.sh` — a before/after page-MDL item in the generated `CLAUDE.local.md`, so
  the pre-flight text reaches the agent that writes pages (proposal C).
- `skills/ui-preflight-pages.md` — "a fidelity score is not a LOOK pass", carrying the table
  above. This is what replaced D.

**B is moot**: `project-bin/page-fidelity.js` already writes the `PAGE-FIDELITY.tsv` header when
it creates the file, so a missing score is not a missing table. **E is untouched** — still a
hypothesis, still possibly too noisy.

Non-Mendix control, so this reads as a pipeline gap rather than a platform one: Arm B's
high-code baseline was 43% (approvals) and 56% (admin) against the same wireframes, and reached
100% only after the same deliberate LOOK loop.
