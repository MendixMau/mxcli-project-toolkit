# Stage-4 gate passes a build plan with none of the mandatory closing rows, so no module is ever LOOKed at

**From:** field run, requirements-driven app replacement (unattended build of a 137-row plan, 7 modules)
**Date:** 2026-10-02
**Kind:** bug
**Field evidence:** `gate-check.sh <project> 4` printed PASS on a plan with 0 of the closing rows #163 makes mandatory; the same run's obligation lines show look/sweep/journeys 0 of 7. Verbatim output below.
**Proposed target:** `bin/gate-check.sh` (`check_stage_4`), `skills/brd-to-build-plan.md`

---

**Severity:** High — the rule exists (#163) and is enforced nowhere; a plan-walking build reaches "DONE"
with the LOOK, sweep, journeys and coherence passes all at 0 of N, and every instrument it did run is green.
**Toolkit:** `check_stage_4` is byte-identical at `192b69a` and master `8abd614`, `bin/gate-check.sh:1169-1182`.
**mxcli version:** v0.24.0 · **Mendix version:** 11.14.0
**Reproducible:** yes, deterministic — any `architecture/build-plan.md` plus one Stage-4 `CONFIRMED` register row.

## The rule
`skills/brd-to-build-plan.md:311-319` (added `311d510`, 2026-09-29, #163): every plan carries three closing rows —
per module `HARNESS` `bin/verify-module.sh <Module>` then LOOK + CONFIRM per `module-review.md`; a
`process-coherence-pass.md` row per 2–3 modules; and the plan's last row `RUN gate-check.sh <project> 5`.
Denominator: N modules → N close rows, ≥⌈N/3⌉ coherence rows, exactly one final gate row. The skill's own
"Why" (line 322 on) is the 2026-09-27 build that went green to DONE with all of it at 0 of 7.

## The plan (proof it was not in the build plan)
`architecture/build-plan.md`, 137 rows, accepted before #163 existed and imported unchanged into the run:
- Row kinds: 78 `BUILD` · 21 `PROVE` · 19 `BRIEF` · 18 `RUN` · 1 `HARNESS` (a fixture row, not a module close).
- `grep -n -i -E "verify-module|module-review|N of N|coherence" architecture/build-plan.md` → **0 hits**.
- The last row is a `PROVE` acceptance-test row, not `gate-check.sh 5`.
- 7 modules (`architecture/modules/*/`) → required ≥7 close rows, ≥3 coherence rows, 1 final gate row; present **0 / 0 / 0**.
- The only visual-comparison clause in the plan is the StyleGallery row. Page rows say "matches its wireframe"
  as a DONE condition with no instrument named.

## The gate (proof it passes anyway)
```
Stage 4 (Build Plan): PASS · Surface present — build-plan.md present and a Stage-4 CONFIRMED decision is in .../PROJECT.md
```
`check_stage_4` tests exactly two things — the file resolves, and `has_confirmed_decision 4` — and never opens
the plan. A rule that later changes what a passed stage must contain (#163) therefore never reopens it.

## What it cost (proof the passes never happened)
Same gate run, obligation lines (verbatim, module names genericized):
```
Obligation look       PENDING — 0 of 7 discharged; NOT DONE: <7 modules> — owner: review-agent, governed by skills/module-review.md
Obligation sweep      PENDING — 0 of 7 discharged
Obligation journeys   PENDING — 0 of 7 discharged
Obligation coherence  PENDING — 0 of 1 discharged
Obligation skeleton   PENDING — 0 of 1 discharged
Obligation design-reaches-app PENDING — 0 of 1 discharged
```
- `design/ui-reviews/` never existed; `git log --all --name-only` shows no `ui-review-*` file, ever.
- Session transcript: tool calls naming `ui-loop.md` **0**, `module-review.md` **0**, `verify-module.sh` **0**;
  `page-fidelity.js` 38, `check-page-shell` 1.
- The only UI measure was `page-fidelity.js` (page MDL vs wireframe HTML; it does not render), first run after
  every page was built: 37/42 pages ≥85%. Eight screenshots looked at afterwards showed defects it cannot see:
  unformatted amounts (`50000`), stacked action buttons, truncated grid headers, an empty Actions card, empty
  grids with no empty-state text. No page was ever compared side by side with its wireframe.
- The build was declared DONE without `gate-check.sh 5` — the row that would have named it is the third closing row.

The build session shares the blame: the baseline routing table points at `module-review.md` ("before calling it
done") and the session never opened it. But that is the failure #163 diagnosed — *nothing that walks a plan does
a step the plan does not list* — and the gate that should have rejected the plan let it through.

**Workaround:** before approving Stage 4, count: `grep -c "verify-module.sh" architecture/build-plan.md` ≥ module
count; `grep -c "process-coherence-pass"` ≥ ⌈N/3⌉; the last numbered row contains `gate-check.sh` and `5`.
**Fix (proposed):** `check_stage_4` reads the plan and FAILs a plan below the closing-row denominator (N from
`architecture/modules/*/module-brief.md`), naming the missing modules. Secondly, re-run Stage 4 when
`brd-to-build-plan.md` changes, so a plan approved before a rule is not grandfathered silently.
