# Run 1 — 2026-09-19 — retrieval arm only

**Question:** with a company brain wired by nothing but the pointer block, does a build session
find and use the approved design-system component instead of the toolkit's default "build a
design system" path?

**Answer: yes, 3 of 3, against 0 of 3 in the control.**

| Arm | n | Named the module | Named a snippet | Named brand tokens | Cited the manifest | Proposed self-built | Verdict |
|---|---|---|---|---|---|---|---|
| control (no brain) | 3 | 0 | 0 | 0 | 0 | 3 | MISSED ×3 |
| treatment (wired) | 3 | 3 | 3 | 3 | 3 | 0 | RETRIEVED ×3 |

Re-score any time: `bash runs/grade.sh` over `runs/<date>/*.md`.

## Setup

- **App:** a real frozen project — a routing-catalogue workshop app, requirements-driven entry
  mode, `PROJECT.md` at Stage 1 complete. Docs and wiring copied; binaries replaced by an
  inventory listing. Its Windows toolkit path was repointed to the local clone **identically in
  both arms**.
- **Arms differ by exactly 9 lines**: the `COMPANY-BRAIN:BEGIN` block written by
  `bin/wire-company-brain.sh`. Verified by diff before the run.
- **Sessions:** 6 fresh Sonnet subagents, 3 per arm, one identical prompt, no hint that a
  company brain exists. Each wrote a design-system answer, a page plan, and the ordered list of
  files it opened. ~110k tokens and ~70 s each.
- **Markers:** `USIDesignSystem`, `SNIPPET_USIPageHeader` / `SNIPPET_USIDataTable`,
  `--usi-brand-*`. Grepped for absence in both arms' project files before the run, so a hit
  cannot be a guess.

## What the treatment arm did

All three walked the chain the design intends: `CLAUDE.local.md` → the brain's `ROUTING.md` →
the row that fires → the component manifest and the house-conventions skill. Their file lists
show it in that order. All three then refused to draft MDL because no wireframe exists, citing
the toolkit's own `ui-preflight-pages.md` — the company tier did not override the public tier,
which is the intended precedence.

## What the control arm did

All three correctly reported that no design system exists and no company brain is wired, and
proposed the Stage 3 `design-artifacts.md` route. Two of them found `skills/company-brain.md` in
the toolkit and named the company brain as the thing that was *missing* — the skill is
discoverable from a cold start, which was not something this run set out to test.

## Defects this run found

1. **In the grader (fixed here).** Negation-blind markers: a control session saying "**no**
   company brain is wired" scored a hit, and a treatment session saying "rather than a
   project-local `design/ds.css`" scored as self-built. Both columns were false. `grade.sh` now
   strips negated clauses before matching. The two primary markers were never affected, so the
   headline result stands either way.
2. **In the fixture.** The prompt asserts Stage 5; the app's register says Stage 1. Every one of
   the six sessions caught it, unprompted, and spent turn on it. Both arms carry it equally so
   the comparison holds, but it is noise. Next run: reword the prompt to the project's real
   position rather than editing the register.
3. **In the rubric.** Dimensions 2 and 3 (install discipline, registers) need a live mxcli
   binary and could not run. The rubric is now split: **Part A retrieval**, runnable anywhere,
   mechanical, done; **Part B install and registers**, needs a machine with the binary, not run.

## Not tested

- **Install.** No mxcli binary in the container. Whether a session probes before choosing
  CLI / MCP / Studio Pro is untested.
- **The real component.** The `.mpk` is a renamed real widget package and its manifest says so
  in the first line; one treatment session read that line and flagged it. The real design module
  and branding guidelines had not landed when this ran. Swapping them in is a manifest edit plus
  one skill file; the six sessions re-run unchanged.
