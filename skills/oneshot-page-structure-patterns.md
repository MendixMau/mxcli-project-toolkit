# Skill: One-Shot Page Structure Patterns — Containers, Spacing, Orientation

**When to use:** you are one-shot-generating (or reviewing) a Mendix page in MDL and it needs to
look like a laid-out page, not a stack of widgets. Read this **before** writing the first
container. It is deliberately silent on branding/colour — see the "Not in scope" note — because
containers, spacing and flex/grid orientation are what actually determine whether a page has a
structure at all.

**Status:** distilled 2026-07-30/31 from diffing two one-shot-generated list pages in the same
project — one rendered correctly, the other rendered flat/stacked with no error at any gate.
Confirmed on Mendix 11.12.0 / mxcli v0.16.0.

---

## Not in scope

Button colours, badge classes, brand palettes — anything from a project's own theme file. That
lives in the consuming project's own stylesheet reference, which is project-scoped and not
transferable by design, and in `learned-stylegallery.md` for turning it into a live in-app
gallery. This file is the opposite: generic structural rules that hold on any Mendix project,
with or without a custom theme.

## 1. Pick the base Layout deliberately, not by inheritance from whatever reference page you copied

Atlas ships several page layout templates (e.g. a plain top-bar layout vs. a top-bar-plus-extra-row
variant). They are not interchangeable — each one gives the page a different amount of built-in
chrome and a different structural starting point (how much of the header/toolbar area is
layout-provided vs. something your script has to build by hand).

**Rule:** when a one-shot script references a `Layout:`, choose it because you inspected what
it provides (`DESCRIBE` a page that already uses it, or check the Atlas layout docs), not because
it's what an existing reference page in the project happened to use. Two sibling pages built from
different layouts, side by side in the same module, will visibly disagree in structure even if
every other widget is identical — and nothing will flag this as an error.

**Why:** the failure observed was exactly this — two list pages in the same project, built by two
different one-shot runs, silently ended up on two different base layouts. Nobody chose it; each
script just carried forward whatever a prior reference used.

## 2. Every header text zone needs a container per element (or around the group)

**Rule:** when a header zone has more than one sibling text/heading widget (breadcrumb, title,
subtext, etc.), each one — or at minimum the group as a whole — must sit inside its own
`container`. Do not place bare `dynamictext` / heading widgets directly as siblings in a column.

**Why:** a container is not just a hook for a branding class. It is what gives the Atlas layout
engine something to apply spacing rules against. Bare sibling text widgets with nothing between
them render pressed together with no gap, even with zero classes applied to any of them. Wrapping
each one in a plain, unstyled `container` alone fixes the spacing — the class is optional, the
container is not.

```sql
-- ❌ Renders with zero gap between breadcrumb, title, subtext
column "headerCol" {
  dynamictext "txtBreadcrumb" (Content: 'Home / List')
  dynamictext "txtTitle"      (Content: 'My List')
  dynamictext "txtSubtext"    (Content: 'A short description')
}

-- ✅ Each element has room to be spaced
column "headerCol" {
  container "cBreadcrumb" { dynamictext "txtBreadcrumb" (Content: 'Home / List') }
  container "cTitle"      { dynamictext "txtTitle"      (Content: 'My List') }
  container "cSubtext"    { dynamictext "txtSubtext"    (Content: 'A short description') }
}
```

## 3. Two orientation techniques exist — pick one per container, and don't mix inconsistently between siblings

Both of these are legitimate, supported ways to make a container's children run horizontally
instead of the default vertical stack:

- **`layoutgrid` + `row` / `column`**, with `DesktopWidth: AutoFill` (or explicit widths) on the
  columns — the classic Atlas responsive-grid approach.
- **A bare `container`** with an explicit
  `DesignProperties: ['Flex container': 'Horizontal (row)', 'Grow / shrink items': '...']` —
  the flex-container mechanism.

