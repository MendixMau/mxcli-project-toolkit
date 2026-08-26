# Design Artifacts — Design System & Wireframes Before Pages
**Applies to:** migration or requirements-driven build (works from documents/SME input — no legacy source needed).
**Purpose:** Produce the UI/brand layer of the architecture phase — a versioned design system, then wireframes for every screen — so page-building has a visual spec to hit and the eventual Atlas theme is generated, not hand-tweaked screen by screen.
**Upstream:** `migration-pipeline.md` Phase 6 (`.mx-brd.json`), source screenshots, BRD `pages`/`useCases`
**Downstream:** `iterative-build-loop.md` (its Step 11 screenshot-coverage check verifies built pages against the wireframes produced here); `learned-stylegallery.md` (turns the design system into a live Mendix StyleGallery module); `ui-preflight-pages.md` (mdl-agent cross-references these artifacts before every page build)
**Companion:** `architecture-blueprint.md` (the structural half of the same phase — run in parallel); `dataviz` skill (for any chart/KPI colors)

---

## When to Use This Skill

- You have module boundaries and need the *look* nailed down before building pages.
- Someone asked for "a design system," "wireframes," "the brand," or "a clickable prototype."
- You're about to build pages and have no visual reference to check them against.

---

## Why This Step Exists

A wireframe with no visual language is half a spec, and page-by-page styling produces drift. Two things must exist before the first page:
1. **A design system** — tokens (color/type/spacing/radius/shadow/motion) + components — that maps to Atlas variables, so the app *inherits* the brand.
2. **Wireframes** — one per screen, annotated with source-field → Mendix-widget mappings — so the build loop has something concrete to verify coverage against.

Get these right and the build loop's job becomes mechanical: reproduce the wireframe with real bindings.

---

## Step 0a: Capture Brand Research (before touching any CSS)

Before writing a single token, produce two markdown files that record the research and decisions
that will drive the design system. These are versioned project artifacts, not scratch notes.

**`design/brand.md`** — brand decisions document. Include:
- Palette table: each brand color with its hex, its role name (`--brand-primary`, etc.), and a
  one-line "use for" note
- Typography: chosen typeface(s) and web-safe fallback; rationale if different from client default
- Deliberate inversions: if the client's corporate brand uses color X as primary but the app uses
  it as CTA (and something else as primary), record this explicitly — e.g. "KT corporate uses red
  as primary; this app inverts: primary = black, CTA = red (one per page rule)." Undocumented
  inversions confuse every future maintainer.
- Atlas variable mapping table: `--primary → $brand-primary`, `--surface → $background-color`, etc.
  This is the bridge from your token decisions to `theme/web/custom-variables.scss`.

**`design/target-ui.md`** — UX pattern inventory from the client mockup or source app. For each
pattern found in the source (filter bar, detail form, barcode scan flow, status badge, etc.),
note: pattern name / Atlas implication (which widget type, which layout approach) / any constraint.
This bridges "what the client UI does" to "what actually needs to be built in Mendix" before
wireframing starts.

---

## Step 0b: Establish the Branding Basis ✋ (a real interview, not a footnote)

Branding is an input, not an afterthought — and not a checkbox to tick silently. Run the full interview protocol (`conversion-runbook.md` §1): propose the options below with evidence for which fits this project, state the assumption if none is given, and get an explicit answer before designing. This is a `✋` gate — record the `CONFIRMED` choice in `PROJECT.md`, it cascades into every token below and doesn't get to default silently.

| Basis | When | Effort |
|---|---|---|
| **Client branding guidelines** (logo, palette, type, spacing) | Real project — request them as an analysis deliverable | depends |
| **Atlas defaults** | POC / no brand yet — matches the actual build target 1:1 | zero |
| **Neutral placeholder palette** (the `dataviz` reference palette) | Design-forward but brand-agnostic, swap later | low |

For a faithful rebuild POC, **Atlas defaults** are usually right — the wireframes then look like what Mendix will actually render, so coverage comparison is like-for-like. Record the choice; it cascades into every token below.

---

## Step 1: Build the Design System FIRST (two versioned files)

**Two files, not one:** a separate `design/ds.css` as the physical token/component source, plus
`design/design-system.html` as the annotated showcase that links it. This split is the
drift-prevention mechanism: every wireframe links `ds.css` via `<link rel="stylesheet"
href="../ds.css">` and never redeclares a token. Change a token in `ds.css` → every wireframe
and the showcase reflect it immediately. See `learned-stylegallery.md` for the full ds.css
architecture, three-tier token naming, and SCSS porting rules.

**`design/ds.css`** — the physical CSS file containing:
- `:root` CSS custom properties for all tokens (light theme) + `[data-theme="dark"]` overrides
- All component class blocks (`.kpi`, `.kt-badge`, `.stepper`, `.form-card`, etc.)

**`design/design-system.html`** — annotated showcase that `<link>`s `ds.css` and renders:

