# Sub-agents start with ~2x the context they need: that, not call count, makes toolkit builds cost more per row

**From:** a field comparison (mxcli + toolkit build vs a Studio Pro MCP build, same frozen spec)
**Date:** 2026-09-29
**Kind:** process
**Field evidence:** Both builds' session transcripts measured with the same script (active minutes
and tokens per window, idle cut 10 min, one usage record per request); build window only.
**Proposed target:** `skills/agent-roles.md` (sub-agent dispatch), agent stubs under `agents/`,
`bin/init-project.sh` (settings it writes)

---

## Finding (measured)

| Build window (6 h cap) | Toolkit build | MCP build |
|---|---|---|
| API calls | 3,630 | 1,839 |
| Rows built | 123 | ~64 |
| **Calls per row** | **29.5** | **28.7** |
| Mean context per call | ~265k | ~128k |
| Cache reads | 962M | 235M |
| Cache writes | 13.5M | 4.3M |
| Output | 0.46M | 1.11M |
| Minutes per row | 2.6 | 5.5 |

Calls per row are the same. The whole cost gap is **context re-read per call**:

1. **Lead session: autocompact was accidentally 1M.** Lead averaged 363–466k per call. Fixable
   by configuration; re-estimated at 250k autocompact the build drops ~$270–310 → ~$214–237.
2. **Sub-agents start heavy and never compact.** Estimated load before the first write is
   ~145–215k (chars/4): stub with 81-row routing table ~8k, CLAUDE.md + CLAUDE.local.md ~5k,
   always-routed skills ~95k (conversion-runbook.md alone 23.5k), whole build-plan + BRD
   20–80k. The MCP build starts at ~1–3k. 34 of 38 sub-agents peaked at 250–580k without
   compacting, so the 225–265k per-call average is a growing context. This part survives
   the autocompact fix and is why the toolkit build still costs ~$1.7–1.9 per row
   vs ~$1.4–1.6 (at a 2x speed advantage).
3. **Parallel agents pay cache writes.** Each fresh sub-agent writes its own cache — 3x the
   MCP build's cache-write spend. That is the price of the parallelism that bought the speed;
   it scales with (2).

Output tokens and effort level are not the driver: lead-to-lead output per call is equal
(~630 vs ~610 tokens). The recorded sub-agent output is undercounted in both builds
(streamed usage records; `measure-usage.py` should read each message's final usage record).

## Proposed improvements (hypotheses until re-measured)

- **Lean dispatch payload per sub-agent role.** The stub names the 2–4 skill files that role
  needs and inlines only the relevant section; it does not inherit the whole always-on set.
  Target: sub-agent mean context ≤ ~130k (the MCP build's level).
- **Pass the slice, not the spec.** A build sub-agent gets its rows + the module's BRD, not
  the whole frozen spec.
- **Autocompact default in what `init-project.sh` writes** (or a preflight warning when a
  session runs with autocompact > 250k).
- **Cap agent bundles / add autocompact for sub-agents** so a long-running drafter compacts
  instead of growing to 500k+.
- **Measure it.** Add per-role mean-context-per-call to the time log so the next run shows
  whether the payload diet worked (same script, same windows).

Done = on the next comparable run, calls/row unchanged, mean context per call roughly halved,
cost per row at or below the MCP build, min/row unchanged.
