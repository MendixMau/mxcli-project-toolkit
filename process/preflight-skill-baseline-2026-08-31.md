# ui-preflight-pages.md — controlled A/B baseline, 2026-08-31

**Question:** does the skill's text actually change drafting behaviour, or was the ToeicBuddy
first-build failure (32% median fidelity, 0/10 shell, `process/first-build-page-fidelity-2026-08-27.md`)
a content problem?

**Method.** 10 fresh drafting agents (Sonnet, general-purpose subagents), one page each:
ToeicBuddy `Practice.Depts_Overview` (wireframe: `main{max-width:900px}`, top tab bar, one
card, 3-col KPI grid). Identical prompt core — wireframe + `ds.css` + StyleGallery directory
as the only readable materials, fixed domain facts, a minimal MDL syntax card, both
`Atlas_Default` and `Atlas_TopBar` offered. **Arm A (5 reps): no skill. Arm B (5 reps): the
full skill text inlined in the prompt.** Drafts scored with `project-bin/check-page-shell.sh`
and `project-bin/page-fidelity.js --no-log`; nothing written into the project.

## Results

| Metric | Arm A (no skill) | Arm B (skill inlined) |
|--------|------------------|----------------------|
| Shell violations per rep | 3,2,3,3,2 (median 3) | 1,1,1,1,1 (median 1, zero variance) |
| …excluding the by-construction column-cap failure | median 2 | **0 in all 5 reps** |
| Correct top-bar layout | 0/5 | 5/5 |
| H1 page title | 2/5 | 5/5 |
| Inline `Style:` attributes | 3/5 | 0/5 |
| Invented class names | 1/5 (`kpi-link`) | 0/5 |
| Empty state on the gallery | 0/5 | 5/5 |
| UI cross-reference block in report | 0/5 | 5/5 (all with honest NOT RUN rows) |
| Fidelity score | 57,66,66,66,66 | 66,66,66,79,66 |

Fidelity saturates at ~66–79% on this fixture (the missed rows are wireframe demo values a
dynamic gallery legitimately renders from data), so the shell check is the discriminating
instrument. One arm-A rep's report *claimed* an H1 scaffold the instrument then found absent —
the self-graded-checklist failure the report block's denominator rows exist for.

Depth of read in arm B: one rep refused an ACTIONBUTTON inside the `.kpi` tile citing the
Step 4 class-carrier specificity row; another refused unverifiable classes under B1 and
refused the wireframe's inline styles, proposing a promoted SCSS class instead. The deep
table rows are read, not skimmed, when the text is present.

## Conclusions acted on (same-day skill edit)

1. **Delivery, not prose, was the field failure.** The 2026-08-25/26 build *cited this skill
   by name* while producing arm-A numbers. When the text is in the drafting context,
   compliance is total. → delivery rule added at the top of the skill: dispatch prompts must
   inline the file (or the subagent reads it first); a one-line reference reproduces arm A.
2. **Stale caches inside the skill.** Step 2's class table and Step 3's gallery-file table
   listed another project's palette and inventory; one arm-B rep flagged the mismatch mid-run.
   → both tables replaced with read-the-actual-file instructions.
3. **The column cap was unbuildable.** All 10 reps failed it by construction: the project's
   `ds.css` has only an element-level `main{max-width}` rule and no page-column class a widget
   can carry; only 1/10 reps noticed. → Step 2 promotion instruction + Step 4 "Page column" row.
4. **The tuned content stays.** Arm B's clean sweep is the eval evidence that the Step 4
   table, hard rule B1 and the field-data paragraph work as written.

## Verification (arm C — 5 fresh reps with the revised skill, same day)

Same method, the revised text inlined. Shell violations {2,1,1,1,1} (the constant 1 is the
by-construction column-cap check; the project still has no matching class to carry).

- **The new page-column material works: 4/5 reps explicitly flagged the 900px column gap in
  their report block** (vs 1/10 pre-revision), one of them writing the promotion recipe into
  the script header. The fifth is the rep below.
- **No wholesale regression, but arm C was not arm B's clean sweep**: one rep chose
  `Atlas_Default` (the layout defect arm B had at 0/5), and one wrote a single inline
  `Style: 'text-align:start'` — reproducing the wireframe's *own* inline override while its
  report claimed B1 compliance. H1 5/5, invented classes 0/5, empty states 5/5, fidelity
  66% across the board.

Two defects across 5 reps against 0 in arm B is within n=5 noise, but the revision also grew
the file by ~800 words; if later field runs show the same dilution pattern, the delivery-rule
and column paragraphs are the ones to keep and the repeated "measured" citations the ones to
trim. The C2 self-report mismatch (inline style shipped, compliance claimed) is one more data
point for the denominator rows: only the mechanical checks caught it.

**Caveats.** n=5 per arm, one page, one model. The harness auto-injected the project's
CLAUDE.md into subagent contexts as system reminders; all reps reported ignoring it, and
arm A's uniform failures argue against contamination in the skill's favour. Raw drafts,
prompts and per-rep tallies lived in the session scratchpad (ephemeral); this file is the
durable record.
