# Design Artifacts — Design System & Wireframes Before Pages
**Purpose:** Produce the UI/brand layer of the architecture phase — a versioned design system, then wireframes for every screen — so page-building has a visual spec to hit and the eventual Atlas theme is generated, not hand-tweaked screen by screen.
**Upstream:** `migration-pipeline.md` Phase 6 (`.mx-brd.json`), source screenshots, BRD `pages`/`useCases`
**Downstream:** `iterative-build-loop.md` (its Step 11 screenshot-coverage check verifies built pages against the wireframes produced here)
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

## Step 0: Establish the Branding Basis (an analysis input — ask)

Branding is an input, not an afterthought. Before designing, resolve the basis explicitly:

| Basis | When | Effort |
|---|---|---|
| **Client branding guidelines** (logo, palette, type, spacing) | Real project — request them as an analysis deliverable | depends |
| **Atlas defaults** | POC / no brand yet — matches the actual build target 1:1 | zero |
| **Neutral placeholder palette** (the `dataviz` reference palette) | Design-forward but brand-agnostic, swap later | low |

For a faithful rebuild POC, **Atlas defaults** are usually right — the wireframes then look like what Mendix will actually render, so coverage comparison is like-for-like. Record the choice; it cascades into every token below.

---

## Step 1: Build the Design System FIRST (one versioned file)

A single self-contained `design/design-system.html`: **the versioned source of truth.** Wireframes reference its tokens; the Atlas theme is generated from its mapping table.

Contents:
- **Tokens as CSS custom properties:** brand ramp, accent, status (reserved), spacing, radius, type scale, shadow, motion — plus a full **light + dark** set. Dark mode is *selected* (its own steps), never an automatic flip.
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

## Output of This Skill

```
design/
  design-system.html           ← tokens + components + Atlas mapping (source of truth)
  wireframes/
    <Screen>.html              ← one per surface, with binding-annotation table
  screenshots/                 ← source screenshots copied in (tier-1 ground truth)
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
- **Hand-picking chart/KPI colors.** Bypasses the `dataviz` validator — ship colorblind-unsafe data. Use the validated palette.
- **Generative design for screens that have a source screenshot.** Invents divergence you then correct back toward the source.
- **Treating the design as a throwaway mockup.** It's the spec the coverage check depends on — version it in-repo, don't paste it into a chat and lose it.
- **Building the wireframe as a page count of routes.** Misses the dialogs/popups that are most of the real UI surface.
