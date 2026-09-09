# BRD Capability Grouping — Proposal (confirm at checkpoint-brd / CAC-2)

The BRD mapper rolled technical-layer packages up into business capabilities using each
item's own source-path evidence. **This is a proposal**: confirm or correct it at the BRD
checkpoint. Corrections go in `config.json` → `"brdGrouping": { "<rawModule>": "<capability>" }`
(overrides win over path evidence), then re-run Phase 3. Mendix module boundaries are still
decided at Stage 3 (`modularize-domain.md`).

**Result: 3 raw package name(s) → 3 capability BRD(s).**

| Raw module (package) | → Capability BRD(s) | Items |
|---|---|---|
| dashboards.js | *(unchanged: 4)* | 4 |
| frontend | *(unchanged: 1)* | 1 |
| schema | *(unchanged: 4)* | 4 |

No grouping was applied (no technical-layer packages detected, or no path evidence).
