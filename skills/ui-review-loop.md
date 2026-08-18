# UI Review Loop — Post-Build Functional + Visual Verification Gate
**Applies to:** any mxcli project with built pages.
**Requires:** bash and Python 3 — this skill runs toolkit shell scripts. Run `bin/doctor.sh` once on a new machine; it names anything missing and how to get it. Windows: use Git Bash, and see the Prerequisites section of `conversion-runbook.md`.

**Purpose:** The output-side counterpart to `module-brief.md` (which fixes the input side). A build
that passes mxbuild and a "record created" happy-path can still ship blank fields, unclickable
navigation, empty grids, unused components, and pages that diverge from their wireframe — **none of
which mxbuild or a naive happy-path can catch.** This skill is the required verification loop that
does: it drives the running app like a user, verifies what actually *renders*, and compares live
pages against their design intent. **Diagnostic only — it never fixes anything.**

**Upstream:** `iterative-build-loop.md` (runs this after each module's happy-path; a full pass before
Stage 6 sign-off), `module-brief.md` (the intent this verifies against)
**Companion:** `journey-proof.md` — **read the division of labour in "Pass 0" below before running
this loop.** Its `design-audit.js` mechanically covers class correctness, accessibility and page
structure across every page at once; this loop covers what a program cannot judge. Neither
supersedes the other, and running this one by hand over ground the audit already covers is wasted
effort with worse coverage.
Also: `learned-skill-ux-audit.md` (deeper design-system *compliance scoring* — run that for a
demo-readiness gap analysis; run THIS for a functional+visual regression gate), `ui-preflight-pages.md`
(the pre-build cross-reference this loop verifies was honored)

**Origin:** Generalized from a battle-tested project-local loop that caught, in one pass: navigation
made unclickable by a stray mobile toggle, DateTime fields blank across every surface, galleries
rendering zero cards with no empty-state, a "View" button still wired to a superseded page, and a
3-column CSS class applied to the wrong DOM level. Every check below exists because a real build
shipped the bug it catches.

---

## Why mxbuild + happy-path is not enough

| What passed | What still shipped |
|-------------|--------------------|
| mxbuild: 0 CE errors | DateTime fields render blank everywhere (correct binding, broken render) |
| Happy-path: "record created" | Top nav unclickable — a mobile toggle overlapped the desktop bar |
| Page exists in MPR | Grid renders zero rows and no empty-state message |
| Wireframe read at pre-flight | Live page added a hamburger nav the wireframe never had |
| Gallery component built | Real pages use plain text instead of the built badge/stepper |

The gap is **rendering, interaction, and reuse** — dimensions only visible by driving the running
app. This loop closes it.

---

## ⛔ Hard gate: confirm a fresh build first

`mxcli exec` writes the `.mpr`, but the browser serves a bundle compiled by Studio Pro. Without a
full SP restart + Run Locally after the last exec, every screenshot reflects the *previous* build —
making the review meaningless (and it has caused fixes for already-fixed bugs and missed live bugs).

```bash
curl -s -o /dev/null -w "%{http_code}" http://localhost:${APP_PORT:-8080}/login.html   # expect 200
```

If not 200, or SP wasn't restarted after the last exec → **stop**, tell the user to reopen the
project in SP and Run Locally, wait for confirmation. Never screenshot a stale build.

---

## Diagnostic-only rule

This loop **never fixes anything** — no MDL, no CSS, no docs, no model changes during the pass.
Findings and artifacts only. Fixes are a separate, explicitly-approved follow-up. Finish by asking
which findings to fix. (Mixing diagnosis and fixing in one pass is how half-fixed, unverified state
accumulates.)

---

## When to run

- **Per-module quick pass** — after each module's happy-path in `iterative-build-loop.md` (step 12
  area). Scope: just the pages that module built. This is the per-module gate.
- **Full pass** — before Stage 6 sign-off, and before any demo. Scope: every page, in nav order.

---

## Pass 0 — run the mechanical audit first, then review what it cannot see

This loop predates `design-audit.js`. Where the two overlap, **the program wins**: it reads every
page in one sweep, it is deterministic, it carries a positive control, and it does not get bored on
page 40. Run it before you open a browser:

```bash
node tests/e2e/design-audit.js               # against the live app
node tests/e2e/design-audit.js --static-only # app down — model-side checks only
```

Then review only the dimensions it cannot reach. The split is not negotiable in either direction:

