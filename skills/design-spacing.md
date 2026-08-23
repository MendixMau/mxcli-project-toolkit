# Skill: design-spacing — the spacing rhythm and page scaffold every page gets

**Applies to:** any mxcli project. Read before building any page or snippet (routed from
`ui-preflight-pages.md` step 4), and during `module-review.md` stage 4d when judging rhythm
(rubric rows 2 and 8) — the reviewer judges against the *named scale below*, not against taste.

**Why this exists (2026-08-22):** across projects, the most consistently wrong visual pattern
is the space *between* elements — a new section starting flush against the previous one, a page
with no header block, field grids spaced by inline pixel styles that differ per page. Root
cause, measured on a live page (`ProductNumberWorkflow_Station` vs `ProductNumber_Overview`,
same project, different build sessions): one page had a crumb + `RenderMode: H1` header, the
other had a crumb and **no title at all**; one used token spacing, the other inline
`gap: 12px`. Nothing mandated a scaffold, so header and rhythm quality was luck-of-the-session.
The spacing knowledge existed (`oneshot-page-structure-patterns.md` §7) but sat one hop away,
framed as a repair pattern — and a second hop is a hop that gets skipped
(the `ui-review-loop.md` lesson). This file makes it a build-time default, not a fix.

---

## 1. The scale — Atlas's, verified from source, not from memory

From `themesource/atlas_core/web/_variables.scss` (the Atlas version actually vendored in the
project — re-verify there if the project's Atlas is newer):

| Token | Value | Utility class suffix |
|---|---|---|
| `$spacing-smallest` | 2px | — |
| `$spacing-smaller` | 4px | — |
| `$spacing-small` | 8px | *(none — bare `spacing-outer-top` etc. is small)* |
| `$spacing-medium` | 16px | `-medium` |
| `$spacing-large` | 24px | `-large` |
| `$spacing-larger` | 32px | — |
| `$spacing-largest` | 48px | — |
| `$layout-spacing-*` | 24px | `-layout` |

The utilities (from `core/base/_spacing.scss`): `spacing-outer-{top,right,bottom,left,
horizontal,vertical}[-medium|-large|-layout|-none]` for **margin**, `spacing-inner-…` same
suffixes for **padding**. These are not a styling hack: Studio Pro's own **Spacing** design
property (Appearance tab) maps to exactly these classes
(`themesource/atlas_core/web/design-properties.json` — None/S/M/L → `spacing-outer-*-none` /
bare / `-medium` / `-large`), so a `Class:` value in MDL produces the identical model a
designer clicking the Appearance tab would.

**Every vertical gap on a page is one of: 0 (inside a component), 8, 16, 24, 32, 48.**
A gap that is none of these came from an inline style or an invented class — replace it.
Projects with their own design system typically alias the same scale
(e.g. `--space-1:4 … --space-6:24 --space-8:48` in `design/ds.css`); when the project defines
one, its token names win for `class:` values, but the *values* must sit on this scale.

## 2. The rhythm hierarchy — larger gap = less related

Spacing is information: the reader groups whatever sits closest (proximity). So the gap size
must follow the content hierarchy, strictly increasing outward:

| Level | Gap | How |
|---|---|---|
| Inside one component (label→input, icon→text) | 0–8px | the component's own CSS; never add spacing classes inside a gallery component |
| Between siblings in a group (form fields, buttons in a row, grid gap) | 8–16px | `spacing-outer-bottom` / `-medium`, or the group container's own gap token |
| Between groups within a section (form block → next form block) | 16px | `spacing-outer-bottom-medium` |
| **Between sections (card → card, grid → next region)** | **24px** | **`spacing-outer-bottom-large` on every section container — this is the one that is consistently missing** |
| Page padding (content vs viewport/layout edges) | 24px | the layout's `-layout` spacing; do not double it with an extra wrapper |

Three rules that follow from it:

- **A new section never starts at 0px from the previous one.** Every top-level section
  container carries `spacing-outer-bottom-large` (plus `card` where the design draws a block —
  `oneshot-page-structure-patterns.md` §6 owns the card-vs-spacing decision). Putting the gap
  on each section's *bottom* (not the next one's top) keeps the rule one-directional and
  mechanical — no page ends up with both, doubling the gap.
- **A heading belongs to what follows it.** Space above a heading ≥ 2× the space below it
  (e.g. 24 above, 8 below). A heading floating equidistant between two sections labels
  neither; one hugging the *previous* section's content labels the wrong one.
- **Same level ⇒ same gap, everywhere on the page.** Two sections 24px apart and the next two
  0px apart is the exact "wall then hole" pattern users report. Consistency beats the specific
  number chosen.

**No inline pixel styles for spacing.** `Style: 'margin-top: 12px'` or `gap: 12px` is
unreviewable (off-scale, invisible to a class sweep) and unthemable. Use the utility class; if
a real grid needs a gap, use the project's spacing token (`gap: var(--space-3)`) via a
design-system class, not a literal.

**Decorative overlays never eat clicks.** Any purely decorative positioned layer — a
`::before`/`::after` wash, gradient, sheen — carries `pointer-events: none`, always. The wiring
sweep catches the failure live (`wiring-sweep.md`, overlay row), but the class should never ship
without the property: a full-bleed `.card-hero::after` without it made a card's real buttons
un-clickable while passing every screenshot review (2026-08-23, sibling project).

## 3. The page scaffold — every full page starts with this

A page without a header block is a defect, not a style choice (`module-review.md` rubric
row 8). Before any content section, every non-popup page gets:

```
container ctnPageHead (Class: 'page-head spacing-outer-bottom-large') {
  dynamictext txtCrumb (Content: 'Home / <Area> / <Page>', Class: 'crumb')
  dynamictext txtTitle (Content: '<What this screen is>', RenderMode: H1)
  // optional, when the wireframe has one:
  dynamictext txtSub (Content: '<one-line purpose>', Class: 'page-sub')
  // page-level actions (a "+ New …" primary button) live here, right-aligned,
  // NOT floating in the first content section
}
```

- Exactly one `RenderMode: H1` per page — it is also the a11y "one h1" check in
  `design-audit.js`. Section titles are H2/H3, never a bare `dynamictext` at body size.
- Use the project design system's header component/class (`.page-head` or equivalent) when one
  exists; the Atlas fallback is the scaffold above with only stock classes.
- Popups/dialogs are exempt from the crumb, not from the title.
- The wireframe's header (title text, subtitle, actions) is part of Step 1 extraction in
  `ui-preflight-pages.md` — building the body without the header is the escape that motivated
  this file.

## 4. Review-side: judging rhythm against the scale

For `module-review.md` 4d (rubric rows 2 and 8), "is the rhythm consistent" is asked against
this file, from the screenshot (the pixel rule — never from declared CSS):

- Measure the actual vertical gaps between sections on the screenshot. Zero between two
  sections = finding, always. Gaps at different sizes for same-level boundaries = finding.
- No H1 / no header block on a full page = finding (row 8), P2 minimum.
- Spacing done with inline pixel styles where a token exists = finding, cite this file.

## Related

- `oneshot-page-structure-patterns.md` — the deep mechanics: why bare siblings collapse,
  card-vs-spacing, layoutgrid behavior. This file owns the *defaults*; that one owns *repair*.
- `ui-preflight-pages.md` — routes here before the first widget (step 4 cross-checks).
- `module-review.md` — stage 4d judges against §2's table and §3's scaffold.
- `design-artifacts.md` — the design system that may alias the scale with project tokens.
