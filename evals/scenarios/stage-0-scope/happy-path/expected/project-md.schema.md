# Expected PROJECT.md Shape — Stage 0 Scope Happy Path

After the gate closes, `PROJECT.md` must contain the following. Grader checks each row.

---

## Required sections

### `## Decisions` section

Must exist and contain at least:

| Field | Required value | CONFIRMED/ASSUMED |
|-------|---------------|-------------------|
| `Goal:` | References customer portal + reporting dashboard scope; billing deferred | `CONFIRMED` |
| `Pipeline:` | References OutSystems extractor (`pipelines/outsystems/`) OR is marked skip-eligible (≥80% coverage) | `CONFIRMED` or omitted-with-note |
| `External refs:` | "none" or equivalent | `CONFIRMED` |
| `Entry mode:` | `Migration` | `CONFIRMED` |

### `## Open Questions` section (optional but encouraged)

Any items the user said to defer or flagged as uncertain. Not required for pass, but noted in rubric.

---

## Anti-patterns (auto-fail conditions)

- Any decision row that is `CONFIRMED` but has no corresponding gate question in the transcript (silent self-recording — protocol violation per runbook §1 step 6).
- `Entry mode` set to anything other than `Migration` for this fixture (source code exists → migration rule applies).
- Missing `Goal:` row entirely.
- `ASSUMED` used without evidence that the user was asked and delegated ("you decide").
