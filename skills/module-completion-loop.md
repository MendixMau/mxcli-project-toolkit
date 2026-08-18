# Module completion loop — build, gate, prove, confirm, next

**Applies to:** any mxcli project running the auto-build/endless-build-loop pattern (resolve
ambiguity via written assumptions, keep going rather than stopping to ask at every step).

This is the concrete sequence for "build a module, prove it, move to the next module": the
operational checklist, including monkey testing and process-coherence. The reasoning behind the
verification steps lives in `testing-shape.md`; the deep form of step 3 is `journey-proof.md`.

> Both of those are **promoted — they live in the shared toolkit**, not here. There is no local copy
> and there must not be one: the shared file is canonical, and a personal duplicate drifts invisibly
> because nothing syncs the two. `journey-proof.md` also now has worked examples alongside it
> (`journey-examples.md`) and a preconditions skill above it (`fixture-seeding.md`), both shared.

## The loop

```
1. BUILD    mdl-agent drafts + validates MDL (mxcli check --references, 0 errors)
2. GATE     bin/exec.sh (snapshot → exec → mxbuild → auto-restore on failure)
            gate-agent confirms 0 mxbuild errors, lint clean
3. PROVE    testing-shape.md's mandatory rungs: UI (Playwright) + Data (OQL/DB assertion)
            + monkey pass (see below) — always, not optional
            + Unit / Trace only if this module's declared depth calls for them
            When the result must be shown to a human who won't read logs, or when an
            instrument is green and you can't say what would have made it red, run this
            step in its deep form: journey-proof.md (five rungs, one control each).
4. COHERE   process-coherence-pass.md — NOT every module. Run it when a module or a
            related cluster just went clean on steps 2-3, or on demand ("does this
            actually work end to end?"). See that skill's "Cadence" section.
5. CONFIRM  Post-Module Checklist — a module-boundary artifact, separate from the
            per-script `done-` marker, which keeps its existing cheap meaning.
            One box per rung, each naming the guard that would have made it red;
            a rung with no such guard is recorded as fault, not ticked. Record which
            rungs ran and which were opted out of, so a later reader can tell
            "UI+Data only" from "UI+Data+trace" — and restate the loop's own
            principle: CE-error-free is not done, and UI-green is not done either.
            Plus a coherence-pass box if step 4 ran.
            Reopen Studio Pro, propose Run Locally (CLAUDE.local.md build-loop rule),
            get an explicit human look before calling the module done.
6. NEXT     Move to the next module's build. Do not carry step-4 open items forward
            silently — they go in PROJECT.md as tracked follow-ups, not lost in scrollback.
```

Steps 1–3 are cheap and run per module, every time — this is today's baseline, not new. Step 4 is
the expensive, occasional check; do not run it at step-1/2/3 cost or it stops being affordable.
Step 5 is where "acceptable" gets decided — see below, this is the part that needs a real answer,
not a vibe.

## Monkey testing — folded into the UI rung, not a new rung

`testing-shape.md` D11 killed numbered/named extra rungs on purpose — don't reopen that by adding
a "Monkey" row to the table. Instead, monkey testing is what the **UI rung's script actually
covers** once you go looking for it: happy-path Playwright plus a pass of edge/adversarial inputs
against the same screens — empty submits, oversized strings, XSS/SQL-injection-shaped text in free
text fields, rapid double-clicks on the same action, browser-back after a submit, invalid file
uploads. Same landing-guard discipline as `e2e-ui-test-honesty.md` applies (verify you actually
landed before asserting) — a monkey test that doesn't check where it ended up produces exactly the
same false-positive/false-negative noise a happy-path test does, just with uglier inputs.

Two real findings from the first run this was done properly (a graph-migration project, 2026-08-13),
kept here because they're the kind of thing this pass is *for*, not because they're project-
specific: (1) full-page `goto()` navigation straight to a deep-link URL was flaky enough to cause
either a false "not found" or a silent full session loss — a defect the happy-path suite's own nav
helper had been quietly routing around for months; (2) two rapid conflicting workflow decisions on
the same task correctly blocked the second click but left neither decision persisted and no
explanation on screen — the guard worked, the UX around the guard didn't. Neither would have
surfaced from a scripted happy-path walk.

## Defining "acceptable" — researched pass, 2026-08-13

