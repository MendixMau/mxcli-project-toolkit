# Gate/process defects harvested from a PLM-workflow migration project's register (3 pending items)

**From:** a PLM-workflow migration project (harvest run 2026-08-31; project referred to descriptively per the bug-log provenance convention)
**Date:** 2026-08-31
**Kind:** learning
**Field evidence:** rows from that project's `PROJECT.md` "Toolkit defects found" table, each already reviewed in-project on 2026-08-06. A fourth row (gate-check sign-off false-pass) was already filed as a personal-toolkit proposal by the project itself and is not repeated here.
**Proposed target:** per-item notes below — none may be promoted without the caveats attached

---

### 1. The runbook's "surface HTML is linked from `index.html`" checklist item is unsatisfiable
`conversion-runbook.md` § *Checklist Before Calling a Stage "Done"* requires each stage's
surface to be linked from `index.html`, but `gate-check.sh` **regenerates `index.html` from
scratch** on every run as a gate-status table with no surface links at all. Any hand-added
link is silently wiped by the next gate check. Either the generator should emit a
surfaces column/section, or the checklist item should be dropped. In the field, a Stage 2
surface ended up reachable only via `PROJECT.md`.
**Status:** pending — the source register marked it "Not filed — pending an explicit
'promote this'". Promote only on instruction.

### 2. `extraction-quality.json` can report 100% with no independent verification
A Stage 1 extraction scored 100% against a manual read that was itself the only method — a
Stage 2 re-read then found two live defects, one recorded as the *inverse* of the source.
The score measures fidelity to the reader, not to the source. Suggested rule: when the
extraction method is a hand read with no second mechanism, cap the score or label it
*self-graded*.
**Status:** pending with a hard caveat — at that project's CAC-2 the user explicitly chose
"patch forward, log as a gate defect" over fixing the toolkit. Recorded here for the
pattern's sake; promote only on explicit instruction.

### 3. `exec.sh` never logs the most common outcome — a clean build
On Mendix 11.13.0 mxbuild writes **no** errors file when the model is clean, so a
successful exec falls through to the one outcome branch with no `log_build` call. In the
field: 7 consecutive successful execs wrote 0 rows to the build log while the single
PARTIAL run logged correctly — the log records problems and silently drops successes,
inverting its own header's promise ("true even when someone forgets"). An in-branch
comment asserting mxbuild "ALWAYS writes an errors file, even on success" is false on that
version and hid the gap. The project fixed its local copy and backfilled 7 rows marked
reconstructed.
**Status:** pending — the source register routes it through the personal toolkit first,
never directly into the shared toolkit. The local fix exists in that project's copy if a
promoter wants the diff.
