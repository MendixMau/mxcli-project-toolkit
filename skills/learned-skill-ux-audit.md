# Skill: UX Audit

## When to use

Invoke this skill when:
- Significant page changes have been made and UX quality needs checking
- A customer demo is approaching and you need a gap analysis vs the design system
- The user says "run a UX audit", "compare to design system", "check the UI", or types `/ux-audit`

---

## Inputs required

- Mendix app running at `http://localhost:8080` (or project-specific port — check `tests/helpers.sh` or CLAUDE.md for the `APP` variable)
- **Design system file** — look first at `design/design-system.html` (the Stockpilot standard location). Read it fully before auditing — tokens, component specs, Atlas mapping table, and app shell wireframe all inform the audit.
- Source reference screenshots (optional — auto-discovered in `design/screenshots/` or `docs/screenshots/`)
- `docs/ux-agent-brief.md` — evaluation rubric and report format (auto-updated in Phase 0, create if missing)

---

## ⛔ Hard gate: confirm a fresh build before any screenshot

**Run this check before Phase -1. If it fails, stop and tell the user to restart SP and Run Locally.**

```bash
# 1. App must be responding
curl -s -o /dev/null -w "%{http_code}" http://localhost:${APP_PORT:-8080}/login.html
# Expected: 200. If 000 or non-200 → app is not running. Do not proceed.

# 2. Verify SP was restarted after the last mxcli exec
# Ask yourself: was `pkill -9 -f "Contents/MacOS/studiopro"` run after the last exec?
# If not, the browser may be serving a stale bundle. Restart SP before continuing.
```

**Why this matters:** `mxcli exec` writes to the `.mpr` file but the browser serves a JS bundle compiled by Studio Pro. Without a full SP restart + Run Locally, screenshots reflect the *previous* build — making any audit or diff meaningless. This has caused real wasted work: fixes were written for issues that had already been resolved, and issues were missed that were actually present.

**Rule:** Never call playwright-cli screenshot or evaluate DOM until you have confirmed that SP was restarted *after* the last exec and the app returned 200 on the login URL.

---

## Four-phase execution (Phase -1 added for design artifact discovery)

### Phase -1 — Discover design artifacts (auto, < 30 seconds)

**Before anything else, look for design artifacts.** This step is mandatory.

```bash
# 1. Design system HTML — highest-fidelity reference
find . -maxdepth 3 -name "design-system.html" -o -name "design*.html" | grep -v node_modules

# 2. Design/wireframe folders
find . -maxdepth 3 -type d \( -name "design" -o -name "designs" -o -name "wireframes" -o -name "mockups" \)

# 3. Reference screenshots
find . -maxdepth 4 \( -name "*.png" -o -name "*.jpg" \) \( -path "*/design/*" -o -path "*/wireframes/*" -o -path "*/docs/*" \)
```

**If a design system HTML file is found:**
1. Read the full file
2. Extract all design tokens: brand colors, radius, spacing, typography scale, surface colors, status colors
3. Note the Atlas mapping table (design token → Atlas SCSS variable)
4. Note every component specified: buttons (variants + states), inputs (affix, error states), KPI tiles (with icon, delta), table (header style, row hover, status badges), dialog (icon + footer pattern), app shell (sidebar, command bar)
5. Capture reference screenshots using Playwright headed (see Phase 1b below)
6. Write `tests/ux-design-artifacts.md` manifest

**Key tokens to extract from Stockpilot design system:**
```
--brand-500: #2a78d6          → $brand-primary (Atlas)
--status-good: #0ca30c        → $brand-success
--status-warning: #fab219     → $brand-warning
--status-critical: #d03b3b    → $brand-danger
--page: #f9f9f7               → $background-color
--surface-1: #ffffff          → card surface
--r-md: 10px / --r-lg: 14px  → border radius
--font-sans: system-ui        → $font-family-base
```

**If no design system is found:** log `"No design artifacts found — audit will focus on Atlas conventions and general UX quality"` and continue.