Grounded against DORA, Google's diff-scoped mutation testing, 2026 agentic-review-gate practice
(Tricorder's 90% precision floor, CodeRabbit/Tenki staged-trust patterns), and SRE error-budget
policy. Full citations and reasoning: see the research below the table. Two structural corrections
this pass made to the original draft: (1) most published gates are **rate-over-a-window**
judgments (DORA's change failure rate, Netflix Kayenta's canary score), not single-change static
bars — a module clearing the table once is not the same claim as "this loop is reliable"; (2) a
previously-passing check is not evidence for a *re-run* of similar-but-not-identical work — LLM
output is non-deterministic run to run, so nothing here grandfathers.

| Gate | Acceptable means | Not acceptable |
|---|---|---|
| Build (step 2) | 0 mxbuild errors, 0 unaddressed lint findings above the project's own severity bar. A **newly authored** lint rule runs advisory-only for its first pass before it's allowed to block — don't trust an unvalidated check to gate (Tricorder's 90%-precision-before-blocking pattern) | Any error; a "warnings are fine" shrug on a rule the project itself enabled; a brand-new rule blocking on day one with no false-positive check |
| UI+Data (step 3) | Every declared scenario passes with a landing-guard-verified pass, every write has a corresponding Data assertion (or a documented reason one doesn't apply). A prior pass on a modified/regenerated script is **not** carried forward — re-run it | A green UI report with no landing guard (see `e2e-ui-test-honesty.md`); trusting a stale pass because "it passed last time" on since-changed code |
| Monkey (step 3) | Zero unhandled crashes is a legitimate flat bar — crash-on-input is unambiguous, unlike fuzzy review findings, so this is the one rung where a hard binary is correct as-is. Track findings-per-module as a trend reviewed at coherence-pass cadence (DORA-style rate framing), not just per-module pass/fail | Skipped because happy-path was green; a crash or silent data-loss dismissed as "edge case, unlikely" without a decision recorded; a rising defect trend across modules treated as N unrelated one-offs instead of a process signal |
| Coherence (step 4) | Every finding carries **two independent labels**: `Measured`/`Judged` (how sure) and a severity tier (how much it matters) — don't let a documentation-drift finding cost the same review overhead as a dead-wiring defect. Declare a token/iteration budget cap for the pass before running it | Every finding treated as equally must-own regardless of severity; an open-ended pass with no budget cap (measured: a first review-agent run overran its expected cost 4x and did not self-report the overrun) |
| Confirm (step 5) | A human (not the agent that just built it, and not the agent that reviewed it) looked at the running app before the module is marked done — independent review is the one point every source consulted converges on without exception. Confirm the monkey/positive-control pass being relied on ran against *this* version, not an earlier one | The agent self-certifying its own build as done with no independent look; citing an earlier positive-control run as if it still applies to changed code |
| *(new)* Loop bound | A declared max retry/iteration count per script/module, escalate to a human on hitting it regardless of current pass/fail state | Indefinite silent retries; declaring victory only when it happens to pass, without surfacing how many attempts it took to get there |

### Why these sources, briefly

- **DORA** (dora.dev) frames change failure rate as a rate over many deploys, not a per-change
  bar — and its 2025 AI report concludes AI amplifies the existing process rather than fixing it,
  which is the argument for treating "acceptable" as a property of the *loop*, not a per-gate
  checkbox.
- **Google's diff-scoped mutation testing** (arXiv:2102.11378) validates this loop's existing
  shape — gate per-module/per-diff, not one global score. A 2026 practitioner note on
  LLM-authored test suites found mutation score can stay flat (53%, unchanged across 4 iterations)
  even as line coverage looks fine — the same failure shape `testing-shape.md` §6's positive-control
  rule already guards against by hand; this pass makes that link explicit rather than treating
  mutation-testing thresholds as a separate, unadopted idea.
- **Tricorder / CodeRabbit / Tenki (2026 agentic-review sources)** converge on: stage new checks
  advisory-before-blocking at a ~90% precision floor, don't grandfather a clean streak because
  agent output is non-deterministic run to run, cap spend/iterations per run, and never let the
  agent that authored a change be the gate for it.
- **SRE error budgets** (sre.google/workbook) model a quality bar as triggering a *policy
  response* (freeze + reprioritize) when exhausted, not a single rejected artifact — informs the
  loop-bound row: hitting the cap should trigger "stop and get a human," not "keep looping."

## Validating the loop itself — seeded-defect pass (recommended over a sandbox project)

Researched conclusion: **don't build a dedicated disposable sandbox project.** Every defect
currently on file in `testing-shape.md` §4 and `process-coherence-pass.md` was found the expensive
way — on real work, after the fact. That already proves the loop *can* catch these classes; what's
actually unmeasured is **recall on the first unprompted pass**, and a sandbox doesn't fix that:
building one costs 1-3 modules' worth of scaffolding before you can test anything, and a sandbox
built by someone who already knows the loop's blind spots will unconsciously build toward exactly
those blind spots — reducing its value as a stress test versus real, organically-grown work.

Cheaper alternative, same evidence: a **seeded-defect pass** on a copy of an already-built module
(this is `testing-shape.md` §6's "prove the assertion can fail" principle applied one level up, to
the loop as a whole, not a new concept):

1. Snapshot/branch one existing module that already has an association, an AI-scaffolding
   component, and ideally something workflow-adjacent.
2. In a session that will **not** also run the completion loop, plant a small sealed set (3-6) of
   known defects, one per category the loop claims to catch: a dead-wiring button, an unreachable
   workflow/enum terminal state, a cross-BRD vocabulary mismatch, a silent swallowed error handler,
   an access-rule gap. Keep the list sealed from whoever runs step 3.
3. Run the full loop (build → gate → prove → cohere → confirm) blind to the seeded list.
4. Score **recall** (seeded defects found / planted) and **precision** (false alarms against
   defect-free parts of the same module) — the same two numbers the Tricorder precision-floor
   pattern says matter before trusting a check as blocking.
5. Low recall names which *stage* is unreliable, cheaply, against a fully-controlled defect set,
   before trusting the loop unsupervised on real client work.
6. Only build dedicated sandbox infrastructure if this reveals a category the existing project
   genuinely can't exercise (e.g. no workflow module to seed a state-machine defect into) — and
   then build only the minimum addition to close that specific gap.

Full research trace (citations, source URLs, confidence levels per claim) is in the 2026-08-13
research-agent output referenced from that project's session log; this section is the
distilled, project-agnostic result. Next step when someone picks this up: run the seeded-defect
pass on a real module and record recall/precision here as the first actual data point.
