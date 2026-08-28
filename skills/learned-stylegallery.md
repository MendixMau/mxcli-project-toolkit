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

**⛔ `design/ds.css` is never compiled into the app.** It is the design reference that the
wireframes and `design-system.html` link to. The only stylesheet the Mendix build ships is
`themesource/<module>/web/main.scss`. **Any CSS fix that must be visible in the running app lands
in `main.scss`; any fix that changes the design contract lands in both files in the same
commit** — and the finding closes only after the changed value is observed rendered live,
post-rebuild (`module-review.md`, pixel rule). Measured consequence (2026-08-23, sibling
project): a styling fix "landed" in `ds.css`, silently did nothing, and survived a full review
pass; a second pass was needed to move it to `main.scss`. `design-audit.js`'s never-promoted
check will not save you here — it diffs class *names*, so a property edit to an
already-promoted class is invisible to it.

**⛔ `mxcli theme create/apply` does NOT perform the port.** It writes the *palette tokens*
(`--mxt-*` custom properties) into the theme — nothing else. No component class rule
(`.tab`, `.status`, `.metric`, `.kpi`, …) ever travels with it. The trap is that its result
is *visibly convincing*: the brand colors land, the app stops looking like bare Atlas, and
the session concludes the design system is installed. Measured (MarkUseCase field run,
2026-08-28): every page across four screens referenced `ds.css` component classes, `theme
apply` had run, and **zero** of those classes existed in `main.scss` — the whole app rendered
unstyled for the entire build, confirmed as 5 pages FAIL on `design-audit.js`'s
never-promoted check. A visible palette change is evidence of exactly one thing: the palette.
The port is a separate, manual pass (§ "ds.css → SCSS Porting Rules" below), and it is done
only when the self-audit diff below prints nothing undocumented.

**Keep the two files self-auditing.** `main.scss` opens with a comment block naming every
deliberate exclusion vs `ds.css` (global resets, wireframe-only annotation chrome, the
`.row` rename). Then drift is one command, and every line of output is either in that
documented list or a bug:

```bash
diff <(grep -oE '^\.[a-zA-Z0-9_-]+' design/ds.css | sort -u) \
     <(grep -oE '^\.[a-zA-Z0-9_-]+' themesource/*/web/main.scss | sort -u) | grep '^<'
```

Run it at three moments: right after `mxcli theme apply` (expect it to list every component
class — that is the port's to-do list, not a pass), at the end of the porting pass (expect
zero undocumented lines), and in every page script's report-back (`ui-preflight-pages.md`,
the class-promotion row) — because a page script may add classes to `ds.css` after the port
was "done".

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

## Don't Stop at ds.css — a Wireframe Can Own Real Layout CSS Too

This porting pass, and the self-audit diff command above it, both compare `ds.css` against
`main.scss` — deliberately, since `ds.css` is the shared token/component contract. But a wireframe
file (`design/wireframes/<Page>.html`) is also free to declare its own **page-specific** inline
`<style>` rules that are never meant to go in `ds.css` at all, because they only apply to one
screen's layout — e.g. a two-column detail-view grid. If the built page's own MDL then reuses that
same class name (correctly, matching the wireframe's intended structure), but nobody ported the
*rule* anywhere real, the page ships wired to a class that resolves to nothing. It builds clean,
`mxcli check` and `mxbuild` pass, every journey and wiring-sweep passes (the widget tree is
correct) — and the page silently renders as an unstyled fallback (stacked full-width instead of a
grid, in the case that surfaced this).

**Found on a real project** (2026-08-24, `mxcli-project-toolkit` field validation run):
`TransportOrder_Detail`'s wireframe declared `.detail-grid { display:grid; grid-template-
columns:1fr 1fr }` in its own `<style>` block. The built page correctly used `Class: 'kt-page-body
detail-grid'`. The rule was never added to `ds.css` *or* `main.scss`. Nothing caught it before
`module-review.md`'s Stage 4 (LOOK) — a human actually looking at the rendered page.

