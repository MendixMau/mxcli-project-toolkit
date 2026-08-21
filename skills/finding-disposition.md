# Skill: finding-disposition — no report ends without a disposition

**Applies to:** every skill that produces a report from a test/review run — currently
`module-review.md` (end of Stage 4/5), `existing-app-assurance.md` Track B (end of the run), and
`e2e-evidence-report.md` (after publishing). Any future report-producing skill should link here
too, rather than re-deriving this step.

**Status:** governing rule for what happens *after* a report is written, the same way
`degrade-to-judgement.md` governs what happens when an input is missing. Where a skill's closing
step is silent about disposition, this fills it in.

**Companion, not a duplicate:** `close-the-loop.md` already has the routing table — *where*
a P1/P2 finding goes (`docs/improvement-register.md`) and the three filing rules (verified only,
execs not commits, nothing in two places). This skill does not restate that table. It answers the
two questions that table doesn't: **when** filing is mandatory rather than optional, and **what to
do with a gap in what ran**, which is not a "finding" in that table's sense at all.

---

## The rule

> **A report that ends at "here are the findings" is half a report. Every FINDING gets routed per
> `close-the-loop.md`, and every gap in what ran gets a named disposition, before the run is
> called done — not because a session happened to remember, but because the owning skill requires it.**

The failure this replaces already happened once and was caught only by luck: a session ran
`graph-sweep.sh`, found it FAULTed on Linux for a real reason (a BSD-only `stat` flag silently
producing garbage instead of erroring), fixed the script inline, and separately noticed six
modules had no `coverage-ledger.md` and logged that to `docs/improvement-register.md` — but did
both **because that session happened to think of it**, not because any skill's closing step
required it. The next session, on a different finding, has no such prompt. A finding that lives
only in an HTML report nobody reopens is a finding that stops existing the moment the report closes.

## Two different things end up in a report, and they get different dispositions

| What you found | Disposition |
|---|---|
| **The harness itself is broken or blind** — a script faults for a reason that isn't the app's fault (wrong `stat` flags, a hardcoded persona, a selector that no longer matches, a check that can't tell partial-read from clean) | Fix it now, in the same cycle, per `skills-over-scripts.md` § "The harness updates itself, in the same cycle, not after" — **if** the fix is small and low-risk (the toolkit script itself, not the app). Then file what was wrong and what changed via `close-the-loop.md`'s routing table (usually `docs/improvement-register.md` as a `(harness)`/`other` row, or the toolkit skill itself if the fix generalizes), so the fix has a record. |
| **The app has a real defect** — blank render, crash, wrong data, bad layout, missing validation, a reuse gap | **Never fix inline during a review/audit pass** — `module-review.md`'s "Diagnostic only" rule and `existing-app-assurance.md`'s "read-only by default" rule both still apply; this skill does not override either. Route it through `close-the-loop.md` to `docs/improvement-register.md`, detailed enough for a cold `mdl-agent` pickup (see below), and ask the user which P1/P2s to send into the build loop now versus leave logged. |

Do not blur these. A harness fix is tooling hygiene you're trusted to do without asking (it changes
no app behavior). A product fix is app behavior and needs the user's go-ahead —
`iterative-build-loop.md` + the STOP table, same as always.

## What "detailed enough for a cold mdl-agent pickup" means

`close-the-loop.md` says a P1/P2 goes in the register; it doesn't say what makes a row *usable* by
someone with no memory of this session. The bar:

- **Module/Cluster + Source pass** — which rung found it, and which report cites it, so the
  evidence is traceable, not just asserted.
- **The finding itself, reproducible** — which page/element, what a user does, what happens
  instead of what should happen. "Grid renders blank" is not enough; "`ProductNumber_Overview`'s
  DataGrid2 columns render blank for every row but the first, confirmed via `/xas/` capture
  showing empty `attributes:{}`" is.
- **A suspected fix class**, even pre-root-cause: MDL-fixable (name the likely statement — a
  missing `sort by`, a grant, an `Editability` clause) vs. needs Studio Pro GUI/MCP page-patch vs.
  needs a data/seed repair vs. not yet known. This is what lets an mdl-agent triage the queue
  without opening every page cold.
