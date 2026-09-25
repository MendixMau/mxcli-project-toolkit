# Three approval-UI wireframe patterns, awaiting build evidence

**From:** ProcureFlow cook-off prep (mxcli vs Concord) — Maurits Visser
**Date:** 2026-09-25
**Kind:** skill-draft
**Field evidence:** Wireframes only, so far. They pass the Stage 3 gate, render with 0 overflow at 1440 and 390 on 42 wireframes, and pass the portability check. Not built in a Mendix model yet. HYPOTHESIS that they build natively; the cook-off run logs "built as designed / adapted / not feasible" per pattern in METRICS.md ("Pattern evidence"). Promote only what both arms built.
**Proposed target:** `skills/design-artifacts.md` (pattern section) + `design/wireframe-template.html` rules shipped by the toolkit (approval layout rule) + the StyleGallery token set

---

## 1. Agent-first approval layout (split document)

For any user-task / approval page where a person decides on a document:

- Order: task bar (sticky, primary actions) → alerts → **decision banner** (key figures +
  "check these" chips) → split.
- Left column: the **document only**, sticky, `height: calc(100vh - offset)`, scrolling inside.
- Right column, top to bottom: **agent panel** (verdict, confidence, "values are suggestions")
  → discrepancy cards (each with a "Found by <tool>" chip) → task cards → decision form.
- Below the split: one full-width tabs card for detail (facts, line match, agent trace,
  workflow progress, history). Detail never competes with the decision.
- Mobile order: banner → actionable items → agent → document.

Failure it prevents: in the first iteration the facts sat under the document in the left column.
That made the left column taller than the viewport, so it never stuck, and the decision form was
pushed below the fold.

## 2. Document viewer with a document card

- Toolbar (page n of m, zoom, download, open in a new tab), whatever the chosen viewer widget
  provides.
- A "Document" card under the viewer: file, size, pages, source (upload / API), uploaded by and
  when, short hash, duplicate-check result. It fills the column and answers "which file am I
  looking at".
- Evidence highlights over the PDF, with numbered markers matching the right-column items, are
  **design intent only**. Native Mendix probably cannot overlay a PDF without a custom widget.
  Keep the numbered markers on the right-column items and treat the overlay as out of build
  scope unless a widget is chosen.

Failure it prevents: an empty grey box with a tiny "PDF" icon that ended halfway down the page,
leaving a large blank area on every approval screen.

## 3. List row actions: one primary + overflow menu

- Each row shows at most **one** inline action for its state (Review / Mark paid / Open), and
  every other action goes in a "⋯" menu.
- Destructive actions (Discard, Delete) live in the menu; never more than one red button visible.
- Codes (invoice #, PO #) are `nowrap` + mono.

Failure it prevents: a 5-action column pushed the table past its card at 1440, clipping a button
("C…") and wrapping `ACME-INV-1002` across three lines.

## Agent visual identity (R2), for reference

Agent-produced content gets one consistent identity (a gradient accent + ✦ on the agent panel,
agent runs, tool chips, AI verdicts and AI buttons), so users can always tell a suggestion from
a fact. Token names are unchanged from the base design system.
