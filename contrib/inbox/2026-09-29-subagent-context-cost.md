# Sub-agents start with ~2x the context they need: that, not call count, makes toolkit builds cost more per row

**From:** ProcureFlow cook-off (mxcli + toolkit arm vs Studio Pro MCP arm, same frozen spec)
**Date:** 2026-09-29
**Kind:** process
**Field evidence:** Both arms' session transcripts measured with the same script (active minutes
and tokens per window, idle cut 10 min, one usage record per request); build window only.
**Proposed target:** `skills/agent-roles.md` (sub-agent dispatch), agent stubs under `agents/`,
`bin/init-project.sh` (settings it writes)

---

## Finding (measured)

| Build window (6 h cap) | Toolkit arm | MCP arm |
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
2. **Sub-agents start heavy.** Every build/test sub-agent averaged 225–240k from its first
   call — it loads CLAUDE.md, the always-on skills and the spec before doing anything. This
   part survives the autocompact fix and is why the toolkit arm still costs ~$1.7–1.9 per row
   vs ~$1.4–1.6 (at a 2x speed advantage).
3. **Parallel agents pay cache writes.** Each fresh sub-agent writes its own cache — 3x the
   MCP arm's cache-write spend. That is the price of the parallelism that bought the speed;
   it scales with (2).

Output tokens and effort level are not the driver: the cheaper arm produced 2.4x more output.

## Proposed improvements (hypotheses until re-measured)

- **Lean dispatch payload per sub-agent role.** The stub names the 2–4 skill files that role
  needs and inlines only the relevant section; it does not inherit the whole always-on set.
  Target: sub-agent mean context ≤ ~130k (the MCP arm's level).
- **Pass the slice, not the spec.** A build sub-agent gets its rows + the module's BRD, not
  the whole frozen spec.
- **Autocompact default in what `init-project.sh` writes** (or a preflight warning when a
  session runs with autocompact > 250k).
- **Measure it.** Add per-role mean-context-per-call to the time log so the next run shows
  whether the payload diet worked (same script, same windows).

Done = on the next comparable run, calls/row unchanged, mean context per call roughly halved,
cost per row at or below the MCP arm, min/row unchanged.
