# Stages 0–4 load ~40–70k of toolkit text before the task starts — trim the default load

**From:** a field comparison (mxcli + toolkit build vs a Studio Pro MCP build, same frozen spec)
**Date:** 2026-09-29
**Kind:** process
**Field evidence:** chars/4 measurement of every baseline row in `bin/lib/skill-routing.tsv` (29 Sep 2026); field-build sub-agents loaded ~145–215k before their first write (see 2026-09-29-subagent-context-cost.md). Stage 0–4 figures are measured file sizes, not transcript-measured loads.
**Proposed target:** `bin/lib/skill-routing.tsv` + `bin/render-routing.sh`, `skills/conversion-runbook.md`, agent stubs under `agents/`

---

The owner's direction: the pipeline is expensive; standard skill/context loads must be limited
when not needed, especially in Stages 0–4/5. Every token loaded at session start is re-read on
every call (cache read), so a 50k default load across ~300 calls is ~15M cache-read tokens per
session.

## What loads today (measured, chars/4)

| Load | Size | When |
|---|---|---|
| `skills/conversion-runbook.md` | ~23k | every session, read in full ("before producing any stage artifact") |
| `skills/interview-protocol.md` | ~5k | every stage |
| `CLAUDE.md` + `CLAUDE.local.md` routing table | ~6k + table | every session |
| stage "-" baselines (skills-over-scripts, degrade-to-judgement, retesting-learned-rules, tool-output-is-not-ground-truth) | ~7k | every stage |
| Stage 0–2 script rows (`source-sufficiency.sh` 10k, `source-ledger.sh` 9k, `facts-lock.sh` 3k, …) | ~25k if read | routed as rows; an agent that *reads* a script instead of running it pays its full size |
| agent stub routing table (81 rows in the mdl stub) | ~8k | every sub-agent |
| Stage 5 baselines | ~75k | build only — but field-build sub-agents loaded ~95k of skills, so the stage slice is not what agents actually honour (hypothesis) |

Total baseline rows: ~163k if everything is read.

## Proposed (hypotheses until re-measured)

1. **Split the runbook**: a ~4–5k spine (stage matrix, gates, entry modes, "read §N for your
   stage") plus per-stage sections read only for the current stage. Biggest single saving
   (~18k per session, every stage).
2. **Run scripts, don't read them**: routing rows for `bin/*.sh` say "run with --help"; the
   rendered table marks them as tools, not reading.
3. **Render stub routing per agent *and* stage**: a stage-5 mdl sub-agent gets only its
   stage-5 build/mdl rows, not the 81-row table.
4. **Pass the slice, not the spec**: stage and build agents get the module/rows they work on,
   not the whole build plan or BRD set.
5. **Budget line in the checklist**: each stage's Live Checklist opens with "context at start:
   Nk" so the load is visible; target ≤ 25k for Stages 0–4 before any source is read.

Done = a Stage 0–4 session starts at ≤ 25k toolkit text (measured from a transcript's first
call), with no gate regressions (`render-routing.sh --check`, stage fixtures).
