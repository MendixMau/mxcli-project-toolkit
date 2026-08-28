# Measured: first-build page fidelity is ~1/3 of the wireframe, and the pre-flight was followed

**Date:** 2026-08-27
**Corpus:** `MendixMau/toeic-buddy` — ToeicBuddy conversion, the 2026-08-25/26 field run.
78 MDL build scripts, 14 wireframes, 10 Practice pages, one design system.
**Method:** model-side only — wireframe HTML vs the page's own build MDL. No app, no
Studio Pro, no screenshots. Prototypes in `process/prototypes/`.

---

## The question

Does a page, on its **first** build, match the wireframe it was built from? The
working target is 80%; the toolkit's only wireframe-coverage rule
(`project-tests/e2e/page-audit-rules.js`, `wireframe/region-coverage`) passes at
`ratio > 0.34`, is severity P3, and — see below — is never invoked.

## The answer

First-build fidelity, scored on headings + action labels + structural classes
(the dimensions that survive a Mendix build; see "What this does not measure"):

| Page | first-build fidelity | repair scripts after |
|---|---|---|
| Vocab_Flashcards | 3% | 5 |
| Listening_Overview | 4% | 4 |
| Dashboard | 11% | 7 |
| Listening_Part | 13% | 8 |
| Reading_Overview | 23% | 2 |
| Depts_Pack | 32% | 7 |
| Speaking_Tasks | 41% | 4 |
| Reading_Part | 52% | 5 |
| VoiceSettings | 63% | 4 |
| Depts_Overview | 67% | 4 |

**Median 32%. Mean 31%. Nothing reached 80%.** Highest was 67%.

## The pre-flight was not skipped

`12-practice-pages.mdl`'s header cites `ui-preflight-pages.md` Step 3 by name, lists
the StyleGallery classes reused, cites `design-spacing.md`'s page-head scaffold, and
logs its wireframe deviations to `run/decisions.md`. The discipline ran. The output
still needed 28 repair scripts.

So the failure is **not** "the agent didn't load the skill". It is that the pre-flight
terminates in a prose "UI cross-reference block" that nothing scores and nothing checks.
Grep confirms that block is named in exactly two places (`agents/mdl-agent.md:110`,
`skills/agent-roles.md:233`) and read by no script or gate.

## Two defects hit 100% of pages and were repaired 10x each

These are the compounding, made countable. Both are stated unambiguously in every
wireframe, and both are decidable in milliseconds from files alone.

**1. The page column.** All **14 of 14** wireframes declare `main{max-width:900px}`.
**0 of 10** pages capped their width. Script `67-page-column.mdl` — fifty-five scripts
after the pages were built — records the measured consequence: content at 1360px,
"three buttons stretched to ~440px each around 25-char captions", "prompts set 1300px
wide — roughly 160 characters per line, about double a comfortable measure", and a
Reading page rendering at two different measures at once. Its own note: *"Nothing chose
that; it is simply what a container does when nothing caps it, and no script ever
capped it."*

**2. The layout shell.** Every wireframe draws `<nav class="tabs">` — a top bar.
**0 of 10** pages used `Atlas_TopBar`; all 10 were built on `Atlas_Default`, whose
collapsed sidebar clipped labels ("All task" for "All tasks"). Repaired wholesale at
script 20.

`process/prototypes/page-shell-conformance.proto.js` re-runs both checks against the
first-build MDL and reports **0/10 and 0/10**. Either would have fired at script 12.

## What a repair count does and does not prove

`Reading_Overview` scored 23% and drew only 2 repairs. That is not a counter-example —
its wireframe asks for "Part 5 - Grammar (10)" and the page says "Part 5". The
divergence is still there. **Repair count measures whether someone noticed, not whether
the page was right**, which is why correlation between fidelity and repairs is only
r ≈ -0.30 across these ten pages. The fidelity score is the better instrument precisely
because it does not depend on anyone noticing.

## What this does not measure

- **Bound text.** A wireframe's sample copy ("Speaker A: We received a complaint...")
  becomes an attribute binding in MDL. Scoring literal content punishes a correct page.
  The full-dimension score (content included) reads 3–62%, median 24%; the table above
  drops that dimension. Both are in `first-build-fidelity.proto.js`.
- **Render.** This is model-side. A page can score 100% here and still render wrong —
  that is what `ui-loop.md` and `module-review.md` stage 4 are for. This gate is
  upstream of them, not a replacement.
- **One project, ten pages.** Directionally strong, not a population estimate.

## Why the existing instruments did not catch it

| Instrument | Why it was silent |
|---|---|
| `mxcli check` / mxbuild | grammar, references, BSON. Blind to CSS and layout. |
| `design-audit.js` rung 6 | computes the wireframe-vs-page delta at `design-audit.js:606` and **deliberately does not score it** — "scoring on that turns every page red for no defect". Correct about raw class delta; the fix is to score regions and shell with chrome excluded. Also runs `info`, non-gating, in `verify-module.sh:572`. |
| `page-audit.js` | holds `wireframe/region-coverage`. **No caller anywhere in the repo** — not `verify-module.sh`, not any skill. |
| `ui-preflight-pages.md` | mandatory, followed, and terminates in an unscored prose block. |
| `ui-loop.md` | right cadence, no threshold, no artifact, nothing checks it ran. |
| Gate: UI | per *module*. On this app that is once, after every page exists. |

## Proposal

1. **Score the shell first.** Page column, layout/nav shell, H1 scaffold — three checks,
   file-only, no app. They caught 100% of pages here and are the highest-leverage rows.
2. **Give the pre-flight a denominator.** Replace the prose block with a scored
   report: regions, action labels, classes, shell — each `ok/n`, chrome excluded by
   construction.
3. **Make it a build-plan row, not a rule.** `brd-to-build-plan.md` already argues this
   for `BRIEF` rows: *"a rule stated in a skill file is followed by whoever loaded the
   skill; a numbered row is followed by whoever works the plan."* Every page `BUILD`
   row gets a paired `HARNESS` row with a `State` cell.
4. **Ratchet, do not cliff.** Measured baseline is 32%. An 80% gate dropped on a
   project at 32% fails everything on day one. Use the per-rule ratchet shape
   `project-bin/lint-gate.sh` already implements.
5. **A dedicated page agent — last.** `mdl-agent` routes 47 skill rows (19 always-on)
   on Sonnet, holds no Write tool, and never sees a page. Splitting it is likely right,
   but an agent with a better prompt and no scorer just relocates the guessing. Build
   the measurement, get the baseline, then decide.
