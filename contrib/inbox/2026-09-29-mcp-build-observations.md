# What a Studio Pro MCP build teaches (and needs) — for the toolkit and for the MCP owners

**From:** a field comparison (mxcli + toolkit build vs a Studio Pro MCP build, same frozen spec)
**Date:** 2026-09-29
**Kind:** learning
**Field evidence:** The MCP build's METRICS/RETRO-LOG/TIME-LOG and the comparison tool's own tool journal: 406 screen-driving calls (22% of build calls) clustered on screens the MCP cannot write; those rows ran 12–21 min each vs 2.6–3.5 min/row for domain and logic; the person did 9 manual steps.
**Proposed target:** `skills/upstream-feedback.md` (route the MCP items), `skills/iterative-build-loop.md` (the two adoptable habits)

---

Adoptable by the toolkit:
- **Save-then-check**: the MCP build lost time to checks against a stale disk copy (229 errors
  hidden until a real save). The toolkit's exec gate already checks the saved file — keep it
  that way, and say so in the build loop.
- **Visual check per page during the build**, not after the person complains (the The MCP build's UI
  work started only after "the UI looks quite bad").

For the MCP/comparison-tool owners (not toolkit work):
- Write support for security, user roles, role home pages, snippets, scheduled events,
  import/export mappings, published REST, pluggable-widget property schema.
- Atomic writes with fixed batch order (a reverse-order batch miswired 16 associations).
- Auto-flush/save before mx check; reload instead of full restart (23 restarts).
- Flag a missing end-of-parallel-path element in consistency check.
- Parallel drafting sub-agents with the lead as the single writer.
- Testing: commit scripts and results, add unit tests, make timers and ERP failure testable.