Contents of `ds.css` + what `design-system.html` renders:
- **Tokens as CSS custom properties:** brand ramp, accent, status (reserved), spacing, radius, type scale, shadow, motion — plus a full **light + dark** set. Dark mode is *selected* (its own steps), never an automatic flip. In Mendix, use `[data-theme="dark"]` not `prefers-color-scheme` — Atlas has its own theme-toggle mechanism and media-query dark mode conflicts with it.
- **Data colors** come from the `dataviz` skill's validated palette — do not hand-pick chart/KPI colors; run its validator if you swap any.
- **Components the app actually needs** (derive from the source screens, not a generic kit): buttons, inputs + validation, table/data grid with row actions, KPI/stat tiles, badges/status pills, dialog, toast, nav shell, plus any product-specific pieces.
- **An Atlas mapping table:** each token → its Atlas SCSS variable (`$brand-primary`, `$background-color`, `$font-color`, `$border-radius-*`, `$spacing-*`, `$font-family-base`, success/warning/danger). This table is what the build phase turns into `theme/web/custom-variables.scss` + design properties.

**Render it and look at it** (headless-screenshot both light and dark) — the eye catches what code review misses. This is non-negotiable per the `dataviz` procedure.

---

## Step 2: Screen Inventory + the Input-Priority Ladder

