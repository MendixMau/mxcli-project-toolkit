# Existing App Assurance — Audit & Regression-Test a Mendix App You Already Have
**Applies to:** any mxcli project — an existing Mendix app with nothing to migrate or build.
**Requires:** bash and Python 3 — this skill runs toolkit shell scripts. Run `bin/doctor.sh` once on a new machine; it names anything missing and how to get it. Windows: use Git Bash, and see the Prerequisites section of `conversion-runbook.md`.
**Purpose:** The recipe for pointing this toolkit at an app that already exists: analyze it, lint it, and put a regression net under it. **No pipeline, no stages, no gates** — this is à-la-carte tool-shelf use; grab the track you need and go.
**Source:** Toolkit review 2026-07-14 — the `[any project]` skills always worked on existing apps, but nothing said so, and nothing routed the "I just want e2e tests / an audit" user anywhere.

---

## When to Use This Skill

- "Can you audit this Mendix app?" — quality, security, architecture boundaries.
- "Build a regression / e2e test suite for our existing app."
- Before a Mendix version upgrade or a big refactor: record what the app does *today* so you can prove it still does it afterwards.
- You inherited an app and need to understand it before touching it.

Not for building anything new — that's `conversion-runbook.md` (pick an entry mode there).

## Ground rules

- **Read-only by default.** Everything here is queries, lint, and tests — nothing writes to the `.mpr`. That's why no gates are needed.
- If the audit finds things worth *fixing*, that's a deliberate hop into the build discipline (`iterative-build-loop.md` + the STOP table), agreed with the user first — never a silent side-effect of the audit.
- A minimal `PROJECT.md` (decision register) is still worth keeping if findings lead to decisions; skip it for a pure test-suite job.

---

## Track A — Analyze / audit the model

| Question | Tool |
|---|---|
| What's in the model? | `SHOW MODULES / ENTITIES / ASSOCIATIONS`, `DESCRIBE ENTITY`, `SEARCH` — see `query-the-model.md` |
| Is it well-structured? | `mxcli graph-report` (community detection, dependency tangles) — `graph-analysis.md` (bundled) |
| Does it violate best practices / architecture boundaries? | `mxcli lint` + Starlark rules — `write-lint-rules.md` (bundled) for custom rules (naming, security, cross-module data) |
| Is it secure? | `manage-security.md` (bundled) as the reference; lint's `sec_*` rules; grep access rules via `DESCRIBE` |
| Overall quality scan | `assess-quality.md` (bundled) |

