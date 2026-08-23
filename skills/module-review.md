# Skill: module-review — one pass per module: does it build, does it work, does it make sense

**Applies to:** every module, before it is called done.
**Replaces** `module-completion-loop.md` and `ui-review-loop.md`, which were two skills for one
job. Two files meant one of them got skipped — and the one that got skipped was always the
looking. That is how a module ships with 31/31 green checks and a broken grid on screen.

**There is one pass. It has five stages and one report.** Do not split it back apart.

---

## The five stages

```
1. BUILD    mdl-agent drafts + validates MDL (mxcli check --references, 0 errors)
2. GATE     bin/exec.sh (snapshot -> exec -> mxbuild -> auto-restore on failure)
            gate-agent confirms 0 mxbuild errors, lint clean
3. PROVE    one command runs the mechanical rungs: `project-bin/verify-module.sh <Module>`
            — conformance-check + graph-sweep + coverage-check (model-side, parallel) +
            journeys (UI/Playwright + Data/OQL + Trace/OTel, one ordered walk via
            journey-runner.js) + journeys-control (positive control — proves the journey
            could have failed) + monkey (crash net). This IS the UI (Playwright) + Data
            (OQL/DB) + monkey rungs named above, run as one instrument, not a second pass
            alongside them. wiring-sweep.md (every clickable element on the page, not just
            what a journey visits) runs alongside it but by hand, deliberately outside
            verify-module.sh — skills-over-scripts.md: the verdict on an ambiguous click
            stays a judgement call, not a script. It is NOT optional and it leaves a file:
            test-agent writes .claude/loop/sweep/<Module>/sweep.md, first line the
            denominator "N of N interactive elements swept across P of P pages". No file
            means the sweep did not happen, and the gate says so. Deep form when an
            instrument is green and you cannot say what would have made it red:
            journey-proof.md
4. LOOK     THE INTELLIGENCE CHECK — a human-equivalent pass over every screen in
            the module. Is it logical? Does it look right? Does it match our design?
            Stages 1-3 cannot answer any of those. This is the stage that gets
            skipped, and it is the stage the escaped defects come from.
5. CONFIRM  one report, explicit denominator, a human look, then next module
```

Stages 1–3 are cheap and mechanical. **Stage 4 is the one with the yield** and the one that
costs attention. Budget for it; do not let a green stage 3 buy an exemption from it.

---

## Stage 4 — the intelligence check

### 4a. The page set is every page in the module, not the pages a test visited

Derive it from the model, not from the journeys:

```bash
./mxcli -p <project>.mpr -c "SHOW PAGES IN <Module>"
```

Every page in that list gets looked at. **A page no journey touches is not out of scope — it is
the highest-risk page you have**, because nothing has ever exercised it. In the 2026-08-19
incident the escaped defects were a native Workflow task-detail page (zero coverage since it was
built, never opened by any journey) and a grid on a module that simply was not run that session.
Both were invisible to a report that enumerated only what ran.

Record the page set and its size in the report. `12 of 12 pages reviewed` is a claim.
`reviewed the module` is not.

### 4b. Run the mechanical sweep first, then look at what it cannot see

```bash
node tests/e2e/design-audit.js               # live app
node tests/e2e/design-audit.js --static-only # app down — model+CSS only
```

Where the program and your eye overlap, **the program wins**: it reads every page in one sweep,
it is deterministic, it carries a positive control, and it does not get bored on page 40.

| Dimension | Owner |
|---|---|
| Invented classes; classes in `design/ds.css` never promoted to the deployed theme | `design-audit.js` |
| Raw `class` where a sanctioned `designProperty` exists | `design-audit.js` |
| Accessibility — axe serious/critical, one `h1`, landmarks | `design-audit.js` |
| Horizontal overflow at three widths | `design-audit.js` |
| **Everything below in 4c/4d/4e** | **you** |

**Guard — mxcli #891:** an object-list item's content-slot children are never read, so a
DataGrid2 inside an Accordion describes as an empty group and the sweep reports clean *without
having looked*. Any page marked `partially-read` must be reviewed by hand and must never be
reported as a clean mechanical pass.

**If `design-audit.js` is not installed**, say so as its own finding and run 4c–4e unaided — but
do not silently absorb its scope. Four dimensions are then UNMEASURED for every page, and a
report that does not say so is the false green this stage exists to prevent.

