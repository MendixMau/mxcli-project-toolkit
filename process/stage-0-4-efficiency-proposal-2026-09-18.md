# Stages P–4 efficiency — proposal (2026-09-18)

**Status:** proposal, draft PR. Nothing here is adopted until merged and field-run.
**Prompt:** users report that Stages 0–4 (triage → build plan) burn too many tokens and too much
wall-clock, and asked for more parallel fan-out and for cheap-vs-capable model choice by purpose
and importance ("cheap is not always the answer").
**Evidence base:** `process/token-path-ab-2026-09-09.md` (A/B, three corpora), the routing table
(`bin/lib/skill-routing.tsv`, `bin/render-routing.sh --check`), the runbook's own dispatch table
(`skills/conversion-runbook.md` §1c, lines 344–384), and a per-file word census of the skills a
Stage P–4 session reads. Figures that were measured are in tables; figures that were estimated say so.

---

## TLDR

1. **The early stages are not inherently expensive. The reading is.** A Stage P–4 session on
   master loads the 78,124-word baseline pack before it does anything, plus 8–23k words of
   stage skills, plus 13,459 words of runbook when it ignores "read your stage section only".
   Fan-out work in Stages 1–4 is already specified (§1c) — the wins left are in *what each
   session reads* and *whether the specified fan-out and model tiers actually land*.
2. **The model tiering was designed and never delivered.** `agents/*.md` pin `opus`/`sonnet`
   (since 2026-07-31); the templates people copy from `skills/agent-roles.md` say
   `model: inherit` six times, and `bin/sync-project.sh` never refreshes a completed stub — so a
   project scaffolded before the pinning runs every subagent on the main session's model forever.
   One-line fix per template, one refresh rule in sync. This is the cheapest win in the document.
3. **Fan-out has a ceiling, not a floor, and Stages P and 0 stay in the main session by
   design.** Their cost is interview stops and reading, not missing parallelism. Enforcing
   fan-out there would add coordination cost for nothing; enforcing it in Stages 1–4 is a gate
   check, not a new mechanism.
4. **Measure before the next round.** The last estimate of a run's token cost missed by ~14×
   (tool output and grading were not counted). A `bin/token-burn.sh` that sums the session
   transcripts by model and by day is the instrument; until it exists, every "this cut cost"
   claim is a word count, not a token count.
5. **Proportionality is the real overspend.** A 3-file corpus produced ~30k words of artifacts
   because every stage emits its full artifact set. A small-project tier that names waivable
   artifacts (register lines, not new code) is the largest remaining lever and needs no
   new instrument.

---

## 1. What was measured

### 1.1 A/B on the token path (2026-09-09, Sonnet, Stages P–2, one corpus)

| Arm | $ | Wall-clock | Requirement recall | Rule recall | Contradictions |
|---|---|---|---|---|---|
| A — master as shipped | 7.94 | 19m04 | 54% | 47% | 0 |
| B — branch (`html-to-md.sh`, span reads) | 5.45 | 12m46 | 81% | 87% | 1 |
| C — docs-ready fast path | 5.42 | 12m04 | 94% | 100% | 3 |

Wave 2 (Haiku, P–4, three corpora): $0.64–$1.03, 4.3–8.2 min, one *hollow* run — CONFIRMED
rows with no artifacts behind them and a stage header that never advanced. That is the Haiku
failure mode: cheap, fast, and confidently empty when nothing mechanical checks the output.

Take-aways the A/B already drew, unchanged here: converting HTML sources to markdown is the
single biggest win (9× fewer bytes, recall 54→81–94%); the docs-ready path is opt-in; none of
the cuts changed correctness; the remaining overspend is proportionality.

### 1.2 Fixed reading load per stage (words, master `2d9a0a2` unless noted)

| Load | Words | Note |
|---|---|---|
| Baseline pack (every session) | 78,124 | `render-routing.sh --check`, budget 80,000 |
| Runbook, whole file | 13,459 | line 62 says read §1b + own stage only; gate-check prints the span |
| Runbook, §1b + one stage section | ~1,200–2,500 | what a compliant session reads |
| On-demand stage skills, Stage P | 11.7k | A/B census |
| Stage 0 | 23.0k | `source-triage` 3,791 is the bulk |
| Stage 1 | 17.3k | |
| Stage 2 | 8.4k | |
| Stage 3 | 23.1k | `architecture-blueprint` 4,822 + `design-artifacts` 3,593 |
| Stage 4 | 18.4k | `brd-to-build-plan` 7,132 |
| Bundled mxcli "read first" skills | 21,279 | on top of baseline for any MDL-writing session |
| Example project `CLAUDE.local.md` | 1,072 | anti-drift section alone 477 |

