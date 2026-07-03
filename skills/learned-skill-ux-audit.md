# Skill: UX Audit

## When to use

Invoke this skill when:
- Significant page changes have been made and UX quality needs checking
- A customer demo is approaching and you need a gap analysis vs OutSystems
- The user says "run a UX audit", "compare to OS", "check the UI", or types `/ux-audit`

---

## Inputs required

- Mendix app running at `http://localhost:8080` (or project-specific port — check `tests/helpers.sh` or the CLAUDE.md for the `APP` variable)
- Source reference screenshots (optional — auto-discovered in `Share/converted/` or `docs/screenshots/`)
- `docs/ux-agent-brief.md` — evaluation rubric and report format (auto-updated in Phase 0)
- Design system file (optional but preferred — auto-discovered in Phase -1)

---

## Four-phase execution (Phase -1 added for design artifact discovery)

### Phase -1 — Discover design artifacts (auto, < 30 seconds)

**Before anything else, look for design artifacts to use as reference material.** This step runs even if the user did not mention a design system — the goal is to discover what exists.

Search these locations in order:

```bash
# 1. Design system HTML files — the highest-fidelity reference
find . -maxdepth 3 -name "design-system.html" -o -name "design*.html" | grep -v node_modules

# 2. Wireframe/design folders
find . -maxdepth 3 -type d \( -name "design" -o -name "designs" -o -name "wireframes" -o -name "mockups" \)

# 3. Screenshots in design/docs folders
find . -maxdepth 4 \( -name "*.png" -o -name "*.jpg" \) \( -path "*/design/*" -o -path "*/wireframes/*" -o -path "*/docs/*" \)

# 4. Figma/Zeplin/Sketch references in markdown docs
grep -r "figma.com\|zeplin.io\|app.abstract.com" docs/ README.md CLAUDE.md 2>/dev/null | head -10
```

After discovery, create `tests/ux-design-artifacts.md` — a short manifest of what was found:

```markdown
## Design artifacts discovered

### Design system
- Path: design/design-system.html
- Type: HTML design system with CSS tokens, component samples, and Atlas mapping table
- Key tokens extracted: [list 3-5 key tokens/colors/fonts from scanning the file]

### Source reference screenshots
- [list any screenshots found, or "None found"]

### Wireframes
- [list any wireframe files, or "None found"]

### External links
- [list any Figma/Zeplin URLs found, or "None found"]
```

If a design system HTML file exists, read it and extract these into the manifest:
- Primary brand color (e.g. `--brand-500: #2a78d6`)
- Surface/background colors
- Status colors (good/warning/critical)
- Border-radius values
- Font family and key type scale values
- Any Atlas mapping table (`--token` → `$atlas-var`)

**This manifest is passed to the Phase 2 agent as the design compliance reference.** If no design artifacts are found at all, log `"No design artifacts found — audit will focus on Atlas conventions and general UX quality"` in the manifest and continue.

### Phase 0 — Sync the brief (auto, < 10 seconds)

Before running the capture, update `docs/ux-agent-brief.md` to reflect the current reference screenshots on disk. Scan `Share/converted/` (or `docs/screenshots/`) for all `.png` files and replace the reference table in the brief.

```bash
# Discover current reference files (try multiple locations)
find Share/converted docs/screenshots -name "*.png" 2>/dev/null | sort
```

Rewrite the reference screenshot table in `docs/ux-agent-brief.md` with the discovered files and their relative paths. Do not change any other section of the brief.

### Phase 1 — Capture (automated, ~3 min)

```bash
node tests/ux-capture.js
```

This produces:
- `tests/screenshots/ux/*.png` — 30+ screenshots covering login, overview, orgchoice, confirmation, newedit (per section), validation state, mobile viewport
- `tests/ux-capture-manifest.json` — structured metadata per page: button labels, editable/readonly field counts, section headers, validation errors, breadcrumb text

If the capture exits with an error, stop and report. Do not proceed to Phase 2 with a partial capture.

### Phase 1b — Page structure dump (automated, ~1 min)

After the screenshot capture, extract the MDL page structure for every page covered by the capture. This gives the agent DOM-equivalent information: layout grids, column widths, container nesting, widget types, CSS classes, and design properties — things that screenshots alone cannot reveal.

Run these commands and write the output to `tests/ux-page-structures.json`:

```bash
./mxcli -p Apex-TestRunOS.mpr -c "DESCRIBE PAGE PayerRegistration.PayerRegistration_Overview" > tests/ux-page-struct-overview.txt
./mxcli -p Apex-TestRunOS.mpr -c "DESCRIBE PAGE PayerRegistration.Payer_OrgChoice" > tests/ux-page-struct-orgchoice.txt
./mxcli -p Apex-TestRunOS.mpr -c "DESCRIBE PAGE PayerRegistration.Payer_Confirm_Selection" > tests/ux-page-struct-confirmation.txt
./mxcli -p Apex-TestRunOS.mpr -c "DESCRIBE PAGE PayerRegistration.PayerDetail_NewEdit" > tests/ux-page-struct-newedit.txt
./mxcli -p Apex-TestRunOS.mpr -c "DESCRIBE NAVIGATION Responsive" > tests/ux-page-struct-navigation.txt
./mxcli -p Apex-TestRunOS.mpr -c "SHOW SNIPPETS IN PayerRegistration" > tests/ux-page-struct-snippets.txt
```