### 4c. Is it logical? — the question nothing else asks

Navigate **via the nav menu or a button, never a direct URL** — this exercises real navigation,
which is where overlay and toggle bugs hide.

For each page, ask and answer in writing:

- **Would a real person understand what this screen is for within five seconds?** If you have to
  read the microflow to know, the screen is wrong.
- **Is the information hierarchy right?** The thing the user came for should be the thing they
  see first. A KPI buried under a filter bar is a finding even if every widget works.
- **Are the affordances honest?** Is "Start" offered on an already-Finished record? Is a button
  shown that the current role cannot use?
- **Does the empty state say something true?** Every grid and gallery, at zero results. A blank
  region is a defect; "No items found" on a page whose query is broken is a *worse* defect,
  because it is a lie the user will believe.
- **Does every displayed field actually show its value?** Especially DateTime, enum, and
  calculated fields. A blank where data must exist (a system `createdDate` can never be null) is
  a render bug, not missing data. Confirm the binding in MDL, then treat a persistent blank as P1.
- **Submit every New/Edit form with required fields empty.** A visible validation message must
  appear. A 4xx/5xx with no user-facing feedback is high-severity silent failure, not a pass.
- **Does every View/Edit/action button point at the *current* page?** Confirm with
  `DESCRIBE PAGE Module.Page` — superseded pages from an earlier build script survive as live
  targets and nothing mechanical notices.

### 4d. Does it look right, and does it match our design?

Class correctness, a11y, structure and overflow are 4b's job — do not re-check them by eye. What
remains is the judgement a diff cannot make.

**Every page gets a written visual verdict. Which yardstick you use depends on what exists — but
"no wireframe" is never an answer, and neither is "looked fine".** The three yardsticks, most
authoritative first; use the best one available and *say which one you used*:

| Available | Assess against | Verdict must state |
|---|---|---|
| A wireframe for this page | the wireframe — the design that was agreed | `vs wireframe` + the divergences |
| No wireframe, a design system exists | the design system, plus §4c's intent questions | `vs design system` + what had no spec |
| Neither | **design judgement, unaided — see the rubric below** | `unaided judgement` + the rubric rows that failed |

**1 — Against the wireframe, when one exists.** Serve the design folder (`python3 -m http.server`
if `file://` is blocked) and screenshot side by side. Compare **structure and intent**: is a
region missing, is the hierarchy inverted, did an affordance the wireframe implied never get
built. *A page can have a perfect class sweep and still be the wrong page.* Divergence is not
automatically a defect — a deliberate improvement is fine — but it is always a **finding to
state**, so someone can confirm it was deliberate.

**2 — Against the design system, always**, including on pages that have a wireframe. A page built
from no design input at all (common with native Mendix Workflow UI, which arrives unstyled) is a
finding in its own right, not an absence of one.

**3 — Unaided design judgement, when there is neither.** This is the case the loop kept treating
as an exemption, and it is not one: a user looking at that page has no wireframe either. Run these
nine rows per page and write a one-line verdict for each. They are ordinary interface-quality
questions — nothing here needs a spec to answer:

| # | Ask | A finding looks like |
|---|---|---|
| 1 | **Is there one clear primary action, and is it the visually dominant one?** | three equally-weighted buttons; the destructive action styled like the primary |
| 2 | **Is the vertical rhythm consistent** — do like elements share spacing, do sections separate? Judge against `design-spacing.md` §2's scale, measured from the screenshot: 0px between two sections is always a finding; same-level boundaries at different gaps is a finding | one card 8px from its heading and the next 40px; a wall with no grouping; a new section starting flush against the previous one |
| 3 | **Is alignment intentional?** Does anything sit on an axis nothing else shares? | a stray right-aligned field in a left-aligned form; ragged column starts |
| 4 | **Is the type hierarchy legible at a glance** — heading, label and body distinguishable without reading? | everything at one size and weight; a label heavier than its heading |
| 5 | **Does the page use the width it has?** | a 300px form stranded in a 1600px viewport; a grid squeezed into a third of the page |
| 6 | **Is anything unfinished on show?** | placeholder text, `New Page`, `Untitled`, a lorem string, a default Atlas icon standing in |
| 7 | **Would you put this in front of the customer tomorrow?** If no, say the reason in one sentence. | "the header and the grid look like they came from two different apps" |
| 8 | **Is the page shell right — nav chrome, breadcrumb, page title/H1, top padding — not just the content region?** Against the wireframe's shell when one exists; unaided otherwise. The scaffold every full page owes is `design-spacing.md` §3 — a page without it is a finding regardless of yardstick. | no page title where the wireframe has an H1; an un-skinned default nav bar; content starting flush under the breadcrumb; a sidebar design shipped as a top-bar app with nobody deciding that |
| 9 | **Is every field the design names actually present and populated?** Count fields against the wireframe/spec — a missing field is not a spacing quirk. | "Product number" in the wireframe, absent on the page; a grid cell blank where data must exist |

