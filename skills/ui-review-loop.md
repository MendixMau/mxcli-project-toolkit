# UI Review Loop — Post-Build Functional + Visual Verification Gate
**Applies to:** any mxcli project with built pages.

**Purpose:** The output-side counterpart to `module-brief.md` (which fixes the input side). A build
that passes mxbuild and a "record created" happy-path can still ship blank fields, unclickable
navigation, empty grids, unused components, and pages that diverge from their wireframe — **none of
which mxbuild or a naive happy-path can catch.** This skill is the required verification loop that
does: it drives the running app like a user, verifies what actually *renders*, and compares live
pages against their design intent. **Diagnostic only — it never fixes anything.**

**Upstream:** `iterative-build-loop.md` (runs this after each module's happy-path; a full pass before
Stage 6 sign-off), `module-brief.md` (the intent this verifies against)
**Companion:** `learned-skill-ux-audit.md` (deeper design-system *compliance scoring* — run that for a
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
- **If a wireframe exists** for this page: render it locally (serve the design folder with
  `python3 -m http.server` if `file://` is blocked) and screenshot it side-by-side with the live
  page. Compare structure, not just "looks okay".
- **When something looks off** (misaligned, floating, oddly spaced), don't stop at the symptom —
  inspect the live computed layout (`getComputedStyle`, `getBoundingClientRect()` on the container
  and its children) to find the CSS root cause. **Mendix native widgets wrap content in fixed
  structural children** (gallery → `.widget-gallery-top-bar` / `-content` / `-footer`; datagrid
  similar). A custom grid/flex class applied to the wrong DOM level is a common, easy-to-miss root
  cause — see `learned-stylegallery.md`.
- Note typography, spacing, layout balance, wrong-widget-for-the-data, and badge/color contrast.

### Pass 4 — Reusable component check
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
