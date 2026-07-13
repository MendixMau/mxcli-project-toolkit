# UI Pre-flight — Design Cross-Reference Before Building Pages

**Purpose:** Before writing any `create page`, `alter page`, or `create snippet` MDL, cross-reference
the wireframe, design-system token file, and in-app StyleGallery examples. This prevents pages that
are structurally correct but visually wrong (bare-Atlas styling, wrong class names, binding
mismatches vs. the wireframe spec).

**Companion skills:** `learned-page-patterns.md` (MDL gotchas), `design-artifacts.md` (how
wireframes and the design system are produced), `iterative-build-loop.md` (Step 3 reads binding
tables; Step 11 verifies against wireframe), `learned-skill-ux-audit.md` (post-build visual audit).

**When to use:** Every time the mdl-agent (or main session) is about to draft a page or snippet.
Not needed for pure microflow/domain/security scripts.

---

## The Four Steps (all mandatory, in order)

### Step 1 — Read the wireframe

Find the HTML wireframe for the page you are building. Project convention is a `design/wireframes/`
folder. Match by page or feature name (e.g. `item-management.html`, `location-detail.html`,
`mobile-scan.html`).

Read the full wireframe file and extract:

| Extract | Where to look in the HTML |
|---------|--------------------------|
| Layout structure | Top-level `<div>` hierarchy — layoutgrid columns, row order, section nesting |
| Widget list | Any element with a `.bind` annotation class or a `data-bind` attribute; also `.wf-note` comment callouts |
| Binding table | Usually a `<table>` or `<dl>` near the bottom of the HTML, or in a companion `.md` annotation file in the same folder |
| Conditional visibility | Callout notes describing "shown only when…" or "edit mode vs. view mode" states |
| Navigation entry point | `.origin` annotation or a nav-link callout stating what opens this page |

**If no wireframe exists:** report this explicitly to the main session and ask whether to proceed
without one or pause and produce a wireframe first (see `design-artifacts.md`).

**If an annotated `.md` companion exists** (e.g. `item-management.md` alongside
`item-management.html`): read it — it often contains the binding table, widget-type decisions, and
filter-field mappings that are harder to parse from the raw HTML.

---

### Step 2 — Read the design-system token file

Find the project's design-system CSS file. Typical paths (project may use one or both):

- `design/ds.css` — raw CSS source of truth (`:root` tokens, component classes)
- `design/design-system.html` — annotated gallery: same tokens plus Atlas mapping table, usage notes
- `themesource/<gallery-module>/web/main.scss` — Mendix-compiled port of `ds.css`

From the relevant component sections, extract the **exact class names** you will need for this page.
Common component classes:

| Component | Class pattern |
|-----------|---------------|
| KPI / stat tile | `.kpi`, `.k-label`, `.k-value`, `.k-delta.k-up/.k-down` |
| Badge / chip | `.kt-badge`, `.kt-badge-cta`, `.kt-badge-success`, `.kt-badge-warning`, `.kt-badge-danger`, `.kt-badge-neutral`, `.kt-badge-info`, `.kt-badge-dark` |
| Form card | `.form-card`, `.form-section` |
| Process stepper | `.stepper`, `.step.done`, `.step.active`, `.step.todo`, `.node`, `.circle`, `.line`, `.s-title`, `.s-meta` |
| Chart container | `.chart-container` |
| Activity feed | `.activity-feed` |
| Scan UI | `.scan-tile`, `.scan-view`, `.reticle`, `.scan-counter`, `.scan-list` |
| Button variants | Check design-system.html — do not invent; use `.btn-primary`, `.btn-default`, or whatever is documented |

**Hard rule (B1):** every `class:` value on a page widget must match a token in the project's
design-system file. Do not invent class names, do not use bare-Atlas class names as the only
class on a design-system-styled widget, do not write inline styles.

---

### Step 3 — Find the closest StyleGallery example

Browse `mdlsource/gallery/` (or wherever the project's in-app design gallery lives). Find the file
whose component matches what you are building:

| Building… | Read this gallery file |
|-----------|----------------------|
| KPI row / stat tiles | `14-kpi-tiles.mdl` |
| Data grid / list overview | `15-data-grid.mdl` |
| Process stepper | `16-process-stepper.mdl` |
| Dialog / toast | `17-dialog-toast.mdl` |
| Buttons | `11-buttons.mdl` |
| Form controls | `12-form-controls.mdl` |
| Badges / chips | `13-badges-chips.mdl` |
| AI copilot / sidebar | `19-ai-copilot.mdl` |

Read the **full file** and use it as the canonical MDL pattern to copy container nesting, widget
naming conventions, and `class:` values from. If no gallery file matches, note this and fall back to
the design-system HTML directly.

---

### Step 4 — Cross-check before writing a single widget

For each widget group in your planned MDL, verify all four:

| Check | Verify |
|-------|--------|
| **Binding** | Attribute/datasource in your script matches the wireframe binding table |
| **Class names** | Every `class:` value is present in `ds.css` / `main.scss` |
| **Widget nesting** | Container depth mirrors the StyleGallery example |
| **Conditional visibility** | Any `visible:` expression on the widget is legal under the STOP table (safe on regular widgets; MCP-only inside `datagrid customContent` columns — BUG-18) |

If a wireframe element cannot be expressed in MDL at all (e.g. association-mode COMBOBOX, cross-module
widget datasource, `DatagridDropdownFilter` in ref mode), flag it before drafting — note which STOP
rule applies and that MCP will handle it as a follow-up.

---

## Report-back format

When you report the completed script back to the main session, include a **UI cross-reference block**:

```
UI cross-reference:
  Wireframe:      design/wireframes/<filename>.html [read — binding table extracted]
  Design system:  design/ds.css — classes used: <list the class names>
  Gallery example: mdlsource/gallery/<filename>.mdl
  Gaps / MCP fallbacks: <any element flagged as STOP, or "none">
```

If no wireframe existed, say so explicitly here. Never silently skip this block.

---

## Common failure modes this pre-flight prevents

| What goes wrong without this step | How this pre-flight catches it |
|-----------------------------------|-------------------------------|
| Page looks bare-Atlas (no KT styling) | Step 2 forces you to pick class names from `ds.css` before writing |
| Widget binds to wrong attribute | Step 1 binding table vs. your planned `contentparams` |
| Class name invented or misspelled | Step 4 cross-check against token file |
| Conditional visibility in a datagrid custom-content column (BUG-18) | Step 4 STOP check |
| Association-mode COMBOBOX drafted in MDL (fails mxcli check) | Step 4 flags it before you write it |
| Page has no navigation entry point | Step 1 `.origin` annotation surfaced in extract |
| Widget nesting doesn't match design system | Step 3 StyleGallery example as canonical structure |