- **Disposition**, using the register's existing vocabulary (`open`, `open (process)`,
  `fixed and verified`, `fixed, gate-clean, not live-UI-confirmed`, `n/a` + reason) — never leave a
  row without one.

If the register already tracks the finding (a rerun reproduced or superseded it), update that row's
trail instead of duplicating — `close-the-loop.md`'s "nothing in two places" rule applies here too.

## What "review if anything didn't run" means

This is the companion half, and it is not the same question as "were there findings." A report can
have zero findings and still owe this section, because zero findings from a rung that didn't run is
not zero findings — it's an unmeasured dimension wearing a clean result.

For every rung the owning skill's own denominator table names (module-review's 4a page set,
existing-app-assurance's per-module/per-persona coverage, e2e-evidence-report's journey list):

1. **State what ran and what didn't**, by name — this is `degrade-to-judgement.md`'s naming rule,
   applied specifically to "didn't run" rather than "input missing."
2. **For each thing that didn't run, say why**: no time budget, missing credentials for a persona,
   no journey file exists yet, an instrument faulted. "No time budget" is an honest answer — it is
   not a reason to omit the line.
3. **Decide whether the gap is a harness gap or a coverage gap** using the table above, and give it
   the matching disposition — a missing journey file is a coverage gap to log for whoever builds
   the suite next; a journey file that exists but the runner can't parse is a harness bug to either
   fix now or log as one.

## Closing question, every run

End every report-producing run — not just `module-review.md`, which already asks this for its own
P1/P2s ("Which P1/P2 findings shall I fix?") — with one combined question in chat:

> **"N findings logged to the improvement register. Which, if any, should I route into the build
> loop now? Which harness gaps should I fix now versus log for later?"**

Then stop and wait, per `interview-protocol.md`. Do not fix product defects, and do not skip
filing harness defects, on the assumption that "the report already said it."

## The mechanical backstop — this skill is not the only thing that can catch a skipped disposition

Everything above is judgement, read only when a session remembers to read it — the exact gap
`close-the-loop.md` already names about itself. Two mechanisms now back it up, so a skipped
disposition is caught even when nobody thought to open this file:

- **`claude-hooks/hooks/work-boundary.sh`** appends a ledger line the moment a report-producing
  command runs (`verify-module.sh`, `review-module.sh`, `journey-runner.js`, `design-audit.js`),
  reading `"<command class> ran → owes a finding-disposition.md pass (route findings via
  close-the-loop.md to docs/improvement-register.md, name what didn't run)"`. That obligation then
  sits on disk in `.claude/.pending-writes`, and `claude-hooks/hooks/precompact-guard.sh`
  interrupts compaction (once per session) while it is non-empty — the run cannot simply scroll
  out of context unfiled without at least one warning.
- **`project-bin/report-disposition-check.sh`** is the mechanical check this skill's judgement
  cannot self-enforce: it reads the newest report, greps it for the FAULT/FINDING/FAIL/NOT
  RUN/short-denominator vocabulary this file and its companions already use, and checks whether
  `docs/improvement-register.md` picked up a row dated the same day. A report with findings and
  zero matching register rows is a FINDING (exit 1) — an un-filed report, not a broken instrument.
  It is wired into `bin/gate-check.sh` at Stages 5 and 6, the same two stages this skill applies
  to, and blocks the gate there exactly like the obligations table already blocks a skipped LOOK
  or sweep.

Same pattern `close-the-loop.md` itself argues for: a document only read on purpose is not enough,
so the judgement layer above now has a mechanical layer under it that notices when it was skipped.
Neither script decides whether a finding matters or how to fix it — that stays here and in
`close-the-loop.md`, per `skills/skills-over-scripts.md`.

## Related

- `skills/close-the-loop.md` — the routing table and filing rules this skill hands off to
- `skills/degrade-to-judgement.md` — the missing-input sibling rule; this skill is its "missing
  run" and "unrouted finding" counterpart
- `skills/skills-over-scripts.md` § "The harness updates itself, in the same cycle, not after" —
  governs the harness-fix half of the table above
- `skills/module-review.md` § "Diagnostic only" — governs the product-fix half
- `skills/existing-app-assurance.md` — Track B's "read-only by default" ground rule, unchanged
- `claude-hooks/hooks/work-boundary.sh` + `project-bin/report-disposition-check.sh` — the
  mechanical backstop described above