---

### Phase 0 — Sync the brief (auto, < 10 seconds)

Update `docs/ux-agent-brief.md` to reflect current reference screenshots. Create the file if missing:

```bash
find design/screenshots docs/screenshots -name "*.png" 2>/dev/null | sort
```

---

### Phase 1 — Capture live app screenshots (Playwright, ~3 min)

**Use the headed Playwright script at `tests/ux-visual-audit.js`** (IVM standard). If no such script exists, create one.

The script must:
- Run headed (`headless: false`) so the user can watch
- Inject a visible red cursor dot for clarity
- Use `slowMo: 80` for legible replay
- Screenshot every distinct UI state: login, overview (full), KPI tiles close-up, datagrid close-up, add/edit popup (empty + filled), sell/insert popup, history page, delete confirmation

All screenshots go to `tests/screenshots/ux/`.

---

### Phase 1b — Capture design system reference screenshots (Playwright, ~30s)

Open the design system HTML file in a headless Playwright session and screenshot each component section:

```javascript
await page.goto('file:///path/to/design/design-system.html', { waitUntil: 'networkidle' });
// Screenshot: KPI row, table, buttons panel, form panel, dialog, app shell
```

Save to `tests/screenshots/design-system/`. These are the pixel-level reference the comparison agent uses.

---

### Phase 1c — Dump page structures (mxcli, ~1 min)

```bash
./mxcli -p *.mpr -c "DESCRIBE PAGE Module.Overview" > tests/ux-page-struct-overview.txt
./mxcli -p *.mpr -c "DESCRIBE PAGE Module.NewEdit"   > tests/ux-page-struct-newedit.txt
# etc. for all pages
./mxcli -p *.mpr -c "DESCRIBE NAVIGATION Responsive" > tests/ux-page-struct-nav.txt
```

---

### Phase 2 — Visual gap analysis agent (~5 min)

Spawn an Agent with this prompt, passing all screenshots and page structures:

```
You are a senior UX reviewer with deep expertise in Mendix Atlas and the Stockpilot design system.

Read the design system:
  design/design-system.html

Read the design artifacts manifest:
  tests/ux-design-artifacts.md

Read the design system REFERENCE screenshots (what it SHOULD look like):
  tests/screenshots/design-system/ds-kpi-tiles.png
  tests/screenshots/design-system/ds-table.png
  tests/screenshots/design-system/ds-buttons.png
  tests/screenshots/design-system/ds-form.png
  tests/screenshots/design-system/ds-dialog.png
  tests/screenshots/design-system/ds-app-shell.png

Read the LIVE app screenshots (what it ACTUALLY looks like):
  [list all tests/screenshots/ux/*.png]

Read the page structures:
  [list all tests/ux-page-struct-*.txt]

## Your job: identify EVERY gap between the design system and the live app.

### Dimension 1 — Color compliance
Compare pixel colors in the live screenshots against design tokens:
- Primary button: should be --brand-500 (#2a78d6). Is it?
- Page background: should be --page (#f9f9f7). Is it?
- Card surfaces: should be --surface-1 (#ffffff) with 1px --hairline (#e1e0d9) border and --shadow-sm. Are they?
- KPI tiles: should have border-radius --r-lg (14px), icon in --grad-ai-soft background. Do they?
- Table headers: should be --surface-2 with UPPERCASE xs text, --ink-muted color. Are they?
- Status badges: should be pill-shaped with dot + label, colors good/warning/critical. Present?
- Danger button: should be transparent with --status-critical text/border, NOT a solid red button. Is it?

### Dimension 2 — Typography
- Page heading: design specifies text-xl (22px) semibold for "Item list". What renders?
- KPI values: design specifies text-3xl (2.25rem) bold tabular-nums. What renders?
- Table header: should be text-xs uppercase letter-spacing .04em. What renders?
- Body text: should be text-base (14px). What renders?

### Dimension 3 — Component patterns
Compare each live component against the design system spec:
- KPI tiles: design has icon (SVG in grad-ai-soft box, top-right), label, value (hero size), delta (▲/▼ with status color). What does the live tile show?
- Table actions column: design shows segmented Sell/Insert control + icon-only Edit + icon-only danger Delete. Live shows separate "Sell"/"Insert" buttons + text "History" button + icon trash. What are the gaps?
- Edit button: design specifies icon-only (pencil SVG, 36×36 border btn). Live shows glyphicon class. Gap?
- Delete button in table: design specifies icon-only danger hover. Live shows icon. Close?
- Add Item button: design shows btn-primary with "+" icon. Live shows text-only. Gap?
- Form inputs: design has input-affix with "€" prefix for Cost/Price. Live shows plain textbox. Gap?
- Required field indicators: design shows red asterisk (*) next to label. Live shows?
- Sidebar navigation: design specifies a 220px sidebar with brand mark + nav items with icons. Live uses Atlas top nav. Major gap?
- Command bar: design specifies an AI command bar on every screen. Present in live?
- Page background: design specifies --page (#f9f9f7, warm off-white). Live Atlas default is white. Gap?

### Dimension 4 — Missing design system features entirely absent from live app
List every feature defined in the design system that doesn't exist at all in the live app:
- Stock status badges (In stock / Low stock / Out of stock) on table rows
- Delta indicators on KPI tiles (▲ 8.2% vs yesterday)
- AI insight KPI tile (Stockpilot insight chip)
- Command bar / ⌘K search
- Sidebar navigation with icons
- Bar chart (stock on hand visualization)
- Toast feedback on successful sell/insert
- Icon-only buttons for Edit/Delete (not glyphicon text icons)
- Segmented Sell/Insert control (not two separate buttons)
- Affixed currency inputs (€ prefix)
- Warm off-white page background (#f9f9f7)

For EACH gap found, state:
(a) What the design system specifies
(b) What the live app shows instead
(c) Severity: critical (brand-breaking) / moderate (noticeable) / minor (polish)
(d) The exact fix: either an MDL ALTER PAGE command, a custom-variables.scss change, or both

Format output as a structured list. Be exhaustive — this is a design compliance audit, not a quick check.

Write the complete report to:
  docs/ux-review-[TODAY'S DATE].md
```

---

### Phase 3 — Parse findings, create tasks, summarize

After the agent completes:
1. Extract all critical and moderate gaps
2. Group into two tracks:
   - **Theme track** (SCSS/Atlas vars — single fix covers all pages): color tokens, radius, background, typography scale
   - **MDL track** (per-page widget changes): button variants, input affixes, badge widgets, layout additions
3. Create a TaskCreate for each track item
4. Report back with overall score (0–100) and prioritized fix list

---

### Phase 4 — Generate HTML report

After the markdown report exists at `docs/ux-review-YYYY-MM-DD.md`, generate a styled HTML version at `docs/ux-review-YYYY-MM-DD.html` using the Stockpilot design tokens.

**Structure of the HTML report:**

```
topbar        — brand-mark + "Stockpilot / UX Gap Report" logo + date badge + "N gaps found" badge
summary row   — 4 stat tiles: Critical / Moderate / Minor / Total (with SCSS·MDL·arch breakdown)
section: Theme Track    — gap cards, one per SCSS fix
section: MDL Track      — gap cards, one per widget change
section: Architectural  — table of out-of-scope features (Phase 4)
section: Microflow Bugs — table of functional bugs found during E2E
section: Priority Order — numbered priority list with track badges
footer        — report version + date
```

**Gap card anatomy (reuse for every finding):**