These files are passed to the Phase 2 agent alongside the screenshots. The agent uses them to:
- Identify layout grid column constraints causing narrow headers or clipped content
- Detect widgets using wrong types (TextBox where ComboBox is needed, missing Required property)
- Find containers missing Atlas card/spacing design classes
- Spot gallery columns without responsive hide-phone/hide-tablet classes
- Confirm widget Editable, Required, Visible properties match the page intent

### Phase 2 — Review (UX agent, ~5 min)

Spawn an Agent with the following prompt, passing all screenshot paths from the manifest, all reference paths discovered in Phase 0, the page structure files from Phase 1b, and the design artifacts manifest from Phase -1:

```
You are a senior UX reviewer with expertise in Mendix Atlas design. Read the agent brief at:
  docs/ux-agent-brief.md

Then read the capture manifest:
  tests/ux-capture-manifest.json

Then read the design artifacts manifest discovered for this project:
  tests/ux-design-artifacts.md

[If a design system HTML file was found in Phase -1, also read it:]
  [design/design-system.html or other path from the manifest]

Then read these Mendix screenshots (use the Read tool on each):
[list all tests/screenshots/ux/*.png from the manifest]

Then read these source/reference screenshots (if any were discovered):
[list all discovered reference PNGs, or skip this section if none]

Then read these page structure files (MDL DESCRIBE output — treat as the DOM equivalent):
  tests/ux-page-struct-overview.txt
  tests/ux-page-struct-orgchoice.txt
  tests/ux-page-struct-confirmation.txt
  tests/ux-page-struct-newedit.txt
  tests/ux-page-struct-navigation.txt
  tests/ux-page-struct-snippets.txt

## Your review has four dimensions:

### 1. Design system compliance (if a design system was found)
Compare the captured screenshots against the design system's:
- **Color tokens**: Are primary action buttons using the brand primary color? Are status badges using the correct good/warning/critical colors?
- **Typography**: Are heading sizes, font weights, and body text consistent with the type scale?
- **Spacing**: Are cards and containers using the spacing tokens (not arbitrary px values)?
- **Border radius**: Do buttons, inputs, and cards match the design system's radius values?
- **Component patterns**: Are buttons, inputs, badges, and dialogs matching the design system's component specs?

For each non-compliance, state: (a) the widget name, (b) what the design system specifies, (c) what is currently rendered, (d) the severity (critical/moderate/minor), and (e) the exact `ALTER PAGE` or `custom-variables.scss` fix.

### 2. Layout and widget type issues
- Identify layout grid column constraints that clip or narrow page content
- Find widgets using wrong types (TextBox where ComboBox/DatePicker is needed)
- Detect missing Atlas design properties: card class on gallery items, hide-phone on columns, Required on mandatory fields
- Spot containers with fixed pixel widths that break responsive layout
- Confirm widget Editable and Required properties match what screenshots suggest

### 3. UX quality and source parity
Compare against the source reference screenshots (if any). Flag regressions in information architecture, label text, or flow logic.

### 4. Atlas mapping gaps
If the design system has an Atlas mapping table (--token → $atlas-var), cross-reference with `theme/web/custom-variables.scss` if present. Flag any token that is defined in the design system but not applied in the theme.

Report each dimension separately. For every issue in any dimension, always state:
(a) the widget name or file, (b) the current value, (c) the recommended value,
(d) the severity (critical/moderate/minor), and (e) the exact mxcli MDL command or SCSS change.

Follow the evaluation rubric and output format in the brief EXACTLY.
Be specific — cite widget names, section names, and screenshot filenames as evidence.
For every quick win provide the exact mxcli MDL command or SCSS edit the team can run live.

Write the complete report to:
  docs/ux-review-[TODAY'S DATE].md
```

Run the agent with `run_in_background: true`. You will be notified when it completes.

### Phase 3 — Parse output and create tasks (auto, after agent completes)

When the agent completes, read `docs/ux-review-[DATE].md` and:

1. **Extract all Quick Wins** — lines matching the `### QW-NN:` pattern
2. **Create a TaskCreate for each quick win** with:
   - `subject`: `QW-NN: [short title from report]`
   - `description`: Issue + Impact + exact mxcli command from the report
3. **Extract all Deeper Improvements** — rows in the `### Deeper improvements` table
4. **Create a TaskCreate for each deeper item** with:
   - `subject`: `UX D-NN: [problem from report]`
   - `description`: Problem + root cause + recommended fix + effort estimate

Report back to the user with:
- Overall score summary (average per page from the scores table)
- Count of quick wins created as tasks
- Count of deeper improvements created as tasks
- Link to the full report: `docs/ux-review-[DATE].md`

---

## Output files

| File | Contents |
|------|----------|
| `tests/screenshots/ux/*.png` | All captured screenshots (overwritten each run) |
| `tests/ux-capture-manifest.json` | Page metadata for the agent |
| `tests/ux-page-struct-*.txt` | MDL DESCRIBE output per page — layout grids, widget types, CSS classes |
| `docs/ux-review-YYYY-MM-DD.md` | Full scored UX report |
| Tasks in task list | One task per quick win + one per deeper improvement |

---

## Updating the brief

`docs/ux-agent-brief.md` is the evaluation contract — it defines the rubric and output format. Do not change the rubric or output format sections. Only update:
- The OS reference screenshot table (Phase 0 auto-syncs this)
- The known bugs table (update manually after bug log changes)

---

## Re-running after fixes

After applying quick wins, re-run the full skill to measure improvement. The new `ux-review-[DATE].md` file is written with today's date — previous reports are preserved for comparison.

To compare scores across runs:
```bash
# List all UX reports chronologically
Get-ChildItem docs -Filter "ux-review-*.md" | Sort-Object Name
```