**When porting a wireframe's design into a real page, also scan that wireframe's own `<style>`
block** for classes that are not `ds.css` tokens/components and not throwaway annotation chrome
(`ann-*`, `wf-note-*`, `wireframe-*`, the wireframe's own layout/meta scaffolding) — anything else
is a candidate for real, page-specific layout CSS that belongs in `main.scss` alongside the ds.css
port, scoped to that page/module rather than promoted into the shared design system.

**Caveat about `design-audit.js`'s rung 6 "wireframe-chrome" check:** as of this writing, its
classifier buckets *any* class that's in a wireframe but not in `ds.css`/the theme as "wireframe-
only chrome that must never reach a real page" (`project-tests/e2e/design-audit.js` — see the
`classifyClasses` function, `CHROME_NAME` regex and its `wfAll` fallback branch). That's the right
call for genuine annotation markup, but it does not distinguish that from a real, page-specific
layout class like `.detail-grid` — a finding there can read as "strip this class from the page"
when the actual fix is "add this class's rule to the theme." Don't blindly delete a flagged class
without checking which case it is; a code fix to that classifier (splitting the two cases) is
flagged inline in the source but not yet made — see the `// TODO` comment at `classifyClasses`.

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

## The Mendix DOM contract — what your CSS is actually selecting

Every fact here was measured with `getComputedStyle` in a running Mendix 11.13.0 app with Atlas
Core, not inferred from reading source. They are the reason a design system's **tokens** port
perfectly while its **rules** silently do not: the tokens are values, the rules are bets on HTML
that Mendix may not emit.

| Fact | Consequence for your stylesheet |
|---|---|
| `html { font-size: 10px }`, body 14px | Every `rem` renders at **62.5%** of a 16px-root design. Author component sizes in `px`. |
| CONTAINER → a plain `<div>` | The only carrier with no competing Atlas rule. **Default choice for a design-system class.** |
| DYNAMICTEXT → an inline `<span>` | A `.foo span` rule matches it *by accident* at 0-1-1 and beats the class-only `.foo-value` (0-1-0) it was meant to support. |
| ACTIONBUTTON → `<button class="btn mx-button … btn-default">`, inline-block | Atlas's **compound** `.mx-button.btn` (0-2-0) beats any single class (0-1-0). Buttons and adjacent text share a line box — no margin fixes it; needs `display: block`. |
| Listview row → wrapped in its own `div.mx-dataview > div.mx-dataview-content` | **Every row is `:nth-of-type(1)` in its own parent.** Row alternation must be driven from data via `DynamicClasses`. |
| DataGrid2 → `role="grid"` `<div>`s | `table` / `th` / `td` / `tr` selectors match **nothing**. A whole responsive-table component can be unreachable. `Size` on a column is a flex weight, not pixels. |
| `theme/web/main.scss` compiles **last** — after Atlas Core and every module theme source | Correct home for app-level styling; overrides Atlas with no `!important`. |
| `theme/web/custom-variables.scss` is imported **once per module** | Declarations only. A CSS *rule* placed there is emitted once per module. |
| Mendix `div` is **float** division: `63 div 10 = 6.3` | Bucketing with `(x div 10) * 10` does not bucket. Bites `DynamicClasses` expressions. |
| Absent CSS and overridden CSS look **identical** in the browser | Never diagnose by squinting. `grep -c '<probe selector>' deployment/web/theme.compiled.css` tells you which one you have. |
| **`DROP MODULE` is a model operation and removes no CSS at all** | `theme/web/*.scss` is app-level and survives every drop, wholesale. So a project that "reset to a clean slate" still has its old styling on the page, and the rebuild either ports the same component twice under two class names or writes a class that *appears* to work because the old rule is still painting it. After any reset, decide per file — keep as the baseline, or archive and re-port — and say which. `themesource/<Module>/web/main.scss` survives too; it is usually a two-line `@import` stub, but a StyleGallery module's real SCSS lives at exactly that path, so read it before deleting. |

### Every class states its carrier

**A class name does not say which widget carries it, and the wrong carrier fails *partially*, which
is worse than failing completely.** Measured: the same `.opt` class on a CONTAINER rendered exactly
as designed; on an ACTIONBUTTON, background, border and the `::before` chip still applied while
`display`, `padding` and `font-size` did not — so the chip lost its flex context and stretched the
full row width with the text pushed underneath. On screen that reads as a **layout bug in the
component**, not as a stylesheet that lost the cascade, and it sends the reader to fix the wrong
thing.

So the component table gets one more column, and it is nearly free:

> `.opt` — **carrier: CONTAINER** (a `<div>`). Not an ACTIONBUTTON: Atlas's `.mx-button.btn`
> compound (0-2-0) outranks `.opt` (0-1-0) and overrides it partially.

Three rules follow:

- **Default to CONTAINER.** Reach for another carrier only when the widget's behaviour is needed.
- **Any rule that sets `background` must also set `color`.** Inheriting text colour from an unknown
  carrier is how a `.opt` with a pale-green background rendered white-on-pale-green — invisible —
  the moment it landed on a `<button>` carrying Atlas's white button text.
- **Add a degradation guard** so the wrong carrier fails visibly rather than half-applying:
  `.mx-button.opt, button.opt { … }`.

### The gallery must be a twin, not a lookalike

**Instantiate each gallery component with the same widget the real pages use.** Look up each class
in the real page sources first. A gallery that renders `.opt` on a CONTAINER while the pages render
it on an ACTIONBUTTON does not just fail to catch the defect — it actively *hides* it, and reports a
clean visual pass over a component that is broken everywhere it actually ships.

### Enumerate every `DynamicClasses` output

A computed class name is outside every contract the toolkit has: the expression is valid MDL, the
class it names may not exist, and the element silently falls back — a `width: 0` bar sitting beside
a caption reading "63% of answers correct". `mxcli check`, `mxcli lint` and `mx check` are all green.

**A `DynamicClasses` expression whose output set is not enumerated in the stylesheet is an
unreviewed contract.** Generate the full range:

```scss
// bar-w-0 … bar-w-100 — the complete set the DynamicClasses expression can emit
@for $w from 0 through 100 { .bar-w-#{$w} { width: #{$w}#{'%'}; } }
```

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
| `19-ai-copilot.mdl` | AI copilot / chat snippet (if applicable) | Frame only — `skills/mendix-agent-ui.md` for the live surface |
| `90-gallery-home.mdl` | Home page assembling all snippets via `snippetcall` | **Last** — snippet references must exist |

**Hard constraint:** exec `90-gallery-home.mdl` last. Its `snippetcall` references depend on
every snippet from 11–19 existing in the MPR. Exec out of order → forward reference failure,
script aborts mid-way, MPR left in partial state.

**The gallery home page owes the same shell every page owes (`design-spacing.md` §2–3) — this
is mandatory, not styling taste.** Measured consequence (2026-08-23, sibling project): a gallery
home scaffolded as bare sibling `snippetcall`s at page root shipped with no side gutters and no
gap between its five sections — and because this page is generated fresh into every project by
this skill, the bug reproduces identically everywhere until the scaffold below is used.
`90-gallery-home.mdl` follows this shape:

```
create page StyleGallery.Gallery_Home (Title: 'Style Gallery', Layout: Atlas_Core.Atlas_Default) {
  container "galleryShell" (Class: 'spacing-inner-horizontal-large spacing-inner-vertical-large') {
    container "pageHead" (Class: 'page-head spacing-outer-bottom-large') {
      dynamictext "heading" (Content: 'Style Gallery', RenderMode: H1)
      dynamictext "sub" (Content: 'Every sanctioned component, live')
    }
    container "secButtons" (Class: 'card card-pad spacing-outer-bottom-large') {
      dynamictext "titleButtons" (Content: 'Buttons', RenderMode: H2)
      snippetcall "scButtons" (Snippet: StyleGallery.SNIPPET_Buttons)
    }
    /* ...one card container per section, each carrying spacing-outer-bottom-large... */
  }
}
```

Three rules the scaffold encodes: (1) one top-level wrapper container with horizontal + vertical
inner padding (Atlas `spacing-inner-*-large`, or the project design system's shell class if
`ds.css` defines one) — sections never sit flush at page root; (2) every section is a
`card`/`card-pad` container carrying `spacing-outer-bottom-large` — never an inline
`Style: 'margin-top: NNpx'`, which is off-scale and forbidden by `design-spacing.md`;
(3) exactly one `RenderMode: H1`, on the page head.

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

## Gallery Widget Layout — the wrapper-CSS trap

