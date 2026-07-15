# StyleGallery — In-App Design System Module
**Applies to:** any mxcli project.

**Purpose:** How to turn a project's `ds.css` design system into a live Mendix StyleGallery module
that is the in-app twin of `design/design-system.html`. The gallery doubles as both a visual
reference for developers and a reusable component kit (snippets callable from production pages).

**Upstream:** `design-artifacts.md` (produces `ds.css` and `design-system.html` first)
**Downstream:** `ui-preflight-pages.md` (Step 3 reads the gallery MDL as the canonical pattern
to copy from when building real pages), `iterative-build-loop.md`

---

## Why a Live Gallery

`design-system.html` is the source of truth for tokens and components. The StyleGallery module
is its Mendix-rendered twin: it runs inside the real app shell (real Atlas layout, real
compiled SCSS), so it catches rendering issues that a standalone HTML file cannot — component
classes that work in the browser mock but break against Atlas's own CSS cascade, or widgets
that need a real object context to apply styles.

A secondary benefit: gallery snippets are directly callable in production pages. The gallery is
not throwaway scaffolding — it is the component kit.

---

## The ds.css Companion File Pattern

**The key architectural decision:** keep the CSS tokens and component classes in a **separate
`design/ds.css` file** rather than embedded in `design-system.html`.

Both `design-system.html` and every wireframe link to it via:
```html
<link rel="stylesheet" href="../ds.css">
```

This means:
- Change a token in `ds.css` → every wireframe and the showcase reflect it immediately
- Zero token drift between the design system and the wireframes
- The SCSS port (`themesource/<module>/web/main.scss`) has one canonical source to diff against

**Never redeclare tokens inside wireframe HTML files.** If a wireframe needs a color, it uses
the token from `ds.css`. If the token doesn't exist, add it to `ds.css` first.

---

## Token Naming: Three-Tier Architecture

Use three layers — never mix them:

| Tier | Examples | Rule |
|------|----------|------|
| **Raw brand hues** | `--brand-black`, `--brand-red`, `--brand-teal` | Chrome decoration only — buttons, nav, headings. Never used for chart series. |
| **Semantic roles** | `--primary`, `--cta`, `--surface`, `--text-secondary`, `--border` | What everything references. Maps to Atlas variables in the Atlas mapping table. |
| **Chart series** | `--series-1` through `--series-8` | Sourced from the `dataviz` validated palette independently — not derived from brand hues. Run the CVD validator if you change any. |

**The primary / CTA split:** `--primary` is the everyday action color (most buttons). `--cta` is
the *one* prominent call-to-action per page. On a corporate project that uses red as its primary
brand color, these can be deliberately inverted: `--primary = black`, `--cta = red`. Record any
such inversion explicitly in `brand.md` — it is a design decision, not a naming preference, and
it will confuse future maintainers if undocumented.

**Dark mode:** author both themes fully and explicitly. Use a `[data-theme="dark"]` attribute
selector, not `prefers-color-scheme`. In Mendix, Atlas has its own theme-toggle mechanism;
media-query-based dark mode conflicts with it. Dark is not an automatic color-flip of light —
certain surfaces (cards, code blocks, status badges) need individually specified values.

---

## ds.css → SCSS Porting Rules

When porting `ds.css` to `themesource/<module>/web/main.scss`, apply these transforms:

| What to exclude / change | Why |
|--------------------------|-----|
| `* { box-sizing: border-box }` | Global element reset — leaks to entire app, overrides Atlas |
| `html, body { margin: 0 }` | Same — Atlas already sets this |
| `body { font-family: ... }` | Same — controlled by Atlas's `$font-family-base` |
| `h1, h2, h3, h4 { ... }` | Global heading reset — overrides Atlas typography |
| `.row { ... }` → rename to `.ds-row` | Atlas uses `.row` heavily in its flex layout system; collision breaks layouts |

**Keep in SCSS:**
- All `:root` CSS custom property declarations (semantic tokens + chart series)
- All component class blocks (`.kpi`, `.kt-badge`, `.stepper`, `.form-card`, etc.)
- The `[data-theme="dark"]` overrides

**Self-containment rule:** the module's `main.scss` declares its own CSS custom properties in
`:root`. It does NOT import `theme/web/custom-variables.scss`. The two co-exist serving different
consumers: Atlas SCSS variables (in `custom-variables.scss`) feed Studio Pro design properties;
CSS custom properties (in `main.scss`) feed opt-in class-based components. Keeping them separate
prevents a change to one from silently breaking the other.

---

## Mendix Module Setup

**File location:** `themesource/<StyleGalleryModuleName>/web/main.scss`

— not `theme/web/main.scss` (app-level, affects everything)
— not `theme/web/custom-variables.scss` (Atlas brand variables only)

Creating the module via MDL (`create module StyleGallery`) automatically creates the
`themesource/stylegallery/` directory tree. Write the SCSS file there after the module MDL has
been exec'd.

**Layout:** Use `Atlas_Core.Atlas_Default` (or equivalent) as the page layout for the Gallery
home page. This renders the gallery inside the real app shell — components are tested in their
actual rendering context, not an isolated iframe.

---

## MDL File Structure and Exec Order

Number files to express the required exec order:

| File | Contents | Notes |
|------|----------|-------|
| `00-module.mdl` | `create module`, module roles, security stub | First — creates the module namespace |
| `05-demo-data.mdl` | NPE entity for gallery widgets that need a context object | Before any component that needs an object |
| `11-buttons.mdl` | Button snippet | |
| `12-form-controls.mdl` | Form controls snippet | |
| `13-badges-chips.mdl` | Badge / chip snippet | |
| `14-kpi-tiles.mdl` | KPI / stat tile snippet | |
| `15-data-grid.mdl` | Data grid snippet | |
| `16-process-stepper.mdl` | Process stepper snippet | |
| `17-dialog-toast.mdl` | Dialog / toast snippet | |
| `19-ai-copilot.mdl` | AI copilot / chat snippet (if applicable) | |
| `90-gallery-home.mdl` | Home page assembling all snippets via `snippetcall` | **Last** — snippet references must exist |

**Hard constraint:** exec `90-gallery-home.mdl` last. Its `snippetcall` references depend on
every snippet from 11–19 existing in the MPR. Exec out of order → forward reference failure,
script aborts mid-way, MPR left in partial state.

**`mxcli check` anytime; `mxcli exec` only with Studio Pro closed.** The `.mpr` is a single
file; concurrent writers corrupt it silently.

---

## Static vs Real-Widget Components

For each gallery component, choose the rendering strategy based on what you are actually demonstrating:

| Strategy | When to use | Example |
|----------|-------------|---------|
| **Static container** (hardcoded HTML structure) | Purely decorative layout: typography specimens, color chips, spacing rulers, icon sets — anything where no Mendix widget is involved | A row of color swatches using `div` containers |
| **Real widget + NPE entity** | Widget that needs an object context to render but has no meaningful domain data to show (e.g. a button in a DataView to test its enabled/disabled state styling) | A DataView over a non-persistent `GalleryItem` entity with one or two string attributes |
| **Real widget + persistent entity + seeded records** | Any data-rendering widget (DataGrid2, ListView, form fields in a DataView) — these **must** have real rows to show; NPE objects are ephemeral and vanish on page reload, leaving the widget empty at runtime | DataGrid2 displaying a `GalleryProduct` entity with 5 seeded rows via a `seed-data.mdl` |

**⛔ Do not use hardcoded containers as a substitute for real widgets.** A `div` with class `btn-primary` renders the CSS but does not verify that the button widget itself receives and applies that class through Atlas. Use the actual Mendix widget.

**⛔ Do not use NPE entities for data-rendering widgets.** NPE objects are not persisted — a DataGrid2 or ListView backed by an NPE microflow datasource will appear empty on every page load after the initial context object is gone. Use a persistent entity with seeded demo records.

**Seeding rule:** any gallery component that renders rows or a list must have a `seed-data.mdl` (idempotent: retrieve-before-create) that inserts enough demo records to make the component visually meaningful (minimum 3–5 rows). Seed scripts run in Phase 2 after the gallery module MDL is exec'd.

---

## Snippets as Production Components

Gallery snippets are reusable in production pages via `snippetcall`. This means:

- Build the gallery snippet with exact class names and container nesting
- When building a production page that needs the same component, call the snippet rather than
  re-implementing the class structure inline
- Changes to a component (token rename, nesting tweak) propagate everywhere via the snippet

This only applies to **purely visual, data-agnostic** components (process steppers, badge strips,
stat tiles with hardcoded structure). Data-bound widgets must be built inline in the page
because their datasource and binding are context-specific.

---

## Output

```
design/
  ds.css                          ← token + component CSS (linked by showcase + all wireframes)
  design-system.html              ← annotated showcase (links ds.css)

themesource/<module>/web/
  main.scss                       ← ds.css ported to SCSS (resets stripped, .row renamed)
  design-properties.json          ← Mendix design properties stub

mdlsource/gallery/
  00-module.mdl
  05-demo-data.mdl
  11-19-*.mdl                     ← one snippet per component
  90-gallery-home.mdl             ← assembles everything; exec last
```

---

## Anti-Patterns This Skill Prevents

| Anti-pattern | What goes wrong |
|---|---|
| Embedding tokens in `design-system.html` instead of a separate `ds.css` | Wireframes must redeclare tokens → drift, inconsistency |
| Porting global resets (`*`, `body`, `h1–h4`) to SCSS | Leaks to entire app, overrides Atlas |
| Using `.row` as a class name in SCSS | Collides with Atlas's layout utility → broken page layouts |
| Putting SCSS under `theme/web/` instead of `themesource/<module>/web/` | Module not self-contained; breaks if extracted to another project |
| Exec-ing `90-gallery-home.mdl` before its snippets | Forward reference failure, partial MPR state |
| Using brand hue vars directly as chart series colors | Bypasses CVD validator; ships colorblind-unsafe data |
| Skipping the explicit dark mode authoring | `prefers-color-scheme` conflicts with Atlas's theme toggle |
| Using a hardcoded `div` container instead of the real Mendix widget | CSS renders correctly in static HTML but may not apply through Atlas's widget output — widget behavior (enabled/disabled, hover, focus states) is untested |
| Using an NPE entity for a data-rendering widget (DataGrid2, ListView) | NPE objects are ephemeral — grid appears empty on every page load; use a persistent entity with seeded demo records |
| Leaving the StyleGallery home page unwired from navigation | Page is unreachable in a running app; wire under `Config` toolbar item at creation time, not in a later cleanup pass |
