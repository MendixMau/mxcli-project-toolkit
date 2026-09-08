# UI Pre-flight — Design Cross-Reference Before Building Pages
**Applies to:** any mxcli project.

**Purpose:** Before writing any `create page`, `alter page`, or `create snippet` MDL, cross-reference
the wireframe, design-system token file, and in-app StyleGallery examples. This prevents pages that
are structurally correct but visually wrong (bare-Atlas styling, wrong class names, binding
mismatches vs. the wireframe spec).

**Companion skills:** `learned-page-patterns.md` (MDL gotchas), `design-artifacts.md` (how
wireframes and the design system are produced), `iterative-build-loop.md` (Step 3 reads binding
tables; Step 11 verifies against wireframe), `learned-skill-ux-audit.md` (post-build visual audit),
`design-spacing.md` (**mandatory, not situational** — the spacing scale, rhythm hierarchy, and
the page-header scaffold every page starts with), `oneshot-page-structure-patterns.md`
(container/spacing/card repair mechanics once you've decided what the wireframe wants).

**When to use:** Every time the mdl-agent (or main session) is about to draft a page or snippet.
Not needed for pure microflow/domain/security scripts.

**This file works only when its full text is in the drafting context.** Measured (A/B, 5 reps
per arm on the same page, 2026-08-31, `process/preflight-skill-baseline-2026-08-31.md`): with
this file inlined in the drafting agent's context, 5/5 reps chose the correct layout shell,
5/5 opened with an H1, 0/5 wrote an inline style or invented a class; without it, 0/5, 2/5 and
3/5+1/5 respectively — the exact ToeicBuddy field defects. The failed field run *cited this
file by name* while producing the without-arm's numbers: a citation is not a read. So when
page-drafting is dispatched to a subagent, the dispatch prompt must include this file's text
(or the subagent must read it as its first action) — a one-line "follow ui-preflight-pages.md"
reproduces the baseline.

---

## The Five Steps (all mandatory, in order)

Steps 1–4 are judgement; Step 5 is the mechanical check that judgement alone was measured to miss.

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

**If no wireframe exists:** ⛔ STOP. Report to the main session that the wireframe is missing and that the page script cannot be drafted until one exists. Do not proceed, do not guess layout or bindings, do not ask whether to proceed without one — the wireframe is not optional. See `design-artifacts.md` to produce one first.

**If an annotated `.md` companion exists** (e.g. `item-management.md` alongside
`item-management.html`): read it — it often contains the binding table, widget-type decisions, and
filter-field mappings that are harder to parse from the raw HTML.

---

### Step 2 — Read the design-system token file

Find the project's design-system CSS file. Typical paths (project may use one or both):

- `design/ds.css` — raw CSS source of truth (`:root` tokens, component classes)
- `design/design-system.html` — annotated gallery: same tokens plus Atlas mapping table, usage notes
- `themesource/<gallery-module>/web/main.scss` — Mendix-compiled port of `ds.css`. **This is the only stylesheet that ships**; a CSS change landed only in `ds.css` is a no-op in-app (`learned-stylegallery.md`, the ⛔ rule)

From the relevant component sections, extract the **exact class names** you will need for this
page — read them out of the project's own `ds.css` / `design-system.html` / `main.scss`, never
from memory or from another project's palette. Every design system names its components
differently (one project's KPI tile is `.kpi` + `.kpi-value`, another's is `.k-value`); the
authoritative list is the stylesheet in front of you, and a class table cached in a skill goes
stale the day the next project is scaffolded. `grep -o '^\.[a-z-]*' design/ds.css | sort -u`
is a fine first pass; then read the rules you plan to lean on, because a selector's shape
matters (`.kpi b` styles a `<b>` inside the tile — it is not a class you can put on a widget).

**Hard rule (B1):** every `class:` value on a page widget must match a token in the project's
design-system file. Do not invent class names, do not use bare-Atlas class names as the only
class on a design-system-styled widget, do not write inline styles.

**Page column (the 0/10 defect):** if the wireframe caps its `main` (e.g. `main{max-width:900px}`)
and the design system has **no reusable page-column class** — only an element-level `main` rule,
which Mendix page markup never matches — the cap is unbuildable from the page author's seat and
silence ships every page full-bleed. Promote a page-column class into `main.scss` (e.g.
`.page-column { max-width: <wireframe px>; margin-inline: auto; }`), carry it on the page's
body container, and record the promotion in the report block. If you cannot touch `main.scss`
in this session, flag the gap in the report block instead — measured 2026-08-31: 10/10 drafts
shipped full-bleed against a 900px wireframe and only 1 rep even noticed the class was missing.

---

### Step 3 — Find the closest StyleGallery example

List `mdlsource/gallery/` (or wherever the project's in-app design gallery lives) — actually
list it; do not trust a remembered file inventory, because each project's gallery holds the
components *its* design system has, under its own numbering. From the real listing, pick the
file(s) whose component matches what you are building (a KPI-tile file for stat tiles, a grid
file for list overviews, the home/scaffold page for page structure) and note in your report
which files you read and which you rejected. (If the gallery has an AI copilot / chat frame
snippet, it is the *frame* only; for the working chat surface read `skills/mendix-agent-ui.md`.)

Read the **full file** and use it as the canonical MDL pattern to copy container nesting, widget
naming conventions, and `class:` values from. If no gallery file matches, note this and fall back to
the design-system HTML directly.

**⛔ Reuse is mandatory, not optional.** If a gallery component exists for a pattern your page needs
— a status badge/pill, a stepper, an empty-state, a KPI tile, a card — the page **must use it**, not
reimplement it as plain text or a bare container. A plain-text status column next to a built badge
component is a defect (`module-review.md` §4e flags exactly this). If you deliberately do *not*
reuse an existing component, state why in the UI cross-reference block — silence reads as "forgot to
reuse", which is the failure this rule prevents. Concretely: enum/state/priority values → the badge
component; a multi-state progression header → the stepper; an empty grid/gallery → the empty-state
component; a single aggregate metric → the KPI tile (not a record list).

---

### Step 4 — Cross-check before writing a single widget

For each widget group in your planned MDL, verify every row:

| Check | Verify |
|-------|--------|
| **Binding** | Attribute/datasource in your script matches the wireframe binding table |
| **Class names** | Every `class:` value is present in `ds.css` / `main.scss` |
| **Widget nesting** | Container depth mirrors the StyleGallery example |
| **Component reuse** | Every pattern with an existing gallery component (badge, stepper, empty-state, KPI, card) uses that component — not plain text or a bare container |
| **Block separation** | Every distinct content block the wireframe draws as its own section gets a `card` wrapper (project's design-system card component if one exists, else Atlas stock `card` design property) — not just a spaced, borderless container (`oneshot-page-structure-patterns.md` §6) |
| **Page column** | If the wireframe caps its `main` width, the page body carries the project's page-column class (promoted per Step 2 if it didn't exist) — an uncapped page renders full-bleed at 1360px against a 900px design |
| **Page scaffold** | The page starts with the header block — crumb + one `RenderMode: H1` title (+ subtitle/actions where the wireframe has them) — per `design-spacing.md` §3. A full page with no H1 is a defect, not a layout choice |
| **Spacing rhythm** | Every top-level section container carries `spacing-outer-bottom-large`; sibling groups use `-medium`; no gap between sections is 0; no spacing via inline pixel styles (`design-spacing.md` §2 — all gaps on the 8/16/24/32/48 scale) |
| **Empty state** | Every grid/gallery has an empty-state message for the zero-result case — never renders nothing |
| **Equal card height** | Every card/tile repeated in a grid or gallery renders at the SAME height as its row siblings, regardless of how much content each one holds — a card with a description and one without must look the same size. The grid container needs `align-items: stretch` (CSS Grid's default, but verify nothing overrides it) AND the card itself needs `height: 100%` — stretch alone sizes the grid CELL, not the card inside it, which is the gap that lets this pass a casual look. (Real incident, 2026-09-01: measured on the running app — a card with a one-line description rendered at 151.6px, a card with none at 127.6px, same grid row, same class. The grid's own row had stretched to 188.6px; the cards inside it hadn't, because `.dashboard-card` had no `height: 100%` to consume that stretch.) |
| **Validation feedback** | Every form with a required/unique field surfaces a visible validation message on failed save (validation-message widget, or the form's own error display) — a save that fails silently (server rejects, UI shows nothing) is a P1, not a pass |
| **Response after a write** | Every button whose action commits, deletes, or otherwise mutates data resolves, on success, to at least one of: a navigation (`show page`/`close page`), a validation/confirmation message on the object, or a data source provably re-scanned after the commit (the mutated object is the target widget's own selection, or the same microflow refreshes the list). A commit that returns to the same screen with no navigation, no message and no refreshing data source is a P1, not a pass — the object was saved and the screen looks untouched, which reads to a user as the button doing nothing. Symmetric to the row above: that one is "does failure say so," this one is "does success say so" — an unchanged screen is silent regardless of which one happened. (Real incident, 2026-09-01: a create-dashboard button committed and returned `true` with no navigation; the create form kept the same object's data, and the gallery below it was a separate microflow data source that does not re-run because a sibling committed. The user's own words: "after clicking new dashboard I don't see anything happening.") |
| **Conditional visibility** | Any `visible:` expression on the widget is legal under the STOP table (safe on regular widgets; MCP-only inside `datagrid customContent` columns — BUG-18) |
| **Class carrier** | Every `class:` value is on the widget its design-system entry names as the carrier. A class alone does not win the cascade: CONTAINER → a bare `<div>` with no competing rule, but ACTIONBUTTON carries Atlas's compound `.mx-button.btn` (0-2-0) which **beats a single class (0-1-0) and overrides it only partially** — background applies, `display`/`padding`/`font-size` do not. See `learned-stylegallery.md` → "The Mendix DOM contract" |
| **Computed class names** | Every `DynamicClasses` expression's **complete output set** exists in the stylesheet. Work out every string the expression can emit and confirm each has a rule — one that does not fails silently, as an empty or unstyled element beside a caption asserting otherwise. Note: **Mendix `div` is float division** (`63 div 10 = 6.3`), so `(x div 10) * 10` does not bucket |

If a wireframe element cannot be expressed in MDL at all (e.g. association-mode COMBOBOX, cross-module
widget datasource, `DatagridDropdownFilter` in ref mode), flag it before drafting — note which STOP
rule applies and that MCP will handle it as a follow-up.

---

### Step 5 — Run the shell check before you exec (mechanical, seconds)

Steps 1–4 are judgement and they are the substance. This step is the part a script can
settle, and it exists because **judgement performed correctly still shipped the wrong
shell on ten pages out of ten**:

```
bin/check-page-shell.sh mdlsource/<your-page-script>.mdl
```

It compares the drafted MDL against the wireframe on the three things the wireframe
states unambiguously — the page column, the layout/nav shell, one `RenderMode: H1` —
and exits non-zero on a mismatch. Run it **before** `bin/exec.sh`, alongside
`mxcli check`; it reads files only, so it needs no app, no Studio Pro, and no
screenshot, and it runs in a cloud/mobile session where the rest of Gate: UI cannot.

A **shell mismatch is scriptable to fix on mxcli ≥ v0.20.0** — layouts are authorable
(`CREATE [OR REPLACE] LAYOUT`, `ALTER LAYOUT` with the full ALTER PAGE vocabulary), and
`ALTER PAGES [IN <mod>] SET LAYOUT = X [WHERE LAYOUT = Y] [MAP (Old AS New)]` migrates
every page in one statement, refusing a repoint that would strand a placeholder binding
(the CE1613 the build would otherwise report page-by-page). `mxcli new` (≥ v0.20) also
scaffolds a **project-owned** `<Module>.App_Default` layout rather than binding pages to
Atlas's — so "the wireframe draws a top bar but the app renders a sidebar" is a one-script
repair now, not the 20-script incident this file records. Editing `Atlas_Core` layouts is
refused by mxcli (marketplace-owned); copy via `describe layout` → rename → exec instead,
knowing the copy loses widgets MDL cannot spell (`Forms$SidebarToggleButton`, images).

Then run the scored companion on the same draft:

```
node <toolkit>/project-bin/page-fidelity.js design/wireframes/<Page>.html <Page> mdlsource/<script>.mdl
```

**Every run is stored.** The scorer appends its result to the project's
`docs/PAGE-FIDELITY.tsv` — the first row for a page is that page's **first-build score
of record**, the number the ≥80% target judges; later rows for the same page show the
rework curve. This is not optional bookkeeping the session may skip: the log is written
by the instrument itself, so a page with no row in the TSV is a page that was never
scored — visible at gate time, not reconstructed afterwards (the MarkUseCase field run,
2026-08-27, built its first pages with no fidelity trace at all, and "what went wrong"
had to be reconstructed from a session status line). Run it again after `exec` against
`DESCRIBE` output (`-` for stdin) to record what actually landed in the model.

**Stub pages are exempt — by flag, never by inference.** A forward-reference stub
(`iterative-build-loop.md` § "Forward references": a page created only so a later
script's references resolve, replaced by its real script) is deliberately not the
build, so it must not become the first-build score of record. Score it with
`--stub`: the row lands marked `stub` and the target skips it — the **first
non-stub row** is the score of record. The flag is a declaration, exactly like a
gate waiver: if you didn't declare it a stub at scoring time, it scores as what
it is. "It was meant as a stub" after a bad score is not a category — it is the
bad score.

**Measured, ToeicBuddy field run 2026-08-25/26** (`process/first-build-page-fidelity-2026-08-27.md`):
first-build fidelity across 10 pages was **32% median** against a target of 80%. All 14
wireframes declared a 900px page column and **0 of 10** pages capped their width — repaired
wholesale at script 67, fifty-five scripts later, after rendering at 1360px. All 10 were
built on a sidebar layout against wireframes drawing a top bar — repaired at script 20.
The script's header carries the full evidence for each check.

**Measured again, controlled A/B, 2026-08-31** (`process/preflight-skill-baseline-2026-08-31.md`):
5 fresh drafting agents with this file inlined produced **zero** judgement-step violations
(layout, H1, inline styles, invented classes) across all 5 reps; 5 without it reproduced every
field defect. The content works when read — the failure mode is dispatching a page build with
a *reference* to this file instead of its text (see the delivery rule at the top).

The build script that produced those pages **cited this file's Step 3 by name**. That is
the point: the pre-flight was run, and its output was a paragraph nobody could fail. A
shell defect is uniform across every page built the same way, so no page stands out as a
diff and per-page review does not surface it — which is exactly what a mechanical check
is for, and exactly what human judgement is worst at.

---

## Report-back format

When you report the completed script back to the main session, include a **UI cross-reference block**:

```
UI cross-reference:
  Wireframe:       design/wireframes/<filename>.html [read — binding table extracted]
  Design system:   design/ds.css — classes used: <list the class names>
  Gallery example:  mdlsource/gallery/<filename>.mdl
  Components reused: <badge / stepper / empty-state / KPI used — or "none needed">
  Reuse skipped:    <any existing gallery component deliberately NOT used, with reason — or "none">
  Empty states:     <every grid/gallery on the page has a zero-result message: yes/no>
  Gaps / MCP fallbacks: <any element flagged as STOP, or "none">
  Shell check:      bin/check-page-shell.sh — <N page(s), N violation(s)> [or: NOT RUN, and why]
  Fidelity score:   page-fidelity.js — <NN% (headings a/b, actions c/d, …)>, logged to docs/PAGE-FIDELITY.tsv [or: NOT RUN, and why]
  Class promotion:  self-audit diff (learned-stylegallery.md § "Keep the two files self-auditing") — <N never-promoted class(es), expect 0> [or: NOT RUN, and why]
```

The class-promotion row exists because a page can be perfect and still render unstyled: every
class it uses lives in `ds.css`, and `ds.css` never ships — only the `main.scss` port does.
`mxcli theme apply` does **not** do that port (it moves palette tokens only — the trap that
cost the MarkUseCase build every styled element on every page, 2026-08-28). One `diff`
command answers it.

**The shell-check, fidelity-score and class-promotion lines are the rows in this block with a denominator, and they are not optional.** Every other line is a claim the author grades themselves; that is what made this block unfalsifiable, and a block nobody can fail is not a check. `NOT RUN` is a legal value — silence is not. A fidelity score below 80% on a first build is not a failure to hide — it is the number that tells the next step (fix before the next page, per `ui-loop.md`), and the TSV row is already written either way.

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
| Built gallery component not reused (plain text instead of the badge/stepper) | Step 3 reuse rule + Step 4 component-reuse cross-check |
| Grid/gallery renders nothing on zero results | Step 4 empty-state cross-check |
| Required/unique field save fails with no visible message (silent 4xx/5xx) | Step 4 validation-feedback cross-check |
| Page's distinct blocks read as one undifferentiated wall of text | Step 4 block-separation cross-check |
| Page built full-bleed against a wireframe that draws a fixed page column; a sidebar layout against a wireframe drawing a top bar — uniform across every page, so no page reads as the odd one out | Step 5 shell check (`0/10` on the run that produced this row) |
| Page built with no title/header block; sections starting flush at 0px; per-page inline pixel spacing | Step 4 page-scaffold + spacing-rhythm cross-checks (`design-spacing.md`) |
| Design-system class on an ACTIONBUTTON, half-overridden by Atlas — reads on screen as a layout bug in the component, not as a CSS problem | Step 4 class-carrier cross-check |
| `DynamicClasses` names a class that does not exist; the element falls back to nothing and the page shows an empty bar/badge next to a caption claiming a value | Step 4 computed-class-name cross-check |