Either is fine. **What is not fine** is using one technique on one sibling container and leaving
the adjacent sibling container with no orientation declaration at all, inside the same row/column
of the page. The two containers will visibly disagree — one lays its children out horizontally,
the other silently stacks.

```sql
-- ❌ Filter inputs get flex row; button group gets nothing → buttons stack vertically
container "cFilters" (
  DesignProperties: ['Flex container': 'Horizontal (row)', 'Grow / shrink items': '1 1 auto']
) { textbox "txtSearch" (...) combobox "cboStatus" (...) }

container "cButtons" {
  actionbutton "btnNew"    (Caption: 'New')
  actionbutton "btnExport" (Caption: 'Export')
  actionbutton "btnDelete" (Caption: 'Delete')
}

-- ✅ Both siblings declare an orientation
container "cFilters" (
  DesignProperties: ['Flex container': 'Horizontal (row)', 'Grow / shrink items': '1 1 auto']
) { textbox "txtSearch" (...) combobox "cboStatus" (...) }

container "cButtons" (
  DesignProperties: ['Flex container': 'Horizontal (row)', 'Grow / shrink items': '0 0 auto']
) { actionbutton "btnNew" (...) actionbutton "btnExport" (...) actionbutton "btnDelete" (...) }
```

## 4. The core rule — no container has a safe default orientation

**Every container that holds more than one sibling widget must have an explicit
orientation/layout declaration.** There is no such thing as "leave it unset and it inherits
something sensible." Omitting it does not inherit the parent's flow, does not centre, does not
wrap — it silently falls back to plain block layout, i.e. every child stacks vertically with no
gap, no matter how many siblings it has or what they are.

## 5. Silent-failure table

This is the layout-layer twin of a data-layer silent failure (a JSON structure with a dead root
occurrence): every automated instrument says the page is fine, and it is visibly wrong.

| Container state | What happens | How to check |
|---|---|---|
| Multiple siblings, no `DesignProperties`, not inside a `layoutgrid` row/column | Children stack vertically, no spacing, in source order | Open the page in the running app or SP page preview — **not** `DESCRIBE PAGE`, which reads back present properties correctly but says nothing about ones that are simply absent |
| One sibling container has flex `DesignProperties`, adjacent sibling has none | The two containers visibly disagree in orientation even though they sit in the same row | Same as above — visual only |
| Bare text/heading widgets placed directly as column children, no wrapping container | Elements run together with zero gap regardless of class | Visual only |
| Page built from a different base `Layout:` than its sibling pages | Different available chrome/structure; pages look structurally inconsistent within one module | `DESCRIBE PAGE` on both pages, compare the `Layout:` line — this one **is** visible if you think to check it |
| `mxcli check`, `check --references`, `mxbuild`/exec | All pass | None of these evaluate rendered layout at all |

**Corollary from the instrument-hierarchy rule in `oneshot-mdl-method.md` §7:** layout correctness
is not provable by any static instrument here. The only instrument that can see it is rendering
the page. Do not conclude a page's structure is fine because every mxcli gate was green.

## 6. Distinct content blocks get a card wrapper — when the wireframe shows them as distinct

**Rule:** if the page has more than one logically separate content block (e.g. a header/info
section, a sub-list, a graph/detail panel — anything the wireframe draws as its own visually
bounded region, even just via whitespace or a border), wrap each block's container in Atlas
Core's stock `card` design property (`DesignProperties: ['Card style': true]`, class `card`) —
**not** a project-specific `card`/`kv`/panel class, unless the project's own design system
(`ds.css` / StyleGallery, per `ui-preflight-pages.md` Steps 2-3) already defines a more specific
block component for this case, in which case use that instead (reuse beats a generic card).

**"Roughly aligns with the wireframe" is the trigger, not exact pixel-matching.** Don't invent
block boundaries the wireframe doesn't show (over-carding turns a page into a stack of tiny boxes),
and don't skip a card just because the wireframe's boundary is a thin rule or whitespace gap rather
than an explicit drawn box — a wireframe section head, a `<hr>`, or a named `.wf-note` region
counts as "this is a distinct block" even without a visible border in the mockup.

