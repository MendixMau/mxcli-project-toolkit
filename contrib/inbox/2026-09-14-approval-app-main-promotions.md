**From:** approval-app-main
**Date:** 2026-09-14
**Kind:** learning
**Field evidence:** promotion/defect sections found in approval-app-main's decision registers — each row was already reviewed in-project; triage into the named target files
**Proposed target:** see per-item notes below

---

## [from PROJECT.md] Toolkit defects found

| Date | Defect | Filed |
|---|---|---|
| 2026-08-06 | `gate-check.sh:146` reports Stage 0 **PASS** on a `triage.md` whose `## Sign-off` block is an empty, explicitly-PENDING template — it greps for the label `Confirmed by:`, not for a value. A `✋` hard-stop gate can therefore be passed by scaffolding alone. *(Stage 0 has since been genuinely signed off — the defect stands regardless.)* | `~/Mendix/personal-toolkit/proposals/gate-check-signoff-false-pass.md` |
| 2026-08-06 | **The runbook's "surface HTML is linked from `index.html`" checklist item is unsatisfiable.** `conversion-runbook.md` § *Checklist Before Calling a Stage "Done"* requires each stage's surface to be linked from `index.html`, but `gate-check.sh:546` **regenerates `index.html` from scratch** on every run as a gate-status table with no surface links at all. Any hand-added link is silently wiped by the next gate check. Either the generator should emit a surfaces column/section, or the checklist item should be dropped. Stage 2's surface (`analysis/knowledge-base/enrichment-summary.html`) is therefore reachable only via `PROJECT.md` and this table. | **Not filed** — pending an explicit "promote this" |
| 2026-08-06 | **`extraction-quality.json` can report 100% for an extraction with no independent verification.** Stage 1 here scored 100% against a manual read that was itself the only method — and a Stage 2 re-read then found two live defects, one of them recorded as the *inverse* of what the source says. The score measures fidelity to the reader, not to the source. Suggested rule: when the extraction method is a hand read with no second mechanism, the quality score should be capped or explicitly labelled *self-graded*, not reported as a clean 100%. | **Not filed.** User chose "patch forward, log as a gate defect" over the fix-the-toolkit option at CAC-2. Recorded here; promote to `~/Mendix/personal-toolkit/proposals/` only on explicit instruction |
| 2026-08-06 | **`bin/exec.sh` never logs the most common outcome — a clean build.** On Mendix 11.13.0 mxbuild writes **no** errors file when the model is clean, so a successful exec falls through to the final `else` branch (`exec.sh:285`) — the one outcome path with no `log_build` call. Result: 7 consecutive successful execs wrote 0 rows to `docs/BUILD-LOG.md`, while the single PARTIAL run logged correctly. The log's own header claims it is true "even when someone forgets", so the failure is invisible and inverted — it records problems and silently drops successes. An in-branch comment asserting mxbuild "ALWAYS writes an errors file, even on success" is false on this version and is what hid the gap. Fixed in this project's copy; 7 rows backfilled and explicitly marked reconstructed. | **Not filed** — pending an explicit "promote this"; per the personal-toolkit rule, it would land in `~/Mendix/personal-toolkit/` first, never directly in the shared toolkit |