| Dimension | Owner | Why |
|---|---|---|
| Class correctness — invented classes, classes defined in `design/ds.css` but never promoted to the deployed theme | **`design-audit.js`** | a corpus diff across every page; no human does this reliably |
| Raw `class` where a sanctioned `designProperty` exists | **`design-audit.js`** | mechanical, from the ELK describe output |
| Accessibility — axe serious/critical, one `h1`, landmarks present | **`design-audit.js`** | this loop never covered it at all |
| Horizontal overflow at three widths | **`design-audit.js`** | `scrollWidth > clientWidth`, cheap and exact |
| Does the page *do* what the user needs — nav that swallows clicks, a save that 4xx's silently, a blank DateTime, a grid with no empty-state | **this loop** | requires interacting and judging the result |
| Does the built page match the wireframe's *structure and intent* | **this loop** | a class diff cannot tell you the wireframe had a filter bar and the page does not |
| Is a built gallery component reused, or reimplemented as plain text | **this loop** | requires recognising an equivalence a class name does not encode |
| Root-causing a visual symptom to the DOM level it came from | **this loop** | `getComputedStyle` + judgment |

**Guard, and it matters:** mxcli issue **#891** — an object-list item's content-slot children are
never read, so a DataGrid2 inside an Accordion describes as an empty group and the class sweep
reports clean **without having looked**. Any page the audit marks `partially-read` must be reviewed
by hand here, and must never be reported as a clean mechanical pass.

**If `design-audit.js` is not installed in this project**, say so in the report as its own finding
and run the passes below unaided — but do not silently absorb its scope. Four of the dimensions
above will then be unmeasured, and a report that does not say so is the false green this whole loop
exists to prevent.

---

## The per-page review — four passes

For each page (navigate to it **via the nav menu or a button click, not a direct URL** — this
exercises real navigation, which catches overlay/toggle bugs):

### Pass 1 — Capture
Full-page screenshot. For any page whose content scrolls inside a nested container (Atlas often
scrolls `.mx-scrollcontainer-center`, not `document.body` — check where `scrollHeight > clientHeight`),
scroll that container and capture below-the-fold too.

### Pass 2 — Functional (try to break it)
- **Every nav item and dropdown actually opens/navigates** — don't assume. A stray overlay or
  off-canvas toggle can silently swallow every click on one page while working elsewhere.
- **Submit every New/Edit form with required fields empty** → a visible validation message must
  appear. A 4xx/5xx network response with zero user-facing feedback is a high-severity silent
  failure, not a pass.
- **State/workflow entities:** are action buttons shown unconditionally regardless of current state
  (e.g. "Start" offered on an already-Finished record)?
- **Every grid/gallery against its zero-result state:** a proper empty-state message, or does it
  render nothing?
- **Every View/Edit/action button:** confirm via MDL (`DESCRIBE PAGE Module.Page`) that it points at
  the *current* page, not a superseded one from an earlier build script — cross-reference the build
  history for pages marked superseded/dead.
- **Every displayed field actually shows its value** — especially DateTime, enum, and calculated
  fields. A blank where data must exist (e.g. a system `createdDate`, which can never be null) is a
  render bug, not missing data. Confirm the binding in MDL, then treat a persistent blank as a P1.

### Pass 3 — Visual vs design intent

**Scope note:** class correctness, accessibility, page structure and horizontal overflow are Pass 0's
job now — do not re-check them by eye here. What remains is the judgment a diff cannot make: does
this page *do what the wireframe was trying to express*.

- **If a wireframe exists** for this page: render it locally (serve the design folder with
  `python3 -m http.server` if `file://` is blocked) and screenshot it side-by-side with the live
  page. Compare **structure and intent** — is a region missing, is the information hierarchy
  inverted, did an affordance the wireframe implied never get built. A page can have a perfect class
  sweep and still be the wrong page.
- **When something looks off** (misaligned, floating, oddly spaced), don't stop at the symptom —
  inspect the live computed layout (`getComputedStyle`, `getBoundingClientRect()` on the container
  and its children) to find the CSS root cause. **Mendix native widgets wrap content in fixed
  structural children** (gallery → `.widget-gallery-top-bar` / `-content` / `-footer`; datagrid
  similar). A custom grid/flex class applied to the wrong DOM level is a common, easy-to-miss root
  cause — see `learned-stylegallery.md`.
- Note typography, spacing, layout balance, wrong-widget-for-the-data, and badge/color contrast.

### Pass 4 — Reusable component check

**Scope note:** the mechanical half of reuse — a raw `class` where a sanctioned `designProperty`
exists — is Pass 0's. This pass is the half no class name encodes: a page that reimplements a built
component as plain text is *correct* by every mechanical check and still a finding.

Visit the project's StyleGallery home page. For every component shown there (badges, steppers,
cards, empty-states, KPI tiles) that is **not** applied to the page you just reviewed — even if the
page uses a plain/unstyled equivalent — record it as a reuse gap, citing the exact gallery section.
The gallery exists to be reused; a plain-text status column next to a built badge component is a
finding.

---

## Graceful degradation (the harness for missing/changed/unwired inputs)