**Why:** confirmed on `RouteSlice.Route_Detail` (2026-07-31) — four blocks (header, version info,
effectivities, route graph) built with only `spacing-outer-bottom-*` utility classes between them
rendered as one undifferentiated wall of text ("looks horrible," in the words of the person who
had to look at it). Atlas Core's stock `card` class (`themesource/atlas_core/web/core/base/_card.scss`
— ships with Atlas Core itself, portable to any project) fixed it: border, padding, background,
shadow, all via the theme's `--card-*` CSS variables. Keep `spacing-outer-bottom-*` too — Atlas's
built-in `--card-margin-bottom` is tight (`--spacing-smaller`) on its own — but the card is what
does the actual visual separation; spacing alone (§ above) is not sufficient once a page has more
than one block that reads as a distinct "thing" to the person looking at it.

```sql
-- ❌ Four blocks, only bottom margin between them — reads as one continuous block
container "cRouteHeader"     (Class: 'spacing-outer-bottom-medium') { ... }
container "cVersionInfo"     (Class: 'spacing-outer-bottom-medium') { ... }
container "cEffectivities"   (Class: 'spacing-outer-bottom-medium') { ... }
container "cRouteGraph"      (Class: 'spacing-outer-bottom-medium') { ... }

-- ✅ Each block is visibly its own card, still spaced apart
container "cRouteHeader"     (Class: 'card spacing-outer-bottom-medium') { ... }
container "cVersionInfo"     (Class: 'card spacing-outer-bottom-medium') { ... }
container "cEffectivities"   (Class: 'card spacing-outer-bottom-medium') { ... }
container "cRouteGraph"      (Class: 'card spacing-outer-bottom-medium') { ... }
```

## 7. Atlas stock spacing utility classes — safe on any project

These ship with Atlas Core itself. Unlike bespoke branding classes, they require **no theme file
import** to work — they are safe to reach for on a brand-new `mxcli new` project with zero custom
CSS.

| Class | Effect |
|---|---|
| `spacing-outer-top-small` / `-medium` / `-large` | Margin above the widget |
| `spacing-outer-bottom-small` / `-medium` / `-large` | Margin below the widget |
| `spacing-outer-left-*` / `spacing-outer-right-*` | Horizontal margin |
| `spacing-inner-top/bottom/left/right-*` | Equivalent padding variants |
| `card` (`DesignProperties: ['Card style': true]`) | Border, padding, background, shadow around the whole container — the block-separation tool from §6, not just spacing |

Prefer these over inventing a custom spacing class when the gap is simply "some space here" —
save custom classes for things Atlas genuinely doesn't provide (badges, KPI tiles, brand colour).

## 8. Checklist

- [ ] Base `Layout:` chosen deliberately for this page, not copied from whatever reference was
      nearby — checked what chrome/structure it actually provides
- [ ] Every header zone with more than one text/heading sibling has each element (or the group)
      wrapped in its own `container`
- [ ] Every container with 2+ sibling widgets has an explicit orientation: either
      `layoutgrid`/`row`/`column` with widths, or `DesignProperties` flex/grid
- [ ] No sibling container pair where one has an orientation declaration and the other doesn't
- [ ] Spacing done first with Atlas stock `spacing-*` utility classes before reaching for a
      custom class
- [ ] Every content block that the wireframe shows as its own distinct section (or that the
      project's design system defines a block component for) is wrapped in a `card` — either
      Atlas's stock one or the project's reused design-system equivalent, not left as a bare
      spaced container
- [ ] Verified by **rendering the page**, not by `DESCRIBE PAGE` or `mxcli check` — those cannot
      see missing orientation at all

---

**Related:** `oneshot-mdl-method.md` (§7 instrument hierarchy, §8 silent-failure table — this file
adds the layout-layer entries), `datagrid-customcontent-text-binding.md` (same silent-failure
class, one layer down), `tool-output-is-not-ground-truth.md`.
