# journey-runner: `persona` is a label, not a login; four acts and `data.rebase` a real console journey needed

**From:** card-disbursement requirements-driven build (build-plan rows 3.8 and 4.7)
**Date:** 2026-09-26
**Kind:** learning
**Field evidence:** read `project-tests/e2e/journey-runner.js` main, which logs in once with `H.login(page)` before the journey loop. The installed copy was patched locally at row 3.8, and its admin-console journeys ran 57/0/0 and 52/0/0 with it.
**Proposed target:** `project-tests/e2e/journey-runner.js`; `skills/journey-proof.md` (schema)

---

**Persona.** The runner logs in once, as `TEST_USER`, for every journey file it is given; a journey's
`persona` is only printed. A cross-role check ("every role sees the badge") has to be one journey file,
run once per role, and nothing in the schema says so. A journey declaring `persona: <role-user>` and
run under an admin `TEST_USER` passes for the wrong reason. The runner already turns an admin fallback
(`usedFallback`) into INVALID, but it does not refuse a mismatch between persona and `TEST_USER`.
Proposal: when `persona` is set and is not `TEST_USER`, report the login INVALID.

**Local extensions** (the diff is in the project's `tests/e2e/journey-runner.js`; harvest-learnings will
pick it up as a locally patched installed script):
- `click` + `row` / `in` / `target`: a grid repeats one widget name on every row, so a first-match
  `.mx-name-<w>` clicks whichever row renders first. `row` is text identifying ONE row (innermost match,
  `last()`), `in` narrows the click to one grid, and `target` picks a child (a pluggable switch's `[role="switch"]`).
- `radio`: choose an option by its caption, then read the checked option back.
- `confirm`: press a button of Mendix's confirmation dialog by its caption, with an optional `says` check.
- `request`: an HTTP call made by a system client, not the persona. Credentials come from env vars the step
  names; missing credentials are an InstrumentFault, reported INVALID (never FAIL).
- `data.rebase`: a step that deletes rows on purpose (a fixture reset) re-takes the baseline for the
  named entities, so later deltas are not measured from a count that no longer exists.

(The two mutant fixes from the same patch set, a numeric `mustPointAt` sentinel and `outcome` on an exact
`expect`, landed directly; see CHANGELOG.)
