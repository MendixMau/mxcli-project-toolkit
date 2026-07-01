# Skill: UX Audit

## When to use

Invoke this skill when:
- Significant page changes have been made and UX quality needs checking
- A customer demo is approaching and you need a gap analysis vs OutSystems
- The user says "run a UX audit", "compare to OS", "check the UI", or types `/ux-audit`

---

## Inputs required

- Mendix app running at `http://localhost:8080` (logged in or loginable as yoko.taoka / Contoso12345)
- OutSystems reference screenshots in `Share/converted/` (auto-discovered)
- `docs/ux-agent-brief.md` — evaluation rubric and report format (auto-updated in Phase 0)

---

## Three-phase execution

### Phase 0 — Sync the brief (auto, < 10 seconds)

Before running the capture, update `docs/ux-agent-brief.md` to reflect the current OS reference screenshots on disk. Scan `Share/converted/` for all `.png` files and replace the OS reference table in the brief.

```bash
# Discover current OS reference files
Get-ChildItem Share/converted -Recurse -Filter "*.png" | Select-Object FullName
```

Rewrite the OutSystems reference table in `docs/ux-agent-brief.md` with the discovered files and their relative paths. Do not change any other section of the brief.

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
./mxcli -p Contoso-TestRunOS.mpr -c "DESCRIBE PAGE PayerRegistration.PayerRegistration_Overview" > tests/ux-page-struct-overview.txt
./mxcli -p Contoso-TestRunOS.mpr -c "DESCRIBE PAGE PayerRegistration.Payer_OrgChoice" > tests/ux-page-struct-orgchoice.txt
./mxcli -p Contoso-TestRunOS.mpr -c "DESCRIBE PAGE PayerRegistration.Payer_Confirm_Selection" > tests/ux-page-struct-confirmation.txt
./mxcli -p Contoso-TestRunOS.mpr -c "DESCRIBE PAGE PayerRegistration.PayerDetail_NewEdit" > tests/ux-page-struct-newedit.txt
./mxcli -p Contoso-TestRunOS.mpr -c "DESCRIBE NAVIGATION Responsive" > tests/ux-page-struct-navigation.txt
./mxcli -p Contoso-TestRunOS.mpr -c "SHOW SNIPPETS IN PayerRegistration" > tests/ux-page-struct-snippets.txt
```

These files are passed to the Phase 2 agent alongside the screenshots. The agent uses them to:
- Identify layout grid column constraints causing narrow headers or clipped content
- Detect widgets using wrong types (TextBox where ComboBox is needed, missing Required property)
- Find containers missing Atlas card/spacing design classes
- Spot gallery columns without responsive hide-phone/hide-tablet classes
- Confirm widget Editable, Required, Visible properties match the page intent

### Phase 2 — Review (UX agent, ~5 min)

Spawn an Agent with the following prompt, passing all screenshot paths from the manifest, all OS reference paths discovered in Phase 0, and all page structure files from Phase 1b:

```
You are a senior UX reviewer. Read the agent brief at:
  docs/ux-agent-brief.md

Then read the capture manifest:
  tests/ux-capture-manifest.json

Then read these Mendix screenshots (use the Read tool on each):
[list all tests/screenshots/ux/*.png from the manifest]

Then read these OutSystems reference screenshots:
[list all Share/converted/**/*.png discovered in Phase 0]

Then read these page structure files (MDL DESCRIBE output — treat as the DOM equivalent):
  tests/ux-page-struct-overview.txt
  tests/ux-page-struct-orgchoice.txt
  tests/ux-page-struct-confirmation.txt
  tests/ux-page-struct-newedit.txt
  tests/ux-page-struct-navigation.txt
  tests/ux-page-struct-snippets.txt

Use the page structure files to:
- Identify layout grid column constraints that clip or narrow page content
- Find widgets using wrong types (TextBox where ComboBox/DatePicker is needed)
- Detect missing Atlas design properties: card class on gallery items, hide-phone on columns, Required on mandatory fields
- Spot containers with fixed pixel widths that break responsive layout
- Confirm widget Editable and Required properties match what screenshots suggest

Report CSS/layout issues separately from data-flow or microflow issues.
For CSS/layout issues, always state: (a) the widget name, (b) the current property value, (c) the recommended value, and (d) the exact mxcli ALTER PAGE command.

Follow the evaluation rubric and output format in the brief EXACTLY.
Be specific — cite widget names, section names, and screenshot filenames as evidence.
For every quick win provide the exact mxcli MDL command the team can run live.

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
