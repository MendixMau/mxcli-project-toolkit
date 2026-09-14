# Small-Project Tier — The Same Gates, a Bounded Artifact Set

**Applies to:** any entry mode. **Triggers** at the Stage 0 sign-off (CAC-1) when the inventory
is at or under the bounds below, or whenever the user says the app is small — a three-screen
tool, one module, a form and a list.

**Purpose:** Stop a small app paying the full pipeline's fixed artifact cost. Measured in the
token-path A/B (`process/token-path-ab-2026-09-09.md`, conclusion 5): a **3-file corpus produced
30k words of Stage 0–4 artifacts; a 200-file corpus produced 44–58k.** The artifact *set* was
the cost, not the source. This tier keeps every gate and every interview and bounds what each
gate reads — it never removes a thing a gate reads.

**Upstream:** the Stage 0 inventory (`bin/source-sufficiency.sh init`, or the intake for
greenfield) and CAC-1 (`checkpoints/checkpoint-scope.md` Q3).
**Downstream:** every stage's §1b checklist carries the caps below as its denominators;
`bin/gate-check.sh` reads the waiver lines this tier tells you to write.

---

## Declared, never inferred

Three bounds, **all three must hold**, read off the Stage 0 inventory and stated in the
checkpoint with the counts as evidence:

| Bound | Small |
|---|---|
| Modules intended | 1 (2 at most, and then only when one is a pure lookup/reference module) |
| Screens | ≤ 8 |
| Use cases (BRD sections) | ≤ 25 |

Recorded as one register line, CONFIRMED by the user at CAC-1:

```
Size tier: small — 1 module, 6 screens, 14 use cases (CAC-1, CONFIRMED)
```

No line, no tier — a session must not decide a project is small because its sources folder
looks thin (CLAUDE.md: never infer a project's position; the same rule for its size). A project
that outgrows a bound mid-build changes the line at the next gate and says so in that
checkpoint's close-out; from then on the full form applies to the stages still ahead.

## What does not change

Every gate and its verdict. Every interview and register line. The source ledger. BRD
validation to Clean. **One wireframe per screen.** Grants co-located with what they protect.
The coverage ledger. The module-review LOOK. The Stage 3 and 4 ✋ decisions. Exec discipline.

## The caps

Word and row caps are denominators the §1b checklist reposts, so a reviewer can fail them.
Exceeding one is not a defect **when the close-out says why in one line** — a cap is a default,
not a ceiling. Exceeding one silently is the defect.

| Stage | Artifact | Full pipeline | Small tier |
|---|---|---|---|
| 0 | `assessment.md` + `triage.md` | two files, six assessment areas | **one file** — `triage.md` with a six-row "Assessment" table, one line per area; no `assessment.md` |
| 1 | knowledge base | `KB.md` + `extraction-report.html` | `KB.md` ≤ 1,500 words; the extraction report only if an extractor ran (docs-ready rule: else `--waive 1` with the reason) |
| 2 | BRDs | one per feature area | **one** `F001-<app>.brd.json` for the whole app (≤ 25 use cases), one agent writes it, so `facts-lock.sh` is skipped — nothing to freeze when there is one writer; `bin/brd-report.sh` still runs; validation still to Clean |
| 3 | `module-design.html` | sign-off page | **waived** — the one boundary is a Decisions row: `Waived artifact module-design: small tier — single module, boundary is decision D-n` |
| 3 | `blueprint.md` | Steps 2–6 | ≤ 600 words: module list, one layer diagram, role model, integrations (or "none"). `blueprint.html` still rendered — the gate checks it and its freshness |
| 3 | `fit-gap.md` | | ≤ 20 rows |
| 3 | `design-system.html` + `ds.css` | full showcase | tokens plus **only the components the wireframes use** — name them, one section each, ≤ 300 words of prose |
| 3 | wireframes | one per screen | unchanged: one per screen, ≤ 8 by the bound |
| 3 | opt-in artifacts | offered at close-out | not offered unless CAC-3's Q3 flags workflow or integration scope |
| 4 | `build-plan.md` | | ≤ 12 numbered scripts; §9 regression ledger stays |
| 4 | module brief | one per module | one |
| 4 | coverage ledger | per module | the single-file form `architecture/coverage-ledger.md` (`coverage-ledger.md` → "Where the ledger lives") |
| 4 | `build-plan.html` | derived render | **waived**: `Waived artifact build-plan-html: small tier — status read from build-plan.md` |
| 5 | `improvement-register.html` | render | **waived**: `Waived artifact improvement-register-html: small tier — the .md is the register` |
| 5–6 | everything else | | unchanged: `exec.sh`, gate-agent after every exec, one ui-review, journeys, `report.json` |

## Writing the waivers

Each `Waived artifact <id>: <reason>` is a register line (`PROJECT.md`, under `## Toolkit
position` or wherever a reader would read it — never inside an HTML comment, which
`artifact-check.sh` skips on purpose). `bin/gate-check.sh --waive` takes stages and per-module
passes, not artifacts, so these three lines are written by hand, once, at CAC-1, with the tier
line. A waived artifact reports WAIVED with its reason on every run — never PRESENT, never
silent.

## The wrong answers this replaces

- *Six assessment areas, each a page, for an app with one entity.* The full form is right for a
  200-file source; on a 3-file one it is 30k words the reader must get through to find the
  three decisions in it.
- *Skipping Stage 3 "because it is small".* Module boundaries, grants and the script order are
  decided at Stages 3–4 and nowhere else (runbook → docs-ready row). Small means one module
  and a short blueprint, not no blueprint.
- *Declaring the tier from the sources folder.* A thin folder is a scope question, not a size
  answer — ask it (CAC-1 Q3), record it, then apply the caps.
