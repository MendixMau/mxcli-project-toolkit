# gate-check.sh: where Stage 0 files must live (and why "not found" can lie about an existing file)

**Applies to:** any mxcli project using the toolkit pipeline
**Purpose:** resolve the Stage 0 gate failure "triage.md not found" when the file plainly
exists — it is almost always in the wrong directory, not missing.

`gate-check.sh` looks for stage deliverables (`intake.md`, `triage.md`, `assessment.md`, …)
through an `ANALYSIS_BASE` variable that resolves to `analysis/<source>/` **only once a
nested `knowledge-base/` directory exists there**. Until that directory exists — i.e. before
Stage 1 has run — `ANALYSIS_BASE` falls back to the project root.

**Practical effect:** Stage 0's `triage.md` and `assessment.md` must be written to the
**project root** (alongside `intake.md` and `PROJECT.md`), not under `analysis/`, or the
Stage 0 gate fails with `triage.md not found (looked in ./ and ./)` even though the file
exists. Once Stage 1 creates `analysis/<source>/knowledge-base/`, later-stage files can live
nested.

**When this bites:** delegating Stage 0 triage/assessment drafting to a subagent that
reasonably assumes an `analysis/` folder (that *is* where sources and BRDs eventually live)
and writes there. The gate output names the exact paths it looked in — read them, move the
file, and re-run; do not debug the script.