**Deliverable:** a findings report (markdown or HTML — reuse `toolkit-guide.html`'s tokens), each finding with evidence (the query/lint output) and a proposed disposition: fix now / log / accept. Triage the list *with the user* — dispositions are their call.

## Track B — Regression / e2e test net

1. Stand up the harness per `e2e-harness-base.md` (Playwright + demo user + app-start discipline).
2. **Per module, inventory every workflow action before writing a single journey — from the
   model, not from memory or a quick click-around:**
   ```bash
   ./mxcli -p <project>.mpr -c "SHOW PAGES IN <Module>"
   ./mxcli -p <project>.mpr -c "SHOW MICROFLOWS IN <Module>"
   ```
   List every button/action on every page (New, Edit, Delete, status/workflow transitions, add
   comment, add note, approve/reject — anything that calls a microflow), then write one journey
   per action, not one journey per screen. Record the count: `<N> actions found, <N> journeys
   written` is a claim; "covered the golden paths" is not — same denominator discipline as
   `wiring-sweep.md`. A workflow's secondary actions (commenting, annotating, cancelling) are
   exactly the ones a quick pass skips and a real user relies on daily; they are not optional
   because they aren't the module's headline feature.
3. Author/extend `journeys/<Module>.journey.json` per `journey-proof.md` for every action from
   step 2's inventory (5 rungs, `--positive-control` proving each could have failed).
4. Add DB assertions (`learned-db-assertions.md`): the UI can lie about whether a create/update/delete landed; OQL can't.
5. Run `wiring-sweep.md` per module — every clickable element on every page, not just the ones a
   journey happens to visit. A dead button is invisible to step 3 by construction: nobody writes
   a journey through a broken affordance because nobody knows it's broken.
6. Run `module-review.md` stage 4 (LOOK) per module — styling, spacing, information hierarchy,
   empty states, design-system reuse; `design-audit.js` for the mechanical dimensions (class
   discipline, overflow, a11y), 4c/4d/4e by eye for the rest. This is the only place "does the UI
   look right" gets asked at all — nothing upstream of it checks visual quality, so skipping it
   means styling was never actually reviewed, however green the journeys are. Skip only 4d's
   wireframe-diff sub-bullet if the app predates this toolkit and has no wireframe on file; run
   the design-system-consistency and root-cause-the-symptom checks regardless.
7. Commit the suite **and the baseline**: "this is what the app does today, proven." That baseline is the acceptance yardstick for any future upgrade, refactor — or migration Stage 6.
8. Optionally generate `test-agent` for repeat runs: `bin/init-agents.sh <session-root> build` (use just test-agent; complete its placeholders per `agent-roles.md`).

### Why the coverage and conformance rungs never come back clean here

Running `project-bin/verify-module.sh <Module>` on an existing app will never get a clean result
from *conformance (ledger claims vs live model)* or *coverage (BRD leaves)*. That is correct and
permanent for this entry mode — not a broken instrument and nothing to fix.

Both measure a built module against `architecture/.../coverage-ledger.md` and the BRD it was
generated from. Those are build-loop artifacts: a BRD is written, a ledger is generated from it and
the build plan's `claims`, and the module is built against both. Track B has no pipeline, no BRD
and no stages by design — it audits an app that already exists rather than tracing one back to a
spec it never had. So there is no denominator, and the honest answer is "does not apply", not
"clean" and not "fault".

Until 2026-08-20 both printed a hard **INSTRUMENT FAULT**, identical to the one a real missing
ledger produces, so the operator could not tell permanent noise from a real gap. They now grade the
absence into four levels (`coverage-ledger.md` → "The four fallback levels"). **Level 4 · NOT
APPLICABLE is this entry mode's normal state**, and the rung now names the reason — "no pipeline
produced a spec for this module" — instead of just failing.

Two things to know about how that renders today:

- `verify-module.sh` maps any non-zero, non-2 exit to **FINDING**, so level 4 shows as `✗ findings`
  rather than as its own verdict. Read the rung's log, which states the level in its first line.
  What has changed is that it no longer counts as a FAULT, so the run stops declaring itself
  `INCOMPLETE` over a file that was never going to exist.
- The *conformance* rung reaches the new grading directly. The *coverage* rung does not yet:
  `verify-module.sh` still short-circuits to a FAULT of its own before calling the coverage script
  when the ledger file is absent. Run `project-bin/coverage-preflight.sh --assess --module <Module>` by
  hand to see the graded answer until that call site is updated.

If you see level 3 instead ("N requirement leaves across M BRDs; 0 traceable to a build-plan row"),
the app *does* have BRDs on disk — you are auditing a project that also went through the pipeline,
and that number is a real gap in that project's traceability, worth raising even though closing it
is not this track's job.

What carries the real signal on Track B is steps 3–6 above: the journeys, the wiring sweep, and the
LOOK stage.

**Deliverable:** a green, committed test suite + `test-report.html`, plus the LOOK-stage and
wiring-sweep findings folded into `docs/improvement-register.md` — a green journey suite alone is
not the deliverable; it only proves the paths someone thought to write. Before calling the run
done, apply `finding-disposition.md`: name every module/persona/affordance the run didn't reach and
why, fix or log every harness gap the run hit, and ask the user which logged findings to route into
the build loop now.

---

## Why this exists as a named recipe

The toolkit's staged pipeline is for *producing* an app. But half the toolkit (`query-the-model`, `e2e-harness-base`, `learned-db-assertions`, lint rules, the bundled analysis skills) is just tools — and tools don't need a pipeline. This file is the router so "I just want tests/an audit" never gets funneled through intake questions it doesn't need.