```html
<div class="gap-card">
  <div class="gap-header">
    <span class="gap-num">01</span>         <!-- 2-digit number -->
    <span class="gap-title">Gap name</span>
    <span class="badge critical|warning|neutral">Severity</span>
  </div>
  <div class="gap-body">
    <!-- 3 rows: Design spec / Live app / Fix -->
    <div class="gap-row">
      <span class="gap-key">Design spec</span>
      <span class="gap-val">...</span>
    </div>
    <div class="gap-row">
      <span class="gap-key">Live app</span>
      <span class="gap-val">...</span>
    </div>
    <div class="gap-row">
      <span class="gap-key">Fix</span>
      <span class="gap-val"><div class="code-block">MDL or SCSS here</div></span>
    </div>
  </div>
</div>
```

**Required CSS classes (copy verbatim from `docs/ux-review-2026-07-05.html` in the IVM project — it is the canonical template):**

| Class | Purpose |
|---|---|
| `.gap-card` | White card, hairline border, r-lg, shadow-sm |
| `.gap-header` | Surface-2 bg, hairline bottom border, flex row |
| `.gap-num` | Brand-500 bold tabular number, 28px wide |
| `.gap-body` | Padding sp-5 |
| `.gap-row` | 2-col grid: 96px key + 1fr value |
| `.gap-key` | xs uppercase muted label |
| `.code-block` | Monospace, surface-sunken bg, hairline border, r-md |
| `.track-badge.track-scss` | Blue pill for SCSS items |
| `.track-badge.track-mdl` | Violet pill for MDL items |
| `.track-badge.track-arch` | Muted pill for architectural items |
| `.priority-item` | White card row: numbered circle + text + track badge |
| `.stat-tile` | KPI-style tile: label / value (text-3xl) / sub |

**Open the report:** After writing the file, run `open docs/ux-review-YYYY-MM-DD.html` so the user can see it immediately.

---

## Output files

| File | Contents |
|------|----------|
| `tests/ux-design-artifacts.md` | Design artifacts discovered in Phase -1 (design system, screenshots, wireframes, external links) |
| `tests/screenshots/ux/*.png` | All captured screenshots (overwritten each run) |
| `tests/ux-capture-manifest.json` | Page metadata for the agent |
| `tests/ux-page-struct-*.txt` | MDL DESCRIBE output per page — layout grids, widget types, CSS classes |
| `docs/ux-review-YYYY-MM-DD.md` | Full scored UX report with design system compliance dimension |
| `docs/ux-review-YYYY-MM-DD.html` | Styled HTML report using Stockpilot tokens |
| Tasks in task list | One task per quick win + one per deeper improvement |

---

## Updating the brief

`docs/ux-agent-brief.md` is the evaluation contract — it defines the rubric and output format. Do not change the rubric or output format sections. Only update:
- The OS reference screenshot table (Phase 0 auto-syncs this)
- The known bugs table (update manually after bug log changes)

---

## Re-running after fixes

After applying fixes (theme or MDL), re-run the full skill. The new report date creates a new file — old reports are preserved for comparison.

To compare gap counts across runs:
```bash
ls -1 docs/ux-review-*.html | sort
```

---

## Known design system gaps for IVM (as of 2026-07-05)

These gaps were confirmed by the first full audit run:

| Gap | Severity | Fix track |
|-----|----------|-----------|
| Page background is white, should be #f9f9f7 | moderate | SCSS |
| Primary button color not #2a78d6 (Atlas default blue) | critical | SCSS |
| KPI tiles missing icon, delta, and hero-size value | critical | MDL |
| Table headers not uppercase xs text with letter-spacing | moderate | SCSS |
| Sell/Insert are separate buttons, not segmented control | moderate | MDL |
| Edit/Delete are glyphicon buttons, not clean icon-btns | moderate | MDL |
| No stock status badge (In stock / Low / Out of stock) | critical | MDL + entity |
| Cost/Price inputs lack € prefix affix | minor | MDL |
| No sidebar navigation — uses Atlas top nav | major | Layout |
| No command bar / AI search | major | MDL |
| No toast feedback on sell/insert success | moderate | MDL |
| No bar chart on overview | moderate | MDL |
| Required field (*) indicators missing on form | minor | MDL |
| Delete dialog lacks danger icon in header | minor | MDL |