PR #99 (stage-sliced baseline) already cuts the *pack* per stage — its branch measures
P 27.9k · 0 29.2k · 1–3 25.5k · 4 34.2k · 5 72.6k · 6 40.0k · 7 26.3k words. Stages P–4 drop
to roughly a third of today's fixed load once it merges. This proposal assumes #99.

**Unreconciled:** three baseline figures exist — 78,124 (this check, master today), 77,774
(master + one skill cut, earlier this week) and 72,001 (a worker's report at `5c3378f`). The
first is the only one run by hand on a known commit; treat the others as unverified until
`render-routing.sh --check` is rerun on the commit each claims.

### 1.3 Where estimates went wrong

The freshness experiment planned ~8k tokens per run and spent ~115k per run — tool output,
file reads and grading were not counted. The nine-way Opus-class fan-out earlier that week spent
$118 and hit the rate limit before finishing. Both are the same lesson: **pilot one rep, measure
it, then fan out.**

---

## 2. What already exists — do not rebuild it

`conversion-runbook.md` §1c (added 2026-09-14) is the dispatch table. It already says, per
stage, what leaves the main session, the batch size, the model, and the mechanical check that
gates the result back in:

| Stage | Unit | Batch | Model | Check |
|---|---|---|---|---|
| 1 | one document → KB extract | ≤6 in flight | Sonnet | `source-ledger.sh check` |
| 1 | image descriptions | 5–8 per agent | Haiku | `images-to-md.sh --check` |
| 2 | one module → BRD | all parallel | Sonnet | `facts-lock.sh` |
| 3a | modularize → blueprint → fit-gap | sequential | Opus | gate |
| 3b | design system + wireframes | ≤8 screens/agent | Sonnet | gate |
| 4 | one module → brief | parallel | Sonnet | gate |
| 4 | build plan | first, sequential | Opus | gate |
| P, 0, 7 | — | main session | — | — |

It also states the Haiku rule (reads whose output is mechanically checked only) and the
fallback for harnesses without subagents (one unit per turn, fresh session per batch).
What it does **not** have is anything that notices when a project ignores it. Nothing in
`gate-check.sh` asks whether Stage 2 BRDs were produced in parallel or serially, on which
model, or at what cost.

---

## 3. The gaps

| # | Gap | Evidence | Effect |
|---|---|---|---|
| G1 | Model tiers don't reach projects | `agent-roles.md` lines 108, 149, 178, 243, 266, 291 = `model: inherit`; `agents/*.md` line 4 = `opus`/`sonnet`; `sync-project.sh` refreshes pure stubs only (lines 17–18, 72–84) | Every subagent runs on the main model; Haiku/Sonnet dispatch in §1c is a suggestion |
| G2 | Whole-runbook reads | 13,459 words vs ~2k span; the span is printed only by gate-check, i.e. *after* the stage started | +11k words per session that reads it whole; measured cause of slow Stages 1–4 |
| G3 | No cost signal | no instrument reads the session transcripts; word counts stand in for tokens | 14× estimate miss; "people are complaining" has no number behind it |
| G4 | Fan-out unenforced | §1c is prose; gate-check has no row for it | serial Stage 2 on a 12-module project is 12× the wall-clock §1c promises |
| G5 | Artifacts scale with the process, not the input | 3-file corpus → ~30k artifact words | the actual "too much" users feel on small projects |
| G6 | Interview stops in P/0 | design: ask, then stop | not a token cost; a wall-clock cost with no fix except fewer, better-batched questions |
| G7 | Bundled-skill tax | 21,279 words of mxcli "read first" skills | Stage 5+ mostly; listed so nobody attributes it to Stages 0–4 |

---

## 4. Proposals, cheapest-per-win first

Each row: the change, the files, the mechanical check that proves it landed, the risk.

### P1 — Deliver the model tiers (G1) — ~1 hour, no new instrument

- `skills/agent-roles.md`: the six templates say the tier `agents/*.md` already pins
  (`architect-agent: opus`; `ba/gate/mdl/review/test-agent: sonnet`), with one sentence on
  why (judgement vs mechanically-checked work).
- `bin/sync-project.sh`: on a completed (non-stub) agent file whose `model:` line differs from
  the toolkit's, **warn** with the diff — never rewrite a completed agent (the stub rule stays).
  Optional `--pin-models` to apply.
- Check: `bin/sync-project.sh` on the example project prints six warnings today and zero after
  `--pin-models`. Field run on one real project, cited in the commit.
- Risk: none to content; projects that deliberately chose `inherit` see one warning line.

### P2 — Read the span, not the file (G2) — ~half a day

- The session-start ritual (`init-project.sh` lines 282–300, `sync-project.sh` 526–543)
  already runs `status.sh --brief`. Make `status.sh --brief` print the same
  `Read for this gate: …(lines A–B)` line gate-check prints at the end — so the span is known
  *before* the stage starts, not after.
- `checkpoints/checkpoint-*.md` and the agent stubs cite the span form, never "read the runbook".
- Check: grep — no baseline/routing row or stub says "read `conversion-runbook.md`" without a
  section. `render-routing.sh --check` stays green.
- Risk: a session that needs another stage's section still has to go find it; the runbook's
  line-62 rule already accepts that.

### P3 — Enforce §1c at the gate (G4) — one day

- `gate-check.sh` stages 1–4 read a **dispatch ledger**: one register line per fan-out batch
  (`Dispatch <stage>: <n> units, <model>, <check>, <date>`), written by the main session when it
  spawns the batch. Missing line → `PENDING` with the §1c row printed; `Dispatch <stage>:
  single-session, reason: <harness>` is the legal opt-out for harnesses without subagents.
- This is the obligation-check pattern (`bin/lib/obligations.tsv`) applied to §1c, not a new
  mechanism: a pass nobody performed reports out loud instead of green-by-absence.
- Check: fixture with the line present / absent / opted-out; field run on one project.
- Risk: one more register line per stage. Worth it — it is also the input P4 needs to attribute
  cost to a batch.

### P4 — Measure (G3) — one day, then it pays for every later decision

`bin/token-burn.sh <project-root>`:

- Streams every `~/.claude/projects/<slug>/*.jsonl` and `…/subagents/agent-*.jsonl` for the
  project's cwd slug; sums `input_tokens`, `cache_creation_input_tokens`,
  `cache_read_input_tokens`, `output_tokens` grouped by `message.model`; cache-read shown
  separately (it is the cheap column, and the one that proves whether the pack is being reused
  or re-read).
- Per-day rollup from message timestamps; best-effort stage attribution from dated register
  rows in `PROJECT.md` and, once P3 lands, from `Dispatch` lines — with an explicit `UNMAPPED`
  bucket and a caveat column. `NOT AVAILABLE` (exit 0, one line) when there is no transcript
  tree: desktop chat, Cowork, Copilot and Cursor sessions leave none this tool can read.
- Field-proof rules (CLAUDE.md → "Shipping an instrument"): golden input is a captured
  transcript fixture with asserted sums, not a hand-written one; slug discovery probed on
  single-tree and `app/` layouts; `jq`/`python3` presence probed, Git Bash considered; the
  commit cites the real project it ran on and the number it printed; the producer of the
  artifact it reads (the Claude Code harness) is named in its header, with the harnesses that
  produce nothing listed.
- Reporting: `status.sh --brief` gains one line — `Tokens this stage: <n>k (<model split>)`
  — so people see the burn while it happens, which is what was asked for. Thresholds come
  later, from data, never from this document.

### P5 — Small-project tier (G5) — half a day of skill text, no code

- `source-triage.md` gains a tier rule: below a corpus size (proposal: ≤5 source files or
  ≤20 pages, to be calibrated by P4), the triage names the artifacts the project will
  **waive** — `Waived artifact <id>: small-project tier` register lines — from a fixed list
  (per-module briefs collapse into the build plan; wireframes only for screens with rules;
  fit-gap only where marketplace modules are in play).
- `artifact-check.sh` already honours those lines; nothing to build.
- Check: the A/B's 3-file corpus rerun under the tier, artifact words counted.
- Risk: a project that starts small and grows must un-waive; the register line's reason makes
  that visible.

### P6 — Batch the interview stops (G6) — text only

- `interview-protocol.md`: in Stages P and 0, questions are asked **in one turn per gate**,
  never one question per turn; the 2+1 checkpoint format already does this at the six
  transitions — extend the "collect, then ask once" rule to intake questions.
- Not a token change; it is the wall-clock people feel in Stage 0.

### P7 — Pilot-one-rep rule (rate limits) — text only, `agent-roles.md` + §1c

- Before any fan-out wider than 3, run one unit, read its cost with P4, then dispatch the
  rest. The $118 fan-out that never finished is the incident.

### P8 — Bundled-skill tax (G7) — out of scope here, noted

- 21k words of mxcli-bundled skills load for MDL sessions; that is Stage 5+, and it is
  upstream's file set. A pointer in the Stage 5 stub to "read the one skill the script needs"
  is the toolkit's only lever. Separate PR.

---

## 5. Model choice by purpose and importance

The rule the user asked for, made explicit. §1c already encodes rows of it; this is the
principle behind the rows, so new units get placed consistently.

| Work | Model | Why | Guard |
|---|---|---|---|
| Reads with a mechanical check (image descriptions, ledger marks, format renders) | Haiku | 78% key recall, 1-in-15 misread on small text — acceptable only when a checker catches the miss | the check is mandatory, not optional |
| Extraction, drafting, rendering with a schema (KB extracts, BRDs, briefs, wireframes) | Sonnet | full recall in the A/B at ~⅓ the cost of Opus; output is checked by `facts-lock`/validators | validator runs before the result re-enters |
| Judgement with no checker: module boundaries, blueprint, fit-gap, build-plan ordering, gate verdicts, interview recommendations | Opus | a wrong cut here is paid for in every later stage | one unit at a time; never batched |
| Main session (questions, verdicts, writes, register) | whatever the user runs | it is the user's seat | — |

"Cheap is not always the answer" is the third row. The hollow Haiku run is the first row
without its guard.

---

## 6. Per-stage plan, P–4

| Stage | In main session | Fan out | Reading budget (after #99) | Biggest lever |
|---|---|---|---|---|
| P | all (intake, kickoff) | none | 27.9k pack + 11.7k | P2 span read; P6 one-turn intake |
| 0 | triage verdict, scope, questions | file inventory only (Haiku, `source-sufficiency.sh init` checks it) | 29.2k + 23.0k | P5 tier decision made *here*; `html-to-md.sh` on any HTML source |
| 1 | ledger, checklist | docs → KB (Sonnet ≤6), images (Haiku 5–8) | 25.5k + 17.3k | P3 dispatch line; P7 pilot one doc |
| 2 | facts lock, gate | modules → BRDs (Sonnet, all) | 25.5k + 8.4k | P3; validators already exist |
| 3 | interview, gate | 3a Opus sequential ∥ 3b Sonnet ≤8 screens | 25.5k + 23.1k | run 3a and 3b concurrently — they are independent until fit-gap |
| 4 | gate, register | briefs (Sonnet, parallel) after build plan (Opus) | 34.2k + 18.4k | P5 collapses briefs on small projects |

A worker is mapping the stage sections against §1c for units the table misses; that map
folds into this section when it lands and is marked as such.

---

## 7. Order and what we deliberately do not do

Order: **P4 (measure) and P1 (tiers) first**, same week; P2 and P6 with them (text); P3 and
P5 once P4 has one project's numbers to calibrate against. P7 is a paragraph. P8 is a separate
PR.

Not proposed:

- **No automatic model switching, no per-token budgets in code.** Thresholds without data are
  the unfalsifiable-checklist defect. P4 produces the data; a later PR may propose numbers.
- **No new fan-out for Stages P and 0.** They are interview stages by design.
- **No rewrite of §1c or the stage matrix.** Text that was baseline-tested is not churned on a
  hunch (CLAUDE.md authoring rule 2).
- **No full-suite reruns to prove any of this.** Each item names its scoped check.

## 8. Open questions for the maintainer

1. Is `--pin-models` in P1 acceptable, or should sync only ever warn on a completed agent?
2. P3's register line: one line per batch, or one per stage with a count? (One per batch is
   what P4 needs for attribution.)
3. P5's corpus threshold — set it now as a placeholder, or wait for P4's first numbers?