Every input this loop wants may be absent, stale, or the project may not be wired to the toolkit at
all. **The rule is loud degradation, never silent skip.** Each fallback is *logged in the report* so
a reader knows the pass ran with reduced fidelity.

| Missing / stale input | Degrade to | Log line in report |
|-----------------------|-----------|--------------------|
| No wireframe for a page | Compare against the design-system component specs + the module brief's screen intent | `"⚠ No wireframe for <Page> — visual pass ran against design-system + brief only"` |
| No design-system file either | Compare against Atlas conventions + general UX heuristics | `"⚠ No design system found — visual pass is heuristic only"` |
| No StyleGallery module | Skip Pass 4; note reuse cannot be checked | `"⚠ No StyleGallery — component-reuse pass skipped"` |
| No module brief | Functional passes still run; note intent could not be cross-checked | `"⚠ No brief for <Module> — functional review ran without scoped intent"` |
| Wireframe older than the page's last build script (mtime) | Run the compare but flag the wireframe as possibly stale | `"⚠ <Page>.html wireframe older than build — divergence may be intentional"` |
| Project not wired to the toolkit (no CLAUDE.local.md / no review-loop reference) | Run this skill directly anyway; report the wiring gap as finding #0 | `"⚠ Project not wired — run bin/sync-project.sh; running review ad-hoc"` |
| No `design-audit.js` (Pass 0) | Run passes 1–4 unaided. Do **not** absorb its scope by eye | `"⚠ No design-audit.js — class promotion, a11y, structure and overflow are UNMEASURED for every page"` |
| A page the audit marked `partially-read` (mxcli #891) | Review that page fully by hand | `"⚠ <Page> partially read by the audit — its clean class sweep did not look at the whole page"` |

Degradation lowers fidelity; it never lowers the bar to "pass". A page reviewed in degraded mode is
reported as such, and the missing input becomes its own finding.

---

## BA / design conformance cross-check (optional, high-value)

Spawn `ba-agent` in the background to cross-check the build against the analysis artifacts (intake,
triage, BRDs, wireframes, requirements/screens/workflows/roles, architecture fit-gap/blueprint/
build-plan) while the UI pass runs. Ask it to report, each with intended-vs-built citations and a
blocks/minor/cosmetic severity:
- Use-cases with no corresponding built page/microflow
- Wireframes with no matching built page
- `roles` intent vs. the actual security matrix
- **Every CONFIRMED decision vs. whether it was actually built** (a confirmed decision silently not
  executed is a BLOCKS finding — see `conversion-runbook.md` Stage-4 reconciliation)
- Documented gaps/decisions in fit-gap that were never addressed

---

## Output

A single self-contained HTML report (screenshots embedded as base64 — no external file deps), saved
alongside the other design artifacts (e.g. `design/ui-reviews/ui-review-<YYYY-MM-DD>.html`), with
sections: Summary · P1 · P2 · P3 · Reusable Gallery Assets · (if ba-agent ran) BA/Design Conformance.

Severity:
- **P1** — broken/missing: user cannot complete a task (unclickable nav, silent save failure, blank
  required field, empty grid with no message, button wired to the wrong page).
- **P2** — significant: confusing, inconsistent, diverges from scoped intent, or a built component
  not reused where it should be.
- **P3** — polish: spacing, label wording, minor inconsistency.

For each finding: page, element (by `mx-name-` class where identifiable), what's wrong, the **root
cause** (not just the symptom), and — for visual issues — a wireframe-vs-live side-by-side where a
wireframe exists.

Finish by asking **"Which P1/P2 findings shall I fix?"** — never fix in the same pass.

---

## Anti-patterns this loop prevents

| Anti-pattern | What goes wrong |
|---|---|
| Treating mxbuild-clean + "record created" as done | Blank fields, unclickable nav, empty grids all pass; the user finds them in production |
| Navigating by direct URL instead of clicking | Overlay/toggle bugs that swallow clicks are never exercised |
| Describing a visual symptom without the computed-CSS root cause | "Looks weird" produces no actionable fix; the wrong-DOM-level class bug stays hidden |
| Skipping the visual pass when no wireframe exists | Silent — degrade loudly against the design system instead |
| Fixing during the review pass | Half-fixed unverified state; keep diagnosis and fixing separate |
| Never checking the StyleGallery for reuse | Built components rot unused while pages reimplement them as plain text |
| Eyeballing class names, a11y or overflow page by page | Pass 0 does it across the whole corpus, deterministically, with a positive control. By hand it is slower, worse, and quietly degrades after page 20 |
| Treating a clean `design-audit.js` run as "the UI is reviewed" | It cannot see a save that 4xx's silently, a grid with no empty-state, or a wireframe region that was never built. Mechanical clean is one of two halves |