**Never put grid/flex layout CSS on a Mendix gallery's outer wrapper.** Mendix's native gallery
widget always wraps its output in three fixed structural children:
`.widget-gallery-top-bar`, `.widget-gallery-content`, `.widget-gallery-footer`. If you set a class
like `display:grid; grid-template-columns:repeat(3,1fr)` on the gallery's **outer element**, those
three scaffolding elements become the grid columns — so the empty top-bar takes column 1, the
actual cards get stranded in column 2, and the empty footer takes column 3. The single card floats
off-center with large empty gutters, and it gets *worse* with more data, not better (all cards
squeeze into the one middle track). This passed mxbuild and shipped — a real P1 from the WMS audit.

**Two correct options:**
1. Target the grid at the content child: `.my-gallery .widget-gallery-content { display:grid; ... }`.
2. Drop the custom class entirely and use the widget's own native `DesktopColumns` / `TabletColumns`
   / `PhoneColumns` properties (set in the MDL) — Mendix lays the cards out correctly by itself.

The same "custom layout class on the wrong DOM level" trap applies to datagrid and any native
widget with its own structural wrapper — inspect the live computed layout (`getBoundingClientRect`
on the container and its children) before assuming your class landed where you think it did.

## Visual Verification — the gallery is only worth it if someone looks

The gallery's entire justification is being the **in-app twin that catches render bugs a static
HTML mock can't** (see "Why a Live Gallery"). That only pays off if the gallery is actually looked
at after it's built. **Before the StyleGallery phase is marked done, run a visual pass over the
rendered gallery home page** (via `module-review.md`'s LOOK stage) and confirm:

- **Every demo value renders** — dates, enums, calculated fields show real values, not blank. A
  blank date in the gallery's own demo cards means the date renders blank *everywhere* downstream
  (a real WMS P1 — the bug was visible in the gallery for the whole build and nobody looked).
- **Labels are correct** — no `ONFAILURE` where `On Failure` was intended (enum-to-caption mapping).
- **KPI tiles show one aggregate value**, not a stacked list of every record (a gallery/list widget
  used where a single-value binding was intended).
- **Each component matches its `design-system.html` spec** — the gallery is the diff target.

**Wire it into navigation as part of building it — the scaffold is not done without this.** Every
gallery build ends with (a) a navigation entry in a profile, (b) a role grant, and (c) the skill
stating **which demo user can see it**. A gallery with no menu entry and no URL is unreachable in
the running app, and unreachable is indistinguishable from absent to everyone downstream. Check the
grant landed on a real role, not the auto-created `.User`:

```
SHOW MODULE ROLES IN <GalleryModule>
```

Measured failure, 2026-08-26: the module was granted to an admin role, there *was* a demo user in
that role, nobody knew, and the first attempt to screenshot the gallery silently measured the
Dashboard instead — and reported on it.

A gallery that was built but never visually verified is not a reference — it's an untested surface
that silently propagates its own bugs into every page that copies from it. A gallery that was built
and left unreachable is worse: every checklist ticks, and the one instrument that would have caught
the defects is the thing nobody opened.

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
| Gallery home assembling snippets flush at page root — no wrapper, no gutters, no section gaps | Reproduces into every project this skill scaffolds; the shell scaffold above is mandatory (2026-08-23, sibling project) |
| Landing a CSS fix only in `design/ds.css` | ds.css is never compiled — the fix is a no-op in-app; theme source first, mirror to ds.css in the same commit |
| Using brand hue vars directly as chart series colors | Bypasses CVD validator; ships colorblind-unsafe data |
| Skipping the explicit dark mode authoring | `prefers-color-scheme` conflicts with Atlas's theme toggle |
| Using a hardcoded `div` container instead of the real Mendix widget | CSS renders correctly in static HTML but may not apply through Atlas's widget output — widget behavior (enabled/disabled, hover, focus states) is untested |
| Using an NPE entity for a data-rendering widget (DataGrid2, ListView) | NPE objects are ephemeral — grid appears empty on every page load; use a persistent entity with seeded demo records |
| Leaving the StyleGallery home page unwired from navigation | Page is unreachable in a running app; wire under `Config` toolbar item at creation time, not in a later cleanup pass |
| Grid/flex layout class on a gallery's outer wrapper | Hits `.widget-gallery-top-bar/-content/-footer` as the columns; cards strand in the middle track. Target `.widget-gallery-content` or use native `DesktopColumns` |
| Marking the gallery done without a visual pass | Render bugs (blank dates, wrong labels, KPI-as-list) sit in the reference and propagate to every page that copies it |