Rows 1–6 are specific enough to be arguable, which is the point. **Row 7 is the one that must not
be softened** — a reviewer who would not show the page but reports no P1 has recorded a false
green in the only place that mattered. If the answer is no, that is at minimum a P2 with the
sentence attached.

**Rows 8–9 run on every page, whichever yardstick applies** — they were added after 2026-08-22,
when a Station page passed its LOOK review with no page title at all, an unstyled default nav bar,
a field missing outright, and ragged field layout, because the rubric only ever interrogated the
content region and the reviewer verified layout from CSS, not pixels (see the rule below).

**The pixel rule: a visual verdict cites what the screenshot shows, never what the CSS declares.**
The 2026-08-22 escape was written as *"fields render in a clean 4-column grid
(`grid-template-columns: repeat(4,1fr)`) matching the wireframe"* — the property existed, the
render was ragged, a field was missing, and the claim was false. `getComputedStyle` is for
root-causing a symptom your eye already found (next bullet); it is never itself evidence that a
page looks right. If a verdict's evidence is a CSS property and not a described screenshot, the
page has not been looked at.

- **Root-cause every visual symptom.** Misaligned, floating, oddly spaced → inspect
  `getComputedStyle` and `getBoundingClientRect()` on the container *and its children*. Mendix
  native widgets wrap content in fixed structural children (gallery →
  `.widget-gallery-top-bar` / `-content` / `-footer`). A custom grid/flex class on the wrong DOM
  level is the common, easy-to-miss cause. See `learned-stylegallery.md`.
- **Capture below the fold.** Atlas often scrolls `.mx-scrollcontainer-center`, not
  `document.body` — find where `scrollHeight > clientHeight` and scroll that.

### 4e. Is the built component reused, or reimplemented?

Visit the StyleGallery home page. For every component there — badges, steppers, cards,
empty-states, KPI tiles — that is **not** applied to the page you just reviewed, even where the
page uses a plain equivalent, record a reuse gap citing the exact gallery section. A plain-text
status column next to a built badge component passes every mechanical check and is still wrong.

### 4f. Cross-check against what was actually asked for (high value, optional)

Spawn `ba-agent` in the background while you review, to report with intended-vs-built citations:
use-cases with no built page or microflow; wireframes with no matching page; `roles` intent vs the
real security matrix; documented fit-gap items never addressed; and **every CONFIRMED decision vs
whether it was actually built** — a confirmed decision silently not executed is a BLOCKS finding
(`conversion-runbook.md` Stage-4 reconciliation).

---

## Degrade to judgement, never to silence

**The rule itself lives in `skills/degrade-to-judgement.md` — baseline routing, governing, and it
applies to every pass in the toolkit, not just this one.** In one line: *a missing input changes
what you assess against, never whether you assess.* Every degraded row carries all three of
**Named** (which input was missing, by path), **Substituted** (what you assessed against instead),
**Still a verdict** (per page, per dimension). `UNMEASURED` is legitimate only for a *mechanical*
dimension — never for a judgement one, because your judgement was available the whole time.

What follows is the worked table for *this* pass. It is an application of that skill, not a
second copy of it; when the two disagree, that skill wins.