List every UI surface (from BRD `pages`, the source, and the fit-gap's "Build (new)" rows). **"Screen count ≠ route count"** — walk dialogs/popups, not just top-level routes. Then pick each screen's design basis by this ladder:

```
1. Screenshot exists            → FAITHFUL wireframe (match it; it is ground truth)
2. No screenshot, BRD/use-case  → DESIGN FROM BRD (fields from page BRD, flow from use-case)
3. New / improved feature       → GENERATIVE (no source to match — design from scope + sibling screens)
```

For each screen also decide its Mendix surface: **top-level page** vs **popup page** vs **snippet**. Most source "dialogs" become popup pages or snippets off a main overview, not routes.

---

## Step 3: Build Wireframes FROM the Design System

Each wireframe is assembled from Step 1's components — never restyled from scratch. One HTML per screen, or a single annotated showcase. Every wireframe carries a **binding annotation** the build loop will check:

| Source field / element | Mendix widget | Datasource | Required | Read-only | Conditional |
|---|---|---|---|---|---|

This table *is* the build checklist `iterative-build-loop.md` Step 3 extracts. Getting widget type right here (combobox vs textbox, enum vs string) saves an `ALTER PAGE REPLACE` later.

---

## Step 3b: Scope Crosscheck — Every Wireframed Element Needs a Requirement

Wireframing invents structure the BRD never asked for — breadcrumbs, a back button, a filter chip, a "clear all" link. None of these are source *fields*, so they never earn a row in the binding-annotation table above, which means they never reach `iterative-build-loop.md`'s checklist either. The result ships as static chrome: it renders, but no microflow, datasource, or navigation action stands behind it — a breadcrumb with no trail logic, a button with no on-click.

Before moving to Step 4, walk each wireframe and list every interactive or structural element that has **no row** in its binding-annotation table. For each one, force an explicit call:

| Call | When | Action |
|---|---|---|
| **Cut it** | Out of scope, or a "nice to have" no use-case asked for | Remove from the wireframe — don't ship UI with nothing behind it |
| **Spec it** | In scope, just missed | Add a row/mini-spec: what generates it, what it does, what it calls. A breadcrumb needs its trail source and each crumb's nav target; a button needs the microflow it triggers |

Record the call — cut or spec'd — next to the element; a wireframe with unresolved chrome does not pass to the build loop. This is a cheap gate here versus a silent "why doesn't this button do anything" discovery mid-build.

---

## Step 4: Tooling — Own HTML Leads

| Tool | Role | Use for |
|---|---|---|
| **Hand-written HTML/CSS in-repo** | Source of truth | The design system + all faithful wireframes. Versioned; the build loop checks against it. |
| **Claude Artifacts** | Optional, clickable | A stakeholder walkthrough of the flow before building — generated from the same HTML, never the spec. |
| **Generative design tools** (Stitch / Figma AI / v0) | Narrow | *Only* tier-3 screens (new/improved features with no source screenshot). |

**Skip generative tools for faithful rebuilds.** They shine when you don't know what the UI should be; in a migration you do — the screenshots are ground truth, and any divergence a generator invents is rework that fights the faithful-rebuild goal.

---

## Step 5: Verify

- **Render every wireframe and look** (both themes).
- **Coverage check** each faithful wireframe against its source screenshot: every visible field/section present, right widget type, right state. Gaps become explicit sub-tasks — the same discipline as the build loop's Step 11, applied one stage earlier so the spec is complete before building.

---

## Step 5b: Build the StyleGallery Mendix Module

Once `ds.css` is stable and the SCSS port is complete, build the in-app StyleGallery module
that is the Mendix-rendered twin of `design-system.html`. See `learned-stylegallery.md` for the
full process: module setup, SCSS porting rules, MDL file numbering and exec order, static vs.
NPE-backed component decision, and the snippet-as-production-component pattern.

This step makes the design system testable inside the real Atlas cascade (catches issues the
standalone HTML cannot) and produces reusable snippets the build loop can call from production
pages directly.

### 5b is a GATE, not a step, and the difference is the whole point

A step is complete when the file is produced. A gate is complete when someone looked. **Producing
the gallery module and never opening it is the failure mode this rule exists for** — and it is not
hypothetical: on a 2026-08-26 field run the gallery module existed, contained exactly the three
components that turned out to be broken, passed every check, and was **in no navigation profile and
had no URL**. Unreachable in the running app. Loaded with the right ammunition, never fired. Wiring
it into navigation and opening it surfaced four real defects in one pass, three of which had already
survived a full module review.

The gate is all four, and 3 and 4 are the ones projects skip:

1. every token in `ds.css` has a matching class in the ported SCSS;
2. the gallery module builds with 0 CE errors;
3. the gallery home page is **in a navigation profile and granted to a role a demo user actually
   holds** — check with `SHOW MODULE ROLES IN <GalleryModule>`, because a security script that was
   drafted and never executed leaves every grant on the auto-created `.User` role, and then the
   first attempt to screenshot the gallery silently measures whatever the demo user lands on
   instead;
4. **someone opened it and wrote down what they saw.**

### Before you port a rule, check it can match Mendix's DOM

Tokens port; rules may not. Run `bin/check-design-portability.sh` (installed by
`sync-project.sh`) over `ds.css` before the SCSS port, not after. It checks three measured Mendix
DOM facts — rem against the app's real root font size, selectors naming HTML elements Mendix never
emits, and positional row selectors — and it exists because none of `mx check`, `mxcli check` or
`mxcli lint` can see a stylesheet at all. See `learned-stylegallery.md` → "The Mendix DOM contract"
for the facts behind each check.

**The property that makes this worth gating: a design-system defect is dormant until some widget
carries the class.** So the defects are all present from the first build and surface one at a time,
much later, as UI work attaches classes to pages. "The build is green and the pages look fine" is
not evidence that the design system is correct — it is evidence that it is not being exercised yet.

---

## Output of This Skill

```
design/
  brand.md                     ← brand decisions + deliberate inversions + Atlas variable mapping
  target-ui.md                 ← UX pattern inventory from client mockup → Atlas implications
  ds.css                       ← token + component CSS (linked by showcase + all wireframes)
  design-system.html           ← annotated showcase (links ds.css; not the token source)
  wireframes/
    <Screen>.html              ← one per surface, with binding-annotation table
  screenshots/                 ← source screenshots copied in (tier-1 ground truth)

themesource/<gallery>/web/
  main.scss                    ← ds.css ported to SCSS (resets stripped, .row renamed) — the ONLY file the app compiles; a fix landed in ds.css alone ships nothing (learned-stylegallery.md)

mdlsource/gallery/
  00-module.mdl … 90-home.mdl ← StyleGallery in-app component module
```

---

## Handoff to the Build Loop

`iterative-build-loop.md` consumes this directly:
- **Step 3 (extract build checklist)** reads each wireframe's binding-annotation table.
- **Step 7 (build pages)** reproduces the wireframe with real bindings.
- **Step 11 (coverage check)** verifies the built page against the wireframe *and* the source screenshot.
- The **Atlas mapping table** drives the one-time theme generation, so pages inherit the brand instead of being individually styled.

---

## Anti-Patterns This Skill Prevents

- **Wireframes before a design system.** Produces inconsistent screens with no shared tokens; the Atlas theme becomes a per-page cleanup job.
- **Embedding tokens in `design-system.html` instead of a separate `ds.css`.** Wireframes must redeclare tokens → drift and inconsistency between screens.
- **Skipping `brand.md` and `target-ui.md`.** Design decisions end up undocumented; deliberate inversions (primary/CTA swap) look like mistakes to future maintainers.
- **Hand-picking chart/KPI colors.** Bypasses the `dataviz` validator — ship colorblind-unsafe data. Use the validated palette.
- **Generative design for screens that have a source screenshot.** Invents divergence you then correct back toward the source.
- **Treating the design as a throwaway mockup.** It's the spec the coverage check depends on — version it in-repo, don't paste it into a chat and lose it.
- **Building the wireframe as a page count of routes.** Misses the dialogs/popups that are most of the real UI surface.
- **Skipping the Step 3b scope crosscheck.** Wireframe-invented chrome (breadcrumbs, extra buttons, filter chips) ships with no requirement behind it — it renders but has no logic, and the gap surfaces mid-build instead of at spec time.
- **Skipping the StyleGallery module.** Design system tokens go untested against the real Atlas cascade; no reusable snippet kit for the build loop.
- **Building the StyleGallery and leaving it unreachable.** Strictly worse than skipping it: the artifact exists, so every checklist ticks, and the instrument that would have caught the defects is the thing nobody opened. See Step 5b's gate, items 3 and 4.
- **Authoring `ds.css` in `rem`.** Atlas Core sets `html { font-size: 10px }`, so every `rem` renders at **62.5%** of a 16px-root design — a `1.6rem` KPI value paints at 16px, a `.75rem` badge at 7.5px. Nothing warns. Author component sizes in `px`; the app has one target platform whose root is fixed by a framework the project does not control, so the indirection buys nothing and hides a 1.6x error.
