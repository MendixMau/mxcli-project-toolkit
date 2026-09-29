# Parallel build: mxbuild collisions, a per-script gate that grows with the model, undercounted output

**From:** benchmark cook-off (mxcli + toolkit arm vs Studio Pro MCP arm, same frozen spec)
**Date:** 2026-09-29
**Kind:** process
**Field evidence:** toolkit arm BUILD-LOG.md and METRICS.md: 11 of 96 script applies failed (11.5%); 2 were "gate could not run: mxbuild exit 1" from concurrent builds (rows 16, fix-39; row 119 was a glyph error, not a collision); per-script apply grew from 22–30 s (slice 1) to 55–65 s (slice 2) as the mxbuild gate grew.
**Proposed target:** `bin/exec.sh` (or its project-bin wrapper), `skills/iterative-build-loop.md`

---

Parallel drafting is the toolkit arm's speed advantage (2.6 vs 5.5 min/row; equal calls per
row), so keep it and remove its friction:
- **Lock/queue mxbuild** across agents (exec.sh lock file or scratch-clone check). [measured: 2 collisions]
- **Batch the gate**: one mxbuild per 3–5 consecutive clean scripts; per-script only after a
  failure. [hypothesis: 10–20 min wall time saved in slice 2]
- **Usage measurement**: streamed transcript lines carry partial usage; the measure script must
  take each message's final usage record — sub-agent output was undercounted in both arms,
  which briefly produced a false "MCP arm writes 2.4x more output" conclusion.