| Missing / stale | Assess against instead | Report line |
|---|---|---|
| No wireframe for a page | design-system specs + the brief's screen intent; if neither, §4d's unaided-judgement rubric | `⚠ No wireframe for <Page> — visual verdict from <design system \| unaided rubric>` |
| No design system either | §4d rubric rows 1–9 + Atlas conventions. **Every page still gets a written verdict** | `⚠ No design system — visual verdict is unaided judgement, rubric rows cited` |
| No StyleGallery | 4e's question survives without it: is any component on this page a hand-rolled version of something the app already builds elsewhere? Compare against sibling pages | `⚠ No StyleGallery — reuse checked against sibling pages, not a gallery` |
| No module brief | 4c and 4d run unchanged. For 4f, fall back to the BRD, then to the requirements the module was built from, then to the build-plan row | `⚠ No brief for <Module> — intent taken from <BRD \| build plan>; scope may be wider than reviewed` |
| Wireframe older than the page's last build script | compare anyway, flag as possibly stale | `⚠ <Page>.html older than build — divergence may be intentional` |
| No `design-audit.js` | 4c–4e unaided. Class promotion, a11y, structure and overflow are genuinely UNMEASURED — say so per page; do **not** claim them from eyeballing | `⚠ No design-audit.js — class promotion, a11y, structure, overflow UNMEASURED on every page` |
| Page marked `partially-read` (#891) | review that page fully by hand | `⚠ <Page> partially read — its clean sweep did not look at the whole page` |
| Project not wired to the toolkit | run this skill ad hoc, from the running app + whatever requirements exist | `⚠ Project not wired — run bin/sync-project.sh; finding #0` |
| An instrument faulted (exit 2) rather than being absent | the fault is a **handoff to judgement**, not an exemption: assess that dimension by hand and report both — the fault, and your verdict | `⚠ <instrument> FAULTED — <dimension> assessed by hand instead; see finding <n>` |
| Something is missing that this table does not list | the same three rules: name it, substitute the best remaining yardstick, still deliver a verdict | `⚠ <what> missing — assessed against <what instead>` |

**The last row is the important one.** This table cannot enumerate every way a project can be
half-wired. When you meet a gap it does not cover, the answer is never "not applicable" or a
silent skip — it is to say what is missing and then use your own judgement against the
requirements and the process, exactly as the named rows do.

---

## Diagnostic only

This pass **never fixes anything**. Diagnosis and repair stay separate passes, or you end with a
half-fixed unverified state and no record of what was wrong. Before asking what to fix, run
`finding-disposition.md`'s closing procedure: every P1/P2 routed through `close-the-loop.md` to
`docs/improvement-register.md` (never left only in this report), every page/journey that 4a's
denominator named but this run didn't reach given a named reason, and any harness fault fixed now
or logged. Then finish by asking **"Which P1/P2 findings shall I fix?"** (per `finding-disposition.md`,
this now also covers harness gaps: which to fix now versus log for later).

---

## Stage 5 — the report, and what it is allowed to claim

One self-contained HTML report, screenshots embedded base64, saved with the design artifacts
(`design/ui-reviews/ui-review-<YYYY-MM-DD>.html`). Sections: Summary · P1 · P2 · P3 · Reuse gaps ·
(if ba-agent ran) BA/design conformance.

**The headline states the denominator — and the commit it was true at.** Not a footnote — the
headline.

```
<Module> · 12 of 12 pages reviewed · stage 3: 2 of 6 journeys executed
  VALID AT: <project repo short-hash at review time>
  NOT RUN this session: <named journeys>
  UNMEASURED: <named dimensions, if any instrument was absent>
```

**Every reviewed page cites its screenshot — the PROOF-OF-LOOK block.** The pixel rule (stage 4)
says a verdict cites what the screenshot shows; this is the part a checker can verify. The report
carries one line per reviewed page, greppable in the HTML (a `<pre>` block is fine), path relative
to the report file:

```
PROOF-OF-LOOK: <Module.PageName> = shots/<YYYY-MM-DD>/<Module.PageName>.png
```

Save the actual capture files under `design/ui-reviews/shots/<date>/` **and commit them with the
report** — the base64 embeds inside the HTML are for display; the files on disk are the proof.
`obligation-check.sh` verifies mechanically: at least as many citations as the headline's
reviewed-page count; every cited file exists and is ≥ 10 KB (a real full-page capture is hundreds
of KB — a blank render or a placeholder is not); every file newer than the `VALID AT` commit
(citing a previous review's screenshots fails). **A report that fails any of these is treated
exactly like no report.** A CSS export, a `getComputedStyle` dump, or a DOM snapshot can never
satisfy it — which is the point: the 2026-08-22 escape (verdicts written from declared CSS while
the render was broken) becomes mechanically impossible to repeat, not just prohibited in prose.
Reports dated before 2026-08-23 predate the rule and are left alone.

**A LOOK report expires when the module changes.** Any BUILD/GATE commit that touches the module
after `VALID AT` invalidates stage 4 for that module — the module is no longer "reviewed", it is
"reviewed as of a model that no longer exists". The check is one command:
`git log --oneline <valid-at-hash>..HEAD -- <module's mdlsource dirs> <the .mpr>` — any output
means re-run stage 4 before citing the report. Measured consequence, 2026-08-22: a month-old
green report was cited for a page that several later build sessions had changed underneath it,
and the page in front of the user matched nothing in the report.

Three claims that must never be merged:

| Claim | What proves it |
|---|---|
| *These N flows are provably correct* | the journeys that actually executed **this run** |
| *The module is complete* | stage 4a's page set — the surfaces nothing touches |
| *It is presentable / demo-ready* | a human looking at it |

Stage 3 proves the **first only**. **"All green" is a banned phrase** whenever the denominator is
not the whole set: a journey that did not run is *absent*, and absent is never green.

**Name what the harness structurally cannot see**, every time, verbatim enough that it reads as a
boundary and not as boilerplate:

- **Any page off the literal click path.** A journey advancing through a grid's inline buttons
  never opens a single station's detail page. That page can have had zero coverage since it was
  built and no report will ever mention it, because reports enumerate what ran, not what exists.
- **Visual and styling regressions**, even on a covered page. Text-presence and DB-state
  assertions cannot tell styled-but-empty from unstyled-but-populated: *both pass* whenever the
  underlying write is correct — this is exactly what stage 4 exists to catch instead.
- **Cell-level rendering** on a grid the journey does not otherwise assert against.

Severity: **P1** user cannot complete a task (unclickable nav, silent save failure, blank required
field, empty grid with no message, button wired to the wrong page). **P2** confusing, inconsistent,
diverges from intent, or a built component not reused. **P3** polish.

Each finding: page, element (by `mx-name-` class), what is wrong, the **root cause** not the
symptom, and a wireframe-vs-live side-by-side where a wireframe exists.

**A fix found faster in Studio Pro than the root cause was found is not a closed bug.** Record it
as unexplained or it will return.

**Before closing the pass, append every P1/P2 to `docs/improvement-register.md`**
(`improvement-register.md`) — one row per finding, with its defect class from that skill's fixed
vocabulary. This is what turns "did this recur" from an archaeology project across dated HTML
reports into a grep, and it is how the trend line the Acceptable table below asks for actually
gets tracked.

**Before any live demo, manually click through exactly what will be shown** — the actual path, in
the actual order. Stage 3 green is necessary, not sufficient, and the gap is widest on the
surfaces built last, which are the ones being demoed.

Then: reopen Studio Pro, propose Run Locally, and get an **independent** human look — not the
agent that built it, not the agent that reviewed it. That is the one point every source on review
practice converges on without exception.

---

## Defining "acceptable"

Researched 2026-08-13 against DORA, Google's diff-scoped mutation testing, 2026 agentic-review
gate practice (Tricorder's 90% precision floor; CodeRabbit/Tenki staged trust) and SRE error-budget
policy. Two structural points: most published gates are **rate-over-a-window** judgements, so
clearing the table once is not "this loop is reliable"; and **nothing grandfathers** — agent output
is non-deterministic run to run, so a prior pass is not evidence for a re-run of changed work.

| Gate | Acceptable | Not acceptable |
|---|---|---|
| Build (2) | 0 mxbuild errors, 0 unaddressed lint findings above the project's bar. A **newly authored** lint rule runs advisory-only for its first pass | any error; "warnings are fine" on a rule the project enabled; a day-one rule blocking with no false-positive check |
| Prove (3) | every declared scenario passes with a landing-guard-verified pass; every write has a Data assertion or a documented reason it does not apply; re-run after any change | green UI with no landing guard; trusting a stale pass on since-changed code |
| Monkey (3) | zero unhandled crashes — a legitimate flat bar, crash-on-input being unambiguous. Track findings-per-module as a trend | skipped because happy-path was green; a crash dismissed as "edge case"; a rising trend read as N unrelated one-offs |
| **Look (4)** | **every page in 4a's set reviewed, each with a written answer to 4c's questions and a 4d visual verdict naming its yardstick (wireframe / design system / unaided rubric); every degradation named, substituted and still carrying a verdict; every verdict's evidence a screenshot, not a CSS declaration; the report stamped `VALID AT` a commit and carrying a `PROOF-OF-LOOK:` citation per page, each pointing at a real capture file on disk** | **sampling the pages a journey happened to visit; "looked fine"; a clean `design-audit.js` reported as "the UI is reviewed"; a missing wireframe or uninstalled instrument treated as a reason to skip a page rather than to change yardstick; a layout claim proven by `getComputedStyle` instead of pixels; citing a report the module has been built past** |
| Confirm (5) | an independent human looked at the running app; the denominator is in the headline | the agent self-certifying; citing an earlier control run as if it still applies |
| Loop bound | a declared max retry count per module; escalate to a human on hitting it regardless of pass/fail | indefinite silent retries; declaring victory without surfacing how many attempts it took |

---

## Validating this loop — seeded-defect pass

**Do not build a disposable sandbox project.** Every defect on file was found the expensive way,
on real work; what is unmeasured is **recall on the first unprompted pass**, and a sandbox does
not fix that. It costs 1–3 modules of scaffolding, and one built by someone who knows the loop's
blind spots will unconsciously build toward them.

Cheaper, same evidence — on a copy of an already-built module:

1. Snapshot one module that has an association, a scaffolded component, ideally something
   workflow-adjacent.
2. In a session that will **not** run the review, plant a sealed set of 3–6 defects, one per
   category this loop claims to catch: dead-wiring button, unreachable workflow/enum terminal
   state, cross-BRD vocabulary mismatch, silently swallowed error handler, access-rule gap, **an
   unstyled page**.
3. Run all five stages blind to the list.
4. Score **recall** (found / planted) and **precision** (false alarms on defect-free parts).
5. Low recall names which *stage* is unreliable, cheaply, before trusting the loop unsupervised.
6. Build sandbox infrastructure only if this reveals a category the real project cannot exercise.

Not yet run. The first team to run it records recall/precision here as the first data point.

---

## Anti-patterns this loop prevents

| Anti-pattern | What goes wrong |
|---|---|
| **Reporting stage 3 green as "demo-ready"** | proves specific flows only; says nothing about the pages it never opened or how any of it looks. This is the 2026-08-19 incident |
| **Reviewing only the pages a journey visited** | the page with no coverage is the one that breaks live |
| **Skipping a dimension because its artifact is missing** | a skipped check and a passed check look identical in the report. Degrade to judgement, name the substitution |
| Treating mxbuild-clean + "record created" as done | blank fields, unclickable nav, empty grids all pass |
| Navigating by direct URL instead of clicking | overlay/toggle bugs that swallow clicks are never exercised |
| Describing a visual symptom without the computed-CSS root cause | "looks weird" produces no fix; the wrong-DOM-level bug survives |
| Skipping the visual pass when no wireframe exists | degrade loudly against the design system instead |
| Fixing during the review | half-fixed unverified state |
| Never checking the StyleGallery | built components rot while pages reimplement them as plain text |
| Eyeballing classes, a11y or overflow page by page | 4b does it deterministically with a positive control; by hand it degrades after page 20 |
| Treating a clean `design-audit.js` as "the UI is reviewed" | it cannot see a silent 4xx save, a missing empty-state, or a wireframe region never built |
| **Answering "did we already catch this?" by grepping an old report** | a prior report is a lead, never a verdict: it can only mention defects someone thought to write down, and it may be stale. The answer to "check our reports" is re-running the wireframe-vs-live comparison now, then citing the report as history. 2026-08-22: a text-search for "top bar" found nothing; the actual side-by-side found six findings in one look |
| **Verdicting the content region and never the shell** | nav chrome, breadcrumb, page title and top spacing are on every screen the user sees; a rubric that stops at the card border ships a page with no H1 and calls it reviewed (rubric rows 8–9 exist because of this) |

## Related

- `skills/skills-over-scripts.md` — why stage 4 is prose and not a program
- `skills/journey-proof.md` · `skills/monkey-test.md` · `skills/wiring-sweep.md` — stage 3's instruments
- `skills/e2e-evidence-report.md` — turning a passing e2e run into a stakeholder-readable HTML
  report (this file owns the denominator rule itself; that skill points back here for it)
- `skills/process-coherence-pass.md` — the cross-module seam, run per cluster not per module
- `skills/improvement-register.md` — where every P1/P2 from CONFIRM gets appended, and the trend read across modules
